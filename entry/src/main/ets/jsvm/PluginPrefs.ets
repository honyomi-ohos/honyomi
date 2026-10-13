import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

/**
 * Per-extension SharedPreferences persistence for JSVM plugins.
 * Seeded into the engine as globalThis.__PREFS_STORE__ and flushed after
 * every __honyomiCall (see JsvmWorker prefs dump).
 */
export class PluginPrefs {
  private static store: preferences.Preferences | undefined = undefined;
  private static initPromise: Promise<void> | undefined = undefined;

  static init(prefs: preferences.Preferences): void {
    PluginPrefs.store = prefs;
  }

  /** Lazily opens the backing preferences file; safe to call repeatedly. */
  static ensureInit(context: common.Context): Promise<void> {
    if (PluginPrefs.store !== undefined) {
      return Promise.resolve();
    }
    if (PluginPrefs.initPromise === undefined) {
      PluginPrefs.initPromise = preferences.getPreferences(context, { name: 'plugin_prefs' })
        .then((prefs: preferences.Preferences): void => {
          PluginPrefs.store = prefs;
        })
        .catch((error: Error): void => {
          PluginPrefs.initPromise = undefined;
          throw error;
        });
    }
    return PluginPrefs.initPromise;
  }

  static seedScript(key: string): string {
    if (PluginPrefs.store === undefined) {
      return '';
    }
    const raw = PluginPrefs.store.getSync(`__extprefs:${key}`, '') as string;
    if (raw === '') {
      return '';
    }
    try {
      JSON.parse(raw);
    } catch (e) {
      // Corrupt persisted payload: drop it instead of poisoning the engine script.
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
