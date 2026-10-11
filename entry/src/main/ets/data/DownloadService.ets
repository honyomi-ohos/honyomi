import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Http } from '../net/Http';
import { SourceRegistry } from '../source/Source';
import { DownloadTask, DownloadedChapter, DownloadedManga, SPage } from '../model/Models';
import { ChapterRepo } from './Repos';
import { MangaRepo } from './Repos';

// 下载服务（对齐 Mihon DownloadManager 的精简版）
// 存储布局: {filesDir}/downloads/{mangaId}/{chapterId}/000.jpg ... + done.mark
export class DownloadService {
  private static rootDir: string = '';
  private static queue: DownloadTask[] = [];
  private static running: boolean = false;
  private static paused: boolean = false;
  private static listeners: Array<() => void> = [];

  static init(context: common.UIAbilityContext): void {
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

  static cancel(chapterId: number): void {
    for (const t of DownloadService.queue) {
      if (t.chapterId === chapterId && t.state !== 1) {
        t.state = 3;
        t.error = '已取消';
      }
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
      DownloadService.notify();
      DownloadService.pump();
    }).catch((e: Error) => {
      hilog.error(0x0001, 'Download', 'process failed: %{public}s', e.message);
      DownloadService.running = false;
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
    const mangaId = DownloadService.mangaIdOf(chapterId);
    if (mangaId < 0) {
      return false;
    }
    return fileIo.accessSync(`${DownloadService.chapterDir(mangaId, chapterId)}/done.mark`);
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

  // 已完成下载的章节 id 集合（一次遍历目录，更新页"已下载"筛选用）
  static downloadedChapterIdSet(): Set<number> {
    const set = new Set<number>();
    if (DownloadService.rootDir === '' || !fileIo.accessSync(DownloadService.rootDir)) {
      return set;
    }
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

  static localPages(mangaId: number, chapterId: number): string[] {
    const dir = DownloadService.chapterDir(mangaId, chapterId);
    if (!fileIo.accessSync(dir)) {
      return [];
    }
    const files = fileIo.listFileSync(dir);
    const pages = files.filter((f: string) => f !== 'done.mark').sort();
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
