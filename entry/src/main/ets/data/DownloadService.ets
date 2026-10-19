import { fileIo } from '@kit.CoreFileKit';
import type { WantAgent } from '@kit.AbilityKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError, zlib } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { Http } from '../net/Http';
import { Source, SourceRegistry } from '../source/Source';
import { ContentType, DownloadedChapter, DownloadedManga, DownloadTask, SPage, SVideo } from '../model/Models';
import { ChapterRepo, MangaRepo } from './Repos';
import { Settings } from '../common/Settings';
import { NetworkMonitor } from '../common/NetworkMonitor';
import { HlsDownloader } from '../common/HlsDownloader';
import { BtModule } from './BtModule';
import { BtComponentInstaller } from '../common/BtComponentInstaller';
import { AppKeys } from '../common/AppKeys';

// 拆分超长条漫图片的高度阈值（对齐 Mihon optimalImageHeight ≈ 屏幕高度*2）
const TALL_IMAGE_LIMIT = 8000;

// 队列持久化 JSON 结构（{filesDir}/download_queue.json）：
// 完成态不落盘（done.mark 为准），下载中(state=1)重启后重新排队，失败态保留供重试
class DownloadTaskRaw {
  mangaId: number = 0;
  mangaTitle: string = '';
  chapterId: number = 0;
  chapterName: string = '';
  chapterNumber: number = 0;
  dateUpload: number = 0;
  sourceKey: string = '';
  mangaUrl: string = '';
  chapterUrl: string = '';
  state: number = 0;
  progress: number = 0;
  total: number = 0;
  error: string = '';
}

class DownloadQueueRaw {
  paused: boolean = false;
  tasks: DownloadTaskRaw[] = [];
}

// 活动任务的控制标志：cancelled=用户取消；blocked=网络环境变化（回到队列续传）
class DlFlags {
  cancelled: boolean = false;
  blocked: boolean = false;
}

// 页面并发下载游标（worker 池共享推进）
class PageCursor {
  next: number = 0;
}

// 下载服务（对齐 Mihon DownloadManager 的精简版）：
// 多源并发（不同源各占一个下载槽）+ 单章页面并发 + 仅 Wi-Fi 门禁 + CBZ 打包 + 超长图拆分
// 存储布局: {filesDir}/downloads/{mangaId}/{chapterId}/000.jpg ... + done.mark
//           开启 CBZ 后页面打包为 chapter.cbz，阅读时解压到 cacheDir/cbz_extract/
export class DownloadService {
  private static rootDir: string = '';
  private static queueFile: string = '';
  private static context: common.UIAbilityContext | undefined = undefined;
  private static queue: DownloadTask[] = [];
  private static paused: boolean = false;
  private static listeners: Array<() => void> = [];
  // 并发模型：同一源同一时刻只跑一个任务，不同源最多 sourceLimit 个任务并行
  private static activeTasks: DownloadTask[] = [];
  private static activeFlags: Map<number, DlFlags> = new Map<number, DlFlags>();
  // 视频流式下载的主动中断句柄（chapterId → cancel）
  private static activeAborts: Map<number, () => void> = new Map<number, () => void>();
  // BT 下载任务映射（chapterId → torrent key）：完成/取消时定位种子句柄
  private static btKeys: Map<number, number> = new Map<number, number>();
  // 已完成(done.mark)章节 id 内存索引：列表行高频查询 isDownloaded，
  // 不能每次调用都做 O(N) 目录扫描；下载完成/删除章节时增量维护
  private static doneIds: Set<number> | undefined = undefined;
  // DATA_TRANSFER 长时任务：下载期间防真机锁屏/切后台进程被挂起导致下载永久卡住。
  // 系统要求通过实况窗持续更新进度（进度超过10分钟未更新会被系统取消），30秒心跳兜底
  private static bgTaskId: number = -1;
  private static bgNotifId: number = -1;
  private static bgRequesting: boolean = false;
  private static bgHeartbeat: number = -1;
  private static bgLastPct: number = -1;
  private static bgCancelBound: boolean = false;

  // 长时任务被用户移除通知/系统取消时重置状态，下个任务开始时重新申请
  private static onBgTaskCancel = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (DownloadService.bgTaskId >= 0 && info.id === DownloadService.bgTaskId) {
      DownloadService.resetBgTask();
    }
  };

  static init(context: common.UIAbilityContext): void {
    DownloadService.context = context;
    DownloadService.rootDir = `${context.filesDir}/downloads`;
    DownloadService.queueFile = `${context.filesDir}/download_queue.json`;
    try {
      if (!fileIo.accessSync(DownloadService.rootDir)) {
        fileIo.mkdirSync(DownloadService.rootDir, true);
      }
    } catch (e) {
      throw new Error(`init download dir failed: ${e}`);
    }
    if (!DownloadService.bgCancelBound) {
      DownloadService.bgCancelBound = true;
      try {
        backgroundTaskManager.on('continuousTaskCancel', DownloadService.onBgTaskCancel);
      } catch (e) {
        hilog.warn(0x0001, 'Download', 'bind continuousTaskCancel failed: %{public}s', `${e}`);
      }
    }
    // 重启恢复持久化队列并自动续传（未暂停时）
    DownloadService.loadQueue();
    if (!DownloadService.paused) {
      DownloadService.pump();
    }
  }

  static addListener(listener: () => void): void {
    DownloadService.listeners.push(listener);
  }

  static removeListener(listener: () => void): void {
    const idx = DownloadService.listeners.indexOf(listener);
    if (idx >= 0) {
      DownloadService.listeners.splice(idx, 1);
    }
  }

  static getQueue(): DownloadTask[] {
    // 返回快照，避免调用方持有内部数组引用
    return DownloadService.queue.slice();
  }

  static isQueued(chapterId: number): boolean {
    for (const t of DownloadService.queue) {
      if (t.chapterId === chapterId && t.state !== 2) {
        return true;
      }
    }
    return false;
  }

  static enqueue(task: DownloadTask): void {
    if (DownloadService.isQueued(task.chapterId) || DownloadService.isDownloaded(task.chapterId)) {
      return;
    }
    task.state = 0;
    DownloadService.queue.push(task);
    DownloadService.persistQueue();
    DownloadService.notify();
    DownloadService.pump();
  }

  // 取消任务：排队中直接移除；下载中置取消标志，由下载循环/续体在页边界退出
  static cancel(chapterId: number): void {
    let hadActive = false;
    for (const t of DownloadService.queue) {
      if (t.chapterId !== chapterId) {
        continue;
      }
      if (t.state === 1) {
        hadActive = true;
      }
      if (t.state !== 3) {
        t.state = 3;
        t.error = 'download_cancelled';
      }
    }
    const flags: DlFlags | undefined = DownloadService.activeFlags.get(chapterId);
    if (flags !== undefined) {
      flags.cancelled = true;
    }
    if (hadActive) {
      const abort: (() => void) | undefined = DownloadService.activeAborts.get(chapterId);
      if (abort !== undefined) {
        abort();
      }
    }
    DownloadService.queue = DownloadService.queue.filter((t: DownloadTask) => t.state !== 3);
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  static clearFinished(): void {
    DownloadService.queue = DownloadService.queue.filter((t: DownloadTask) => t.state !== 2 && t.state !== 3);
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  // 取消队列中全部任务（对齐 Mihon 下载队列页 overflow 的 "Cancel all"）
  static cancelAll(): void {
    let hadActive = false;
    for (const t of DownloadService.queue) {
      if (t.state === 1) {
        hadActive = true;
      }
      if (t.state !== 3) {
        t.state = 3;
        t.error = 'download_cancelled';
      }
    }
    DownloadService.activeFlags.forEach((flags: DlFlags): void => {
      flags.cancelled = true;
    });
    if (hadActive) {
      DownloadService.activeAborts.forEach((abort: () => void): void => {
        abort();
      });
    }
    DownloadService.queue = [];
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  // 按章节号升/降序重排队列（对齐 Mihon "Order by chapter number"）：
  // 各作品分组内排序，分组间顺序保持不变
  static sortQueue(asc: boolean): void {
    const groups = DownloadService.groupsOf();
    const next: DownloadTask[] = [];
    groups.forEach((tasks: DownloadTask[]): void => {
      const sorted = tasks.slice().sort((a: DownloadTask, b: DownloadTask): number => {
        const ka = a.chapterNumber > 0 ? a.chapterNumber : a.chapterId;
        const kb = b.chapterNumber > 0 ? b.chapterNumber : b.chapterId;
        return asc ? ka - kb : kb - ka;
      });
      for (const t of sorted) {
        next.push(t);
      }
    });
    DownloadService.queue = next;
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  // 按上传日期重排队列（对齐 Mihon "Order by upload date" 的 Newest/Oldest）：
  // 各作品分组内排序，分组间顺序保持不变
  static sortQueueByDate(newest: boolean): void {
    const groups = DownloadService.groupsOf();
    const next: DownloadTask[] = [];
    groups.forEach((tasks: DownloadTask[]): void => {
      const sorted = tasks.slice().sort((a: DownloadTask, b: DownloadTask): number => {
        return newest ? b.dateUpload - a.dateUpload : a.dateUpload - b.dateUpload;
      });
      for (const t of sorted) {
        next.push(t);
      }
    });
    DownloadService.queue = next;
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  // 拖拽排序后按给定章节 id 顺序同步内部队列（静默处理，不触发通知以不打断落位动画）
  static reorderQueue(orderedIds: number[]): void {
    const byId = new Map<number, DownloadTask>();
    for (const t of DownloadService.queue) {
      byId.set(t.chapterId, t);
    }
    const next: DownloadTask[] = [];
    for (const id of orderedIds) {
      const t: DownloadTask | undefined = byId.get(id);
      if (t !== undefined) {
        next.push(t);
        byId.delete(id);
      }
    }
    // 未包含在有序列表中的任务（同步期间新增）保持原有相对顺序追加
    byId.forEach((t: DownloadTask) => {
      next.push(t);
    });
    DownloadService.queue = next;
    DownloadService.persistQueue();
  }

  // 暂停：活动任务继续跑完，不再启动新任务
  static pauseAll(): void {
    DownloadService.paused = true;
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  static resumeAll(): void {
    DownloadService.paused = false;
    DownloadService.persistQueue();
    DownloadService.notify();
    DownloadService.pump();
  }

  static isPaused(): boolean {
    return DownloadService.paused;
  }

  // 置顶/移底：仅对排队中(state=0)的任务生效，且只在所属作品分组内移动
  // （对齐 Mihon 行菜单的 move to top/bottom：分组间顺序不受影响）
  static moveToTop(chapterId: number): void {
    const task = DownloadService.queue.find((t: DownloadTask) => t.chapterId === chapterId && t.state === 0);
    if (task === undefined) {
      return;
    }
    const groups = DownloadService.groupsOf();
    const group: DownloadTask[] | undefined = groups.get(task.mangaId);
    if (group === undefined) {
      return;
    }
    const idx = group.indexOf(task);
    if (idx > 0) {
      group.splice(idx, 1);
      group.unshift(task);
      DownloadService.queue = DownloadService.flattenGroups(groups);
      DownloadService.persistQueue();
      DownloadService.notify();
    }
  }

  static moveToBottom(chapterId: number): void {
    const task = DownloadService.queue.find((t: DownloadTask) => t.chapterId === chapterId && t.state === 0);
    if (task === undefined) {
      return;
    }
    const groups = DownloadService.groupsOf();
    const group: DownloadTask[] | undefined = groups.get(task.mangaId);
    if (group === undefined) {
      return;
    }
    const idx = group.indexOf(task);
    if (idx >= 0 && idx < group.length - 1) {
      group.splice(idx, 1);
      group.push(task);
      DownloadService.queue = DownloadService.flattenGroups(groups);
      DownloadService.persistQueue();
      DownloadService.notify();
    }
  }

  // 整部作品置顶/移底（对齐 Mihon move_to_top_series/move_to_bottom_series）
  static moveSeriesToTop(mangaId: number): void {
    const groups = DownloadService.groupsOf();
    const group: DownloadTask[] | undefined = groups.get(mangaId);
    if (group === undefined) {
      return;
    }
    groups.delete(mangaId);
    const next: DownloadTask[] = group.slice();
    groups.forEach((tasks: DownloadTask[]): void => {
      for (const t of tasks) {
        next.push(t);
      }
    });
    DownloadService.queue = next;
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  static moveSeriesToBottom(mangaId: number): void {
    const groups = DownloadService.groupsOf();
    const group: DownloadTask[] | undefined = groups.get(mangaId);
    if (group === undefined) {
      return;
    }
    // 删除后重新插入：Map 按插入顺序迭代，目标分组落到末尾
    groups.delete(mangaId);
    groups.set(mangaId, group);
    DownloadService.queue = DownloadService.flattenGroups(groups);
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  // 取消整部作品的全部任务（对齐 Mihon cancel_series）
  static cancelSeries(mangaId: number): void {
    let hadActive = false;
    for (const t of DownloadService.queue) {
      if (t.mangaId !== mangaId) {
        continue;
      }
      if (t.state === 1) {
        hadActive = true;
      }
      if (t.state !== 3) {
        t.state = 3;
        t.error = 'download_cancelled';
      }
      const flags: DlFlags | undefined = DownloadService.activeFlags.get(t.chapterId);
      if (flags !== undefined) {
        flags.cancelled = true;
      }
    }
    if (hadActive) {
      DownloadService.activeAborts.forEach((abort: () => void, chapterId: number): void => {
        const owns: boolean = DownloadService.queue.some((t: DownloadTask): boolean => {
          return t.mangaId === mangaId && t.chapterId === chapterId;
        });
        if (owns) {
          abort();
        }
      });
    }
    DownloadService.queue = DownloadService.queue.filter((t: DownloadTask) => t.mangaId !== mangaId);
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  // 重试失败任务
  static retry(chapterId: number): void {
    for (const t of DownloadService.queue) {
      if (t.chapterId === chapterId && t.state === 3) {
        t.state = 0;
        t.progress = 0;
        t.error = '';
      }
    }
    // 手动重试视为重新接受 BT 组件安装引导（此前"暂不"的拒绝仅抑制自动弹窗）
    AppStorage.setOrCreate(AppKeys.BT_ASK_DISMISSED, false);
    DownloadService.persistQueue();
    DownloadService.notify();
    DownloadService.pump();
  }

  // BT 组件安装完成后重跑因组件缺失（bt_component_required）失败的任务
  static retryBtComponentTasks(): void {
    let touched = false;
    for (const t of DownloadService.queue) {
      if (t.state === 3 && t.error === 'bt_component_required') {
        t.state = 0;
        t.progress = 0;
        t.error = '';
        touched = true;
      }
    }
    if (!touched) {
      return;
    }
    DownloadService.persistQueue();
    DownloadService.notify();
    DownloadService.pump();
  }

  // 前台 UIAbilityContext（BtComponentInstaller 发起按需安装须前台上下文）
  static abilityContext(): common.UIAbilityContext | undefined {
    return DownloadService.context;
  }

  // 网络环境/仅 Wi-Fi 开关变化后的门禁刷新：
  // 不可用 → 活动任务在页边界回到队列；可用 → 恢复泵送
  static refreshNetworkGate(): void {
    if (!DownloadService.networkAllowed()) {
      DownloadService.activeFlags.forEach((flags: DlFlags): void => {
        flags.blocked = true;
      });
      DownloadService.activeAborts.forEach((abort: () => void): void => {
        abort();
      });
    } else {
      DownloadService.pump();
    }
  }

  static chapterDir(mangaId: number, chapterId: number): string {
    return `${DownloadService.rootDir}/${mangaId}/${chapterId}`;
  }

  // 已下载漫画的 id 列表（downloads/{mangaId}/ 目录存在即算）
  static downloadedMangaIds(): number[] {
    const ids: number[] = [];
    try {
      if (DownloadService.rootDir === '' || !fileIo.accessSync(DownloadService.rootDir)) {
        return ids;
      }
      const mangaDirs = fileIo.listFileSync(DownloadService.rootDir);
      for (const md of mangaDirs) {
        const id = parseInt(md, 10);
        if (id >= 0) {
          ids.push(id);
        }
      }
    } catch (e) {
      throw new Error(`list downloaded manga ids failed: ${e}`);
    }
    return ids;
  }

  static isDownloaded(chapterId: number): boolean {
    if (DownloadService.doneIds === undefined) {
      DownloadService.rebuildDoneIndex();
    }
    return DownloadService.doneIds !== undefined && DownloadService.doneIds.has(chapterId);
  }

  // 每部漫画的已下载章节数（与 rebuildDoneIndex 口径一致：仅统计带 done.mark 的章节），书架下载徽标用
  static downloadedChapterCounts(): Record<string, number> {
    const counts: Record<string, number> = {};
    try {
      if (DownloadService.rootDir === '' || !fileIo.accessSync(DownloadService.rootDir)) {
        return counts;
      }
      const mangaDirs = fileIo.listFileSync(DownloadService.rootDir);
      for (const md of mangaDirs) {
        const id = parseInt(md, 10);
        if (id >= 0) {
          const chapterDirs = fileIo.listFileSync(`${DownloadService.rootDir}/${md}`);
          let done = 0;
          for (const cd of chapterDirs) {
            if (fileIo.accessSync(`${DownloadService.rootDir}/${md}/${cd}/done.mark`)) {
              done += 1;
            }
          }
          counts[`${id}`] = done;
        }
      }
      return counts;
    } catch (e) {
      throw new Error(`count downloaded chapters failed: ${e}`);
    }
  }

  // 已完成下载的章节 id 集合（复用 done 索引，更新页"已下载"筛选用）
  static downloadedChapterIdSet(): Set<number> {
    if (DownloadService.doneIds === undefined) {
      DownloadService.rebuildDoneIndex();
    }
    const set = new Set<number>();
    if (DownloadService.doneIds !== undefined) {
      DownloadService.doneIds.forEach((id: number) => {
        set.add(id);
      });
    }
    return set;
  }

  // 从目录结构反查 mangaId（downloads/{mangaId}/{chapterId}/）
  static mangaIdOf(chapterId: number): number {
    try {
      if (DownloadService.rootDir === '' || !fileIo.accessSync(DownloadService.rootDir)) {
        return -1;
      }
      const mangaDirs = fileIo.listFileSync(DownloadService.rootDir);
      for (const md of mangaDirs) {
        const chapterPath = `${DownloadService.rootDir}/${md}/${chapterId}`;
        if (fileIo.accessSync(chapterPath)) {
          return parseInt(md, 10);
        }
      }
    } catch (e) {
      throw new Error(`find manga id failed: ${e}`);
    }
    return -1;
  }

  static localText(mangaId: number, chapterId: number): string {
    const path = `${DownloadService.chapterDir(mangaId, chapterId)}/chapter.txt`;
    try {
      if (DownloadService.rootDir !== '' && fileIo.accessSync(path)) {
        return path;
      }
    } catch (e) {
      throw new Error(`check local text failed: ${e}`);
    }
    return '';
  }

  static localVideo(mangaId: number, chapterId: number): string {
    const dir = DownloadService.chapterDir(mangaId, chapterId);
    // 直链下载产物为 video.mp4，m3u8(MPEG-TS) 合并产物为 video.ts
    const names: string[] = ['video.mp4', 'video.ts'];
    for (const name of names) {
      const path = `${dir}/${name}`;
      try {
        if (DownloadService.rootDir !== '' && fileIo.accessSync(path)) {
          return path;
        }
      } catch (e) {
        throw new Error(`check local video failed: ${e}`);
      }
    }
    // BT 下载产物：种子内部文件名/子目录由种子决定，递归扫描取最大视频文件
    return DownloadService.scanVideoFile(dir);
  }

  // BT 种子常见视频容器扩展（localVideo 扫描回退用）
  private static readonly VIDEO_EXTS: string[] =
    ['.mp4', '.mkv', '.ts', '.avi', '.mov', '.webm', '.m4v', '.wmv', '.flv', '.mpg', '.mpeg'];

  private static scanVideoFile(dir: string): string {
    if (DownloadService.rootDir === '') {
      return '';
    }
    try {
      if (!fileIo.accessSync(dir)) {
        return '';
      }
      return DownloadService.scanVideoDir(dir);
    } catch (e) {
      return '';
    }
  }

  // 递归扫描目录内最大的视频文件（BT 章节可能含多文件/子目录，播放主视频取最大者）
  private static scanVideoDir(dir: string): string {
    let best = '';
    let bestSize = -1;
    let entries: string[] = [];
    try {
      entries = fileIo.listFileSync(dir);
    } catch (e) {
      return '';
    }
    for (const name of entries) {
      if (name === 'done.mark' || name === 'video.mp4' || name === 'video.ts') {
        continue;
      }
      const full = `${dir}/${name}`;
      let isDir = false;
      let size = -1;
      try {
        const stat = fileIo.statSync(full);
        isDir = stat.isDirectory();
        size = stat.size;
      } catch (e) {
        continue;
      }
      if (isDir) {
        const sub = DownloadService.scanVideoDir(full);
        if (sub !== '') {
          const subSize = DownloadService.fileSizeOf(sub);
          if (subSize > bestSize) {
            best = sub;
            bestSize = subSize;
          }
        }
        continue;
      }
      const lower = name.toLowerCase();
      for (const ext of DownloadService.VIDEO_EXTS) {
        if (lower.endsWith(ext)) {
          if (size > bestSize) {
            best = full;
            bestSize = size;
          }
          break;
        }
      }
    }
    return best;
  }

  private static fileSizeOf(path: string): number {
    try {
      return fileIo.statSync(path).size;
    } catch (e) {
      return 0;
    }
  }

  static localPages(mangaId: number, chapterId: number): string[] {
    const dir = DownloadService.chapterDir(mangaId, chapterId);
    try {
      if (!fileIo.accessSync(dir)) {
        return [];
      }
      const files = fileIo.listFileSync(dir);
      const pages = files.filter((f: string) => f !== 'done.mark' && f !== 'chapter.txt' &&
        f !== 'video.mp4' && f !== 'video.ts' && f !== 'chapter.cbz' && f !== 'extract.ok').sort();
      const result: string[] = [];
      for (const f of pages) {
        result.push(`${dir}/${f}`);
      }
      return result;
    } catch (e) {
      throw new Error(`list local pages failed: ${e}`);
    }
  }

  // 本地页面（异步版）：CBZ 章节首次阅读时解压到缓存目录后返回图片路径
  static async localPagesAsync(mangaId: number, chapterId: number): Promise<string[]> {
    const dir = DownloadService.chapterDir(mangaId, chapterId);
    try {
      if (!fileIo.accessSync(dir)) {
        return [];
      }
      const cbz = `${dir}/chapter.cbz`;
      if (fileIo.accessSync(cbz)) {
        return await DownloadService.extractCbzPages(cbz, mangaId, chapterId);
      }
    } catch (e) {
      throw new Error(`check local pages failed: ${e}`);
    }
    return DownloadService.localPages(mangaId, chapterId);
  }

  // 删除章节本地文件：先取消并等待活动下载任务退出，避免删除与写入并发产生半截文件
  static async deleteChapter(mangaId: number, chapterId: number): Promise<void> {
    const active = DownloadService.queue.find((t: DownloadTask) => t.chapterId === chapterId && t.state === 1);
    DownloadService.cancel(chapterId);
    if (active !== undefined) {
      await new Promise<void>((resolve: () => void) => {
        const timer = setInterval((): void => {
          if (!DownloadService.isActive(chapterId)) {
            clearInterval(timer);
            resolve();
          }
        }, 50);
      });
    }
    const dir = DownloadService.chapterDir(mangaId, chapterId);
    try {
      if (fileIo.accessSync(dir)) {
        DownloadService.rmdir(dir);
      }
    } catch (e) {
      throw new Error(`delete chapter files failed: ${e}`);
    }
    DownloadService.clearExtractCache(mangaId, chapterId);
    if (DownloadService.doneIds !== undefined) {
      DownloadService.doneIds.delete(chapterId);
    }
    DownloadService.queue = DownloadService.queue.filter((t: DownloadTask) => t.chapterId !== chapterId);
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  static async listDownloaded(): Promise<DownloadedManga[]> {
    const result: DownloadedManga[] = [];
    try {
      if (DownloadService.rootDir === '' || !fileIo.accessSync(DownloadService.rootDir)) {
        return result;
      }
      const mangaDirs = fileIo.listFileSync(DownloadService.rootDir).sort();
      for (const md of mangaDirs) {
        const mangaId = parseInt(md, 10);
        const mangaPath = `${DownloadService.rootDir}/${md}`;
        const chapterDirs = fileIo.listFileSync(mangaPath).sort((a: string, b: string) => {
          return parseInt(a, 10) - parseInt(b, 10);
        });
        const chapters: DownloadedChapter[] = [];
        for (const cd of chapterDirs) {
          if (!fileIo.accessSync(`${mangaPath}/${cd}/done.mark`)) {
            continue;
          }
          const chapterId = parseInt(cd, 10);
          const names = await DownloadService.chapterNames(mangaId, chapterId);
          chapters.push(DownloadedChapter.of(mangaId, names[0], chapterId, names[1]));
        }
        if (chapters.length > 0) {
          const manga = await MangaRepo.get(mangaId);
          const group = new DownloadedManga();
          group.mangaId = mangaId;
          group.mangaTitle = manga !== undefined ? manga.title : `#${mangaId}`;
          group.chapters = chapters;
          result.push(group);
        }
      }
      return result;
    } catch (e) {
      throw new Error(`list downloaded failed: ${e}`);
    }
  }

  private static isActive(chapterId: number): boolean {
    for (const t of DownloadService.activeTasks) {
      if (t.chapterId === chapterId) {
        return true;
      }
    }
    return false;
  }

  private static networkAllowed(): boolean {
    return !Settings.getDownloadWifiOnly() || NetworkMonitor.isWifiLike();
  }

  private static notify(): void {
    const snapshot = DownloadService.listeners.slice();
    for (const fn of snapshot) {
      fn();
    }
  }

  // 按作品分组（保持首次出现顺序，组内保持队列顺序）
  private static groupsOf(): Map<number, DownloadTask[]> {
    const groups = new Map<number, DownloadTask[]>();
    for (const t of DownloadService.queue) {
      let g: DownloadTask[] | undefined = groups.get(t.mangaId);
      if (g === undefined) {
        g = [];
        groups.set(t.mangaId, g);
      }
      g.push(t);
    }
    return groups;
  }

  // 分组按插入顺序摊平回队列
  private static flattenGroups(groups: Map<number, DownloadTask[]>): DownloadTask[] {
    const next: DownloadTask[] = [];
    groups.forEach((tasks: DownloadTask[]): void => {
      for (const t of tasks) {
        next.push(t);
      }
    });
    return next;
  }

  // 泵送：同一源同时只跑一个任务，不同源最多 sourceLimit 个并行
  private static pump(): void {
    if (DownloadService.paused || !DownloadService.networkAllowed()) {
      return;
    }
    const limit = Settings.getDownloadParallelSourceLimit();
    while (DownloadService.activeTasks.length < limit) {
      const busySources = new Set<string>();
      for (const t of DownloadService.activeTasks) {
        busySources.add(t.sourceKey);
      }
      const next = DownloadService.queue.find((t: DownloadTask): boolean => {
        return t.state === 0 && !busySources.has(t.sourceKey);
      });
      if (next === undefined) {
        return;
      }
      DownloadService.activeTasks.push(next);
      DownloadService.launch(next);
    }
  }

  private static launch(task: DownloadTask): void {
    DownloadService.ensureBgTask();
    const flags = new DlFlags();
    DownloadService.activeFlags.set(task.chapterId, flags);
    DownloadService.process(task, flags).then(() => {
      DownloadService.finishTask(task);
    }).catch((e: Error) => {
      hilog.error(0x0001, 'Download', 'process failed: %{public}s', e.message);
      DownloadService.finishTask(task);
    });
  }

  private static finishTask(task: DownloadTask): void {
    DownloadService.activeTasks = DownloadService.activeTasks.filter((t: DownloadTask) => t !== task);
    DownloadService.activeFlags.delete(task.chapterId);
    DownloadService.activeAborts.delete(task.chapterId);
    // 完成即移出队列：避免"228/228"完成态常驻队列页，章节转由"已下载"区展示；
    // 失败任务保留在队列中供重试
    if (task.state === 2) {
      DownloadService.queue = DownloadService.queue.filter((t: DownloadTask) => t !== task);
    }
    DownloadService.persistQueue();
    DownloadService.releaseBgTaskIfIdle();
    DownloadService.notify();
    DownloadService.pump();
  }

  private static async process(task: DownloadTask, flags: DlFlags): Promise<void> {
    task.state = 1;
    task.progress = 0;
    task.error = '';
    DownloadService.notify();
    DownloadService.publishBgProgress(true);
    try {
      const source = SourceRegistry.get(task.sourceKey);
      if (source === undefined) {
        throw new Error(`source_not_found|${task.sourceKey}`);
      }
      if (flags.cancelled) {
        throw new Error('download_cancelled');
      }
      if (flags.blocked) {
        throw new Error('network_blocked');
      }
      if (source.contentType === ContentType.NOVEL) {
        await DownloadService.downloadNovel(task, source, flags);
        return;
      }
      if (source.contentType === ContentType.VIDEO) {
        await DownloadService.downloadVideo(task, source, flags);
        return;
      }
      const pages: SPage[] = await source.getPageList(task.chapterUrl);
      if (flags.cancelled) {
        throw new Error('download_cancelled');
      }
      if (flags.blocked) {
        throw new Error('network_blocked');
      }
      task.total = pages.length;
      DownloadService.notify();
      const imageHeaders = source.imageRequestHeaders();
      const dir = DownloadService.chapterDir(task.mangaId, task.chapterId);
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      // 残留 .tmp 是上次进程被杀/取消时的半截文件；正式页文件经原子写必然完整，
      // 已存在的页直接跳过实现断点续传
      DownloadService.cleanTmpFiles(dir);
      // 页级并发：单章内 pageLimit 个 worker 同时抓页
      const cursor = new PageCursor();
      const workerCount = Math.min(Settings.getDownloadParallelPageLimit(), pages.length);
      const workers: Array<Promise<void>> = [];
      for (let i = 0; i < workerCount; i++) {
        workers.push(DownloadService.pageWorker(task, pages, dir, imageHeaders, flags, cursor));
      }
      await Promise.all(workers);
      // 页列表比上次短时清理超出的多余编号页，避免旧图混入本地阅读
      DownloadService.removeStalePages(dir, pages.length);
      // 打包 CBZ（设置开启时；失败自动回退文件夹形式）
      await DownloadService.buildCbz(task, dir);
      const markFd = fileIo.openSync(`${dir}/done.mark`,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE).fd;
      fileIo.closeSync(markFd);
      if (DownloadService.doneIds !== undefined) {
        DownloadService.doneIds.add(task.chapterId);
      }
      task.state = 2;
      if (task.total > 0) {
        ChapterRepo.setPages(task.chapterId, task.total).catch((e: Error) => {
          hilog.warn(0x0001, 'Download', 'setPages failed for %{public}d: %{public}s', task.chapterId, e.message);
        });
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'download_failed';
      if (msg === 'network_blocked') {
        // 网络环境变化（如离开 Wi-Fi）：回到队列，网络恢复后自动续传
        task.state = 0;
        task.error = '';
      } else {
        task.state = 3;
        task.error = msg;
        // BT 组件缺失：置前台安装引导标志（用户未拒绝过时弹出 BtComponentDialog）
        if (msg === 'bt_component_required' &&
          AppStorage.get<boolean>(AppKeys.BT_ASK_DISMISSED) !== true) {
          AppStorage.setOrCreate(AppKeys.BT_COMPONENT_ASK, true);
        }
      }
      // 失败/取消仅清理半截 .tmp 文件，已完整落盘的页保留供重试/重启续传
      DownloadService.cleanupPartial(task.mangaId, task.chapterId);
    }
  }

  // 单章页面下载 worker：按共享游标领取下一页，直至取尽或被取消/阻断
  private static async pageWorker(task: DownloadTask, pages: SPage[], dir: string,
    imageHeaders: Record<string, string> | undefined, flags: DlFlags, cursor: PageCursor): Promise<void> {
    while (true) {
      const i = cursor.next;
      cursor.next += 1;
      if (i >= pages.length) {
        return;
      }
      if (flags.cancelled) {
        throw new Error('download_cancelled');
      }
      if (flags.blocked) {
        throw new Error('network_blocked');
      }
      const p = pages[i];
      const fileName = DownloadService.pad(p.index);
      const filePath = `${dir}/${fileName}.jpg`;
      if (!fileIo.accessSync(filePath)) {
        const buffer = await Http.getBuffer(p.url, imageHeaders);
        if (flags.cancelled) {
          throw new Error('download_cancelled');
        }
        if (flags.blocked) {
          throw new Error('network_blocked');
        }
        DownloadService.writePageFile(filePath, buffer);
        await DownloadService.splitTallIfNeeded(filePath);
      }
      task.progress += 1;
      DownloadService.notify();
      DownloadService.publishBgProgress(false);
    }
  }

  // 拆分超长条漫图片（对齐 Mihon splitTallImage）：超过阈值高度均分为多片 JPEG，
  // 全部切片落盘成功后删除原图；任一步失败保留原图不影响阅读
  private static async splitTallIfNeeded(filePath: string): Promise<void> {
    if (!Settings.getSplitTallImages()) {
      return;
    }
    let src: image.ImageSource | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    const slices: string[] = [];
    try {
      src = image.createImageSource(filePath);
      const info: image.ImageInfo = await src.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      if (w <= 0 || h <= TALL_IMAGE_LIMIT) {
        return;
      }
      const partCount = Math.ceil(h / TALL_IMAGE_LIMIT);
      const sliceH = Math.floor(h / partCount);
      packer = image.createImagePacker();
      const base = filePath.substring(0, filePath.length - 4);
      for (let i = 0; i < partCount; i++) {
        const top = i * sliceH;
        const height = i === partCount - 1 ? h - top : sliceH;
        const region: image.Region = { x: 0, y: top, size: { width: w, height: height } };
        const pm: image.PixelMap = await src.createPixelMap({ desiredRegion: region });
        const buf: ArrayBuffer = await packer.packing(pm, { format: 'image/jpeg', quality: 90 });
        const slicePath = `${base}__${DownloadService.pad(i + 1)}.jpg`;
        DownloadService.writePageFile(slicePath, buf);
        slices.push(slicePath);
        pm.release();
      }
      fileIo.unlinkSync(filePath);
    } catch (e) {
      for (const s of slices) {
        try {
          fileIo.unlinkSync(s);
        } catch (_e) {
        }
      }
      hilog.warn(0x0001, 'Download', 'split tall image failed: %{public}s', `${e}`);
    } finally {
      if (src !== undefined) {
        src.release();
      }
      if (packer !== undefined) {
        packer.release();
      }
    }
  }

  // CBZ 打包（对齐 Mihon archiveChapter）：页面目录压缩为 chapter.cbz 后删除零散页文件；
  // 打包失败保留文件夹形式，阅读路径不受影响
  private static async buildCbz(task: DownloadTask, dir: string): Promise<void> {
    if (!Settings.getSaveChaptersAsCbz()) {
      return;
    }
    let hasPage = false;
    const files = fileIo.listFileSync(dir);
    for (const f of files) {
      if (f.endsWith('.jpg')) {
        hasPage = true;
        break;
      }
    }
    if (!hasPage) {
      return;
    }
    const opts: zlib.Options = {
      level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
      memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
      strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
    };
    const tmp = `${DownloadService.rootDir}/tmp_cbz_${task.chapterId}.zip`;
    try {
      if (fileIo.accessSync(tmp)) {
        fileIo.unlinkSync(tmp);
      }
      await zlib.compressFile(dir, tmp, opts);
      for (const f of fileIo.listFileSync(dir)) {
        if (f.endsWith('.jpg')) {
          fileIo.unlinkSync(`${dir}/${f}`);
        }
      }
      const cbz = `${dir}/chapter.cbz`;
      if (fileIo.accessSync(cbz)) {
        fileIo.unlinkSync(cbz);
      }
      fileIo.renameSync(tmp, cbz);
    } catch (e) {
      try {
        if (fileIo.accessSync(tmp)) {
          fileIo.unlinkSync(tmp);
        }
      } catch (_e) {
      }
      hilog.warn(0x0001, 'Download', 'build cbz failed: %{public}s', `${e}`);
    }
  }

  // CBZ 读取：解压到 cacheDir/cbz_extract/{mangaId}/{chapterId}，extract.ok 标记完整性；
  // 缓存被系统清理或上次解压中断时自动重解
  private static async extractCbzPages(cbzPath: string, mangaId: number, chapterId: number): Promise<string[]> {
    const ctx = DownloadService.context;
    if (ctx === undefined) {
      throw new Error('download_not_ready');
    }
    const extractDir = `${ctx.cacheDir}/cbz_extract/${mangaId}/${chapterId}`;
    const markPath = `${extractDir}/extract.ok`;
    const opts: zlib.Options = {
      level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
      memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
      strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
    };
    try {
      if (!fileIo.accessSync(markPath)) {
        if (fileIo.accessSync(extractDir)) {
          DownloadService.rmdir(extractDir);
        }
        fileIo.mkdirSync(extractDir, true);
        await zlib.decompressFile(cbzPath, extractDir, opts);
        const fd = fileIo.openSync(markPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE).fd;
        fileIo.closeSync(fd);
      }
    } catch (e) {
      try {
        if (fileIo.accessSync(extractDir)) {
          DownloadService.rmdir(extractDir);
        }
      } catch (_e) {
      }
      throw new Error(`extract cbz failed: ${e}`);
    }
    return DownloadService.listImagesRecursive(extractDir);
  }

  // 递归列出目录下全部图片文件（解压产物可能是嵌套目录结构，按文件名排序保证页序）
  private static listImagesRecursive(dir: string): string[] {
    const out: string[] = [];
    try {
      if (!fileIo.accessSync(dir)) {
        return out;
      }
      const files = fileIo.listFileSync(dir).sort();
      for (const f of files) {
        const p = `${dir}/${f}`;
        let isDir = false;
        try {
          isDir = fileIo.statSync(p).isDirectory();
        } catch (_e) {
          continue;
        }
        if (isDir) {
          const nested = DownloadService.listImagesRecursive(p);
          for (const n of nested) {
            out.push(n);
          }
        } else if (DownloadService.isImageFile(f)) {
          out.push(p);
        }
      }
    } catch (e) {
      throw new Error(`list cbz images failed: ${e}`);
    }
    return out;
  }

  private static isImageFile(name: string): boolean {
    const lower = name.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') ||
      lower.endsWith('.webp') || lower.endsWith('.gif');
  }

  // 删除章节时同步清理 CBZ 解压缓存
  private static clearExtractCache(mangaId: number, chapterId: number): void {
    const ctx = DownloadService.context;
    if (ctx === undefined) {
      return;
    }
    const extractDir = `${ctx.cacheDir}/cbz_extract/${mangaId}/${chapterId}`;
    try {
      if (fileIo.accessSync(extractDir)) {
        DownloadService.rmdir(extractDir);
      }
    } catch (e) {
      hilog.warn(0x0001, 'Download', 'clear extract cache failed: %{public}s', `${e}`);
    }
  }

  private static async downloadNovel(task: DownloadTask, source: Source, flags: DlFlags): Promise<void> {
    const text = await source.getChapterText(task.chapterUrl);
    if (flags.cancelled) {
      throw new Error('download_cancelled');
    }
    if (flags.blocked) {
      throw new Error('network_blocked');
    }
    if (text === '') {
      throw new Error('no_content');
    }
    const dir = DownloadService.chapterDir(task.mangaId, task.chapterId);
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const path = `${dir}/chapter.txt`;
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
      const fd = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE).fd;
      try {
        fileIo.writeSync(fd, text);
      } finally {
        fileIo.closeSync(fd);
      }
    } catch (e) {
      throw new Error(`write novel file failed: ${e}`);
    }
    DownloadService.markDone(dir);
    if (DownloadService.doneIds !== undefined) {
      DownloadService.doneIds.add(task.chapterId);
    }
    task.total = 1;
    task.progress = 1;
    task.state = 2;
  }

  private static async downloadVideo(task: DownloadTask, source: Source, flags: DlFlags): Promise<void> {
    const videos: SVideo[] = await source.getVideoList(task.chapterUrl);
    if (flags.cancelled) {
      throw new Error('download_cancelled');
    }
    if (flags.blocked) {
      throw new Error('network_blocked');
    }
    if (videos.length === 0) {
      throw new Error('video_no_streams');
    }
    // 优先直链（单文件 + 系统级断点续传），无直链回退 m3u8 走 HLS 下载管线
    let chosen: SVideo | undefined = undefined;
    for (let i = 0; i < videos.length; i++) {
      if (!ContentType.isPlaylist(videos[i].url)) {
        chosen = videos[i];
        break;
      }
    }
    const dir = DownloadService.chapterDir(task.mangaId, task.chapterId);
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
    } catch (e) {
      throw new Error(`prepare video file failed: ${e}`);
    }
    // BT 链接（magnet / .torrent）：走 libtorrent 下载管线
    if (chosen !== undefined && DownloadService.isBtUrl(chosen.url)) {
      await DownloadService.downloadBt(task, chosen.url, dir, flags);
      return;
    }
    if (chosen === undefined) {
      // 多个 m3u8（多清晰度）时按清晰度标签选最优流，而非固定取第一个
      let stream: SVideo = videos[0];
      let bestScore = DownloadService.scoreQuality(stream.quality);
      for (let i = 1; i < videos.length; i++) {
        const s = DownloadService.scoreQuality(videos[i].quality);
        if (s > bestScore) {
          bestScore = s;
          stream = videos[i];
        }
      }
      await DownloadService.downloadHls(task, stream, dir, flags);
      return;
    }
    if (DownloadService.context === undefined) {
      throw new Error('download_not_ready');
    }
    const path = `${dir}/video.mp4`;
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (e) {
      throw new Error(`prepare video file failed: ${e}`);
    }
    task.total = 1;
    task.progress = 0;
    DownloadService.notify();
    const handle = Http.downloadToFile(DownloadService.context, chosen.url, chosen.headers, path);
    DownloadService.activeAborts.set(task.chapterId, (): void => {
      handle.cancel();
    });
    handle.setProgressCb((received: number, total: number): void => {
      if (total > 0 && task.total !== total) {
        task.total = total;
        DownloadService.notify();
      }
      // 视频任务 total/progress 为字节数：同步已接收字节数供进度条与实况窗百分比使用
      task.progress = received;
      DownloadService.publishBgProgress(false);
    });
    try {
      await handle.promise;
    } finally {
      DownloadService.activeAborts.delete(task.chapterId);
    }
    if (flags.cancelled) {
      throw new Error('download_cancelled');
    }
    if (flags.blocked) {
      throw new Error('network_blocked');
    }
    DownloadService.markDone(dir);
    if (DownloadService.doneIds !== undefined) {
      DownloadService.doneIds.add(task.chapterId);
    }
    // 完成态进度回满：避免"已完成"与空进度条/进度 1 同时展示
    if (task.total > 0) {
      task.progress = task.total;
    }
    task.state = 2;
  }

  // BT 链接判定：magnet URI 或 .torrent 直链
  static isBtUrl(url: string): boolean {
    const u = url.trim();
    if (u.startsWith('magnet:')) {
      return true;
    }
    const q = u.indexOf('?');
    const path = q >= 0 ? u.substring(0, q) : u;
    return path.toLowerCase().endsWith('.torrent');
  }

  // 无 tracker 的纯 infohash magnet（如 animegarden）在 DHT 引导受阻的网络下找不到
  // 任何 peer。追加动画生态常用的公开 tracker 作为兜底发现通道（原 swarm 若向这些
  // tracker 上报过即可命中；追加不影响 DHT 继续工作）。
  private static readonly BT_FALLBACK_TRACKERS: string[] = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.demonii.com:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.dler.org:6969/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://tracker.cyberia.is:6969/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'https://tr.bangumi.moe:9696/announce',
    'http://open.acgnxtracker.com:80/announce',
    'http://t.acg.rip:6699/announce',
    'http://t.nyaatracker.com:2710/announce'
  ];

  private static withFallbackTrackers(magnet: string): string {
    if (magnet.indexOf('tr=') >= 0) {
      return magnet;
    }
    let out = magnet;
    for (const tr of DownloadService.BT_FALLBACK_TRACKERS) {
      out += '&tr=' + encodeURIComponent(tr);
    }
    return out;
  }

  // BT 下载：magnet/.torrent → BtModule（torrent HSP 动态加载，libtorrent worker）。
  // 产物落 chapterDir（种子内部文件名/子目录由种子决定，localVideo 递归扫描定位）。
  // 重启恢复：队列恢复为 queued → 重走 downloadVideo → 同 savePath 重加种子 → re-check 续传，无需额外状态。
  // 取消：remove(key,false) 保留分片；完成：remove(key,false) 保留文件并停止做种。
  // 组件未装（AGC 按需分发）→ bt_component_required → process 置前台安装引导标志。
  private static async downloadBt(task: DownloadTask, url: string, dir: string, flags: DlFlags): Promise<void> {
    if (DownloadService.context === undefined) {
      throw new Error('download_not_ready');
    }
    if (!BtComponentInstaller.isInstalled()) {
      throw new Error('bt_component_required');
    }
    // 引擎级默认下载目录（savePath 兜底）；实际落盘以每任务 savePath 为准
    const btRoot = `${DownloadService.rootDir}/bt`;
    try {
      if (!fileIo.accessSync(btRoot)) {
        fileIo.mkdirSync(btRoot, true);
      }
    } catch (e) {
      throw new Error(`prepare bt dir failed: ${e}`);
    }
    // ensureStarted 内动态 import + 引擎启动，任一失败归一为 bt_component_required
    await BtModule.ensureStarted(btRoot);
    let key = -1;
    if (url.startsWith('magnet:')) {
      key = await BtModule.addMagnet(DownloadService.withFallbackTrackers(url), dir);
    } else {
      const bytes = await Http.getBuffer(url, undefined);
      key = await BtModule.addTorrentFile(new Uint8Array(bytes), dir);
    }
    DownloadService.btKeys.set(task.chapterId, key);
    // metadata 就绪前 total=1 防除零；就绪后为字节数（与直链视频语义一致）
    task.total = 1;
    task.progress = 0;
    DownloadService.notify();
    DownloadService.activeAborts.set(task.chapterId, (): void => {
      // 主动取消：移除任务但保留已下载分片（重试/重启 re-check 续传）
      BtModule.remove(key, false).catch((): void => {
      });
    });
    try {
      while (true) {
        if (flags.cancelled) {
          throw new Error('download_cancelled');
        }
        if (flags.blocked) {
          throw new Error('network_blocked');
        }
        const st = await BtModule.status(key);
        if (st.error !== undefined && st.error !== '') {
          throw new Error(`bt_error: ${st.error}`);
        }
        if (st.hasMetadata && st.totalWanted > 0) {
          task.total = st.totalWanted;
          task.progress = st.totalDone;
        }
        DownloadService.notify();
        DownloadService.publishBgProgress(false);
        if (st.isFinished) {
          break;
        }
        await new Promise<void>((resolve: () => void) => {
          setTimeout(resolve, 1000);
        });
      }
    } finally {
      DownloadService.activeAborts.delete(task.chapterId);
      DownloadService.btKeys.delete(task.chapterId);
    }
    if (flags.cancelled) {
      throw new Error('download_cancelled');
    }
    if (flags.blocked) {
      throw new Error('network_blocked');
    }
    // 完成即移除（保留文件）：不做种、不占会话句柄
    await BtModule.remove(key, false);
    DownloadService.markDone(dir);
    if (DownloadService.doneIds !== undefined) {
      DownloadService.doneIds.add(task.chapterId);
    }
    if (task.total > 0) {
      task.progress = task.total;
    }
    task.state = 2;
  }

  // m3u8 下载：HLS 管线（解析 → 多码率选择 → 分片下载 → AES-128 解密 → 合并），
  // 进度按分片计数（total/progress 为分片数）
  private static async downloadHls(task: DownloadTask, stream: SVideo, dir: string,
    flags: DlFlags): Promise<void> {
    // 清理上次中断留下的半截产物，避免与本次输出（video.ts/video.mp4）混存
    const staleFiles: string[] = ['video.mp4', 'video.ts'];
    for (const stale of staleFiles) {
      try {
        if (fileIo.accessSync(`${dir}/${stale}`)) {
          fileIo.unlinkSync(`${dir}/${stale}`);
        }
      } catch (_e) {
      }
    }
    task.total = 0;
    task.progress = 0;
    await HlsDownloader.download(stream.url, stream.headers, dir,
      (done: number, total: number): void => {
        task.total = total;
        task.progress = done;
        DownloadService.notify();
        DownloadService.publishBgProgress(false);
      },
      (): string => {
        if (flags.cancelled) {
          return 'cancelled';
        }
        if (flags.blocked) {
          return 'blocked';
        }
        return '';
      });
    if (flags.cancelled) {
      throw new Error('download_cancelled');
    }
    if (flags.blocked) {
      throw new Error('network_blocked');
    }
    DownloadService.markDone(dir);
    if (DownloadService.doneIds !== undefined) {
      DownloadService.doneIds.add(task.chapterId);
    }
    // 完成态进度回满（分片数计满），避免"已完成"与"进度 1"同时展示
    if (task.total > 0) {
      task.progress = task.total;
    }
    task.state = 2;
  }

  // 清晰度标签打分：数字清晰度（1080p/720p 等）优先，中文档位与关键词次之，
  // 无法识别返回 0；仅用于多个 m3u8 流之间的相对排序
  private static scoreQuality(label: string): number {
    const l = label.toLowerCase();
    const withP = l.match(/([0-9]{3,4})p/);
    if (withP !== null && withP.length > 1) {
      return parseInt(withP[1], 10);
    }
    // 独立数字（排除 h264/x265 等编码名前缀）
    const plain = l.match(/(?:^|[^a-z0-9.])([0-9]{3,4})(?:$|[^0-9])/);
    if (plain !== null && plain.length > 1) {
      return parseInt(plain[1], 10);
    }
    if (l.indexOf('4k') >= 0 || l.indexOf('2160') >= 0) {
      return 2160;
    }
    if (l.indexOf('蓝光') >= 0 || l.indexOf('bluray') >= 0 || l.indexOf('blu-ray') >= 0) {
      return 1440;
    }
    if (l.indexOf('超清') >= 0 || l.indexOf('超高清') >= 0) {
      return 1080;
    }
    if (l.indexOf('高清') >= 0 || l.indexOf('hd') >= 0) {
      return 720;
    }
    if (l.indexOf('标清') >= 0 || l.indexOf('sd') >= 0) {
      return 480;
    }
    if (l.indexOf('流畅') >= 0) {
      return 360;
    }
    return 0;
  }

  private static markDone(dir: string): void {
    try {
      const markFd = fileIo.openSync(`${dir}/done.mark`, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE).fd;
      fileIo.closeSync(markFd);
    } catch (e) {
      throw new Error(`mark done failed: ${e}`);
    }
  }

  // 失败/取消时清理章节内的半截 .tmp 文件（完整页文件保留，供续传）
  private static cleanupPartial(mangaId: number, chapterId: number): void {
    if (DownloadService.rootDir === '') {
      return;
    }
    const dir = DownloadService.chapterDir(mangaId, chapterId);
    DownloadService.cleanTmpFiles(dir);
  }

  // 原子写单页：先写 .tmp 再改名落位，进程任意时刻被杀都不会留下半截正式页文件，
  // 从而重启后可按"文件存在即完整"安全断点续传
  private static writePageFile(path: string, buffer: ArrayBuffer): void {
    const tmp = `${path}.tmp`;
    let fd: number = -1;
    try {
      fd = fileIo.openSync(tmp,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC).fd;
      fileIo.writeSync(fd, buffer);
    } catch (e) {
      throw new Error(`write_page_failed: ${e}`);
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd);
        } catch (e) {
        }
      }
    }
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
      fileIo.renameSync(tmp, path);
    } catch (e) {
      throw new Error(`write_page_failed: ${e}`);
    }
  }

  // 清理目录内残留的半截 .tmp 文件
  private static cleanTmpFiles(dir: string): void {
    try {
      if (!fileIo.accessSync(dir)) {
        return;
      }
      const files = fileIo.listFileSync(dir);
      for (const f of files) {
        if (f.endsWith('.tmp')) {
          fileIo.unlinkSync(`${dir}/${f}`);
        }
      }
    } catch (e) {
    }
  }

  // 删除编号超出当前页数的旧页文件（页列表缩短场景，避免旧图混入）
  private static removeStalePages(dir: string, pageCount: number): void {
    try {
      if (!fileIo.accessSync(dir)) {
        return;
      }
      const files = fileIo.listFileSync(dir);
      for (const f of files) {
        if (!f.endsWith('.jpg')) {
          continue;
        }
        const idx = parseInt(f.substring(0, f.length - 4), 10);
        if (!Number.isNaN(idx) && idx >= pageCount) {
          fileIo.unlinkSync(`${dir}/${f}`);
        }
      }
    } catch (e) {
    }
  }

  private static pad(index: number): string {
    const s = `${index}`;
    if (s.length >= 3) {
      return s;
    }
    let out = s;
    while (out.length < 3) {
      out = `0${out}`;
    }
    return out;
  }

  // ---------------- DATA_TRANSFER 长时任务（真机锁屏/后台续传） ----------------

  // 队列有任务要执行时申请 DATA_TRANSFER 长时任务（API 21+ 多任务接口，与听书 AUDIO_PLAYBACK 互不影响）
  private static ensureBgTask(): void {
    if (DownloadService.bgTaskId >= 0 || DownloadService.bgRequesting) {
      return;
    }
    const ctx = DownloadService.context;
    if (ctx === undefined) {
      return;
    }
    DownloadService.bgRequesting = true;
    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: ctx.abilityInfo.bundleName,
          abilityName: ctx.abilityInfo.name
        }
      ],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0
    };
    wantAgent.getWantAgent(info).then((agent: WantAgent): Promise<backgroundTaskManager.ContinuousTaskNotification> => {
      const req = new backgroundTaskManager.ContinuousTaskRequest();
      req.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_DATA_TRANSFER];
      req.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_LIVE_VIEW_NOTIFICATION];
      req.wantAgent = agent;
      return backgroundTaskManager.startBackgroundRunning(ctx, req);
    }).then((res: backgroundTaskManager.ContinuousTaskNotification): void => {
      DownloadService.bgRequesting = false;
      if (res.continuousTaskId === undefined) {
        hilog.warn(0x0001, 'Download', 'dataTransfer task created without id');
        return;
      }
      DownloadService.bgTaskId = res.continuousTaskId;
      DownloadService.bgNotifId = res.notificationId;
      DownloadService.startBgHeartbeat();
      // 通知授权未开时实况窗进度更新会失败（任务10分钟后被系统取消），前台弹授权引导
      notificationManager.isNotificationEnabled().then((enabled: boolean): void => {
        if (enabled) {
          return;
        }
        notificationManager.requestEnableNotification(ctx).catch((_e: BusinessError): void => {
        });
      }).catch((_e: BusinessError): void => {
      });
      DownloadService.publishBgProgress(true);
    }).catch((e: BusinessError): void => {
      DownloadService.bgRequesting = false;
      hilog.warn(0x0001, 'Download', 'request dataTransfer task failed: %{public}d %{public}s', e.code, e.message);
    });
  }

  // 队列再无排队/进行中任务时按 id 定点撤销长时任务（不影响听书等其他长时任务）
  private static releaseBgTaskIfIdle(): void {
    for (const t of DownloadService.queue) {
      if (t.state === 0 || t.state === 1) {
        return;
      }
    }
    const ctx = DownloadService.context;
    const taskId = DownloadService.bgTaskId;
    DownloadService.resetBgTask();
    if (ctx === undefined || taskId < 0) {
      return;
    }
    backgroundTaskManager.stopBackgroundRunning(ctx, taskId).catch((e: BusinessError): void => {
      hilog.warn(0x0001, 'Download', 'stop dataTransfer task failed: %{public}d %{public}s', e.code, e.message);
    });
  }

  private static resetBgTask(): void {
    if (DownloadService.bgHeartbeat >= 0) {
      clearInterval(DownloadService.bgHeartbeat);
      DownloadService.bgHeartbeat = -1;
    }
    DownloadService.bgTaskId = -1;
    DownloadService.bgNotifId = -1;
    DownloadService.bgLastPct = -1;
  }

  // 实况窗进度心跳：DATA_TRANSFER 要求持续更新进度，30秒兜底刷新防止任务被系统取消
  private static startBgHeartbeat(): void {
    if (DownloadService.bgHeartbeat >= 0) {
      return;
    }
    DownloadService.bgHeartbeat = setInterval((): void => {
      DownloadService.publishBgProgress(true);
    }, 30000);
  }

  // 以长时任务返回的通知 id 更新实况窗下载进度（downloadTemplate）；
  // force=true 跳过百分比去重，供心跳续期与新章节标题刷新使用
  private static publishBgProgress(force: boolean): void {
    if (DownloadService.bgNotifId < 0) {
      return;
    }
    const task = DownloadService.queue.find((t: DownloadTask): boolean => t.state === 1);
    if (task === undefined) {
      return;
    }
    let pct = 0;
    if (task.total > 0) {
      pct = Math.floor(task.progress * 100 / task.total);
      // 完成态由任务结束后的长时任务撤销清理，进度环不提前消失
      if (pct > 99) {
        pct = 99;
      }
    }
    if (!force && pct === DownloadService.bgLastPct) {
      return;
    }
    DownloadService.bgLastPct = pct;
    // 隐藏通知内容（隐私设置）：不显示作品/章节名，标题用占位文案
    let notifTitle: string = task.mangaTitle;
    let notifText: string = task.chapterName;
    if (Settings.getHideNotificationContent()) {
      notifTitle = '•••';
      notifText = '•••';
      const ctx = DownloadService.context;
      if (ctx !== undefined) {
        try {
          notifTitle = ctx.resourceManager.getStringSync($r('app.string.privacy_dl_title').id);
        } catch (_e) {
        }
      }
    }
    const template: notificationManager.NotificationTemplate = {
      name: 'downloadTemplate',
      data: {
        'title': notifTitle,
        'fileName': notifText,
        'progressValue': pct
      }
    };
    const request: notificationManager.NotificationRequest = {
      id: DownloadService.bgNotifId,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
        systemLiveView: {
          typeCode: 8,
          title: notifTitle,
          text: notifText
        }
      },
      notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
      template: template
    };
    notificationManager.publish(request).catch((e: BusinessError): void => {
      hilog.warn(0x0001, 'Download', 'publish live view progress failed: %{public}d %{public}s', e.code, e.message);
    });
  }

  // ---------------- 队列持久化（关闭应用后重开继续下载） ----------------

  // 队列/暂停态变更时原子落盘；完成态任务不持久化（done.mark 为准）
  private static persistQueue(): void {
    const file = DownloadService.queueFile;
    if (file === '') {
      return;
    }
    try {
      const raw = new DownloadQueueRaw();
      raw.paused = DownloadService.paused;
      for (const t of DownloadService.queue) {
        if (t.state === 2) {
          continue;
        }
        const r = new DownloadTaskRaw();
        r.mangaId = t.mangaId;
        r.mangaTitle = t.mangaTitle;
        r.chapterId = t.chapterId;
        r.chapterName = t.chapterName;
        r.chapterNumber = t.chapterNumber;
        r.dateUpload = t.dateUpload;
        r.sourceKey = t.sourceKey;
        r.mangaUrl = t.mangaUrl;
        r.chapterUrl = t.chapterUrl;
        r.state = t.state;
        r.progress = t.progress;
        r.total = t.total;
        r.error = t.error;
        raw.tasks.push(r);
      }
      const tmp = `${file}.tmp`;
      const fd = fileIo.openSync(tmp,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC).fd;
      try {
        fileIo.writeSync(fd, JSON.stringify(raw));
      } finally {
        fileIo.closeSync(fd);
      }
      if (fileIo.accessSync(file)) {
        fileIo.unlinkSync(file);
      }
      fileIo.renameSync(tmp, file);
    } catch (e) {
      hilog.warn(0x0001, 'Download', 'persist queue failed: %{public}s', `${e}`);
    }
  }

  // 启动时恢复持久化队列：下载中(1)重新排队，失败(3)保留可重试；
  // 已有 done.mark 的任务丢弃（完成态以磁盘为准）
  private static loadQueue(): void {
    const file = DownloadService.queueFile;
    if (file === '') {
      return;
    }
    try {
      if (!fileIo.accessSync(file)) {
        return;
      }
      const stat = fileIo.statSync(file);
      if (stat.size <= 0) {
        return;
      }
      let text = '';
      const fd = fileIo.openSync(file, fileIo.OpenMode.READ_ONLY).fd;
      try {
        const buf = new ArrayBuffer(stat.size);
        fileIo.readSync(fd, buf);
        text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      } finally {
        fileIo.closeSync(fd);
      }
      const raw = JSON.parse(text) as DownloadQueueRaw;
      if (raw === null || typeof raw !== 'object' || !Array.isArray(raw.tasks)) {
        return;
      }
      DownloadService.paused = raw.paused === true;
      const restored: DownloadTask[] = [];
      for (const r of raw.tasks) {
        if (typeof r.chapterId !== 'number' || typeof r.sourceKey !== 'string' ||
          typeof r.chapterUrl !== 'string' || r.chapterUrl === '') {
          continue;
        }
        if (DownloadService.isDownloaded(r.chapterId)) {
          continue;
        }
        const t = new DownloadTask();
        t.mangaId = typeof r.mangaId === 'number' ? r.mangaId : 0;
        t.mangaTitle = typeof r.mangaTitle === 'string' ? r.mangaTitle : '';
        t.chapterId = r.chapterId;
        t.chapterName = typeof r.chapterName === 'string' ? r.chapterName : '';
        t.chapterNumber = typeof r.chapterNumber === 'number' ? r.chapterNumber : 0;
        t.dateUpload = typeof r.dateUpload === 'number' ? r.dateUpload : 0;
        t.sourceKey = r.sourceKey;
        t.mangaUrl = typeof r.mangaUrl === 'string' ? r.mangaUrl : '';
        t.chapterUrl = r.chapterUrl;
        t.state = r.state === 3 ? 3 : 0;
        t.progress = typeof r.progress === 'number' ? r.progress : 0;
        t.total = typeof r.total === 'number' ? r.total : 0;
        t.error = t.state === 3 && typeof r.error === 'string' ? r.error : '';
        restored.push(t);
      }
      DownloadService.queue = restored;
      if (restored.length > 0) {
        hilog.info(0x0001, 'Download', 'restored %{public}d queue tasks, paused=%{public}s',
          restored.length, `${DownloadService.paused}`);
      }
      DownloadService.notify();
    } catch (e) {
      hilog.warn(0x0001, 'Download', 'load queue failed: %{public}s', `${e}`);
    }
  }

  // 单次目录遍历构建 done.mark 索引
  private static rebuildDoneIndex(): void {
    const set = new Set<number>();
    try {
      if (DownloadService.rootDir !== '' && fileIo.accessSync(DownloadService.rootDir)) {
        const mangaDirs = fileIo.listFileSync(DownloadService.rootDir);
        for (const md of mangaDirs) {
          const mangaPath = `${DownloadService.rootDir}/${md}`;
          if (!fileIo.accessSync(mangaPath)) {
            continue;
          }
          const chapterDirs = fileIo.listFileSync(mangaPath);
          for (const cd of chapterDirs) {
            if (fileIo.accessSync(`${mangaPath}/${cd}/done.mark`)) {
              const chapterId = parseInt(cd, 10);
              if (chapterId > 0) {
                set.add(chapterId);
              }
            }
          }
        }
      }
    } catch (e) {
      throw new Error(`rebuild done index failed: ${e}`);
    }
    DownloadService.doneIds = set;
  }

  private static rmdir(path: string): void {
    try {
      if (!fileIo.accessSync(path)) {
        return;
      }
      const stat = fileIo.statSync(path);
      if (stat.isDirectory()) {
        const children = fileIo.listFileSync(path);
        for (const c of children) {
          DownloadService.rmdir(`${path}/${c}`);
        }
        fileIo.rmdirSync(path);
      } else {
        fileIo.unlinkSync(path);
      }
    } catch (e) {
      throw new Error(`rmdir ${path} failed: ${e}`);
    }
  }

  private static async chapterNames(mangaId: number, chapterId: number): Promise<string[]> {
    try {
      const chapter = await ChapterRepo.getById(chapterId);
      if (chapter !== undefined) {
        const manga = await MangaRepo.get(mangaId);
        const mangaTitle = manga !== undefined ? manga.title : `#${mangaId}`;
        return [mangaTitle, chapter.name];
      }
    } catch (e) {
      hilog.warn(0x0001, 'Download', 'chapterNames failed for %{public}d', chapterId);
    }
    return [`#${mangaId}`, `#${chapterId}`];
  }
}
