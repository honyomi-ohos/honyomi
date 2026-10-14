import { display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, HistoryRepo } from '../data/Repos';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { SourceRegistry } from '../source/Source';
import { MangaRecord, ChapterRecord } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';
import { Theme, ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Settings } from '../common/Settings';
import { Util } from '../common/Util';
import { TtsPlaybackService, TtsServiceStateHandler, TtsServiceParaHandler, TtsServiceChapterHandler, TtsServiceErrorHandler, TtsServiceFinishHandler } from '../common/TtsPlaybackService';
import { TtsText } from '../common/TtsText';
import { ReaderWindow } from '../common/ReaderWindow';
import { ReaderChapterNav, ChapterNeighbors } from '../common/ReaderChapterNav';
import { DownloadService } from '../data/DownloadService';
import { EmulationFlipView } from './components/PageFlip';
import { NovelBlock, NovelPage, SPINE_W, EMPTY_NOVEL_PAGE, NovelPaginator, NovelChapterText } from './components/novel/NovelPaginator';
import { NovelModeSheet } from './components/novel/NovelModeSheet';
import { NovelDisplayPanel } from './components/novel/NovelDisplayPanel';
import { NovelTextPanel } from './components/novel/NovelTextPanel';
import { ReaderMenu, ReaderBottomBar, ReaderNavRow, ReaderPagePill, ReaderMenuIconButton, ReaderIndicatorBadge, ReaderOrientationSheet } from './components/ReaderChrome';
import { LoadingBackButton } from './components/LoadingBackButton';

// 翻屏进度持久化防抖间隔（毫秒）
const PERSIST_DEBOUNCE_MS: number = 2000;

// 翻页屏幕的 LazyForEach 数据源：按需构建当前屏及相邻屏，大章节不再一次性渲染全部页面
class NovelScreenSource implements IDataSource {
  private items: number[] = [];
  private listeners: DataChangeListener[] = [];

  setItems(items: number[]): void {
    this.items = items;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): number {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }
}

// 章节加载与分页：正文解析/分页引擎在 NovelPaginator，页面只保留状态与渲染
// 小说阅读器：滚动 / 翻页 / 双页三种模式，交互对齐漫画阅读器——
// 全屏正文，点击屏幕中间呼出菜单（顶栏+底栏），底部设置面板含
// 翻页方式 / 字号 / 行间距 / 段间距 / 背景（背景与漫画阅读器共用 readerTheme）。
// 进度统一记为千分比 0–1000（滚动=滚动比例，翻页/双页=页码比例），各模式间可近似换算恢复。
@Component
export struct NovelReaderPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @State manga: MangaRecord = new MangaRecord();
  @State chapter: ChapterRecord = new ChapterRecord();
  @State body: string = '';
  @State html: boolean = false;
  @State loading: boolean = true;
  @State showMenu: boolean = false;
  @State fontSize: number = 18;
  @State lineHeight: number = 32;
  @State paraSpacing: number = 0;
  @State prevId: number = 0;
  @State nextId: number = 0;
  @State mode: string = 'scroll';
  @State pages: NovelPage[] = [];
  // 章节含插图（html 正文解析出 <img>）：滚动模式内嵌渲染，翻页模式插图独占一页
  @State hasImages: boolean = false;
  @State screenIdxs: number[] = [];
  @State pageIdx: number = 0;
  @State readerTheme: number = 3;
  @State showPageNumber: boolean = true;
  // 菜单/指示器展示用的进度快照（permille 高频变化，不宜直接做状态）
  @State permilleUi: number = 0;
  // 底栏各设置入口的 Sheet：阅读模式 / 屏幕方向 / 画面 / 文本设置
  @State showModeSheet: boolean = false;
  // 翻页动画：curl=仿真 slide=滑动 cover=覆盖
  @State animMode: string = 'slide';
  // 双页半页翻动的触发序号：正数下一页，负数上一页
  @State leafTurn: number = 0;
  @State orientation: string = 'free';
  @State showOrientationSheet: boolean = false;
  // 底栏设置面板（画面/文本）共用一个 bindSheet：同一节点链式绑定多个 bindSheet 时只有最后一个生效，
  // 前面的会被立即关闭，故用单个 isShow + panelKind 切换内容
  @State showPanelSheet: boolean = false;
  @State panelKind: string = '';
  @State brightLv: number = 0;
  // 听书（系统 TTS）：播放中 / 当前朗读段
  @State ttsPlaying: boolean = false;
  @State ttsParaIdx: number = -1;
  // 正文配色：auto=跟随背景 light=浅色 dark=深色
  @State colorScheme: string = 'auto';
  @State pageMargin: number = 20;
  // 正文字体：default/serif/sans/mono
  @State fontFamily: string = 'default';
  // 翻页动画逐帧变换（与 screenIdxs 一一对应）：x 位移 / y 轴翻转角 / 层级
  @State transX: number[] = [];
  @State transAngle: number[] = [];
  @State transZ: number[] = [];
  // 双页仿真：左右半页各自绕中线（书脊）的翻转角
  @State transAngleL: number[] = [];
  @State transAngleR: number[] = [];
  // 双页仿真翻转半页的纵向倾斜（随抓取位置变化）
  @State halfTilt: number = 0;
  // 本次翻页的抓取纵向位置（0 顶部 ~ 1 底部，相对正文区），决定卷曲弓高与倾斜方向
  private flipGrabY: number = 0.5;
  private mangaId: number = -1;
  private chapterId: number = -1;
  private scroller: Scroller = new Scroller();
  private scrollY: number = 0;
  private contentH: number = 0;
  private viewH: number = 0;
  private restored: boolean = false;
  private permille: number = 0;
  private swiperCtrl: SwiperController = new SwiperController();
  private screenSource: NovelScreenSource = new NovelScreenSource();
  // 分页引擎（测量函数注入：与渲染端 fontSize/lineHeight 一致的 vp 高度）
  private paginator: NovelPaginator =
    new NovelPaginator((text: string, widthVp: number): number => this.measureTextVp(text, widthVp));
  private contW: number = 0;
  private contH: number = 0;
  private pageW: number = 0;
  private pageH: number = 0;
  private pagSig: string = '';

  private screenDensity: number = 2;
  // 段落 → 翻页页码映射（buildPages 填充，听书跟随翻页用）
  private paraPage: number[] = [];
  // 滚动模式视口宽度（听书跟随滚动测高用）
  private scrollW: number = 0;
  // 滚动模式段落纵向偏移缓存（签名变化时重算）
  private paraOffsets: number[] = [];
  private paraOffSig: string = '';
  // html 章节解析出的「文本段 + 插图」块序列（hasImages 时有效）
  private blocks: NovelBlock[] = [];
  // 章节加载代次号：连续切章时旧 loadChapter 续体据此丢弃
  private loadGen: number = 0;
  // 页面销毁标志：loadChapter 各 await 后校验，防止退出后启动无人结算的会话
  private destroyed: boolean = false;
  // 进度持久化防抖：待落盘的快照（章节/漫画/千分比在调度时锁定，切章不串写）
  private persistPending: boolean = false;
  private persistTimerId: number = -1;
  private persistSnapChapterId: number = -1;
  private persistSnapMangaId: number = -1;
  private persistSnapPermille: number = 0;

  aboutToAppear(): void {
    try {
      this.screenDensity = display.getDefaultDisplaySync().densityPixels;
    } catch (error) {
      this.screenDensity = 2;
    }
    this.mode = Settings.getNovelReaderMode();
    this.fontSize = Settings.getNovelFontSize();
    this.lineHeight = Settings.getNovelLineHeight();
    this.paraSpacing = Settings.getNovelParagraphSpacing();
    this.readerTheme = Settings.getReaderTheme();
    this.showPageNumber = Settings.getReaderShowPageNumber();
    this.animMode = Settings.getNovelPageAnim();
    this.orientation = Settings.getNovelOrientation();
    this.colorScheme = Settings.getNovelColorScheme();
    this.pageMargin = Settings.getNovelMargin();
    this.fontFamily = Settings.getNovelFontFamily();
    this.brightLv = Settings.getReaderBrightness();
    this.applyOrientation();
    this.applyBrightness();
    this.wireTtsEvents();
  }

  aboutToDisappear(): void {
    this.destroyed = true;
    this.loadGen += 1;
    // 听书播放与页面生命周期解耦：离开阅读器不停止朗读，仅退订本实例回调
    TtsPlaybackService.events.offState(this.ttsOnState);
    TtsPlaybackService.events.offPara(this.ttsOnPara);
    TtsPlaybackService.events.offChapter(this.ttsOnChapter);
    TtsPlaybackService.events.offError(this.ttsOnError);
    TtsPlaybackService.events.offFinish(this.ttsOnFinish);
    this.flushPersist();
    ReadingStatsRepo.flush();
    // 还原窗口方向与亮度
    ReaderWindow.restore(Util.hostAbilityContext(this.getUIContext()));
  }

  private applyOrientation(): void {
    ReaderWindow.applyOrientation(Util.hostAbilityContext(this.getUIContext()), this.orientation);
  }

  private applyBrightness(): void {
    ReaderWindow.applyBrightness(Util.hostAbilityContext(this.getUIContext()), this.brightLv);
  }

  private async loadChapter(): Promise<void> {
    const gen = ++this.loadGen;
    this.loading = true;
    this.showMenu = false;
    this.restored = false;
    this.body = '';
    this.pages = [];
    this.blocks = [];
    this.hasImages = false;
    this.screenIdxs = [];
    this.screenSource.setItems([]);
    this.pageIdx = 0;
    this.pagSig = '';
    // 打开其它章节时停止听书；听书服务正在朗读本章（跟随切章/重新进入）不打断
    if (TtsPlaybackService.currentChapterId() !== this.chapterId) {
      TtsPlaybackService.stop();
    }
    this.ttsParaIdx = -1;
    this.paraPage = [];
    this.paraOffSig = '';
    this.mode = Settings.getNovelReaderMode();
    this.fontSize = Settings.getNovelFontSize();
    this.lineHeight = Settings.getNovelLineHeight();
    this.paraSpacing = Settings.getNovelParagraphSpacing();
    this.animMode = Settings.getNovelPageAnim();
    this.colorScheme = Settings.getNovelColorScheme();
    this.pageMargin = Settings.getNovelMargin();
    this.fontFamily = Settings.getNovelFontFamily();
    ReadingStatsRepo.flush();
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      if (this.destroyed || gen !== this.loadGen) {
        return;
      }
      const chapter = await ChapterRepo.getById(this.chapterId);
      if (this.destroyed || gen !== this.loadGen) {
        return;
      }
      if (chapter === undefined) {
        this.loading = false;
        Util.toastRes(this.getUIContext(), $r('app.string.reader_chapter_not_found'));
        this.pathStack.pop();
        return;
      }
      this.chapter = chapter;
      this.mangaId = chapter.mangaId;
      this.permille = chapter.lastPageRead > 0 && chapter.lastPageRead <= 1000 ? chapter.lastPageRead : 0;
      const manga = await MangaRepo.get(chapter.mangaId);
      if (this.destroyed || gen !== this.loadGen) {
        return;
      }
      if (manga !== undefined) {
        this.manga = manga;
      }
      const local = DownloadService.localText(chapter.mangaId, chapter.id);
      let text = '';
      if (local !== '') {
        text = Util.readTextAuto(local);
      } else {
        const source = SourceRegistry.get(this.manga.sourceKey);
        if (source === undefined) {
          throw new Error('source_unavailable');
        }
        text = await source.getChapterText(chapter.url);
      }
      if (this.destroyed || gen !== this.loadGen) {
        return;
      }
      if (text === '') {
        throw new Error('no_content');
      }
      this.html = NovelChapterText.looksLikeHtml(text);
      this.body = text;
      this.parseChapterBlocks();
      // 插件返回的无插图 html 正文：剥成纯文本走统一的分页/渲染路径，
      // 翻页/双页分页与字号/行距/字体设置才能生效（原 RichText 路径两者均不支持）
      if (this.html && !this.hasImages) {
        this.body = NovelChapterText.htmlToPlain(text);
        this.html = false;
        this.parseChapterBlocks();
      }
      await this.loadNeighbors();
      if (this.destroyed || gen !== this.loadGen) {
        return;
      }
      await HistoryRepo.upsert(chapter.mangaId, chapter.id, this.permille);
      if (this.destroyed || gen !== this.loadGen) {
        return;
      }
      ReadingStatsRepo.begin(chapter.mangaId, chapter.id);
    } catch (e) {
      if (gen === this.loadGen) {
        Util.toastRes(this.getUIContext(), $r('app.string.reader_load_failed'),
          [Util.errText(this.getUIContext(), e instanceof Error ? e.message : String(e))]);
      }
    }
    if (this.destroyed || gen !== this.loadGen) {
      return;
    }
    this.loading = false;
    this.ensurePaginated();
    // 听书服务若正在朗读本章（跟随切章/重新进入），同步播放态与朗读高亮
    this.syncTtsUi();
  }

  private async loadNeighbors(): Promise<void> {
    const n: ChapterNeighbors = await ReaderChapterNav.neighbors(this.mangaId, this.chapterId);
    this.prevId = n.prevId;
    this.nextId = n.nextId;
  }

  private restoreOnce(): void {
    if (this.restored || this.permille <= 0 || this.contentH <= this.viewH || this.viewH <= 0) {
      return;
    }
    const range = this.contentH - this.viewH;
    this.scroller.scrollTo({ xOffset: 0, yOffset: range * this.permille / 1000, animation: false });
    this.restored = true;
    this.permilleUi = this.permille;
  }

  private captureOffset(y: number): void {
    this.scrollY = y;
    ReadingStatsRepo.tick();
    const range = this.contentH - this.viewH;
    if (range <= 0) {
      this.permille = 1000;
      return;
    }
    let value = Math.round(y / range * 1000);
    if (value < 0) {
      value = 0;
    }
    if (value > 1000) {
      value = 1000;
    }
    this.permille = value;
  }

  // 翻屏高频持久化防抖：2 秒内合并为一次落盘；快照在调度时锁定，
  // 切章/退出经 flushPersist 立即写盘，旧章 permille 不会写入新章
  private persist(): void {
    if (this.chapterId <= 0) {
      return;
    }
    if (this.persistTimerId !== -1) {
      clearTimeout(this.persistTimerId);
    }
    this.persistSnapChapterId = this.chapterId;
    this.persistSnapMangaId = this.mangaId;
    this.persistSnapPermille = this.permille;
    this.persistPending = true;
    this.persistTimerId = setTimeout((): void => {
      this.persistTimerId = -1;
      if (!this.persistPending) {
        return;
      }
      this.persistPending = false;
      this.persistWrite(this.persistSnapChapterId, this.persistSnapMangaId, this.persistSnapPermille);
    }, PERSIST_DEBOUNCE_MS);
  }

  // 立即落盘待写的进度快照（切章/退出时调用）
  private flushPersist(): void {
    if (this.persistTimerId !== -1) {
      clearTimeout(this.persistTimerId);
      this.persistTimerId = -1;
    }
    if (!this.persistPending) {
      return;
    }
    this.persistPending = false;
    this.persistWrite(this.persistSnapChapterId, this.persistSnapMangaId, this.persistSnapPermille);
  }

  private persistWrite(chapterId: number, mangaId: number, permille: number): void {
    ChapterRepo.setLastPageRead(chapterId, permille).catch((e: Object): void => {
      hilog.warn(0x0001, 'NovelReader', 'setLastPageRead failed: %{public}s', `${e}`);
    });
    HistoryRepo.upsert(mangaId, chapterId, permille).catch((e: Object): void => {
      hilog.warn(0x0001, 'NovelReader', 'history upsert failed: %{public}s', `${e}`);
    });
    if (permille >= 950) {
      ChapterRepo.setRead(chapterId, true).catch((e: Object): void => {
        hilog.warn(0x0001, 'NovelReader', 'setRead failed: %{public}s', `${e}`);
      });
    }
  }

  private openChapter(id: number): void {
    if (id <= 0) {
      return;
    }
    // 先把上一章的进度快照立即落盘，再切换章节，防止旧章 permille 写入新章
    this.flushPersist();
    this.chapterId = id;
    this.loadChapter();
  }

  // ---- 听书（系统 TTS，经 TtsPlaybackService 与页面生命周期解耦）----

  // 订阅模型的稳定回调引用：aboutToAppear 订阅、aboutToDisappear 退订
  private readonly ttsOnState: TtsServiceStateHandler =
    (_playing: boolean, _paused: boolean, _mangaId: number, _chapterId: number): void => {
      this.syncTtsUi();
    };

  private readonly ttsOnPara: TtsServiceParaHandler =
    (_mangaId: number, chapterId: number, paraIdx: number): void => {
      if (chapterId !== this.chapterId) {
        return;
      }
      this.ttsParaIdx = paraIdx;
      // 章节加载中不跟随（分页/滚动映射仍是旧章内容）
      if (!this.loading) {
        this.followTtsPara(paraIdx);
      }
    };

  private readonly ttsOnChapter: TtsServiceChapterHandler = (mangaId: number, chapterId: number): void => {
    if (mangaId !== this.mangaId) {
      return;
    }
    if (chapterId === this.chapterId) {
      this.syncTtsUi();
      return;
    }
    // 听书自动进入下一章：阅读器跟随加载（不打断朗读）
    this.openChapter(chapterId);
  };

  private readonly ttsOnError: TtsServiceErrorHandler = (message: string): void => {
    Util.toastRes(this.getUIContext(), $r('app.string.novel_tts_error'),
      [Util.errText(this.getUIContext(), message)]);
    this.syncTtsUi();
  };

  private readonly ttsOnFinish: TtsServiceFinishHandler = (): void => {
    Util.toastRes(this.getUIContext(), $r('app.string.novel_tts_finish'));
    this.syncTtsUi();
  };

  // 接管听书服务事件：跟随滚动/翻页、跟随切章、错误/播完提示
  private wireTtsEvents(): void {
    TtsPlaybackService.events.onState(this.ttsOnState);
    TtsPlaybackService.events.onPara(this.ttsOnPara);
    TtsPlaybackService.events.onChapter(this.ttsOnChapter);
    TtsPlaybackService.events.onError(this.ttsOnError);
    TtsPlaybackService.events.onFinish(this.ttsOnFinish);
  }

  // 同步听书 UI：仅当服务正在朗读当前章节时显示播放态
  private syncTtsUi(): void {
    this.ttsPlaying = TtsPlaybackService.isPlaying() && TtsPlaybackService.currentChapterId() === this.chapterId;
    if (!this.ttsPlaying) {
      this.ttsParaIdx = -1;
    }
  }

  // 听书文本段落：html 章节剥除标签，纯文本按行拆分（与 TtsPlaybackService 共用算法）
  private ttsParas(): string[] {
    return TtsText.chapterParas(this.body);
  }

  // 起播段落：翻页/双页取当前页首段；滚动按进度比例估算
  private currentTtsPara(): number {
    const paras = this.ttsParas();
    if (paras.length === 0) {
      return 0;
    }
    if (this.mode !== 'scroll' && this.paraPage.length === paras.length) {
      const total = this.pages.length;
      if (total > 0) {
        const logical = this.mode === 'double' ? this.pageIdx * 2 :
          (this.mode === 'paged_rtl' ? total - 1 - this.pageIdx : this.pageIdx);
        const page = Math.min(total - 1, Math.max(0, logical));
        for (let i = 0; i < this.paraPage.length; i++) {
          if (this.paraPage[i] >= page) {
            return i;
          }
        }
        return paras.length - 1;
      }
    }
    return Math.min(paras.length - 1, Math.max(0, Math.round(this.permille * (paras.length - 1) / 1000)));
  }

  private async startTts(fromPara: number): Promise<void> {
    if (this.body === '') {
      return;
    }
    const paras = this.ttsParas();
    if (paras.length === 0) {
      return;
    }
    this.ttsPlaying = true;
    const ok = await TtsPlaybackService.start(this.mangaId, this.chapterId, fromPara,
      Util.hostAbilityContext(this.getUIContext()));
    if (!ok) {
      this.ttsPlaying = false;
      this.ttsParaIdx = -1;
      Util.toastRes(this.getUIContext(), $r('app.string.novel_tts_error'),
        [Util.errText(this.getUIContext(), 'tts_unavailable')]);
    }
  }

  // 听书按钮：直接起播/续播并进入播放器（不弹听书设置面板）；播放中点击则暂停
  private async startTtsAndOpenPlayer(): Promise<void> {
    if (TtsPlaybackService.isPlaying()) {
      TtsPlaybackService.pause();
      return;
    }
    if (TtsPlaybackService.isPaused() && TtsPlaybackService.currentChapterId() === this.chapterId) {
      TtsPlaybackService.resume();
      this.pathStack.pushPathByName('TtsPlayer', null);
      return;
    }
    await this.startTts(this.currentTtsPara());
    if (TtsPlaybackService.isActive()) {
      this.pathStack.pushPathByName('TtsPlayer', null);
    }
  }

  // 跟随朗读进度：滚动模式滚到对应段落，翻页/双页翻到对应页
  private followTtsPara(idx: number): void {
    // 插图高度不定，含插图章节的滚动模式不做听书跟随
    if (this.hasImages && this.mode === 'scroll') {
      return;
    }
    if (this.mode === 'scroll') {
      this.followTtsScroll(idx);
    } else {
      this.followTtsPaged(idx);
    }
  }

  // 滚动跟随：按测量计算段落纵向偏移（带签名缓存），段落不在可视区时滚动过去
  private followTtsScroll(idx: number): void {
    const paras = this.body.split('\n');
    const width = (this.scrollW > 0 ? this.scrollW : this.contW) - this.pageMargin * 2;
    if (paras.length === 0 || width <= 0) {
      return;
    }
    const sig = `${this.body.length}|${this.fontSize}|${this.lineHeight}|${this.paraSpacing}|${Math.round(width)}`;
    if (sig !== this.paraOffSig) {
      const offsets: number[] = [];
      let y = this.statusBarH + 16;
      for (let i = 0; i < paras.length; i++) {
        offsets.push(y);
        y += this.measureTextVp(paras[i] === '' ? ' ' : paras[i], width) + this.paraSpacing;
      }
      this.paraOffsets = offsets;
      this.paraOffSig = sig;
    }
    if (idx < 0 || idx >= this.paraOffsets.length) {
      return;
    }
    const top = this.paraOffsets[idx];
    if (top >= this.scrollY + 24 && top <= this.scrollY + this.viewH - 72) {
      return;
    }
    const target = Math.max(0, top - this.statusBarH - 16);
    this.restored = true;
    this.scroller.scrollTo({ xOffset: 0, yOffset: target, animation: true });
  }

  // 翻页/双页跟随：段落 → 页 → 屏，翻到朗读页（curl 模式经 index 属性同步）
  private followTtsPaged(idx: number): void {
    if (this.paraPage.length === 0 || idx < 0 || idx >= this.paraPage.length) {
      return;
    }
    const total = this.pages.length;
    if (total <= 0 || this.screenIdxs.length === 0) {
      return;
    }
    const page = Math.min(total - 1, Math.max(0, this.paraPage[idx]));
    let screen = page;
    if (this.mode === 'double') {
      screen = Math.floor(page / 2);
    } else if (this.mode === 'paged_rtl') {
      screen = total - 1 - page;
    }
    if (screen < 0) {
      screen = 0;
    }
    if (screen >= this.screenIdxs.length) {
      screen = this.screenIdxs.length - 1;
    }
    if (screen !== this.pageIdx) {
      this.jumpScreen(screen);
    }
  }

  // 解析 html 章节为「文本段 + 插图」块序列（NovelChapterText.parseBlocks），
  // 同时标记 hasImages 供渲染路径分流；无插图时保持原有渲染路径
  private parseChapterBlocks(): void {
    this.blocks = NovelChapterText.parseBlocks(this.html, this.body);
    this.hasImages = false;
    for (let i = 0; i < this.blocks.length; i++) {
      if (this.blocks[i].isImage) {
        this.hasImages = true;
        break;
      }
    }
  }

  private toggleMenu(): void {
    this.showMenu = !this.showMenu;
    if (this.showMenu) {
      this.permilleUi = this.permille;
    }
  }

  // ---- 翻页 / 双页模式：按文本测量分页（页=段落数组，支持段间距） ----

  // 根据当前容器尺寸与模式计算单页文本可用宽高（vp）；
  // 内容区为全屏，已预留状态栏/导航栏内边距，此处从整高中扣除
  private recalcPageBox(): void {
    if (this.mode === 'double') {
      // 双页：左右各半，扣除左右边距与中缝宽度
      this.pageW = Math.floor((this.contW - this.pageMargin * 2 - SPINE_W) / 2);
    } else {
      this.pageW = Math.floor(this.contW - this.pageMargin * 2);
    }
    this.pageH = Math.floor(this.contH - (this.statusBarH + 8) - (this.navBarH + 8));
  }

  // 分页参数（正文/模式/字号/行距/段距/页面尺寸）变化时重新分页，并按千分比恢复到原位置附近
  private ensurePaginated(): void {
    if (this.loading || this.body === '' || this.mode === 'scroll') {
      return;
    }
    this.recalcPageBox();
    if (this.pageW <= 0 || this.pageH <= 0) {
      return;
    }
    const sig = `${this.body.length}|${this.mode}|${this.fontSize}|${this.lineHeight}|${this.paraSpacing}|` +
      `${this.pageMargin}|${this.fontFamily}|${Math.round(this.pageW)}|${Math.round(this.pageH)}`;
    if (sig === this.pagSig) {
      return;
    }
    // 同步分页引擎参数后重建页面（分页/切点算法在 NovelPaginator）
    this.paginator.pageW = this.pageW;
    this.paginator.pageH = this.pageH;
    this.paginator.paraSpacing = this.paraSpacing;
    this.paginator.lineHeight = this.lineHeight;
    const blocks: NovelBlock[] = this.hasImages ? this.blocks : NovelChapterText.plainBlocks(this.body);
    const pages = this.paginator.buildPages(blocks);
    this.paraPage = this.paginator.paraPage;
    const total = pages.length;
    let logical = 0;
    if (total > 1) {
      logical = Math.min(total - 1, Math.round(this.permille * (total - 1) / 1000));
    }
    const screenCount = this.mode === 'double' ? Math.ceil(total / 2) : total;
    const screens: number[] = [];
    for (let i = 0; i < screenCount; i++) {
      screens.push(i);
    }
    // 从右到左：屏幕序与页序相反，按阅读进度换算起始屏
    const screenIdx = this.mode === 'double' ? Math.floor(logical / 2) :
      (this.mode === 'paged_rtl' ? screenCount - 1 - logical : logical);
    this.pagSig = sig;
    this.pages = pages;
    this.screenIdxs = screens;
    this.screenSource.setItems(screens);
    this.transX = Util.zeros(screenCount);
    this.transAngle = Util.zeros(screenCount);
    this.transZ = Util.zeros(screenCount);
    this.transAngleL = Util.zeros(screenCount);
    this.transAngleR = Util.zeros(screenCount);
    this.halfTilt = 0;
    this.pageIdx = screenIdx;
    try {
      this.swiperCtrl.changeIndex(screenIdx, false);
    } catch (e) {
      // Swiper 尚未挂载时忽略，首次渲染由 .index() 指定
    }
  }

  // 测量文本在指定宽度下的渲染高度（vp），与 Text 的 fontSize/lineHeight 设置一致
  private measureTextVp(text: string, widthVp: number): number {
    const size: SizeOptions = this.getUIContext().getMeasureUtils().measureTextSize({
      textContent: text,
      fontSize: this.fontSize,
      lineHeight: this.lineHeight,
      constraintWidth: widthVp
    });
    const h = size.height;
    return this.getUIContext().px2vp(typeof h === 'number' ? h : 0);
  }

  // 越界返回共享的空页常量（不新建对象字面量）
  private pageAt(idx: number): NovelPage {
    if (idx >= 0 && idx < this.pages.length) {
      return this.pages[idx];
    }
    return EMPTY_NOVEL_PAGE;
  }

  // 供 @Builder 使用的单值访问器（@Builder 内禁止局部变量，避免多次 pageAt 调用）
  private pageImageUrl(idx: number): string {
    return this.pageAt(idx).imageUrl;
  }

  private pageTexts(idx: number): string[] {
    return this.pageAt(idx).texts;
  }

  private scrollParas(): string[] {
    return this.body.split('\n');
  }

  // 翻页/双页：屏幕（Swiper 页）切换 → 换算千分比并持久化
  private onScreenChange(idx: number): void {
    this.pageIdx = idx;
    const total = this.pages.length;
    // 从右到左：屏幕序与页序相反，页码 = 总页数 - 1 - 屏幕索引
    const logical = this.mode === 'double' ? idx * 2 :
      (this.mode === 'paged_rtl' ? total - 1 - idx : idx);
    let permille = 1000;
    if (total > 1) {
      permille = Math.round(logical * 1000 / (total - 1));
      if (permille < 0) {
        permille = 0;
      }
      if (permille > 1000) {
        permille = 1000;
      }
    }
    this.permille = permille;
    this.permilleUi = permille;
    ReadingStatsRepo.tick();
    this.persist();
  }

  // 任一设置 Sheet 打开时，内容区点击一律忽略（防止蒙层点击透传触发翻页/菜单）
  private anySheetOpen(): boolean {
    return this.showModeSheet || this.showOrientationSheet || this.showPanelSheet;
  }

  // 关闭全部设置 Sheet（enableOutsideInteractive 模式下由页面点击主动接管关闭）
  private dismissSheets(): void {
    this.showModeSheet = false;
    this.showOrientationSheet = false;
    this.showPanelSheet = false;
  }

  // 打开指定 Sheet（互斥：先关其余，避免多个 bindSheet 叠加）
  private openSheet(which: string): void {
    this.dismissSheets();
    if (which === 'mode') {
      this.showModeSheet = true;
    } else if (which === 'orientation') {
      this.showOrientationSheet = true;
    } else if (which === 'display' || which === 'text') {
      this.panelKind = which;
      this.showPanelSheet = true;
    }
  }

  private contentTap(): void {
    if (this.anySheetOpen()) {
      this.dismissSheets();
      return;
    }
    this.toggleMenu();
  }

  // 点击左右 30% 区域翻页；点击中间呼出/收起菜单（从右到左阅读时点击区镜像）
  // 记录翻页抓取的纵向位置（0=页面顶部，1=底部），驱动仿真卷曲的弓高方向与幅度
  private updateGrabY(y: number): void {
    if (this.contH <= 0) {
      return;
    }
    const frac = (y - this.statusBarH - 8) / this.contH;
    this.flipGrabY = Math.min(0.95, Math.max(0.05, frac));
  }

  private handleTap(event: ClickEvent): void {
    if (this.anySheetOpen()) {
      this.dismissSheets();
      return;
    }
    if (this.contW <= 0) {
      return;
    }
    this.updateGrabY(event.y);
    if (this.mode === 'paged_rtl') {
      if (event.x < this.contW * 0.3) {
        this.turnScreen(1);
      } else if (event.x > this.contW * 0.7) {
        this.turnScreen(-1);
      } else {
        this.toggleMenu();
      }
      return;
    }
    if (event.x < this.contW * 0.3) {
      this.turnScreen(-1);
    } else if (event.x > this.contW * 0.7) {
      this.turnScreen(1);
    } else {
      this.toggleMenu();
    }
  }

  // 翻页/双页：边界处跳上一章/下一章（dir 为阅读方向：+1 下一页，-1 上一页）
  private turnScreen(dir: number): void {
    const rtl = this.mode === 'paged_rtl';
    // 从右到左：屏幕序反转，阅读前进 = Swiper 索引递减
    const target = rtl ? this.pageIdx - dir : this.pageIdx + dir;
    if (target < 0) {
      this.openChapter(rtl ? this.nextId : this.prevId);
      return;
    }
    if (target >= this.screenIdxs.length) {
      this.openChapter(rtl ? this.prevId : this.nextId);
      return;
    }
    // showNext/showPrevious 自带动效并触发自定义过渡回调（仿真/滑动/覆盖均有动画）；
    // 不先改 this.pageIdx：index 属性变化是无动画瞬跳，会吞掉 changeIndex 的动效
    try {
      if (target > this.pageIdx) {
        this.swiperCtrl.showNext();
      } else {
        this.swiperCtrl.showPrevious();
      }
    } catch (e) {
      // 忽略控制器未绑定异常
    }
  }

  // 底栏进度 Slider 跳屏（翻页/双页）
  private jumpScreen(idx: number): void {
    if (idx < 0 || idx >= this.screenIdxs.length) {
      return;
    }
    this.pageIdx = idx;
    try {
      this.swiperCtrl.changeIndex(idx, false);
    } catch (e) {
      // 忽略控制器未绑定异常
    }
    this.onScreenChange(idx);
  }

  // 底栏进度 Slider 跳转（滚动：千分比）
  private scrollToPermille(p: number): void {
    let v = p;
    if (v < 0) {
      v = 0;
    }
    if (v > 1000) {
      v = 1000;
    }
    this.permille = v;
    this.permilleUi = v;
    this.restored = true;
    const range = this.contentH - this.viewH;
    if (range > 0) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: range * v / 1000, animation: false });
    }
    ReadingStatsRepo.tick();
    this.persist();
  }

  private setMode(mode: string): void {
    if (mode === this.mode) {
      return;
    }
    this.mode = mode;
    Settings.setNovelReaderMode(mode);
    this.restored = false;
    this.pagSig = '';
    this.pages = [];
    this.screenIdxs = [];
    this.screenSource.setItems([]);
    this.transX = [];
    this.transAngle = [];
    this.transZ = [];
    this.transAngleL = [];
    this.transAngleR = [];
    this.pageIdx = 0;
    if (mode !== 'scroll') {
      this.ensurePaginated();
    }
  }

  // 翻页动画切换：清空残留变换，避免上一模式的中间态影响渲染
  private setAnimMode(v: string): void {
    if (v === this.animMode) {
      return;
    }
    this.animMode = v;
    Settings.setNovelPageAnim(v);
    this.resetTransforms();
  }

  private resetTransforms(): void {
    for (let i = 0; i < this.transX.length; i++) {
      this.transX[i] = 0;
      this.transAngle[i] = 0;
      this.transZ[i] = 0;
      this.transAngleL[i] = 0;
      this.transAngleR[i] = 0;
    }
  }

  // 正文颜色：配色为浅色/深色时强制文字色，自动时按阅读背景推导（白底深色字，黑/灰底浅色字）
  private readerTextCol(): string {
    if (this.colorScheme === 'light') {
      return '#ECEEF2';
    }
    if (this.colorScheme === 'dark') {
      return '#16181D';
    }
    const t = this.readerTheme === 3 ? (this.isDark ? 1 : 0) : this.readerTheme;
    if (t === 0) {
      return '#16181D';
    }
    return '#ECEEF2';
  }

  // 正文字体（映射为系统字体族；默认 HarmonyOS Sans）
  private fontFamilyVal(): string {
    if (this.fontFamily === 'serif') {
      return 'serif';
    }
    if (this.fontFamily === 'sans') {
      return 'sans-serif';
    }
    if (this.fontFamily === 'mono') {
      return 'monospace';
    }
    return 'HarmonyOS Sans';
  }

  // 右下角进度指示文案（从右到左按阅读顺序显示页码）
  private indicatorText(): string {
    if (this.mode === 'scroll') {
      return `${Math.round(this.permilleUi / 10)}%`;
    }
    if (this.screenIdxs.length > 0) {
      if (this.mode === 'paged_rtl') {
        return `${this.screenIdxs.length - this.pageIdx}/${this.screenIdxs.length}`;
      }
      return `${this.pageIdx + 1}/${this.screenIdxs.length}`;
    }
    return '';
  }

  // 底栏进度 Slider 的显示值（从右到左模式按阅读顺序，滑杆方向随之镜像）
  private pagedSliderPos(): number {
    const n = this.screenIdxs.length;
    if (n <= 0) {
      return 1;
    }
    return this.mode === 'paged_rtl' ? n - this.pageIdx : this.pageIdx + 1;
  }

  private pagedScreenFromSlider(v: number): number {
    if (this.mode === 'paged_rtl') {
      return this.screenIdxs.length - v;
    }
    return v - 1;
  }

  private setPageTransform(i: number, x: number, angle: number, z: number): void {
    if (this.transX[i] !== x) {
      this.transX[i] = x;
    }
    if (this.transAngle[i] !== angle) {
      this.transAngle[i] = angle;
    }
    if (this.transZ[i] !== z) {
      this.transZ[i] = z;
    }
  }

  // 双页仿真：设置某屏左右半页的绕中线翻转角（书脊固定不动）
  private setHalfAngle(i: number, angleL: number, angleR: number): void {
    if (this.transAngleL[i] !== angleL) {
      this.transAngleL[i] = angleL;
    }
    if (this.transAngleR[i] !== angleR) {
      this.transAngleR[i] = angleR;
    }
  }

  // 翻转中的页面投影（增强仿真立体感）
  private flipShadow(active: boolean): ShadowOptions {
    if (active) {
      return { radius: 16, color: '#4D000000' };
    }
    return { radius: 0, color: Color.Transparent };
  }

  // 仿真翻转的透视相机距离（px）：约 2 倍页宽，近大远小，替代正交刚性旋转
  private flipPerspective(): number {
    if (this.animMode !== 'curl' || this.contW <= 0) {
      return 0;
    }
    const px = this.contW * this.screenDensity * 2;
    return Math.min(Math.max(px, 400), 2800);
  }

  // 仿真卷曲阴影不透明度：翻起（0→90°）随弯曲渐深，翻过竖直（90→180°）渐消，静止时为 0
  private curlShade(angle: number): number {
    if (this.animMode !== 'curl') {
      return 0;
    }
    const a = Math.abs(angle);
    if (a < 0.5) {
      return 0;
    }
    if (a <= 90) {
      return a / 90 * 0.32;
    }
    return Math.max(0, 1 - (a - 90) / 90) * 0.18;
  }

  // 双页仿真：半页翻转超过 90° 后显示真实纸背（对应相邻屏的页内容）
  private halfBackFace(i: number, left: boolean): boolean {
    if (this.animMode !== 'curl' || this.mode !== 'double') {
      return false;
    }
    const angle = left ? this.transAngleL[i] : this.transAngleR[i];
    return Math.abs(angle) > 90;
  }

  // 单页与双页的仿真卷曲均由 EmulationFlipView 接管。此处只服务滑动与覆盖。
  // proxy.position 为该页相对动画起始位置的位移比例（负=向左），默认位移=position*mainAxisLength，
  // 以负向 translate 抵消默认位移后叠加自定义变换。
  private onContentTransition(proxy: SwiperContentTransitionProxy): void {
    const i = proxy.index;
    if (i < 0 || i >= this.transX.length) {
      return;
    }
    const p = proxy.position;
    const settled = Math.abs(p - Math.round(p)) < 0.001;
    if (this.animMode === 'slide' || settled || (this.animMode === 'curl' && this.mode !== 'double')) {
      this.setPageTransform(i, 0, 0, 0);
      this.setHalfAngle(i, 0, 0);
      if (this.halfTilt !== 0) {
        this.halfTilt = 0;
      }
      return;
    }
    const L = proxy.mainAxisLength;
    const S = proxy.selectedIndex;
    const rtl = this.mode === 'paged_rtl';
    const isDouble = this.mode === 'double';
    if (i === S) {
      const goingNext = rtl ? p > 0 : p < 0;
      if (this.animMode === 'cover') {
        if (goingNext) {
          this.setPageTransform(i, -p * L, 0, 0);
        } else {
          this.setPageTransform(i, 0, 0, 2);
        }
        if (this.halfTilt !== 0) {
          this.halfTilt = 0;
        }
        return;
      }
      if (isDouble) {
        this.setPageTransform(i, -p * L, 0, 2);
        const tilt = Math.max(-1, Math.min(1, (this.flipGrabY - 0.5) * 2)) * 20 * Math.sin(Math.PI * Math.abs(p));
        if (goingNext) {
          this.setHalfAngle(i, 0, -180 * Math.abs(p));
        } else {
          this.setHalfAngle(i, 180 * Math.abs(p), 0);
        }
        this.halfTilt = tilt;
      }
    } else if (i === S + 1) {
      if (this.animMode === 'cover') {
        this.setPageTransform(i, 0, 0, 2);
      } else if (isDouble) {
        this.setPageTransform(i, -p * L, 0, 0);
        this.setHalfAngle(i, 0, 0);
      }
    } else if (i === S - 1) {
      if (this.animMode === 'cover') {
        this.setPageTransform(i, -p * L, 0, 0);
      } else if (isDouble) {
        this.setPageTransform(i, -p * L, 0, 0);
        this.setHalfAngle(i, 0, 0);
      }
    } else {
      this.setPageTransform(i, 0, 0, 0);
      this.setHalfAngle(i, 0, 0);
    }
  }

  // 单页仿真：阅读顺序页码（从右到左时与屏幕序相反）
  private readingIndex(): number {
    const count = this.screenIdxs.length;
    if (count <= 0) {
      return 0;
    }
    if (this.mode === 'paged_rtl') {
      return count - 1 - this.pageIdx;
    }
    return this.pageIdx;
  }

  // 仿真卷曲。双页只翻外侧半页（一页），另一半保持不动；纸背是下一页正文。
  private curlActive(): boolean {
    return this.animMode === 'curl' && this.mode !== 'scroll';
  }

  private requestLeaf(dir: number): void {
    this.leafTurn = dir > 0 ? Math.abs(this.leafTurn) + 1 : -(Math.abs(this.leafTurn) + 1);
  }

  // onLeaf=false 时 localX 属于左侧静止页；true 时属于右侧翻动页（中缝 SPINE_W vp）
  private onSpreadTap(localX: number, onLeaf: boolean): void {
    if (this.anySheetOpen()) {
      this.dismissSheets();
      return;
    }
    const inner = this.contW - this.pageMargin * 2;
    if (inner <= 0) {
      this.contentTap();
      return;
    }
    const half = (inner - SPINE_W) / 2;
    const globalX = onLeaf ? half + SPINE_W + localX : localX;
    if (globalX < inner * 0.3) {
      this.requestLeaf(-1);
    } else if (globalX > inner * 0.7) {
      this.requestLeaf(1);
    } else {
      this.contentTap();
    }
  }

  private onCurlIndex(reading: number): void {
    const count = this.screenIdxs.length;
    if (count <= 0) {
      return;
    }
    const screen = this.mode === 'paged_rtl' ? count - 1 - reading : reading;
    if (screen < 0 || screen >= count) {
      return;
    }
    this.onScreenChange(screen);
  }

  private onCurlOverscroll(dir: number): void {
    if (this.anySheetOpen()) {
      this.dismissSheets();
      return;
    }
    this.openChapter(dir > 0 ? this.nextId : this.prevId);
  }

  @Builder
  curlPageBody(index: number) {
    Row() {
      this.PageText(index)
    }
    .width('100%')
    .height('100%')
  }

  // 双页右侧正在翻的那一页
  @Builder
  leafFront(index: number) {
    this.PageText(index * 2 + 1)
  }

  // 这一页的背面：下一页正文（折痕镜像后显示在纸背）
  @Builder
  leafBack(index: number) {
    this.PageText(index * 2 + 2)
  }

  @Builder
  DoubleLeaf() {
    Row() {
      Column() {
        this.PageText(this.pageIdx * 2)
      }
      .layoutWeight(1)
      .height('100%')
      .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
      .onClick((event: ClickEvent) => {
        this.onSpreadTap(event.x, false);
      })

      Column() {
        Divider()
          .vertical(true)
          .strokeWidth(1)
          .color('#66808080')
          .height('70%')
      }
      .width(SPINE_W)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))

      EmulationFlipView({
        index: this.pageIdx,
        pageCount: this.screenIdxs.length,
        fromLeft: false,
        nextOnLeft: false,
        tapMode: 'horizontal',
        flipEnabled: !this.anySheetOpen(),
        showBack: true,
        ownTap: false,
        turnToken: this.leafTurn,
        bgColor: Theme.readerBg(this.readerTheme, this.isDark),
        onIndexChange: (index: number): void => {
          this.onCurlIndex(index);
        },
        onCenterTap: (): void => {
          this.contentTap();
        },
        onOverscroll: (dir: number): void => {
          this.onCurlOverscroll(dir);
        },
        onAreaTap: (x: number, _y: number): void => {
          this.onSpreadTap(x, true);
        },
        pageContent: (index: number): void => {
          this.leafFront(index);
        },
        backContent: (index: number): void => {
          this.leafBack(index);
        }
      })
        .layoutWeight(1)
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  // 单页正文：插图页独占整页；文本页段间距为 0 时合并为单个 Text（大章节性能友好），
  // >0 时按段落 Column({space}) 渲染
  @Builder
  PageText(pIdx: number) {
    if (this.pageImageUrl(pIdx) !== '') {
      Image(this.pageImageUrl(pIdx))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
    } else if (this.paraSpacing > 0) {
      Column({ space: this.paraSpacing }) {
        ForEach(this.pageTexts(pIdx), (para: string, i: number) => {
          Text(para)
            .fontSize(this.fontSize)
            .lineHeight(this.lineHeight)
            .fontFamily(this.fontFamilyVal())
            .fontColor(this.readerTextCol())
            .width('100%')
        }, (para: string, i: number) => `${this.pagSig}#${pIdx}#${i}`)
      }
      .layoutWeight(1)
      .height('100%')
    } else {
      Text(this.pageTexts(pIdx).join('\n'))
        .fontSize(this.fontSize)
        .lineHeight(this.lineHeight)
        .fontFamily(this.fontFamilyVal())
        .fontColor(this.readerTextCol())
        .layoutWeight(1)
        .height('100%')
    }
  }

  // Swiper 一屏：双页=左右两页 + 中缝分隔线；从右到左=屏幕索引与页序相反；单页=一页
  @Builder
  PageScreen(sIdx: number) {
    if (this.mode === 'double') {
      Row() {
        // 左半页：仿真后退时绕中线（书脊）从左翻回，翻过 90° 后显示真实纸背（上一屏右页）
        Stack() {
          if (this.halfBackFace(sIdx, true)) {
            Column() {
              this.PageText(sIdx * 2 - 1)
            }
            .width('100%')
            .height('100%')
            .scale({ x: -1 })
          } else {
            this.PageText(sIdx * 2)
          }
          // 卷曲阴影：书脊侧（右缘）加深，页面竖起时最深
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 270,
              colors: [['#52000000', 0], ['#00000000', 0.75]]
            })
            .opacity(this.curlShade(this.transAngleL[sIdx]))
            .hitTestBehavior(HitTestMode.None)
        }
        .layoutWeight(1)
        .height('100%')
        .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
        .translate({ y: this.transAngleL[sIdx] !== 0 ? this.halfTilt : 0 })
        .rotate({
          x: 0,
          y: 1,
          z: 0,
          angle: this.transAngleL[sIdx],
          centerX: '100%',
          centerY: '50%',
          perspective: this.flipPerspective()
        })
        .zIndex(this.transAngleL[sIdx] !== 0 ? 2 : 0)
        .shadow(this.flipShadow(this.transAngleL[sIdx] !== 0))

        // 中缝书脊（固定不动）
        Column() {
          Divider()
            .vertical(true)
            .strokeWidth('1vp')
            .color('#66808080')
            .height('70%')
        }
        .width(SPINE_W)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))

        // 右半页：仿真前进时绕中线（书脊）翻向左侧，翻过 90° 后显示真实纸背（下一屏左页）
        Stack() {
          if (this.halfBackFace(sIdx, false)) {
            Column() {
              this.PageText(sIdx * 2 + 2)
            }
            .width('100%')
            .height('100%')
            .scale({ x: -1 })
          } else {
            this.PageText(sIdx * 2 + 1)
          }
          // 卷曲阴影：书脊侧（左缘）加深，页面竖起时最深
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 90,
              colors: [['#52000000', 0], ['#00000000', 0.75]]
            })
            .opacity(this.curlShade(this.transAngleR[sIdx]))
            .hitTestBehavior(HitTestMode.None)
        }
        .layoutWeight(1)
        .height('100%')
        .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
        .translate({ y: this.transAngleR[sIdx] !== 0 ? this.halfTilt : 0 })
        .rotate({
          x: 0,
          y: 1,
          z: 0,
          angle: this.transAngleR[sIdx],
          centerX: '0%',
          centerY: '50%',
          perspective: this.flipPerspective()
        })
        .zIndex(this.transAngleR[sIdx] !== 0 ? 2 : 0)
        .shadow(this.flipShadow(this.transAngleR[sIdx] !== 0))
      }
      .width('100%')
      .height('100%')
    } else if (this.mode === 'paged_rtl') {
      Row() {
        this.PageText(this.pages.length - 1 - sIdx)
      }
      .width('100%')
      .height('100%')
    } else {
      Row() {
        this.PageText(sIdx)
      }
      .width('100%')
      .height('100%')
    }
  }

  // 滚动模式正文：含插图 html 按块渲染（文本段 + 内嵌插图）；
  // 纯文本按段间距设置选择整段 Text 或分段 Column
  @Builder
  ScrollBody() {
    if (this.hasImages) {
      Column({ space: this.paraSpacing }) {
        ForEach(this.blocks, (block: NovelBlock, i: number) => {
          if (block.isImage) {
            Image(block.text)
              .width('100%')
              .objectFit(ImageFit.Contain)
              .borderRadius(6)
              .constraintSize({ maxHeight: this.viewH > 0 ? this.viewH * 0.7 : 480 })
              .margin({ top: 8, bottom: 8 })
          } else {
            Text(block.text)
              .fontSize(this.fontSize)
              .lineHeight(this.lineHeight)
              .fontFamily(this.fontFamilyVal())
              .fontColor(this.readerTextCol())
              .width('100%')
              .backgroundColor(this.ttsParaIdx === block.ttsIdx ? '#2E808080' : Color.Transparent)
              .borderRadius(this.ttsParaIdx === block.ttsIdx ? 4 : 0)
          }
        }, (block: NovelBlock, i: number) => `${i}#${block.isImage}#${block.text.length}`)
      }
      .width('100%')
    } else if (this.paraSpacing > 0) {
      Column({ space: this.paraSpacing }) {
        ForEach(this.scrollParas(), (para: string, i: number) => {
          Text(para === '' ? ' ' : para)
            .fontSize(this.fontSize)
            .lineHeight(this.lineHeight)
            .fontFamily(this.fontFamilyVal())
            .fontColor(this.readerTextCol())
            .width('100%')
            .backgroundColor(this.ttsParaIdx === i ? '#2E808080' : Color.Transparent)
            .borderRadius(this.ttsParaIdx === i ? 4 : 0)
        }, (para: string, i: number) => `${this.body.length}#${i}#${para.length}`)
      }
      .width('100%')
    } else {
      Text(this.body)
        .fontSize(this.fontSize)
        .lineHeight(this.lineHeight)
        .fontFamily(this.fontFamilyVal())
        .fontColor(this.readerTextCol())
        .width('100%')
    }
  }

  // ---- 菜单（共享 ReaderChrome 骨架：顶栏+占位+底栏，样式与拆分前一致） ----

  @Builder
  menuBottomBar() {
    ReaderBottomBar({
      navBarH: this.navBarH,
      navRow: (): void => {
        this.menuNavRow();
      },
      settingsRow: (): void => {
        this.menuSettingsRow();
      }
    })
  }

  // 章节导航行：上一章 / 进度胶囊 / 下一章（guard 保留在回调内）
  @Builder
  menuNavRow() {
    ReaderNavRow({
      prevActive: this.prevId > 0,
      nextActive: this.nextId > 0,
      pill: (): void => {
        this.menuNavPill();
      },
      onPrev: (): void => {
        if (this.prevId > 0) {
          this.openChapter(this.prevId);
        }
      },
      onNext: (): void => {
        if (this.nextId > 0) {
          this.openChapter(this.nextId);
        }
      }
    })
  }

  // 进度胶囊：滚动=百分比 Slider，翻页/双页=页码胶囊（ReaderPagePill），无屏=空占位
  @Builder
  menuNavPill() {
    if (this.mode === 'scroll') {
      Row() {
        Text(`${Math.round(this.permilleUi / 10)}%`)
          .fontSize(13)
          .fontColor('#FFFFFF')
          .width(44)
          .textAlign(TextAlign.End)
        Slider({
          value: this.permilleUi,
          min: 0,
          max: 1000,
          step: 1,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .blockColor('#FFFFFF')
          .selectedColor('#88FFFFFF')
          .trackColor('#33FFFFFF')
          .margin({ left: 8, right: 8 })
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.scrollToPermille(Math.round(value));
            }
          })
        Text('100%')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .width(44)
      }
      .layoutWeight(1)
      .height(44)
      .borderRadius(22)
      .backgroundColor('#33FFFFFF')
      .padding({ left: 14, right: 14 })
    } else if (this.screenIdxs.length > 0) {
      ReaderPagePill({
        pos: this.pagedSliderPos(),
        total: this.screenIdxs.length,
        onSeek: (value: number): void => {
          this.jumpScreen(this.pagedScreenFromSlider(value));
        }
      })
    } else {
      Column().layoutWeight(1)
    }
  }

  // 设置行：阅读模式 / 屏幕方向 / 画面 / 文本 / 听书
  @Builder
  menuSettingsRow() {
    Row() {
      ReaderMenuIconButton({
        icon: this.novelModeIcon(),
        onTap: (): void => {
          this.openSheet('mode');
        }
      })
      ReaderMenuIconButton({
        icon: 'screen_rotation',
        onTap: (): void => {
          this.openSheet('orientation');
        }
      })
      ReaderMenuIconButton({
        icon: 'palette',
        onTap: (): void => {
          this.openSheet('display');
        }
      })
      ReaderMenuIconButton({
        icon: 'format_size',
        onTap: (): void => {
          this.openSheet('text');
        }
      })
      ReaderMenuIconButton({
        icon: this.ttsPlaying ? 'pause' : 'playlist_play',
        onTap: (): void => {
          this.startTtsAndOpenPlayer();
        }
      })
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.SpaceEvenly)
    .backgroundColor('#CC000000')
  }

  @Builder
  orientationSheetBuilder() {
    ReaderOrientationSheet({
      selected: this.orientation,
      onPick: (v: string): void => {
        this.showOrientationSheet = false;
        this.orientation = v;
        Settings.setNovelOrientation(v);
        this.applyOrientation();
      }
    })
  }

  // 底栏阅读模式图标（随当前模式变化）
  private novelModeIcon(): string {
    if (this.mode === 'paged') {
      return 'reader_ltr';
    }
    if (this.mode === 'paged_rtl') {
      return 'reader_rtl';
    }
    if (this.mode === 'double') {
      return 'reader_double';
    }
    return 'reader_scroll';
  }

  // 阅读模式选择 + 翻页动画
  @Builder
  modeSheetBuilder() {
    NovelModeSheet({
      mode: this.mode,
      animMode: this.animMode,
      onMode: (v: string): void => {
        this.showModeSheet = false;
        this.setMode(v);
      },
      onAnim: (v: string): void => {
        this.setAnimMode(v);
      }
    })
  }

  // 底栏设置面板标题（画面 / 文本共用一个 bindSheet）
  private panelTitleRes(): ResourceStr {
    if (this.panelKind === 'text') {
      return $r('app.string.novel_tab_text');
    }
    return $r('app.string.novel_tab_display');
  }

  // 底栏设置面板内容：按 panelKind 切换（同一节点只允许一个生效的 bindSheet，多绑会互相顶掉）
  @Builder
  panelSheetBuilder() {
    if (this.panelKind === 'display') {
      NovelDisplayPanel({
        brightLv: this.brightLv,
        colorScheme: this.colorScheme,
        readerTheme: this.readerTheme,
        onBrightness: (v: number): void => {
          this.brightLv = v;
          Settings.setReaderBrightness(v);
          this.applyBrightness();
        },
        onColorScheme: (v: string): void => {
          this.colorScheme = v;
          Settings.setNovelColorScheme(v);
        },
        onTheme: (v: number): void => {
          this.readerTheme = v;
          Settings.setReaderTheme(v);
        }
      })
    } else if (this.panelKind === 'text') {
      NovelTextPanel({
        fontSize: this.fontSize,
        pageMargin: this.pageMargin,
        paraSpacing: this.paraSpacing,
        lineHeight: this.lineHeight,
        fontFamily: this.fontFamily,
        onFontSizeDone: (v: number): void => {
          Settings.setNovelFontSize(v);
          this.ensurePaginated();
        },
        onMarginDone: (v: number): void => {
          Settings.setNovelMargin(v);
          this.ensurePaginated();
        },
        onParaSpacingDone: (v: number): void => {
          Settings.setNovelParagraphSpacing(v);
          this.ensurePaginated();
        },
        onLineHeightDone: (v: number): void => {
          Settings.setNovelLineHeight(v);
          this.ensurePaginated();
        },
        onFontFamily: (v: string): void => {
          this.fontFamily = v;
          Settings.setNovelFontFamily(v);
          this.ensurePaginated();
        }
      })
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        // 内容区
        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.pal.primary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.contentTap();
          })
        } else if (this.body === '') {
          Column() {
            Text($r('app.string.novel_empty'))
              .fontSize(14)
              .fontColor(this.pal.sub)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.contentTap();
          })
        } else if (this.mode === 'scroll') {
          Scroll(this.scroller) {
            Column() {
              this.ScrollBody()
            }
            .width('100%')
            .padding({ left: this.pageMargin, right: this.pageMargin, top: this.statusBarH + 16, bottom: this.navBarH + 24 })
            .onAreaChange((_old: Area, neu: Area) => {
              const h = neu.height;
              if (typeof h === 'number') {
                this.contentH = h;
                this.restoreOnce();
              }
            })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .onAreaChange((_old: Area, neu: Area) => {
            const w = neu.width;
            const h = neu.height;
            if (typeof w === 'number') {
              this.scrollW = w;
            }
            if (typeof h === 'number') {
              this.viewH = h;
              this.restoreOnce();
            }
          })
          .onDidScroll((_x: number, y: number, _state: ScrollState) => {
            this.captureOffset(y);
          })
          .onScrollStop(() => {
            this.permilleUi = this.permille;
            this.persist();
          })
          .onClick(() => {
            this.contentTap();
          })
        } else {
          Column() {
            if (this.curlActive() && this.mode === 'double') {
              this.DoubleLeaf()
            } else if (this.curlActive()) {
              EmulationFlipView({
                index: this.readingIndex(),
                pageCount: this.screenIdxs.length,
                fromLeft: this.mode === 'paged_rtl',
                nextOnLeft: this.mode === 'paged_rtl',
                tapMode: 'horizontal',
                flipEnabled: !this.anySheetOpen(),
                bgColor: Theme.readerBg(this.readerTheme, this.isDark),
                onIndexChange: (index: number): void => {
                  this.onCurlIndex(index);
                },
                onCenterTap: (): void => {
                  this.contentTap();
                },
                onOverscroll: (dir: number): void => {
                  this.onCurlOverscroll(dir);
                },
                pageContent: (index: number): void => {
                  this.curlPageBody(index)
                }
              })
                .width('100%')
                .height('100%')
            } else {
            Swiper(this.swiperCtrl) {
              LazyForEach(this.screenSource, (sIdx: number) => {
                // 每屏包一层容器：translate/zIndex 仅能挂在实体组件上；
                // 双页模式容器透明（遮盖由左右半页承担），单页模式整屏不透明。
                Stack() {
                    this.PageScreen(sIdx)
                }
                .width('100%')
                .height('100%')
                .backgroundColor(this.mode === 'double' ? Color.Transparent :
                  Theme.readerBg(this.readerTheme, this.isDark))
                .translate({ x: this.transX[sIdx] })
                .zIndex(this.transZ[sIdx])
              }, (sIdx: number) => `${this.pagSig}#${sIdx}`)
            }
            .width('100%')
            .height('100%')
            .loop(false)
            .indicator(false)
            .index(this.pageIdx)
            .customContentTransition({
              timeout: 1000,
              transition: (proxy: SwiperContentTransitionProxy) => {
                this.onContentTransition(proxy);
              }
            })
            .onChange((idx: number) => {
              this.onScreenChange(idx);
            })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down || event.type === TouchType.Move) {
                this.updateGrabY(event.touches[0].y);
              }
            })
            }
          }
          .width('100%')
          .height('100%')
          .padding({ left: this.pageMargin, right: this.pageMargin, top: this.statusBarH + 8, bottom: this.navBarH + 8 })
          .onAreaChange((_old: Area, neu: Area) => {
            const w = neu.width;
            const h = neu.height;
            if (typeof w === 'number' && typeof h === 'number') {
              this.contW = w;
              this.contH = h;
              this.ensurePaginated();
            }
          })
          .onClick((event: ClickEvent) => {
            if (!this.curlActive()) {
              this.handleTap(event);
            }
          })
        }

        // 加载中：PC 无返回手势，左上角返回 + ESC 兜底退出，避免卡在加载页等网络超时
        if (this.loading) {
          LoadingBackButton({
            onBack: (): void => {
              this.pathStack.pop();
            }
          })
        }

        // 进度/页码指示（菜单收起时）
        if (!this.showMenu && !this.loading && this.body !== '' && this.showPageNumber &&
          this.indicatorText() !== '') {
          ReaderIndicatorBadge({
            text: this.indicatorText(),
            navBarH: this.navBarH
          })
        }

        // 菜单：顶栏 + 点击关闭占位 + 底栏（章节导航行 + 设置行）
        if (this.showMenu) {
          ReaderMenu({
            title: this.manga.title,
            subtitle: this.chapter.name,
            statusBarH: this.statusBarH,
            onBack: (): void => {
              this.pathStack.pop();
            },
            onBackdrop: (): void => {
              if (this.anySheetOpen()) {
                this.dismissSheets();
                return;
              }
              this.showMenu = false;
            },
            bottomBar: (): void => {
              this.menuBottomBar();
            }
          })
        }

        // 设置面板 bindSheet 常驻宿主：挂 if(showMenu) 条件节点时菜单收起即销毁宿主，弹层不可靠；
        // 同一节点链式绑定多个 bindSheet 只有最后一个生效，故用独立常驻节点承载
        Column()
          .width(0)
          .height(0)
          .hitTestBehavior(HitTestMode.None)
          .bindSheet($$this.showPanelSheet, this.panelSheetBuilder(), {
            preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
            width: Bp.isWide(this.windowW) ? 560 : '100%',
            height: SheetSize.FIT_CONTENT,
            title: { title: this.panelTitleRes() },
            detents: [SheetSize.FIT_CONTENT],
            dragBar: true,
            showClose: false,
            blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
            enableOutsideInteractive: true
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
      .bindSheet($$this.showModeSheet, this.modeSheetBuilder(), {
        preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
        width: Bp.isWide(this.windowW) ? 560 : '100%',
        height: SheetSize.FIT_CONTENT,
        title: { title: $r('app.string.reader_reading_mode') },
        detents: [SheetSize.FIT_CONTENT],
        dragBar: true,
        showClose: false,
        blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
        enableOutsideInteractive: true
      })
    }
    .hideTitleBar(true)
    .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
    .bindSheet($$this.showOrientationSheet, this.orientationSheetBuilder(), {
      preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
      width: Bp.isWide(this.windowW) ? 560 : '100%',
      height: SheetSize.FIT_CONTENT,
      title: { title: $r('app.string.reader_screen_orientation') },
      detents: [SheetSize.FIT_CONTENT],
      dragBar: true,
      showClose: false,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      enableOutsideInteractive: true
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as ReaderParams;
      if (params !== undefined && params !== null) {
        this.mangaId = params.mangaId;
        this.chapterId = params.chapterId;
      }
      this.loadChapter();
    })
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function NovelReaderBuilder() {
  NovelReaderPage()
}
