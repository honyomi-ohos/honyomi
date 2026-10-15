import { motion } from '@kit.MultimodalAwarenessKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, HistoryRepo } from '../data/Repos';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { SourceRegistry } from '../source/Source';
import { MangaRecord, ChapterRecord, SPage } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';
import { Theme, ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { GripSupport } from '../common/GripSupport';
import { ReaderWindow } from '../common/ReaderWindow';
import { ReaderChapterNav, ChapterNeighbors } from '../common/ReaderChapterNav';
import { DownloadService } from '../data/DownloadService';
import { TrackService } from '../data/track/TrackService';
import { SmartImage } from './components/SmartImage';
import { ComicStripViewer, STRIP_LEAD_COUNT } from './components/ComicStripViewer';
import { SwitchRow, TextRow } from './components/Prefs';
import { PickerSheet } from './components/PickerSheet';
import { EmulationFlipView } from './components/PageFlip';
import {
  ReaderMenu,
  ReaderBottomBar,
  ReaderNavRow,
  ReaderPagePill,
  ReaderMenuIconButton,
  ReaderIndicatorBadge,
  ReaderOrientationSheet,
  ReaderFilterArea,
  ReaderTransition
} from './components/ReaderChrome';
import { LoadingBackButton } from './components/LoadingBackButton';

// 章节过渡标记页（PageDataSource 混入的伪页，url 为保留前缀，index 为负）：
// 翻到章节边界时展示上一章/下一章过渡视图（对齐 Mihon ChapterTransition）
const TRANS_PREV_URL: string = '@@transition/prev';
const TRANS_NEXT_URL: string = '@@transition/next';

// LazyForEach 数据源
class PageDataSource implements IDataSource {
  private pages: SPage[] = [];
  private listeners: DataChangeListener[] = [];

  setPages(pages: SPage[]): void {
    this.pages = pages;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.pages.length;
  }

  getData(index: number): SPage {
    return this.pages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }
}

// 阅读器：翻页(LTR) / 右到左(RTL) / 条漫(Webtoon) 三模式
// 底栏对齐 Mihon：章节导航行（圆形上/下一章按钮 + 页码胶囊 Slider）+ 设置行（模式/旋转/裁边/设置）
@Component
export struct ReaderPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @StorageLink('libDirty') libDirty: number = 0;
  @State manga: MangaRecord = new MangaRecord();
  @State chapter: ChapterRecord = new ChapterRecord();
  @State pages: SPage[] = [];
  @State mode: string = 'ltr';
  @State displayIndex: number = 0;
  @State currentReal: number = 0;
  @State showMenu: boolean = false;
  @State showSettings: boolean = false;
  @State showModeSheet: boolean = false;
  @State showOrientationSheet: boolean = false;
  @State loading: boolean = true;
  @State hasPrev: boolean = false;
  @State hasNext: boolean = false;
  // 相邻章节名（过渡视图展示；空串表示无相邻章节）
  @State prevChapterName: string = '';
  @State nextChapterName: string = '';
  // 仿真翻页边界的章节过渡覆盖层：1=下一章过渡，-1=上一章过渡，0=无
  @State transOverlay: number = 0;
  @State crop: boolean = false;
  @State readerTheme: number = 3;
  @State brightLv: number = 0;
  @State showPageNumber: boolean = true;
  @State orientation: string = 'free';
  // 阅读器设置面板 tab：0=阅读模式 1=常规 2=滤镜（参考 Mihon）
  @State settingsTab: number = 0;
  // 滤镜（灰度/反色为开关；亮度/对比度/饱和度有开关+百分比，100=原始）
  @State filterGrayscale: boolean = false;
  @State filterInvert: boolean = false;
  @State filterBrightnessOn: boolean = false;
  @State filterBrightness: number = 100;
  @State filterContrastOn: boolean = false;
  @State filterContrast: number = 100;
  @State filterSaturationOn: boolean = false;
  @State filterSaturation: number = 100;
  // 点击翻页区域导航：'default','ltr','rtl','vertical','edge','none'
  @State navMode: string = 'default';
  // 双页显示（横向分页模式生效）
  @State dualPage: boolean = false;
  // 条漫侧边距（%）
  @State webtoonPadding: number = 0;
  // 翻页动画：curl=仿真 slide=滑动 cover=覆盖（条漫与垂直模式不走仿真）
  @State pageAnim: string = 'slide';
  // 双页只翻一侧时的触发序号：正数下一页，负数上一页
  @State leafTurn: number = 0;
  @State coverX: number[] = [];
  @State coverY: number[] = [];
  @State coverZ: number[] = [];
  // 智感握姿：握持侧即“下一页”热区（true=右手握持/右侧翻下一页）
  @State gripRight: boolean = true;
  // 设备是否支持智感握姿（不支持则隐藏该模式选项）
  @State gripSupported: boolean = true;
  private gripListening: boolean = false;
  private handleHoldingHandChange: (status: motion.HoldingHandStatus) => void =
    (status: motion.HoldingHandStatus): void => {
      if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
        if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
          this.gripRight = false;
        } else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
          this.gripRight = true;
        }
      }
    };
  private dataSource: PageDataSource = new PageDataSource();
  private scroller: Scroller = new Scroller();
  private touchDownX: number = -1;
  private touchDownY: number = -1;
  // 阅读器实际内容宽度/高度（vp）：平板分屏/悬浮窗/旋转下以组件实时宽高计算点击分区
  private readerW: number = 360;
  private readerH: number = 640;
  private mangaId: number = -1;
  private chapterId: number = -1;
  // 章节加载代次号：连续切章时旧 loadChapter 续体据此丢弃
  private loadGen: number = 0;
  // 边界触发的切章落点：1=下一章落在首页，-1=上一章落在末页，0=按历史进度恢复
  private gotoBoundary: number = 0;
  // 条漫续读定位定时器 id（aboutToDisappear 清除）
  private resumeTimerId: number = -1;
  // 内容区在窗口中的偏移（TouchObject.x/y 为窗口坐标，点击热区需换算为组件内坐标）
  private readerOffX: number = 0;
  private readerOffY: number = 0;

  aboutToAppear(): void {
    this.gripSupported = GripSupport.isSupported();
    this.crop = Settings.getReaderCrop();
    this.readerTheme = Settings.getReaderTheme();
    this.brightLv = Settings.getReaderBrightness();
    this.showPageNumber = Settings.getReaderShowPageNumber();
    this.orientation = Settings.getReaderOrientation();
    this.filterGrayscale = Settings.getReaderGrayscale();
    this.filterInvert = Settings.getReaderInvert();
    this.filterBrightnessOn = Settings.getReaderBrightnessEnabled();
    this.filterBrightness = Settings.getReaderFilterBrightness();
    this.filterContrastOn = Settings.getReaderContrastEnabled();
    this.filterContrast = Settings.getReaderContrast();
    this.filterSaturationOn = Settings.getReaderSaturationEnabled();
    this.filterSaturation = Settings.getReaderSaturation();
    this.navMode = Settings.getReaderNavMode();
    this.pageAnim = Settings.getReaderPageAnim();
    this.dualPage = Settings.getReaderDualPage();
    this.webtoonPadding = Settings.getReaderWebtoonPadding();
    this.applyOrientation();
    this.applyBrightness();
  }

  aboutToDisappear(): void {
    this.libDirty += 1;
    ReadingStatsRepo.flush();
    this.updateGripListener(false);
    if (this.resumeTimerId !== -1) {
      clearTimeout(this.resumeTimerId);
      this.resumeTimerId = -1;
    }
    // 还原窗口方向与亮度
    ReaderWindow.restore(Util.hostAbilityContext(this.getUIContext()));
  }

  // 智感握姿：订阅/退订握持手感知（want=false 强制退订）
  private updateGripListener(want: boolean): void {
    const shouldListen: boolean = want && this.mode === 'smart_grip' && this.gripSupported;
    if (shouldListen && !this.gripListening) {
      if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
        try {
          motion.on('holdingHandChanged', this.handleHoldingHandChange);
          this.gripListening = true;
        } catch (error) {
          hilog.warn(0x0001, 'Reader', 'subscribe holdingHandChanged failed: %{public}s', `${error}`);
        }
      }
    } else if (!shouldListen && this.gripListening) {
      if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
        try {
          motion.off('holdingHandChanged', this.handleHoldingHandChange);
        } catch (error) {
          hilog.warn(0x0001, 'Reader', 'unsubscribe holdingHandChanged failed: %{public}s', `${error}`);
        }
      }
      this.gripListening = false;
    }
  }

  private applyOrientation(): void {
    ReaderWindow.applyOrientation(Util.hostAbilityContext(this.getUIContext()), this.orientation);
  }

  private applyBrightness(): void {
    ReaderWindow.applyBrightness(Util.hostAbilityContext(this.getUIContext()), this.brightLv);
  }

  // 记录内容区尺寸与组件在窗口中的全局偏移（globalPosition），供点击热区换算
  private syncReaderArea(newArea: Area): void {
    const w = newArea.width;
    if (typeof w === 'number' && w > 0) {
      this.readerW = w;
    }
    const h = newArea.height;
    if (typeof h === 'number' && h > 0) {
      this.readerH = h;
    }
    const gp = newArea.globalPosition;
    const gx = gp.x;
    if (typeof gx === 'number') {
      this.readerOffX = gx;
    }
    const gy = gp.y;
    if (typeof gy === 'number') {
      this.readerOffY = gy;
    }
  }

  private async loadChapter(): Promise<void> {
    const gen = ++this.loadGen;
    this.loading = true;
    this.showMenu = false;
    this.transOverlay = 0;
    // 切章：先结算上一章的阅读会话
    ReadingStatsRepo.flush();
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      if (gen !== this.loadGen) {
        return;
      }
      const chapter = await ChapterRepo.getById(this.chapterId);
      if (gen !== this.loadGen) {
        return;
      }
      if (chapter === undefined) {
        Util.toastRes(this.getUIContext(), $r('app.string.reader_chapter_not_found'));
        this.pathStack.pop();
        return;
      }
      this.chapter = chapter;
      this.mangaId = chapter.mangaId;
      const manga = await MangaRepo.get(chapter.mangaId);
      if (gen !== this.loadGen) {
        return;
      }
      if (manga !== undefined) {
        this.manga = manga;
      }
      let pages: SPage[] = [];
      if (DownloadService.isDownloaded(chapter.id)) {
        // 离线优先：读取已下载的本地页面
        const files: string[] = DownloadService.localPages(chapter.mangaId, chapter.id);
        for (let i = 0; i < files.length; i++) {
          const p: SPage = { index: i, url: `file://${files[i]}` };
          pages.push(p);
        }
      } else {
        const source = SourceRegistry.get(this.manga.sourceKey);
        if (source === undefined) {
          throw new Error('source_unavailable');
        }
        pages = await source.getPageList(chapter.url);
      }
      if (gen !== this.loadGen) {
        return;
      }
      this.pages = pages;
      this.mode = Settings.getReaderMode();
      // 历史保存的智感握姿在当前设备不支持时，静默回退为从左到右
      if (this.mode === 'smart_grip' && !this.gripSupported) {
        this.mode = 'ltr';
      }
      // 边界切章落点：向前进下一章落在首页，向回退上一章落在末页（对齐 Mihon 无缝切换）；
      // 菜单按钮切章按历史进度恢复
      if (this.gotoBoundary < 0 && pages.length > 0) {
        this.currentReal = pages.length - 1;
      } else if (this.gotoBoundary > 0) {
        this.currentReal = 0;
      } else {
        this.currentReal = chapter.lastPageRead > 0 && chapter.lastPageRead < pages.length
          ? chapter.lastPageRead : 0;
      }
      this.gotoBoundary = 0;
      await this.refreshNeighbors();
      if (gen !== this.loadGen) {
        return;
      }
      this.applyMode(true);
      await HistoryRepo.upsert(chapter.mangaId, chapter.id, this.currentReal);
      if (gen !== this.loadGen) {
        return;
      }
      // 开始本章的阅读时长计时
      ReadingStatsRepo.begin(chapter.mangaId, chapter.id);
    } catch (e) {
      // 加载失败清空旧章页面，防止旧页码经 persistProgress 写入本章进度
      if (gen === this.loadGen) {
        this.pages = [];
        Util.toastRes(this.getUIContext(), $r('app.string.reader_load_failed'),
          [Util.errText(this.getUIContext(), e instanceof Error ? e.message : String(e))]);
      }
    }
    if (gen !== this.loadGen) {
      return;
    }
    this.loading = false;
  }

  private async refreshNeighbors(): Promise<void> {
    const n: ChapterNeighbors = await ReaderChapterNav.neighbors(this.mangaId, this.chapterId);
    this.hasPrev = n.hasPrev;
    this.hasNext = n.hasNext;
    let prevName = '';
    let nextName = '';
    for (let i = 0; i < n.chapters.length; i++) {
      const c: ChapterRecord = n.chapters[i];
      if (n.prevId > 0 && c.id === n.prevId) {
        prevName = c.name;
      }
      if (n.nextId > 0 && c.id === n.nextId) {
        nextName = c.name;
      }
    }
    this.prevChapterName = prevName;
    this.nextChapterName = nextName;
  }

  // 根据模式构建展示页序（含章节边界过渡页）并恢复进度：
  // 非 RTL：[上一章过渡, 页0..页N-1, 下一章过渡]；RTL 整体反转（阅读前进 = 索引递减）
  private applyMode(scrollToResume: boolean): void {
    const cellCount = this.pages.length + 2;
    this.coverX = Util.zeros(cellCount);
    this.coverY = Util.zeros(cellCount);
    this.coverZ = Util.zeros(cellCount);
    const cells: SPage[] = [];
    const prevT: SPage = { index: -1, url: TRANS_PREV_URL };
    const nextT: SPage = { index: -2, url: TRANS_NEXT_URL };
    if (this.mode === 'rtl') {
      cells.push(nextT);
      for (let i = this.pages.length - 1; i >= 0; i--) {
        cells.push(this.pages[i]);
      }
      cells.push(prevT);
      this.dataSource.setPages(cells);
      this.displayIndex = this.pages.length - this.currentReal;
    } else {
      cells.push(prevT);
      for (let i = 0; i < this.pages.length; i++) {
        cells.push(this.pages[i]);
      }
      cells.push(nextT);
      this.dataSource.setPages(cells);
      this.displayIndex = this.currentReal + 1;
    }
    if (this.mode === 'webtoon' && scrollToResume) {
      const target = this.currentReal + STRIP_LEAD_COUNT;
      if (this.resumeTimerId !== -1) {
        clearTimeout(this.resumeTimerId);
      }
      this.resumeTimerId = setTimeout(() => {
        this.resumeTimerId = -1;
        this.scroller.scrollToIndex(target, false, ScrollAlign.START);
      }, 200);
    }
    this.updateGripListener(true);
  }

  // 展示单元格（含过渡页）→ 真实页序；过渡页换算结果越界由调用方校验
  private displayToReal(displayIdx: number): number {
    if (this.mode === 'rtl') {
      return this.pages.length - displayIdx;
    }
    return displayIdx - 1;
  }

  private realToDisplay(realIdx: number): number {
    if (this.mode === 'rtl') {
      return this.pages.length - realIdx;
    }
    return realIdx + 1;
  }

  // 展示单元格种类：'prev'/'next' 为过渡页，'' 为普通页（首尾单元格恒为过渡页）
  private cellKind(cell: number): string {
    if (cell === 0) {
      return this.mode === 'rtl' ? 'next' : 'prev';
    }
    if (cell === this.pages.length + 1) {
      return this.mode === 'rtl' ? 'prev' : 'next';
    }
    return '';
  }

  private async onSwipe(displayIdx: number): Promise<void> {
    this.displayIndex = displayIdx;
    const kind = this.cellKind(displayIdx);
    if (kind === 'next') {
      // 落在“下一章”过渡页：没有下一章时呼出菜单（对齐 Mihon），有则等待继续前翻
      if (!this.hasNext) {
        this.showMenu = true;
      }
      return;
    }
    if (kind === 'prev') {
      return;
    }
    const real = this.displayToReal(displayIdx);
    if (real !== this.currentReal) {
      this.currentReal = real;
      await this.persistProgress();
    }
  }

  private async persistProgress(): Promise<void> {
    try {
      ReadingStatsRepo.tick();
      await ChapterRepo.setLastPageRead(this.chapterId, this.currentReal);
      await HistoryRepo.upsert(this.mangaId, this.chapterId, this.currentReal);
      if (this.currentReal >= this.pages.length - 1 && !this.chapter.read) {
        this.chapter.read = true;
        await ChapterRepo.setRead(this.chapterId, true);
        TrackService.updateChapterRead(this.mangaId, this.chapterId).catch((e: Object): void => {
          hilog.warn(0x0001, 'Reader', 'track update failed: %{public}s', `${e}`);
        });
      }
    } catch (e) {
      hilog.warn(0x0001, 'Reader', 'persistProgress failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private setMode(mode: string): void {
    this.mode = mode;
    this.transOverlay = 0;
    Settings.setReaderMode(mode);
    this.applyMode(true);
  }

  private modeIcon(): string {
    if (this.mode === 'rtl') {
      return 'reader_rtl';
    }
    if (this.mode === 'webtoon') {
      return 'reader_webtoon';
    }
    if (this.mode === 'vertical') {
      return 'reader_vertical';
    }
    if (this.mode === 'smart_grip') {
      return 'smart_grip';
    }
    return 'reader_ltr';
  }

  // 当前设备可用的阅读模式（智感握姿仅在支持的设备上提供）
  private availableModes(): string[] {
    const modes: string[] = ['ltr', 'rtl', 'vertical', 'webtoon'];
    if (this.gripSupported) {
      modes.push('smart_grip');
    }
    return modes;
  }

  private modeOptions(): ResourceStr[] {
    const opts: ResourceStr[] = [$r('app.string.reader_mode_ltr'), $r('app.string.reader_mode_rtl'),
      $r('app.string.reader_mode_vertical'), $r('app.string.reader_mode_webtoon')];
    if (this.gripSupported) {
      opts.push($r('app.string.reader_mode_smart_grip'));
    }
    return opts;
  }

  private modeIcons(): string[] {
    const icons: string[] = ['reader_ltr', 'reader_rtl', 'reader_vertical', 'reader_webtoon'];
    if (this.gripSupported) {
      icons.push('smart_grip');
    }
    return icons;
  }

  private selectedModeIndex(): number {
    const idx: number = this.availableModes().indexOf(this.mode);
    return idx >= 0 ? idx : 0;
  }

  private selectMode(): void {
    this.showModeSheet = true;
  }

  @Builder
  modeSheetBuilder() {
    PickerSheet({
      options: this.modeOptions(),
      icons: this.modeIcons(),
      selectedIndex: this.selectedModeIndex(),
      onPick: (index: number): void => {
        this.showModeSheet = false;
        const m: string | undefined = this.availableModes()[index];
        if (m !== undefined) {
          this.setMode(m);
        }
      }
    })
  }

  private selectOrientation(): void {
    this.showOrientationSheet = true;
  }

  @Builder
  orientationSheetBuilder() {
    ReaderOrientationSheet({
      selected: this.orientation,
      onPick: (v: string): void => {
        this.showOrientationSheet = false;
        this.orientation = v;
        Settings.setReaderOrientation(v);
        this.applyOrientation();
      }
    })
  }

  private toggleCrop(): void {
    this.crop = !this.crop;
    Settings.setReaderCrop(this.crop);
  }

  private setCrop(v: boolean): void {
    this.crop = v;
    Settings.setReaderCrop(v);
  }

  // 双页显示：横向分页模式（LTR/RTL/智感握姿）下 Swiper 一屏两页
  private dualPageActive(): boolean {
    return this.dualPage && this.mode !== 'vertical';
  }

  // Slider 跳页（按真实页序）
  private jumpToReal(real: number): void {
    if (real < 0 || real >= this.pages.length) {
      return;
    }
    const display = this.realToDisplay(real);
    this.displayIndex = display;
    if (this.mode === 'webtoon') {
      this.scroller.scrollToIndex(display, false, ScrollAlign.START);
      this.currentReal = real;
      this.persistProgress();
    } else {
      this.onSwipe(display);
    }
  }

  // 切换相邻章节；fromBoundary=true 表示由阅读边界（过渡页）触发，
  // 下一章落在首页、上一章落在末页；菜单按钮触发按历史进度恢复
  private async gotoChapter(next: boolean, fromBoundary: boolean = false): Promise<void> {
    const targetId: number = await ReaderChapterNav.neighborChapterId(this.mangaId, this.chapterId, next);
    if (targetId === 0) {
      Util.toastRes(this.getUIContext(), next ? $r('app.string.reader_last_chapter') : $r('app.string.reader_first_chapter'));
      return;
    }
    if (next && !this.chapter.read) {
      await ChapterRepo.setRead(this.chapterId, true);
    }
    this.gotoBoundary = fromBoundary ? (next ? 1 : -1) : 0;
    this.chapterId = targetId;
    await this.loadChapter();
  }

  // 翻页模式点击区域（导航模式：默认/从左到右/从右到左/垂直/边缘/无，对齐 Mihon pref_viewer_nav）
  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      if (event.touches.length === 0) {
        return;
      }
      const down: TouchObject = event.touches[0];
      // TouchObject.x/y 为窗口坐标，减去组件在窗口中的偏移得到组件内坐标
      this.touchDownX = down.x - this.readerOffX;
      this.touchDownY = down.y - this.readerOffY;
    } else if (event.type === TouchType.Up) {
      if (this.touchDownX < 0 || event.changedTouches.length === 0) {
        return;
      }
      const up: TouchObject = event.changedTouches[0];
      const upX = up.x - this.readerOffX;
      const upY = up.y - this.readerOffY;
      const dx = Math.abs(upX - this.touchDownX);
      const dy = Math.abs(upY - this.touchDownY);
      this.touchDownX = -1;
      if (dx > 20 || dy > 20) {
        return; // 滑动，忽略
      }
      if (this.pages.length === 0) {
        return;
      }
      if (this.navMode === 'none') {
        this.showMenu = !this.showMenu;
        return;
      }
      if (this.navMode === 'vertical') {
        const zoneY = upY / (this.readerH > 0 ? this.readerH : 640);
        if (zoneY < 0.3) {
          this.step(-1);
        } else if (zoneY > 0.7) {
          this.step(1);
        } else {
          this.showMenu = !this.showMenu;
        }
        return;
      }
      const zone = upX / (this.readerW > 0 ? this.readerW : 360);
      // “下一页”是否在左侧：默认跟随阅读模式（RTL；智感握姿下左手握持时握持侧为下一页），可被导航模式覆盖
      let nextOnLeft: boolean = this.mode === 'rtl' ||
        (this.mode === 'smart_grip' && !this.gripRight);
      if (this.navMode === 'ltr') {
        nextOnLeft = false;
      } else if (this.navMode === 'rtl') {
        nextOnLeft = true;
      }
      if (this.navMode === 'edge') {
        // 边缘导航：仅屏幕左右边缘窄条翻页，其余区域切换菜单
        if (zone < 0.12) {
          this.step(nextOnLeft ? 1 : -1);
        } else if (zone > 0.88) {
          this.step(nextOnLeft ? -1 : 1);
        } else {
          this.showMenu = !this.showMenu;
        }
        return;
      }
      if (zone < 0.3) {
        // 左侧区域
        this.step(nextOnLeft ? 1 : -1);
      } else if (zone > 0.7) {
        // 右侧区域
        this.step(nextOnLeft ? -1 : 1);
      } else {
        this.showMenu = !this.showMenu;
      }
    }
  }

  // 点击热区翻页：delta 为阅读方向步进（+1 下一页，-1 上一页）。
  // RTL 展示序与阅读序相反，展示索引步进方向需取反；章节首尾垫有过渡页，
  // 在过渡页上继续前/后翻即切换章节（上一章落在末页，下一章落在首页）
  private step(delta: number): void {
    const ddelta = this.mode === 'rtl' ? -delta : delta;
    const kind = this.cellKind(this.displayIndex);
    if (kind === 'next') {
      if (delta > 0) {
        this.gotoChapter(true, true);
      } else {
        this.backFromTransition();
      }
      return;
    }
    if (kind === 'prev') {
      if (delta < 0) {
        this.gotoChapter(false, true);
      } else {
        this.backFromTransition();
      }
      return;
    }
    const target = this.displayIndex + ddelta;
    if (target < 0 || target > this.pages.length + 1) {
      return;
    }
    this.displayIndex = target;
    this.onSwipe(target);
  }

  // 从过渡页返回本章边界页（真实进度未变，仅回到当前页）
  private backFromTransition(): void {
    const back = this.realToDisplay(this.currentReal);
    this.displayIndex = back;
    this.onSwipe(back);
  }

  private useCurl(): boolean {
    return this.pageAnim === 'curl' && this.mode !== 'webtoon' && this.mode !== 'vertical' && this.pages.length > 0;
  }

  private curlDual(): boolean {
    return this.dualPage && this.mode !== 'vertical';
  }

  private curlCount(): number {
    if (this.pages.length === 0) {
      return 0;
    }
    if (this.curlDual()) {
      return Math.ceil(this.pages.length / 2);
    }
    return this.pages.length;
  }

  private curlIndex(): number {
    if (this.pages.length === 0) {
      return 0;
    }
    if (this.curlDual()) {
      return Math.min(this.curlCount() - 1, Math.floor(this.currentReal / 2));
    }
    return this.currentReal;
  }

  // 仿真卷曲从左缘翻出下一页：从右到左，或智感握姿左手（下一页在左侧）
  private curlFromLeft(): boolean {
    if (this.mode === 'rtl') {
      return true;
    }
    if (this.mode === 'smart_grip' && !this.gripRight) {
      return true;
    }
    return false;
  }

  private curlNextOnLeft(): boolean {
    if (this.navMode === 'ltr') {
      return false;
    }
    if (this.navMode === 'rtl') {
      return true;
    }
    return this.curlFromLeft();
  }

  private curlTapMode(): string {
    if (this.navMode === 'none') {
      return 'none';
    }
    if (this.navMode === 'vertical') {
      return 'vertical';
    }
    if (this.navMode === 'edge') {
      return 'edge';
    }
    return 'horizontal';
  }

  private curlEnabled(): boolean {
    return !this.showSettings && !this.showModeSheet && !this.showOrientationSheet;
  }

  private onCurlIndex(index: number): void {
    const real = this.curlDual() ? Math.min(this.pages.length - 1, index * 2) : index;
    if (real < 0 || real >= this.pages.length || real === this.currentReal) {
      return;
    }
    this.currentReal = real;
    this.displayIndex = this.realToDisplay(real);
    this.persistProgress();
  }

  // 仿真翻页滑出边界：弹出章节过渡层（dir>0 越过末页，dir<0 越过首页）
  private onCurlOverscroll(dir: number): void {
    if (this.transOverlay !== 0) {
      return;
    }
    this.transOverlay = dir > 0 ? 1 : -1;
    // 没有下一章时呼出菜单（对齐 Mihon：落在无目标的 Next 过渡页）
    if (dir > 0 && !this.hasNext) {
      this.showMenu = true;
    }
  }

  // 过渡层点击：按导航热区判定——继续前/后翻进入相邻章节，反向返回本章，中键呼出菜单
  private onTransitionOverlayTap(x: number, y: number): void {
    const kind = this.transOverlay > 0 ? 'next' : 'prev';
    if (this.navMode === 'none') {
      this.transOverlay = 0;
      this.showMenu = !this.showMenu;
      return;
    }
    let delta = 0;
    if (this.navMode === 'vertical') {
      const zoneY = y / (this.readerH > 0 ? this.readerH : 640);
      if (zoneY < 0.3) {
        delta = -1;
      } else if (zoneY > 0.7) {
        delta = 1;
      }
    } else {
      // “下一页”是否在左侧：默认跟随阅读模式，可被导航模式覆盖
      let nextOnLeft: boolean = this.mode === 'rtl' ||
        (this.mode === 'smart_grip' && !this.gripRight);
      if (this.navMode === 'ltr') {
        nextOnLeft = false;
      } else if (this.navMode === 'rtl') {
        nextOnLeft = true;
      }
      const zone = x / (this.readerW > 0 ? this.readerW : 360);
      if (zone < 0.3) {
        delta = nextOnLeft ? 1 : -1;
      } else if (zone > 0.7) {
        delta = nextOnLeft ? -1 : 1;
      }
    }
    this.transOverlay = 0;
    if (delta === 0) {
      this.showMenu = !this.showMenu;
      return;
    }
    if (kind === 'next' && delta > 0) {
      this.gotoChapter(true, true);
    } else if (kind === 'prev' && delta < 0) {
      this.gotoChapter(false, true);
    }
  }

  private setPageAnim(v: string): void {
    if (v === this.pageAnim) {
      return;
    }
    this.pageAnim = v;
    Settings.setReaderPageAnim(v);
    this.coverX = Util.zeros(this.pages.length);
    this.coverY = Util.zeros(this.pages.length);
    this.coverZ = Util.zeros(this.pages.length);
  }

  private coverAt(arr: number[], index: number): number {
    if (this.pageAnim !== 'cover' || index < 0 || index >= arr.length) {
      return 0;
    }
    return arr[index];
  }

  private setCover(i: number, x: number, y: number, z: number): void {
    if (i < 0 || i >= this.coverX.length) {
      return;
    }
    if (this.coverX[i] !== x) {
      this.coverX[i] = x;
    }
    if (this.coverY[i] !== y) {
      this.coverY[i] = y;
    }
    if (this.coverZ[i] !== z) {
      this.coverZ[i] = z;
    }
  }

  // 覆盖：新页滑入盖住静止的当前页。滑动模式不改位移，沿用 Swiper 默认滚动。
  private onCoverTransition(proxy: SwiperContentTransitionProxy): void {
    if (this.pageAnim !== 'cover') {
      return;
    }
    const i = proxy.index;
    if (i < 0 || i >= this.coverX.length) {
      return;
    }
    const p = proxy.position;
    if (Math.abs(p - Math.round(p)) < 0.001) {
      this.setCover(i, 0, 0, 0);
      return;
    }
    const span = proxy.mainAxisLength;
    const selected = proxy.selectedIndex;
    const vertical = this.mode === 'vertical';
    const pinX = vertical ? 0 : -p * span;
    const pinY = vertical ? -p * span : 0;
    if (i === selected) {
      if (p < 0) {
        this.setCover(i, pinX, pinY, 0);
      } else {
        this.setCover(i, 0, 0, 2);
      }
    } else if (i === selected + 1) {
      this.setCover(i, 0, 0, 2);
    } else if (i === selected - 1) {
      this.setCover(i, pinX, pinY, 0);
    } else {
      this.setCover(i, 0, 0, 0);
    }
  }

  @Builder
  curlFull(index: number) {
    if (index >= 0 && index < this.pages.length) {
      SmartImage({
        url: this.pages[index].url,
        sourceKey: this.manga.sourceKey,
        fit: this.crop ? ImageFit.Cover : ImageFit.Contain,
        fill: true
      })
        .width('100%')
        .height('100%')
    }
  }

  @Builder
  curlHalf(index: number) {
    if (index >= 0 && index < this.pages.length) {
      SmartImage({
        url: this.pages[index].url,
        sourceKey: this.manga.sourceKey,
        fit: this.crop ? ImageFit.Cover : ImageFit.Contain,
        fill: true
      })
        .layoutWeight(1)
        .height('100%')
    } else {
      Column()
        .layoutWeight(1)
        .height('100%')
    }
  }

  private requestLeaf(dir: number): void {
    const next = dir > 0 ? Math.abs(this.leafTurn) + 1 : -(Math.abs(this.leafTurn) + 1);
    this.leafTurn = next === 0 ? dir : next;
  }

  // 双页热区按整屏计算。onLeaf 表示点击落在正在翻的那一半。
  private onDualTap(localX: number, localY: number, onLeaf: boolean): void {
    if (this.showSettings || this.showModeSheet || this.showOrientationSheet) {
      return;
    }
    const fullW = this.readerW > 0 ? this.readerW : 1;
    const fullH = this.readerH > 0 ? this.readerH : 1;
    const globalX = this.curlFromLeft() ? (onLeaf ? localX : fullW / 2 + localX) :
      (onLeaf ? fullW / 2 + localX : localX);
    if (this.curlTapMode() === 'none') {
      this.showMenu = !this.showMenu;
      return;
    }
    if (this.curlTapMode() === 'vertical') {
      const y = localY / fullH;
      if (y < 0.3) {
        this.requestLeaf(-1);
      } else if (y > 0.7) {
        this.requestLeaf(1);
      } else {
        this.showMenu = !this.showMenu;
      }
      return;
    }
    const edge = this.curlTapMode() === 'edge' ? 0.12 : 0.3;
    const nextOnLeft = this.curlNextOnLeft();
    let dir = 0;
    if (globalX < fullW * edge) {
      dir = nextOnLeft ? 1 : -1;
    } else if (globalX > fullW * (1 - edge)) {
      dir = nextOnLeft ? -1 : 1;
    }
    if (dir === 0) {
      this.showMenu = !this.showMenu;
    } else {
      this.requestLeaf(dir);
    }
  }

  @Builder
  curlLeafPage(index: number) {
    this.curlFull(index * 2 + 1)
  }

  @Builder
  curlLeafBack(index: number) {
    this.curlFull(index * 2 + 2)
  }

  @Builder
  ComicStaticHalf() {
    Column() {
      this.curlFull(this.curlIndex() * 2)
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
    .onClick((event: ClickEvent) => {
      this.onDualTap(event.x, event.y, false);
    })
  }

  @Builder
  ComicFlipLeaf() {
    EmulationFlipView({
      index: this.curlIndex(),
      pageCount: this.curlCount(),
      fromLeft: this.curlFromLeft(),
      nextOnLeft: this.curlNextOnLeft(),
      tapMode: this.curlTapMode(),
      flipEnabled: this.curlEnabled(),
      showBack: true,
      ownTap: false,
      turnToken: this.leafTurn,
      bgColor: Theme.readerBg(this.readerTheme, this.isDark),
      onIndexChange: (index: number): void => {
        this.onCurlIndex(index);
      },
      onCenterTap: (): void => {
        this.showMenu = !this.showMenu;
      },
      onOverscroll: (dir: number): void => {
        this.onCurlOverscroll(dir);
      },
      onAreaTap: (x: number, y: number): void => {
        this.onDualTap(x, y, true);
      },
      pageContent: (index: number): void => {
        this.curlLeafPage(index);
      },
      backContent: (index: number): void => {
        this.curlLeafBack(index);
      }
    })
      .layoutWeight(1)
      .height('100%')
  }

  @Builder
  DualLeaf() {
    Row() {
      if (this.curlFromLeft()) {
        this.ComicFlipLeaf()
        this.ComicStaticHalf()
      } else {
        this.ComicStaticHalf()
        this.ComicFlipLeaf()
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((_old: Area, newArea: Area) => {
      this.syncReaderArea(newArea);
    })
  }

  @Builder
  curlPageBody(index: number) {
    if (this.curlDual()) {
      Row() {
        if (this.curlFromLeft()) {
          this.curlHalf(index * 2 + 1)
          this.curlHalf(index * 2)
        } else {
          this.curlHalf(index * 2)
          this.curlHalf(index * 2 + 1)
        }
      }
      .width('100%')
      .height('100%')
    } else {
      this.curlFull(index)
    }
  }

  // ---- 各阅读模式内容体（经 ReaderFilterArea 的 content 注入；@BuilderParam 传参
  // 只能调用 @Builder 方法，不能内联 UI 组件语法） ----

  // 过渡视图文字色：白底深色字，灰/黑底浅色字（自动主题按系统深浅色）
  private readerTextCol(): string {
    const t = this.readerTheme === 3 ? (this.isDark ? 1 : 0) : this.readerTheme;
    return t === 0 ? '#16181D' : '#ECEEF2';
  }

  private readerSubCol(): string {
    const t = this.readerTheme === 3 ? (this.isDark ? 1 : 0) : this.readerTheme;
    return t === 0 ? '#9916181D' : '#99ECEEF2';
  }

  // 条漫模式内容体
  @Builder
  webtoonBody() {
    ComicStripViewer({
      pages: this.pages,
      sourceKey: this.manga.sourceKey,
      initialIndex: this.currentReal + STRIP_LEAD_COUNT,
      isDark: this.isDark,
      sidePadding: this.webtoonPadding,
      currentChapterName: this.chapter.name,
      prevChapterName: this.prevChapterName,
      nextChapterName: this.nextChapterName,
      textCol: this.readerTextCol(),
      subCol: this.readerSubCol(),
      scroller: this.scroller,
      onTap: (): void => {
        this.showMenu = !this.showMenu;
      },
      onPageVisible: (index: number): void => {
        const kind = this.cellKind(index);
        if (kind === 'next') {
          // 滚动到“下一章”过渡页：没有下一章时呼出菜单（对齐 Mihon）
          if (!this.hasNext) {
            this.showMenu = true;
          }
          return;
        }
        if (kind === 'prev') {
          return;
        }
        this.displayIndex = index;
        const real = this.displayToReal(index);
        if (real !== this.currentReal && index >= 0) {
          this.currentReal = real;
          this.persistProgress();
        }
      },
      onPrevChapter: (): void => {
        this.gotoChapter(false, true);
      },
      onNextChapter: (): void => {
        this.gotoChapter(true, true);
      }
    })
      .width('100%')
      .height('100%')
  }

  // 单仿真翻页内容体
  @Builder
  curlSingleBody() {
    EmulationFlipView({
      index: this.curlIndex(),
      pageCount: this.curlCount(),
      fromLeft: this.curlFromLeft(),
      nextOnLeft: this.curlNextOnLeft(),
      tapMode: this.curlTapMode(),
      flipEnabled: this.curlEnabled(),
      bgColor: Theme.readerBg(this.readerTheme, this.isDark),
      onIndexChange: (index: number): void => {
        this.onCurlIndex(index);
      },
      onCenterTap: (): void => {
        if (this.showSettings || this.showModeSheet || this.showOrientationSheet) {
          return;
        }
        this.showMenu = !this.showMenu;
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
      .onAreaChange((_old: Area, newArea: Area) => {
        this.syncReaderArea(newArea);
      })
  }

  // 普通翻页（Swiper）内容体：首尾为章节过渡页，中间为正文页
  @Builder
  swiperBody() {
    Swiper() {
      LazyForEach(this.dataSource, (page: SPage, index: number) => {
        Stack() {
          if (page.url === TRANS_PREV_URL || page.url === TRANS_NEXT_URL) {
            // 章节过渡页（对齐 Mihon：越界展示上一章/下一章信息）
            Column() {
              ReaderTransition({
                kind: page.url === TRANS_NEXT_URL ? 'next' : 'prev',
                currentName: this.chapter.name,
                targetName: page.url === TRANS_NEXT_URL ? this.nextChapterName : this.prevChapterName,
                textCol: this.readerTextCol(),
                subCol: this.readerSubCol()
              })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            SmartImage({
              url: page.url,
              sourceKey: this.manga.sourceKey,
              fit: this.crop ? ImageFit.Cover : ImageFit.Contain,
              fill: true
            })
            .width('100%')
            .height('100%')
          }
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.coverAt(this.coverX, index), y: this.coverAt(this.coverY, index) })
        .zIndex(this.coverAt(this.coverZ, index))
      }, (page: SPage) => page.url)
    }
    .width('100%')
    .height('100%')
    .displayCount(this.dualPageActive() ? 2 : 1)
    .loop(false)
    .vertical(this.mode === 'vertical')
    .index(this.displayIndex)
    .indicator(false)
    .customContentTransition({
      timeout: 800,
      transition: (proxy: SwiperContentTransitionProxy): void => {
        this.onCoverTransition(proxy);
      }
    })
    .onChange((index: number) => {
      this.onSwipe(index);
    })
    .onTouch((event: TouchEvent) => {
      this.handleTouch(event);
    })
    .onAreaChange((_old: Area, newArea: Area) => {
      this.syncReaderArea(newArea);
    })
  }

  // 仿真翻页边界的章节过渡覆盖层（Swiper 单元格方案不适用于仿真翻页，改为全屏层）
  @Builder
  curlTransitionOverlay() {
    if (this.transOverlay !== 0) {
      Column() {
        ReaderTransition({
          kind: this.transOverlay > 0 ? 'next' : 'prev',
          currentName: this.chapter.name,
          targetName: this.transOverlay > 0 ? this.nextChapterName : this.prevChapterName,
          textCol: this.readerTextCol(),
          subCol: this.readerSubCol()
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick((event: ClickEvent) => {
        this.onTransitionOverlayTap(event.x, event.y);
      })
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

  // 章节导航行：上一章 / 页码胶囊 / 下一章（guard 保留在回调内）
  @Builder
  menuNavRow() {
    ReaderNavRow({
      prevActive: this.hasPrev,
      nextActive: this.hasNext,
      pill: (): void => {
        this.menuNavPill();
      },
      onPrev: (): void => {
        if (this.hasPrev) {
          this.gotoChapter(false);
        }
      },
      onNext: (): void => {
        if (this.hasNext) {
          this.gotoChapter(true);
        }
      }
    })
  }

  // 页码胶囊：当前页 + Slider + 总页数（无页时空占位）
  @Builder
  menuNavPill() {
    if (this.pages.length > 0) {
      ReaderPagePill({
        pos: this.currentReal + 1,
        total: this.pages.length,
        onSeek: (value: number): void => {
          this.jumpToReal(value - 1);
        }
      })
    } else {
      Column().layoutWeight(1)
    }
  }

  // 设置行：阅读模式 / 旋转 / 裁边 / 设置
  @Builder
  menuSettingsRow() {
    Row() {
      ReaderMenuIconButton({
        icon: this.modeIcon(),
        onTap: (): void => {
          this.selectMode();
        }
      })
      ReaderMenuIconButton({
        icon: 'screen_rotation',
        onTap: (): void => {
          this.selectOrientation();
        }
      })
      ReaderMenuIconButton({
        icon: this.crop ? 'crop' : 'crop_off',
        onTap: (): void => {
          this.toggleCrop();
        }
      })
      ReaderMenuIconButton({
        icon: 'settings',
        onTap: (): void => {
          this.showSettings = true;
        }
      })
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        // 内容区
        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(this.pal.primary)
            Text($r('app.string.reader_loading_chapter'))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .margin({ top: 12 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.mode === 'webtoon') {
          // 条漫模式：PixelMap 直绘的无限竖向滚动（防防盗链拦截 + 内存受控）
          ReaderFilterArea({
            grayOn: this.filterGrayscale,
            invOn: this.filterInvert,
            brightOn: this.filterBrightnessOn,
            brightPct: this.filterBrightness / 100,
            contrOn: this.filterContrastOn,
            contrPct: this.filterContrast / 100,
            satOn: this.filterSaturationOn,
            satPct: this.filterSaturation / 100,
            content: (): void => {
              this.webtoonBody()
            }
          })
        } else if (this.useCurl() && this.curlDual()) {
          ReaderFilterArea({
            grayOn: this.filterGrayscale,
            invOn: this.filterInvert,
            brightOn: this.filterBrightnessOn,
            brightPct: this.filterBrightness / 100,
            contrOn: this.filterContrastOn,
            contrPct: this.filterContrast / 100,
            satOn: this.filterSaturationOn,
            satPct: this.filterSaturation / 100,
            content: (): void => {
              this.DualLeaf()
            }
          })
        } else if (this.useCurl()) {
          ReaderFilterArea({
            grayOn: this.filterGrayscale,
            invOn: this.filterInvert,
            brightOn: this.filterBrightnessOn,
            brightPct: this.filterBrightness / 100,
            contrOn: this.filterContrastOn,
            contrPct: this.filterContrast / 100,
            satOn: this.filterSaturationOn,
            satPct: this.filterSaturation / 100,
            content: (): void => {
              this.curlSingleBody()
            }
          })
        } else {
          ReaderFilterArea({
            grayOn: this.filterGrayscale,
            invOn: this.filterInvert,
            brightOn: this.filterBrightnessOn,
            brightPct: this.filterBrightness / 100,
            contrOn: this.filterContrastOn,
            contrPct: this.filterContrast / 100,
            satOn: this.filterSaturationOn,
            satPct: this.filterSaturation / 100,
            content: (): void => {
              this.swiperBody()
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

        // 仿真翻页边界过渡层
        this.curlTransitionOverlay()

        // 页码指示（菜单收起时）
        if (!this.showMenu && !this.loading && this.pages.length > 0 && this.showPageNumber) {
          ReaderIndicatorBadge({
            text: `${this.currentReal + 1}/${this.pages.length}`,
            navBarH: this.navBarH
          })
        }

        // 菜单
        if (this.showMenu) {
          ReaderMenu({
            title: this.manga.title,
            subtitle: this.chapter.name,
            statusBarH: this.statusBarH,
            onBack: (): void => {
              this.pathStack.pop();
            },
            onBackdrop: (): void => {
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
          .bindSheet($$this.showSettings, this.settingsSheet(), {
            preferType: Bp.sheetType(this.windowW),
            width: Bp.sheetWidth(this.windowW),
            height: SheetSize.FIT_CONTENT,
            title: { title: $r('app.string.reader_settings') },
            detents: [SheetSize.FIT_CONTENT],
            dragBar: true,
            showClose: false,
            blurStyle: BlurStyle.COMPONENT_ULTRA_THICK
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
      .bindSheet($$this.showModeSheet, this.modeSheetBuilder(), {
        preferType: Bp.sheetType(this.windowW),
        width: Bp.sheetWidth(this.windowW),
        height: SheetSize.FIT_CONTENT,
        title: { title: $r('app.string.reader_reading_mode') },
        detents: [SheetSize.FIT_CONTENT],
        dragBar: true,
        showClose: false,
        blurStyle: BlurStyle.COMPONENT_ULTRA_THICK
      })
    }
    .hideTitleBar(true)
    .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
    .bindSheet($$this.showOrientationSheet, this.orientationSheetBuilder(), {
      preferType: Bp.sheetType(this.windowW),
      width: Bp.sheetWidth(this.windowW),
      height: SheetSize.FIT_CONTENT,
      title: { title: $r('app.string.reader_screen_orientation') },
      detents: [SheetSize.FIT_CONTENT],
      dragBar: true,
      showClose: false,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK
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

  // 更多设置面板：背景色 / 显示页码 / 亮度
  // 当前阅读模式/屏幕方向的显示文案
  private modeLabelRes(): ResourceStr {
    if (this.mode === 'rtl') {
      return $r('app.string.reader_mode_rtl');
    }
    if (this.mode === 'vertical') {
      return $r('app.string.reader_mode_vertical');
    }
    if (this.mode === 'webtoon') {
      return $r('app.string.reader_mode_webtoon');
    }
    if (this.mode === 'smart_grip') {
      return $r('app.string.reader_mode_smart_grip');
    }
    return $r('app.string.reader_mode_ltr');
  }

  private orientationLabelRes(): ResourceStr {
    if (this.orientation === 'portrait') {
      return $r('app.string.reader_orientation_portrait');
    }
    if (this.orientation === 'landscape') {
      return $r('app.string.reader_orientation_landscape');
    }
    if (this.orientation === 'lock_portrait') {
      return $r('app.string.reader_orientation_lock_portrait');
    }
    if (this.orientation === 'lock_landscape') {
      return $r('app.string.reader_orientation_lock_landscape');
    }
    return $r('app.string.reader_orientation_free');
  }

  // 阅读器设置面板（参考 Mihon：阅读模式 / 常规 / 滤镜）
  @Builder
  settingsSheet() {
    Column({ space: 0 }) {
      // Tab 栏
      Row() {
        this.settingsTabItem(0, $r('app.string.reader_reading_mode'))
        this.settingsTabItem(1, $r('app.string.reader_tab_general'))
        this.settingsTabItem(2, $r('app.string.reader_tab_filter'))
      }
      .width('100%')
      .height(40)

      if (this.settingsTab === 0) {
        // 阅读模式
        TextRow({
          title: $r('app.string.reader_reading_mode'),
          value: this.modeLabelRes(),
          onTap: (): void => {
            this.showSettings = false;
            this.selectMode();
          }
        })
        Divider().color(this.pal.divider)
        TextRow({
          title: $r('app.string.reader_screen_orientation'),
          value: this.orientationLabelRes(),
          onTap: (): void => {
            this.showSettings = false;
            this.selectOrientation();
          }
        })
        Divider().color(this.pal.divider)
        if (this.mode !== 'webtoon') {
          Column({ space: 8 }) {
            Text($r('app.string.novel_page_animation'))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              this.animChip($r('app.string.novel_anim_curl'), 'curl')
              this.animChip($r('app.string.novel_anim_slide'), 'slide')
              this.animChip($r('app.string.novel_anim_cover'), 'cover')
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 8 })
          Divider().color(this.pal.divider)
        }
        if (this.mode === 'webtoon') {
          // 条漫：侧边距
          this.filterSliderRow($r('app.string.reader_webtoon_padding'), this.webtoonPadding, 0, 25,
            (value: number, done: boolean): void => {
              this.webtoonPadding = value;
              if (done) {
                Settings.setReaderWebtoonPadding(value);
              }
            })
        } else {
          // 点击翻页区域
          Column({ space: 8 }) {
            Text($r('app.string.reader_nav_tap_zones'))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              this.navChip($r('app.string.reader_nav_default'), 'default')
              this.navChip($r('app.string.reader_nav_ltr'), 'ltr')
              this.navChip($r('app.string.reader_nav_rtl'), 'rtl')
              this.navChip($r('app.string.reader_nav_vertical'), 'vertical')
              this.navChip($r('app.string.reader_nav_edge'), 'edge')
              this.navChip($r('app.string.reader_nav_none'), 'none')
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 8 })

          if (this.mode !== 'vertical') {
            Divider().color(this.pal.divider)
            SwitchRow({
              title: $r('app.string.reader_dual_page'),
              isOn: this.dualPage,
              onChange: (value: boolean): void => {
                this.dualPage = value;
                Settings.setReaderDualPage(value);
              }
            })
          }
          Divider().color(this.pal.divider)
          SwitchRow({
            title: $r('app.string.reader_crop_borders'),
            isOn: this.crop,
            onChange: (value: boolean): void => {
              this.setCrop(value);
            }
          })
        }
      } else if (this.settingsTab === 1) {
        // 常规：背景色 / 显示页码 / 亮度
        Column({ space: 8 }) {
          Text($r('app.string.reader_background'))
            .fontSize(13)
            .fontColor(this.pal.sub)
            .width('100%')
          Row({ space: 8 }) {
            this.themeChip($r('app.string.reader_theme_auto'), 3)
            this.themeChip($r('app.string.reader_theme_white'), 0)
            this.themeChip($r('app.string.reader_theme_gray'), 2)
            this.themeChip($r('app.string.reader_theme_black'), 1)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

        Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })

        // 显示页码
        SwitchRow({
          title: $r('app.string.reader_show_page_number'),
          isOn: this.showPageNumber,
          onChange: (value: boolean): void => {
            this.showPageNumber = value;
            Settings.setReaderShowPageNumber(value);
          }
        })

        Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })

        // 亮度
        Row() {
          Text($r('app.string.reader_brightness'))
            .fontSize(16)
            .fontColor(this.pal.text)
            .width(64)
          Slider({ value: this.brightLv, min: 0, max: 1, step: 0.05 })
            .layoutWeight(1)
            .blockColor(this.pal.primary)
            .selectedColor(this.pal.primary)
            .trackColor(this.pal.divider)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.brightLv = Math.round(value * 20) / 20;
                Settings.setReaderBrightness(this.brightLv);
                this.applyBrightness();
              }
            })
          Text(this.brightLv === 0 ? $r('app.string.reader_auto') : `${Math.round(this.brightLv * 100)}%`)
            .fontSize(12)
            .fontColor(this.pal.sub)
            .width(44)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
      } else {
        // 滤镜：灰度 / 反色 / 亮度 / 对比度 / 饱和度（参考 Mihon，每项有开关控制是否应用）
        SwitchRow({
          title: $r('app.string.reader_filter_grayscale'),
          isOn: this.filterGrayscale,
          onChange: (value: boolean): void => {
            this.filterGrayscale = value;
            Settings.setReaderGrayscale(value);
          }
        })
        Divider().color(this.pal.divider)
        SwitchRow({
          title: $r('app.string.reader_filter_invert'),
          isOn: this.filterInvert,
          onChange: (value: boolean): void => {
            this.filterInvert = value;
            Settings.setReaderInvert(value);
          }
        })
        Divider().color(this.pal.divider)
        SwitchRow({
          title: $r('app.string.reader_brightness'),
          isOn: this.filterBrightnessOn,
          onChange: (value: boolean): void => {
            this.filterBrightnessOn = value;
            Settings.setReaderBrightnessEnabled(value);
          }
        })
        if (this.filterBrightnessOn) {
          this.filterSliderRow($r('app.string.reader_brightness'), this.filterBrightness, 50, 150,
            (value: number, done: boolean): void => {
              this.filterBrightness = value;
              if (done) {
                Settings.setReaderFilterBrightness(value);
              }
            })
        }
        Divider().color(this.pal.divider)
        SwitchRow({
          title: $r('app.string.reader_filter_contrast'),
          isOn: this.filterContrastOn,
          onChange: (value: boolean): void => {
            this.filterContrastOn = value;
            Settings.setReaderContrastEnabled(value);
          }
        })
        if (this.filterContrastOn) {
          this.filterSliderRow($r('app.string.reader_filter_contrast'), this.filterContrast, 50, 150,
            (value: number, done: boolean): void => {
              this.filterContrast = value;
              if (done) {
                Settings.setReaderContrast(value);
              }
            })
        }
        Divider().color(this.pal.divider)
        SwitchRow({
          title: $r('app.string.reader_filter_saturation'),
          isOn: this.filterSaturationOn,
          onChange: (value: boolean): void => {
            this.filterSaturationOn = value;
            Settings.setReaderSaturationEnabled(value);
          }
        })
        if (this.filterSaturationOn) {
          this.filterSliderRow($r('app.string.reader_filter_saturation'), this.filterSaturation, 50, 150,
            (value: number, done: boolean): void => {
              this.filterSaturation = value;
              if (done) {
                Settings.setReaderSaturation(value);
              }
            })
        }
      }

      Column().height(16)
    }
    .width('100%')
  }

  // 设置面板 Tab 项（选中高亮 + 底部指示条）
  @Builder
  settingsTabItem(index: number, label: ResourceStr) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontWeight(this.settingsTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.settingsTab === index ? this.pal.primary : this.pal.sub)
        .maxLines(1)
      Divider()
        .width(24)
        .height(2)
        .borderRadius(1)
        .margin({ top: 5 })
        .color(this.settingsTab === index ? this.pal.primary : Color.Transparent)
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height('100%')
    .onClick(() => {
      this.settingsTab = index;
    })
  }

  // 滤镜滑杆行：label + Slider + 百分比（拖动实时预览，松手持久化）
  @Builder
  filterSliderRow(label: ResourceStr, value: number, min: number, max: number,
    onChange: (value: number, done: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor(this.pal.text)
        .width(64)
      Slider({ value: value, min: min, max: max, step: 1 })
        .layoutWeight(1)
        .blockColor(this.pal.primary)
        .selectedColor(this.pal.primary)
        .trackColor(this.pal.divider)
        .margin({ left: 8, right: 8 })
        .onChange((sliderValue: number, mode: SliderChangeMode) => {
          onChange(Math.round(sliderValue),
            mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
        })
      Text(`${Math.round(value)}%`)
        .fontSize(12)
        .fontColor(this.pal.sub)
        .width(44)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  animChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.pageAnim === value ? this.pal.onPrimary : this.pal.text)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.pageAnim === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.setPageAnim(value);
      })
  }

  // 点击翻页区域导航 chip
  @Builder
  navChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.navMode === value ? this.pal.onPrimary : this.pal.text)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.navMode === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.navMode = value;
        Settings.setReaderNavMode(value);
      })
  }

  @Builder
  themeChip(label: ResourceStr, value: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.readerTheme === value ? this.pal.onPrimary : this.pal.text)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.readerTheme === value ? this.pal.primary : this.pal.chip)
      .onClick(() => {
        this.readerTheme = value;
        Settings.setReaderTheme(value);
      })
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function ReaderBuilder() {
  ReaderPage()
}
