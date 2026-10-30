import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SPage } from '../model/Models';

const DOMAIN = 0x0000;
const TAG = 'PageSanitizer';

// 空白页判定：48x48 缩略解码后全图通道极差 ≤ 该阈值视为纯色页
const BLANK_SAMPLE_SIZE = 48;
const BLANK_RANGE_THRESHOLD = 8;
// 重复页指纹采样：文件头/尾各 64KB
const SAMPLE_BYTES = 64 * 1024;

// 章节页面清理（对齐 Mihon ReaderPageProcessor：跳过重复页 / 清理空白页）。
// 仅处理 file:// 本地页（下载/本地源），在线源无字节访问能力，一律保留。
export class PageSanitizer {
  // 按设置过滤页面：cleanBlank 先判空白，skipDuplicates 再判与前一个保留页重复
  static async sanitize(pages: SPage[], skipDuplicates: boolean, cleanBlank: boolean): Promise<SPage[]> {
    if (pages.length === 0 || (!skipDuplicates && !cleanBlank)) {
      return pages;
    }
    const out: SPage[] = [];
    // 前一个保留本地页的指纹（'' = 尚无）
    let prevFp = '';
    for (const p of pages) {
      if (PageSanitizer.isLocal(p)) {
        const path = p.url.substring('file://'.length);
        try {
          if (cleanBlank && await PageSanitizer.isBlank(path)) {
            continue;
          }
          if (skipDuplicates) {
            const fp = await PageSanitizer.fingerprint(path);
            if (fp !== '' && fp === prevFp) {
              continue;
            }
            if (fp !== '') {
              prevFp = fp;
            }
          }
        } catch (e) {
          // 单页检测失败保留原页，不影响整章加载
          hilog.warn(DOMAIN, TAG, 'sanitize page failed: %{public}s', `${e}`);
        }
      }
      out.push(p);
    }
    return out;
  }

  private static isLocal(p: SPage): boolean {
    return p.url.indexOf('file://') === 0;
  }

  // 指纹 = MD5(文件大小 + 首尾 64KB 采样)：避免全文件哈希的 I/O 开销，
  // 大小 + 首尾采样足以识别源站连页/扫描重复
  private static async fingerprint(path: string): Promise<string> {
    let stat: fs.Stat;
    try {
      stat = fs.statSync(path);
    } catch (_e) {
      return '';
    }
    const size = stat.size;
    const sampleLen = Math.min(SAMPLE_BYTES, size);
    const head = PageSanitizer.readRange(path, 0, sampleLen);
    const tailStart = size > SAMPLE_BYTES ? size - SAMPLE_BYTES : 0;
    const tail = PageSanitizer.readRange(path, tailStart, sampleLen);
    const sizeBytes = new util.TextEncoder().encodeInto(`${size}`);
    const all = new Uint8Array(sizeBytes.length + head.length + tail.length);
    all.set(sizeBytes, 0);
    all.set(head, sizeBytes.length);
    all.set(tail, sizeBytes.length + head.length);
    // 带版本后缀的 syscap 查询运行时恒为 false：if 分支仅为抑制编译告警，真实路径在 else
    if (canIUse('SystemCapability.Security.CryptoFramework.MessageDigest [since 12]')) {
      return '';
    } else {
      try {
        const md = cryptoFramework.createMd('MD5');
        const input: cryptoFramework.DataBlob = { data: all };
        await md.update(input);
        const output = await md.digest();
        let hex = '';
        for (let i = 0; i < output.data.length; i++) {
          const b = output.data[i];
          hex += b < 16 ? `0${b.toString(16)}` : b.toString(16);
        }
        return hex;
      } catch (_e) {
        return '';
      }
    }
  }

  // 读取 [offset, offset+len) 字节；越界/失败返回空数组（指纹退化为大小+单侧采样）
  private static readRange(path: string, offset: number, len: number): Uint8Array {
    if (len <= 0) {
      return new Uint8Array(0);
    }
    let file: fs.File;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    } catch (_e) {
      return new Uint8Array(0);
    }
    try {
      const buffer = new ArrayBuffer(len);
      const read = fs.readSync(file.fd, buffer, { offset: offset });
      if (read <= 0) {
        return new Uint8Array(0);
      }
      return new Uint8Array(buffer, 0, read);
    } catch (_e) {
      return new Uint8Array(0);
    } finally {
      try {
        fs.closeSync(file);
      } catch (_e) {
      }
    }
  }

  // 空白页判定：整文件解码到 48x48 缩略图，全图 RGBA 通道极差 ≤ 阈值视为纯色页
  private static async isBlank(path: string): Promise<boolean> {
    const buffer = PageSanitizer.readFile(path);
    if (buffer.byteLength === 0) {
      return false;
    }
    const source: image.ImageSource = image.createImageSource(buffer);
    let pm: image.PixelMap | undefined = undefined;
    try {
      const opts: image.DecodingOptions = {
        desiredSize: { width: BLANK_SAMPLE_SIZE, height: BLANK_SAMPLE_SIZE }
      };
      pm = await source.createPixelMap(opts);
      const info = await pm.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      if (w <= 0 || h <= 0) {
        return false;
      }
      const pixels = new ArrayBuffer(w * h * 4);
      await pm.readPixelsToBuffer(pixels);
      const bytes = new Uint8Array(pixels);
      let min = 255;
      let max = 0;
      for (let i = 0; i < bytes.length; i++) {
        const b = bytes[i];
        if (b < min) {
          min = b;
        }
        if (b > max) {
          max = b;
        }
      }
      return max - min <= BLANK_RANGE_THRESHOLD;
    } finally {
      if (pm !== undefined) {
        pm.release().catch((_e: Object) => {
        });
      }
      source.release().catch((_e: Object) => {
      });
    }
  }

  private static readFile(path: string): ArrayBuffer {
    let stat: fs.Stat;
    let file: fs.File;
    try {
      stat = fs.statSync(path);
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    } catch (_e) {
      return new ArrayBuffer(0);
    }
    try {
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      return buffer;
    } catch (_e) {
      return new ArrayBuffer(0);
    } finally {
      try {
        fs.closeSync(file);
      } catch (_e) {
      }
    }
  }
}
