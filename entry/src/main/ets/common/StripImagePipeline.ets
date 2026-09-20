import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ImageCache } from './ImageCache';
import { Http } from '../net/Http';

// 条漫阅读图片管线（对齐 Mihon Coil 管线的内存层）：
// 1. 防盗链字节获取：复用 ImageCache 磁盘缓存（带源声明的 Referer/Cookie/UA 请求头），
//    未声明请求头的源直连取回
// 2. 字节 -> PixelMap 解码（超宽图按上限等比缩放解码，控制内存）
// 3. LRU 内存缓存：近 MAX_CACHE 张驻留，超出自动 release() 回收
export class StripImagePipeline {
  private static cache: Map<string, image.PixelMap> = new Map();
  private static inflight: Map<string, Promise<image.PixelMap>> = new Map();
  private static readonly MAX_CACHE: number = 14;
  private static readonly MAX_DECODE_WIDTH: number = 1440;

  static async load(url: string, sourceKey: string): Promise<image.PixelMap> {
    const hit = StripImagePipeline.cache.get(url);
    if (hit !== undefined) {
      StripImagePipeline.touch(url);
      return hit;
    }
    const pending = StripImagePipeline.inflight.get(url);
    if (pending !== undefined) {
      return pending;
    }
    const task = StripImagePipeline.fetchAndDecode(url, sourceKey);
    StripImagePipeline.inflight.set(url, task);
    try {
      return await task;
    } finally {
      StripImagePipeline.inflight.delete(url);
    }
  }

  // 立即回收单张（如章节关闭）
  static release(url: string): void {
    const pm = StripImagePipeline.cache.get(url);
    if (pm !== undefined) {
      StripImagePipeline.cache.delete(url);
      pm.release().catch((_e: Object) => {
      });
    }
  }

  static clearAll(): void {
    StripImagePipeline.cache.forEach((pm: image.PixelMap) => {
      pm.release().catch((_e: Object) => {
      });
    });
    StripImagePipeline.cache.clear();
  }

  static cachedCount(): number {
    return StripImagePipeline.cache.size;
  }

  // ---------------- 内部实现 ----------------

  private static async fetchAndDecode(url: string, sourceKey: string): Promise<image.PixelMap> {
    const buffer = await StripImagePipeline.fetchBytes(url, sourceKey);
    const source: image.ImageSource = image.createImageSource(buffer);
    try {
      const opts = await StripImagePipeline.decodeOptions(source);
      const pm = opts !== undefined ? await source.createPixelMap(opts) : await source.createPixelMap();
      StripImagePipeline.put(url, pm);
      return pm;
    } finally {
      source.release().catch((_e: Object) => {
      });
    }
  }

  // 防盗链获取：经 ImageCache 管线（源请求头 + 磁盘缓存 + CookieJar）解析为可读地址
  private static async fetchBytes(url: string, sourceKey: string): Promise<ArrayBuffer> {
    const display = await ImageCache.resolve(url, sourceKey);
    if (display.indexOf('file://') === 0) {
      return StripImagePipeline.readFile(display.substring('file://'.length));
    }
    return Http.getBuffer(display, undefined);
  }

  private static readFile(path: string): ArrayBuffer {
    const stat = fs.statSync(path);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      return buffer;
    } finally {
      fs.closeSync(file);
    }
  }

  // 超宽图等比缩放解码，限制单页内存占用
  private static async decodeOptions(source: image.ImageSource): Promise<image.DecodingOptions | undefined> {
    try {
      const info = await source.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      if (w <= StripImagePipeline.MAX_DECODE_WIDTH || w <= 0 || h <= 0) {
        return undefined;
      }
      const scaledW = StripImagePipeline.MAX_DECODE_WIDTH;
      const scaledH = Math.round(h * scaledW / w);
      const opts: image.DecodingOptions = {
        desiredSize: { width: scaledW, height: scaledH },
      };
      return opts;
    } catch (_e) {
      return undefined;
    }
  }

  private static put(url: string, pm: image.PixelMap): void {
    StripImagePipeline.cache.set(url, pm);
    while (StripImagePipeline.cache.size > StripImagePipeline.MAX_CACHE) {
      const oldest = StripImagePipeline.cache.keys().next();
      if (oldest.done) {
        break;
      }
      const victim = StripImagePipeline.cache.get(oldest.value);
      StripImagePipeline.cache.delete(oldest.value);
      if (victim !== undefined) {
        victim.release().catch((_e: Object) => {
        });
      }
    }
  }

  private static touch(url: string): void {
    const pm = StripImagePipeline.cache.get(url);
    if (pm !== undefined) {
      StripImagePipeline.cache.delete(url);
      StripImagePipeline.cache.set(url, pm);
    }
  }
}
