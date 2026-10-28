import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hidebug } from '@kit.PerformanceAnalysisKit';
import { ImageCache } from './ImageCache';
import { Http } from '../net/Http';

interface StripCacheEntry {
  pm: image.PixelMap;
  bytes: number;
}

// 条漫阅读图片管线（对齐 Mihon Coil 管线的内存层）：
// 1. 防盗链字节获取：复用 ImageCache 磁盘缓存（带源声明的 Referer/Cookie/UA 请求头），
//    未声明请求头的源直连取回
// 2. 字节 -> PixelMap 解码（超宽/超高图按上限等比缩放解码，限制单页内存）
// 3. LRU 内存缓存：按字节预算（MAX_CACHE_BYTES）驻留，超出自动 release() 回收；
//    条漫长图单张可达数十 MB，必须以字节而非张数计量，否则 OOM
export class StripImagePipeline {
  private static cache: Map<string, StripCacheEntry> = new Map();
  private static inflight: Map<string, Promise<image.PixelMap>> = new Map();
  // 已被 release 的 url：解码完成后不再入缓存（防"复活"）
  private static released: Set<string> = new Set<string>();
  private static totalBytes: number = 0;
  // 内存预算：设备总内存的 15%，上限 256MB、下限 64MB（中低端设备避免触发 LMK）；
  // 超大条漫章节由 LRU 按字节淘汰
  private static readonly MAX_CACHE_BYTES: number = StripImagePipeline.computeBudget();
  // 单张解码宽度上限（px）
  private static readonly MAX_DECODE_WIDTH: number = 1440;
  // 单张解码总像素上限：条漫是"窄而极高"的长图，仅限宽不够
  private static readonly MAX_DECODE_PIXELS: number = 16000000; // ≈64MB RGBA

  static async load(url: string, sourceKey: string, pageUrl: string = ''): Promise<image.PixelMap> {
    const hit = StripImagePipeline.cache.get(url);
    if (hit !== undefined) {
      StripImagePipeline.touch(url);
      return hit.pm;
    }
    const pending = StripImagePipeline.inflight.get(url);
    if (pending !== undefined) {
      return pending;
    }
    // 新一轮加载视作新会话：清掉历史的 release 标记
    StripImagePipeline.released.delete(url);
    const task = StripImagePipeline.fetchAndDecode(url, sourceKey, pageUrl);
    StripImagePipeline.inflight.set(url, task);
    try {
      return await task;
    } finally {
      StripImagePipeline.inflight.delete(url);
    }
  }

  // OCR 专用解码：CoreVisionKit 文字识别仅接受 RGBA_8888；
  // 复用防盗链字节获取与解码上限，不入内存缓存，调用方负责 release()
  static async loadForOcr(url: string, sourceKey: string, pageUrl: string): Promise<image.PixelMap> {
    const buffer = await StripImagePipeline.fetchBytes(url, sourceKey, pageUrl);
    const source: image.ImageSource = image.createImageSource(buffer);
    try {
      const base = await StripImagePipeline.decodeOptions(source);
      const opts: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      if (base !== undefined && base.desiredSize !== undefined) {
        opts.desiredSize = base.desiredSize;
      }
      return await source.createPixelMap(opts);
    } finally {
      source.release().catch((_e: Object) => {
      });
    }
  }

  // 立即回收单张（如章节关闭）
  static release(url: string): void {
    // 同时撤销 inflight 任务并标记已释放：解码完成后不再 put 回缓存，防止条目"复活"
    StripImagePipeline.released.add(url);
    StripImagePipeline.inflight.delete(url);
    const entry = StripImagePipeline.cache.get(url);
    if (entry !== undefined) {
      StripImagePipeline.cache.delete(url);
      StripImagePipeline.totalBytes -= entry.bytes;
      if (StripImagePipeline.totalBytes < 0) {
        StripImagePipeline.totalBytes = 0;
      }
      entry.pm.release().catch((_e: Object) => {
      });
    }
  }

  static clearAll(): void {
    StripImagePipeline.cache.forEach((entry: StripCacheEntry) => {
      entry.pm.release().catch((_e: Object) => {
      });
    });
    StripImagePipeline.cache.clear();
    StripImagePipeline.totalBytes = 0;
  }

  static cachedCount(): number {
    return StripImagePipeline.cache.size;
  }

  static cachedBytes(): number {
    return StripImagePipeline.totalBytes;
  }

  // ---------------- 内部实现 ----------------

  // 按设备总内存计算预算：hidebug.getSystemMemInfo().totalMem（bigint，单位 KB），无权限要求；
  // 读取失败（低版本/syscap 缺失）回退 128MB 中等预算
  private static computeBudget(): number {
    try {
      const totalBytes: number = Number(hidebug.getSystemMemInfo().totalMem) * 1024;
      return Math.max(64 * 1024 * 1024, Math.min(256 * 1024 * 1024, Math.floor(totalBytes * 0.15)));
    } catch (_e) {
      return 128 * 1024 * 1024;
    }
  }

  private static async fetchAndDecode(url: string, sourceKey: string, pageUrl: string): Promise<image.PixelMap> {
    const buffer = await StripImagePipeline.fetchBytes(url, sourceKey, pageUrl);
    const source: image.ImageSource = image.createImageSource(buffer);
    try {
      const opts = await StripImagePipeline.decodeOptions(source);
      const pm = opts !== undefined ? await source.createPixelMap(opts) : await source.createPixelMap();
      // 解码期间被 release：不入缓存直接失败，调用方按加载错误兜底
      if (StripImagePipeline.released.has(url)) {
        pm.release().catch((_e: Object) => {
        });
        throw new Error('strip image released before decode finished');
      }
      const bytes = await StripImagePipeline.pixelBytes(pm);
      StripImagePipeline.put(url, pm, bytes);
      return pm;
    } finally {
      source.release().catch((_e: Object) => {
      });
    }
  }

  // 防盗链获取：经 ImageCache 管线（源请求头 + 磁盘缓存 + CookieJar）解析为可读地址
  private static async fetchBytes(url: string, sourceKey: string, pageUrl: string): Promise<ArrayBuffer> {
    const display = await ImageCache.resolve(url, sourceKey, pageUrl);
    if (display.indexOf('file://') === 0) {
      return StripImagePipeline.readFile(display.substring('file://'.length));
    }
    return Http.getBuffer(display, undefined);
  }

  private static readFile(path: string): ArrayBuffer {
    let stat: fs.Stat;
    let file: fs.File;
    try {
      stat = fs.statSync(path);
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    } catch (e) {
      throw new Error(`open strip image file failed: ${e}`);
    }
    try {
      const buffer = new ArrayBuffer(stat.size);
      try {
        fs.readSync(file.fd, buffer);
      } catch (e) {
        throw new Error(`read strip image file failed: ${e}`);
      }
      return buffer;
    } finally {
      try {
        fs.closeSync(file);
      } catch (e) {
      }
    }
  }

  // 等比缩放解码：同时限制宽度与总像素数，控制单页内存占用
  private static async decodeOptions(source: image.ImageSource): Promise<image.DecodingOptions | undefined> {
    try {
      const info = await source.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      if (w <= 0 || h <= 0) {
        return undefined;
      }
      const scale = Math.min(1,
        StripImagePipeline.MAX_DECODE_WIDTH / w,
        StripImagePipeline.MAX_DECODE_PIXELS / (w * h));
      if (scale >= 1) {
        return undefined;
      }
      const opts: image.DecodingOptions = {
        desiredSize: { width: Math.round(w * scale), height: Math.round(h * scale) },
      };
      return opts;
    } catch (_e) {
      return undefined;
    }
  }

  private static async pixelBytes(pm: image.PixelMap): Promise<number> {
    try {
      const info = await pm.getImageInfo();
      return info.size.width * info.size.height * 4;
    } catch (_e) {
      return 0;
    }
  }

  private static put(url: string, pm: image.PixelMap, bytes: number): void {
    const entry: StripCacheEntry = { pm: pm, bytes: bytes };
    StripImagePipeline.cache.set(url, entry);
    StripImagePipeline.totalBytes += bytes;
    while (StripImagePipeline.cache.size > 0) {
      const oldest = StripImagePipeline.cache.keys().next();
      if (oldest.done) {
        break;
      }
      // 新放入的条目不参与本轮淘汰（单张超预算时至少保留本张）
      if (oldest.value === url) {
        break;
      }
      if (StripImagePipeline.totalBytes <= StripImagePipeline.MAX_CACHE_BYTES) {
        break;
      }
      const victim = StripImagePipeline.cache.get(oldest.value);
      StripImagePipeline.cache.delete(oldest.value);
      if (victim !== undefined) {
        StripImagePipeline.totalBytes -= victim.bytes;
        if (StripImagePipeline.totalBytes < 0) {
          StripImagePipeline.totalBytes = 0;
        }
        // 仅从 Map 移除、延迟一拍 release：可能仍有页面正在渲染该 PixelMap，立即回收会闪灰/崩溃
        const pmToRelease: image.PixelMap = victim.pm;
        setTimeout((): void => {
          pmToRelease.release().catch((_e: Object) => {
          });
        }, 0);
      }
    }
  }

  private static touch(url: string): void {
    const entry = StripImagePipeline.cache.get(url);
    if (entry !== undefined) {
      StripImagePipeline.cache.delete(url);
      StripImagePipeline.cache.set(url, entry);
    }
  }
}
