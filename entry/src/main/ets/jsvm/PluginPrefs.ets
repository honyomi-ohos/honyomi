import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

/**
 * Per-extension SharedPreferences persistence for JSVM plugins.
 * Seeded into the engine as globalThis.__PREFS_STORE__ and flushed after
 * every __honyomiCall (see JsvmWorker prefs dump).
 *
 * persist 为防抖写（300ms 内多条 worker 消息合并为一次落盘）；
 * flushAll() 提供立即可 await 的落盘路径（销毁/退出场景防丢数据）。
 */
export class PluginPrefs {
  private static store: preferences.Preferences | undefined = undefined;
  private static initPromise: Promise<void> | undefined = undefined;
  // 防抖待写队列：扩展 key -> 最新 prefs JSON
  private static pending: Map<string, string> = new Map();
  private static debounceTimer: number = -1;

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

  // 防抖持久化：300ms 窗口内同一扩展仅保留最新快照，合并为一次 putSync + flush
  static persist(key: string, storeJson: string): void {
    if (PluginPrefs.store === undefined || storeJson === '') {
      return;
    }
    PluginPrefs.pending.set(key, storeJson);
    if (PluginPrefs.debounceTimer >= 0) {
      clearTimeout(PluginPrefs.debounceTimer);
    }
    PluginPrefs.debounceTimer = setTimeout(() => {
      PluginPrefs.debounceTimer = -1;
      PluginPrefs.writePending();
    }, 300);
  }

  // 立即落盘全部待写偏好并等待 flush 完成（供退出/销毁路径 await）
  static async flushAll(): Promise<void> {
    if (PluginPrefs.debounceTimer >= 0) {
      clearTimeout(PluginPrefs.debounceTimer);
      PluginPrefs.debounceTimer = -1;
    }
    if (PluginPrefs.pending.size > 0) {
      PluginPrefs.writePending();
    }
    const store = PluginPrefs.store;
    if (store !== undefined) {
      await store.flush();
    }
  }

  private static writePending(): void {
    const store = PluginPrefs.store;
    if (store === undefined) {
      return;
    }
    PluginPrefs.pending.forEach((json: string, key: string) => {
      store.putSync(`__extprefs:${key}`, json);
    });
    PluginPrefs.pending.clear();
    store.flush();
  }
}
