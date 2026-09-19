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
}
