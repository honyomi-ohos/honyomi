import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Http } from '../net/Http';

// HLS 主播放列表的一个可播放变体（多码率条目）
class HlsVariant {
  url: string = '';
  bandwidth: number = 0;
}

// HLS 媒体分片：URL + AES-128 加密信息（密钥地址与显式 IV）+ 媒体序号
class HlsSegment {
  url: string = '';
  seq: number = 0;
  // 空串 = 未加密
  keyUri: string = '';
  // EXT-X-KEY 显式 IV；undefined = 按媒体序号推导
  keyIv: Uint8Array | undefined = undefined;
}

// HLS 媒体播放列表解析结果
class HlsMediaPlaylist {
  segments: HlsSegment[] = [];
  // fMP4 初始化段地址（EXT-X-MAP）；空串表示 MPEG-TS 流
  initUrl: string = '';
  // 无 EXT-X-ENDLIST 视为直播/事件流，不支持下载
  live: boolean = true;
}

// TS 分片 PES 扫描结果：首个带 PTS 的 PES 原始值与输出时间线上的最大 PTS
class TsPesScan {
  firstPts: number = -1;
  maxPts: number = -1;
}

// MPEG-TS 时间轴缝合器：源播放列表常把多段独立编码的视频（各自 PTS 从 ~0 起）拼进
// 一个列表，裸合并出的 TS 在分片边界出现 PTS 倒退，解复用器据此把文件判坏（时长与
// 可播范围只剩第一段）。本类逐分片检测首个 PES 的 PTS 回跳，为该分片起计算统一偏移
// 并原位重写全部 PTS/DTS/PCR，把多条时间轴缝成一条连续时间线（各段 PID 映射一致，
// 已实测校验，无需重映射 PID/流类型）。
class TsTimelineFixer {
  // 当前分片起统一叠加的 90kHz tick 偏移（33bit 环内非负）
  private curOffset: number = 0;
  // 已输出时间线上最近的最大 PES PTS；-1 表示尚未见过任何 PES
  private lastOutPts: number = -1;

  // 处理一个 TS 分片（原位改写 buf）。无 PES 的分片直接跳过。
  processSegment(buf: Uint8Array): void {
    const scan: TsPesScan = TsTimelineFixer.scanPes(buf, this.curOffset, false);
    if (scan.firstPts < 0) {
      return;
    }
    // 首个 PES 相对已输出时间线倒退超过 1s：判定为新时间轴块，块首紧接上一块结尾
    // （留 40ms 间隙），此后所有分片叠加新偏移
    if (this.lastOutPts >= 0 && scan.firstPts + this.curOffset < this.lastOutPts - 90000) {
      this.curOffset = this.lastOutPts + 3600 - scan.firstPts;
      hilog.info(0x0001, 'HlsDownload', 'ts timeline stitched: new block, offset=%{public}d ticks (%{public}ds)',
        this.curOffset, Math.round(this.curOffset / 90000));
    }
    if (this.curOffset === 0) {
      // 尚无任何时间轴断裂：重写是恒等变换，只推进 lastOutPts
      this.lastOutPts = scan.maxPts;
    } else {
      this.lastOutPts = TsTimelineFixer.scanPes(buf, this.curOffset, true).maxPts;
    }
  }

  // 扫描（rewrite=true 时原位重写）分片内全部 188 字节 TS 包：
  // 视频/音频 PES 的 PTS/DTS 与自适应字段中的 PCR 基值按 offset 平移（33bit 取模）
  private static scanPes(buf: Uint8Array, offset: number, rewrite: boolean): TsPesScan {
    const out: TsPesScan = new TsPesScan();
    let i = 0;
    while (i + 188 <= buf.length) {
      if (buf[i] !== 0x47) {
        i += 1;
        continue;
      }
      const flags: number = buf[i + 1];
      const pusi: boolean = (flags & 0x40) !== 0;
      const afc: number = (buf[i + 3] >> 4) & 3;
      let p: number = i + 4;
      if (afc === 2 || afc === 3) {
        const afl: number = buf[i + 4];
        if (rewrite && afl >= 7 && (buf[i + 5] & 0x10) !== 0) {
          TsTimelineFixer.shiftPcr(buf, i + 6, offset);
        }
        p += 1 + afl;
      }
      if (pusi && (afc === 1 || afc === 3) && p + 14 < i + 188 &&
        buf[p] === 0 && buf[p + 1] === 0 && buf[p + 2] === 1) {
        const sid: number = buf[p + 3];
        if ((sid >= 0xE0 && sid <= 0xEF) || (sid >= 0xC0 && sid <= 0xDF)) {
          const ptsFlags: number = (buf[p + 7] >> 6) & 3;
          if (ptsFlags !== 0) {
            const raw: number = TsTimelineFixer.readPts(buf, p + 9);
            if (out.firstPts < 0) {
              out.firstPts = raw;
            }
            if (rewrite) {
              TsTimelineFixer.writePts(buf, p + 9, raw + offset);
              if (ptsFlags === 3 && p + 19 < i + 188) {
                TsTimelineFixer.writePts(buf, p + 14, TsTimelineFixer.readPts(buf, p + 14) + offset);
              }
            }
            if (raw + offset > out.maxPts) {
              out.maxPts = raw + offset;
            }
          }
        }
      }
      i += 188;
    }
    return out;
  }

  // PTS/DTS 33bit 编码读取（5 字节，含 marker 位）
  private static readPts(b: Uint8Array, p: number): number {
    return (b[p] >> 1 & 7) * 1073741824 + b[p + 1] * 4194304 +
      (b[p + 2] >> 1 & 0x7F) * 32768 + b[p + 3] * 128 + (b[p + 4] >> 1);
  }

  private static writePts(b: Uint8Array, p: number, v: number): void {
    let t = v % 8589934592;
    if (t < 0) {
      t += 8589934592;
    }
    b[p] = 0x20 | ((Math.floor(t / 1073741824) & 7) << 1) | 1;
    b[p + 1] = Math.floor(t / 4194304) & 0xFF;
    b[p + 2] = ((Math.floor(t / 32768) & 0x7F) << 1) | 1;
    b[p + 3] = Math.floor(t / 128) & 0xFF;
    b[p + 4] = ((t & 0x7F) << 1) | 1;
  }

  // PCR 基值（33bit）平移，9bit 扩展保留
  private static shiftPcr(b: Uint8Array, p: number, offset: number): void {
    const base: number = b[p] * 33554432 + b[p + 1] * 131072 +
      b[p + 2] * 512 + b[p + 3] * 2 + (b[p + 4] >> 7);
    let nb = (base + offset) % 8589934592;
    if (nb < 0) {
      nb += 8589934592;
    }
    const ext: number = ((b[p + 4] & 0x7F) << 8) | b[p + 5];
    b[p] = Math.floor(nb / 33554432) & 0xFF;
    b[p + 1] = Math.floor(nb / 131072) & 0xFF;
    b[p + 2] = Math.floor(nb / 512) & 0xFF;
    b[p + 3] = Math.floor(nb / 2) & 0xFF;
    b[p + 4] = ((nb & 1) << 7) | ((ext >> 8) & 0x7F);
    b[p + 5] = ext & 0xFF;
  }
}

// HLS(m3u8) 下载器：解析 m3u8（含主列表多码率选择）→ 逐分片请求（带源请求头）
// → AES-128-CBC 解密 → 按序合并。fMP4 流（含 EXT-X-MAP）输出 video.mp4，
// MPEG-TS 流输出 video.ts（AVPlayer 支持 mpeg2ts 播放）。
// 不支持直播型流（无 EXT-X-ENDLIST）、SAMPLE-AES 与字节范围分片。
export class HlsDownloader {
  // 分片并发窗口：窗口内并发抓取、按序落盘，兼顾速度与顺序保证
  private static readonly CONCURRENCY: number = 3;

  // 下载一条 m3u8 流到 dir：返回最终文件路径。
  // onProgress 按分片计数回调（done/total）；shouldStop 返回 'cancelled'/'blocked' 中断下载
  static async download(url: string, headers: Record<string, string>, dir: string,
    onProgress: (done: number, total: number) => void,
    shouldStop: () => string): Promise<string> {
    let playlistUrl = url;
    let text: string = await Http.get(playlistUrl, headers);
    HlsDownloader.checkStop(shouldStop);
    if (text === '') {
      throw new Error('hls_parse_failed');
    }
    if (text.charCodeAt(0) === 0xFEFF) {
      text = text.substring(1);
    }
    // 主播放列表（多码率）：取带宽最高的变体后解析其媒体列表
    if (text.indexOf('#EXT-X-STREAM-INF') >= 0) {
      const variants: HlsVariant[] = HlsDownloader.parseMaster(text, playlistUrl);
      if (variants.length === 0) {
        throw new Error('hls_parse_failed');
      }
      let best: HlsVariant = variants[0];
      for (const v of variants) {
        if (v.bandwidth > best.bandwidth) {
          best = v;
        }
      }
      hilog.info(0x0001, 'HlsDownload', 'master playlist: %{public}d variants, pick bandwidth=%{public}d',
        variants.length, best.bandwidth);
      playlistUrl = best.url;
      text = await Http.get(playlistUrl, headers);
      HlsDownloader.checkStop(shouldStop);
      if (text === '') {
        throw new Error('hls_parse_failed');
      }
      if (text.charCodeAt(0) === 0xFEFF) {
        text = text.substring(1);
      }
    }
    const media: HlsMediaPlaylist = HlsDownloader.parseMedia(text, playlistUrl);
    if (media.live) {
      throw new Error('hls_live_unsupported');
    }
    if (media.segments.length === 0) {
      throw new Error('hls_no_segments');
    }
    const isFmp4 = media.initUrl !== '';
    const outPath = `${dir}/${isFmp4 ? 'video.mp4' : 'video.ts'}`;
    const tmpPath = `${outPath}.tmp`;
    const total = media.segments.length;
    onProgress(0, total);
    hilog.info(0x0001, 'HlsDownload', 'start: %{public}d segments, %{public}s', total, isFmp4 ? 'fmp4' : 'ts');
    const keyCache = new Map<string, Uint8Array>();
    // MPEG-TS：逐分片缝合多时间轴（详见 TsTimelineFixer）；fMP4 时间线在 trun 盒内，不适用
    const fixer: TsTimelineFixer = new TsTimelineFixer();
    // 大文件顺序写入官方推荐 fs.createStream 流式接口（FAQ faqs-local-file-manager-77）：
    // 流内部维护写入位置、每块自动推进。fd 版 writeSync 在部分设备上位置不随写入推进，
    // 且传 options.offset 追加会被判非法参数直接抛错，均不可靠
    let stream: fileIo.Stream | undefined = undefined;
    try {
      stream = fileIo.createStreamSync(tmpPath, 'w');
      // fMP4：初始化段（ftyp/moov）在最前
      if (isFmp4) {
        HlsDownloader.checkStop(shouldStop);
        const initBuf: ArrayBuffer = await Http.getBuffer(media.initUrl, headers);
        HlsDownloader.writeBuffer(stream, initBuf);
      }
      let next = 0;
      let done = 0;
      const window: Array<Promise<ArrayBuffer>> = [];
      while (true) {
        HlsDownloader.checkStop(shouldStop);
        while (next < total && window.length < HlsDownloader.CONCURRENCY) {
          const seg = media.segments[next];
          next += 1;
          const pending = HlsDownloader.fetchSegment(seg, headers, keyCache);
          // 并发窗口内其余分片失败时不产生未处理的 Promise 拒绝
          pending.catch((_e: Error): void => {
          });
          window.push(pending);
        }
        const head: Promise<ArrayBuffer> | undefined = window.shift();
        if (head === undefined) {
          break;
        }
        const buf: ArrayBuffer = await head;
        HlsDownloader.checkStop(shouldStop);
        if (!isFmp4) {
          fixer.processSegment(new Uint8Array(buf));
        }
        HlsDownloader.writeBuffer(stream, buf);
        done += 1;
        onProgress(done, total);
      }
    } catch (e) {
      if (stream !== undefined) {
        try {
          stream.closeSync();
        } catch (_ce) {
        }
      }
      try {
        if (fileIo.accessSync(tmpPath)) {
          fileIo.unlinkSync(tmpPath);
        }
      } catch (_ue) {
      }
      throw e as Error;
    }
    try {
      stream.closeSync();
    } catch (e) {
      throw new Error(`write video file failed: ${e}`);
    }
    try {
      if (fileIo.accessSync(outPath)) {
        fileIo.unlinkSync(outPath);
      }
      fileIo.renameSync(tmpPath, outPath);
    } catch (e) {
      throw new Error(`write video file failed: ${e}`);
    }
    hilog.info(0x0001, 'HlsDownload', 'done: %{public}s', outPath);
    return outPath;
  }

  // ---------------- 播放列表解析 ----------------

  // 主播放列表 → 变体列表（BANDWIDTH + 变体媒体列表地址）
  private static parseMaster(text: string, baseUrl: string): HlsVariant[] {
    const out: HlsVariant[] = [];
    const lines = text.split(/\r?\n/);
    let pendingBandwidth = -1;
    for (const raw of lines) {
      const line = raw.trim();
      if (line === '') {
        continue;
      }
      if (line.charAt(0) === '#') {
        if (line.indexOf('#EXT-X-STREAM-INF:') === 0) {
          const attrs = HlsDownloader.parseAttrs(line);
          const bw = attrs['BANDWIDTH'];
          pendingBandwidth = bw !== undefined && !Number.isNaN(parseInt(bw, 10)) ? parseInt(bw, 10) : 0;
        }
        continue;
      }
      if (pendingBandwidth >= 0) {
        const variant = new HlsVariant();
        variant.url = HlsDownloader.resolveUrl(baseUrl, line);
        variant.bandwidth = pendingBandwidth;
        out.push(variant);
        pendingBandwidth = -1;
      }
    }
    return out;
  }

  // 媒体播放列表 → 分片序列 + fMP4 初始化段 + 直播判定
  private static parseMedia(text: string, baseUrl: string): HlsMediaPlaylist {
    const playlist = new HlsMediaPlaylist();
    const lines = text.split(/\r?\n/);
    let mediaSeq = 0;
    let keyUri = '';
    let keyIv: Uint8Array | undefined = undefined;
    let index = 0;
    for (const raw of lines) {
      const line = raw.trim();
      if (line === '') {
        continue;
      }
      if (line.charAt(0) !== '#') {
        const segment = new HlsSegment();
        segment.url = HlsDownloader.resolveUrl(baseUrl, line);
        segment.seq = mediaSeq + index;
        segment.keyUri = keyUri;
        segment.keyIv = keyIv;
        playlist.segments.push(segment);
        index += 1;
        continue;
      }
      if (line.indexOf('#EXT-X-MEDIA-SEQUENCE:') === 0) {
        const seq = parseInt(line.substring('#EXT-X-MEDIA-SEQUENCE:'.length), 10);
        if (!Number.isNaN(seq) && seq >= 0) {
          mediaSeq = seq;
        }
      } else if (line.indexOf('#EXT-X-ENDLIST') === 0) {
        playlist.live = false;
      } else if (line.indexOf('#EXT-X-KEY:') === 0) {
        const attrs = HlsDownloader.parseAttrs(line);
        const method = HlsDownloader.attrStr(attrs, 'METHOD');
        if (method === 'NONE') {
          keyUri = '';
          keyIv = undefined;
        } else if (method === 'AES-128') {
          const uri = HlsDownloader.attrStr(attrs, 'URI');
          if (uri === '') {
            throw new Error('hls_unsupported_encryption');
          }
          keyUri = HlsDownloader.resolveUrl(baseUrl, uri);
          const ivHex = HlsDownloader.attrStr(attrs, 'IV');
          if (ivHex !== '') {
            keyIv = HlsDownloader.parseIvHex(ivHex);
            if (keyIv === undefined) {
              throw new Error('hls_unsupported_encryption');
            }
          } else {
            keyIv = undefined;
          }
        } else {
          // SAMPLE-AES 等其他加密方式
          throw new Error('hls_unsupported_encryption');
        }
      } else if (line.indexOf('#EXT-X-MAP:') === 0) {
        const attrs = HlsDownloader.parseAttrs(line);
        const uri = HlsDownloader.attrStr(attrs, 'URI');
        if (uri === '') {
          continue;
        }
        if (HlsDownloader.attrStr(attrs, 'KEY') !== '' ||
          HlsDownloader.attrStr(attrs, 'BYTERANGE') !== '') {
          throw new Error('hls_unsupported_encryption');
        }
        playlist.initUrl = HlsDownloader.resolveUrl(baseUrl, uri);
      } else if (line.indexOf('#EXT-X-BYTERANGE:') === 0) {
        throw new Error('hls_parse_failed');
      }
    }
    return playlist;
  }

  // ---------------- 分片获取与解密 ----------------

  // 通过流顺序写入整块缓冲：字节数不足视为写入失败（磁盘满/沙箱异常）
  private static writeBuffer(stream: fileIo.Stream, buf: ArrayBuffer): void {
    const written = stream.writeSync(buf);
    if (written !== buf.byteLength) {
      throw new Error('hls_write_failed');
    }
  }

  private static async fetchSegment(segment: HlsSegment, headers: Record<string, string>,
    keyCache: Map<string, Uint8Array>): Promise<ArrayBuffer> {
    const data: ArrayBuffer = await Http.getBuffer(segment.url, headers);
    if (segment.keyUri === '') {
      return data;
    }
    const key: Uint8Array = await HlsDownloader.loadKey(segment.keyUri, headers, keyCache);
    const iv: Uint8Array = segment.keyIv !== undefined ? segment.keyIv : HlsDownloader.seqIv(segment.seq);
    return HlsDownloader.aes128Decrypt(data, key, iv);
  }

  private static async loadKey(keyUrl: string, headers: Record<string, string>,
    keyCache: Map<string, Uint8Array>): Promise<Uint8Array> {
    const cached = keyCache.get(keyUrl);
    if (cached !== undefined) {
      return cached;
    }
    const buf: ArrayBuffer = await Http.getBuffer(keyUrl, headers);
    const key = new Uint8Array(buf);
    if (key.length !== 16) {
      throw new Error('hls_unsupported_encryption');
    }
    keyCache.set(keyUrl, key);
    return key;
  }

  // AES-128-CBC 解密（NoPadding 解出原始块，再按 PKCS7 启发式裁尾，
  // 兼容带 PKCS7 填充与零填充两种封装）
  private static aes128Decrypt(data: ArrayBuffer, key: Uint8Array, iv: Uint8Array): ArrayBuffer {
    try {
      const keyGen = cryptoFramework.createSymKeyGenerator('AES128');
      const symKey = keyGen.convertKeySync({ data: key });
      const cipher = cryptoFramework.createCipher('AES128|CBC|NoPadding');
      const params: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: { data: iv },
      };
      cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
      const plain = cipher.doFinalSync({ data: new Uint8Array(data) });
      const stripped = HlsDownloader.stripPkcs7(plain.data);
      return stripped.buffer;
    } catch (e) {
      hilog.warn(0x0001, 'HlsDownload', 'aes decrypt failed: %{public}s', `${e}`);
      throw new Error('hls_decrypt_failed');
    }
  }

  // PKCS7 裁尾：末字节 1..16 且末尾等值才视为填充剥离，否则原样返回
  private static stripPkcs7(bytes: Uint8Array): Uint8Array {
    if (bytes.length === 0) {
      return bytes;
    }
    const pad = bytes[bytes.length - 1];
    if (pad < 1 || pad > 16 || pad > bytes.length) {
      return bytes;
    }
    for (let i = bytes.length - pad; i < bytes.length; i++) {
      if (bytes[i] !== pad) {
        return bytes;
      }
    }
    return bytes.slice(0, bytes.length - pad);
  }

  // 无显式 IV 时按媒体序号推导：16 字节，低 8 字节大端序
  private static seqIv(seq: number): Uint8Array {
    const iv = new Uint8Array(16);
    let v = seq;
    for (let i = 15; i >= 8; i--) {
      iv[i] = v % 256;
      v = Math.floor(v / 256);
    }
    return iv;
  }

  private static parseIvHex(hex: string): Uint8Array | undefined {
    let h = hex.trim();
    if (h.indexOf('0x') === 0 || h.indexOf('0X') === 0) {
      h = h.substring(2);
    }
    if (h.length !== 32) {
      return undefined;
    }
    const out = new Uint8Array(16);
    for (let i = 0; i < 16; i++) {
      const byte = parseInt(h.substring(i * 2, i * 2 + 2), 16);
      if (Number.isNaN(byte)) {
        return undefined;
      }
      out[i] = byte;
    }
    return out;
  }

  // ---------------- 工具 ----------------

  private static checkStop(shouldStop: () => string): void {
    const state = shouldStop();
    if (state === 'cancelled') {
      throw new Error('download_cancelled');
    }
    if (state === 'blocked') {
      throw new Error('network_blocked');
    }
  }

  // 标签属性列表解析：逗号分隔（引号内逗号不拆分），键名统一大写
  private static parseAttrs(line: string): Record<string, string> {
    const out: Record<string, string> = {};
    const colon = line.indexOf(':');
    if (colon < 0) {
      return out;
    }
    const inner = line.substring(colon + 1);
    let name = '';
    let value = '';
    let inValue = false;
    let inQuote = false;
    for (let i = 0; i < inner.length; i++) {
      const c = inner.charAt(i);
      if (!inValue) {
        if (c === '=') {
          inValue = true;
        } else if (c !== ' ') {
          name += c;
        }
      } else if (inQuote) {
        if (c !== '"') {
          value += c;
        } else {
          inQuote = false;
        }
      } else if (c === '"') {
        inQuote = true;
      } else if (c === ',') {
        if (name !== '') {
          out[name.toUpperCase()] = value;
        }
        name = '';
        value = '';
        inValue = false;
      } else {
        value += c;
      }
    }
    if (inValue && name !== '') {
      out[name.toUpperCase()] = value;
    }
    return out;
  }

  private static attrStr(attrs: Record<string, string>, name: string): string {
    const v = attrs[name];
    return v !== undefined && typeof v === 'string' ? v : '';
  }

  // 相对地址解析：绝对/协议相对/根相对/目录相对四种形态
  private static resolveUrl(base: string, uri: string): string {
    const t = uri.trim();
    if (t === '') {
      return '';
    }
    if (t.indexOf('https://') === 0 || t.indexOf('http://') === 0) {
      return t;
    }
    if (t.indexOf('//') === 0) {
      return `${base.indexOf('https://') === 0 ? 'https:' : 'http:'}${t}`;
    }
    if (t.charAt(0) === '/') {
      let start = 0;
      if (base.indexOf('https://') === 0) {
        start = 8;
      } else if (base.indexOf('http://') === 0) {
        start = 7;
      }
      const slash = base.indexOf('/', start);
      return slash >= 0 ? base.substring(0, slash) + t : base + t;
    }
    let b = base;
    const hash = b.indexOf('#');
    if (hash >= 0) {
      b = b.substring(0, hash);
    }
    const query = b.indexOf('?');
    if (query >= 0) {
      b = b.substring(0, query);
    }
    const slash = b.lastIndexOf('/');
    const dir = slash >= 0 ? b.substring(0, slash + 1) : `${b}/`;
    return dir + t;
  }
}
