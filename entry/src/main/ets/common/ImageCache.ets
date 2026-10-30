import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Http } from '../net/Http';
import { SourceRegistry } from '../source/Source';
import { PluginService } from '../data/PluginService';
import { AvifConverter } from './AvifConverter';

// 磁盘缓存文件元信息（超预算时按 mtime 淘汰最旧文件）
interface CacheFileMeta {
  name: string;
  mtime: number;
  size: number;
}

// 进程内解析结果（同一 URL 全部界面共享同一结果，杜绝状态分叉）
interface ResolvedEntry {
  value: string;
  ok: boolean;
  at: number;
}

// 远程图片落盘缓存（对齐 Mihon Coil 图片管线中"按源请求头"的部分）
// 源声明了 imageRequestHeaders 时走宿主 http 管线并缓存到本地，否则交由系统 Image 直连
export class ImageCache {
  // 磁盘缓存预算：超出后按 mtime 淘汰最旧文件直到回到预算内
  private static readonly MAX_DISK_BYTES: number = 256 * 1024 * 1024;
  private static dir: string = '';
  private static inflight: Map<string, Promise<string>> = new Map();
  // 进程内结果缓存：成功永久有效（文件被淘汰时自动失效重取），失败回退按 TTL 过期重试
  private static resolved: Map<string, ResolvedEntry> = new Map();
  private static readonly FAIL_TTL_MS: number = 60000;
  private static readonly MAX_MEMO: number = 512;
  private static seq: number = 0;
  // 目录累计字节数（init 时延后一拍统计一次，写入增量维护）
  private static totalBytes: number = 0;
  private static evicting: boolean = false;

  static init(context: common.Context): void {
    ImageCache.dir = `${context.cacheDir}/image_file_cache`;
    try {
      if (!fs.accessSync(ImageCache.dir)) {
        fs.mkdirSync(ImageCache.dir, true);
      }
    } catch (e) {
      throw new Error(`init cache dir failed: ${e}`);
    }
    // 启动路径不做同步全量统计：延后一拍在后台累计字节数，并清扫进程被杀残留的临时文件
    setTimeout((): void => {
      ImageCache.sweepTmp();
      ImageCache.rescanBytes();
    }, 0);
  }

  // 清理 1 小时前的 .tmp 残留（进程被杀时未及 rename 的下载半成品）
  private static sweepTmp(): void {
    try {
      const names = fs.listFileSync(ImageCache.dir);
      const now = Date.now();
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        if (name.indexOf('.tmp') !== name.length - '.tmp'.length) {
          continue;
        }
        const stat = fs.statSync(`${ImageCache.dir}/${name}`);
        const mtimeMs = stat.mtime * 1000;
        if (now - mtimeMs > 3600000) {
          fs.unlinkSync(`${ImageCache.dir}/${name}`);
        }
      }
    } catch (_e) {
    }
  }

  // 解析展示地址：http(s) 一律经宿主 http 管线下载落盘（AVIF→JPEG 转码 + LRU 淘汰）
  // 后返回 file:// 本地路径；源声明请求头（Referer/UA/Cookie）时附加，未声明用空请求头
  // （Http 层自动补默认 UA）；下载失败回退原始地址交系统 Image 直连兜底；本地文件原样返回。
  // 统一单例语义：同一 URL 无论多少界面并发请求，共享同一网络任务与同一结果（含失败回退）
  static async resolve(url: string, sourceKey: string, pageUrl?: string): Promise<string> {
    if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
      return url;
    }
    // 自初始化防护：早于 EntryAbility 初始化时直接返回原 url，避免拼出 "/hash.jpg" 根路径
    if (ImageCache.dir === '') {
      return url;
    }
    // 进程内结果缓存：任一界面加载成功后其余界面直接秒回同一结果
    const memo = ImageCache.resolved.get(url);
    if (memo !== undefined) {
      if (memo.ok) {
        try {
          if (fs.accessSync(memo.value.substring('file://'.length))) {
            return memo.value;
          }
        } catch (_e) {
        }
        ImageCache.resolved.delete(url);
      } else if (Date.now() - memo.at < ImageCache.FAIL_TTL_MS) {
        // 失败回退记录在 TTL 内直接复用，保证各界面状态一致；过期后允许重试网络
        return memo.value;
      } else {
        ImageCache.resolved.delete(url);
      }
    }
    // 缓存命中优先（不依赖源注册状态，历史/更新页等无 sourceKey 场景同样本地服务）
    const path = await ImageCache.cachedPath(url);
    let exists: boolean = false;
    try {
      exists = fs.accessSync(path);
    } catch (e) {
      throw new Error(`access cache file failed: ${e}`);
    }
    if (exists) {
      const hit = `file://${path}`;
      ImageCache.remember(url, hit, true);
      return hit;
    }
    let source = SourceRegistry.get(sourceKey);
    if (source === undefined && sourceKey !== '') {
      // 冷启动竞态：书架封面先于插件源注册渲染，限时等待插件加载完成后再查一次
      await ImageCache.waitPluginsLoaded();
      source = SourceRegistry.get(sourceKey);
    }
    // 源请求头：声明了用源请求头（防盗链），未声明/未知源用空请求头；
    // 统一经宿主管线下载缓存（未入库封面同样进 LRU 公共缓存）
    const srcHeaders = source !== undefined ? source.imageRequestHeaders() : undefined;
    const headers: Record<string, string> = srcHeaders !== undefined ? srcHeaders : {};
    // 单例任务：创建者与并发加入者共享同一 Promise；任务内部自带失败回退，
    // 所有调用方拿到完全一致的结果，不会出现裸拒绝穿透导致的状态分叉
    const pending = ImageCache.inflight.get(url);
    if (pending !== undefined) {
      return pending;
    }
    const task = ImageCache.settleFetch(url, ImageCache.withReferer(headers, pageUrl), path);
    ImageCache.inflight.set(url, task);
    try {
      return await task;
    } finally {
      ImageCache.inflight.delete(url);
    }
  }

  // 包装一次下载任务：成功记录进程内结果并返回 file://；失败记录回退结果并返回原始 url
  private static settleFetch(url: string, headers: Record<string, string>, path: string): Promise<string> {
    return ImageCache.fetch(url, headers, path).then((p: string): string => {
      ImageCache.remember(url, p, true);
      return p;
    }, (e: Error): string => {
      // 管线下载失败（网络异常/防盗链拦截等）：回退原始地址，交系统 Image 直连兜底；
      // 结果同样进进程内缓存，TTL 内所有界面共享同一回退状态，不再各自重试或分叉
      hilog.warn(0x0000, 'CoverDbg', 'fetch failed url=%{public}s err=%{public}s', url, `${e}`);
      ImageCache.remember(url, url, false);
      return url;
    });
  }

  private static remember(url: string, value: string, ok: boolean): void {
    if (ImageCache.resolved.size >= ImageCache.MAX_MEMO) {
      ImageCache.resolved.clear();
    }
    const entry: ResolvedEntry = { value: value, ok: ok, at: Date.now() };
    ImageCache.resolved.set(url, entry);
  }

  // 限时等待插件加载完成（加载挂死时 8s 超时回落直连）；

  // 命中缓存直接返回；未命中无论源是否声明请求头都下载落盘；失败返回 ''
  static async ensureLocal(context: common.Context, url: string, sourceKey: string): Promise<string> {
    if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
      return url;
    }
    if (ImageCache.dir === '') {
      ImageCache.init(context);
    }
    const source = SourceRegistry.get(sourceKey);
    const srcHeaders = source !== undefined ? source.imageRequestHeaders() : undefined;
    const headers: Record<string, string> = srcHeaders !== undefined ? srcHeaders : {};
    const path = await ImageCache.cachedPath(url);
    let exists: boolean = false;
    try {
      exists = fs.accessSync(path);
    } catch (e) {
      throw new Error(`access cache file failed: ${e}`);
    }
    if (exists) {
      return path;
    }
    // 复用统一单例任务：与 resolve 共享同一 inflight 条目（自带回退、不会裸拒绝），
    // 拿到回退 url（非 file://）时说明本次下载失败，按约定返回 ''
    const pending = ImageCache.inflight.get(url);
    if (pending !== undefined) {
      const done = await pending;
      return done.indexOf('file://') === 0 ? done.substring('file://'.length) : '';
    }
    const task = ImageCache.settleFetch(url, headers, path);
    ImageCache.inflight.set(url, task);
    try {
      const done = await task;
      return done.indexOf('file://') === 0 ? done.substring('file://'.length) : '';
    } finally {
      ImageCache.inflight.delete(url);
    }
  }

  // 确保本地文件存在并返回裸绝对路径（桌面卡片等需要 fd 的场景）：

  // 缓存目录占用字节数
  static size(): number {
    try {
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
    } catch (e) {
      throw new Error(`measure cache size failed: ${e}`);
    }
  }

  // 缓存文件数量（清除章节缓存时用于提示删除了多少个文件）
  static count(): number {
    try {
      if (ImageCache.dir === '' || !fs.accessSync(ImageCache.dir)) {
        return 0;
      }
      return fs.listFileSync(ImageCache.dir).length;
    } catch (e) {
      throw new Error(`count cache files failed: ${e}`);
    }
  }

  // 枚举仍同步（仅读目录项+元信息），真正的文件删除走异步 unlink，不再阻塞启动路径
  static clearAll(): number {
    const total: number = ImageCache.size();
    ImageCache.totalBytes = 0;
    try {
      if (ImageCache.dir !== '' && fs.accessSync(ImageCache.dir)) {
        const names = fs.listFileSync(ImageCache.dir);
        for (let i = 0; i < names.length; i++) {
          fs.unlink(`${ImageCache.dir}/${names[i]}`).catch((_e: BusinessError): void => {
          });
        }
      }
    } catch (e) {
      throw new Error(`clear cache failed: ${e}`);
    }
    return total;
  }

  // 全量统计目录字节数（作为超预算判定的基准）
  private static rescanBytes(): void {
    try {
      if (ImageCache.dir === '' || !fs.accessSync(ImageCache.dir)) {
        return;
      }
      let total: number = 0;
      const names = fs.listFileSync(ImageCache.dir);
      for (let i = 0; i < names.length; i++) {
        try {
          total += fs.statSync(`${ImageCache.dir}/${names[i]}`).size;
        } catch (_e) {
        }
      }
      ImageCache.totalBytes = total;
    } catch (e) {
      throw new Error(`rescan cache bytes failed: ${e}`);
    }
  }

  // 清空缓存目录，返回清除的字节数

  // 插件就绪后清掉超时定时器，不留下空转计时器
  private static waitPluginsLoaded(): Promise<void> {
    return new Promise<void>((resolve: (value: void) => void): void => {
      let timerId: number = -1;
      PluginService.ready().then((): void => {
        if (timerId >= 0) {
          clearTimeout(timerId);
          timerId = -1;
        }
        resolve();
      }).catch((_e: Object): void => {
        if (timerId >= 0) {
          clearTimeout(timerId);
          timerId = -1;
        }
        resolve();
      });
      timerId = setTimeout((): void => {
        timerId = -1;
        resolve();
      }, 8000);
    });
  }

  // ---------------- 内部实现 ----------------

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

  private static async fetch(url: string, headers: Record<string, string>, path: string): Promise<string> {
    const raw = await Http.getBuffer(url, headers);
    let buffer = raw;
    // AVIF 落盘前转 JPEG：系统解码器不支持 AVIF（且失败时 Promise 挂死）
    if (AvifConverter.isAvif(new Uint8Array(raw))) {
      try {
        buffer = await AvifConverter.convert(new Uint8Array(raw));
      } catch (e) {
        // 转换失败：保留原始 AVIF 字节（支持 AVIF 的设备仍可显示）
      }
    }
    // 原子落盘：先写临时文件再改名，避免应用进程与表单进程并发写坏同一封面；
    // 临时文件名带时间戳+序号，多进程/多任务并发写同一封面也不会互相覆盖
    const tmp = `${path}.${Date.now()}.${ImageCache.seq++}.tmp`;
    let existed = false;
    try {
      const file = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      if (!fs.accessSync(path)) {
        fs.renameSync(tmp, path);
      } else {
        fs.unlinkSync(tmp);
        existed = true;
      }
    } catch (e) {
      // 失败/异常路径清理 .tmp 残留
      try {
        if (fs.accessSync(tmp)) {
          fs.unlinkSync(tmp);
        }
      } catch (_e) {
      }
      throw new Error((e as Error).message);
    }
    if (!existed) {
      ImageCache.noteWrite(buffer.byteLength);
    }
    return `file://${path}`;
  }

  // 写入成功后增量累计字节，超预算时延后一拍触发 LRU 淘汰
  private static noteWrite(bytes: number): void {
    ImageCache.totalBytes += bytes;
    if (ImageCache.totalBytes > ImageCache.MAX_DISK_BYTES && !ImageCache.evicting) {
      ImageCache.evicting = true;
      setTimeout((): void => {
        try {
          ImageCache.evictOldest();
        } finally {
          ImageCache.evicting = false;
        }
      }, 0);
    }
  }

  // 超预算时按 mtime 淘汰最旧文件，直到回到预算内
  private static evictOldest(): void {
    try {
      if (ImageCache.dir === '' || !fs.accessSync(ImageCache.dir)) {
        return;
      }
      const names = fs.listFileSync(ImageCache.dir);
      const metas: CacheFileMeta[] = [];
      for (let i = 0; i < names.length; i++) {
        try {
          const stat = fs.statSync(`${ImageCache.dir}/${names[i]}`);
          const meta: CacheFileMeta = { name: names[i], mtime: stat.mtime, size: stat.size };
          metas.push(meta);
        } catch (_e) {
        }
      }
      metas.sort((a: CacheFileMeta, b: CacheFileMeta): number => a.mtime - b.mtime);
      for (let i = 0; i < metas.length; i++) {
        if (ImageCache.totalBytes <= ImageCache.MAX_DISK_BYTES) {
          break;
        }
        try {
          fs.unlinkSync(`${ImageCache.dir}/${metas[i].name}`);
          ImageCache.totalBytes -= metas[i].size;
          if (ImageCache.totalBytes < 0) {
            ImageCache.totalBytes = 0;
          }
        } catch (_e) {
        }
      }
    } catch (e) {
      throw new Error(`evict cache failed: ${e}`);
    }
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
    try {
      // @SuppressWarnings syscap
      const md = cryptoFramework.createMd('MD5');
      const input: cryptoFramework.DataBlob = { data: new util.TextEncoder().encodeInto(text) };
      // @SuppressWarnings syscap
      await md.update(input);
      // @SuppressWarnings syscap
      const output = await md.digest();
      let hex = '';
      for (let i = 0; i < output.data.length; i++) {
        const b = output.data[i];
        hex += b < 16 ? `0${b.toString(16)}` : b.toString(16);
      }
      return hex;
    } catch (e) {
      throw new Error(`md5 failed: ${e}`);
    }
  }
}
