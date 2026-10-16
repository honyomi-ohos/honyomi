import { fileIo } from '@kit.CoreFileKit';
import type { WantAgent } from '@kit.AbilityKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { Http } from '../net/Http';
import { Source, SourceRegistry } from '../source/Source';
import { ContentType, DownloadedChapter, DownloadedManga, DownloadTask, SPage, SVideo } from '../model/Models';
import { ChapterRepo, MangaRepo } from './Repos';

// 队列持久化 JSON 结构（{filesDir}/download_queue.json）：
// 完成态不落盘（done.mark 为准），下载中(state=1)重启后重新排队，失败态保留供重试
class DownloadTaskRaw {
  mangaId: number = 0;
  mangaTitle: string = '';
  chapterId: number = 0;
  chapterName: string = '';
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

// 下载服务（对齐 Mihon DownloadManager 的精简版）
// 存储布局: {filesDir}/downloads/{mangaId}/{chapterId}/000.jpg ... + done.mark
export class DownloadService {
  private static rootDir: string = '';
  private static queueFile: string = '';
  private static context: common.UIAbilityContext | undefined = undefined;
  private static queue: DownloadTask[] = [];
  private static running: boolean = false;
  private static paused: boolean = false;
  private static listeners: Array<() => void> = [];
  private static activeCancel: (() => void) | undefined = undefined;
  // 已完成(done.mark)章节 id 内存索引：列表行高频查询 isDownloaded，
  // 不能每次调用都做 O(N) 目录扫描；下载完成/删除章节时增量维护
  private static doneIds: Set<number> | undefined = undefined;
  // 当前正在 process 的任务（deleteChapter 等待其退出用）
  private static activeTask: DownloadTask | undefined = undefined;
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

  // 取消任务：排队中直接移除；下载中（视频中断传输，图片/小说置状态后由下载循环检查中止）
  static cancel(chapterId: number): void {
    let hasActive = false;
    for (const t of DownloadService.queue) {
      if (t.chapterId !== chapterId) {
        continue;
      }
      if (t.state === 1) {
        hasActive = true;
      }
      if (t.state !== 3) {
        t.state = 3;
        t.error = 'download_cancelled';
      }
    }
    if (hasActive && DownloadService.activeCancel !== undefined) {
      DownloadService.activeCancel();
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
    let hasActive = false;
    for (const t of DownloadService.queue) {
      if (t.state === 1) {
        hasActive = true;
      }
      if (t.state !== 3) {
        t.state = 3;
        t.error = 'download_cancelled';
      }
    }
    if (hasActive && DownloadService.activeCancel !== undefined) {
      DownloadService.activeCancel();
    }
    DownloadService.queue = [];
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  // 按章节 id 升/降序重排整个队列（对齐 Mihon "Order by chapter number" 的近似实现）
  static sortQueue(asc: boolean): void {
    const sorted: DownloadTask[] = DownloadService.queue.slice()
      .sort((a: DownloadTask, b: DownloadTask): number => {
        return asc ? a.chapterId - b.chapterId : b.chapterId - a.chapterId;
      });
    DownloadService.queue = sorted;
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

  // 暂停：当前任务继续跑完，不再启动新任务
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

  // 置顶/移底：仅对排队中(state=0)的任务生效
  static moveToTop(chapterId: number): void {
    const task = DownloadService.queue.find((t: DownloadTask) => t.chapterId === chapterId && t.state === 0);
    if (task === undefined) {
      return;
    }
    DownloadService.queue = DownloadService.queue.filter((t: DownloadTask) => t !== task);
    DownloadService.queue.unshift(task);
    DownloadService.persistQueue();
    DownloadService.notify();
  }

  static moveToBottom(chapterId: number): void {
    const task = DownloadService.queue.find((t: DownloadTask) => t.chapterId === chapterId && t.state === 0);
    if (task === undefined) {
      return;
    }
    DownloadService.queue = DownloadService.queue.filter((t: DownloadTask) => t !== task);
    DownloadService.queue.push(task);
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
    DownloadService.persistQueue();
    DownloadService.notify();
    DownloadService.pump();
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
    const path = `${DownloadService.chapterDir(mangaId, chapterId)}/video.mp4`;
    try {
      if (DownloadService.rootDir !== '' && fileIo.accessSync(path)) {
        return path;
      }
    } catch (e) {
      throw new Error(`check local video failed: ${e}`);
    }
    return '';
  }

  static localPages(mangaId: number, chapterId: number): string[] {
    const dir = DownloadService.chapterDir(mangaId, chapterId);
    try {
      if (!fileIo.accessSync(dir)) {
        return [];
      }
      const files = fileIo.listFileSync(dir);
      const pages = files.filter((f: string) => f !== 'done.mark' && f !== 'chapter.txt' && f !== 'video.mp4').sort();
      const result: string[] = [];
      for (const f of pages) {
        result.push(`${dir}/${f}`);
      }
      return result;
    } catch (e) {
      throw new Error(`list local pages failed: ${e}`);
    }
  }

  // 删除章节本地文件：先取消并等待活动下载任务退出，避免删除与写入并发产生半截文件
  static async deleteChapter(mangaId: number, chapterId: number): Promise<void> {
    const active = DownloadService.queue.find((t: DownloadTask) => t.chapterId === chapterId && t.state === 1);
    DownloadService.cancel(chapterId);
    if (active !== undefined) {
      await new Promise<void>((resolve: () => void) => {
        const timer = setInterval((): void => {
          if (DownloadService.activeTask !== active) {
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

  private static notify(): void {
    const snapshot = DownloadService.listeners.slice();
    for (const fn of snapshot) {
      fn();
    }
  }

  private static pump(): void {
    if (DownloadService.running || DownloadService.paused) {
      return;
    }
    const next = DownloadService.queue.find((t: DownloadTask) => t.state === 0);
    if (next === undefined) {
      return;
    }
    DownloadService.ensureBgTask();
    DownloadService.running = true;
    DownloadService.activeTask = next;
    DownloadService.process(next).then(() => {
      DownloadService.running = false;
      DownloadService.activeTask = undefined;
      DownloadService.activeCancel = undefined;
      DownloadService.persistQueue();
      DownloadService.releaseBgTaskIfIdle();
      DownloadService.notify();
      DownloadService.pump();
    }).catch((e: Error) => {
      hilog.error(0x0001, 'Download', 'process failed: %{public}s', e.message);
      DownloadService.running = false;
      DownloadService.activeTask = undefined;
      DownloadService.activeCancel = undefined;
      DownloadService.persistQueue();
      DownloadService.releaseBgTaskIfIdle();
      DownloadService.notify();
      DownloadService.pump();
    });
  }

  private static async process(task: DownloadTask): Promise<void> {
    task.state = 1;
    task.progress = 0;
    task.error = '';
    // 图片/文本下载也注册取消回调（对齐 downloadVideo 的 activeCancel 模式）：
    // cancel() 置状态后由下载循环/await 续体每轮检查 task.state 中止
    DownloadService.activeCancel = (): void => {
      task.state = 3;
      task.error = 'download_cancelled';
    };
    DownloadService.notify();
    DownloadService.publishBgProgress(true);
    try {
      const source = SourceRegistry.get(task.sourceKey);
      if (source === undefined) {
        throw new Error(`source_not_found|${task.sourceKey}`);
      }
      if (source.contentType === ContentType.NOVEL) {
        await DownloadService.downloadNovel(task, source);
        return;
      }
      if (source.contentType === ContentType.VIDEO) {
        await DownloadService.downloadVideo(task, source);
        return;
      }
      const pages: SPage[] = await source.getPageList(task.chapterUrl);
      if (task.state === 3) {
        throw new Error('download_cancelled');
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
      for (const p of pages) {
        if (task.state === 3) {
          throw new Error('download_cancelled');
        }
        const fileName = DownloadService.pad(p.index);
        const filePath = `${dir}/${fileName}.jpg`;
        if (!fileIo.accessSync(filePath)) {
          const buffer = await Http.getBuffer(p.url, imageHeaders);
          DownloadService.writePageFile(filePath, buffer);
        }
        task.progress += 1;
        DownloadService.notify();
        DownloadService.publishBgProgress(false);
      }
      // 页列表比上次短时清理超出的多余编号页，避免旧图混入本地阅读
      DownloadService.removeStalePages(dir, pages.length);
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
      task.state = 3;
      task.error = e instanceof Error ? e.message : 'download_failed';
      // 失败/取消仅清理半截 .tmp 文件，已完整落盘的页保留供重试/重启续传
      DownloadService.cleanupPartial(task.mangaId, task.chapterId);
    }
  }

  private static async downloadNovel(task: DownloadTask, source: Source): Promise<void> {
    const text = await source.getChapterText(task.chapterUrl);
    if (task.state === 3) {
      throw new Error('download_cancelled');
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

  private static async downloadVideo(task: DownloadTask, source: Source): Promise<void> {
    const videos: SVideo[] = await source.getVideoList(task.chapterUrl);
    if (task.state === 3) {
      throw new Error('download_cancelled');
    }
    let chosen: SVideo | undefined = undefined;
    for (let i = 0; i < videos.length; i++) {
      if (!ContentType.isPlaylist(videos[i].url)) {
        chosen = videos[i];
        break;
      }
    }
    if (chosen === undefined) {
      throw new Error('stream_only');
    }
    if (DownloadService.context === undefined) {
      throw new Error('download_not_ready');
    }
    const dir = DownloadService.chapterDir(task.mangaId, task.chapterId);
    const path = `${dir}/video.mp4`;
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
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
    DownloadService.activeCancel = (): void => {
      handle.cancel();
    };
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
      DownloadService.activeCancel = undefined;
    }
    DownloadService.markDone(dir);
    if (DownloadService.doneIds !== undefined) {
      DownloadService.doneIds.add(task.chapterId);
    }
    task.progress = 1;
    task.state = 2;
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
    const template: notificationManager.NotificationTemplate = {
      name: 'downloadTemplate',
      data: {
        'title': task.mangaTitle,
        'fileName': task.chapterName,
        'progressValue': pct
      }
    };
    const request: notificationManager.NotificationRequest = {
      id: DownloadService.bgNotifId,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
        systemLiveView: {
          typeCode: 8,
          title: task.mangaTitle,
          text: task.chapterName
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
