import { common, bundleManager } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import zlib from '@ohos.zlib';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { PluginManifest, JsvmSource, CompiledSourceInfo } from '../source/JsvmSource';
import { JsvmExtensionManager } from '../jsvm/JsvmExtensionManager';
import { PluginPrefs } from '../jsvm/PluginPrefs';
import { SourceRegistry } from '../source/Source';
import { ContentType } from '../model/Models';
import { Http } from '../net/Http';

const DOMAIN = 0x0002;
const TAG = 'PluginService';

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
  runtime?: string;
  engine?: string;
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
}

interface RawRepoIndex {
  plugins?: RawRepoEntry[];
}

// 插件包管理：.honyomiplug(zip: manifest.json + main.js) 安装/卸载 + 在线仓库索引
// 所有插件统一运行于 JSVM 隔离引擎（专属 Worker + 本机 C++ JSVM，零 ArkWeb 依赖）
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

  static parseManifest(text: string): PluginManifest {
    const raw = JSON.parse(text) as RawManifest;
    const key = raw.key ?? '';
    const name = raw.name ?? '';
    if (!new RegExp('^[a-z0-9_]+$').test(key)) {
      throw new Error('plugin_bad_key');
    }
    if (name === '') {
      throw new Error('plugin_missing_name');
    }
    const versionCode = raw.versionCode ?? 0;
    if (versionCode <= 0) {
      throw new Error('plugin_bad_version_code');
    }
    // 引擎门禁：唯一支持的执行引擎是 jsvm
    const engine = raw.engine ?? 'jsvm';
    if (engine !== 'jsvm') {
      throw new Error(`plugin_bad_engine|${engine}`);
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
      runtime: raw.runtime ?? '',
      engine: engine,
      contentType: ContentType.normalize(raw.contentType),
    };
    return manifest;
  }

  static listInstalled(): InstalledPlugin[] {
    const result: InstalledPlugin[] = [];
    let names: string[] = [];
    try {
      if (!fs.accessSync(PluginService.pluginsDir)) {
        return result;
      }
      names = fs.listFileSync(PluginService.pluginsDir);
    } catch (e) {
      return result;
    }
    for (const dir of names) {
      const manifestPath = `${PluginService.pluginsDir}/${dir}/manifest.json`;
      try {
        if (!fs.accessSync(manifestPath)) {
          continue;
        }
        const manifest = PluginService.parseManifest(fs.readTextSync(manifestPath));
        const iconPath = `${PluginService.pluginsDir}/${dir}/${manifest.icon}`;
        const item: InstalledPlugin = {
          manifest: manifest,
          iconPath: manifest.icon !== '' && fs.accessSync(iconPath) ? `file://${iconPath}` : '',
        };
        result.push(item);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'skip invalid plugin %{public}s: %{public}s', dir, (e as Error).message);
      }
    }
    return result;
  }

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
    const zipPath = `${PluginService.cacheDir}/plugin_repo_${entry.key}_${Date.now()}_${util.generateRandomUUID()}.honyomiplug`;
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
      throw new Error(`plugin_write_failed|${e}`);
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
    await JsvmExtensionManager.unloadExtension(packageKey);
    const dir = `${PluginService.pluginsDir}/${packageKey}`;
    try {
      if (fs.accessSync(dir)) {
        fs.rmdirSync(dir);
      }
    } catch (e) {
      throw new Error(`plugin_uninstall_failed|${e}`);
    }
    // 注意：数据库中该源的漫画数据保留，重装同 key 插件后自动恢复
  }

  private static loadAllPromise: Promise<void> | undefined = undefined;

  // 等待全部插件加载完成（尚未开始加载时立即返回）；
  // 供 ImageCache 等消费方在冷启动竞态下等待插件源注册完成
  static ready(): Promise<void> {
    return PluginService.loadAllPromise ?? Promise.resolve();
  }

  // 加载全部插件（每个插件在其专属 Worker 的隔离 JSVM 引擎中执行）；
  // 记忆化：并发/重复调用共享同一次加载，避免重复起 Worker
  static async loadAll(): Promise<void> {
    if (PluginService.loadAllPromise === undefined) {
      PluginService.loadAllPromise = PluginService.doLoadAll();
    }
    return PluginService.loadAllPromise;
  }

  private static async doLoadAll(): Promise<void> {
    const installed = PluginService.listInstalled();
    for (const item of installed) {
      try {
        const scriptText = fs.readTextSync(`${PluginService.pluginsDir}/${item.manifest.key}/main.js`);
        await PluginService.reloadOne(item.manifest, scriptText);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'load plugin %{public}s failed: %{public}s',
          item.manifest.key, (e as Error).message);
      }
    }
  }

  static markDirty(): void {
    AppStorage.setOrCreate('pluginsDirty', (AppStorage.get<number>('pluginsDirty') ?? 0) + 1);
  }

  // ---------------- 仓库索引 ----------------

  static async fetchRepo(url: string): Promise<RepoEntry[]> {
    const text = await Http.get(url, undefined);
    const raw = JSON.parse(text) as RawRepoIndex;
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
        };
        entries.push(entry);
      }
    }
    return entries;
  }

  // ---------------- 内部实现 ----------------

  // manifest.runtime 非空时，在 main.js 前拼接共享运行时（rawfile plugin_runtime_<name>.js）
  static composeScript(manifest: PluginManifest, mainJs: string): string {
    if (manifest.runtime === '') {
      return mainJs;
    }
    return `${PluginService.getRuntime(manifest.runtime)}\n;\n${mainJs}`;
  }

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
      const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
      await md.update({ data: new Uint8Array(data) });
      const digest: cryptoFramework.DataBlob = await md.digest();
      let out = '';
      for (let i = 0; i < digest.data.length; i++) {
        const byte: number = digest.data[i];
        out += byte < 16 ? `0${byte.toString(16)}` : byte.toString(16);
      }
      return out;
    } catch (e) {
      throw new Error(`plugin_checksum_failed|${e}`);
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
      throw new Error(`plugin_extract_failed|${e}`);
    }
    let stagingDir = '';
    try {
      const rootDir = PluginService.findPluginRoot(extractDir);
      let manifestText = '';
      try {
        manifestText = fs.readTextSync(`${rootDir}/manifest.json`);
      } catch (e) {
        throw new Error(`plugin_manifest_read_failed|${e}`);
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
        throw new Error(`plugin_stage_failed|${e}`);
      }
      const destDir = `${PluginService.pluginsDir}/${manifest.key}`;
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
      let scriptText = '';
      try {
        scriptText = fs.readTextSync(`${destDir}/main.js`);
      } catch (e) {
        throw new Error(`plugin_read_failed|${e}`);
      }
      await PluginService.reloadOne(manifest, scriptText);
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
    const slash = indexUrl.lastIndexOf('/');
    const base = slash >= 0 ? indexUrl.substring(0, slash + 1) : indexUrl;
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

  private static keyPart(raw: string): string {
    const lower = raw.toLowerCase();
    let out = '';
    for (let i = 0; i < lower.length; i++) {
      const c = lower.charAt(i);
      const ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
      if (ok) {
        out += c;
      } else if (out !== '' && out.charAt(out.length - 1) !== '_') {
        out += '_';
      }
    }
    while (out.length > 0 && out.charAt(out.length - 1) === '_') {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  private static childKey(packageKey: string, src: CompiledSourceInfo, used: string[]): string {
    const lang = PluginService.keyPart(src.lang ?? 'all');
    let key = `${packageKey}_${lang !== '' ? lang : 'src'}`;
    const taken = used.indexOf(key) >= 0 || key === packageKey || SourceRegistry.get(key) !== undefined;
    if (taken) {
      const id = PluginService.keyPart(src.id ?? '0');
      const suffix = id.length > 4 ? id.substring(id.length - 4) : (id !== '' ? id : '0');
      key = `${key}_${suffix}`;
    }
    return key;
  }

  private static manifestForSource(base: PluginManifest, src: CompiledSourceInfo, key: string): PluginManifest {
    let supports = base.supportsLatest;
    if (src.supportsLatest === true || src.supportsLatest === false) {
      supports = src.supportsLatest;
    }
    const manifest: PluginManifest = {
      key: key,
      name: src.name !== undefined && src.name !== '' ? src.name : base.name,
      lang: src.lang !== undefined && src.lang !== '' ? src.lang : base.lang,
      version: base.version,
      versionCode: base.versionCode,
      baseUrl: src.baseUrl !== undefined && src.baseUrl !== '' ? src.baseUrl : base.baseUrl,
      // 单源声明 nsfw 时优先生效，否则继承包级 manifest.nsfw
      nsfw: src.nsfw !== undefined ? src.nsfw : base.nsfw,
      supportsLatest: supports,
      minAppVersion: base.minAppVersion,
      dslVersion: base.dslVersion,
      icon: base.icon,
      runtime: base.runtime,
      engine: base.engine,
      contentType: ContentType.normalize(base.contentType),
    };
    return manifest;
  }

  private static async readCompiledSources(packageKey: string): Promise<CompiledSourceInfo[]> {
    try {
      const raw = await JsvmExtensionManager.callData<object>(packageKey, 'getSources', []);
      const text = JSON.stringify(raw);
      const parsed = JSON.parse(text) as CompiledSourceInfo[];
      if (Array.isArray(parsed)) {
        return parsed;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getSources failed for %{public}s: %{public}s', packageKey, (e as Error).message);
    }
    return [];
  }

  private static registerCompiled(manifest: PluginManifest, methods: string[], compiled: CompiledSourceInfo[]): void {
    const used: string[] = [manifest.key];
    const iconUrl = PluginService.iconUrlOf(manifest);
    for (let i = 0; i < compiled.length; i++) {
      const info = compiled[i];
      const key = i === 0 ? manifest.key : PluginService.childKey(manifest.key, info, used);
      used.push(key);
      const child = PluginService.manifestForSource(manifest, info, key);
      const sourceId = info.id !== undefined ? info.id : '';
      const src = new JsvmSource(child, methods, manifest.key, sourceId, iconUrl);
      SourceRegistry.register(src);
      src.warmImageHeaders();
    }
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

  // 加载/替换插件：卸载旧引擎后重新拉起专属 Worker + 隔离 JSVM_Context。
  // tachiyomi 编译产物若包含多个源，共用一个引擎并各自注册。
  private static async reloadOne(manifest: PluginManifest, mainJs: string): Promise<void> {
    const script = PluginService.composeScript(manifest, mainJs);
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
    const info = await JsvmExtensionManager.loadExtension(manifest.key, script, seed);
    PluginService.unregisterPackage(manifest.key);
    if (info.kind === 'tachiyomi' && info.methods.indexOf('getSources') >= 0) {
      const compiled = await PluginService.readCompiledSources(manifest.key);
      if (compiled.length > 0) {
        PluginService.registerCompiled(manifest, info.methods, compiled);
        hilog.info(DOMAIN, TAG, 'jsvm plugin ready: %{public}s v%{public}s (%{public}d sources, mem %{public}d)',
          manifest.key, manifest.version, compiled.length, JsvmExtensionManager.memoryBytes(manifest.key));
        return;
      }
    }
    const src = new JsvmSource(manifest, info.methods, manifest.key, '', PluginService.iconUrlOf(manifest));
    SourceRegistry.register(src);
    // 插件可选导出 getHeaders：声明后图片经宿主 http 管线加载（支持 Referer/Cookie）
    src.warmImageHeaders();
    hilog.info(DOMAIN, TAG, 'jsvm plugin ready: %{public}s v%{public}s (kind %{public}s, %{public}d methods, mem %{public}d)',
      manifest.key, manifest.version, info.kind, info.methods.length, JsvmExtensionManager.memoryBytes(manifest.key));
  }
}
