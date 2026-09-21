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
      const options: preferences.Options = { name: 'mihon_settings' };
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
  // 'auto' 跟随系统 | 'zh' 简体中文 | 'en' English
  static getAppLanguage(): string {
    return Settings.getStr('appLanguage', 'auto');
  }

  static setAppLanguage(v: string): void {
    Settings.setStr('appLanguage', v);
  }

  // 应用语言偏好到系统（立即生效并持久化；'default' 跟随系统需冷启动生效）
  static applyAppLanguage(): void {
    const lang: string = Settings.getAppLanguage();
    const tag: string = lang === 'zh' ? 'zh-Hans' : (lang === 'en' ? 'en-US' : 'default');
    try {
      i18n.System.setAppPreferredLanguage(tag);
    } catch (_e) {
    }
  }

  // ---- 书架 ----
  static getLibrarySort(): string {
    return Settings.getStr('librarySort', 'title');
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

  static getLibraryFilter(): string {
    return Settings.getStr('libraryFilter', 'none');
  }

  static setLibraryFilter(v: string): void {
    Settings.setStr('libraryFilter', v);
  }

  static getLibraryView(): string {
    return Settings.getStr('libraryView', 'grid');
  }

  static setLibraryView(v: string): void {
    Settings.setStr('libraryView', v);
  }

  static getLibraryGridCols(): number {
    return Settings.getNum('libraryGridCols', 0);
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
  // 文本色与 color.json 的 mihon_text 对应（浅 #16181D / 深 #ECEEF2）
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
