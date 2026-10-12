import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window, UIContext } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { Theme } from './Theme';

// 轻量设置存储（阅读/主题/书架/阅读器/浏览/全局开关等）
export class Settings {
  private static store: preferences.Preferences | undefined = undefined;

  static init(context: common.UIAbilityContext): void {
    if (Settings.store === undefined) {
      const options: preferences.Options = { name: 'honyomi_settings' };
      Settings.store = preferences.getPreferencesSync(context, options);
    }
  }

  private static getStr(key: string, def: string): string {
    if (Settings.store === undefined) {
      return def;
    }
    return Settings.store.getSync(key, def) as string;
  }

  private static setStr(key: string, value: string): void {
    if (Settings.store === undefined) {
      return;
    }
    Settings.store.putSync(key, value);
    Settings.store.flush();
  }

  private static getBool(key: string, def: boolean): boolean {
    if (Settings.store === undefined) {
      return def;
    }
    return Settings.store.getSync(key, def) as boolean;
  }

  private static setBool(key: string, value: boolean): void {
    if (Settings.store === undefined) {
      return;
    }
    Settings.store.putSync(key, value);
    Settings.store.flush();
  }

  private static getNum(key: string, def: number): number {
    if (Settings.store === undefined) {
      return def;
    }
    return Settings.store.getSync(key, def) as number;
  }

  private static setNum(key: string, value: number): void {
    if (Settings.store === undefined) {
      return;
    }
    Settings.store.putSync(key, value);
    Settings.store.flush();
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

  // 小说阅读模式：scroll（滚动）| paged（翻页）| double（双页）
  static getNovelReaderMode(): string {
    const raw = Settings.getStr('novelReaderMode', 'scroll');
    return raw === 'paged' || raw === 'double' ? raw : 'scroll';
  }

  static setNovelReaderMode(v: string): void {
    Settings.setStr('novelReaderMode', v);
  }

  // 小说段间距（vp）
  static getNovelParagraphSpacing(): number {
    const n = Settings.getNum('novelParagraphSpacing', 0);
    return n >= 0 && n <= 28 ? n : 0;
  }

  static setNovelParagraphSpacing(v: number): void {
    Settings.setNum('novelParagraphSpacing', v);
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

  static getAnilistToken(): string {
    return Settings.getStr('anilistToken', '');
  }

  static setAnilistToken(token: string): void {
    Settings.setStr('anilistToken', token);
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
  static getAccentColor(): string {
    return Settings.getStr('accentColor', 'blue');
  }

  static setAccentColor(v: string): void {
    Settings.setStr('accentColor', v);
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
    AppStorage.setOrCreate('downloadedOnly', v);
  }

  static getIncognito(): boolean {
    return Settings.getBool('incognito', false);
  }

  static setIncognito(v: boolean): void {
    Settings.setBool('incognito', v);
    AppStorage.setOrCreate('incognito', v);
  }

  static getShowNsfw(): boolean {
    return Settings.getBool('showNsfw', false);
  }

  static setShowNsfw(v: boolean): void {
    Settings.setBool('showNsfw', v);
  }

  static getDownloadWifiOnly(): boolean {
    return Settings.getBool('downloadWifiOnly', false);
  }

  static setDownloadWifiOnly(v: boolean): void {
    Settings.setBool('downloadWifiOnly', v);
  }

  static pushGlobalFlags(): void {
    AppStorage.setOrCreate('downloadedOnly', Settings.getDownloadedOnly());
    AppStorage.setOrCreate('incognito', Settings.getIncognito());
  }

  // ---- 通用 ----
  static getStartTab(): number {
    return Settings.getNum('startTab', 0);
  }

  static setStartTab(v: number): void {
    Settings.setNum('startTab', v);
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
    AppStorage.setOrCreate('appLanguage', lang);
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
    return Settings.getNum('readerBrightness', 0);
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
    Settings.store.deleteSync('viewer_mode:' + mangaId);
    Settings.store.flush();
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
    AppStorage.setOrCreate('isDark', dark);
    AppStorage.setOrCreate('accent', Settings.getAccentColor());
    AppStorage.setOrCreate('amoled', Settings.getAmoledMode());
    Settings.pushPalette();
  }

  static applyAccent(): void {
    AppStorage.setOrCreate('accent', Settings.getAccentColor());
    AppStorage.setOrCreate('amoled', Settings.getAmoledMode());
    Settings.pushPalette();
  }

  // 重建色板并写入 AppStorage 'palette'（组件经 @StorageProp 绑定）
  static pushPalette(): void {
    const dark: boolean = AppStorage.get<boolean>('isDark') ?? false;
    AppStorage.setOrCreate('palette',
      Theme.buildPalette(dark, Settings.getAmoledMode(), Settings.getAccentColor()));
  }

  // 应用颜色模式到系统（资源/系统组件随此切换；auto = 跟随系统）
  static applyColorMode(context: common.Context): void {
    const mode: string = Settings.getThemeMode();
    if (mode === 'dark') {
      context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (mode === 'light') {
      context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
    Settings.applySystemBar(context);
  }

  // 系统栏：透明背景（沉浸式，光感效果由系统渲染），内容色与应用文本色一致
  // 文本色与 color.json 的 honyomi_text 对应（浅 #16181D / 深 #ECEEF2）
  static applySystemBar(context: common.Context): void {
    window.getLastWindow(context).then((win: window.Window) => {
      const dark: boolean = AppStorage.get<boolean>('isDark') ?? false;
      const content: string = dark ? '#ECEEF2' : '#16181D';
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: content,
        isStatusBarLightIcon: dark,
        navigationBarColor: '#00000000',
        navigationBarContentColor: content,
        isNavigationBarLightIcon: dark
      }).catch((_e: Error) => {
      });
    }).catch((_e: Error) => {
    });
  }

  // 避让区高度（vp）写入 AppStorage，供页面上下 padding 避让状态栏/导航栏
  static initAvoidAreas(context: common.Context): void {
    window.getLastWindow(context).then((win: window.Window) => {
      const ui: UIContext = win.getUIContext();
      const sb: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const nb: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate('statusBarH', ui.px2vp(sb.topRect.height));
      AppStorage.setOrCreate('navBarH', ui.px2vp(nb.bottomRect.height));
    }).catch((_e: Error) => {
    });
  }
}
