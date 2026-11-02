import { common } from '@kit.AbilityKit';
import { AppDb } from '../../data/AppDb';
import { ChapterRepo, HistoryRepo, MangaRepo } from '../../data/Repos';
import { ReadingStatsRepo } from '../../data/ReadingStats';
import { ChapterRecord, MangaRecord } from '../../model/Models';
import { ContinueSession } from '../ContinueSession';
import { ReaderLoadGuard } from './ReaderLoadGuard';

// 章节加载钩子：内容管线/导航刷新/落点等页面差异经函数字段注入（aboutToAppear 接线），
// 骨架顺序两阅读器统一。
// 注：不能用接口 + 对象字面量初始化——ArkTS 禁止带函数成员的对象字面量
// （arkts-no-untyped-obj-literals），故以函数字段类 + 默认空实现承载
export class ReaderChapterFlowHooks {
  // 重置领域状态（loading/正文/页列表/翻译代次/设置快照等）
  prepare: () => void = (): void => {};
  // 页面宿主上下文（AppDb 初始化用）
  appContext: () => common.UIAbilityContext = (): common.UIAbilityContext => {
    throw new Error('ReaderChapterFlowHooks.appContext not wired');
  };
  // 待加载章节 id
  chapterId: () => number = (): number => -1;
  // 章节不存在：toast 前的页面处理（小说需先撤 loading）
  onNotFound: () => void = (): void => {};
  // 章节记录就绪（小说在此消费 gotoEnd/gotoPermille/历史进度落点）
  onChapterResolved: (chapter: ChapterRecord) => void = (_chapter: ChapterRecord): void => {};
  // 漫画记录就绪（未取到时保持原记录）
  onMangaResolved: (manga: MangaRecord | undefined) => void = (_manga: MangaRecord | undefined): void => {};
  // 内容管线（小说取正文并派生分页；漫画取页列表/清洗/落点）；
  // isStale 供管线内部各 await 续点做代次校验
  loadContent: (chapter: ChapterRecord, isStale: () => boolean) => Promise<void> =
    (_chapter: ChapterRecord, _isStale: () => boolean): Promise<void> => Promise.resolve();
  // 刷新相邻章节导航（小说 loadNeighbors / 漫画 refreshNeighbors）
  refreshNav: () => Promise<void> = (): Promise<void> => Promise.resolve();
  // 导航就绪后的模式应用（漫画 applyMode(true)；小说不接线）
  afterNav: () => void = (): void => {};
  // 记录用的当前进度快照（小说千分比 / 漫画页码）
  progressSnapshot: () => number = (): number => 0;
  // 内容类型（ContinueSession 快照用）
  contentType: () => string = (): string => '';
  // 进度记录完成后的附加动作（漫画按下载设置预下载）
  afterRecord: (chapter: ChapterRecord, manga: MangaRecord | undefined) => void =
    (_chapter: ChapterRecord, _manga: MangaRecord | undefined): void => {};
  // 加载失败清理（漫画清空旧页防止旧页码写入本章进度）
  onLoadError: (errorMessage: string) => void = (_errorMessage: string): void => {};
  // 收尾（撤 loading、自动翻译/预取/自动翻页重挂等）
  onSettled: () => void = (): void => {};
}

// 章节加载骨架：代次守卫 → 结算上章会话 → 章节记录 → 漫画记录 → 内容 →
// 导航 → 模式 → 历史/接续会话/阅读时长记录 → 附加动作；toast/pop 经构造注入避免依赖页面
export class ReaderChapterFlow {
  private readonly guard: ReaderLoadGuard;
  private readonly hooks: ReaderChapterFlowHooks;
  private readonly toastNotFound: () => void;
  private readonly toastLoadFailed: (errorMessage: string) => void;
  private readonly pop: () => void;

  constructor(guard: ReaderLoadGuard, hooks: ReaderChapterFlowHooks,
    toastNotFound: () => void, toastLoadFailed: (errorMessage: string) => void, pop: () => void) {
    this.guard = guard;
    this.hooks = hooks;
    this.toastNotFound = toastNotFound;
    this.toastLoadFailed = toastLoadFailed;
    this.pop = pop;
  }

  async load(): Promise<void> {
    const gen: number = this.guard.begin();
    this.hooks.prepare();
    // 切章：先结算上一章的阅读会话
    ReadingStatsRepo.flush();
    try {
      await AppDb.ready(this.hooks.appContext());
      if (this.guard.isStale(gen)) {
        return;
      }
      const chapter: ChapterRecord | undefined = await ChapterRepo.getById(this.hooks.chapterId());
      if (this.guard.isStale(gen)) {
        return;
      }
      if (chapter === undefined) {
        this.hooks.onNotFound();
        this.toastNotFound();
        this.pop();
        return;
      }
      this.hooks.onChapterResolved(chapter);
      const manga: MangaRecord | undefined = await MangaRepo.get(chapter.mangaId);
      if (this.guard.isStale(gen)) {
        return;
      }
      this.hooks.onMangaResolved(manga);
      await this.hooks.loadContent(chapter, (): boolean => this.guard.isStale(gen));
      if (this.guard.isStale(gen)) {
        return;
      }
      await this.hooks.refreshNav();
      if (this.guard.isStale(gen)) {
        return;
      }
      this.hooks.afterNav();
      const progress: number = this.hooks.progressSnapshot();
      await HistoryRepo.upsert(chapter.mangaId, chapter.id, progress);
      // 跨设备接续/碰一碰会话快照：随章节加载刷新（进度语义=小说千分比/漫画页码）
      ContinueSession.update(this.hooks.contentType(), manga, chapter, progress);
      if (this.guard.isStale(gen)) {
        return;
      }
      // 开始本章的阅读时长计时
      ReadingStatsRepo.begin(chapter.mangaId, chapter.id);
      this.hooks.afterRecord(chapter, manga);
    } catch (e) {
      const errorMessage: string = e instanceof Error ? e.message : String(e);
      if (!this.guard.isStale(gen)) {
        this.hooks.onLoadError(errorMessage);
        this.toastLoadFailed(errorMessage);
      }
    }
    if (this.guard.isStale(gen)) {
      return;
    }
    this.hooks.onSettled();
  }
}
