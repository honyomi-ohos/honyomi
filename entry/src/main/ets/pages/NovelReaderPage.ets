import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
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
import { NovelTts } from '../common/NovelTts';
import { ReaderWindow } from '../common/ReaderWindow';
import { ReaderChapterNav, ChapterNeighbors } from '../common/ReaderChapterNav';
import { DownloadService } from '../data/DownloadService';
import { AppIconRes, AppIcon } from './components/AppIcon';
import { PickerSheet } from './components/PickerSheet';
import { EmulationFlipView } from './components/PageFlip';

// 屏幕方向的可选值（与方向选择 sheet 选项一一对应）
const NOVEL_ORIENTATIONS: string[] = ['free', 'portrait', 'landscape', 'lock_portrait', 'lock_landscape'];
const NOVEL_ORIENTATION_ICONS: string[] =
  ['screen_rotation', 'stay_current_portrait', 'stay_current_landscape', 'screen_lock_portrait', 'screen_lock_landscape'];
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

// 章节正文块：文本段或插图（插件正文里的 <img> 解析而来）
interface NovelBlock {
  isImage: boolean;
  // 文本段内容；图片块的图片 URL
  text: string;
  // 文本段在听书段落序列中的序号（图片块为 -1）
  ttsIdx: number;
}

// 翻页模式的单页：普通页为段落集合，插图页 imageUrl 非空、独占整页
interface NovelPage {
  texts: string[];
  imageUrl: string;
}

// 阅读模式的可选值（与模式选择 sheet 选项一一对应）
const NOVEL_MODES: string[] = ['scroll', 'paged', 'paged_rtl', 'double'];
const NOVEL_MODE_ICONS: string[] = ['reader_scroll', 'reader_ltr', 'reader_rtl', 'reader_double'];
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
  // 底栏设置面板（画面/文本/听书）共用一个 bindSheet：同一节点链式绑定多个 bindSheet 时只有最后一个生效，
  // 前面的会被立即关闭，故用单个 isShow + panelKind 切换内容
  @State showPanelSheet: boolean = false;
  @State panelKind: string = '';
  @State brightLv: number = 0;
  // 听书（系统 TTS）：播放中 / 当前朗读段 / 语速面板
  @State ttsPlaying: boolean = false;
  @State ttsParaIdx: number = -1;
  @State ttsSpeed: number = 1;
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
  private contW: number = 0;
  private contH: number = 0;
  private pageW: number = 0;
  private pageH: number = 0;
  private pagSig: string = '';

  private screenDensity: number = 2;
  // 段落 → 翻页页码映射（buildPages 填充，听书跟随翻页用）
  private paraPage: number[] = [];
  // 听书自动续播下一章标记
  private ttsResume: boolean = false;
  // 滚动模式视口宽度（听书跟随滚动测高用）
  private scrollW: number = 0;
  // 滚动模式段落纵向偏移缓存（签名变化时重算）
  private paraOffsets: number[] = [];
  private paraOffSig: string = '';
  // html 章节解析出的「文本段 + 插图」块序列（hasImages 时有效）
  private blocks: NovelBlock[] = [];
  // pushTextBlocks 递增的文本段序号（解析一章期间有效）
  private blockTextSeq: number = 0;

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
    this.ttsSpeed = Settings.getNovelTtsSpeed();
    this.applyOrientation();
    this.applyBrightness();
    this.wireTtsEvents();
  }

  aboutToDisappear(): void {
    NovelTts.stop();
    NovelTts.resetEvents();
    this.persist();
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
    NovelTts.stop();
    this.ttsPlaying = false;
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
      const chapter = await ChapterRepo.getById(this.chapterId);
      if (chapter === undefined) {
        Util.toastRes(this.getUIContext(), $r('app.string.reader_chapter_not_found'));
        this.pathStack.pop();
        return;
      }
      this.chapter = chapter;
      this.mangaId = chapter.mangaId;
      this.permille = chapter.lastPageRead > 0 && chapter.lastPageRead <= 1000 ? chapter.lastPageRead : 0;
      const manga = await MangaRepo.get(chapter.mangaId);
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
          throw new Error('源不可用');
        }
        text = await source.getChapterText(chapter.url);
      }
      if (text === '') {
        throw new Error('章节没有正文');
      }
      this.html = NovelReaderPage.looksLikeHtml(text);
      this.body = text;
      this.parseChapterBlocks();
      await this.loadNeighbors();
      await HistoryRepo.upsert(chapter.mangaId, chapter.id, this.permille);
      ReadingStatsRepo.begin(chapter.mangaId, chapter.id);
    } catch (e) {
      this.ttsResume = false;
      Util.toastRes(this.getUIContext(), $r('app.string.reader_load_failed'), [(e as Error).message]);
    }
    this.loading = false;
    this.ensurePaginated();
    // 听书自动续播：上一章播完自动加载下一章后从头继续朗读
    if (this.ttsResume) {
      this.ttsResume = false;
      this.startTts(0);
    }
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

  private persist(): void {
    if (this.chapterId <= 0) {
      return;
    }
    ChapterRepo.setLastPageRead(this.chapterId, this.permille).catch(() => {
    });
    HistoryRepo.upsert(this.mangaId, this.chapterId, this.permille).catch(() => {
    });
    if (this.permille >= 950) {
      ChapterRepo.setRead(this.chapterId, true).catch(() => {
      });
    }
  }

  private openChapter(id: number): void {
    if (id <= 0) {
      return;
    }
    this.persist();
    this.chapterId = id;
    this.loadChapter();
  }

  // ---- 听书（系统 TTS）----

  // 接管 NovelTts 事件：跟随滚动/翻页、播完自动下一章、错误提示
  private wireTtsEvents(): void {
    NovelTts.events.onParaStart = (idx: number): void => {
      this.ttsParaIdx = idx;
      this.followTtsPara(idx);
    };
    NovelTts.events.onAllDone = (): void => {
      this.ttsPlaying = false;
      this.ttsParaIdx = -1;
      if (this.nextId > 0) {
        this.ttsResume = true;
        this.openChapter(this.nextId);
      } else {
        Util.toastRes(this.getUIContext(), $r('app.string.novel_tts_finish'));
      }
    };
    NovelTts.events.onError = (message: string): void => {
      this.ttsPlaying = false;
      this.ttsParaIdx = -1;
      Util.toastRes(this.getUIContext(), $r('app.string.novel_tts_error'), [message]);
    };
  }

  // 听书文本段落：html 章节剥除标签，纯文本按行拆分
  private ttsParas(): string[] {
    if (this.hasImages) {
      const out: string[] = [];
      for (const block of this.blocks) {
        if (!block.isImage) {
          out.push(block.text);
        }
      }
      return out;
    }
    if (this.html) {
      const stripped = this.body
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<\/p>/gi, '\n')
        .replace(/<[^>]+>/g, '')
        .replace(/&nbsp;/g, ' ')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&amp;/g, '&');
      return stripped.split('\n');
    }
    return this.body.split('\n');
  }

  // 按开头若干段采样推断语种（ASCII 过半判英文）
  private ttsLang(paras: string[]): string {
    let ascii = 0;
    let total = 0;
    const sampleCount = Math.min(paras.length, 40);
    for (let i = 0; i < sampleCount; i++) {
      const s = paras[i];
      for (let j = 0; j < s.length; j++) {
        const c = s.charCodeAt(j);
        if (c > 32) {
          total++;
          if (c < 128) {
            ascii++;
          }
        }
      }
    }
    if (total > 0 && ascii * 2 > total) {
      return 'en-US';
    }
    return 'zh-CN';
  }

  // 起播段落：翻页/双页取当前页首段；滚动/html 按进度比例估算
  private currentTtsPara(): number {
    const paras = this.ttsParas();
    if (paras.length === 0) {
      return 0;
    }
    if ((!this.html || this.hasImages) && this.mode !== 'scroll' && this.paraPage.length === paras.length) {
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
    const ok = await NovelTts.start(paras, fromPara, this.ttsLang(paras),
      Util.hostAbilityContext(this.getUIContext()));
    if (!ok) {
      this.ttsPlaying = false;
      this.ttsParaIdx = -1;
      Util.toastRes(this.getUIContext(), $r('app.string.novel_tts_error'), ['engine']);
    }
  }

  private toggleTts(): void {
    if (NovelTts.isPlaying()) {
      NovelTts.stop();
      this.ttsPlaying = false;
      this.ttsParaIdx = -1;
      return;
    }
    this.startTts(this.currentTtsPara());
  }

  private setTtsSpeed(v: number): void {
    this.ttsSpeed = v;
    Settings.setNovelTtsSpeed(v);
    // 播放中改语速：从当前朗读段以新语速续播
    if (NovelTts.isPlaying()) {
      const from = this.ttsParaIdx >= 0 ? this.ttsParaIdx : NovelTts.currentPara();
      NovelTts.stop();
      this.startTts(from);
    }
  }

  // 跟随朗读进度：滚动模式滚到对应段落，翻页/双页翻到对应页
  private followTtsPara(idx: number): void {
    if (this.html && !this.hasImages) {
      return;
    }
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

  private static looksLikeHtml(text: string): boolean {
    const head = text.substring(0, 240).toLowerCase();
    return head.indexOf('<p') >= 0 || head.indexOf('<br') >= 0 || head.indexOf('<div') >= 0 ||
      head.indexOf('<html') >= 0;
  }

  // 解析 html 章节为「文本段 + 插图」块序列：正文以 <img> 标记插图，
  // 滚动模式内嵌渲染、翻页模式插图独占一页；无插图时保持原有渲染路径
  private parseChapterBlocks(): void {
    this.blocks = [];
    this.hasImages = false;
    this.blockTextSeq = 0;
    if (!this.html) {
      return;
    }
    const imgRe = /<img\b[^>]*>/gi;
    let idx = 0;
    let match = imgRe.exec(this.body);
    while (match !== null) {
      this.pushTextBlocks(this.body.substring(idx, match.index));
      const src = NovelReaderPage.imgSrcOf(match[0]);
      if (src !== '') {
        const image: NovelBlock = { isImage: true, text: src, ttsIdx: -1 };
        this.blocks.push(image);
        this.hasImages = true;
      }
      idx = match.index + match[0].length;
      match = imgRe.exec(this.body);
    }
    this.pushTextBlocks(this.body.substring(idx));
  }

  // 把 <img> 之间的 html 片段剥成纯文本段落，追加为文本块（跳过空段）
  private pushTextBlocks(segment: string): void {
    const text = segment
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n')
      .replace(/<\/div>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&amp;/g, '&');
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line === '') {
        continue;
      }
      const block: NovelBlock = { isImage: false, text: line, ttsIdx: this.blockTextSeq };
      this.blocks.push(block);
      this.blockTextSeq += 1;
    }
  }

  // 提取 <img> 标签的 src 属性
  private static imgSrcOf(tag: string): string {
    const match = /\ssrc\s*=\s*["']([^"']+)["']/i.exec(tag);
    if (match === null) {
      return '';
    }
    return match[1].trim();
  }

  // 纯文本章节的块视图：每行一个文本块（与 body.split('\n') 等价）
  private plainBlocks(): NovelBlock[] {
    const paras = this.body.split('\n');
    const out: NovelBlock[] = [];
    for (let i = 0; i < paras.length; i++) {
      const block: NovelBlock = { isImage: false, text: paras[i], ttsIdx: i };
      out.push(block);
    }
    return out;
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
      // 双页：左右各半，扣除左右边距与中缝 25（Divider 两侧 margin 12 + 1 线宽）
      this.pageW = Math.floor((this.contW - this.pageMargin * 2 - 25) / 2);
    } else {
      this.pageW = Math.floor(this.contW - this.pageMargin * 2);
    }
    this.pageH = Math.floor(this.contH - (this.statusBarH + 8) - (this.navBarH + 8));
  }

  // 分页参数（正文/模式/字号/行距/段距/页面尺寸）变化时重新分页，并按千分比恢复到原位置附近
  private ensurePaginated(): void {
    if (this.loading || this.body === '' || (this.html && !this.hasImages) || this.mode === 'scroll') {
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
    const pages = this.buildPages();
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
    this.transX = NovelReaderPage.zeros(screenCount);
    this.transAngle = NovelReaderPage.zeros(screenCount);
    this.transZ = NovelReaderPage.zeros(screenCount);
    this.transAngleL = NovelReaderPage.zeros(screenCount);
    this.transAngleR = NovelReaderPage.zeros(screenCount);
    this.halfTilt = 0;
    this.pageIdx = screenIdx;
    try {
      this.swiperCtrl.changeIndex(screenIdx, false);
    } catch (e) {
      // Swiper 尚未挂载时忽略，首次渲染由 .index() 指定
    }
  }

  private static zeros(n: number): number[] {
    const arr: number[] = [];
    for (let i = 0; i < n; i++) {
      arr.push(0);
    }
    return arr;
  }

  // 按块贪心装页（段间计入 paraSpacing，与渲染端 Column({space}) 一致）；超长段落按测量二分切分；
  // 插图块独占一页（imageUrl 非空）。同时记录 paraPage[i]：第 i 个文本段所在的页码（听书跟随翻页用）
  private buildPages(): NovelPage[] {
    const pages: NovelPage[] = [];
    const paraPage: number[] = [];
    const maxH = this.pageH;
    const width = this.pageW;
    const gap = this.paraSpacing;
    const blocks: NovelBlock[] = this.hasImages ? this.blocks : this.plainBlocks();
    let current: string[] = [];
    let used = 0;
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      if (block.isImage) {
        // 插图：收尾当前文本页，插图独占新页
        if (current.length > 0) {
          pages.push({ texts: current, imageUrl: '' });
          current = [];
          used = 0;
        }
        pages.push({ texts: [], imageUrl: block.text });
        continue;
      }
      let para = block.text;
      if (para === '') {
        para = ' ';
      }
      const h = this.measureTextVp(para, width);
      if (h <= maxH) {
        const extra = current.length > 0 ? gap : 0;
        if (used + extra + h <= maxH) {
          paraPage[block.ttsIdx] = pages.length;
          current.push(para);
          used += extra + h;
          continue;
        }
        // 当前页放不下：整段放入新页
        if (current.length > 0) {
          pages.push({ texts: current, imageUrl: '' });
        }
        paraPage[block.ttsIdx] = pages.length;
        current = [para];
        used = h;
        continue;
      }
      // 整段超过一页：按字符切分
      if (current.length > 0) {
        pages.push({ texts: current, imageUrl: '' });
        current = [];
        used = 0;
      }
      paraPage[block.ttsIdx] = pages.length;
      let rest = para;
      // 每页可容纳字符数的先验（0=未知）：由上一次切点更新；
      // 剩余不超过一页容量时才整段测量判断能否收尾，避免反复测量大段文本
      let cap = 0;
      while (rest.length > 0) {
        if (rest.length <= cap) {
          const hRest = this.measureTextVp(rest, width);
          if (hRest <= maxH) {
            current.push(rest);
            used = hRest;
            break;
          }
        }
        const fit = this.fitPrefix(rest, width, maxH, cap);
        if (fit <= 0) {
          // 页高不足一行：整段放入避免死循环
          current.push(rest);
          used = maxH;
          break;
        }
        if (fit >= rest.length) {
          // 整个剩余部分一页内放得下：并入当前页，继续贪心装后续段落
          current.push(rest);
          used = this.measureTextVp(rest, width);
          break;
        }
        pages.push({ texts: [rest.substring(0, fit)], imageUrl: '' });
        rest = rest.substring(fit);
        cap = fit;
      }
    }
    if (current.length > 0) {
      pages.push({ texts: current, imageUrl: '' });
    }
    this.paraPage = paraPage;
    return pages;
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

  // 在超长段落中找切点：capHint 为上一页的字符容量先验（0=未知）。
  // 先用实测行数按比例收敛切点，页面基本排满（剩余不足 0.08 行）即接受，
  // 省去精确二分的十余次测量；未收敛时才在剩余区间精确二分兜底，结果与全量二分一致
  private fitPrefix(text: string, width: number, maxH: number, capHint: number): number {
    const len = text.length;
    if (len <= 0) {
      return 0;
    }
    const linesPerPage = maxH / this.lineHeight;
    let best = 0;
    let hiFail = len + 1;
    let k = capHint > 0 ? Math.max(1, Math.min(len, Math.round(capHint))) : Math.ceil(len / 2);
    let accepted = false;
    for (let iter = 0; iter < 4 && !accepted && k > best && k < hiFail; iter++) {
      const h = this.measureTextVp(text.substring(0, k), width);
      if (h <= maxH) {
        best = k;
        if (k >= len) {
          break;
        }
        const linesUsed = Math.max(1, h / this.lineHeight);
        const linesLeft = linesPerPage - linesUsed;
        if (linesLeft < 0.08) {
          accepted = true;
          break;
        }
        // 按剩余行数与每行字符数估算可再容纳的字符量
        let nk = k + Math.max(1, Math.round(linesLeft * (k / linesUsed)));
        if (nk >= hiFail) {
          nk = hiFail - 1;
        }
        if (nk <= best) {
          break;
        }
        k = nk;
      } else {
        hiFail = k;
        const linesUsed = Math.max(1, h / this.lineHeight);
        const over = linesUsed - linesPerPage;
        const nk = k - Math.max(1, Math.round(over * (k / linesUsed)));
        if (nk <= best) {
          break;
        }
        k = nk;
      }
    }
    if (!accepted) {
      // 未整页收敛：剩余区间精确二分，保证与全量二分结果一致
      while (best + 1 < hiFail) {
        const mid = Math.floor((best + hiFail) / 2);
        if (this.measureTextVp(text.substring(0, mid), width) <= maxH) {
          best = mid;
        } else {
          hiFail = mid;
        }
      }
    }
    // 避免切开代理对（emoji 等）
    if (best > 0 && best < text.length) {
      const code = text.charCodeAt(best - 1);
      if (code >= 0xD800 && code <= 0xDBFF) {
        best -= 1;
      }
    }
    return best;
  }

  private pageAt(idx: number): NovelPage {
    if (idx >= 0 && idx < this.pages.length) {
      return this.pages[idx];
    }
    return { texts: [], imageUrl: '' };
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
    } else if (which === 'display' || which === 'text' || which === 'tts') {
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
    if (this.mode === 'scroll' || (this.html && !this.hasImages)) {
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
    const next = dir > 0 ? Math.abs(this.leafTurn) + 1 : -(Math.abs(this.leafTurn) + 1);
    this.leafTurn = next === 0 ? dir : next;
  }

  // onLeaf=false 时 localX 属于左侧静止页；true 时属于右侧翻动页（中缝 25vp）
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
    const half = (inner - 25) / 2;
    const globalX = onLeaf ? half + 25 + localX : localX;
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
      .width(25)
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
    if (this.pageAt(pIdx).imageUrl !== '') {
      Image(this.pageAt(pIdx).imageUrl)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
    } else if (this.paraSpacing > 0) {
      Column({ space: this.paraSpacing }) {
        ForEach(this.pageAt(pIdx).texts, (para: string, i: number) => {
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
      Text(this.pageAt(pIdx).texts.join('\n'))
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
        .width(25)
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

  // 滚动模式正文：含插图 html 按块渲染（文本段 + 内嵌插图）；纯 html 用 RichText；
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
    } else if (this.html) {
      RichText(this.body)
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

  // 阅读模式 chip（滚动 / 单页式从左到右 / 单页式从右到左 / 双页）
  @Builder
  modeChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.mode === value ? '#FFFFFF' : this.pal.text)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.mode === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.setMode(value);
      })
  }

  // 翻页动画 chip（仿真 / 滑动 / 覆盖）
  @Builder
  animChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.animMode === value ? '#FFFFFF' : this.pal.text)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.animMode === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.setAnimMode(value);
      })
  }

  // 配色 chip（自动 / 浅色 / 深色）
  @Builder
  schemeChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.colorScheme === value ? '#FFFFFF' : this.pal.text)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.colorScheme === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.colorScheme = value;
        Settings.setNovelColorScheme(value);
      })
  }

  // 字体 chip（默认 / 宋体 / 黑体 / 等宽）
  @Builder
  fontChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.fontFamily === value ? '#FFFFFF' : this.pal.text)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.fontFamily === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.fontFamily = value;
        Settings.setNovelFontFamily(value);
        this.ensurePaginated();
      })
  }

  // 背景 chip（与漫画阅读器共用 readerTheme：自动/白/灰/黑）
  @Builder
  themeChip(label: ResourceStr, value: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.readerTheme === value ? '#FFFFFF' : this.pal.text)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.readerTheme === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.readerTheme = value;
        Settings.setReaderTheme(value);
      })
  }

  // 设置面板滑杆行：label 在上、Slider + 数值在下（对齐面板内其他分组的排版）
  @Builder
  novelSliderRow(label: ResourceStr, value: number, min: number, max: number,
    onChange: (value: number, done: boolean) => void) {
    Column({ space: 8 }) {
      Text(label)
        .fontSize(13)
        .fontColor(this.pal.sub)
        .width('100%')
      Row() {
        Slider({ value: value, min: min, max: max, step: 1 })
          .layoutWeight(1)
          .blockColor(this.pal.primary)
          .selectedColor(this.pal.primary)
          .trackColor(this.pal.divider)
          .onChange((sliderValue: number, mode: SliderChangeMode) => {
            onChange(Math.round(sliderValue),
              mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          })
        Text(`${value}`)
          .fontSize(13)
          .fontColor(this.pal.text)
          .width(44)
          .textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 6 })
  }

  @Builder
  orientationSheetBuilder() {
    PickerSheet({
      options: [$r('app.string.reader_orientation_free'), $r('app.string.reader_orientation_portrait'),
        $r('app.string.reader_orientation_landscape'), $r('app.string.reader_orientation_lock_portrait'),
        $r('app.string.reader_orientation_lock_landscape')],
      icons: NOVEL_ORIENTATION_ICONS,
      selectedIndex: NOVEL_ORIENTATIONS.indexOf(this.orientation),
      onPick: (index: number): void => {
        this.showOrientationSheet = false;
        const v: string | undefined = NOVEL_ORIENTATIONS[index];
        if (v !== undefined) {
          this.orientation = v;
          Settings.setNovelOrientation(v);
          this.applyOrientation();
        }
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
    Column({ space: 0 }) {
      PickerSheet({
        options: [$r('app.string.novel_mode_scroll'), $r('app.string.novel_mode_single_ltr'),
          $r('app.string.novel_mode_single_rtl'), $r('app.string.novel_mode_double')],
        icons: NOVEL_MODE_ICONS,
        selectedIndex: NOVEL_MODES.indexOf(this.mode),
        onPick: (index: number): void => {
          this.showModeSheet = false;
          const v: string | undefined = NOVEL_MODES[index];
          if (v !== undefined) {
            this.setMode(v);
          }
        }
      })

      Divider().color(this.pal.divider)

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
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      Column().height(16)
    }
    .width('100%')
  }

  // 底栏设置面板标题（画面 / 文本 / 听书共用一个 bindSheet）
  private panelTitleRes(): ResourceStr {
    if (this.panelKind === 'text') {
      return $r('app.string.novel_tab_text');
    }
    if (this.panelKind === 'tts') {
      return $r('app.string.novel_tts');
    }
    return $r('app.string.novel_tab_display');
  }

  // 底栏设置面板内容：按 panelKind 切换（同一节点只允许一个生效的 bindSheet，多绑会互相顶掉）
  @Builder
  panelSheetBuilder() {
    if (this.panelKind === 'display') {
      this.displaySheetBuilder()
    } else if (this.panelKind === 'text') {
      this.textSheetBuilder()
    } else {
      this.ttsSheetBuilder()
    }
  }

  // 画面：亮度 / 配色 / 背景
  @Builder
  displaySheetBuilder() {
    Column({ space: 0 }) {
      Column({ space: 8 }) {
        Text($r('app.string.reader_brightness'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Row() {
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
            .fontSize(13)
            .fontColor(this.pal.text)
            .width(52)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      Divider().color(this.pal.divider)

      Column({ space: 8 }) {
        Text($r('app.string.novel_color_scheme'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          this.schemeChip($r('app.string.reader_auto'), 'auto')
          this.schemeChip($r('app.string.novel_color_light'), 'light')
          this.schemeChip($r('app.string.novel_color_dark'), 'dark')
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      Divider().color(this.pal.divider)

      Column({ space: 8 }) {
        Text($r('app.string.reader_background'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          this.themeChip($r('app.string.reader_theme_auto'), 3)
          this.themeChip($r('app.string.reader_theme_white'), 0)
          this.themeChip($r('app.string.reader_theme_gray'), 2)
          this.themeChip($r('app.string.reader_theme_black'), 1)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      Column().height(16)
    }
    .width('100%')
  }

  // 文本设置：字号 / 边距 / 段间距 / 行间距 / 字体
  @Builder
  textSheetBuilder() {
    Column({ space: 0 }) {
      this.novelSliderRow($r('app.string.novel_font_size'), this.fontSize, 14, 32,
        (value: number, done: boolean): void => {
          this.fontSize = value;
          if (done) {
            Settings.setNovelFontSize(value);
          }
          this.ensurePaginated();
        })

      Divider().color(this.pal.divider)

      this.novelSliderRow($r('app.string.novel_margin'), this.pageMargin, 8, 48,
        (value: number, done: boolean): void => {
          this.pageMargin = value;
          if (done) {
            Settings.setNovelMargin(value);
          }
          this.ensurePaginated();
        })

      Divider().color(this.pal.divider)

      this.novelSliderRow($r('app.string.novel_paragraph_spacing'), this.paraSpacing, 0, 28,
        (value: number, done: boolean): void => {
          this.paraSpacing = value;
          if (done) {
            Settings.setNovelParagraphSpacing(value);
          }
          this.ensurePaginated();
        })

      Divider().color(this.pal.divider)

      this.novelSliderRow($r('app.string.novel_line_height'), this.lineHeight, 20, 56,
        (value: number, done: boolean): void => {
          this.lineHeight = value;
          if (done) {
            Settings.setNovelLineHeight(value);
          }
          this.ensurePaginated();
        })

      Divider().color(this.pal.divider)

      Column({ space: 8 }) {
        Text($r('app.string.novel_font_family'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          this.fontChip($r('app.string.novel_font_default'), 'default')
          this.fontChip($r('app.string.novel_font_serif'), 'serif')
          this.fontChip($r('app.string.novel_font_sans'), 'sans')
          this.fontChip($r('app.string.novel_font_mono'), 'mono')
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      Column().height(16)
    }
    .width('100%')
  }

  // 听书：播放/停止 + 语速
  @Builder
  ttsSheetBuilder() {
    Column({ space: 0 }) {
      Button(this.ttsPlaying ? $r('app.string.novel_tts_stop') : $r('app.string.novel_tts_start'))
        .fontSize(14)
        .fontColor('#FFFFFF')
        .type(ButtonType.Capsule)
        .backgroundColor(this.ttsPlaying ? '#8A343434' : this.pal.primary)
        .height(40)
        .padding({ left: 28, right: 28 })
        .margin({ top: 16 })
        .onClick(() => {
          this.toggleTts();
        })

      Divider()
        .color(this.pal.divider)
        .margin({ top: 16 })

      Column({ space: 8 }) {
        Text($r('app.string.novel_tts_speed'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          this.ttsSpeedChip('0.5x', 0.5)
          this.ttsSpeedChip('0.75x', 0.75)
          this.ttsSpeedChip('1x', 1)
          this.ttsSpeedChip('1.25x', 1.25)
          this.ttsSpeedChip('1.5x', 1.5)
          this.ttsSpeedChip('2x', 2)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      Column().height(16)
    }
    .width('100%')
  }

  // 语速 chip（0.5x - 2x，播放中切换立即生效）
  @Builder
  ttsSpeedChip(label: string, value: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.ttsSpeed === value ? '#FFFFFF' : this.pal.text)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.ttsSpeed === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.setTtsSpeed(value);
      })
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
        } else if (this.mode === 'scroll' || (this.html && !this.hasImages)) {
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

        // 进度/页码指示（菜单收起时）
        if (!this.showMenu && !this.loading && this.body !== '' && this.showPageNumber &&
          this.indicatorText() !== '') {
          Text(this.indicatorText())
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor('#66000000')
            .margin({ left: 16, top: 16, right: 16, bottom: this.navBarH + 16 })
        }

        // 菜单：顶栏 + 点击关闭占位 + 底栏（章节导航行 + 设置行）
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
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 4, right: 16, top: this.statusBarH + 10, bottom: 10 })
            .backgroundColor('#CC000000')
            // 对齐漫画阅读器：顶栏从屏幕上方滑入/滑出 + 渐隐
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
                if (this.anySheetOpen()) {
                  this.dismissSheets();
                  return;
                }
                this.showMenu = false;
              })

            // 底栏
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
                .opacity(this.prevId > 0 ? 1 : 0.4)
                .onClick(() => {
                  if (this.prevId > 0) {
                    this.openChapter(this.prevId);
                  }
                })

                // 进度胶囊：滚动=百分比 Slider，翻页/双页=页码 Slider
                if (this.mode === 'scroll' || (this.html && !this.hasImages)) {
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
                  Row() {
                    Text(`${this.pagedSliderPos()}`)
                      .fontSize(13)
                      .fontColor('#FFFFFF')
                      .width(24)
                      .textAlign(TextAlign.End)
                    Slider({
                      value: this.pagedSliderPos(),
                      min: 1,
                      max: this.screenIdxs.length > 1 ? this.screenIdxs.length : 2,
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
                          this.jumpScreen(this.pagedScreenFromSlider(Math.round(value)));
                        }
                      })
                    Text(`${this.screenIdxs.length}`)
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
                .opacity(this.nextId > 0 ? 1 : 0.4)
                .onClick(() => {
                  if (this.nextId > 0) {
                    this.openChapter(this.nextId);
                  }
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16 })

              // 设置行：阅读模式 / 屏幕方向 / 画面 / 文本设置（对齐漫画阅读器：多个入口图标）
              Row() {
                Column() {
                  Image(AppIconRes.get(this.novelModeIcon()))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.openSheet('mode');
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
                  this.openSheet('orientation');
                })

                Column() {
                  Image(AppIconRes.get('palette'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.openSheet('display');
                })

                Column() {
                  Image(AppIconRes.get('format_size'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.openSheet('text');
                })

                // 听书（系统 TTS）
                Column() {
                  Image(AppIconRes.get(this.ttsPlaying ? 'pause' : 'playlist_play'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.openSheet('tts');
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
            // 对齐漫画阅读器：底栏从屏幕下方滑入/滑出 + 渐隐
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
