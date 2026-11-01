import { motion } from '@kit.MultimodalAwarenessKit';
import { KeyCode } from '@kit.InputKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDb } from '../data/AppDb';
import { ChapterRepo, HistoryRepo, MangaRepo } from '../data/Repos';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { SourceRegistry } from '../source/Source';
import { ChapterRecord, ContentType, MangaRecord, SPage } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';
import { ContinueSession } from '../common/ContinueSession';
import { Theme, ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { GripSupport } from '../common/GripSupport';
import { ReaderWindow } from '../common/ReaderWindow';
import { Haptics } from '../common/Haptics';
import { ChapterFlags } from '../common/ChapterFlags';
import { ReaderChapterNav } from '../common/ReaderChapterNav';
import { DownloadService } from '../data/DownloadService';
import { DownloadRules } from '../data/DownloadRules';
import { PageSanitizer } from '../common/PageSanitizer';
import { ChapterPageStore } from '../common/ChapterPageStore';
import { TrackService } from '../data/track/TrackService';
import { SmartImage } from './components/SmartImage';
import { AppIconRes } from './components/AppIcon';
import { ComicStripViewer, STRIP_LEAD_COUNT } from './components/ComicStripViewer';
import { SwitchRow, TextRow } from './components/Prefs';
import { WideSlider } from './components/WideSlider';
import { PickerSheet } from './components/PickerSheet';
import { SheetPreset } from './components/SheetPreset';
import { ReaderChapterSheet } from './components/ReaderChapterSheet';
import { EmulationFlipView } from './components/PageFlip';
import { ReaderChapterTransitionView } from './components/ReaderChapterTransitionView';
import { ReaderFlashOverlay } from './components/ReaderFlashOverlay';
import {
  ReaderFilterArea,
  ReaderFooterText,
  ReaderHdsHost,
  ReaderHeaderText,
  ReaderIndicatorBadge,
  ReaderMenu,
  ReaderMenuIconButton,
  ReaderNavRow,
  ReaderOrientationSheet,
  ReaderPagePill
} from './components/ReaderChrome';
import { LoadingBackButton } from './components/LoadingBackButton';
import { MangaTransOverlay } from './components/MangaTransOverlay';
import { EMPTY_TRANS, MangaOcrTranslator, PageTransData } from '../translate/MangaOcr';
import { CoverViewer } from './components/CoverViewer';
import { SaveConfirmDialog } from './components/Dialogs';
import { ImageActions } from '../common/ImageActions';
import { ImageCache } from '../common/ImageCache';

// 章节过渡标记页（PageDataSource 混入的伪页，url 为保留前缀，index 为负）：
// 翻到章节边界时展示上一章/下一章过渡视图（对齐 Mihon ChapterTransition）
const TRANS_PREV_URL: string = '@@transition/prev';
const TRANS_NEXT_URL: string = '@@transition/next';
// 双页“封面独立成页”时垫在上一章过渡页后的空白占位页（index 为负）
const DUAL_BLANK_URL: string = '@@dual/blank';

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

// 阅读器：翻页(LTR) / 右到左(RTL) / 垂直 / 条漫(Webtoon) / 连续滚动(Continuous) / 智感握姿
// 底栏对齐 Mihon：章节导航行（圆形上/下一章按钮 + 页码胶囊 Slider）+ 设置行（模式/旋转/裁边/设置）
@Component
export struct ReaderPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') @Watch('onDarkChanged') isDark: boolean = false;
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
  @State showChapterSheet: boolean = false;
  @State tocChapters: ChapterRecord[] = [];
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
  // 横屏（内容区宽>高）自动双页：横向分页模式下一屏两页，竖屏恢复单页
  @State isLandscape: boolean = false;
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
  private dataSource: PageDataSource = new PageDataSource();
  private scroller: Scroller = new Scroller();
  // Swiper 控制器：翻页必须走控制器（showNext/changeIndex 等自带切换动画并触发过渡回调）；
  // 直接改 .index() 绑定变量是无动画瞬跳（见 NovelReaderPage 同样结论）
  private swiperCtrl: SwiperController = new SwiperController();
  // 控制器动画进行中的目标索引（-1 = 空闲）：动画期间 displayIndex 尚未更新，
  // 连续快翻需基于 pending 目标累计，否则会被旧值吞掉
  private flipTarget: number = -1;
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
  // 图片缩放（图库式手势）：双指捏合/双击放大，松手捏合或双击回位；翻页/切章自动复位
  @State zoomScale: number = 1;
  @State zoomX: number = 0;
  @State zoomY: number = 0;
  private pinchBase: number = 1;
  private panBaseX: number = 0;
  private panBaseY: number = 0;
  // 单击调度（延迟 260ms 识别双击缩放）：待执行动作与定时器 id
  private pendingTap: (() => void) | null = null;
  private pendingTapTimer: number = -1;
  // 自动翻页（华为阅读）：间隔可调，定时步进下一页；条漫模式不适用
  @State autoPageSec: number = 0;
  @State autoRunning: boolean = false;
  private autoTimerId: number = -1;
  // 音量键翻页（默认关；开=音量上/下代替翻页）
  @State volumeTurn: boolean = false;
  // 阅读时屏幕常亮（默认开）
  @State keepScreenOn: boolean = true;
  // 预加载后续页数（Swiper cachedCount）
  @State preloadPages: number = 4;
  // 双页模式：'auto'（横屏自动，默认）| 'force'（始终双页）| 'off'（始终单页）
  @State dualPageMode: string = 'auto';
  // 双页时封面独立成页（默认开）
  @State dualCover: boolean = true;
  // 条漫/连续模式页间距（vp）
  @State webtoonGap: number = 0;
  // 显示页眉页脚（章节名/页码常驻边角）
  @State showHeaderFooter: boolean = false;
  // 整章图片翻译（漫画 OCR）：会话开关 / 进行中 / 每页译文叠加数据（与 pages 对齐，null=未翻译）
  @State transOn: boolean = false;
  @State translating: boolean = false;
  @State pageTrans: (PageTransData | null)[] = [];
  // 译文完成计数（驱动条漫 LazyForEach 条目刷新）
  @State transStamp: number = 0;
  // ---- Mihon 对齐：章末跳过 / 章节过渡页 / 墨水屏闪屏 / 裁边 / 混合 / 缩放起点 ----
  // 章末跳过：已读章节 / 详情页筛选隐藏的章节 / 同章节号重复章节
  @State skipRead: boolean = false;
  @State skipFiltered: boolean = false;
  @State skipDuplicate: boolean = false;
  // 章节过渡页开关（关闭时仅缺章仍强制显示，对齐 Mihon alwaysShowChapterTransition）
  @State showChapterTransition: boolean = true;
  // 墨水屏闪屏（对齐 Mihon flashPagePrefetch）：开关/颜色/时长/间隔/翻页计数
  @State flashEnabled: boolean = false;
  @State flashColor: string = 'white';
  @State flashDurationMs: number = 100;
  @State flashEveryPages: number = 1;
  @State flashTick: number = 0;
  // 条漫裁边 / 条漫禁止缩小（近似：本实现缩放下限恒为 1）
  @State cropWebtoon: boolean = false;
  @State webtoonDisableZoomOut: boolean = false;
  // 滤镜混合模式（不可命名为 blendMode：与通用属性方法冲突）
  @State filterBlend: string = 'none';
  // 双击缩放起始位置：automatic | left | right | center
  @State zoomStart: string = 'automatic';
  // 当前章/相邻章节详情（过渡页展示）：下载状态/汉化组/缺章数
  @State currentChapterDownloaded: boolean = false;
  @State prevChapterScanlator: string = '';
  @State prevChapterDownloaded: boolean = false;
  @State prevGap: number = 0;
  @State nextChapterScanlator: string = '';
  @State nextChapterDownloaded: boolean = false;
  @State nextGap: number = 0;
  // 新翻页动画（stack/fade）逐单元格旋转/缩放/透明度
  @State animRot: number[] = [];
  @State animScl: number[] = [];
  @State animOpa: number[] = [];
  // 应用跳过筛选后的导航章节表（prev/next 取自该表；手动目录选择不受影响）
  private navChapters: ChapterRecord[] = [];
  // 查看原图（右键菜单）：当前页全屏查看器
  @State showPageViewer: boolean = false;
  @State viewPageUrl: string = '';
  private transGen: number = 0;
  private destroyed: boolean = false;

  aboutToAppear(): void {
    this.gripSupported = GripSupport.isSupported();
    this.crop = Settings.getReaderCropBordersPaged();
    this.readerTheme = Settings.getReaderTheme();
    this.syncReaderBgDark();
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
    this.webtoonPadding = Settings.getReaderWebtoonPadding();
    this.autoPageSec = Settings.getReaderAutoPageSec();
    this.volumeTurn = Settings.getReaderVolumeTurn();
    this.keepScreenOn = Settings.getReaderKeepScreenOn();
    this.preloadPages = Settings.getReaderPreloadPages();
    this.dualPageMode = Settings.getReaderDualPageMode();
    this.dualCover = Settings.getReaderDualPageCover();
    this.webtoonGap = Settings.getReaderWebtoonGap();
    this.showHeaderFooter = Settings.getReaderShowHeaderFooter();
    this.skipRead = Settings.getReaderSkipRead();
    this.skipFiltered = Settings.getReaderSkipFiltered();
    this.skipDuplicate = Settings.getReaderSkipDuplicate();
    this.showChapterTransition = Settings.getReaderShowChapterTransition();
    this.flashEnabled = Settings.getReaderFlashEnabled();
    this.flashColor = Settings.getReaderFlashColor();
    this.flashDurationMs = Settings.getReaderFlashDurationMs();
    this.flashEveryPages = Settings.getReaderFlashEveryPages();
    this.cropWebtoon = Settings.getReaderCropBordersWebtoon();
    this.webtoonDisableZoomOut = Settings.getReaderWebtoonDisableZoomOut();
    this.filterBlend = Settings.getReaderColorFilterBlend();
    this.zoomStart = Settings.getReaderZoomStart();
    this.transOn = Settings.getTransEnabled();
    this.applyOrientation();
    this.applyBrightness();
    // 阅读时保持屏幕常亮（退出时由 ReaderWindow.restore 还原熄屏策略）
    ReaderWindow.setKeepScreenOn(Util.hostAbilityContext(this.getUIContext()), this.keepScreenOn);
  }

  aboutToDisappear(): void {
    this.destroyed = true;
    this.transGen += 1;
    this.libDirty += 1;
    ReadingStatsRepo.flush();
    this.updateGripListener(false);
    this.cancelPendingTap();
    this.stopAutoPage();
    if (this.resumeTimerId !== -1) {
      clearTimeout(this.resumeTimerId);
      this.resumeTimerId = -1;
    }
    // 还原窗口方向与亮度
    ReaderWindow.restore(Util.hostAbilityContext(this.getUIContext()));
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

  @Builder
  curlFull(index: number) {
    if (index >= 0 && index < this.pages.length) {
      Stack() {
        SmartImage({
          url: this.pages[index].url,
          sourceKey: this.manga.sourceKey,
          fit: this.crop ? ImageFit.Cover : ImageFit.Contain,
          fill: true,
          highQuality: Settings.getReaderHighQuality(),
          retryable: true
        })
          .width('100%')
          .height('100%')
        if (this.transOn) {
          MangaTransOverlay({
            data: this.pageTrans[index] ?? EMPTY_TRANS,
            fit: this.crop ? ImageFit.Cover : ImageFit.Contain
          })
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  curlHalf(index: number) {
    if (index >= 0 && index < this.pages.length) {
      Stack() {
        SmartImage({
          url: this.pages[index].url,
          sourceKey: this.manga.sourceKey,
          fit: this.crop ? ImageFit.Cover : ImageFit.Contain,
          fill: true,
          highQuality: Settings.getReaderHighQuality(),
          retryable: true
        })
          .width('100%')
          .height('100%')
        if (this.transOn) {
          MangaTransOverlay({
            data: this.pageTrans[index] ?? EMPTY_TRANS,
            fit: this.crop ? ImageFit.Cover : ImageFit.Contain
          })
        }
      }
      .layoutWeight(1)
      .height('100%')
    } else {
      Column()
        .layoutWeight(1)
        .height('100%')
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

  // 根据模式构建展示页序（含章节边界过渡页）并恢复进度：

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

  // 条漫/连续模式内容体
  @Builder
  webtoonBody() {
    ComicStripViewer({
      pages: this.pages,
      sourceKey: this.manga.sourceKey,
      initialIndex: this.currentReal + this.stripLead(),
      isDark: this.isDark,
      sidePadding: this.webtoonPadding,
      gap: this.webtoonGap,
      // 连续模式：按屏高裁切逐页竖向滚动；条漫模式：原图直绘不限制高度
      fit: this.mode === 'continuous' ? ImageFit.Cover : ImageFit.Contain,
      maxItemHeight: this.mode === 'continuous' ? Math.floor(this.readerH) : 0,
      transOn: this.transOn,
      transStamp: this.transStamp,
      overlayFor: (index: number): PageTransData => {
        if (index < 0 || index >= this.pageTrans.length) {
          return EMPTY_TRANS;
        }
        return this.pageTrans[index] ?? EMPTY_TRANS;
      },
      currentChapterName: this.chapter.name,
      prevChapterName: this.prevChapterName,
      nextChapterName: this.nextChapterName,
      // 过渡页按开关/缺章显隐，信息含汉化组/下载/缺章数（对齐 Mihon ChapterTransition）
      showPrevTransition: this.showPrevTrans(),
      showNextTransition: this.showNextTrans(),
      currentChapterScanlator: this.chapter.scanlator,
      currentChapterDownloaded: this.currentChapterDownloaded,
      prevChapterScanlator: this.prevChapterScanlator,
      prevChapterDownloaded: this.prevChapterDownloaded,
      prevGap: this.prevGap,
      nextChapterScanlator: this.nextChapterScanlator,
      nextChapterDownloaded: this.nextChapterDownloaded,
      nextGap: this.nextGap,
      disableZoomOut: this.webtoonDisableZoomOut,
      cropBorders: this.cropWebtoon,
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
      },
      // 尾部过渡页隐藏时触底无缝进入下一章（对齐 Mihon WebtoonAdapter 无过渡直进）
      onEndReached: (): void => {
        if (!this.showNextTrans() && this.hasNext) {
          this.gotoChapter(true, true);
        }
      }
    })
      .width('100%')
      .height('100%')
      .onAreaChange((_old: Area, newArea: Area) => {
        this.syncReaderArea(newArea);
      })
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
      turnToken: this.leafTurn,
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
    Stack() {
      Swiper(this.swiperCtrl) {
        LazyForEach(this.dataSource, (page: SPage, index: number) => {
          Stack() {
            if (page.url === TRANS_PREV_URL || page.url === TRANS_NEXT_URL) {
              // 章节过渡页（对齐 Mihon：越界展示上一章/下一章信息 + 缺章警告）
              Column() {
                ReaderChapterTransitionView({
                  kind: page.url === TRANS_NEXT_URL ? 'next' : 'prev',
                  currentName: this.chapter.name,
                  currentScanlator: this.chapter.scanlator,
                  currentDownloaded: this.currentChapterDownloaded,
                  targetName: page.url === TRANS_NEXT_URL ? this.nextChapterName : this.prevChapterName,
                  targetScanlator: page.url === TRANS_NEXT_URL ? this.nextChapterScanlator : this.prevChapterScanlator,
                  targetDownloaded: page.url === TRANS_NEXT_URL ? this.nextChapterDownloaded : this.prevChapterDownloaded,
                  gapCount: page.url === TRANS_NEXT_URL ? this.nextGap : this.prevGap,
                  textCol: this.readerTextCol(),
                  subCol: this.readerSubCol()
                })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else if (page.url === DUAL_BLANK_URL) {
              // 双页“封面独立成页”占位：空白格（透出阅读器背景）；
              // 过渡页隐藏时双页边界组也用空白占位保持成组配对不变
              Column()
                .width('100%')
                .height('100%')
            } else {
              SmartImage({
                url: page.url,
                sourceKey: this.manga.sourceKey,
                fit: this.crop ? ImageFit.Cover : ImageFit.Contain,
                fill: true,
                highQuality: Settings.getReaderHighQuality(),
                retryable: true
              })
                .width('100%')
                .height('100%')
              if (this.transOn) {
                MangaTransOverlay({
                  data: this.pageTrans[page.index] ?? EMPTY_TRANS,
                  fit: this.crop ? ImageFit.Cover : ImageFit.Contain
                })
              }
            }
          }
          .width('100%')
          .height('100%')
          .translate({ x: this.coverAt(this.coverX, index), y: this.coverAt(this.coverY, index) })
          .zIndex(this.coverAt(this.coverZ, index))
          .rotate(this.rotAt(index))
          .scale(this.sclAt(index))
          .opacity(this.opaAt(index))
        }, (page: SPage) => page.url)
      }
      .width('100%')
      .height('100%')
      // 双页按组翻页（swipeByGroup）：一次滑动/步进整组（两页）
      .displayCount(this.dualPageActive() ? 2 : 1, this.dualPageActive())
      .cachedCount(this.preloadPages)
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
      .scale({ x: this.zoomScale, y: this.zoomScale })
      .translate({ x: this.zoomX, y: this.zoomY })
      .gesture(PinchGesture({ fingers: 2 })
        .onActionStart((event: GestureEvent) => {
          this.pinchBase = this.zoomScale;
        })
        .onActionUpdate((event: GestureEvent) => {
          // 以捏合起点缩放为基准，实时跟随捏合比例
          this.applyZoom(this.pinchBase * event.scale, this.zoomX, this.zoomY);
        })
        .onActionEnd(() => {
          if (this.zoomScale <= 1.02) {
            this.resetZoom();
          }
        }))

      if (this.zoomScale > 1.001) {
        this.zoomPanOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  // 缩放后的平移/捏合/双击回位覆盖层：盖在 Swiper 上方接管手势，避免单指拖动触发翻页
  @Builder
  zoomPanOverlay() {
    Column()
      .width('100%')
      .height('100%')
      .gesture(PanGesture({ direction: PanDirection.All, distance: 5 })
        .onActionStart((event: GestureEvent) => {
          this.panBaseX = this.zoomX;
          this.panBaseY = this.zoomY;
        })
        .onActionUpdate((event: GestureEvent) => {
          this.applyZoom(this.zoomScale, this.panBaseX + event.offsetX, this.panBaseY + event.offsetY);
        }))
      .gesture(PinchGesture({ fingers: 2 })
        .onActionStart((event: GestureEvent) => {
          this.pinchBase = this.zoomScale;
        })
        .onActionUpdate((event: GestureEvent) => {
          this.applyZoom(this.pinchBase * event.scale, this.zoomX, this.zoomY);
        })
        .onActionEnd(() => {
          if (this.zoomScale <= 1.02) {
            this.resetZoom();
          }
        }))
      .gesture(TapGesture({ count: 2 })
        .onAction((event: GestureEvent) => {
          this.resetZoom();
        }))
  }

  // 仿真翻页边界的章节过渡覆盖层（Swiper 单元格方案不适用于仿真翻页，改为全屏层）
  @Builder
  curlTransitionOverlay() {
    if (this.transOverlay !== 0) {
      Column() {
        ReaderChapterTransitionView({
          kind: this.transOverlay > 0 ? 'next' : 'prev',
          currentName: this.chapter.name,
          currentScanlator: this.chapter.scanlator,
          currentDownloaded: this.currentChapterDownloaded,
          targetName: this.transOverlay > 0 ? this.nextChapterName : this.prevChapterName,
          targetScanlator: this.transOverlay > 0 ? this.nextChapterScanlator : this.prevChapterScanlator,
          targetDownloaded: this.transOverlay > 0 ? this.nextChapterDownloaded : this.prevChapterDownloaded,
          gapCount: this.transOverlay > 0 ? this.nextGap : this.prevGap,
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

  // 设置行：章节目录 / 自动翻页 / 阅读模式 / 旋转 / 裁边 / 设置
  @Builder
  menuSettingsRow() {
    Row() {
      ReaderMenuIconButton({
        icon: 'view_list',
        onTap: (): void => {
          this.openChapterSheet();
        }
      })
      ReaderMenuIconButton({
        icon: 'schedule',
        onTap: (): void => {
          this.toggleAutoPage();
        }
      })
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
        icon: (this.stripMode() ? this.cropWebtoon : this.crop) ? 'crop' : 'crop_off',
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

  // 整章图片翻译：OCR 识别 + 分块翻译，当前页起先后再回绕，逐页叠加译文
  private async translateChapterImages(): Promise<void> {
    if (this.translating || this.pages.length === 0 || this.destroyed) {
      return;
    }
    const gen = ++this.transGen;
    this.translating = true;
    const ui = this.getUIContext();
    if (this.pageTrans.length !== this.pages.length) {
      const slots: (PageTransData | null)[] = [];
      for (let i = 0; i < this.pages.length; i++) {
        slots.push(i < this.pageTrans.length ? this.pageTrans[i] : null);
      }
      this.pageTrans = slots;
    }
    if (!await MangaOcrTranslator.retain()) {
      this.translating = false;
      this.transOn = false;
      // OCR 服务不可用与翻译引擎失败分开提示（模拟器常无 AI OCR 服务）
      Util.toastRes(ui, $r('app.string.manga_ocr_unavailable'));
      return;
    }
    const order: number[] = [];
    for (let i = this.currentReal; i < this.pages.length; i++) {
      order.push(i);
    }
    for (let i = 0; i < this.currentReal; i++) {
      order.push(i);
    }
    let failed = false;
    try {
      const to = Settings.getTransTargetLang();
      for (const idx of order) {
        if (this.destroyed || gen !== this.transGen) {
          return;
        }
        const done = this.pageTrans[idx];
        if (done !== null && done !== undefined) {
          continue;
        }
        const page: SPage = this.pages[idx];
        try {
          const data: PageTransData | null = await MangaOcrTranslator.translateImage(page.url,
            this.manga.sourceKey, page.pageUrl ?? '', to,
            (): boolean => this.destroyed || gen !== this.transGen);
          if (this.destroyed || gen !== this.transGen) {
            return;
          }
          if (data === null) {
            // 页面语言与目标语言一致：无需翻译，终止整章流程
            this.transOn = false;
            Util.toastRes(ui, $r('app.string.trans_same_lang'));
            return;
          }
          this.pageTrans[idx] = data;
          this.transStamp += 1;
        } catch (e) {
          hilog.warn(0x0001, 'Reader', 'manga ocr translate failed: %{public}s',
            e instanceof Error ? e.message : String(e));
          failed = true;
          break;
        }
      }
    } finally {
      void MangaOcrTranslator.release();
      this.translating = false;
    }
    if (this.destroyed || gen !== this.transGen) {
      return;
    }
    if (failed) {
      this.transOn = false;
      Util.toastRes(ui, $r('app.string.novel_trans_failed'));
    } else {
      Util.toastRes(ui, $r('app.string.novel_trans_done'));
    }
  }

  // ---- PC/2in1 右键菜单：本页图片 保存 / 复制 / 分享 / 查看原图 ----

  // 标准 Menu 组件（与全 app 右键菜单一致）：系统玻璃材质/动效/键盘导航；
  // 图标经 dark 资源限定符适配明暗（base 黑 / dark 白）
  @Builder
  readerContextMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.reader_ctx_save_page'), startIcon: AppIconRes.get('download') })
        .onClick(() => {
          void this.saveCurrentPage();
        })
      MenuItem({ content: $r('app.string.reader_ctx_copy_page'), startIcon: AppIconRes.get('content_copy') })
        .onClick(() => {
          void this.copyCurrentPage();
        })
      MenuItem({ content: $r('app.string.reader_ctx_share_page'), startIcon: AppIconRes.get('share') })
        .onClick(() => {
          void this.shareCurrentPage();
        })
      MenuItem({ content: $r('app.string.reader_ctx_view_original'), startIcon: AppIconRes.get('image') })
        .onClick(() => {
          this.openPageViewer();
        })
    }
  }

  // 查看原图：CoverViewer 全屏（自带缩放/保存/分享，显示原图）
  @Builder
  pageViewerBuilder() {
    CoverViewer({
      coverUrl: this.viewPageUrl,
      sourceKey: this.manga.sourceKey,
      title: `${this.manga.title} p${this.currentReal + 1}`,
      onClose: (): void => {
        this.showPageViewer = false;
      }
    })
  }

  // 当前页原图落盘沙箱（ImageCache 下载/缓存），失败返回空串
  private async ensurePageLocal(): Promise<string> {
    const page: SPage | undefined = this.pages[this.currentReal];
    if (page === undefined) {
      return '';
    }
    try {
      const local = await ImageCache.ensureLocal(Util.hostAbilityContext(this.getUIContext()),
        page.url, this.manga.sourceKey);
      hilog.info(0x0001, 'Reader', 'ctx menu: page local resolved, len=%{public}d', local.length);
      return local;
    } catch (e) {
      hilog.warn(0x0001, 'Reader', 'page download failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      return '';
    }
  }

  // 保存当前页原图到图库
  // 防抖：系统保存对话框在部分环境会静默挂起十几秒才失败，期间无任何反馈，
  // 用户会反复触发导致回退确认弹窗层叠（点一次按钮只关一层，看似关不掉）
  private saveInFlight: boolean = false;

  private async saveCurrentPage(): Promise<void> {
    if (this.saveInFlight) {
      hilog.info(0x0001, 'Reader', 'ctx menu: save already in flight, ignore');
      return;
    }
    this.saveInFlight = true;
    try {
      await this.doSaveCurrentPage();
    } finally {
      this.saveInFlight = false;
    }
  }

  private async doSaveCurrentPage(): Promise<void> {
    hilog.info(0x0001, 'Reader', 'ctx menu: save page %{public}d', this.currentReal);
    const ui = this.getUIContext();
    const local = await this.ensurePageLocal();
    if (local === '') {
      Util.toastRes(ui, $r('app.string.reader_page_save_failed'));
      return;
    }
    const title = `${ImageActions.safeName(this.manga.title)}_p${this.currentReal + 1}`;
    const result = await ImageActions.saveToGallery(Util.hostAbilityContext(ui), local, title);
    hilog.info(0x0001, 'Reader', 'ctx menu: save result=%{public}s', result);
    if (result === 'ok') {
      Util.toastRes(ui, $r('app.string.reader_page_saved'));
      return;
    }
    if (result === 'declined') {
      Util.toastRes(ui, $r('app.string.reader_page_save_failed'));
      return;
    }
    // 系统保存对话框不可用：回退 SaveButton 确认弹窗
    const fileName = `${title}.${ImageActions.fileExtOf(local)}`;
    const dialog = new CustomDialogController({
      builder: SaveConfirmDialog({
        title: $r('app.string.reader_save_confirm_title'),
        fileName: fileName,
        onConfirmed: (): void => {
          ImageActions.saveViaCreateAsset(Util.hostAbilityContext(ui), local, title)
            .then((ok2: boolean) => {
              hilog.info(0x0001, 'Reader', 'ctx menu: save fallback result=%{public}s', ok2 ? 'ok' : 'fail');
              Util.toastRes(ui, ok2 ? $r('app.string.reader_page_saved') :
                $r('app.string.reader_page_save_failed'));
            });
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  // 复制当前页原图到剪贴板
  private async copyCurrentPage(): Promise<void> {
    hilog.info(0x0001, 'Reader', 'ctx menu: copy page %{public}d', this.currentReal);
    const ui = this.getUIContext();
    const local = await this.ensurePageLocal();
    if (local === '') {
      Util.toastRes(ui, $r('app.string.reader_page_copy_failed'));
      return;
    }
    const ok = await ImageActions.copyToClipboard(local);
    hilog.info(0x0001, 'Reader', 'ctx menu: copy result=%{public}s', ok ? 'ok' : 'fail');
    Util.toastRes(ui, ok ? $r('app.string.reader_page_copied') : $r('app.string.reader_page_copy_failed'));
  }

  // 分享当前页原图
  private async shareCurrentPage(): Promise<void> {
    hilog.info(0x0001, 'Reader', 'ctx menu: share page %{public}d', this.currentReal);
    const ui = this.getUIContext();
    const local = await this.ensurePageLocal();
    if (local === '') {
      Util.toastRes(ui, $r('app.string.reader_page_share_failed'));
      return;
    }
    const ok = await ImageActions.share(Util.hostAbilityContext(ui), local,
      `${this.manga.title} p${this.currentReal + 1}`);
    hilog.info(0x0001, 'Reader', 'ctx menu: share result=%{public}s', ok ? 'ok' : 'fail');
    if (!ok) {
      Util.toastRes(ui, $r('app.string.reader_page_share_failed'));
    }
  }

  // 全屏查看当前页原图
  private openPageViewer(): void {
    hilog.info(0x0001, 'Reader', 'ctx menu: view original page %{public}d', this.currentReal);
    const page: SPage | undefined = this.pages[this.currentReal];
    if (page === undefined) {
      return;
    }
    this.viewPageUrl = page.url;
    this.showPageViewer = true;
  }

  build() {
    NavDestination() {
      // HDS 沉浸宿主：设置行挂入页签栏胶囊、进度行挂入迷你栏胶囊，
      // 垂直堆叠为两块独立玻璃；showMenu 开合驱动官方显隐动效
      ReaderHdsHost({
        barsVisible: this.showMenu,
        barBottomMargin: Math.max(this.navBarH, 12),
        barWidth: 328,
        content: (): void => {
          this.readerBody();
        },
        progressBar: (): void => {
          this.menuNavRow();
        },
        settingsBar: (): void => {
          this.menuSettingsRow();
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
    .bindSheet($$this.showOrientationSheet, this.orientationSheetBuilder(),
      SheetPreset.fit(this.windowW, {
        title: $r('app.string.reader_screen_orientation'),
        showClose: false,
        glass: true
      }))
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

  // 阅读器主体（内容 + 菜单 + Sheet 宿主）：装入 ReaderHdsHost 唯一 TabContent
  @Builder
  readerBody() {
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
        .onAreaChange((_old: Area, newArea: Area) => {
          this.syncReaderArea(newArea);
        })
      } else if (this.stripMode()) {
        // 条漫/连续模式：PixelMap 直绘的无限竖向滚动（防防盗链拦截 + 内存受控）
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
          .blendMode(this.blendModeValue())
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
          .blendMode(this.blendModeValue())
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
          .blendMode(this.blendModeValue())
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
          .blendMode(this.blendModeValue())
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

      // 墨水屏闪屏遮罩（常驻全屏，不拦截触摸；flashTick 翻页驱动）
      ReaderFlashOverlay({
        flashTick: this.flashTick,
        flashEnabled: this.flashEnabled,
        flashColor: this.flashColor,
        flashDurationMs: this.flashDurationMs,
        flashInterval: this.flashEveryPages
      })

      // 页码指示（菜单收起时）
      if (!this.showMenu && !this.loading && this.pages.length > 0 && this.showPageNumber) {
        ReaderIndicatorBadge({
          text: `${this.currentReal + 1}/${this.pages.length}`,
          navBarH: this.navBarH
        })
      }

      // 页眉页脚常驻小字（章节名/页码；菜单打开或加载中隐藏）
      if (this.showHeaderFooter && !this.showMenu && !this.loading && this.pages.length > 0) {
        ReaderHeaderText({
          text: this.chapter.name,
          statusBarH: this.statusBarH
        })
        ReaderFooterText({
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
          }
        })
      }
      // 设置面板 bindSheet 常驻宿主：挂 if(showMenu) 条件节点时菜单收起即销毁宿主，弹层不可靠；
      // 同一节点链式绑定多个 bindSheet 只有最后一个生效，故用独立常驻节点承载
      Column()
        .width(0)
        .height(0)
        .hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showSettings, this.settingsSheet(),
          SheetPreset.fit(this.windowW, {
            title: $r('app.string.reader_settings'),
            showClose: false,
            glass: true
          }))
      // 章节目录抽屉宿主（同上：独立常驻节点承载）
      Column()
        .width(0)
        .height(0)
        .hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showChapterSheet, this.chapterSheetBuilder(),
          SheetPreset.fit(this.windowW, {
            title: $r('app.string.reader_chapter_list'),
            showClose: false,
            glass: true,
            height: SheetSize.MEDIUM
          }))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
    // 键盘控制宿主：默认获焦使 onKeyEvent 生效，触摸重聚焦避免焦点漂移后按键失灵
    .focusable(true)
    .defaultFocus(true)
    .focusOnTouch(true)
    .onKeyEvent((event: KeyEvent) => {
      this.handleReaderKey(event);
    })
    .bindSheet($$this.showModeSheet, this.modeSheetBuilder(),
      SheetPreset.fit(this.windowW, {
        title: $r('app.string.reader_reading_mode'),
        showClose: false,
        glass: true
      }))
    // PC/2in1：内容区右键菜单（保存/复制/分享/查看原图），标准 Menu 组件
    .bindContextMenu(this.readerContextMenu, ResponseType.RightClick)
    // 查看原图：复用 CoverViewer 全屏查看（自带缩放/保存/分享）
    .bindContentCover($$this.showPageViewer, this.pageViewerBuilder(), {
      modalTransition: ModalTransition.ALPHA,
      backgroundColor: '#B3000000'
    })
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
        if (!this.stripMode()) {
          Column({ space: 8 }) {
            Text($r('app.string.novel_page_animation'))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              this.animChip($r('app.string.novel_anim_curl'), 'curl')
              this.animChip($r('app.string.novel_anim_slide'), 'slide')
              this.animChip($r('app.string.novel_anim_cover'), 'cover')
              if (this.mode !== 'vertical' && !this.dualPageActive()) {
                // 附加转场动画：仅单页水平模式可用
                this.animChip($r('app.string.novel_anim_stack'), 'stack')
                this.animChip($r('app.string.novel_anim_fade'), 'fade')
              }
            }
            .width('100%')
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: 8
          })

          Divider().color(this.pal.divider)
        }
        if (this.stripMode()) {
          // 条漫/连续：侧边距 + 页间距
          this.filterSliderRow($r('app.string.reader_webtoon_padding'), this.webtoonPadding, 0, 25,
            (value: number, done: boolean): void => {
              this.webtoonPadding = value;
              if (done) {
                Settings.setReaderWebtoonPadding(value);
              }
            })
          Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })
          this.filterSliderRow($r('app.string.reader_webtoon_gap'), this.webtoonGap, 0, 40,
            (value: number, done: boolean): void => {
              this.webtoonGap = value;
              if (done) {
                Settings.setReaderWebtoonGap(value);
              }
            })
          Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })
          SwitchRow({
            title: $r('app.string.reader_set_crop_webtoon'),
            isOn: this.cropWebtoon,
            onChange: (value: boolean): void => {
              this.setCrop(value);
            }
          })
          Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })
          SwitchRow({
            title: $r('app.string.reader_set_webtoon_no_zoom_out'),
            isOn: this.webtoonDisableZoomOut,
            onChange: (value: boolean): void => {
              this.webtoonDisableZoomOut = value;
              Settings.setReaderWebtoonDisableZoomOut(value);
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
              this.navChip($r('app.string.reader_nav_lshape'), 'lshape')
              this.navChip($r('app.string.reader_nav_kindle'), 'kindle')
              this.navChip($r('app.string.reader_nav_none'), 'none')
            }
            .width('100%')
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: 8
          })
          Divider().color(this.pal.divider)

          SwitchRow({
            title: $r('app.string.reader_crop_borders'),
            isOn: this.crop,
            onChange: (value: boolean): void => {
              this.setCrop(value);
            }
          })

          Divider().color(this.pal.divider)

          // 双页显示（横向分页模式：自动=横屏双页 / 始终 / 关闭）
          Column({ space: 8 }) {
            Text($r('app.string.reader_dual_page'))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              this.dualChip($r('app.string.reader_dual_auto'), 'auto')
              this.dualChip($r('app.string.reader_dual_force'), 'force')
              this.dualChip($r('app.string.reader_dual_off'), 'off')
            }
            .width('100%')
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: 8
          })

          if (this.mode !== 'rtl') {
            SwitchRow({
              title: $r('app.string.reader_dual_cover'),
              isOn: this.dualCover,
              onChange: (value: boolean): void => {
                this.dualCover = value;
                Settings.setReaderDualPageCover(value);
                this.applyMode(false);
              }
            })
          }

          Divider().color(this.pal.divider)

          // 缩放起始位置（双击放大落点，对齐 Mihon zoomStartPosition）
          Column({ space: 8 }) {
            Text($r('app.string.reader_set_zoom_start'))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              this.zoomStartChip($r('app.string.reader_zoom_automatic'), 'automatic')
              this.zoomStartChip($r('app.string.reader_zoom_left'), 'left')
              this.zoomStartChip($r('app.string.reader_zoom_right'), 'right')
              this.zoomStartChip($r('app.string.reader_zoom_center'), 'center')
            }
            .width('100%')
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: 8
          })
        }
      } else if (this.settingsTab === 1) {
        // 常规：章节跳过 / 过渡页 / 墨水屏刷新 / 背景色 / 显示页码 / 亮度
        SwitchRow({
          title: $r('app.string.reader_set_skip_read'),
          isOn: this.skipRead,
          onChange: (value: boolean): void => {
            this.skipRead = value;
            Settings.setReaderSkipRead(value);
            void this.refreshNeighbors();
          }
        })
        Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })
        SwitchRow({
          title: $r('app.string.reader_set_skip_filtered'),
          isOn: this.skipFiltered,
          onChange: (value: boolean): void => {
            this.skipFiltered = value;
            Settings.setReaderSkipFiltered(value);
            void this.refreshNeighbors();
          }
        })
        Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })
        SwitchRow({
          title: $r('app.string.reader_set_skip_duplicate'),
          isOn: this.skipDuplicate,
          onChange: (value: boolean): void => {
            this.skipDuplicate = value;
            Settings.setReaderSkipDuplicate(value);
            void this.refreshNeighbors();
          }
        })
        Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })
        SwitchRow({
          title: $r('app.string.reader_set_chapter_transition'),
          isOn: this.showChapterTransition,
          onChange: (value: boolean): void => {
            this.showChapterTransition = value;
            Settings.setReaderShowChapterTransition(value);
            this.applyMode(false);
          }
        })
        Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })

        // 墨水屏整页刷新闪烁（翻页时叠加黑白闪层）
        SwitchRow({
          title: $r('app.string.reader_set_flash_enable'),
          isOn: this.flashEnabled,
          onChange: (value: boolean): void => {
            this.flashEnabled = value;
            Settings.setReaderFlashEnabled(value);
          }
        })
        if (this.flashEnabled) {
          Column({ space: 8 }) {
            Text($r('app.string.reader_set_flash_color'))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              this.flashColorChip($r('app.string.reader_flash_color_white'), 'white')
              this.flashColorChip($r('app.string.reader_flash_color_black'), 'black')
              this.flashColorChip($r('app.string.reader_flash_color_both'), 'both')
            }
            .width('100%')
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: 4
          })
          this.numSliderRow($r('app.string.reader_set_flash_duration'), this.flashDurationMs, 40, 500,
            ' ms', (value: number, done: boolean): void => {
              this.flashDurationMs = value;
              if (done) {
                Settings.setReaderFlashDurationMs(value);
              }
            })
          this.numSliderRow($r('app.string.reader_set_flash_every'), this.flashEveryPages, 1, 10,
            '', (value: number, done: boolean): void => {
              this.flashEveryPages = value;
              if (done) {
                Settings.setReaderFlashEveryPages(value);
              }
            })
        }
        Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })

        Column({ space: 8 }) {
          Text($r('app.string.reader_background'))
            .fontSize(13)
            .fontColor(this.pal.sub)
            .width('100%')
          Row({ space: 8 }) {
            this.themeChip($r('app.string.reader_theme_auto'), 3)
            this.themeChip($r('app.string.reader_theme_white'), 0)
            this.themeChip($r('app.string.reader_theme_paper'), 4)
            this.themeChip($r('app.string.reader_theme_gray'), 2)
            this.themeChip($r('app.string.reader_theme_black'), 1)
          }
          .width('100%')
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 8
        })

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

        // 图片翻译（OCR 整章翻译叠加）
        SwitchRow({
          title: $r('app.string.manga_trans_image'),
          subtitle: $r('app.string.manga_trans_image_sub'),
          isOn: this.transOn,
          onChange: (value: boolean): void => {
            Settings.setTransEnabled(value);
            if (!value) {
              // 关闭：取消在途翻译并隐藏叠加
              this.transGen += 1;
              this.translating = false;
              this.transOn = false;
              return;
            }
            this.transOn = true;
            void this.translateChapterImages();
          }
        })

        Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })

        // 亮度
        Row() {
          Text($r('app.string.reader_brightness'))
            .fontSize(16)
            .fontColor(this.pal.text)
            .width(64)
          WideSlider({
            sliderValue: this.brightLv,
            min: 0,
            max: 1,
            step: 0.05,
            onChange: (value: number, mode: SliderChangeMode): void => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.brightLv = Math.round(value * 20) / 20;
                Settings.setReaderBrightness(this.brightLv);
                this.applyBrightness();
              }
            }
          })
            .layoutWeight(1)
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
        // 滤镜：混合模式 / 灰度 / 反色 / 亮度 / 对比度 / 饱和度（参考 Mihon，每项有开关控制是否应用）
        Column({ space: 8 }) {
          Text($r('app.string.reader_set_color_blend'))
            .fontSize(13)
            .fontColor(this.pal.sub)
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            this.blendChip($r('app.string.reader_blend_none'), 'none')
            this.blendChip($r('app.string.reader_blend_multiply'), 'multiply')
            this.blendChip($r('app.string.reader_blend_screen'), 'screen')
            this.blendChip($r('app.string.reader_blend_overlay'), 'overlay')
            this.blendChip($r('app.string.reader_blend_darken'), 'darken')
            this.blendChip($r('app.string.reader_blend_lighten'), 'lighten')
          }
          .width('100%')
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 8
        })
        Divider().color(this.pal.divider)
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
      WideSlider({
        sliderValue: value,
        min: min,
        max: max,
        step: 1,
        onChange: (sliderValue: number, mode: SliderChangeMode): void => {
          onChange(Math.round(sliderValue),
            mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
        }
      })
        .layoutWeight(1)
        .margin({ left: 8, right: 8 })
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

  // 数值滑杆行：label + Slider + 数值（带单位后缀，拖动实时预览，松手持久化）
  @Builder
  numSliderRow(label: ResourceStr, value: number, min: number, max: number, suffix: string,
    onChange: (value: number, done: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.pal.text)
        .width(96)
      WideSlider({
        sliderValue: value,
        min: min,
        max: max,
        step: 1,
        onChange: (sliderValue: number, mode: SliderChangeMode): void => {
          onChange(Math.round(sliderValue),
            mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
        }
      })
        .layoutWeight(1)
        .margin({ left: 8, right: 8 })
      Text(`${Math.round(value)}${suffix}`)
        .fontSize(12)
        .fontColor(this.pal.sub)
        .width(52)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
  }

  // 缩放起始位置 chip
  @Builder
  zoomStartChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.zoomStart === value ? this.pal.onPrimary : this.pal.text)
      .padding({
        left: 12,
        right: 12,
        top: 6,
        bottom: 6
      })
      .borderRadius(14)
      .backgroundColor(this.zoomStart === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.zoomStart = value;
        Settings.setReaderZoomStart(value);
      })
  }

  // 滤镜混合模式 chip
  @Builder
  blendChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.filterBlend === value ? this.pal.onPrimary : this.pal.text)
      .padding({
        left: 12,
        right: 12,
        top: 6,
        bottom: 6
      })
      .borderRadius(14)
      .backgroundColor(this.filterBlend === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.filterBlend = value;
        Settings.setReaderColorFilterBlend(value);
      })
  }

  // 墨水屏闪烁颜色 chip
  @Builder
  flashColorChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.flashColor === value ? this.pal.onPrimary : this.pal.text)
      .padding({
        left: 12,
        right: 12,
        top: 6,
        bottom: 6
      })
      .borderRadius(14)
      .backgroundColor(this.flashColor === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.flashColor = value;
        Settings.setReaderFlashColor(value);
      })
  }

  @Builder
  animChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.pageAnim === value ? this.pal.onPrimary : this.pal.text)
      .padding({
        left: 12,
        right: 12,
        top: 6,
        bottom: 6
      })
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
      .padding({
        left: 12,
        right: 12,
        top: 6,
        bottom: 6
      })
      .borderRadius(14)
      .backgroundColor(this.navMode === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.navMode = value;
        Settings.setReaderNavMode(value);
      })
  }

  // 双页模式 chip：auto=横屏自动（默认） force=始终双页 off=始终单页
  @Builder
  dualChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.dualPageMode === value ? this.pal.onPrimary : this.pal.text)
      .padding({
        left: 12,
        right: 12,
        top: 6,
        bottom: 6
      })
      .borderRadius(14)
      .backgroundColor(this.dualPageMode === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        if (this.dualPageMode === value) {
          return;
        }
        this.dualPageMode = value;
        Settings.setReaderDualPageMode(value);
        this.applyMode(false);
      })
  }

  // 0=白 1=黑 2=灰 3=自动（跟随深色模式） 4=纸张（护眼米黄）
  syncReaderBgDark(): void {
    const t = this.readerTheme === 3 ? (this.isDark ? 1 : 0) : this.readerTheme;
    AppStorage.setOrCreate('readerBgDark', t !== 0 && t !== 4);
  }

  onDarkChanged(): void {
    this.syncReaderBgDark();
  }

  @Builder
  themeChip(label: ResourceStr, value: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.readerTheme === value ? this.pal.onPrimary : this.pal.text)
      .padding({
        left: 14,
        right: 14,
        top: 6,
        bottom: 6
      })
      .borderRadius(16)
      .backgroundColor(this.readerTheme === value ? this.pal.primary : this.pal.chip)
      .onClick(() => {
        this.readerTheme = value;
        Settings.setReaderTheme(value);
        this.syncReaderBgDark();
      })
  }

  // 切换相邻章节；fromBoundary=true 表示由阅读边界（过渡页）触发，

  @Builder
  chapterSheetBuilder() {
    ReaderChapterSheet({
      chapters: this.tocChapters,
      currentId: this.chapterId,
      pal: this.pal,
      onPick: (id: number): void => {
        this.showChapterSheet = false;
        if (id !== this.chapterId) {
          Haptics.medium();
          this.gotoBoundary = 0;
          this.chapterId = id;
          this.loadChapter();
        }
      }
    })
  }

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

  // 点击热区翻页：delta 为阅读方向步进（+1 下一页，-1 上一页）。
  // RTL 展示序与阅读序相反，展示索引步进方向需取反；章节首尾垫有过渡页，

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
    const wasLandscape = this.isLandscape;
    this.isLandscape = this.readerW > this.readerH;
    // 横竖屏翻转后双页 auto 激活态/成组占位可能变化，重建分页单元格并对齐到当前页所在组
    if (wasLandscape !== this.isLandscape && !this.loading && this.pages.length > 0
      && !this.stripMode() && this.mode !== 'vertical') {
      this.applyMode(false);
    }
  }

  private async loadChapter(): Promise<void> {
    const gen = ++this.loadGen;
    this.loading = true;
    this.showMenu = false;
    this.transOverlay = 0;
    // 切章作废在途图片翻译并清空译文叠加（transOn 保持会话开关语义）
    this.transGen += 1;
    this.translating = false;
    this.pageTrans = [];
    this.resetZoom();
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
        // 离线优先：读取已下载的本地页面（CBZ 章节首次阅读自动解压到缓存）
        const files: string[] = await ChapterPageStore.localPagesAsync(chapter.mangaId, chapter.id);
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
        // 部分下载复用：该章下载进行中/中断时，已完整落盘的页直接用本地文件，
        // 未下载的页照常在线加载（列表结构不变，仅 url 替换为 file://）
        pages = ChapterPageStore.substituteDownloadedPages(chapter.mangaId, chapter.id, pages);
      }
      if (gen !== this.loadGen) {
        return;
      }
      // 页面处理：仅对本地（file://）页跳过重复页/清理空白页（在线页直接通过）
      if (pages.length > 0) {
        pages = await PageSanitizer.sanitize(pages, Settings.getReaderSkipDuplicatePages(),
          Settings.getReaderCleanBlankPages());
        if (gen !== this.loadGen) {
          return;
        }
      }
      this.pages = pages;
      // 每部漫画独立阅读模式（对齐 Mihon per-manga viewer）：
      // 本漫画设置过的模式优先，未设置回退全局默认模式
      const perMangaMode: string = Settings.getViewerMode(`${chapter.mangaId}`);
      this.mode = perMangaMode !== '' ? perMangaMode : Settings.getReaderMode();
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
      // 跨设备接续/碰一碰会话快照：随章节加载刷新（进度语义=页码）
      ContinueSession.update(ContentType.MANGA, this.manga, chapter, this.currentReal);
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
      // 阅读预下载：当前章与下一章均已下载时，按设置预下载后续未读章节
      if (manga !== undefined) {
        DownloadRules.downloadAheadIfNeeded(manga, chapter.id);
      }
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
    this.armAutoPage();
    // 会话开关开着：新章加载完成后自动开始图片翻译
    if (this.transOn && this.pages.length > 0) {
      void this.translateChapterImages();
    }
  }

  // 应用跳过筛选后的导航章节表（对齐 Mihon ReaderViewModel.getCurrentChapters）：
  // skipFiltered 去除违反详情页筛选的章节；skipRead 去除已读；当前章被过滤时补回再重排；
  // skipDuplicate 去除同章节号重复（当前章优先）。手动章节目录选择不走该表，不受影响
  private buildNavChapters(all: ChapterRecord[]): ChapterRecord[] {
    let list: ChapterRecord[] = all.slice();
    if (this.skipFiltered) {
      const flags: number = this.manga.chapterFlags;
      const unreadMode: string = ChapterFlags.unreadFilter(flags);
      const dlMode: string = ChapterFlags.downloadedFilter(flags);
      const bmMode: string = ChapterFlags.bookmarkedFilter(flags);
      list = list.filter((c: ChapterRecord): boolean => {
        if (unreadMode === 'include' && c.read) {
          return false;
        }
        if (unreadMode === 'exclude' && !c.read) {
          return false;
        }
        if (dlMode === 'include' && !DownloadService.isDownloaded(c.id)) {
          return false;
        }
        if (dlMode === 'exclude' && DownloadService.isDownloaded(c.id)) {
          return false;
        }
        if (bmMode === 'include' && !c.bookmark) {
          return false;
        }
        if (bmMode === 'exclude' && c.bookmark) {
          return false;
        }
        return true;
      });
    }
    if (this.skipRead) {
      list = list.filter((c: ChapterRecord): boolean => !c.read);
    }
    // 当前章被过滤时补回，保证阅读位置始终在导航表内
    if (list.findIndex((c: ChapterRecord): boolean => c.id === this.chapterId) < 0) {
      const cur: ChapterRecord | undefined = all.find((c: ChapterRecord): boolean => c.id === this.chapterId);
      if (cur !== undefined) {
        list.push(cur);
      }
    }
    // 阅读正序（对齐 Mihon getChapterSort(manga, sortDescending=false)）：
    // 源顺序模式 = sortOrder 升序（sortOrder 即源声明的"旧→新"自然顺序）；
    // 章节号/日期/字母模式 = 对应键升序。prev/next 不再受详情页展示方向影响
    list = ReaderChapterNav.readingOrder(list, this.manga.chapterFlags, this.manga.sourceKey);
    if (this.skipDuplicate) {
      list = this.removeDuplicateChapters(list);
    }
    return list;
  }

  // 同章节号去重（对齐 Mihon removeDuplicateChapters）：按章节号分组，每组取一章——
  // 当前章所在组保留当前章；其余组优先与当前章同汉化组者，再取上传时间最新者
  private removeDuplicateChapters(list: ChapterRecord[]): ChapterRecord[] {
    const groups: Map<number, ChapterRecord[]> = new Map<number, ChapterRecord[]>();
    for (const c of list) {
      const key: number = c.chapterNumber;
      const arr: ChapterRecord[] | undefined = groups.get(key);
      if (arr === undefined) {
        groups.set(key, [c]);
      } else {
        arr.push(c);
      }
    }
    const curScanlator: string = this.chapter.scanlator;
    const out: ChapterRecord[] = [];
    groups.forEach((arr: ChapterRecord[]): void => {
      const cur: ChapterRecord | undefined = arr.find((c: ChapterRecord): boolean => c.id === this.chapterId);
      if (cur !== undefined) {
        out.push(cur);
        return;
      }
      const sameScan: ChapterRecord | undefined =
        arr.find((c: ChapterRecord): boolean => c.scanlator === curScanlator);
      if (sameScan !== undefined) {
        out.push(sameScan);
        return;
      }
      let newest: ChapterRecord = arr[0];
      for (const c of arr) {
        if (c.dateUpload > newest.dateUpload) {
          newest = c;
        }
      }
      out.push(newest);
    });
    // 保持传入的阅读正序（对齐 Mihon removeDuplicates 保序去重），不再按 sortOrder 重排
    return out;
  }

  // 两章之间缺失的章节号数（对齐 Mihon MissingChapters.calculateChapterGap：floor 差 - 1）
  private chapterGap(a: ChapterRecord, b: ChapterRecord): number {
    const lo: number = Math.min(Math.floor(a.chapterNumber), Math.floor(b.chapterNumber));
    const hi: number = Math.max(Math.floor(a.chapterNumber), Math.floor(b.chapterNumber));
    const gap: number = hi - lo - 1;
    return gap > 0 ? gap : 0;
  }

  // 导航表内相邻章节 id（无目标返回 0）
  private navNeighborId(next: boolean): number {
    let pos: number = -1;
    for (let i = 0; i < this.navChapters.length; i++) {
      if (this.navChapters[i].id === this.chapterId) {
        pos = i;
        break;
      }
    }
    if (next) {
      return pos >= 0 && pos < this.navChapters.length - 1 ? this.navChapters[pos + 1].id : 0;
    }
    return pos > 0 ? this.navChapters[pos - 1].id : 0;
  }

  private async refreshNeighbors(): Promise<void> {
    const all: ChapterRecord[] = await ChapterRepo.listByManga(this.mangaId);
    this.navChapters = this.buildNavChapters(all);
    let pos: number = -1;
    for (let i = 0; i < this.navChapters.length; i++) {
      if (this.navChapters[i].id === this.chapterId) {
        pos = i;
        break;
      }
    }
    const prev: ChapterRecord | undefined = pos > 0 ? this.navChapters[pos - 1] : undefined;
    const next: ChapterRecord | undefined =
      pos >= 0 && pos < this.navChapters.length - 1 ? this.navChapters[pos + 1] : undefined;
    this.hasPrev = prev !== undefined;
    this.hasNext = next !== undefined;
    this.prevChapterName = prev !== undefined ? prev.name : '';
    this.nextChapterName = next !== undefined ? next.name : '';
    this.prevChapterScanlator = prev !== undefined ? prev.scanlator : '';
    this.prevChapterDownloaded = prev !== undefined ? DownloadService.isDownloaded(prev.id) : false;
    this.nextChapterScanlator = next !== undefined ? next.scanlator : '';
    this.nextChapterDownloaded = next !== undefined ? DownloadService.isDownloaded(next.id) : false;
    this.currentChapterDownloaded = DownloadService.isDownloaded(this.chapterId);
    this.prevGap = prev !== undefined ? this.chapterGap(prev, this.chapter) : 0;
    this.nextGap = next !== undefined ? this.chapterGap(this.chapter, next) : 0;
  }

  // 章节过渡页显隐（对齐 Mihon：开关开启或两章章节号不连续时显示）
  private showPrevTrans(): boolean {
    return this.showChapterTransition || this.prevGap > 0;
  }

  private showNextTrans(): boolean {
    return this.showChapterTransition || this.nextGap > 0;
  }

  // 条漫列表头部偏移（上一章过渡页隐藏时为 0）
  private stripLead(): number {
    return this.showPrevTrans() ? STRIP_LEAD_COUNT : 0;
  }

  // 滤镜混合模式（对齐 Mihon colorFilterBlendMode；近似：整个滤镜区与阅读器背景混合）
  private blendModeValue(): BlendMode {
    if (this.filterBlend === 'multiply') {
      return BlendMode.MULTIPLY;
    }
    if (this.filterBlend === 'screen') {
      return BlendMode.SCREEN;
    }
    if (this.filterBlend === 'overlay') {
      return BlendMode.OVERLAY;
    }
    if (this.filterBlend === 'darken') {
      return BlendMode.DARKEN;
    }
    if (this.filterBlend === 'lighten') {
      return BlendMode.LIGHTEN;
    }
    return BlendMode.NONE;
  }

  // 非 RTL：[上一章过渡(按开关/缺章), (双页封面独立时空白占位), 页0..页N-1, 下一章过渡(按开关/缺章)]；
  // RTL 整体反转（阅读前进 = 索引递减），双页成组对齐时在下一章过渡页后垫空白占位；
  // 双页模式过渡槽恒保留（过渡页隐藏时以空白占位顶替，成组配对数学不变）；
  // 单页模式过渡页隐藏时完全省略（displayToReal/realToDisplay/cellKind 同步按偏移计算）
  private applyMode(scrollToResume: boolean): void {
    this.resetZoom();
    this.flipTarget = -1;
    const extra = this.dualExtra();
    const dual = this.dualPageActive();
    const showPrev = this.showPrevTrans();
    const showNext = this.showNextTrans();
    const leadCount = dual || showPrev ? 1 : 0;
    const tailCount = dual || showNext ? 1 : 0;
    const cellCount = this.pages.length + leadCount + tailCount + extra;
    this.coverX = Util.zeros(cellCount);
    this.coverY = Util.zeros(cellCount);
    this.coverZ = Util.zeros(cellCount);
    this.resetAnimArrays(cellCount);
    const cells: SPage[] = [];
    if (this.mode === 'rtl') {
      if (tailCount > 0) {
        // 前端槽：下一章过渡页（隐藏时双页以空白占位顶替，保持后续成组对齐）
        const nextT: SPage = { index: -2, url: showNext ? TRANS_NEXT_URL : DUAL_BLANK_URL };
        cells.push(nextT);
        if (extra > 0) {
          // 双页成组对齐占位：保证封面组按“封面独立”设置落位
          const blankCell: SPage = { index: -3, url: DUAL_BLANK_URL };
          cells.push(blankCell);
        }
      }
      for (let i = this.pages.length - 1; i >= 0; i--) {
        cells.push(this.pages[i]);
      }
      if (leadCount > 0) {
        const prevT: SPage = { index: -1, url: showPrev ? TRANS_PREV_URL : DUAL_BLANK_URL };
        cells.push(prevT);
      }
      this.dataSource.setPages(cells);
      this.displayIndex = this.realToDisplay(this.currentReal);
    } else {
      if (leadCount > 0) {
        // 双页封面独立：上一章过渡页后垫空白占位，封面页不再与过渡页配对
        const prevT: SPage = { index: -1, url: showPrev ? TRANS_PREV_URL : DUAL_BLANK_URL };
        cells.push(prevT);
        if (extra > 0) {
          const blankCell: SPage = { index: -3, url: DUAL_BLANK_URL };
          cells.push(blankCell);
        }
      }
      for (let i = 0; i < this.pages.length; i++) {
        cells.push(this.pages[i]);
      }
      if (tailCount > 0) {
        const nextT: SPage = { index: -2, url: showNext ? TRANS_NEXT_URL : DUAL_BLANK_URL };
        cells.push(nextT);
      }
      this.dataSource.setPages(cells);
      this.displayIndex = this.realToDisplay(this.currentReal);
    }
    if (this.stripMode() && scrollToResume) {
      const target = this.currentReal + this.stripLead();
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

  // 展示单元格（含过渡页）→ 真实页序；双页取组内先读页（LTR 左页、RTL 右页），
  // 组内无真实页（纯过渡组）返回 -1 由调用方校验；
  // 过渡页隐藏时头部偏移为 0（双页槽位恒保留，偏移不变）
  private displayToReal(displayIdx: number): number {
    if (this.dualPageActive()) {
      const rtl = this.mode === 'rtl';
      const first = this.dualCellReal(rtl ? displayIdx + 1 : displayIdx);
      if (first >= 0) {
        return first;
      }
      return this.dualCellReal(rtl ? displayIdx : displayIdx + 1);
    }
    const lead = this.showPrevTrans() ? 1 : 0;
    if (this.mode === 'rtl') {
      const tail = this.showNextTrans() ? 1 : 0;
      return this.pages.length + tail - 1 - displayIdx;
    }
    return displayIdx - lead;
  }

  private realToDisplay(realIdx: number): number {
    if (this.dualPageActive()) {
      // 真实页所在单元格 → 对齐到组起始格（偶数）
      const cell = this.mode === 'rtl' ? this.pages.length + this.dualExtra() - realIdx
        : realIdx + (this.dualCover ? 1 : 2);
      return cell - (cell % 2);
    }
    if (this.mode === 'rtl') {
      const tail = this.showNextTrans() ? 1 : 0;
      return this.pages.length - 1 - realIdx + tail;
    }
    return realIdx + (this.showPrevTrans() ? 1 : 0);
  }

  // 展示单元格种类：'prev'/'next' 为过渡组/页，'' 为普通页；
  // 过渡页隐藏的单页模式首尾单元格即真实页（返回 ''），双页槽位恒在（返回过渡组）
  private cellKind(cell: number): string {
    if (this.dualPageActive()) {
      // 双页：首尾槽恒为过渡/占位组
      const lastCell = this.pages.length + 1 + this.dualExtra();
      if (cell === 0) {
        return this.mode === 'rtl' ? 'next' : 'prev';
      }
      if (cell === lastCell - (lastCell % 2)) {
        return this.mode === 'rtl' ? 'prev' : 'next';
      }
      return '';
    }
    const lead = this.showPrevTrans() ? 1 : 0;
    const tail = this.showNextTrans() ? 1 : 0;
    const lastCell = this.pages.length + lead + tail - 1;
    if (this.mode === 'rtl') {
      if (tail > 0 && cell === 0) {
        return 'next';
      }
      if (lead > 0 && cell === lastCell) {
        return 'prev';
      }
      return '';
    }
    if (lead > 0 && cell === 0) {
      return 'prev';
    }
    if (tail > 0 && cell === lastCell) {
      return 'next';
    }
    return '';
  }

  private async onSwipe(displayIdx: number): Promise<void> {
    this.displayIndex = displayIdx;
    this.flipTarget = -1;
    this.resetZoom();
    this.armAutoPage();
    const kind = this.cellKind(displayIdx);
    if (kind === 'next') {
      // 双页：边界组可能与末页同屏，先记录组内真实页进度
      if (this.dualPageActive()) {
        await this.persistDualBoundary(displayIdx);
      }
      // 落在“下一章”过渡页：没有下一章时呼出菜单（对齐 Mihon），有则等待继续前翻
      if (!this.hasNext) {
        this.showMenu = true;
      }
      return;
    }
    if (kind === 'prev') {
      // 双页：边界组可能与封面同屏，先记录组内真实页进度
      if (this.dualPageActive()) {
        await this.persistDualBoundary(displayIdx);
      }
      return;
    }
    const real = this.displayToReal(displayIdx);
    // 空白占位/过渡页等非正文页：不更新阅读进度
    if (real < 0 || real >= this.pages.length) {
      return;
    }
    if (real !== this.currentReal) {
      this.currentReal = real;
      await this.persistProgress();
    }
  }

  // 双页边界组（过渡页与真实页同组）内真实页进度记录
  private async persistDualBoundary(displayIdx: number): Promise<void> {
    const real = this.displayToReal(displayIdx);
    if (real >= 0 && real < this.pages.length && real !== this.currentReal) {
      this.currentReal = real;
      await this.persistProgress();
    }
  }

  private async persistProgress(): Promise<void> {
    // 翻页瞬间触发墨水屏刷新闪烁（覆盖所有真实页变更路径）
    this.flashTick += 1;
    ContinueSession.updateProgress(this.currentReal);
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
        // 读完本章：按下载设置删除倒数第 N 章的下载
        DownloadRules.onChapterFinished(this.mangaId, this.chapterId);
      }
    } catch (e) {
      hilog.warn(0x0001, 'Reader', 'persistProgress failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private setMode(mode: string): void {
    this.mode = mode;
    this.transOverlay = 0;
    // 模式按漫画保存（对齐 Mihon per-manga viewer），不改全局默认模式
    Settings.setViewerMode(`${this.mangaId}`, mode);
    this.applyMode(true);
    // 条漫/连续不支持自动翻页，切回分页模式时若此前开启则恢复倒计时
    if (this.stripMode()) {
      this.stopAutoPage();
    } else {
      this.armAutoPage();
    }
  }

  private modeIcon(): string {
    if (this.mode === 'rtl') {
      return 'reader_rtl';
    }
    if (this.mode === 'webtoon') {
      return 'reader_webtoon';
    }
    if (this.mode === 'continuous') {
      return 'reader_continuous';
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
    const modes: string[] = ['ltr', 'rtl', 'vertical', 'webtoon', 'continuous'];
    if (this.gripSupported) {
      modes.push('smart_grip');
    }
    return modes;
  }

  private modeOptions(): ResourceStr[] {
    const opts: ResourceStr[] = [$r('app.string.reader_mode_ltr'), $r('app.string.reader_mode_rtl'),
      $r('app.string.reader_mode_vertical'), $r('app.string.reader_mode_webtoon'),
      $r('app.string.reader_mode_continuous')];
    if (this.gripSupported) {
      opts.push($r('app.string.reader_mode_smart_grip'));
    }
    return opts;
  }

  private modeIcons(): string[] {
    const icons: string[] = ['reader_ltr', 'reader_rtl', 'reader_vertical', 'reader_webtoon', 'reader_continuous'];
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

  private selectOrientation(): void {
    this.showOrientationSheet = true;
  }

  // 打开章节目录抽屉（参考华为阅读）：加载全量章节，当前章高亮定位
  private async openChapterSheet(): Promise<void> {
    this.tocChapters = await ChapterRepo.listByManga(this.mangaId);
    this.showChapterSheet = true;
  }

  // 裁边开关按模式分别保存（对齐 Mihon cropBordersPaged / cropBordersWebtoon）
  private toggleCrop(): void {
    if (this.stripMode()) {
      this.cropWebtoon = !this.cropWebtoon;
      Settings.setReaderCropBordersWebtoon(this.cropWebtoon);
      return;
    }
    this.crop = !this.crop;
    Settings.setReaderCropBordersPaged(this.crop);
  }

  private setCrop(v: boolean): void {
    if (this.stripMode()) {
      this.cropWebtoon = v;
      Settings.setReaderCropBordersWebtoon(v);
      return;
    }
    this.crop = v;
    Settings.setReaderCropBordersPaged(v);
  }

  // 条漫/连续滚动模式（像素直绘竖向滚动）
  private stripMode(): boolean {
    return this.mode === 'webtoon' || this.mode === 'continuous';
  }

  // 双页显示：'auto'=横屏（内容区宽>高）自动（默认），'force'=始终双页，'off'=始终单页；
  // 条漫/连续与垂直模式不适用
  private dualPageActive(): boolean {
    if (this.dualPageMode === 'off' || this.stripMode() || this.mode === 'vertical') {
      return false;
    }
    if (this.dualPageMode === 'force') {
      return true;
    }
    return this.isLandscape;
  }

  // 双页“封面独立成页”占位数（按组翻页时用于成组对齐）：
  // LTR 关闭该开关时在上一章过渡页后垫 1 张空白，使 (p0,p1) 成组、封面不与过渡页同屏；
  // RTL 需按 p0 所在格奇偶性垫 1 张对齐封面组（开=封面与上一章过渡页同组，关=封面与 p1 同组）
  private dualExtra(): number {
    if (!this.dualPageActive()) {
      return 0;
    }
    if (this.mode === 'rtl') {
      // 无垫时 p0 位于第 n 格；cover=true 需其落偶数格（与 prevT 成组），否则落奇数格（与 p1 成组）
      const p0Even = this.pages.length % 2 === 0;
      return p0Even === this.dualCover ? 0 : 1;
    }
    return this.dualCover ? 0 : 1;
  }

  // 双页单元格 → 真实页序；过渡页/空白占位返回 -1
  private dualCellReal(cell: number): number {
    if (this.mode === 'rtl') {
      const real = this.pages.length + this.dualExtra() - cell;
      return real >= 0 && real < this.pages.length ? real : -1;
    }
    const real = cell - (this.dualCover ? 1 : 2);
    return real >= 0 && real < this.pages.length ? real : -1;
  }

  // 双页最后一组的起始单元格
  private lastGroupStart(): number {
    const lastCell = this.pages.length + 1 + this.dualExtra();
    return lastCell - (lastCell % 2);
  }

  // 双页按组步进：一次前进/后退一组（两页）；边界组朝章内方向先回到正文组
  private stepDual(delta: number): void {
    const dir = this.mode === 'rtl' ? -delta : delta;
    const base = this.flipTarget >= 0 ? this.flipTarget : this.displayIndex;
    const kind = this.cellKind(base);
    if (kind === 'next') {
      if (delta > 0) {
        this.gotoChapter(true, true);
      } else if (this.displayToReal(base) >= 0) {
        this.moveGroup(dir);
      } else {
        this.backFromTransition();
      }
      return;
    }
    if (kind === 'prev') {
      if (delta < 0) {
        this.gotoChapter(false, true);
      } else if (this.displayToReal(base) >= 0) {
        this.moveGroup(dir);
      } else {
        this.backFromTransition();
      }
      return;
    }
    this.moveGroup(dir);
  }

  // 双页翻一组（2 个单元格），越界不动；走控制器保证组切换动画
  private moveGroup(dir: number): void {
    const base = this.flipTarget >= 0 ? this.flipTarget : this.displayIndex;
    const target = base + dir * 2;
    if (target < 0 || target > this.lastGroupStart()) {
      return;
    }
    Haptics.soft();
    this.flipTarget = target;
    try {
      this.swiperCtrl.changeIndex(target, true);
    } catch (e) {
      // Swiper 未挂载：回退属性瞬跳
      this.flipTarget = -1;
      this.displayIndex = target;
      this.onSwipe(target);
    }
  }

  // Slider 跳页（按真实页序）
  private jumpToReal(real: number): void {
    if (real < 0 || real >= this.pages.length) {
      return;
    }
    const display = this.realToDisplay(real);
    this.displayIndex = display;
    if (this.stripMode()) {
      this.scroller.scrollToIndex(display, false, ScrollAlign.START);
      this.currentReal = real;
      this.persistProgress();
    } else {
      this.onSwipe(display);
    }
  }

  // 下一章落在首页、上一章落在末页；菜单按钮触发按历史进度恢复
  private async gotoChapter(next: boolean, fromBoundary: boolean = false): Promise<void> {
    // 相邻章节取自跳过筛选后的导航表（对齐 Mihon ReaderViewModel）；
    // 表内没有当前章（首帧未就绪/数据变更）时先刷新一次再取
    if (this.navChapters.findIndex((c: ChapterRecord): boolean => c.id === this.chapterId) < 0) {
      await this.refreshNeighbors();
    }
    const targetId: number = this.navNeighborId(next);
    if (targetId === 0) {
      Util.toastRes(this.getUIContext(),
        next ? $r('app.string.reader_last_chapter') : $r('app.string.reader_first_chapter'));
      return;
    }
    if (next && !this.chapter.read) {
      await ChapterRepo.setRead(this.chapterId, true);
      // 前进到下一章视为读完本章：按下载设置删除倒数第 N 章的下载
      DownloadRules.onChapterFinished(this.mangaId, this.chapterId);
    }
    Haptics.medium();
    this.gotoBoundary = fromBoundary ? (next ? 1 : -1) : 0;
    this.chapterId = targetId;
    await this.loadChapter();
  }

  // 翻页模式点击区域（导航模式：默认/从左到右/从右到左/垂直/边缘/无，对齐 Mihon pref_viewer_nav）
  // 单击延迟 260ms 派发，为双击缩放（图库手势）留出识别窗口
  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      if (event.touches.length === 0) {
        return;
      }
      if (event.touches.length > 1) {
        // 第二根手指按下：进入捏合，作废单击与待派发的单击动作
        this.touchDownX = -1;
        this.cancelPendingTap();
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
      const swipeDx = upX - this.touchDownX;
      const swipeDy = upY - this.touchDownY;
      this.touchDownX = -1;
      if (dx > 20 || dy > 20) {
        // 滑动：交给过渡页隐藏时的越界切章判定，否则忽略
        this.handleSwipePastEnd(swipeDx, swipeDy);
        return;
      }
      if (this.pages.length === 0) {
        return;
      }
      if (this.pendingTapTimer >= 0) {
        // 双击窗口内的第二次抬起：取消待派发单击，改为双击缩放
        this.cancelPendingTap();
        this.toggleZoomAt(upX, upY);
        return;
      }
      this.pendingTap = (): void => {
        this.dispatchTapZone(upX, upY);
      };
      this.pendingTapTimer = setTimeout(() => {
        this.pendingTapTimer = -1;
        const act = this.pendingTap;
        this.pendingTap = null;
        if (act !== null) {
          act();
        }
      }, 260);
    }
  }

  // 单击热区派发：在 260ms 双击窗口确认后执行（原 handleTouch Up 逻辑）
  private dispatchTapZone(upX: number, upY: number): void {
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
    if (this.navMode === 'lshape' || this.navMode === 'kindle') {
      // L 形 / Kindle 导航热区（对齐 Mihon LNavigation / KindlishNavigation）
      const nx = upX / (this.readerW > 0 ? this.readerW : 360);
      const ny = upY / (this.readerH > 0 ? this.readerH : 640);
      const delta = this.lNavDelta(nx, ny, this.navMode === 'kindle');
      if (delta === 0) {
        this.showMenu = !this.showMenu;
      } else {
        this.step(delta);
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

  // L 形 / Kindle 导航热区（对齐 Mihon LNavigation / KindlishNavigation，含水平镜像）：
  // lshape：上 1/3 上一页、下 1/3 下一页、中带左/右 1/3 上一页/下一页、中间菜单；
  // kindle：上 1/3 菜单、下方左 1/3 上一页、右 2/3 下一页；
  // 返回阅读方向步进（0=菜单）
  private lNavDelta(nx: number, ny: number, kindle: boolean): number {
    if (kindle) {
      if (ny < 0.33) {
        return 0;
      }
      return this.lNavNextOnLeft() ? (nx >= 0.66 ? -1 : 1) : (nx < 0.33 ? -1 : 1);
    }
    if (ny < 0.33) {
      return -1;
    }
    if (ny >= 0.66) {
      return 1;
    }
    if (this.lNavNextOnLeft()) {
      return nx < 0.33 ? 1 : (nx >= 0.66 ? -1 : 0);
    }
    return nx < 0.33 ? -1 : (nx >= 0.66 ? 1 : 0);
  }

  // L 形 / Kindle 热区是否水平镜像（“下一页”在左侧）：默认跟随阅读模式，可被导航模式覆盖
  private lNavNextOnLeft(): boolean {
    if (this.navMode === 'ltr') {
      return false;
    }
    if (this.navMode === 'rtl') {
      return true;
    }
    return this.mode === 'rtl' || (this.mode === 'smart_grip' && !this.gripRight);
  }

  // 过渡页隐藏时的越界滑动切章（阈值 60vp，对齐 Mihon 无过渡页直进相邻章）
  private handleSwipePastEnd(dx: number, dy: number): void {
    if (this.stripMode() || this.dualPageActive() || this.pages.length === 0 || this.useCurl()) {
      return;
    }
    if (this.mode === 'vertical') {
      if (dy < -60 && !this.showNextTrans() && this.atForwardEdge() && this.hasNext) {
        this.gotoChapter(true, true);
      } else if (dy > 60 && !this.showPrevTrans() && this.atBackwardEdge() && this.hasPrev) {
        this.gotoChapter(false, true);
      }
      return;
    }
    // 前进方向滑动分量（LTR：左滑前进；RTL：右滑前进）
    const forwardSwipe = this.mode === 'rtl' ? dx : -dx;
    if (forwardSwipe > 60 && !this.showNextTrans() && this.atForwardEdge() && this.hasNext) {
      this.gotoChapter(true, true);
    } else if (forwardSwipe < -60 && !this.showPrevTrans() && this.atBackwardEdge() && this.hasPrev) {
      this.gotoChapter(false, true);
    }
  }

  // 当前是否在前进方向边界真实页（或过渡页）
  private atForwardEdge(): boolean {
    const base = this.flipTarget >= 0 ? this.flipTarget : this.displayIndex;
    if (this.cellKind(base) === 'next') {
      return true;
    }
    const real = this.displayToReal(base);
    return real >= 0 && real >= this.pages.length - 1;
  }

  // 当前是否在后退方向边界真实页（或过渡页）
  private atBackwardEdge(): boolean {
    const base = this.flipTarget >= 0 ? this.flipTarget : this.displayIndex;
    if (this.cellKind(base) === 'prev') {
      return true;
    }
    const real = this.displayToReal(base);
    return real === 0;
  }

  // ---- 图片缩放（图库式手势）----

  // 应用缩放并夹取平移量，保证图片边缘不被拖出屏幕
  private applyZoom(scale: number, tx: number, ty: number): void {
    const s = Math.max(1, Math.min(4, scale));
    const maxTx = ((s - 1) * this.readerW) / 2;
    const maxTy = ((s - 1) * this.readerH) / 2;
    this.zoomScale = s;
    this.zoomX = Math.max(-maxTx, Math.min(maxTx, tx));
    this.zoomY = Math.max(-maxTy, Math.min(maxTy, ty));
  }

  private resetZoom(): void {
    this.zoomScale = 1;
    this.zoomX = 0;
    this.zoomY = 0;
  }

  // 双击切换缩放：已放大则复位；未放大则 2.5 倍缩放，落点按 zoomStart 设置——
  // 左起点/右起点/居中固定对边，自动模式对准点击位置（对齐 Mihon zoomStartPosition）
  private toggleZoomAt(upX: number, upY: number): void {
    if (this.zoomScale > 1.001) {
      this.resetZoom();
      return;
    }
    const s = 2.5;
    const maxTx = ((s - 1) * this.readerW) / 2;
    const cy = this.readerH / 2;
    if (this.zoomStart === 'left') {
      this.applyZoom(s, maxTx, 0);
      Haptics.soft();
      return;
    }
    if (this.zoomStart === 'right') {
      this.applyZoom(s, -maxTx, 0);
      Haptics.soft();
      return;
    }
    if (this.zoomStart === 'center') {
      this.applyZoom(s, 0, 0);
      Haptics.soft();
      return;
    }
    // 缩放以组件中心为轴，使点击点保持不动需要的平移量：(1-s)*(P-C)
    const cx = this.readerW / 2;
    this.applyZoom(s, (1 - s) * (upX - cx), (1 - s) * (upY - cy));
    Haptics.soft();
  }

  // 取消待派发的单击（双击确认/捏合打断/组件销毁时调用）
  private cancelPendingTap(): void {
    if (this.pendingTapTimer >= 0) {
      clearTimeout(this.pendingTapTimer);
      this.pendingTapTimer = -1;
    }
    this.pendingTap = null;
  }

  // ---- 自动翻页（华为阅读对齐）----

  // 切换自动翻页：条漫模式不适用；未设置间隔时默认 15 秒并持久化
  private toggleAutoPage(): void {
    if (this.autoRunning) {
      this.stopAutoPage();
      Util.toastRes(this.getUIContext(), $r('app.string.reader_auto_page_off'));
      return;
    }
    if (this.stripMode()) {
      Util.toastRes(this.getUIContext(), $r('app.string.reader_auto_page_webtoon_off'));
      return;
    }
    if (this.autoPageSec <= 0) {
      this.autoPageSec = 15;
      Settings.setReaderAutoPageSec(15);
    }
    this.autoRunning = true;
    Haptics.soft();
    this.armAutoPage();
    Util.toastRes(this.getUIContext(), $r('app.string.reader_auto_page_on'));
  }

  private stopAutoPage(): void {
    this.autoRunning = false;
    if (this.autoTimerId !== -1) {
      clearTimeout(this.autoTimerId);
      this.autoTimerId = -1;
    }
  }

  // 重新起算自动翻页倒计时（每次翻页/切章/手动操作后调用，手动翻页也会重置倒计时）
  private armAutoPage(): void {
    if (this.autoTimerId !== -1) {
      clearTimeout(this.autoTimerId);
      this.autoTimerId = -1;
    }
    if (!this.autoRunning || this.loading || this.autoPageSec <= 0 || this.stripMode()) {
      return;
    }
    this.autoTimerId = setTimeout(() => {
      this.autoTimerId = -1;
      if (this.autoRunning && !this.loading) {
        this.step(1);
      }
    }, this.autoPageSec * 1000);
  }

  // 在过渡页上继续前/后翻即切换章节（上一章落在末页，下一章落在首页）
  private step(delta: number): void {
    if (this.dualPageActive()) {
      this.stepDual(delta);
      return;
    }
    const ddelta = this.mode === 'rtl' ? -delta : delta;
    const base = this.flipTarget >= 0 ? this.flipTarget : this.displayIndex;
    const kind = this.cellKind(base);
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
    const target = base + ddelta;
    const cellTotal = this.pages.length + (this.showPrevTrans() ? 1 : 0) + (this.showNextTrans() ? 1 : 0);
    // 过渡页隐藏时越过首尾真实页直接切章（对齐 Mihon 无缝衔接）；
    // 过渡页显示时步进落到过渡页（上述 cellKind 分支接管后续切章）
    if (target > cellTotal - 1 || target < 0) {
      if (delta > 0 && !this.showNextTrans() && this.hasNext) {
        this.gotoChapter(true, true);
      } else if (delta < 0 && !this.showPrevTrans() && this.hasPrev) {
        this.gotoChapter(false, true);
      }
      return;
    }
    Haptics.soft();
    // 走控制器步进（自带切换动画）；不预写 displayIndex，属性变化是瞬跳
    this.flipTarget = target;
    try {
      if (ddelta > 0) {
        this.swiperCtrl.showNext();
      } else {
        this.swiperCtrl.showPrevious();
      }
    } catch (e) {
      // Swiper 未挂载：回退属性瞬跳
      this.flipTarget = -1;
      this.displayIndex = target;
      this.onSwipe(target);
    }
  }

  // 从过渡页返回本章边界页（真实进度未变，仅回到当前页）
  private backFromTransition(): void {
    const back = this.realToDisplay(this.currentReal);
    this.flipTarget = back;
    try {
      this.swiperCtrl.changeIndex(back, true);
    } catch (e) {
      // Swiper 未挂载：回退属性瞬跳
      this.flipTarget = -1;
      this.displayIndex = back;
      this.onSwipe(back);
    }
  }

  // ---- 键盘控制（外接键盘/PC）：方向键/PgUp/PgDn/空格翻页，回车呼出菜单，Escape 逐级退出 ----

  private handleReaderKey(event: KeyEvent): void {
    if (event.type !== KeyType.Down) {
      return;
    }
    // 音量键翻页（阅读体验开关）：音量上=上一页，音量下=下一页；
    // 菜单/弹层打开或加载中不接管按键，保留系统音量调节
    if (this.volumeTurn && !this.loading && this.pages.length > 0 && !this.showMenu &&
      !this.showSettings && !this.showModeSheet && !this.showOrientationSheet &&
      !this.showChapterSheet &&
      (event.keyCode === KeyCode.KEYCODE_VOLUME_UP || event.keyCode === KeyCode.KEYCODE_VOLUME_DOWN)) {
      this.keyTurn(event.keyCode === KeyCode.KEYCODE_VOLUME_UP ? -1 : 1);
      return;
    }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      // 加载中由 LoadingBackButton 的 ESC 快捷键兜底退出，避免重复 pop
      if (this.loading) {
        return;
      }
      if (this.showSettings) {
        this.showSettings = false;
      } else if (this.showChapterSheet) {
        this.showChapterSheet = false;
      } else if (this.showModeSheet) {
        this.showModeSheet = false;
      } else if (this.showOrientationSheet) {
        this.showOrientationSheet = false;
      } else if (this.showMenu) {
        this.showMenu = false;
      } else {
        this.pathStack.pop();
      }
      return;
    }
    if (event.keyCode === KeyCode.KEYCODE_ENTER) {
      if (!this.loading) {
        this.showMenu = !this.showMenu;
      }
      return;
    }
    // Home/End：跳本章首页/末页
    if (event.keyCode === KeyCode.KEYCODE_MOVE_HOME) {
      this.jumpEdge(false);
      return;
    }
    if (event.keyCode === KeyCode.KEYCODE_MOVE_END) {
      this.jumpEdge(true);
      return;
    }
    let delta = 0;
    const verticalScroll = this.mode === 'vertical' || this.stripMode();
    if (event.keyCode === KeyCode.KEYCODE_PAGE_DOWN || event.keyCode === KeyCode.KEYCODE_SPACE) {
      delta = 1;
    } else if (event.keyCode === KeyCode.KEYCODE_PAGE_UP) {
      delta = -1;
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
      delta = this.mode === 'rtl' ? -1 : 1;
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
      delta = this.mode === 'rtl' ? 1 : -1;
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      delta = verticalScroll ? 1 : 0;
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      delta = verticalScroll ? -1 : 0;
    }
    if (delta !== 0) {
      this.keyTurn(delta);
    }
  }

  // Home/End：跳本章首页/末页（复用 Slider 跳页入口，条漫滚动/其余翻页自适应）
  private jumpEdge(toEnd: boolean): void {
    if (this.loading || this.pages.length === 0 || this.showMenu ||
      this.showSettings || this.showModeSheet || this.showOrientationSheet) {
      return;
    }
    this.jumpToReal(toEnd ? this.pages.length - 1 : 0);
  }

  // 键盘翻页统一入口：条漫整屏滚动、仿真走翻页令牌、其余走 step
  //（step 内部已适配 RTL 与章节过渡页；仿真边界过渡层上继续前进进相邻章节）
  private keyTurn(delta: number): void {
    if (this.loading || this.pages.length === 0 || this.showMenu ||
      this.showSettings || this.showModeSheet || this.showOrientationSheet) {
      return;
    }
    if (this.stripMode()) {
      this.scroller.scrollBy(0, delta * (this.readerH > 0 ? this.readerH : 640));
      return;
    }
    if (this.transOverlay !== 0) {
      const next = this.transOverlay > 0;
      this.transOverlay = 0;
      if (delta > 0) {
        this.gotoChapter(next, true);
      }
      return;
    }
    if (this.useCurl()) {
      this.requestLeaf(delta);
      return;
    }
    this.step(delta);
  }

  // ---- 各阅读模式内容体（经 ReaderFilterArea 的 content 注入；@BuilderParam 传参
  // 只能调用 @Builder 方法，不能内联 UI 组件语法） ----

  private useCurl(): boolean {
    return this.pageAnim === 'curl' && !this.stripMode() && this.mode !== 'vertical' && this.pages.length > 0;
  }

  private curlDual(): boolean {
    return this.dualPageActive();
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

  // ---- 菜单（共享 ReaderChrome 骨架：顶栏+占位+底栏，样式与拆分前一致） ----

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
    if (this.navMode === 'lshape') {
      return 'lshape';
    }
    if (this.navMode === 'kindle') {
      return 'kindle';
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

  // 仿真翻页滑出边界：弹出章节过渡层（dir>0 越过末页，dir<0 越过首页）；
  // 过渡层被设置关闭且章节号连续时直接进入相邻章节（无下一章呼出菜单）
  private onCurlOverscroll(dir: number): void {
    if (this.transOverlay !== 0) {
      return;
    }
    if (dir > 0 && !this.showNextTrans()) {
      if (this.hasNext) {
        this.gotoChapter(true, true);
      } else {
        this.showMenu = true;
      }
      return;
    }
    if (dir < 0 && !this.showPrevTrans()) {
      if (this.hasPrev) {
        this.gotoChapter(false, true);
      } else {
        this.showMenu = true;
      }
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
    } else if (this.navMode === 'lshape' || this.navMode === 'kindle') {
      // L 形 / Kindle 导航热区
      const nx = x / (this.readerW > 0 ? this.readerW : 360);
      const ny = y / (this.readerH > 0 ? this.readerH : 640);
      delta = this.lNavDelta(nx, ny, this.navMode === 'kindle');
    } else {
      // “下一页”是否在左侧：默认跟随阅读模式，可被导航模式覆盖
      let nextOnLeft: boolean = this.mode === 'rtl' ||
        (this.mode === 'smart_grip' && !this.gripRight);
      if (this.navMode === 'ltr') {
        nextOnLeft = false;
      } else if (this.navMode === 'rtl') {
        nextOnLeft = true;
      }
      const edge = this.navMode === 'edge' ? 0.12 : 0.3;
      const zone = x / (this.readerW > 0 ? this.readerW : 360);
      if (zone < edge) {
        delta = nextOnLeft ? 1 : -1;
      } else if (zone > 1 - edge) {
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

  // 更多设置面板：背景色 / 显示页码 / 亮度

  private setPageAnim(v: string): void {
    if (v === this.pageAnim) {
      return;
    }
    this.pageAnim = v;
    Settings.setReaderPageAnim(v);
    this.resetAnimArrays(this.cellTotal());
  }

  // 展示单元格总数（含过渡槽与双页占位）
  private cellTotal(): number {
    const dual = this.dualPageActive();
    const lead = dual || this.showPrevTrans() ? 1 : 0;
    const tail = dual || this.showNextTrans() ? 1 : 0;
    return this.pages.length + lead + tail + this.dualExtra();
  }

  private coverAt(arr: number[], index: number): number {
    if ((this.pageAnim !== 'cover' && !this.extraAnimAllowed()) || index < 0 || index >= arr.length) {
      return 0;
    }
    return arr[index];
  }

  // 附加页面动画（堆叠/交叉）：仅单页水平模式可用
  private isExtraAnim(): boolean {
    return this.pageAnim === 'stack' || this.pageAnim === 'fade';
  }

  private extraAnimAllowed(): boolean {
    return this.isExtraAnim() && !this.dualPageActive() && this.mode !== 'vertical' &&
      this.mode !== 'webtoon' && this.mode !== 'continuous';
  }

  // 附加动画三通道（旋转角/缩放/不透明度）取值
  private rotAt(index: number): RotateOptions {
    if (!this.extraAnimAllowed() || index < 0 || index >= this.animRot.length) {
      return { x: 0, y: 1, z: 0, angle: 0 };
    }
    return { x: 0, y: 1, z: 0, angle: this.animRot[index], centerX: '50%', centerY: '50%', perspective: 900 };
  }

  private sclAt(index: number): ScaleOptions {
    if (!this.extraAnimAllowed() || index < 0 || index >= this.animScl.length) {
      return { x: 1, y: 1 };
    }
    return { x: this.animScl[index], y: this.animScl[index] };
  }

  private opaAt(index: number): number {
    if (!this.extraAnimAllowed() || index < 0 || index >= this.animOpa.length) {
      return 1;
    }
    return this.animOpa[index];
  }

  // 重置附加动画通道并按单元格数重建
  private resetAnimArrays(cellCount: number): void {
    const rot: number[] = [];
    const scl: number[] = [];
    const opa: number[] = [];
    for (let i = 0; i < cellCount; i++) {
      rot.push(0);
      scl.push(1);
      opa.push(1);
    }
    this.animRot = rot;
    this.animScl = scl;
    this.animOpa = opa;
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

  // 覆盖/附加动画共用的落位写入：位移/层级 + 旋转/缩放/不透明度
  private setAnim(i: number, x: number, y: number, z: number,
    rot: number, scl: number, opa: number): void {
    this.setCover(i, x, y, z);
    if (i < 0 || i >= this.animRot.length) {
      return;
    }
    if (this.animRot[i] !== rot) {
      this.animRot[i] = rot;
    }
    if (this.animScl[i] !== scl) {
      this.animScl[i] = scl;
    }
    if (this.animOpa[i] !== opa) {
      this.animOpa[i] = opa;
    }
  }

  // 覆盖：新页滑入盖住静止的当前页。滑动模式不改位移，沿用 Swiper 默认滚动。
  private onCoverTransition(proxy: SwiperContentTransitionProxy): void {
    if (this.extraAnimAllowed()) {
      this.onExtraAnimTransition(proxy);
      return;
    }
    if (this.pageAnim !== 'cover') {
      return;
    }
    const i = proxy.index;
    if (i < 0 || i >= this.coverX.length) {
      return;
    }
    const p = proxy.position;
    const span = proxy.mainAxisLength;
    const selected = proxy.selectedIndex;
    if (this.dualPageActive()) {
      // 按组翻页：position 含各页槽位偏移，组位移比例 = p - (i - 组起始)，
      // 前翻 move∈[-2,0]、后翻 move∈[0,2]，符号即方向
      const gs = selected - (selected % 2);
      const rel = i - gs;
      const move = p - rel;
      if (Math.abs(move) < 0.001 || Math.abs(move) >= 2 - 0.001) {
        // 起始/完成帧：恢复默认布局
        this.setCover(i, 0, 0, 0);
        return;
      }
      if (move < 0) {
        // 前翻：离场组原位固定垫底，进场组自然滑入覆盖
        if (rel === 0 || rel === 1) {
          this.setCover(i, -move * span, 0, 0);
        } else {
          this.setCover(i, 0, 0, 2);
        }
      } else {
        // 后翻：进场组固定于窗口槽垫底，离场组自然滑出揭开
        if (rel === -2 || rel === -1) {
          this.setCover(i, (2 - move) * span, 0, 0);
        } else {
          this.setCover(i, 0, 0, 2);
        }
      }
      return;
    }
    if (Math.abs(p - Math.round(p)) < 0.001) {
      this.setCover(i, 0, 0, 0);
      return;
    }
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

  // 附加页面动画转场（单页水平模式）：
  // fade=双页固定位移交叉淡化；stack=进场自然滑入、离场定点缩退
  private onExtraAnimTransition(proxy: SwiperContentTransitionProxy): void {
    const i = proxy.index;
    if (i < 0 || i >= this.coverX.length) {
      return;
    }
    const p = proxy.position;
    const selected = proxy.selectedIndex;
    if (Math.abs(p - Math.round(p)) < 0.001 || Math.abs(p) > 1.001) {
      // 起始/完成帧或非相邻页：恢复默认布局
      this.setAnim(i, 0, 0, 0, 0, 1, 1);
      return;
    }
    const span = proxy.mainAxisLength;
    const L = Math.abs(p);
    const t = 1 - L;
    const pin = -p * span;
    const anim = this.pageAnim;
    if (i === selected) {
      // 离场页
      if (anim === 'fade') {
        this.setAnim(i, pin, 0, 0, 0, 1, 1 - L);
      } else {
        this.setAnim(i, pin, 0, 0, 0, 1 - 0.15 * L, 1 - 0.4 * L);
      }
    } else if (i === selected + 1 || i === selected - 1) {
      // 进场页
      if (anim === 'fade') {
        this.setAnim(i, pin, 0, 2, 0, 1, t);
      } else {
        this.setAnim(i, 0, 0, 2, 0, 1, 1);
      }
    } else {
      this.setAnim(i, 0, 0, 0, 0, 1, 1);
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
    if (this.curlTapMode() === 'lshape' || this.curlTapMode() === 'kindle') {
      // L 形 / Kindle 导航热区（全屏归一化坐标）
      const nx = globalX / fullW;
      const ny = localY / fullH;
      const delta = this.lNavDelta(nx, ny, this.curlTapMode() === 'kindle');
      if (delta === 0) {
        this.showMenu = !this.showMenu;
      } else {
        this.requestLeaf(delta);
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

  // 过渡视图文字色：白底/纸张底深色字，灰/黑底浅色字（自动主题按系统深浅色）
  private readerTextCol(): string {
    const t = this.readerTheme === 3 ? (this.isDark ? 1 : 0) : this.readerTheme;
    return t === 0 || t === 4 ? '#16181D' : '#ECEEF2';
  }

  // 阅读页背景明暗同步给 ReaderChrome（玻璃前景色据此取高对比色）：

  private readerSubCol(): string {
    const t = this.readerTheme === 3 ? (this.isDark ? 1 : 0) : this.readerTheme;
    return t === 0 || t === 4 ? '#9916181D' : '#99ECEEF2';
  }

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
    if (this.mode === 'continuous') {
      return $r('app.string.reader_mode_continuous');
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
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function ReaderBuilder() {
  ReaderPage()
}
