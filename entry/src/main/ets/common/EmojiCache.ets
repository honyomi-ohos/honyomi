import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Http } from '../net/Http';
import { AtomicFileWriter } from './AtomicFileWriter';

// Bangumi 表情持久缓存（评论区全部表情图共用：片段表情 + 12 反应表情）：
// 与 ImageCache/BgmCoverCache 的 LRU 淘汰策略不同——表情文件极小且集合有限，
// 落盘后永不过期、不淘汰，仅随用户在「数据与存储」手动清除释放；
// 目录位于 filesDir（应用持久区，系统不回收）。落盘复用 AtomicFileWriter 共享原语
export class EmojiCache {
  private static dir: string = '';
  private static inflight: Map<string, Promise<string>> = new Map();
  // 进程内已解析结果：url → 本地 file:// 路径（cached() 同步查询用）
  private static resolved: Map<string, string> = new Map();
  // 失败记录时间戳（TTL 内不重试，避免离线时每次加载都重复请求）
  private static failed: Map<string, number> = new Map();
  private static readonly FAIL_TTL_MS: number = 60000;
  // 批量预热并发数
  private static readonly CONCURRENCY: number = 6;

  static init(context: common.Context): void {
    EmojiCache.dir = `${context.filesDir}/emoji_cache`;
    try {
      if (!fs.accessSync(EmojiCache.dir)) {
        fs.mkdirSync(EmojiCache.dir, true);
      }
    } catch (e) {
      throw new Error(`init emoji cache dir failed: ${e}`);
    }
    // 延后一拍清扫进程被杀残留的 .tmp 半成品
    setTimeout((): void => {
      AtomicFileWriter.sweepTmp(EmojiCache.dir);
    }, 0);
  }

  // 同步查询（渲染线程用）：已解析返回本地 file:// 路径，否则返回原 url
  // （未命中场景由上层先经 ensureAll 预热，渲染时基本必命中）
  static cached(url: string): string {
    if (EmojiCache.dir === '' ||
      (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0)) {
      return url;
    }
    const hit: string | undefined = EmojiCache.resolved.get(url);
    if (hit !== undefined) {
      return hit;
    }
    return url;
  }

  // 解析展示地址：磁盘命中返回 file:// 本地路径；未命中经宿主 http 管线下载
  // 落盘后返回；下载失败回退原始地址交系统 Image 直连兜底（失败 TTL 内不重试）
  static async resolve(url: string): Promise<string> {
    if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
      return url;
    }
    if (EmojiCache.dir === '') {
      return url;
    }
    const failAt: number | undefined = EmojiCache.failed.get(url);
    if (failAt !== undefined) {
      if (Date.now() - failAt < EmojiCache.FAIL_TTL_MS) {
        return url;
      }
      EmojiCache.failed.delete(url);
    }
    const path: string = `${EmojiCache.dir}/${EmojiCache.fileName(url)}`;
    try {
      if (fs.accessSync(path)) {
        const local: string = `file://${path}`;
        EmojiCache.resolved.set(url, local);
        return local;
      }
    } catch (_e) {
      return url;
    }
    const pending: Promise<string> | undefined = EmojiCache.inflight.get(url);
    if (pending !== undefined) {
      return pending;
    }
    const task: Promise<string> = EmojiCache.fetch(url, path);
    EmojiCache.inflight.set(url, task);
    try {
      return await task;
    } catch (e) {
      hilog.warn(0x0000, 'EmojiCache', 'fetch failed url=%{public}s err=%{public}s', url, `${e}`);
      EmojiCache.failed.set(url, Date.now());
      return url;
    } finally {
      EmojiCache.inflight.delete(url);
    }
  }

  // 批量预热（去重 + 并发池）：全部完成后返回，单个失败静默（resolve 内回退原地址）
  static async ensureAll(urls: string[]): Promise<void> {
    const unique: string[] = [];
    for (let i = 0; i < urls.length; i++) {
      const u: string = urls[i];
      if (unique.indexOf(u) < 0) {
        unique.push(u);
      }
    }
    let next: number = 0;
    const worker = async (): Promise<void> => {
      while (next < unique.length) {
        await EmojiCache.resolve(unique[next]);
        next++;
      }
    };
    const tasks: Promise<void>[] = [];
    const n: number = Math.min(EmojiCache.CONCURRENCY, unique.length);
    for (let i = 0; i < n; i++) {
      tasks.push(worker());
    }
    await Promise.all(tasks);
  }

  // 目录占用字节数
  static size(): number {
    try {
      if (EmojiCache.dir === '' || !fs.accessSync(EmojiCache.dir)) {
        return 0;
      }
      let total: number = 0;
      const names: string[] = fs.listFileSync(EmojiCache.dir);
      for (let i = 0; i < names.length; i++) {
        total += fs.statSync(`${EmojiCache.dir}/${names[i]}`).size;
      }
      return total;
    } catch (_e) {
      return 0;
    }
  }

  // 缓存文件数量（清除时用于提示删除了多少个文件）
  static count(): number {
    try {
      if (EmojiCache.dir === '' || !fs.accessSync(EmojiCache.dir)) {
        return 0;
      }
      return fs.listFileSync(EmojiCache.dir).length;
    } catch (_e) {
      return 0;
    }
  }

  // 手动清除：删除目录内全部文件并清空内存记录，返回清除的字节数
  static clearAll(): number {
    let total: number = 0;
    EmojiCache.resolved.clear();
    EmojiCache.failed.clear();
    try {
      if (EmojiCache.dir !== '' && fs.accessSync(EmojiCache.dir)) {
        const names: string[] = fs.listFileSync(EmojiCache.dir);
        for (let i = 0; i < names.length; i++) {
          try {
            total += fs.statSync(`${EmojiCache.dir}/${names[i]}`).size;
            fs.unlinkSync(`${EmojiCache.dir}/${names[i]}`);
          } catch (_e) {
          }
        }
      }
    } catch (_e) {
    }
    return total;
  }

  // ---------------- 内部实现 ----------------

  private static async fetch(url: string, path: string): Promise<string> {
    const raw: ArrayBuffer = await Http.getBuffer(url, {});
    // 原子落盘（时间戳+序号 .tmp → rename）：避免并发写坏同一文件
    AtomicFileWriter.write(path, raw);
    const local: string = `file://${path}`;
    EmojiCache.resolved.set(url, local);
    return local;
  }

  // 文件名：URL 清洗为安全文件名（保留扩展名；过长截尾保留后段 + 扩展名）
  private static fileName(url: string): string {
    const q: number = url.indexOf('?');
    let clean: string = (q >= 0 ? url.substring(0, q) : url).replace(/[^a-zA-Z0-9.]/g, '_');
    if (clean.length > 120) {
      const dot: number = clean.lastIndexOf('.');
      const ext: string = dot >= 0 ? clean.substring(dot) : '';
      const head: string = dot >= 0 ? clean.substring(0, dot) : clean;
      clean = head.substring(head.length - (120 - ext.length)) + ext;
    }
    return clean;
  }
}
