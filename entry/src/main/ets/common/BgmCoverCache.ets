import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { Http } from '../net/Http';
import { AvifConverter } from './AvifConverter';
import { AtomicFileWriter } from './AtomicFileWriter';
import { LruBudget } from './LruBudget';

// Bangumi 条目封面独立缓存（新番时间表 / 条目详情 / 相关系列共用）：
// 与 ImageCache（章节页 + 漫画公共 LRU）完全隔离——章节缓存清除、阅读页挤占
// 均不影响本目录；按条目 id 落盘（日历 API 与 v0 详情 API 的同一封面 URL 变体不同，
// 按 URL 缓存跨页即失效，按 id 缓存则时间表 ⇄ 条目详情 ⇄ 相关条目全局共享一次下载）。
// 独立 64MB 预算按 mtime 淘汰，失败回退原始地址交系统 Image 直连兜底。
// 落盘/淘汰复用 AtomicFileWriter + LruBudget 共享原语
export class BgmCoverCache {
  // 磁盘缓存预算：超出后按 mtime 淘汰最旧文件直到回到预算内
  private static readonly MAX_DISK_BYTES: number = 64 * 1024 * 1024;
  private static dir: string = '';
  private static inflight: Map<number, Promise<string>> = new Map();
  // 字节预算引擎（init 时创建）：记账 + 超预算按 mtime LRU 淘汰
  private static budget: LruBudget | null = null;

  static init(context: common.Context): void {
    BgmCoverCache.dir = `${context.cacheDir}/bgm_cover_cache`;
    try {
      if (!fs.accessSync(BgmCoverCache.dir)) {
        fs.mkdirSync(BgmCoverCache.dir, true);
      }
    } catch (e) {
      throw new Error(`init bgm cover dir failed: ${e}`);
    }
    BgmCoverCache.budget = new LruBudget(BgmCoverCache.dir, BgmCoverCache.MAX_DISK_BYTES);
    // 启动路径不做同步全量统计：延后一拍在后台累计字节数，并清扫进程被杀残留的临时文件
    setTimeout((): void => {
      AtomicFileWriter.sweepTmp(BgmCoverCache.dir);
      if (BgmCoverCache.budget !== null) {
        BgmCoverCache.budget.rescan();
      }
    }, 0);
  }

  // 解析展示地址：命中返回 file:// 本地路径；未命中经宿主 http 管线下载
  //（Bangumi CDN 公开图，空请求头 + Http 层默认 UA；AVIF→JPEG 转码）落盘后返回；
  // 下载失败回退原始地址交系统 Image 直连兜底
  static async resolve(subjectId: number, url: string): Promise<string> {
    if (!(subjectId > 0)) {
      return url;
    }
    if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
      return url;
    }
    // 自初始化防护：早于 EntryAbility 初始化时直接返回原 url
    if (BgmCoverCache.dir === '') {
      return url;
    }
    const path = `${BgmCoverCache.dir}/${subjectId}.jpg`;
    try {
      if (fs.accessSync(path)) {
        return `file://${path}`;
      }
    } catch (e) {
      return url;
    }
    const pending = BgmCoverCache.inflight.get(subjectId);
    if (pending !== undefined) {
      return pending;
    }
    const task = BgmCoverCache.fetch(url, path);
    BgmCoverCache.inflight.set(subjectId, task);
    try {
      return await task;
    } catch (e) {
      // 管线下载失败（网络异常等）：回退原始地址，交系统 Image 直连兜底
      return url;
    } finally {
      BgmCoverCache.inflight.delete(subjectId);
    }
  }

  // ---------------- 内部实现 ----------------

  private static async fetch(url: string, path: string): Promise<string> {
    const raw = await Http.getBuffer(url, {});
    let buffer = raw;
    // AVIF 落盘前转 JPEG：系统解码器不支持 AVIF（且失败时 Promise 挂死）
    if (AvifConverter.isAvif(new Uint8Array(raw))) {
      try {
        buffer = await AvifConverter.convert(new Uint8Array(raw));
      } catch (e) {
        // 转换失败：保留原始 AVIF 字节（支持 AVIF 的设备仍可显示）
      }
    }
    // 原子落盘（时间戳+序号 .tmp → rename）：避免并发写坏同一封面
    const existed = AtomicFileWriter.write(path, buffer);
    if (!existed) {
      if (BgmCoverCache.budget !== null) {
        BgmCoverCache.budget.noteWrite(buffer.byteLength);
      }
    }
    return `file://${path}`;
  }
}
