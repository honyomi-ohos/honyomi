import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// 轻量设置存储（阅读模式 / 主题模式）
export class Settings {
  private static store: preferences.Preferences | undefined = undefined;

  static init(context: common.UIAbilityContext): void {
    if (Settings.store === undefined) {
      const options: preferences.Options = { name: 'mihon_settings' };
      Settings.store = preferences.getPreferencesSync(context, options);
    }
  }

  static getReaderMode(): string {
    if (Settings.store === undefined) {
      return 'ltr';
    }
    const value = Settings.store.getSync('readerMode', 'ltr') as string;
    return value;
  }

  static setReaderMode(mode: string): void {
    if (Settings.store === undefined) {
      return;
    }
    Settings.store.putSync('readerMode', mode);
    Settings.store.flush();
  }

  static getThemeMode(): string {
    if (Settings.store === undefined) {
      return 'auto';
    }
    const value = Settings.store.getSync('themeMode', 'auto') as string;
    return value;
  }

  static setThemeMode(mode: string): void {
    if (Settings.store === undefined) {
      return;
    }
    Settings.store.putSync('themeMode', mode);
    Settings.store.flush();
  }

  // 根据设置与系统颜色模式计算是否深色，并写入 AppStorage
  static applyTheme(systemDark: boolean): void {
    const mode: string = Settings.getThemeMode();
    const dark: boolean = mode === 'dark' || (mode === 'auto' && systemDark);
    AppStorage.setOrCreate('isDark', dark);
  }

  static getAnilistToken(): string {
    if (Settings.store === undefined) {
      return '';
    }
    const value = Settings.store.getSync('anilistToken', '') as string;
    return value;
  }

  static setAnilistToken(token: string): void {
    if (Settings.store === undefined) {
      return;
    }
    Settings.store.putSync('anilistToken', token);
    Settings.store.flush();
  }

  static getLastRefreshAt(): number {
    if (Settings.store === undefined) {
      return 0;
    }
    const value = Settings.store.getSync('lastRefreshAt', 0) as number;
    return value;
  }

  static setLastRefreshAt(time: number): void {
    if (Settings.store === undefined) {
      return;
    }
    Settings.store.putSync('lastRefreshAt', time);
    Settings.store.flush();
  }

  static getPluginRepoUrl(): string {
    if (Settings.store === undefined) {
      return '';
    }
    const value = Settings.store.getSync('pluginRepoUrl', '') as string;
    return value;
  }

  static setPluginRepoUrl(url: string): void {
    if (Settings.store === undefined) {
      return;
    }
    Settings.store.putSync('pluginRepoUrl', url);
    Settings.store.flush();
  }
}
