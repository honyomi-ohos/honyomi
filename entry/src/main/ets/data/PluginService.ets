import { bundleManager, common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { JsvmSource, PluginManifest, SourcePrefItem, SourcePrefOption } from '../source/JsvmSource';
import { EngineBackend, EngineGateway } from '../jsvm/EngineGateway';
import { PluginPrefs } from '../jsvm/PluginPrefs';
import { SourceRegistry } from '../source/Source';
import { ContentType, PluginRecord } from '../model/Models';
import { Http } from '../net/Http';
import { Util } from '../common/Util';
import { AppKeys } from '../common/AppKeys';
import { AppDb } from './AppDb';
import { MangaRepo, PluginRepo } from './Repos';

const DOMAIN = 0x0002;
const TAG = 'PluginService';

// 最终注册源规格（引擎解析结果，持久化到 plugin.sourcesJson）：
// spec.key 即 manga.sourceKey 引用的注册 key
export interface SourceSpec {
  key: string;
  name: string;
  lang: string;
  baseUrl: string;
  nsfw: boolean;
  supportsLatest: boolean;

  // 空字符串。旧的多源记录可能带 source id，解析时保留。
  sourceId: string;
}

interface RawManifest {
  key?: string;
  name?: string;
  lang?: string;
  version?: string;
  versionCode?: number;
  baseUrl?: string;
  nsfw?: boolean;
  supportsLatest?: boolean;
  minAppVersion?: number;
  dslVersion?: number;
  icon?: string;
  contentType?: string;
}

export interface InstalledPlugin {
  manifest: PluginManifest;
  iconPath: string;
}

export interface RepoEntry {
  key: string;
  name: string;
  lang: string;
  version: string;
  versionCode: number;
  file: string;
  nsfw: boolean;
  icon: string;

  // manga | novel | video；仓库索引未声明时为空字符串（UI 不显示类型角标）
  contentType: string;

  // 仓库索引声明的 sha256（可选），下载后校验插件包完整性
  checksum: string;

  // 插件对应站点首页（manifest.baseUrl）：供安装前预览网站；未声明时为空字符串
  site: string;
}

interface RawRepoEntry {
  key?: string;
  name?: string;
  lang?: string;
  version?: string;
  versionCode?: number;
  file?: string;
  nsfw?: boolean;
  icon?: string;
  contentType?: string;
  checksum?: string;
  site?: string;
  baseUrl?: string;
}

interface RawRepoIndex {
  name?: string;
  website?: string;
  plugins?: RawRepoEntry[];
}

// 插件仓库信息（仓库管理页展示：地址 + 展示名 + 官网）
export interface RepoStoreInfo {
  url: string;
  name: string;
  // 仓库官网（索引声明 website 字段，http(s) 归一化）；未声明为空字符串
  website: string;
}

// manifest.json settings 数组元素（插件静态设置声明：type/key/title/summary/
// default/options/sensitive/hidden）。声明后设置页渲染与写入全部在宿主侧完成，
// 无需拉起 JSVM 引擎；插件可选保留 setPreference 作为引擎运行中的内存态同步钩子。
interface RawManifestSetting {
  type?: string;
  key?: string;
  title?: string;
  summary?: string;
  default?: string;
  options?: RawSettingOption[];
  sensitive?: boolean;
  hidden?: boolean;
}

interface RawSettingOption {
  value?: string;
  label?: string;
}

interface RawManifestSettingsFile {
  settings?: RawManifestSetting[];
}

// 插件包管理：.honyomiplug(zip: manifest.json + main.js) 安装/卸载 + 在线仓库索引
// 所有插件统一运行于 JSVM 隔离引擎（专属 Worker + 本机 C++ JSVM，零 ArkWeb 依赖）。
// 千级插件规模：数据库 plugin 表为元数据索引，启动只注册占位源（不扫盘不拉引擎），
// 引擎在源被实际调用时惰性拉起（ensureEngine 记忆化 + LRU 淘汰，见 JsvmExtensionManager）。
export class PluginService {
  // 宿主支持的插件 DSL 最高版本（与 JSVM 适配层 ADAPTER_JS 的契约保持一致）
  static readonly HOST_DSL_VERSION: number = 2;
  private static pluginsDir: string = '';
  private static cacheDir: string = '';
  private static context: common.UIAbilityContext | undefined = undefined;
  private static runtimeCache: Map<string, string> = new Map();
  private static appVersionCode: number = 1;
  // 调试签名构建（appProvisionType === 'debug'）：放行 http 协议的仓库索引/插件包，release 一律强制 https
  private static debugBuild: boolean = false;
  // 引擎启动记忆化（packageKey → 进行中/已失败的启动 Promise）：
  // 并发调用共享同一次启动；失败保留 rejected 记忆防止全局搜索对坏插件反复重试起引擎，
  // 成功/卸载/重装时清除（LRU 淘汰后可再次拉起）
  private static startPromises: Map<string, Promise<void>> = new Map();
  private static loadAllPromise: Promise<void> | undefined = undefined;

  static init(context: common.UIAbilityContext): void {
    PluginService.pluginsDir = `${context.filesDir}/plugins`;
    PluginService.cacheDir = context.cacheDir;
    PluginService.context = context;
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      PluginService.appVersionCode = bundleInfo.versionCode;
      PluginService.debugBuild = bundleInfo.appInfo !== undefined &&
        bundleInfo.appInfo.appProvisionType === 'debug';
    } catch (e) {
      PluginService.appVersionCode = 1;
      PluginService.debugBuild = false;
    }
    try {
      if (!fs.accessSync(PluginService.pluginsDir)) {
        fs.mkdirSync(PluginService.pluginsDir, true);
      }
    } catch (e) {
    }
    PluginService.cleanStaleTemp();
    PluginService.cleanStaleStaging();
  }

  static parseManifest(text: string): PluginManifest {
    const raw = JSON.parse(text) as RawManifest;
    const key = raw.key ?? '';
    const name = raw.name ?? '';
    // 小写 UUID v4。安装目录、偏好和引擎都按它区分，同一站点可以装多份插件。
    if (!new RegExp('^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').test(key)) {
      throw new Error('plugin_bad_key');
    }
    if (name === '') {
      throw new Error('plugin_missing_name');
    }
    const versionCode = raw.versionCode ?? 0;
    if (versionCode <= 0) {
      throw new Error('plugin_bad_version_code');
    }
    // 版本门禁：DSL 版本过高或要求的应用版本过高时拒绝加载，给出可理解的错误
    const dslVersion = raw.dslVersion ?? 1;
    if (dslVersion > PluginService.HOST_DSL_VERSION) {
      throw new Error(`plugin_dsl_too_new|DSL v${dslVersion} > v${PluginService.HOST_DSL_VERSION}`);
    }
    const minAppVersion = raw.minAppVersion ?? 1;
    if (minAppVersion > PluginService.appVersionCode) {
      throw new Error(`plugin_app_too_old|${minAppVersion}`);
    }
    // icon 仅允许简单文件名（禁止 /、\、.. 等路径穿越），非法时忽略
    let icon = raw.icon ?? '';
    if (icon !== '' && (icon.indexOf('/') >= 0 || icon.indexOf('\\') >= 0 || icon.indexOf('..') >= 0 ||
      !new RegExp('^[A-Za-z0-9_.-]+$').test(icon))) {
      icon = '';
    }
    const manifest: PluginManifest = {
      key: key,
      name: name,
      lang: raw.lang ?? 'multi',
      version: raw.version ?? '1.0.0',
      versionCode: versionCode,
      baseUrl: raw.baseUrl ?? '',
      nsfw: raw.nsfw === true,
      supportsLatest: raw.supportsLatest !== false,
      minAppVersion: minAppVersion,
      dslVersion: dslVersion,
      icon: icon,
      contentType: ContentType.normalize(raw.contentType),
    };
    return manifest;
  }

  // DB 异常时降级为空列表（面板显示"暂无插件"）
  static async listInstalled(): Promise<InstalledPlugin[]> {
    const result: InstalledPlugin[] = [];
    try {
      const records = await PluginRepo.list();
      for (const record of records) {
        const manifest = PluginService.manifestOfRecord(record);
        const item: InstalledPlugin = {
          manifest: manifest,
          iconPath: PluginService.iconUrlOf(manifest),
        };
        result.push(item);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'list installed failed: %{public}s', (e as Error).message);
    }
    return result;
  }

  // 已安装插件列表（异步 DB 版）：读 plugin 元数据索引，不触碰引擎；

  // 从文件选择器 URI 安装插件包
  static async installFromFile(uri: string): Promise<string> {
    const zipPath = `${PluginService.cacheDir}/plugin_install_${Date.now()}_${util.generateRandomUUID()}.honyomiplug`;
    try {
      const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        fs.copyFile(srcFile.fd, zipPath);
      } finally {
        fs.closeSync(srcFile);
      }
    } catch (e) {
      throw new Error(`plugin_read_failed|${(e as Error).message}`);
    }
    try {
      return await PluginService.installZip(zipPath);
    } finally {
      try {
        if (fs.accessSync(zipPath)) {
          fs.unlinkSync(zipPath);
        }
      } catch (e) {
      }
    }
  }

  // 是否调试签名构建：调试态放行 http 协议插件分发（本地调试仓库），release 拒绝
  static isDebugBuild(): boolean {
    return PluginService.debugBuild;
  }

  // 从仓库条目下载并安装：release 强制 https（调试构建放行 http），索引声明 checksum（sha256）时校验完整性
  static async installFromRepo(entry: RepoEntry): Promise<string> {
    if (entry.file.startsWith('http://') && !PluginService.isDebugBuild()) {
      throw new Error('plugin_repo_not_https');
    }
    const buffer: ArrayBuffer = await Http.getBuffer(entry.file, undefined);
    if (entry.checksum !== '') {
      const actual: string = await PluginService.sha256Hex(buffer);
      if (actual !== entry.checksum.toLowerCase()) {
        throw new Error('plugin_checksum_mismatch');
      }
    }
    const zipPath =
      `${PluginService.cacheDir}/plugin_repo_${entry.key}_${Date.now()}_${util.generateRandomUUID()}.honyomiplug`;
    try {
      const file = fs.openSync(zipPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      try {
        fs.writeSync(file.fd, buffer);
      } finally {
        try {
          fs.closeSync(file);
        } catch (e2) {
        }
      }
    } catch (e) {
      throw new Error(`plugin_write_failed|${Util.errSummary(e)}`);
    }
    try {
      return await PluginService.installZip(zipPath);
    } finally {
      try {
        if (fs.accessSync(zipPath)) {
          fs.unlinkSync(zipPath);
        }
      } catch (e) {
      }
    }
  }

  static async uninstall(key: string): Promise<void> {
    const packageKey = PluginService.packageKeyOf(key);
    PluginService.unregisterPackage(packageKey);
    // 清除引擎启动记忆（含失败 rejected 记忆），重装后可重新拉起
    PluginService.startPromises.delete(packageKey);
    // 卸载即销毁插件持久化数据：明文偏好 blob + SecureStore 条目 + 敏感键注册表一并清除，
    // 重装同 key（或安装仿冒同 key 的包）不继承旧值
    if (PluginService.context !== undefined) {
      try {
        await PluginPrefs.ensureInit(PluginService.context);
        PluginPrefs.removePackage(packageKey);
        PluginPrefs.removeSecureEntries(packageKey);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'remove secure prefs of %{public}s failed: %{public}s',
          packageKey, (e as Error).message);
      }
    }
    // 引擎后端未注册（预览器等场景）时无引擎可卸载，直接跳过
    const engine = EngineGateway.get();
    if (engine !== undefined) {
      await engine.unloadExtension(packageKey);
    }
    // 元数据索引同步移除；DB 不可用时降级告警（残留记录重装时被覆盖）
    try {
      await PluginRepo.remove(packageKey);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'remove plugin record failed: %{public}s', (e as Error).message);
    }
    const dir = `${PluginService.pluginsDir}/${packageKey}`;
    try {
      if (fs.accessSync(dir)) {
        fs.rmdirSync(dir);
      }
    } catch (e) {
      throw new Error(`plugin_uninstall_failed|${Util.errSummary(e)}`);
    }
    // 注意：数据库中该源的漫画数据保留，重装同 key 插件后自动恢复
  }

  // 供 ImageCache 等消费方在冷启动竞态下等待插件源注册完成
  static ready(): Promise<void> {
    return PluginService.loadAllPromise ?? Promise.resolve();
  }

  // 记忆化：并发/重复调用共享同一次加载
  static async loadAll(): Promise<void> {
    if (PluginService.loadAllPromise === undefined) {
      PluginService.loadAllPromise = PluginService.doLoadAll();
    }
    return PluginService.loadAllPromise;
  }

  // 失败保留 rejected 记忆（防全局搜索风暴），成功/卸载/重装时清除
  static async ensureEngine(packageKey: string): Promise<void> {
    const engine = EngineGateway.get();
    if (engine !== undefined && engine.isLoaded(packageKey)) {
      return;
    }
    const pending = PluginService.startPromises.get(packageKey);
    if (pending !== undefined) {
      await pending;
      return;
    }
    const promise = PluginService.doStartEngine(packageKey);
    PluginService.startPromises.set(packageKey, promise);
    await promise;
    // 成功：清除记忆（LRU 淘汰后再次调用可重新拉起）
    PluginService.startPromises.delete(packageKey);
  }

  // 等待全部插件源注册完成（尚未开始加载时立即返回）；

  static markDirty(): void {
    AppStorage.setOrCreate(AppKeys.PLUGINS_DIRTY, (AppStorage.get<number>(AppKeys.PLUGINS_DIRTY) ?? 0) + 1);
  }

  // 加载全部插件：注册占位源（DB 元数据索引，不扫盘不拉引擎）+ 预热在库源；

  static async fetchRepo(url: string): Promise<RepoEntry[]> {
    const text = await Http.get(url, undefined);
    return PluginService.parseRepoIndex(url, JSON.parse(text) as RawRepoIndex);
  }

  // 仓库索引 JSON → 条目列表（fetchRepo / fetchStoreInfo 共用解析）
  private static parseRepoIndex(url: string, raw: RawRepoIndex): RepoEntry[] {
    const entries: RepoEntry[] = [];
    const list = raw.plugins;
    if (Array.isArray(list)) {
      for (const item of list) {
        const key = item.key ?? '';
        const file = item.file ?? '';
        if (key === '' || file === '') {
          continue;
        }
        const entry: RepoEntry = {
          key: key,
          name: item.name ?? key,
          lang: item.lang ?? 'multi',
          version: item.version ?? '',
          versionCode: item.versionCode ?? 0,
          file: PluginService.resolveRepoFile(url, file),
          nsfw: item.nsfw === true,
          icon: item.icon !== undefined && item.icon !== '' ?
            PluginService.resolveRepoIcon(url, item.icon) : '',
          contentType: item.contentType !== undefined && item.contentType !== null ?
            ContentType.normalize(item.contentType) : '',
          checksum: item.checksum ?? '',
          site: PluginService.normalizeSiteUrl(item.site !== undefined && item.site !== '' ?
            item.site : item.baseUrl),
        };
        entries.push(entry);
      }
    }
    return entries;
  }

  // 所有插件一律 jsvm 引擎：main.js 前固定拼接共享运行时（rawfile plugin_runtime_jsvm.js）
  static composeScript(mainJs: string): string {
    return `${PluginService.getRuntime('jsvm')}\n;\n${mainJs}`;
  }

  // 仓库索引信息（添加仓库时校验 + 管理页展示）：
  // 拉取索引并要求 plugins 数组可解析；展示名取索引声明 name，缺省回退地址主机名；
  // 官网取索引声明 website（仅接受 http(s) 绝对地址，其余视为未声明）
  static async fetchStoreInfo(url: string): Promise<RepoStoreInfo> {
    if (url.startsWith('http://') && !PluginService.isDebugBuild()) {
      throw new Error('plugin_repo_not_https');
    }
    const text = await Http.get(url, undefined);
    const raw = JSON.parse(text) as RawRepoIndex;
    if (raw === null || raw === undefined || !Array.isArray(raw.plugins)) {
      throw new Error('plugin_repo_bad_index');
    }
    PluginService.parseRepoIndex(url, raw);
    let name = typeof raw.name === 'string' ? raw.name : '';
    if (name === '') {
      const m = new RegExp('^https?://([^/?#]+)').exec(url);
      name = m !== null ? m[1] : url;
    }
    const info: RepoStoreInfo = {
      url: url,
      name: name,
      website: PluginService.normalizeSiteUrl(raw.website),
    };
    return info;
  }

  // 多仓库条目合并（插件商店支持多仓库）：同 key 插件保留 versionCode 更高的条目
  static mergeRepoEntries(lists: RepoEntry[][]): RepoEntry[] {
    const byKey = new Map<string, RepoEntry>();
    for (const list of lists) {
      for (const entry of list) {
        const existing = byKey.get(entry.key);
        if (existing === undefined || entry.versionCode > existing.versionCode) {
          byKey.set(entry.key, entry);
        }
      }
    }
    const merged: RepoEntry[] = [];
    for (const entry of byKey.values()) {
      merged.push(entry);
    }
    return merged;
  }

  // 清理上次崩溃/失败安装遗留的 staging/备份目录（.staging_*/.old_*，含 manifest.json 会被误识别为插件）
  private static cleanStaleStaging(): void {
    let names: string[] = [];
    try {
      if (!fs.accessSync(PluginService.pluginsDir)) {
        return;
      }
      names = fs.listFileSync(PluginService.pluginsDir);
    } catch (e) {
      return;
    }
    for (const name of names) {
      if (!name.startsWith('.staging_') && !name.startsWith('.old_')) {
        continue;
      }
      const path = `${PluginService.pluginsDir}/${name}`;
      try {
        fs.rmdirSync(path);
        hilog.info(DOMAIN, TAG, 'cleaned stale staging: %{public}s', name);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'clean stale staging failed: %{public}s %{public}s', name, (e as Error).message);
      }
    }
  }

  // 预热在库源：对"书架有漫画且声明 getHeaders"的插件包立即拉引擎并预热图片头，

  // 清理历史失败安装遗留的临时文件/目录（plugin_extract_*/plugin_install_*/plugin_repo_*）
  private static cleanStaleTemp(): void {
    let names: string[] = [];
    try {
      if (!fs.accessSync(PluginService.cacheDir)) {
        return;
      }
      names = fs.listFileSync(PluginService.cacheDir);
    } catch (e) {
      return;
    }
    for (const name of names) {
      if (!name.startsWith('plugin_extract_') && !name.startsWith('plugin_install_') &&
        !name.startsWith('plugin_repo_')) {
        continue;
      }
      const path = `${PluginService.cacheDir}/${name}`;
      try {
        if (fs.statSync(path).isDirectory()) {
          fs.rmdirSync(path);
        } else {
          fs.unlinkSync(path);
        }
        hilog.info(DOMAIN, TAG, 'cleaned stale temp: %{public}s', name);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'clean stale temp failed: %{public}s %{public}s', name, (e as Error).message);
      }
    }
  }

  // 惰性引擎启动（记忆化）：引擎已加载直接返回；进行中共享同一次启动；

  // 拉起单个插件引擎：读盘 manifest 门禁 → 组装脚本 → prefs 回注 → loadExtension

  private static async doLoadAll(): Promise<void> {
    // 元数据索引在数据库中：等待数据库就绪（EntryAbility 已发起 ready，此处共享同一实例）
    if (PluginService.context !== undefined) {
      await AppDb.ready(PluginService.context);
    }
    let records: PluginRecord[] = [];
    try {
      records = await PluginRepo.list();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read plugin index failed: %{public}s', (e as Error).message);
      return;
    }
    if (records.length === 0) {
      return;
    }
    // 只注册占位源：nsfw/methods/supportsLatest 等来自持久化元数据，
    // 引擎在源被实际调用时经 engineStarter 惰性拉起
    for (const record of records) {
      PluginService.registerPlaceholders(record);
    }
    hilog.info(DOMAIN, TAG, 'registered %{public}d plugin packages from db index', records.length);
    // 预热：仅为"在库漫画且导出 getHeaders"的插件包拉引擎（封面需要 Referer/Cookie）
    await PluginService.prewarmLibrary();
  }

  // 插件敏感偏好声明注册（引擎启动后调用）：读取 getSettingsSchema，

  // 保证冷启动书架封面带 Referer/Cookie；其余插件保持惰性
  private static async prewarmLibrary(): Promise<void> {
    if (EngineGateway.get() === undefined) {
      // 预览器等场景无引擎后端：占位源保持惰性
      return;
    }
    try {
      const counts = await MangaRepo.countBySource();
      const packageKeys = new Set<string>();
      for (const source of SourceRegistry.all()) {
        if (source instanceof JsvmSource && (counts[source.key] ?? 0) > 0 &&
          source.hasMethod('getHeaders')) {
          packageKeys.add(source.packageKey);
        }
      }
      for (const packageKey of packageKeys) {
        try {
          await PluginService.ensureEngine(packageKey);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'prewarm %{public}s failed: %{public}s',
            packageKey, (e as Error).message);
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'prewarm library failed: %{public}s', (e as Error).message);
    }
  }

  // ---------------- 仓库索引 ----------------

  // → 解析最终源规格 → 同步注册表（就地升级占位源）→ 元数据落库 → 预热图片头
  private static async doStartEngine(packageKey: string): Promise<void> {
    const dir = `${PluginService.pluginsDir}/${packageKey}`;
    let manifestText = '';
    let scriptText = '';
    try {
      manifestText = fs.readTextSync(`${dir}/manifest.json`);
      scriptText = fs.readTextSync(`${dir}/main.js`);
    } catch (e) {
      throw new Error(`plugin_start_read_failed|${Util.errSummary(e)}`);
    }
    const manifest = PluginService.parseManifest(manifestText);
    const script = PluginService.composeScript(scriptText);
    // 插件偏好持久化：确保 Preferences 就绪，并把已存的 __PREFS_STORE__ 注回引擎
    let seed = '';
    if (PluginService.context !== undefined) {
      try {
        await PluginPrefs.ensureInit(PluginService.context);
        seed = PluginPrefs.seedScript(manifest.key);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'plugin prefs init failed: %{public}s', (e as Error).message);
      }
    }
    const engine: EngineBackend = EngineGateway.require();
    const info = await engine.loadExtension(manifest.key, script, seed);
    const specs = PluginService.resolveSpecs(manifest);
    PluginService.syncRegistry(manifest, info.methods, specs);
    // 元数据落库（安装/升级/引擎重启均幂等覆盖）
    await PluginService.persistRecord(manifest, info.methods, specs);
    // 插件敏感偏好声明注册：getSettingsSchema 中 sensitive: true / type: 'password'
    // 的键登记到 SecureStore 分流注册表（见 PluginPrefs.registerSensitiveKeys）
    PluginService.registerSensitivePrefKeys(manifest.key);
    // 插件可选导出 getHeaders：声明后图片经宿主 http 管线加载（Referer/Cookie）
    for (const spec of specs) {
      const src = SourceRegistry.get(spec.key);
      if (src instanceof JsvmSource) {
        src.warmImageHeaders();
      }
    }
    hilog.info(DOMAIN, TAG, 'jsvm engine started: %{public}s v%{public}s (%{public}d sources, mem %{public}d)',
      manifest.key, manifest.version, specs.length, engine.memoryBytes(manifest.key));
  }

  // 把 sensitive 声明的键登记到 PluginPrefs 注册表，供 persist 分流 / seed 回注。
  // manifest settings 静态声明优先（无需引擎）；未声明时回退运行期 getSettingsSchema 契约。
  private static registerSensitivePrefKeys(packageKey: string): void {
    PluginService.declaredSettings(packageKey).then((items: SourcePrefItem[]): void => {
      const keys: string[] = [];
      for (const item of items) {
        if (item.sensitive) {
          keys.push(item.key);
        }
      }
      if (keys.length > 0) {
        PluginPrefs.registerSensitiveKeys(packageKey, keys);
        return;
      }
      PluginService.registerSensitivePrefKeysLegacy(packageKey);
    }).catch((_e: Error): void => {
      PluginService.registerSensitivePrefKeysLegacy(packageKey);
    });
  }

  // 运行期 getSettingsSchema 契约的敏感键注册（未迁移 manifest settings 的插件）
  private static registerSensitivePrefKeysLegacy(packageKey: string): void {
    const src = SourceRegistry.get(packageKey);
    if (!(src instanceof JsvmSource) || !src.hasMethod('getSettingsSchema')) {
      return;
    }
    src.getSettingsSchema().then((schema: SourcePrefItem[]): void => {
      const keys: string[] = [];
      for (const item of schema) {
        if (item.sensitive) {
          keys.push(item.key);
        }
      }
      PluginPrefs.registerSensitiveKeys(packageKey, keys);
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'read sensitive pref schema of %{public}s failed: %{public}s',
        packageKey, e.message);
    });
  }

  // manifest 静态声明的插件设置：读安装目录 manifest.json 的 settings 数组，
  // 合并 PluginPrefs 当前值 → SourcePrefItem[]。全程不触碰 JSVM 引擎。
  // 无声明/解析失败返回空数组（调用方回退运行期 getSettingsSchema 契约）。
  static async declaredSettings(packageKey: string): Promise<SourcePrefItem[]> {
    let manifestText = '';
    try {
      manifestText = fs.readTextSync(`${PluginService.pluginsDir}/${packageKey}/manifest.json`);
    } catch (e) {
      return [];
    }
    let rawSettings: RawManifestSetting[] = [];
    try {
      const parsed = JSON.parse(manifestText) as RawManifestSettingsFile;
      if (parsed !== null && parsed !== undefined && Array.isArray(parsed.settings)) {
        rawSettings = parsed.settings;
      }
    } catch (e) {
      return [];
    }
    const items: SourcePrefItem[] = [];
    const sensitiveKeys: string[] = [];
    for (const raw of rawSettings) {
      const item = PluginService.toDeclaredPrefItem(raw);
      if (item === undefined) {
        continue;
      }
      if (item.sensitive) {
        sensitiveKeys.push(item.key);
      }
      items.push(item);
    }
    if (items.length === 0) {
      return [];
    }
    if (PluginService.context !== undefined) {
      try {
        await PluginPrefs.ensureInit(PluginService.context);
      } catch (e) {
        // 偏好存储不可用：当前值降级为声明默认值
      }
      const stored = PluginPrefs.currentValues(packageKey);
      for (const item of items) {
        const v = stored[item.key];
        if (typeof v === 'string') {
          item.value = v;
        } else if (v !== undefined && v !== null) {
          item.value = `${v}`;
        }
      }
      if (sensitiveKeys.length > 0) {
        PluginPrefs.registerSensitiveKeys(packageKey, sensitiveKeys);
      }
    }
    return items;
  }

  // manifest 静态设置写入：直接落 PluginPrefs（不拉起引擎）；引擎恰在运行时
  // 转发 setPreference 同步插件内存态（best-effort，见 JsvmSource.syncPreferenceLive）
  static async setDeclaredPref(packageKey: string, key: string, value: string): Promise<void> {
    if (PluginService.context !== undefined) {
      await PluginPrefs.ensureInit(PluginService.context);
      PluginPrefs.updatePref(packageKey, key, value);
    }
    const src = SourceRegistry.get(packageKey);
    if (src instanceof JsvmSource) {
      await src.syncPreferenceLive(key, value);
    }
  }

  // 单条 manifest 静态设置声明 → SourcePrefItem（类型白名单外的条目丢弃）
  private static toDeclaredPrefItem(raw: RawManifestSetting): SourcePrefItem | undefined {
    const key = raw.key ?? '';
    if (key === '') {
      return undefined;
    }
    let type = raw.type ?? 'edit';
    if (type !== 'switch' && type !== 'select' && type !== 'edit' && type !== 'password') {
      return undefined;
    }
    // 敏感声明：sensitive: true 或 type: 'password'（password 渲染为 edit 行）
    let sensitive = raw.sensitive === true;
    if (type === 'password') {
      sensitive = true;
      type = 'edit';
    }
    const options: SourcePrefOption[] = [];
    if (Array.isArray(raw.options)) {
      for (const o of raw.options) {
        if (o !== undefined && o.value !== undefined) {
          const opt: SourcePrefOption = {
            value: o.value,
            label: o.label ?? o.value,
          };
          options.push(opt);
        }
      }
    }
    const item: SourcePrefItem = {
      type: type,
      key: key,
      title: raw.title ?? key,
      summary: raw.summary ?? '',
      value: raw.default ?? '',
      options: options,
      sensitive: sensitive,
      hidden: raw.hidden === true,
    };
    return item;
  }

  // ---------------- 内部实现 ----------------

  // 仓库索引声明的站点地址归一化：仅接受 http(s) 绝对地址，其余视为未声明
  private static normalizeSiteUrl(url: string | undefined): string {
    const u = url ?? '';
    if (u === '') {
      return '';
    }
    return /^https?:\/\//.test(u) ? u : '';
  }

  // 插件运行时 shim：rawfile 产物由 plugins/runtime/src 经 esbuild 打包直出
  // 并随仓库提交（文件名是宿主/沙箱稳定契约），此处仅按名读取缓存
  private static getRuntime(name: string): string {
    const cached = PluginService.runtimeCache.get(name);
    if (cached !== undefined) {
      return cached;
    }
    if (!new RegExp('^[a-z0-9_]+$').test(name) || PluginService.context === undefined) {
      hilog.warn(DOMAIN, TAG, 'invalid plugin runtime name: %{public}s', name);
      throw new Error(`plugin_runtime_invalid|${name}`);
    }
    try {
      const data = PluginService.context.resourceManager
        .getRawFileContentSync(`plugin_runtime_${name}.js`);
      const text = util.TextDecoder.create('utf-8').decodeToString(data);
      PluginService.runtimeCache.set(name, text);
      return text;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'load plugin runtime %{public}s failed: %{public}s', name, (e as Error).message);
      throw new Error(`plugin_runtime_missing|${name}`);
    }
  }

  private static async sha256Hex(data: ArrayBuffer): Promise<string> {
    try {
      if (canIUse('SystemCapability.Security.CryptoFramework.MessageDigest')) {
        const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
        await md.update({ data: new Uint8Array(data) });
        const digest: cryptoFramework.DataBlob = await md.digest();
        let out = '';
        for (let i = 0; i < digest.data.length; i++) {
          const byte: number = digest.data[i];
          out += byte < 16 ? `0${byte.toString(16)}` : byte.toString(16);
        }
        return out;
      }
      throw new Error('crypto unavailable');
    } catch (e) {
      throw new Error(`plugin_checksum_failed|${Util.errSummary(e)}`);
    }
  }

  // 先解压/复制到临时目录，全部成功后再原子替换旧插件目录，失败保留旧插件
  private static async installZip(zipPath: string): Promise<string> {
    const extractDir = `${PluginService.cacheDir}/plugin_extract_${Date.now()}_${util.generateRandomUUID()}`;
    try {
      if (!fs.accessSync(extractDir)) {
        fs.mkdirSync(extractDir, true);
      }
      await zlib.decompressFile(zipPath, extractDir);
    } catch (e) {
      throw new Error(`plugin_extract_failed|${Util.errSummary(e)}`);
    }
    let stagingDir = '';
    try {
      const rootDir = PluginService.findPluginRoot(extractDir);
      let manifestText = '';
      try {
        manifestText = fs.readTextSync(`${rootDir}/manifest.json`);
      } catch (e) {
        throw new Error(`plugin_manifest_read_failed|${Util.errSummary(e)}`);
      }
      const manifest = PluginService.parseManifest(manifestText);
      let mainExists = false;
      try {
        mainExists = fs.accessSync(`${rootDir}/main.js`);
      } catch (e) {
      }
      if (!mainExists) {
        throw new Error('plugin_missing_main');
      }
      // 同名 key 已被 name 不同的其它插件占用：无包签名校验下，仿冒既有插件 key 的包
      // 会在安装后继承其持久化偏好（含 SecureStore 种子并入的敏感值），必须拒绝；
      // name 相同视为同插件升级/重装，放行
      const destDir = `${PluginService.pluginsDir}/${manifest.key}`;
      if (fs.accessSync(destDir)) {
        let oldName = '';
        try {
          const oldManifest = PluginService.parseManifest(fs.readTextSync(`${destDir}/manifest.json`));
          oldName = oldManifest.name;
        } catch (_e) {
        }
        if (oldName !== '' && oldName !== manifest.name) {
          throw new Error(`plugin_key_conflict|${manifest.key}`);
        }
      }
      // 先完整复制到 staging 目录，成功后再删除旧目录并 rename 新目录
      stagingDir = `${PluginService.pluginsDir}/.staging_${manifest.key}_${Date.now()}_${util.generateRandomUUID()}`;
      try {
        fs.mkdirSync(stagingDir, true);
        fs.copyFileSync(`${rootDir}/manifest.json`, `${stagingDir}/manifest.json`);
        fs.copyFileSync(`${rootDir}/main.js`, `${stagingDir}/main.js`);
        if (manifest.icon !== '' && fs.accessSync(`${rootDir}/${manifest.icon}`)) {
          fs.copyFileSync(`${rootDir}/${manifest.icon}`, `${stagingDir}/${manifest.icon}`);
        }
      } catch (e) {
        throw new Error(`plugin_stage_failed|${Util.errSummary(e)}`);
      }
      const backupDir = `${PluginService.pluginsDir}/.old_${manifest.key}_${util.generateRandomUUID()}`;
      let swapped = false;
      try {
        if (fs.accessSync(destDir)) {
          fs.renameSync(destDir, backupDir);
          swapped = true;
        }
      } catch (e) {
        throw new Error(`plugin_replace_failed|${e}`);
      }
      try {
        fs.renameSync(stagingDir, destDir);
        stagingDir = '';
      } catch (e) {
        if (swapped) {
          try {
            fs.renameSync(backupDir, destDir);
          } catch (e2) {
          }
        }
        throw new Error(`plugin_replace_failed|${(e as Error).message}`);
      }
      try {
        if (swapped && fs.accessSync(backupDir)) {
          fs.rmdirSync(backupDir);
        }
      } catch (e) {
      }
      // 重装/升级：清除旧启动记忆（含失败 rejected 记忆）后拉起引擎并同步注册表/元数据
      PluginService.startPromises.delete(manifest.key);
      await PluginService.doStartEngine(manifest.key);
      hilog.info(DOMAIN, TAG, 'plugin installed: %{public}s', manifest.key);
      return manifest.key;
    } finally {
      try {
        if (stagingDir !== '' && fs.accessSync(stagingDir)) {
          fs.rmdirSync(stagingDir);
        }
      } catch (e) {
      }
      try {
        if (fs.accessSync(extractDir)) {
          fs.rmdirSync(extractDir);
        }
      } catch (e) {
      }
    }
  }

  private static findPluginRoot(extractDir: string): string {
    try {
      if (fs.accessSync(`${extractDir}/manifest.json`)) {
        return extractDir;
      }
      const names: string[] = fs.listFileSync(extractDir);
      for (const name of names) {
        const sub = `${extractDir}/${name}`;
        const stat = fs.statSync(sub);
        if (stat.isDirectory() && fs.accessSync(`${sub}/manifest.json`)) {
          return sub;
        }
      }
    } catch (e) {
    }
    throw new Error('plugin_no_manifest');
  }

  // 仓库索引里的 file 可以是绝对 URL，也可以相对 index.json 所在目录；release 强制 https，调试构建放行 http。
  private static resolveRepoFile(indexUrl: string, file: string): string {
    if (file.startsWith('http://')) {
      // 明文 http 分发插件包等同远程代码注入面：仅调试签名构建放行，release 一律拒绝
      if (!PluginService.isDebugBuild()) {
        throw new Error('plugin_repo_entry_not_https');
      }
      return file;
    }
    if (file.startsWith('https://')) {
      return file;
    }
    // 相对基准取 indexUrl 最后一个路径斜杠之前；裸源地址（http://host:port，无路径）时
    // lastIndexOf('/') 会命中协议分隔符吞掉主机名，此时基准应为根目录（补尾斜杠）
    const schemeEnd = indexUrl.indexOf('://');
    const pathStart = schemeEnd >= 0 ? schemeEnd + 3 : 0;
    const base = indexUrl.indexOf('/', pathStart) < 0 ? `${indexUrl}/` :
      indexUrl.substring(0, indexUrl.lastIndexOf('/') + 1);
    let rel = file;
    while (rel.startsWith('./')) {
      rel = rel.substring(2);
    }
    return `${base}${rel}`;
  }

  // 图标地址解析失败（非 https）时降级为无图标，不中断整个仓库列表
  private static resolveRepoIcon(indexUrl: string, icon: string): string {
    try {
      return PluginService.resolveRepoFile(indexUrl, icon);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'skip non-https repo icon: %{public}s', icon);
      return '';
    }
  }

  private static packageKeyOf(key: string): string {
    const existing = SourceRegistry.get(key);
    if (existing instanceof JsvmSource) {
      return existing.packageKey;
    }
    return key;
  }

  private static unregisterPackage(packageKey: string): void {
    const keys: string[] = [];
    for (const source of SourceRegistry.all()) {
      if (source instanceof JsvmSource && source.packageKey === packageKey) {
        keys.push(source.key);
      } else if (source.key === packageKey) {
        keys.push(source.key);
      }
    }
    for (const key of keys) {
      SourceRegistry.unregister(key);
    }
  }

  // 一个包注册一个源，key 就是包 key。
  private static resolveSpecs(manifest: PluginManifest): SourceSpec[] {
    const spec: SourceSpec = {
      key: manifest.key,
      name: manifest.name,
      lang: manifest.lang,
      baseUrl: manifest.baseUrl,
      nsfw: manifest.nsfw,
      supportsLatest: manifest.supportsLatest,
      sourceId: '',
    };
    const specs: SourceSpec[] = [];
    specs.push(spec);
    return specs;
  }

  // 注册表同步：已有占位源就地升级（同 key 同 sourceId 保持实例稳定），
  // 缺失的补注册，插件已移除的子源注销
  private static syncRegistry(manifest: PluginManifest, methods: string[], specs: SourceSpec[]): void {
    const iconUrl = PluginService.iconUrlOf(manifest);
    const specKeys = new Set<string>();
    for (const spec of specs) {
      specKeys.add(spec.key);
      const child = PluginService.manifestForSpec(manifest, spec);
      const existing = SourceRegistry.get(spec.key);
      if (existing instanceof JsvmSource && existing.packageKey === manifest.key &&
        existing.sourceId === spec.sourceId) {
        existing.upgrade(child, methods);
        existing.setEngineStarter((): Promise<void> => PluginService.ensureEngine(manifest.key));
        continue;
      }
      const src = new JsvmSource(child, methods, manifest.key, spec.sourceId, iconUrl);
      src.setEngineStarter((): Promise<void> => PluginService.ensureEngine(manifest.key));
      SourceRegistry.register(src);
    }
    // 子源已从插件中移除：注销残留注册
    for (const source of SourceRegistry.all()) {
      if (source instanceof JsvmSource && source.packageKey === manifest.key && !specKeys.has(source.key)) {
        SourceRegistry.unregister(source.key);
      }
    }
  }

  // 占位源注册：DB 元数据 → JsvmSource（不拉引擎），engineStarter 注入惰性启动
  private static registerPlaceholders(record: PluginRecord): void {
    const base = PluginService.manifestOfRecord(record);
    const methods = PluginService.parseStringArray(record.methodsJson);
    let specs = PluginService.parseSpecs(record.sourcesJson);
    if (specs.length === 0) {
      // 索引缺源规格（异常数据兜底）：按单源处理
      const spec: SourceSpec = {
        key: record.key,
        name: record.name,
        lang: record.lang,
        baseUrl: record.baseUrl,
        nsfw: record.nsfw,
        supportsLatest: base.supportsLatest,
        sourceId: '',
      };
      specs = [spec];
    }
    const iconUrl = PluginService.iconUrlOf(base);
    for (const spec of specs) {
      const manifest = PluginService.manifestForSpec(base, spec);
      const src = new JsvmSource(manifest, methods, record.key, spec.sourceId, iconUrl);
      src.setEngineStarter((): Promise<void> => PluginService.ensureEngine(record.key));
      SourceRegistry.register(src);
    }
  }

  // plugin 表记录 → 包级 manifest（占位源/详情页展示用）
  private static manifestOfRecord(record: PluginRecord): PluginManifest {
    const manifest: PluginManifest = {
      key: record.key,
      name: record.name,
      lang: record.lang,
      version: record.version,
      versionCode: record.versionCode,
      baseUrl: record.baseUrl,
      nsfw: record.nsfw,
      supportsLatest: record.supportsLatest,
      minAppVersion: record.minAppVersion,
      dslVersion: record.dslVersion,
      icon: record.icon,
      contentType: ContentType.normalize(record.contentType),
    };
    return manifest;
  }

  // 包级 manifest + 源规格 → 注册用 manifest（spec 字段优先，空值回退包级）
  private static manifestForSpec(base: PluginManifest, spec: SourceSpec): PluginManifest {
    const manifest: PluginManifest = {
      key: spec.key,
      name: spec.name !== '' ? spec.name : base.name,
      lang: spec.lang !== '' ? spec.lang : base.lang,
      version: base.version,
      versionCode: base.versionCode,
      baseUrl: spec.baseUrl !== '' ? spec.baseUrl : base.baseUrl,
      nsfw: spec.nsfw,
      supportsLatest: spec.supportsLatest,
      minAppVersion: base.minAppVersion,
      dslVersion: base.dslVersion,
      icon: base.icon,
      contentType: ContentType.normalize(base.contentType),
    };
    return manifest;
  }

  // 持久化元数据索引：引擎解析结果（方法表 + 最终源规格）落库
  private static async persistRecord(manifest: PluginManifest, methods: string[],
    specs: SourceSpec[]): Promise<void> {
    const record = new PluginRecord();
    record.key = manifest.key;
    record.name = manifest.name;
    record.lang = manifest.lang;
    record.version = manifest.version;
    record.versionCode = manifest.versionCode;
    record.baseUrl = manifest.baseUrl;
    record.nsfw = manifest.nsfw;
    record.supportsLatest = manifest.supportsLatest;
    record.minAppVersion = manifest.minAppVersion;
    record.dslVersion = manifest.dslVersion;
    record.icon = manifest.icon;
    record.contentType = manifest.contentType;
    record.methodsJson = JSON.stringify(methods);
    record.sourcesJson = JSON.stringify(specs);
    record.installedAt = Date.now();
    await PluginRepo.upsert(record);
  }

  // sourcesJson → SourceSpec[]（损坏/缺失字段容忍，逐项校验归一）
  private static parseSpecs(sourcesJson: string): SourceSpec[] {
    let parsed: SourceSpec[] = [];
    try {
      const raw = JSON.parse(sourcesJson) as SourceSpec[];
      if (Array.isArray(raw)) {
        parsed = raw;
      }
    } catch (e) {
      return [];
    }
    const specs: SourceSpec[] = [];
    for (const item of parsed) {
      if (item === undefined || item === null || typeof item.key !== 'string' || item.key === '') {
        continue;
      }
      const spec: SourceSpec = {
        key: item.key,
        name: typeof item.name === 'string' ? item.name : '',
        lang: typeof item.lang === 'string' ? item.lang : 'multi',
        baseUrl: typeof item.baseUrl === 'string' ? item.baseUrl : '',
        nsfw: item.nsfw === true,
        supportsLatest: item.supportsLatest === true,
        sourceId: typeof item.sourceId === 'string' ? item.sourceId : '',
      };
      specs.push(spec);
    }
    return specs;
  }

  // methodsJson → string[]（损坏数据容忍）
  private static parseStringArray(rawJson: string): string[] {
    let parsed: string[] = [];
    try {
      const raw = JSON.parse(rawJson) as string[];
      if (Array.isArray(raw)) {
        parsed = raw;
      }
    } catch (e) {
      return [];
    }
    const out: string[] = [];
    for (const item of parsed) {
      if (typeof item === 'string') {
        out.push(item);
      }
    }
    return out;
  }

  // 插件图标 file:// 路径；包内无图标时返回空字符串
  private static iconUrlOf(manifest: PluginManifest): string {
    if (manifest.icon === '') {
      return '';
    }
    const p = `${PluginService.pluginsDir}/${manifest.key}/${manifest.icon}`;
    try {
      return fs.accessSync(p) ? `file://${p}` : '';
    } catch (e) {
      return '';
    }
  }
}
