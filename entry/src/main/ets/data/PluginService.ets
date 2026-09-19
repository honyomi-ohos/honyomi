import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import zlib from '@ohos.zlib';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PluginManifest, PluginSource } from '../source/PluginSource';
import { SourceRegistry } from '../source/Source';
import { PluginHost } from './PluginHost';
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
}

export interface InstalledPlugin {
  manifest: PluginManifest;
  enabled: boolean;
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

// 插件包管理：.mihonplug(zip: manifest.json + main.js) 安装/卸载/启停 + 在线仓库索引
export class PluginService {
  private static pluginsDir: string = '';
  private static cacheDir: string = '';

  static init(context: common.UIAbilityContext): void {
    PluginService.pluginsDir = `${context.filesDir}/plugins`;
    PluginService.cacheDir = context.cacheDir;
    PluginHost.getInstance().init(context);
    if (!fs.accessSync(PluginService.pluginsDir)) {
      fs.mkdirSync(PluginService.pluginsDir, true);
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
    const manifest: PluginManifest = {
      key: key,
      name: name,
      lang: raw.lang ?? 'multi',
      version: raw.version ?? '1.0.0',
      versionCode: versionCode,
      baseUrl: raw.baseUrl ?? '',
      nsfw: raw.nsfw === true,
      supportsLatest: raw.supportsLatest !== false,
      minAppVersion: raw.minAppVersion ?? 1,
      dslVersion: raw.dslVersion ?? 1,
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
        const item: InstalledPlugin = {
          manifest: manifest,
          enabled: PluginHost.getInstance().isPluginEnabled(manifest.key),
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
    const zipPath = `${PluginService.cacheDir}/plugin_install_${Date.now()}.mihonplug`;
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
    const zipPath = `${PluginService.cacheDir}/plugin_repo_${entry.key}_${Date.now()}.mihonplug`;
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

  static async setEnabled(key: string, enabled: boolean): Promise<void> {
    PluginHost.getInstance().setPluginEnabled(key, enabled);
    await PluginService.reloadKey(key);
  }

  static async uninstall(key: string): Promise<void> {
    SourceRegistry.unregister(key);
    await PluginHost.getInstance().unloadPlugin(key);
    const dir = `${PluginService.pluginsDir}/${key}`;
    if (fs.accessSync(dir)) {
      fs.rmdirSync(dir);
    }
    // 注意：数据库中该源的漫画数据保留，重装同 key 插件后自动恢复
  }

  // 宿主就绪后加载全部已启用插件
  static async loadAll(): Promise<void> {
    const installed = PluginService.listInstalled();
    for (const item of installed) {
      if (!item.enabled) {
        continue;
      }
      try {
        const scriptText = fs.readTextSync(`${PluginService.pluginsDir}/${item.manifest.key}/main.js`);
        await PluginHost.getInstance().loadPlugin(item.manifest.key, JSON.stringify(item.manifest), scriptText);
        SourceRegistry.register(new PluginSource(item.manifest));
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
          file: file,
          nsfw: item.nsfw === true,
        };
        entries.push(entry);
      }
    }
    return entries;
  }

  // ---------------- 内部实现 ----------------

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

  private static async reloadKey(key: string): Promise<void> {
    const manifestPath = `${PluginService.pluginsDir}/${key}/manifest.json`;
    if (!fs.accessSync(manifestPath)) {
      SourceRegistry.unregister(key);
      await PluginHost.getInstance().unloadPlugin(key);
      return;
    }
    const manifest = PluginService.parseManifest(fs.readTextSync(manifestPath));
    const scriptText = fs.readTextSync(`${PluginService.pluginsDir}/${key}/main.js`);
    await PluginService.reloadOne(manifest, scriptText);
  }

  private static async reloadOne(manifest: PluginManifest, scriptText: string): Promise<void> {
    if (!PluginHost.getInstance().isPluginEnabled(manifest.key)) {
      SourceRegistry.unregister(manifest.key);
      await PluginHost.getInstance().unloadPlugin(manifest.key);
      return;
    }
    await PluginHost.getInstance().loadPlugin(manifest.key, JSON.stringify(manifest), scriptText);
    SourceRegistry.register(new PluginSource(manifest));
  }
}
