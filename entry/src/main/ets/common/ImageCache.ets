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
import { AtomicFileWriter } from './AtomicFileWriter';
import { LruBudget } from './LruBudget';

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
  // 字节预算引擎（init 时创建）：记账 + 超预算按 mtime LRU 淘汰
  private static budget: LruBudget | null = null;

  static init(context: common.Context): void {
    ImageCache.dir = `${context.cacheDir}/image_file_cache`;
    try {
      if (!fs.accessSync(ImageCache.dir)) {
        fs.mkdirSync(ImageCache.dir, true);
      }
    } catch (e) {
      throw new Error(`init cache dir failed: ${e}`);
    }
    ImageCache.budget = new LruBudget(ImageCache.dir, ImageCache.MAX_DISK_BYTES);
    // 启动路径不做同步全量统计：延后一拍在后台累计字节数，并清扫进程被杀残留的临时文件
    setTimeout((): void => {
      AtomicFileWriter.sweepTmp(ImageCache.dir);
      if (ImageCache.budget !== null) {
        ImageCache.budget.rescan();
      }
    }, 0);
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

  // 网络环境变化（插件 API 调用成功、可能刚注入 DNS 直连规则）时清空失败回退记录：
  // 后续请求不再等失败 TTL 过期，立即重新走网络（成功记录保留，仍秒回本地文件）
  static resetFailed(): void {
    ImageCache.resolved.forEach((entry: ResolvedEntry, url: string): void => {
      if (!entry.ok) {
        ImageCache.resolved.delete(url);
      }
    });
  }

  // 仅查磁盘缓存（不触发下载）：命中返回裸绝对路径，未命中返回 ''。
  // 供下载流程复用在线阅读时已缓存到的页字节，未命中由调用方走自身网络路径
  // （缓存中的 AVIF 已转码 JPEG，复制产物离线显示不受系统 AVIF 解码器缺失影响）
  static async peekCached(url: string): Promise<string> {
    if (ImageCache.dir === '') {
      return '';
    }
    const path = await ImageCache.cachedPath(url);
    try {
      if (fs.accessSync(path)) {
        return path;
      }
    } catch (_e) {
    }
    return '';
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
    if (ImageCache.budget !== null) {
      ImageCache.budget.reset();
    }
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

  // ---------------- 内部实现 ----------------

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

  // 防盗链：源请求头未声明 Referer 时回填为章节页地址
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
    // 原子落盘（时间戳+序号 .tmp → rename）：避免应用进程与表单进程并发写坏同一封面
    const existed = AtomicFileWriter.write(path, buffer);
    if (!existed) {
      if (ImageCache.budget !== null) {
        ImageCache.budget.noteWrite(buffer.byteLength);
      }
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
