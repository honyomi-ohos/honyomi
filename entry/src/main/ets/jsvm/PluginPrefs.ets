import { preferences } from '@kit.ArkData';

/**
 * Per-extension SharedPreferences persistence for JSVM plugins.
 * Seeded into the engine as globalThis.__PREFS_STORE__ and flushed after
 * every __honyomiCall (see JsvmWorker prefs dump).
 */
export class PluginPrefs {
  private static store: preferences.Preferences | undefined = undefined;

  static init(prefs: preferences.Preferences): void {
    PluginPrefs.store = prefs;
  }

  static seedScript(key: string): string {
    if (PluginPrefs.store === undefined) {
      return '';
    }
    const raw = PluginPrefs.store.getSync(`__extprefs:${key}`, '') as string;
    if (raw === '') {
      return '';
    }
    return `globalThis.__PREFS_STORE__ = ${raw};`;
  }

  static persist(key: string, storeJson: string): void {
    if (PluginPrefs.store === undefined || storeJson === '') {
      return;
    }
    PluginPrefs.store.putSync(`__extprefs:${key}`, storeJson);
    PluginPrefs.store.flush();
  }
}
