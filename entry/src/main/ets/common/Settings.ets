import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window, UIContext } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme, ThemePalette } from './Theme';
import { AppKeys } from './AppKeys';

const DOMAIN = 0x0000;
const TAG = 'Settings';

// 轻量设置存储（阅读/主题/书架/阅读器/浏览/全局开关等）
export class Settings {
  private static store: preferences.Preferences | undefined = undefined;
  private static appCtx: common.UIAbilityContext | undefined = undefined;
  // flush 防抖定时器（500ms 批量落盘）
  private static flushTimer: number = -1;

  static init(context: common.UIAbilityContext): void {
    Settings.appCtx = context;
    if (Settings.store === undefined) {
      const options: preferences.Options = { name: 'honyomi_settings' };
      try {
        Settings.store = preferences.getPreferencesSync(context, options);
      } catch (_e) {
      }
    }
  }

  // 供无 context 入参的工具层解析资源字符串（Util.timeAgo 等）
  static appContext(): common.UIAbilityContext | undefined {
    return Settings.appCtx;
  }

  // 取值后 typeof 校验：跨版本类型变更时回退默认值，避免静默返回错误类型
  private static getStr(key: string, def: string): string {
    if (Settings.store === undefined) {
      return def;
    }
    try {
      const v = Settings.store.getSync(key, def);
      return typeof v === 'string' ? v as string : def;
    } catch (e) {
      return def;
    }
  }

  // 写入保持 putSync（读己之写）+ 500ms 防抖批量 flush（高频写场景消除 I/O 放大）
  private static setStr(key: string, value: string): void {
    if (Settings.store === undefined) {
      return;
    }
    try {
      Settings.store.putSync(key, value);
    } catch (_e) {
    }
    Settings.scheduleFlush();
  }

  private static getBool(key: string, def: boolean): boolean {
    if (Settings.store === undefined) {
      return def;
    }
    try {
      const v = Settings.store.getSync(key, def);
      return typeof v === 'boolean' ? v as boolean : def;
    } catch (e) {
      return def;
    }
  }

  private static setBool(key: string, value: boolean): void {
    if (Settings.store === undefined) {
      return;
    }
    try {
      Settings.store.putSync(key, value);
    } catch (_e) {
    }
    Settings.scheduleFlush();
  }

  private static getNum(key: string, def: number): number {
    if (Settings.store === undefined) {
      return def;
    }
    try {
      const v = Settings.store.getSync(key, def);
      return typeof v === 'number' ? v as number : def;
    } catch (e) {
      return def;
    }
  }

  private static setNum(key: string, value: number): void {
    if (Settings.store === undefined) {
      return;
    }
    try {
      Settings.store.putSync(key, value);
    } catch (_e) {
    }
    Settings.scheduleFlush();
  }

  // 防抖批量落盘：500ms 内的连续写只触发一次 flush
  private static scheduleFlush(): void {
    if (Settings.flushTimer !== -1) {
      clearTimeout(Settings.flushTimer);
    }
    Settings.flushTimer = setTimeout((): void => {
      Settings.flushTimer = -1;
      if (Settings.store !== undefined) {
        // flush() 返回 Promise：必须挂 catch，否则异步落盘失败成为未处理 rejection
        Settings.store.flush().catch((e: Object): void => {
          hilog.warn(DOMAIN, TAG, 'debounced settings flush failed: %{public}s', `${e}`);
        });
      }
    }, 500);
  }

  // 立即 flush 并取消防抖定时器（应用退后台/销毁时调用）
  static flushNow(): void {
    if (Settings.flushTimer !== -1) {
      clearTimeout(Settings.flushTimer);
      Settings.flushTimer = -1;
    }
    if (Settings.store !== undefined) {
      try {
        // 同步 try/catch 只能捕获 flush() 同步抛错；Promise 化的落盘失败需 catch 兜底
        Settings.store.flush().catch((e: Object): void => {
          hilog.warn(DOMAIN, TAG, 'settings flushNow failed: %{public}s', `${e}`);
        });
      } catch (_e) {
      }
    }
  }

  // ---- 既有键 ----
  static getReaderMode(): string {
    return Settings.getStr('readerMode', 'ltr');
  }

  static setReaderMode(mode: string): void {
    Settings.setStr('readerMode', mode);
  }

  static getNovelFontSize(): number {
    const n = Settings.getNum('novelFontSize', 18);
    return n >= 14 && n <= 32 ? n : 18;
  }

  static setNovelFontSize(v: number): void {
    Settings.setNum('novelFontSize', v);
  }

  static getNovelLineHeight(): number {
    const n = Settings.getNum('novelLineHeight', 32);
    return n >= 20 && n <= 56 ? n : 32;
  }

  static setNovelLineHeight(v: number): void {
    Settings.setNum('novelLineHeight', v);
  }

  // 小说阅读模式：scroll（滚动）| paged（单页式从左到右）| paged_rtl（单页式从右到左）| double（双页）
  static getNovelReaderMode(): string {
    const raw = Settings.getStr('novelReaderMode', 'scroll');
    if (raw === 'paged' || raw === 'paged_rtl' || raw === 'double') {
      return raw;
    }
    return 'scroll';
  }

  static setNovelReaderMode(v: string): void {
    Settings.setStr('novelReaderMode', v);
  }

  // 小说翻页动画（翻页/双页模式）：curl（仿真）| slide（滑动）| cover（覆盖）
  static getNovelPageAnim(): string {
    const raw = Settings.getStr('novelPageAnim', 'slide');
    if (raw === 'curl' || raw === 'cover') {
      return raw;
    }
    return 'slide';
  }

  static setNovelPageAnim(v: string): void {
    Settings.setStr('novelPageAnim', v);
  }

  // 小说阅读器屏幕方向：free | portrait | landscape | lock_portrait | lock_landscape
  static getNovelOrientation(): string {
    return Settings.getStr('novelOrientation', 'free');
  }

  static setNovelOrientation(v: string): void {
    Settings.setStr('novelOrientation', v);
  }

  // 小说文字配色：auto（跟随背景）| light（浅色文字）| dark（深色文字）
  static getNovelColorScheme(): string {
    const raw = Settings.getStr('novelColorScheme', 'auto');
    if (raw === 'light' || raw === 'dark') {
      return raw;
    }
    return 'auto';
  }

  static setNovelColorScheme(v: string): void {
    Settings.setStr('novelColorScheme', v);
  }

  // 小说正文左右边距（vp）
  static getNovelMargin(): number {
    const n = Settings.getNum('novelMargin', 20);
    return n >= 8 && n <= 48 ? n : 20;
  }

  static setNovelMargin(v: number): void {
    Settings.setNum('novelMargin', v);
  }

  // 小说正文字体：default | serif（宋体）| sans（黑体）| mono（等宽）
  static getNovelFontFamily(): string {
    const raw = Settings.getStr('novelFontFamily', 'default');
    if (raw === 'serif' || raw === 'sans' || raw === 'mono') {
      return raw;
    }
    return 'default';
  }

  static setNovelFontFamily(v: string): void {
    Settings.setStr('novelFontFamily', v);
  }

  // 小说段间距（vp）
  static getNovelParagraphSpacing(): number {
    const n = Settings.getNum('novelParagraphSpacing', 0);
    return n >= 0 && n <= 28 ? n : 0;
  }

  static setNovelParagraphSpacing(v: number): void {
    Settings.setNum('novelParagraphSpacing', v);
  }

  // 听书语速（0.5 - 2.0，默认 1.0）
  static getNovelTtsSpeed(): number {
    const n = Settings.getNum('novelTtsSpeed', 1);
    return n >= 0.5 && n <= 2 ? n : 1;
  }

  static setNovelTtsSpeed(v: number): void {
    Settings.setNum('novelTtsSpeed', v);
  }

  // 书架类型筛选：all | manga | novel | video
  static getLibraryContentFilter(): string {
    const raw = Settings.getStr('libContentFilter', 'all');
    if (raw === 'manga' || raw === 'novel' || raw === 'video') {
      return raw;
    }
    return 'all';
  }

  static setLibraryContentFilter(v: string): void {
    Settings.setStr('libContentFilter', v);
  }

  static getThemeMode(): string {
    return Settings.getStr('themeMode', 'auto');
  }

  static setThemeMode(mode: string): void {
    Settings.setStr('themeMode', mode);
  }

  // ---- 追踪（对齐 Mihon TrackPreferences）----
  // 仅存非敏感信息：trackUsername_{syncId} / trackDisplay_{syncId}
  // 密码与 OAuth token 一律走 SecureStore（Asset Store）加密存储，不落明文偏好
  static getTrackUsername(syncId: number): string {
    return Settings.getStr(`trackUsername_${syncId}`, '');
  }

  static setTrackUsername(syncId: number, v: string): void {
    Settings.setStr(`trackUsername_${syncId}`, v);
  }

  static getTrackDisplay(syncId: number): string {
    return Settings.getStr(`trackDisplay_${syncId}`, '');
  }

  static setTrackDisplay(syncId: number, v: string): void {
    Settings.setStr(`trackDisplay_${syncId}`, v);
  }

  // AniList 评分制：POINT_100 / POINT_10 / POINT_10_DECIMAL / POINT_5 / POINT_3
  static getAnilistScoreType(): string {
    return Settings.getStr('anilistScoreType', 'POINT_100');
  }

  static setAnilistScoreType(v: string): void {
    Settings.setStr('anilistScoreType', v);
  }

  // Kitsu 评分制：simple（表情）/ regular（星）/ advanced（10 分制小数）
  static getKitsuScoreType(): string {
    const raw: string = Settings.getStr('kitsuScoreType', 'simple');
    if (raw === 'regular' || raw === 'advanced') {
      return raw;
    }
    return 'simple';
  }

  static setKitsuScoreType(v: string): void {
    Settings.setStr('kitsuScoreType', v);
  }

  // MangaBaka 评分制：STEP_1 / STEP_5 / STEP_10 / STEP_20 / STEP_25（0-100 步进）
  static getMangabakaScoreType(): string {
    return Settings.getStr('mangabakaScoreType', 'STEP_10');
  }

  static setMangabakaScoreType(v: string): void {
    Settings.setStr('mangabakaScoreType', v);
  }

  // 阅读完成后自动同步追踪进度
  static getTrackAutoUpdate(): boolean {
    return Settings.getBool('trackAutoUpdate', true);
  }

  static setTrackAutoUpdate(v: boolean): void {
    Settings.setBool('trackAutoUpdate', v);
  }

  static getLastRefreshAt(): number {
    return Settings.getNum('lastRefreshAt', 0);
  }

  static setLastRefreshAt(time: number): void {
    Settings.setNum('lastRefreshAt', time);
  }

  static getPluginRepoUrl(): string {
    return Settings.getStr('pluginRepoUrl', '');
  }

  static setPluginRepoUrl(url: string): void {
    Settings.setStr('pluginRepoUrl', url);
  }

  // ---- 数据与存储（对齐 Mihon BackupPreferences / LibraryPreferences）----
  // 自动备份频率（小时，0=关闭）
  static getBackupInterval(): number {
    return Settings.getNum('backupInterval', 0);
  }

  static setBackupInterval(v: number): void {
    Settings.setNum('backupInterval', v);
  }

  // 上次自动备份时间戳（毫秒）
  static getLastAutoBackupTimestamp(): number {
    return Settings.getNum('lastAutoBackupTimestamp', 0);
  }

  static setLastAutoBackupTimestamp(v: number): void {
    Settings.setNum('lastAutoBackupTimestamp', v);
  }

  // 启动时清除章节缓存
  static getAutoClearChapterCache(): boolean {
    return Settings.getBool('autoClearChapterCache', false);
  }

  static setAutoClearChapterCache(v: boolean): void {
    Settings.setBool('autoClearChapterCache', v);
  }

  // ---- 主题 ----
  static getAppThemeId(): string {
    const raw: string = Settings.getStr('appTheme', 'default');
    return Theme.isValidTheme(raw) ? raw : 'default';
  }

  static setAppThemeId(v: string): void {
    Settings.setStr('appTheme', v);
  }

  static getAmoledMode(): boolean {
    return Settings.getBool('amoledMode', false);
  }

  static setAmoledMode(v: boolean): void {
    Settings.setBool('amoledMode', v);
  }

  // ---- 全局标志 ----
  static getDownloadedOnly(): boolean {
    return Settings.getBool('downloadedOnly', false);
  }

  static setDownloadedOnly(v: boolean): void {
    Settings.setBool('downloadedOnly', v);
    AppStorage.setOrCreate(AppKeys.DOWNLOADED_ONLY, v);
  }

  static getIncognito(): boolean {
    return Settings.getBool('incognito', false);
  }

  static setIncognito(v: boolean): void {
    Settings.setBool('incognito', v);
    AppStorage.setOrCreate(AppKeys.INCOGNITO, v);
  }

  static getShowNsfw(): boolean {
    return Settings.getBool('showNsfw', false);
  }

  static setShowNsfw(v: boolean): void {
    Settings.setBool('showNsfw', v);
    AppStorage.setOrCreate(AppKeys.SHOW_NSFW, v);
  }

  static getDownloadWifiOnly(): boolean {
    return Settings.getBool('downloadWifiOnly', false);
  }

  static setDownloadWifiOnly(v: boolean): void {
    Settings.setBool('downloadWifiOnly', v);
  }

  static pushGlobalFlags(): void {
    AppStorage.setOrCreate(AppKeys.DOWNLOADED_ONLY, Settings.getDownloadedOnly());
    AppStorage.setOrCreate(AppKeys.INCOGNITO, Settings.getIncognito());
    AppStorage.setOrCreate(AppKeys.SHOW_NSFW, Settings.getShowNsfw());
  }

  // ---- 通用 ----
  static getStartTab(): number {
    return Settings.getNum('startTab', 0);
  }

  static setStartTab(v: number): void {
    Settings.setNum('startTab', v);
  }

  // ---- 新手引导（对齐 Mihon shownOnboarding）----
  static getShownOnboarding(): boolean {
    return Settings.getBool('shownOnboarding', false);
  }

  static setShownOnboarding(v: boolean): void {
    Settings.setBool('shownOnboarding', v);
  }

  // ---- 应用语言 ----
  // 'auto' 跟随系统，否则为 BCP-47 语言标签（如 'zh-Hans' / 'en-US'）
  static getAppLanguage(): string {
    const raw: string = Settings.getStr('appLanguage', 'auto');
    // 旧版取值迁移（'zh'/'en'）
    if (raw === 'zh') {
      return 'zh-Hans';
    }
    if (raw === 'en') {
      return 'en-US';
    }
    return raw;
  }

  static setAppLanguage(v: string): void {
    Settings.setStr('appLanguage', v);
  }

  // 应用语言偏好到系统（立即生效并持久化；'default' 跟随系统需冷启动生效）
  static applyAppLanguage(): void {
    const lang: string = Settings.getAppLanguage();
    AppStorage.setOrCreate(AppKeys.APP_LANGUAGE, lang);
    const tag: string = lang === 'auto' ? 'default' : lang;
    try {
      i18n.System.setAppPreferredLanguage(tag);
    } catch (_e) {
    }
  }

  // ---- 书架 ----
  // 排序键：'alpha','total','lastRead','lastUpdate','unread','latestChapter','fetchDate','dateAdded','random'
  static getLibrarySort(): string {
    const raw: string = Settings.getStr('librarySort', 'alpha');
    // 旧版取值迁移
    if (raw === 'title') {
      return 'alpha';
    }
    if (raw === 'added') {
      return 'dateAdded';
    }
    return raw;
  }

  static setLibrarySort(v: string): void {
    Settings.setStr('librarySort', v);
  }

  static getLibrarySortAsc(): boolean {
    return Settings.getBool('librarySortAsc', true);
  }

  static setLibrarySortAsc(v: boolean): void {
    Settings.setBool('librarySortAsc', v);
  }

  // 三态筛选：key 为 'downloaded','unread','started','bookmarked','completed','tracked'
  // 值为 'ignore'（忽略）| 'include'（包含）| 'exclude'（排除）
  static getLibraryTriState(key: string): string {
    return Settings.getStr('libFilter:' + key, 'ignore');
  }

  static setLibraryTriState(key: string, v: string): void {
    Settings.setStr('libFilter:' + key, v);
  }

  // ---- 更新页筛选（对齐 Mihon UpdatesPreferences）----
  // 三态：key 为 'downloaded','unread','started','bookmarked'
  static getUpdatesTriState(key: string): string {
    return Settings.getStr('updFilter:' + key, 'ignore');
  }

  static setUpdatesTriState(key: string, v: string): void {
    Settings.setStr('updFilter:' + key, v);
  }

  // 分类筛选（JSON 数组）：排除优先于包含
  static getUpdatesIncludedCategories(): number[] {
    return Settings.getNumList('updFilterCats:included');
  }

  static setUpdatesIncludedCategories(v: number[]): void {
    Settings.setStr('updFilterCats:included', JSON.stringify(v));
  }

  static getUpdatesExcludedCategories(): number[] {
    return Settings.getNumList('updFilterCats:excluded');
  }

  static setUpdatesExcludedCategories(v: number[]): void {
    Settings.setStr('updFilterCats:excluded', JSON.stringify(v));
  }

  // ---- 即将推出页分类筛选（对齐 Mihon UpcomingPreferences）----
  static getUpcomingIncludedCategories(): number[] {
    return Settings.getNumList('upcomingCats:included');
  }

  static setUpcomingIncludedCategories(v: number[]): void {
    Settings.setStr('upcomingCats:included', JSON.stringify(v));
  }

  static getUpcomingExcludedCategories(): number[] {
    return Settings.getNumList('upcomingCats:excluded');
  }

  static setUpcomingExcludedCategories(v: number[]): void {
    Settings.setStr('upcomingCats:excluded', JSON.stringify(v));
  }

  // JSON 数字数组读取（异常/类型不符时回退空数组）
  private static getNumList(key: string): number[] {
    const raw: string = Settings.getStr(key, '[]');
    const result: number[] = [];
    try {
      const parsed = JSON.parse(raw) as number[];
      for (const n of parsed) {
        if (typeof n === 'number') {
          result.push(n);
        }
      }
    } catch (e) {
      // 解析失败按空处理
    }
    return result;
  }

  // 显示模式：'compact','comfortable','cover','list'（旧值 'grid' 归一为 'compact'）
  static getLibraryView(): string {
    const raw: string = Settings.getStr('libraryView', 'compact');
    if (raw === 'grid') {
      return 'compact';
    }
    return raw;
  }

  static setLibraryView(v: string): void {
    Settings.setStr('libraryView', v);
  }

  // 每行数目：0 = 自动
  static getLibraryGridCols(): number {
    const v: number = Settings.getNum('libraryGridCols', 0);
    if (v < 0 || v > 10) {
      return 0;
    }
    return Math.floor(v);
  }

  static setLibraryGridCols(v: number): void {
    Settings.setNum('libraryGridCols', v);
  }

  static getShowUnreadBadge(): boolean {
    return Settings.getBool('showUnreadBadge', true);
  }

  static setShowUnreadBadge(v: boolean): void {
    Settings.setBool('showUnreadBadge', v);
  }

  static getShowDownloadBadge(): boolean {
    return Settings.getBool('showDownloadBadge', true);
  }

  static setShowDownloadBadge(v: boolean): void {
    Settings.setBool('showDownloadBadge', v);
  }

  static getShowLocalBadge(): boolean {
    return Settings.getBool('showLocalBadge', false);
  }

  static setShowLocalBadge(v: boolean): void {
    Settings.setBool('showLocalBadge', v);
  }

  static getShowLanguageBadge(): boolean {
    return Settings.getBool('showLanguageBadge', false);
  }

  static setShowLanguageBadge(v: boolean): void {
    Settings.setBool('showLanguageBadge', v);
  }

  static getShowCategoryTabs(): boolean {
    return Settings.getBool('showCategoryTabs', true);
  }

  static setShowCategoryTabs(v: boolean): void {
    Settings.setBool('showCategoryTabs', v);
  }

  static getShowMangaCount(): boolean {
    return Settings.getBool('showMangaCount', false);
  }

  static setShowMangaCount(v: boolean): void {
    Settings.setBool('showMangaCount', v);
  }

  // ---- 阅读器 ----
  static getReaderShowPageNumber(): boolean {
    return Settings.getBool('readerShowPageNumber', true);
  }

  static setReaderShowPageNumber(v: boolean): void {
    Settings.setBool('readerShowPageNumber', v);
  }

  static getReaderDualPage(): boolean {
    return Settings.getBool('readerDualPage', false);
  }

  static setReaderDualPage(v: boolean): void {
    Settings.setBool('readerDualPage', v);
  }

  static getReaderTheme(): number {
    return Settings.getNum('readerTheme', 3);
  }

  static setReaderTheme(v: number): void {
    Settings.setNum('readerTheme', v);
  }

  static getReaderBrightness(): number {
    const n: number = Settings.getNum('readerBrightness', 0);
    // 钳制到 [0,1]：越界值传给 setWindowBrightness 会静默失败，导致亮度调节永久失效
    return n >= 0 && n <= 1 ? n : 0;
  }

  static setReaderBrightness(v: number): void {
    Settings.setNum('readerBrightness', v);
  }

  static getReaderCrop(): boolean {
    return Settings.getBool('readerCrop', false);
  }

  static setReaderCrop(v: boolean): void {
    Settings.setBool('readerCrop', v);
  }

  static getReaderOrientation(): string {
    return Settings.getStr('readerOrientation', 'free');
  }

  static setReaderOrientation(v: string): void {
    Settings.setStr('readerOrientation', v);
  }

  // ---- 阅读器滤镜（灰度/反色为开关；亮度/对比度/饱和度有开关+百分比，100=原始） ----
  static getReaderGrayscale(): boolean {
    return Settings.getBool('readerGrayscale', false);
  }

  static setReaderGrayscale(v: boolean): void {
    Settings.setBool('readerGrayscale', v);
  }

  static getReaderInvert(): boolean {
    return Settings.getBool('readerInvert', false);
  }

  static setReaderInvert(v: boolean): void {
    Settings.setBool('readerInvert', v);
  }

  static getReaderBrightnessEnabled(): boolean {
    return Settings.getBool('readerBrightnessEnabled', false);
  }

  static setReaderBrightnessEnabled(v: boolean): void {
    Settings.setBool('readerBrightnessEnabled', v);
  }

  static getReaderFilterBrightness(): number {
    return Settings.getNum('readerFilterBrightness', 100);
  }

  static setReaderFilterBrightness(v: number): void {
    Settings.setNum('readerFilterBrightness', v);
  }

  static getReaderContrastEnabled(): boolean {
    return Settings.getBool('readerContrastEnabled', false);
  }

  static setReaderContrastEnabled(v: boolean): void {
    Settings.setBool('readerContrastEnabled', v);
  }

  static getReaderContrast(): number {
    return Settings.getNum('readerContrast', 100);
  }

  static setReaderContrast(v: number): void {
    Settings.setNum('readerContrast', v);
  }

  static getReaderSaturationEnabled(): boolean {
    return Settings.getBool('readerSaturationEnabled', false);
  }

  static setReaderSaturationEnabled(v: boolean): void {
    Settings.setBool('readerSaturationEnabled', v);
  }

  static getReaderSaturation(): number {
    return Settings.getNum('readerSaturation', 100);
  }

  static setReaderSaturation(v: number): void {
    Settings.setNum('readerSaturation', v);
  }

  // 漫画翻页动画（横向分页）：curl（仿真）| slide（滑动）| cover（覆盖）。垂直滚动与条漫不使用仿真。
  static getReaderPageAnim(): string {
    const raw = Settings.getStr('readerPageAnim', 'slide');
    if (raw === 'curl' || raw === 'cover') {
      return raw;
    }
    return 'slide';
  }

  static setReaderPageAnim(v: string): void {
    Settings.setStr('readerPageAnim', v);
  }

  // ---- 阅读器导航/条漫 ----
  // 点击翻页区域：'default','ltr','rtl','vertical','edge','none'
  static getReaderNavMode(): string {
    return Settings.getStr('readerNavMode', 'default');
  }

  static setReaderNavMode(v: string): void {
    Settings.setStr('readerNavMode', v);
  }

  // 条漫侧边距（百分比 0-25）
  static getReaderWebtoonPadding(): number {
    return Settings.getNum('readerWebtoonPadding', 0);
  }

  static setReaderWebtoonPadding(v: number): void {
    Settings.setNum('readerWebtoonPadding', v);
  }

  static getViewerMode(mangaId: string): string {
    return Settings.getStr('viewer_mode:' + mangaId, '');
  }

  static setViewerMode(mangaId: string, mode: string): void {
    Settings.setStr('viewer_mode:' + mangaId, mode);
  }

  static removeViewerMode(mangaId: string): void {
    if (Settings.store === undefined) {
      return;
    }
    try {
      Settings.store.deleteSync('viewer_mode:' + mangaId);
    } catch (_e) {
    }
    Settings.scheduleFlush();
  }

  // ---- 视频播放器 ----
  // 默认播放倍速（0.5 - 3.0）
  static getVideoSpeed(): number {
    const n = Settings.getNum('videoSpeed', 1.0);
    return n >= 0.5 && n <= 3.0 ? n : 1.0;
  }

  static setVideoSpeed(v: number): void {
    Settings.setNum('videoSpeed', v);
  }

  // 播完自动连播下一集
  static getVideoAutoNext(): boolean {
    return Settings.getBool('videoAutoNext', true);
  }

  static setVideoAutoNext(v: boolean): void {
    Settings.setBool('videoAutoNext', v);
  }

  // 画面显示模式（0=适应 1=填充 2=拉伸）
  static getVideoScaleMode(): number {
    const n = Settings.getNum('videoScaleMode', 0);
    return n >= 0 && n <= 2 ? Math.floor(n) : 0;
  }

  static setVideoScaleMode(v: number): void {
    Settings.setNum('videoScaleMode', v);
  }

  // ---- 弹幕 ----
  static getDanmakuEnabled(): boolean {
    return Settings.getBool('danmakuEnabled', true);
  }

  static setDanmakuEnabled(v: boolean): void {
    Settings.setBool('danmakuEnabled', v);
  }

  // 弹幕字号（vp）
  static getDanmakuFont(): number {
    const n = Settings.getNum('danmakuFont', 16);
    return n >= 12 && n <= 28 ? n : 16;
  }

  static setDanmakuFont(v: number): void {
    Settings.setNum('danmakuFont', v);
  }

  // 弹幕不透明度（百分比 10 - 100）
  static getDanmakuOpacityPct(): number {
    const n = Settings.getNum('danmakuOpacity', 80);
    return n >= 10 && n <= 100 ? n : 80;
  }

  static setDanmakuOpacityPct(v: number): void {
    Settings.setNum('danmakuOpacity', v);
  }

  // 弹幕显示区域（占屏幕高度百分比：25/50/75/100）
  static getDanmakuAreaPct(): number {
    const n = Settings.getNum('danmakuArea', 50);
    return n === 25 || n === 75 || n === 100 ? n : 50;
  }

  static setDanmakuAreaPct(v: number): void {
    Settings.setNum('danmakuArea', v);
  }

  // 弹幕滚动时长（秒，越短越快：6/8/10/12）
  static getDanmakuDurationSec(): number {
    const n = Settings.getNum('danmakuDuration', 10);
    return n === 6 || n === 8 || n === 12 ? n : 10;
  }

  static setDanmakuDurationSec(v: number): void {
    Settings.setNum('danmakuDuration', v);
  }

  // ---- 本地源文件夹（Mihon local source：固定一个用户文件夹，同步进沙箱扫描）----
  static getLocalFolderUri(): string {
    return Settings.getStr('localFolderUri', '');
  }

  static setLocalFolderUri(v: string): void {
    Settings.setStr('localFolderUri', v);
  }

  static getLocalFolderName(): string {
    return Settings.getStr('localFolderName', '');
  }

  static setLocalFolderName(v: string): void {
    Settings.setStr('localFolderName', v);
  }

  static getLastLocalSyncAt(): number {
    return Settings.getNum('lastLocalSyncAt', 0);
  }

  static setLastLocalSyncAt(v: number): void {
    Settings.setNum('lastLocalSyncAt', v);
  }

  // ---- 源 ----
  static getPinnedSources(): string {
    return Settings.getStr('pinnedSources', '[]');
  }

  static setPinnedSources(v: string): void {
    Settings.setStr('pinnedSources', v);
  }

  // ---- 主题应用 ----
  // 根据设置与系统颜色模式计算是否深色，并写入 AppStorage 与 palette
  static applyTheme(systemDark: boolean): void {
    const mode: string = Settings.getThemeMode();
    const dark: boolean = mode === 'dark' || (mode === 'auto' && systemDark);
    AppStorage.setOrCreate(AppKeys.IS_DARK, dark);
    AppStorage.setOrCreate(AppKeys.APP_THEME, Settings.getAppThemeId());
    AppStorage.setOrCreate(AppKeys.AMOLED, Settings.getAmoledMode());
    Settings.pushPalette();
  }

  // 主题/AMOLED 变更：更新 AppStorage、重建色板并同步系统栏
  static applyAppTheme(context: common.Context): void {
    AppStorage.setOrCreate(AppKeys.APP_THEME, Settings.getAppThemeId());
    AppStorage.setOrCreate(AppKeys.AMOLED, Settings.getAmoledMode());
    Settings.pushPalette();
    Settings.applySystemBar(context);
  }

  // 重建色板并写入 AppStorage 'palette'（组件经 @StorageProp 绑定）
  static pushPalette(): void {
    const dark: boolean = AppStorage.get<boolean>(AppKeys.IS_DARK) ?? false;
    AppStorage.setOrCreate(AppKeys.PALETTE,
      Theme.buildPalette(Settings.getAppThemeId(), dark, Settings.getAmoledMode()));
  }

  // 应用颜色模式到系统（资源/系统组件随此切换；auto = 跟随系统）
  static applyColorMode(context: common.Context): void {
    const mode: string = Settings.getThemeMode();
    if (mode === 'dark') {
      try {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } catch (e) {
        throw new Error(`set color mode failed: ${e}`);
      }
    } else if (mode === 'light') {
      try {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } catch (e) {
        throw new Error(`set color mode failed: ${e}`);
      }
    } else {
      try {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      } catch (e) {
        throw new Error(`set color mode failed: ${e}`);
      }
    }
    Settings.applySystemBar(context);
  }

  // 系统栏：透明背景（沉浸式，光感效果由系统渲染），内容色取自当前 palette 的文本色
  static applySystemBar(context: common.Context): void {
    window.getLastWindow(context).then((win: window.Window) => {
      const dark: boolean = AppStorage.get<boolean>(AppKeys.IS_DARK) ?? false;
      const pal: ThemePalette = AppStorage.get<ThemePalette>(AppKeys.PALETTE) ?? new ThemePalette();
      const content: string = pal.text;
      if (canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
        win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          statusBarContentColor: content,
          isStatusBarLightIcon: dark,
          navigationBarColor: '#00000000',
          navigationBarContentColor: content,
          isNavigationBarLightIcon: dark
        }).catch((_e: Error) => {
        });
      }
    }).catch((_e: Error) => {
    });
  }

  // 避让区高度（vp）写入 AppStorage，供页面上下 padding 避让状态栏/导航栏
  private static avoidSubscribed: boolean = false;

  static initAvoidAreas(context: common.Context): void {
    window.getLastWindow(context).then((win: window.Window) => {
      const ui: UIContext = win.getUIContext();
      const sync = (): void => {
        const sb: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const nb: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        AppStorage.setOrCreate(AppKeys.STATUS_BAR_H, ui.px2vp(sb.topRect.height));
        AppStorage.setOrCreate(AppKeys.NAV_BAR_H, ui.px2vp(nb.bottomRect.height));
      };
      sync();
      // 动态订阅避让区变化：折叠/旋转后高度随之更新，避免只取一次快照导致避让区过期
      if (!Settings.avoidSubscribed) {
        try {
          win.on('avoidAreaChange', (_data: window.AvoidAreaOptions): void => {
            sync();
          });
          Settings.avoidSubscribed = true;
        } catch (_e) {
        }
      }
    }).catch((_e: Error) => {
    });
  }
}
