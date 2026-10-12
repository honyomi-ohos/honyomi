import { common, bundleManager } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import zlib from '@ohos.zlib';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { PluginManifest, JsvmSource, CompiledSourceInfo } from '../source/JsvmSource';
import { JsvmExtensionManager } from '../jsvm/JsvmExtensionManager';
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
}

interface RawRepoEntry {
  key?: string;
  name?: string;
  lang?: string;
  version?: string;
  versionCode?: number;
  file?: string;
  nsfw?: boolean;
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

  static init(context: common.UIAbilityContext): void {
    PluginService.pluginsDir = `${context.filesDir}/plugins`;
    PluginService.cacheDir = context.cacheDir;
    PluginService.context = context;
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      PluginService.appVersionCode = bundleInfo.versionCode;
    } catch (e) {
      PluginService.appVersionCode = 1;
    }
    if (!fs.accessSync(PluginService.pluginsDir)) {
      fs.mkdirSync(PluginService.pluginsDir, true);
    }
    PluginService.cleanStaleTemp();
  }

  // 清理历史失败安装遗留的临时文件/目录（plugin_extract_*/plugin_install_*/plugin_repo_*）
  private static cleanStaleTemp(): void {
    if (!fs.accessSync(PluginService.cacheDir)) {
      return;
    }
    const names: string[] = fs.listFileSync(PluginService.cacheDir);
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
      throw new Error('manifest.key 无效（仅小写字母/数字/下划线）');
    }
    if (name === '') {
      throw new Error('manifest.name 缺失');
    }
    const versionCode = raw.versionCode ?? 0;
    if (versionCode <= 0) {
      throw new Error('manifest.versionCode 无效');
    }
    // 引擎门禁：唯一支持的执行引擎是 jsvm
    const engine = raw.engine ?? 'jsvm';
    if (engine !== 'jsvm') {
      throw new Error(`不支持的插件引擎: ${engine}（本应用仅支持 jsvm）`);
    }
    // 版本门禁：DSL 版本过高或要求的应用版本过高时拒绝加载，给出可理解的错误
    const dslVersion = raw.dslVersion ?? 1;
    if (dslVersion > PluginService.HOST_DSL_VERSION) {
      throw new Error(`插件需要新版应用（DSL v${dslVersion} > v${PluginService.HOST_DSL_VERSION}），请先升级应用`);
    }
    const minAppVersion = raw.minAppVersion ?? 1;
    if (minAppVersion > PluginService.appVersionCode) {
      throw new Error(`插件需要应用版本号 ≥ ${minAppVersion}，请先升级应用`);
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
      icon: raw.icon ?? '',
      runtime: raw.runtime ?? '',
      engine: engine,
      contentType: ContentType.normalize(raw.contentType),
    };
    return manifest;
  }

  static listInstalled(): InstalledPlugin[] {
    const result: InstalledPlugin[] = [];
    if (!fs.accessSync(PluginService.pluginsDir)) {
      return result;
    }
    const names: string[] = fs.listFileSync(PluginService.pluginsDir);
    for (const dir of names) {
      const manifestPath = `${PluginService.pluginsDir}/${dir}/manifest.json`;
      if (!fs.accessSync(manifestPath)) {
        continue;
      }
      try {
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
    const zipPath = `${PluginService.cacheDir}/plugin_install_${Date.now()}.honyomiplug`;
    try {
      const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        fs.copyFile(srcFile.fd, zipPath);
      } finally {
        fs.closeSync(srcFile);
      }
    } catch (e) {
      throw new Error(`读取所选文件失败：${(e as Error).message}`);
    }
    try {
      return await PluginService.installZip(zipPath);
    } finally {
      if (fs.accessSync(zipPath)) {
        fs.unlinkSync(zipPath);
      }
    }
  }

  // 从仓库条目下载并安装
  static async installFromRepo(entry: RepoEntry): Promise<string> {
    const buffer = await Http.getBuffer(entry.file, undefined);
    const zipPath = `${PluginService.cacheDir}/plugin_repo_${entry.key}_${Date.now()}.honyomiplug`;
    const file = fs.openSync(zipPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    try {
      fs.writeSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    try {
      return await PluginService.installZip(zipPath);
    } finally {
      if (fs.accessSync(zipPath)) {
        fs.unlinkSync(zipPath);
      }
    }
  }

  static async uninstall(key: string): Promise<void> {
    const packageKey = PluginService.packageKeyOf(key);
    PluginService.unregisterPackage(packageKey);
    await JsvmExtensionManager.unloadExtension(packageKey);
    const dir = `${PluginService.pluginsDir}/${packageKey}`;
    if (fs.accessSync(dir)) {
      fs.rmdirSync(dir);
    }
    // 注意：数据库中该源的漫画数据保留，重装同 key 插件后自动恢复
  }

  // 加载全部插件（每个插件在其专属 Worker 的隔离 JSVM 引擎中执行）
  static async loadAll(): Promise<void> {
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
      return '';
    }
    const data = PluginService.context.resourceManager
      .getRawFileContentSync(`plugin_runtime_${name}.js`);
    const text = util.TextDecoder.create('utf-8').decodeToString(data);
    PluginService.runtimeCache.set(name, text);
    return text;
  }

  private static async installZip(zipPath: string): Promise<string> {
    const extractDir = `${PluginService.cacheDir}/plugin_extract_${Date.now()}`;
    if (!fs.accessSync(extractDir)) {
      fs.mkdirSync(extractDir, true);
    }
    await zlib.decompressFile(zipPath, extractDir);
    try {
      const rootDir = PluginService.findPluginRoot(extractDir);
      const manifest = PluginService.parseManifest(fs.readTextSync(`${rootDir}/manifest.json`));
      if (!fs.accessSync(`${rootDir}/main.js`)) {
        throw new Error('插件包缺少 main.js');
      }
      const destDir = `${PluginService.pluginsDir}/${manifest.key}`;
      if (fs.accessSync(destDir)) {
        fs.rmdirSync(destDir);
      }
      fs.mkdirSync(destDir, true);
      fs.copyFileSync(`${rootDir}/manifest.json`, `${destDir}/manifest.json`);
      fs.copyFileSync(`${rootDir}/main.js`, `${destDir}/main.js`);
      if (manifest.icon !== '' && fs.accessSync(`${rootDir}/${manifest.icon}`)) {
        fs.copyFileSync(`${rootDir}/${manifest.icon}`, `${destDir}/${manifest.icon}`);
      }
      const scriptText = fs.readTextSync(`${destDir}/main.js`);
      await PluginService.reloadOne(manifest, scriptText);
      hilog.info(DOMAIN, TAG, 'plugin installed: %{public}s', manifest.key);
      return manifest.key;
    } finally {
      if (fs.accessSync(extractDir)) {
        fs.rmdirSync(extractDir);
      }
    }
  }

  private static findPluginRoot(extractDir: string): string {
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
    throw new Error('插件包中未找到 manifest.json');
  }

  // 仓库索引里的 file 可以是绝对 URL，也可以相对 index.json 所在目录。
  private static resolveRepoFile(indexUrl: string, file: string): string {
    if (file.startsWith('http://') || file.startsWith('https://')) {
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
      nsfw: base.nsfw,
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
    for (let i = 0; i < compiled.length; i++) {
      const info = compiled[i];
      const key = i === 0 ? manifest.key : PluginService.childKey(manifest.key, info, used);
      used.push(key);
      const child = PluginService.manifestForSource(manifest, info, key);
      const sourceId = info.id !== undefined ? info.id : '';
      const src = new JsvmSource(child, methods, manifest.key, sourceId);
      SourceRegistry.register(src);
      src.warmImageHeaders();
    }
  }

  // 加载/替换插件：卸载旧引擎后重新拉起专属 Worker + 隔离 JSVM_Context。
  // tachiyomi 编译产物若包含多个源，共用一个引擎并各自注册。
  private static async reloadOne(manifest: PluginManifest, mainJs: string): Promise<void> {
    const script = PluginService.composeScript(manifest, mainJs);
    const info = await JsvmExtensionManager.loadExtension(manifest.key, script);
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
    const src = new JsvmSource(manifest, info.methods, manifest.key, '');
    SourceRegistry.register(src);
    // 插件可选导出 getHeaders：声明后图片经宿主 http 管线加载（支持 Referer/Cookie）
    src.warmImageHeaders();
    hilog.info(DOMAIN, TAG, 'jsvm plugin ready: %{public}s v%{public}s (kind %{public}s, %{public}d methods, mem %{public}d)',
      manifest.key, manifest.version, info.kind, info.methods.length, JsvmExtensionManager.memoryBytes(manifest.key));
  }
}
