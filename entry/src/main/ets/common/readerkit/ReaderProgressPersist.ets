// 进度持久化：调度时锁定「章节/漫画/进度」快照（切章不串写）；
// debounceMs>0 防抖合并（小说 2000ms），=0 立即写（漫画）。
// 进度取值与落盘经构造注入的闭包提供（ArkTS 禁止带函数成员的对象字面量，不能用钩子接口）
export class ReaderProgressPersist {
  private readonly currentChapterId: () => number;
  private readonly currentMangaId: () => number;
  private readonly currentProgress: () => number;
  private readonly writeProgress: (chapterId: number, mangaId: number, progress: number) => void;
  private readonly debounceMs: number;
  private pending: boolean = false;
  private timerId: number = -1;
  private snapChapterId: number = -1;
  private snapMangaId: number = -1;
  private snapProgress: number = 0;

  constructor(currentChapterId: () => number, currentMangaId: () => number, currentProgress: () => number,
    writeProgress: (chapterId: number, mangaId: number, progress: number) => void, debounceMs: number) {
    this.currentChapterId = currentChapterId;
    this.currentMangaId = currentMangaId;
    this.currentProgress = currentProgress;
    this.writeProgress = writeProgress;
    this.debounceMs = debounceMs;
  }

  // 调度一次进度落盘（快照立即锁定；防抖期内重复调用只保留最后快照）
  schedule(): void {
    const chapterId: number = this.currentChapterId();
    if (chapterId <= 0) {
      return;
    }
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    this.snapChapterId = chapterId;
    this.snapMangaId = this.currentMangaId();
    this.snapProgress = this.currentProgress();
    this.pending = true;
    if (this.debounceMs <= 0) {
      this.pending = false;
      this.writeProgress(this.snapChapterId, this.snapMangaId, this.snapProgress);
      return;
    }
    this.timerId = setTimeout((): void => {
      this.timerId = -1;
      if (!this.pending) {
        return;
      }
      this.pending = false;
      this.writeProgress(this.snapChapterId, this.snapMangaId, this.snapProgress);
    }, this.debounceMs);
  }

  // 立即落盘待写快照（切章/退出时调用）
  flush(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    if (!this.pending) {
      return;
    }
    this.pending = false;
    this.writeProgress(this.snapChapterId, this.snapMangaId, this.snapProgress);
  }

  // 丢弃待写快照并清定时器（不落盘）
  dispose(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    this.pending = false;
  }
}
