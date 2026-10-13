import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Http } from '../net/Http';
import { SourceRegistry, Source } from '../source/Source';
import { DownloadTask, DownloadedChapter, DownloadedManga, SPage, SVideo, ContentType } from '../model/Models';
import { ChapterRepo } from './Repos';
import { MangaRepo } from './Repos';

// 下载服务（对齐 Mihon DownloadManager 的精简版）
// 存储布局: {filesDir}/downloads/{mangaId}/{chapterId}/000.jpg ... + done.mark
export class DownloadService {
  private static rootDir: string = '';
  private static context: common.UIAbilityContext | undefined = undefined;
  private static queue: DownloadTask[] = [];
  private static running: boolean = false;
  private static paused: boolean = false;
  private static listeners: Array<() => void> = [];
  private static activeCancel: (() => void) | undefined = undefined;
  // 已完成(done.mark)章节 id 内存索引：列表行高频查询 isDownloaded，
  // 不能每次调用都做 O(N) 目录扫描；下载完成/删除章节时增量维护
  private static doneIds: Set<number> | undefined = undefined;

  static init(context: common.UIAbilityContext): void {
    DownloadService.context = context;
    DownloadService.rootDir = `${context.filesDir}/downloads`;
    if (!fileIo.accessSync(DownloadService.rootDir)) {
      fileIo.mkdirSync(DownloadService.rootDir, true);
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

  private static notify(): void {
    const snapshot = DownloadService.listeners.slice();
    for (const fn of snapshot) {
      fn();
    }
  }

  static getQueue(): DownloadTask[] {
    return DownloadService.queue;
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
    DownloadService.notify();
    DownloadService.pump();
  }

  // 取消任务：排队中直接移除；下载中（如视频）中断当前传输
  static cancel(chapterId: number): void {
    for (const t of DownloadService.queue) {
      if (t.chapterId === chapterId && t.state !== 1) {
        t.state = 3;
        t.error = '已取消';
      }
    }
    const active = DownloadService.queue.find((t: DownloadTask) => t.chapterId === chapterId && t.state === 1);
    if (active !== undefined && DownloadService.activeCancel !== undefined) {
      DownloadService.activeCancel();
    }
    DownloadService.queue = DownloadService.queue.filter((t: DownloadTask) => t.state !== 3);
    DownloadService.notify();
  }

  static clearFinished(): void {
    DownloadService.queue = DownloadService.queue.filter((t: DownloadTask) => t.state !== 2 && t.state !== 3);
    DownloadService.notify();
  }

  // 暂停：当前任务继续跑完，不再启动新任务
  static pauseAll(): void {
    DownloadService.paused = true;
    DownloadService.notify();
  }

  static resumeAll(): void {
    DownloadService.paused = false;
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
    DownloadService.notify();
  }

  static moveToBottom(chapterId: number): void {
    const task = DownloadService.queue.find((t: DownloadTask) => t.chapterId === chapterId && t.state === 0);
    if (task === undefined) {
      return;
    }
    DownloadService.queue = DownloadService.queue.filter((t: DownloadTask) => t !== task);
    DownloadService.queue.push(task);
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
    DownloadService.notify();
    DownloadService.pump();
  }

  private static pump(): void {
    if (DownloadService.running || DownloadService.paused) {
      return;
    }
    const next = DownloadService.queue.find((t: DownloadTask) => t.state === 0);
    if (next === undefined) {
      return;
    }
    DownloadService.running = true;
    DownloadService.process(next).then(() => {
      DownloadService.running = false;
      DownloadService.activeCancel = undefined;
      DownloadService.notify();
      DownloadService.pump();
    }).catch((e: Error) => {
      hilog.error(0x0001, 'Download', 'process failed: %{public}s', e.message);
      DownloadService.running = false;
      DownloadService.activeCancel = undefined;
      DownloadService.notify();
      DownloadService.pump();
    });
  }

  private static async process(task: DownloadTask): Promise<void> {
    task.state = 1;
    task.progress = 0;
    task.error = '';
    DownloadService.notify();
    try {
      const source = SourceRegistry.get(task.sourceKey);
      if (source === undefined) {
        throw new Error(`source not found: ${task.sourceKey}`);
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
      task.total = pages.length;
      DownloadService.notify();
      const imageHeaders = source.imageRequestHeaders();
      const dir = DownloadService.chapterDir(task.mangaId, task.chapterId);
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      for (const p of pages) {
        const fileName = DownloadService.pad(p.index);
        const filePath = `${dir}/${fileName}.jpg`;
        if (!fileIo.accessSync(filePath)) {
          const buffer = await Http.getBuffer(p.url, imageHeaders);
          const fd = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE).fd;
          try {
            fileIo.writeSync(fd, buffer);
          } finally {
            fileIo.closeSync(fd);
          }
        }
        task.progress += 1;
        DownloadService.notify();
      }
      const markFd = fileIo.openSync(`${dir}/done.mark`,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE).fd;
      fileIo.closeSync(markFd);
      if (DownloadService.doneIds !== undefined) {
        DownloadService.doneIds.add(task.chapterId);
      }
      task.state = 2;
      if (task.total > 0) {
        ChapterRepo.setPages(task.chapterId, task.total).catch(() => {
        });
      }
    } catch (e) {
      task.state = 3;
      task.error = e instanceof Error ? e.message : '下载失败';
    }
  }

  private static async downloadNovel(task: DownloadTask, source: Source): Promise<void> {
    const text = await source.getChapterText(task.chapterUrl);
    if (text === '') {
      throw new Error('章节没有正文');
    }
    const dir = DownloadService.chapterDir(task.mangaId, task.chapterId);
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
    let chosen: SVideo | undefined = undefined;
    for (let i = 0; i < videos.length; i++) {
      if (!ContentType.isPlaylist(videos[i].url)) {
        chosen = videos[i];
        break;
      }
    }
    if (chosen === undefined) {
      throw new Error('该视频是在线串流，不能下载');
    }
    if (DownloadService.context === undefined) {
      throw new Error('下载服务未初始化');
    }
    const dir = DownloadService.chapterDir(task.mangaId, task.chapterId);
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
    const path = `${dir}/video.mp4`;
    if (fileIo.accessSync(path)) {
      fileIo.unlinkSync(path);
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
    const markFd = fileIo.openSync(`${dir}/done.mark`, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE).fd;
    fileIo.closeSync(markFd);
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

  static chapterDir(mangaId: number, chapterId: number): string {
    return `${DownloadService.rootDir}/${mangaId}/${chapterId}`;
  }

  // 已下载漫画的 id 列表（downloads/{mangaId}/ 目录存在即算）
  static downloadedMangaIds(): number[] {
    const ids: number[] = [];
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
    return ids;
  }

  static isDownloaded(chapterId: number): boolean {
    if (DownloadService.doneIds === undefined) {
      DownloadService.rebuildDoneIndex();
    }
    return DownloadService.doneIds !== undefined && DownloadService.doneIds.has(chapterId);
  }

  // 单次目录遍历构建 done.mark 索引
  private static rebuildDoneIndex(): void {
    const set = new Set<number>();
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
    DownloadService.doneIds = set;
  }

  // 每部漫画的已下载章节数（downloads/{mangaId}/ 下章节目录数），书架下载徽标用
  static downloadedChapterCounts(): Record<string, number> {
    const counts: Record<string, number> = {};
    if (DownloadService.rootDir === '' || !fileIo.accessSync(DownloadService.rootDir)) {
      return counts;
    }
    const mangaDirs = fileIo.listFileSync(DownloadService.rootDir);
    for (const md of mangaDirs) {
      const id = parseInt(md, 10);
      if (id >= 0) {
        const chapterDirs = fileIo.listFileSync(`${DownloadService.rootDir}/${md}`);
        counts[`${id}`] = chapterDirs.length;
      }
    }
    return counts;
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
    return -1;
  }

  static localText(mangaId: number, chapterId: number): string {
    const path = `${DownloadService.chapterDir(mangaId, chapterId)}/chapter.txt`;
    if (DownloadService.rootDir !== '' && fileIo.accessSync(path)) {
      return path;
    }
    return '';
  }

  static localVideo(mangaId: number, chapterId: number): string {
    const path = `${DownloadService.chapterDir(mangaId, chapterId)}/video.mp4`;
    if (DownloadService.rootDir !== '' && fileIo.accessSync(path)) {
      return path;
    }
    return '';
  }

  static localPages(mangaId: number, chapterId: number): string[] {
    const dir = DownloadService.chapterDir(mangaId, chapterId);
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
  }

  static deleteChapter(mangaId: number, chapterId: number): void {
    const dir = DownloadService.chapterDir(mangaId, chapterId);
    if (fileIo.accessSync(dir)) {
      DownloadService.rmdir(dir);
    }
    if (DownloadService.doneIds !== undefined) {
      DownloadService.doneIds.delete(chapterId);
    }
    DownloadService.queue = DownloadService.queue.filter((t: DownloadTask) => t.chapterId !== chapterId);
    DownloadService.notify();
  }

  private static rmdir(path: string): void {
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
  }

  static async listDownloaded(): Promise<DownloadedManga[]> {
    const result: DownloadedManga[] = [];
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
