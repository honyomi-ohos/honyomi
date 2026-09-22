import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Http } from '../net/Http';
import { SourceRegistry } from '../source/Source';

// 远程图片落盘缓存（对齐 Mihon Coil 图片管线中"按源请求头"的部分）
// 源声明了 imageRequestHeaders 时走宿主 http 管线并缓存到本地，否则交由系统 Image 直连
export class ImageCache {
  private static dir: string = '';
  private static inflight: Map<string, Promise<string>> = new Map();

  static init(context: common.UIAbilityContext): void {
    ImageCache.dir = `${context.cacheDir}/image_file_cache`;
    if (!fs.accessSync(ImageCache.dir)) {
      fs.mkdirSync(ImageCache.dir, true);
    }
  }

  // 解析展示地址：http(s) 且源需要请求头 → file:// 本地缓存；其余原样返回
  static async resolve(url: string, sourceKey: string, pageUrl?: string): Promise<string> {
    if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
      return url;
    }
    const source = SourceRegistry.get(sourceKey);
    if (source === undefined) {
      return url;
    }
    const headers = source.imageRequestHeaders();
    if (headers === undefined) {
      return url;
    }
    const path = await ImageCache.cachedPath(url);
    if (fs.accessSync(path)) {
      return `file://${path}`;
    }
    const pending = ImageCache.inflight.get(url);
    if (pending !== undefined) {
      return pending;
    }
    const task = ImageCache.fetch(url, ImageCache.withReferer(headers, pageUrl), path);
    ImageCache.inflight.set(url, task);
    try {
      return await task;
    } finally {
      ImageCache.inflight.delete(url);
    }
  }

  // 防盗链：源请求头未声明 Referer 时回退为章节页地址
  private static withReferer(headers: Record<string, string>, pageUrl?: string): Record<string, string> {
    if (pageUrl === undefined || pageUrl === '') {
      return headers;
    }
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === 'referer') {
        return headers;
      }
    }
    const merged: Record<string, string> = {};
    for (let i = 0; i < keys.length; i++) {
      merged[keys[i]] = headers[keys[i]];
    }
    merged['Referer'] = pageUrl;
    return merged;
  }

  // 缓存目录占用字节数
  static size(): number {
    if (ImageCache.dir === '' || !fs.accessSync(ImageCache.dir)) {
      return 0;
    }
    let total = 0;
    const names = fs.listFileSync(ImageCache.dir);
    for (let i = 0; i < names.length; i++) {
      const stat = fs.statSync(`${ImageCache.dir}/${names[i]}`);
      total += stat.size;
    }
    return total;
  }

  // 清空缓存目录，返回清除的字节数
  static clearAll(): number {
    const total = ImageCache.size();
    if (ImageCache.dir !== '' && fs.accessSync(ImageCache.dir)) {
      const names = fs.listFileSync(ImageCache.dir);
      for (let i = 0; i < names.length; i++) {
        fs.unlinkSync(`${ImageCache.dir}/${names[i]}`);
      }
    }
    return total;
  }

  // ---------------- 内部实现 ----------------

  private static async fetch(url: string, headers: Record<string, string>, path: string): Promise<string> {
    const buffer = await Http.getBuffer(url, headers);
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    try {
      fs.writeSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    return `file://${path}`;
  }

  private static async cachedPath(url: string): Promise<string> {
    const hash = await ImageCache.md5(url);
    return `${ImageCache.dir}/${hash}${ImageCache.extOf(url)}`;
  }

  private static extOf(url: string): string {
    const q = url.indexOf('?');
    const path = q >= 0 ? url.substring(0, q) : url;
    const dot = path.lastIndexOf('.');
    if (dot >= 0 && path.length - dot <= 6) {
      return path.substring(dot);
    }
    return '.jpg';
  }

  private static async md5(text: string): Promise<string> {
    const md = cryptoFramework.createMd('MD5');
    const input: cryptoFramework.DataBlob = { data: new util.TextEncoder().encodeInto(text) };
    await md.update(input);
    const output = await md.digest();
    let hex = '';
    for (let i = 0; i < output.data.length; i++) {
      const b = output.data[i];
      hex += b < 16 ? `0${b.toString(16)}` : b.toString(16);
    }
    return hex;
  }
}
