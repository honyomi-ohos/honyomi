import { common } from '@kit.AbilityKit';
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
import { SmartImage } from './components/SmartImage';
import { ComicStripViewer } from './components/ComicStripViewer';
import { AppIconRes, AppIcon } from './components/AppIcon';
import { SwitchRow, TextRow } from './components/Prefs';
import { PickerSheet } from './components/PickerSheet';
import { EmulationFlipView } from './components/PageFlip';

// 屏幕旋转的可选值（与下方 sheet 选项一一对应）
const READER_ORIENTATIONS: string[] = ['free', 'portrait', 'landscape', 'lock_portrait', 'lock_landscape'];
const READER_ORIENTATION_ICONS: string[] =
  ['screen_rotation', 'stay_current_portrait', 'stay_current_landscape', 'screen_lock_portrait', 'screen_lock_landscape'];

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
          throw new Error('源不可用');
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
      this.currentReal = chapter.lastPageRead > 0 && chapter.lastPageRead < pages.length
        ? chapter.lastPageRead : 0;
      this.applyMode(true);
      await HistoryRepo.upsert(chapter.mangaId, chapter.id, this.currentReal);
      if (gen !== this.loadGen) {
        return;
      }
      // 开始本章的阅读时长计时
      ReadingStatsRepo.begin(chapter.mangaId, chapter.id);
      await this.refreshNeighbors();
    } catch (e) {
      // 加载失败清空旧章页面，防止旧页码经 persistProgress 写入本章进度
      if (gen === this.loadGen) {
        this.pages = [];
        Util.toastRes(this.getUIContext(), $r('app.string.reader_load_failed'),
          [e instanceof Error ? e.message : String(e)]);
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
  }

  private static zeros(n: number): number[] {
    const arr: number[] = [];
    for (let i = 0; i < n; i++) {
      arr.push(0);
    }
    return arr;
  }

  // 根据模式构建展示页序并恢复进度
  private applyMode(scrollToResume: boolean): void {
    this.coverX = ReaderPage.zeros(this.pages.length);
    this.coverY = ReaderPage.zeros(this.pages.length);
    this.coverZ = ReaderPage.zeros(this.pages.length);
    if (this.mode === 'rtl') {
      this.dataSource.setPages(this.pages.slice().reverse());
      this.displayIndex = this.pages.length - 1 - this.currentReal;
    } else {
      this.dataSource.setPages(this.pages);
      this.displayIndex = this.currentReal;
    }
    if (this.mode === 'webtoon' && scrollToResume) {
      const target = this.currentReal;
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

  private displayToReal(displayIdx: number): number {
    if (this.mode === 'rtl') {
      return this.pages.length - 1 - displayIdx;
    }
    return displayIdx;
  }

  private realToDisplay(realIdx: number): number {
    if (this.mode === 'rtl') {
      return this.pages.length - 1 - realIdx;
    }
    return realIdx;
  }

  private async onSwipe(displayIdx: number): Promise<void> {
    this.displayIndex = displayIdx;
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
      }
    } catch (e) {
      hilog.warn(0x0001, 'Reader', 'persistProgress failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private setMode(mode: string): void {
    this.mode = mode;
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
    PickerSheet({
      options: [$r('app.string.reader_orientation_free'), $r('app.string.reader_orientation_portrait'),
        $r('app.string.reader_orientation_landscape'), $r('app.string.reader_orientation_lock_portrait'),
        $r('app.string.reader_orientation_lock_landscape')],
      icons: READER_ORIENTATION_ICONS,
      selectedIndex: READER_ORIENTATIONS.indexOf(this.orientation),
      onPick: (index: number): void => {
        this.showOrientationSheet = false;
        const v: string | undefined = READER_ORIENTATIONS[index];
        if (v !== undefined) {
          this.orientation = v;
          Settings.setReaderOrientation(v);
          this.applyOrientation();
        }
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

  private async gotoChapter(next: boolean): Promise<void> {
    const targetId: number = await ReaderChapterNav.neighborChapterId(this.mangaId, this.chapterId, next);
    if (targetId === 0) {
      Util.toastRes(this.getUIContext(), next ? $r('app.string.reader_last_chapter') : $r('app.string.reader_first_chapter'));
      return;
    }
    if (next && !this.chapter.read) {
      await ChapterRepo.setRead(this.chapterId, true);
    }
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

  private step(delta: number): void {
    const target = this.displayIndex + delta;
    if (target < 0) {
      Util.toastRes(this.getUIContext(), $r('app.string.reader_first_page'));
      return;
    }
    if (target >= this.pages.length) {
      Util.toastRes(this.getUIContext(), $r('app.string.reader_last_page'));
      return;
    }
    this.displayIndex = target;
    this.onSwipe(target);
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

  private onCurlOverscroll(dir: number): void {
    Util.toastRes(this.getUIContext(),
      dir < 0 ? $r('app.string.reader_first_page') : $r('app.string.reader_last_page'));
  }

  private setPageAnim(v: string): void {
    if (v === this.pageAnim) {
      return;
    }
    this.pageAnim = v;
    Settings.setReaderPageAnim(v);
    this.coverX = ReaderPage.zeros(this.pages.length);
    this.coverY = ReaderPage.zeros(this.pages.length);
    this.coverZ = ReaderPage.zeros(this.pages.length);
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
    .grayscale(this.filterGrayscale ? 1 : 0)
    .invert(this.filterInvert ? 1 : 0)
    .brightness(this.filterBrightnessOn ? this.filterBrightness / 100 : 1)
    .contrast(this.filterContrastOn ? this.filterContrast / 100 : 1)
    .saturate(this.filterSaturationOn ? this.filterSaturation / 100 : 1)
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
          ComicStripViewer({
            pages: this.pages,
            sourceKey: this.manga.sourceKey,
            initialIndex: this.currentReal,
            isDark: this.isDark,
            sidePadding: this.webtoonPadding,
            scroller: this.scroller,
            onTap: (): void => {
              this.showMenu = !this.showMenu;
            },
            onPageVisible: (index: number): void => {
              this.displayIndex = index;
              const real = this.displayToReal(index);
              if (real !== this.currentReal && index >= 0) {
                this.currentReal = real;
                this.persistProgress();
              }
            }
          })
            .width('100%')
            .height('100%')
            .grayscale(this.filterGrayscale ? 1 : 0)
            .invert(this.filterInvert ? 1 : 0)
            .brightness(this.filterBrightnessOn ? this.filterBrightness / 100 : 1)
            .contrast(this.filterContrastOn ? this.filterContrast / 100 : 1)
            .saturate(this.filterSaturationOn ? this.filterSaturation / 100 : 1)
        } else if (this.useCurl() && this.curlDual()) {
          this.DualLeaf()
        } else if (this.useCurl()) {
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
            .grayscale(this.filterGrayscale ? 1 : 0)
            .invert(this.filterInvert ? 1 : 0)
            .brightness(this.filterBrightnessOn ? this.filterBrightness / 100 : 1)
            .contrast(this.filterContrastOn ? this.filterContrast / 100 : 1)
            .saturate(this.filterSaturationOn ? this.filterSaturation / 100 : 1)
            .onAreaChange((_old: Area, newArea: Area) => {
              this.syncReaderArea(newArea);
            })
        } else {
          Swiper() {
            LazyForEach(this.dataSource, (page: SPage, index: number) => {
              Stack() {
                SmartImage({
                  url: page.url,
                  sourceKey: this.manga.sourceKey,
                  fit: this.crop ? ImageFit.Cover : ImageFit.Contain,
                  fill: true
                })
                  .width('100%')
                  .height('100%')
              }
              .width('100%')
              .height('100%')
              .translate({ x: this.coverAt(this.coverX, index), y: this.coverAt(this.coverY, index) })
              .zIndex(this.coverAt(this.coverZ, index))
            }, (page: SPage) => page.url)
          }
          .width('100%')
          .height('100%')
          .grayscale(this.filterGrayscale ? 1 : 0)
          .invert(this.filterInvert ? 1 : 0)
          .brightness(this.filterBrightnessOn ? this.filterBrightness / 100 : 1)
          .contrast(this.filterContrastOn ? this.filterContrast / 100 : 1)
          .saturate(this.filterSaturationOn ? this.filterSaturation / 100 : 1)
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

        // 页码指示（菜单收起时）
        if (!this.showMenu && !this.loading && this.pages.length > 0 && this.showPageNumber) {
          Text(`${this.currentReal + 1}/${this.pages.length}`)
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor('#66000000')
            .margin({ left: 16, top: 16, right: 16, bottom: this.navBarH + 16 })
        }

        // 菜单
        if (this.showMenu) {
          Column() {
            // 顶栏
            Row() {
              AppIcon({ name: 'arrow_back', iconSize: 24, tint: '#FFFFFF' })
                .padding({ left: 12, right: 12 })
                .onClick(() => {
                  this.pathStack.pop();
                })
              Column() {
                Text(this.manga.title)
                  .fontSize(14)
                  .fontColor('#FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.chapter.name)
                  .fontSize(11)
                  .fontColor('#CCCCCC')
                  .maxLines(1)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 4, right: 16, top: this.statusBarH + 10, bottom: 10 })
            .backgroundColor('#CC000000')
            // 对齐 Mihon ReaderAppBars：顶栏从屏幕上方滑入/滑出 + 渐隐（滑移 200ms、渐隐 150ms）
            .transition(
              TransitionEffect.translate({ y: -120 })
                .animation({ duration: 200, curve: Curve.Linear })
                .combine(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.Linear }))
            )

            // 占位（空 Column 宽度默认自适应内容为 0，必须显式撑满才能接收点击关闭菜单）
            Column()
              .layoutWeight(1)
              .width('100%')
              .onClick(() => {
                this.showMenu = false;
              })

            // 底栏：章节导航行 + 设置行（对齐 Mihon ReaderAppBars）
            Column({ space: 8 }) {
              // 章节导航行
              Row({ space: 12 }) {
                // 上一章
                Column() {
                  Image(AppIconRes.get('skip_previous'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(44)
                .height(44)
                .borderRadius(22)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#33FFFFFF')
                .opacity(this.hasPrev ? 1 : 0.4)
                .onClick(() => {
                  if (this.hasPrev) {
                    this.gotoChapter(false);
                  }
                })

                // 页码胶囊：当前页 + Slider + 总页数
                if (this.pages.length > 0) {
                  Row() {
                    Text(`${this.currentReal + 1}`)
                      .fontSize(13)
                      .fontColor('#FFFFFF')
                      .width(24)
                      .textAlign(TextAlign.End)
                    Slider({
                      value: this.currentReal + 1,
                      min: 1,
                      max: this.pages.length > 1 ? this.pages.length : 2,
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
                          this.jumpToReal(Math.round(value) - 1);
                        }
                      })
                    Text(`${this.pages.length}`)
                      .fontSize(13)
                      .fontColor('#FFFFFF')
                      .width(24)
                  }
                  .layoutWeight(1)
                  .height(44)
                  .borderRadius(22)
                  .backgroundColor('#33FFFFFF')
                  .padding({ left: 14, right: 14 })
                } else {
                  Column().layoutWeight(1)
                }

                // 下一章
                Column() {
                  Image(AppIconRes.get('skip_next'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(44)
                .height(44)
                .borderRadius(22)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#33FFFFFF')
                .opacity(this.hasNext ? 1 : 0.4)
                .onClick(() => {
                  if (this.hasNext) {
                    this.gotoChapter(true);
                  }
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16 })

              // 设置行：阅读模式 / 旋转 / 裁边 / 设置
              Row() {
                Column() {
                  Image(AppIconRes.get(this.modeIcon()))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.selectMode();
                })

                Column() {
                  Image(AppIconRes.get('screen_rotation'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.selectOrientation();
                })

                Column() {
                  Image(AppIconRes.get(this.crop ? 'crop' : 'crop_off'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.toggleCrop();
                })

                Column() {
                  Image(AppIconRes.get('settings'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.showSettings = true;
                })
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.SpaceEvenly)
              .backgroundColor('#CC000000')
            }
            .width('100%')
            .padding({ top: 8, bottom: this.navBarH + 8 })
            .backgroundColor('#CC000000')
            // 对齐 Mihon ReaderAppBars：底栏从屏幕下方滑入/滑出 + 渐隐
            .transition(
              TransitionEffect.translate({ y: 240 })
                .animation({ duration: 200, curve: Curve.Linear })
                .combine(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.Linear }))
            )
          }
          .width('100%')
          .height('100%')
          // 整棵子树删除时根组件需有消失转场时间，保证子组件的退出动画完整播放
          .transition(
            TransitionEffect.asymmetric(
              TransitionEffect.IDENTITY,
              TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Linear })
            )
          )
        }

        // 设置面板 bindSheet 常驻宿主：挂 if(showMenu) 条件节点时菜单收起即销毁宿主，弹层不可靠；
        // 同一节点链式绑定多个 bindSheet 只有最后一个生效，故用独立常驻节点承载
        Column()
          .width(0)
          .height(0)
          .hitTestBehavior(HitTestMode.None)
          .bindSheet($$this.showSettings, this.settingsSheet(), {
            preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
            width: Bp.isWide(this.windowW) ? 560 : '100%',
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
        preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
        width: Bp.isWide(this.windowW) ? 560 : '100%',
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
      preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
      width: Bp.isWide(this.windowW) ? 560 : '100%',
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
      .fontColor(this.pageAnim === value ? '#FFFFFF' : this.pal.text)
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
      .fontColor(this.navMode === value ? '#FFFFFF' : this.pal.text)
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
      .fontColor(this.readerTheme === value ? '#FFFFFF' : this.pal.text)
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
