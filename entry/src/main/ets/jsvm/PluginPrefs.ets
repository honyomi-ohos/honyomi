import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SecureStore } from '../common/SecureStore';

const DOMAIN = 0x0000;
const TAG = 'PluginPrefs';

/**
 * Per-extension SharedPreferences persistence for JSVM plugins.
 * Seeded into the engine as globalThis.__PREFS_STORE__ (captured into the
 * shim's closure and hidden from the plugin surface) and flushed after
 * every __honyomiCall (see JsvmWorker prefs dump).
 *
 * 安全契约：每个引擎实例只承载一个扩展，偏好存储是该扩展自己的扁平偏好映射
 * （k→v），由 shim 持有为闭包私有对象；插件经 $.prefs（createPrefs() 的后端）
 * 读写，raw __prefs_* 全局不进插件可见面，插件无法寻址其它插件的偏好。
 * persist/seed 均以 manifest.key 为持久化命名空间。
 *
 * persist 为防抖写（300ms 内多条 worker 消息合并为一次落盘）；
 * flushAll() 提供立即可 await 的落盘路径（销毁/退出场景防丢数据）。
 *
 * 敏感偏好分流：插件经 getSettingsSchema 声明 sensitive: true（或 type: 'password'）
 * 的设置项，其值存入 SecureStore（Asset Store，别名 honyomi.plugin.{pkg}.{key}），
 * 明文 preferences 仅保留非敏感键；seedScript 时再合并回偏好存储，
 * 插件 JS 读取路径不变。
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

  // 敏感键的 Asset Store 别名（pkgKey + prefKey 保证全局唯一）
  static secureAlias(pkgKey: string, prefKey: string): string {
    return `honyomi.plugin.${pkgKey}.${prefKey}`;
  }

  // 读取扩展声明的敏感键注册表（__extsecure:{key}，JSON 字符串数组）
  static secureKeysOf(pkgKey: string): string[] {
    const store = PluginPrefs.store;
    if (store === undefined) {
      return [];
    }
    try {
      const raw = store.getSync(`__extsecure:${pkgKey}`, '[]') as string;
      const parsed = JSON.parse(raw) as Array<Object>;
      const keys: string[] = [];
      for (const k of parsed) {
        if (typeof k === 'string' && k !== '') {
          keys.push(k);
        }
      }
      return keys;
    } catch (_e) {
    }
    return [];
  }

  /**
   * 注册/刷新扩展的敏感键（引擎启动时由 getSettingsSchema 声明解析而来）。
   * 注册后 persist 自动把敏感值分流到 SecureStore，seedScript 回注内存。
   */
  static registerSensitiveKeys(pkgKey: string, keys: string[]): void {
    const store = PluginPrefs.store;
    if (store === undefined) {
      return;
    }
    try {
      store.putSync(`__extsecure:${pkgKey}`, JSON.stringify(keys));
      store.flush().catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, 'flush sensitive-key registry failed: %{public}s', `${e}`);
      });
    } catch (_e) {
    }
  }

  // 卸载清理：删除该扩展全部敏感条目（SecureStore）与敏感键注册表
  static removeSecureEntries(pkgKey: string): void {
    const store = PluginPrefs.store;
    if (store === undefined) {
      return;
    }
    const keys = PluginPrefs.secureKeysOf(pkgKey);
    for (const k of keys) {
      SecureStore.removeSync(PluginPrefs.secureAlias(pkgKey, k));
    }
    try {
      store.deleteSync(`__extsecure:${pkgKey}`);
      store.flush().catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, 'flush after sensitive-key removal failed: %{public}s', `${e}`);
      });
    } catch (_e) {
    }
  }

  // 卸载路径：彻底清除该扩展的明文偏好 blob（__extprefs:<key>）与防抖队列中的
  // 待写快照。若只清 SecureStore 不清明文 blob，重装同 key（或安装仿冒同 key 的
  // 恶意包）会经 seedScript 继承旧偏好
  static removePackage(pkgKey: string): void {
    PluginPrefs.pending.delete(pkgKey);
    const store = PluginPrefs.store;
    if (store === undefined) {
      return;
    }
    try {
      store.deleteSync(`__extprefs:${pkgKey}`);
      store.flush().catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, 'flush after prefs removal failed: %{public}s', `${e}`);
      });
    } catch (_e) {
    }
  }

  // 构建 __PREFS_STORE__ 种子：明文偏好 + SecureStore 敏感值合并；
  // 插件 JS 读取路径不变（敏感值仅存在于内存中的 globalThis）
  static seedScript(key: string): string {
    const merged = PluginPrefs.mergedPrefs(key);
    const json = JSON.stringify(merged);
    if (json === '{}' || json === '') {
      return '';
    }
    try {
      JSON.parse(json);
    } catch (e) {
      return '';
    }
    return `globalThis.__PREFS_STORE__ = ${json};`;
  }

  // 当前持久化偏好的合并视图（明文 preferences + SecureStore 敏感值）：
  // manifest 静态设置读取当前值用；store 未初始化/载荷损坏时返回空对象
  static currentValues(key: string): Record<string, Object> {
    return PluginPrefs.mergedPrefs(key);
  }

  // 单键写入（manifest 静态设置路径）：合并当前值 → 改键 → 敏感分流 → 立即落盘。
  // 立即写而非防抖：设置页写入后回读必须一致；先叠加防抖队列中的 worker 快照，
  // 避免立即落盘覆盖丢失 worker 侧更新
  static updatePref(pkgKey: string, key: string, value: string): void {
    const store = PluginPrefs.store;
    if (store === undefined) {
      return;
    }
    const merged = PluginPrefs.mergedPrefs(pkgKey);
    const pendingJson = PluginPrefs.pending.get(pkgKey);
    if (pendingJson !== undefined) {
      try {
        const pendingParsed = JSON.parse(pendingJson) as Record<string, Object>;
        // 仅接受对象载荷：JSON.parse('null')/'5' 等合法非对象 JSON 直接丢弃
        if (pendingParsed !== null && pendingParsed !== undefined && typeof pendingParsed === 'object') {
          for (const k of Object.keys(pendingParsed)) {
            merged[k] = pendingParsed[k];
          }
        }
      } catch (_e) {
      }
    }
    merged[key] = value;
    PluginPrefs.persist(pkgKey, JSON.stringify(merged));
    if (PluginPrefs.debounceTimer >= 0) {
      clearTimeout(PluginPrefs.debounceTimer);
      PluginPrefs.debounceTimer = -1;
    }
    PluginPrefs.writePending();
    store.flush().catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'flush after pref update failed: %{public}s', `${e}`);
    });
  }

  // 明文偏好 + SecureStore 敏感值合并（seedScript / currentValues / updatePref 共用）。
  // 全链路契约：__PREFS_STORE__ 是单个扩展自己的扁平偏好映射（k→v），
  // 仅接受顶层字符串键；损坏/非对象载荷整体丢弃。
  private static mergedPrefs(key: string): Record<string, Object> {
    const merged: Record<string, Object> = {};
    const store = PluginPrefs.store;
    if (store !== undefined) {
      let raw = '';
      try {
        raw = store.getSync(`__extprefs:${key}`, '') as string;
      } catch (e) {
        raw = '';
      }
      if (raw !== '') {
        try {
          const parsed = JSON.parse(raw) as Record<string, Object>;
          // 仅接受对象载荷：JSON.parse('null')/'5' 等合法非对象 JSON 直接丢弃，
          // 否则后续 merged[k] = v 写入 null 会抛错
          if (parsed !== null && parsed !== undefined && typeof parsed === 'object') {
            // 顶层字符串键
            for (const k of Object.keys(parsed)) {
              if (typeof parsed[k] === 'string') {
                merged[k] = parsed[k];
              }
            }
          }
        } catch (e) {
          // Corrupt persisted payload: drop it instead of poisoning the engine script.
        }
      }
    }
    // 敏感键回注：Asset Store → __PREFS_STORE__
    const secureKeys = PluginPrefs.secureKeysOf(key);
    for (const k of secureKeys) {
      const v = SecureStore.getSync(PluginPrefs.secureAlias(key, k));
      if (v !== '') {
        merged[k] = v;
      }
    }
    return merged;
  }

  // 防抖持久化：300ms 窗口内同一扩展仅保留最新快照，合并为一次 putSync + flush；
  // 声明了敏感键的扩展先分流（敏感值 → SecureStore，其余 → 明文偏好）
  static persist(key: string, storeJson: string): void {
    if (PluginPrefs.store === undefined || storeJson === '') {
      return;
    }
    const plainJson = PluginPrefs.splitSecure(key, storeJson);
    PluginPrefs.pending.set(key, plainJson);
    if (PluginPrefs.debounceTimer >= 0) {
      clearTimeout(PluginPrefs.debounceTimer);
    }
    PluginPrefs.debounceTimer = setTimeout(() => {
      PluginPrefs.debounceTimer = -1;
      PluginPrefs.writePending();
    }, 300);
  }

  // 敏感分流：把快照 JSON 拆为“敏感值 → SecureStore / 其余 → 明文偏好”，

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
      try {
        await store.flush();
      } catch (e) {
        throw new Error(`flush plugin prefs failed: ${e}`);
      }
    }
  }

  // 返回应写入明文偏好的 JSON（无敏感键时原样返回）
  private static splitSecure(pkgKey: string, storeJson: string): string {
    const secureKeys = PluginPrefs.secureKeysOf(pkgKey);
    if (secureKeys.length === 0) {
      return storeJson;
    }
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(storeJson) as Record<string, Object>;
    } catch (_e) {
      return storeJson;
    }
    const keySet = new Set<string>(secureKeys);
    const plain: Record<string, Object> = {};
    for (const k of Object.keys(parsed)) {
      const v: Object | undefined = parsed[k];
      if (keySet.has(k) && typeof v === 'string') {
        // 空串视为清除该敏感项（Asset Store 删除条目）
        SecureStore.putSync(PluginPrefs.secureAlias(pkgKey, k), v as string);
      } else {
        plain[k] = v as Object;
      }
    }
    return JSON.stringify(plain);
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
    try {
      store.flush().catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, 'flush pending plugin prefs failed: %{public}s', `${e}`);
      });
    } catch (e) {
    }
  }
}
