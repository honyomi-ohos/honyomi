import { fileIo, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { Settings, PluginStoreRecord } from '../common/Settings';
import { BackupCrypto, BackupSecureBlob } from '../common/BackupCrypto';
import { SecureStore } from '../common/SecureStore';
import { AppKeys } from '../common/AppKeys';
import { AppDb } from './AppDb';
import { CategoryRepo, ChapterRepo, MangaRepo, TrackRepo, TrackExportRow, PluginRepo } from './Repos';
import { CategoryRecord, ChapterRecord, ContentType, MangaRecord, PluginRecord, SManga, TrackRecord } from '../model/Models';
import { PluginPrefs } from '../jsvm/PluginPrefs';
import { DanmakuService } from './DanmakuService';
import { PluginService, RepoEntry } from './PluginService';
import { Tracker } from './track/Tracker';
import { TrackerManager } from './track/TrackerManager';

// 备份/恢复（对齐 Mihon BackupCreator / BackupRestore 的 JSON 子集）。
// v3 双档：完整档（作品 + 全部设置 + 插件仓库 + 插件清单（嵌套各插件明文偏好与
// 敏感键注册表）+ 追踪绑定，可选加密敏感段：追踪器凭据 / 弹幕账号 / 翻译密钥 /
// 插件敏感偏好）、精简档（作品 + 插件仓库 + 插件清单）。导入仅支持 v3
// （项目未发布过，不兼容旧格式）；自动备份恒为 v3 精简档（敏感数据绝不落未加密文件）。
// 插件信任状态绝不进备份：导入安装的插件一律未受信任，由用户重新确认。

// 导出选项：full=false 精简档；includeSensitive 仅 full=true 时有效，需 password（≥6 位）
export interface BackupOptions {
  full: boolean;
  includeSensitive: boolean;
  password: string;
}

// JSON 解析的宽松原始模型（字段可缺失/类型不定），校验后拷入严格模型
interface RawBackupChapter {
  url?: string;
  name?: string;
  chapterNumber?: number;
  read?: boolean;
  lastPageRead?: number;
}

interface RawBackupWork {
  sourceKey?: string;
  url?: string;
  title?: string;
  thumbnailUrl?: string;
  author?: string;
  description?: string;
  genre?: string;
  status?: string;
  category?: string;
  contentType?: string;
  chapters?: RawBackupChapter[];
}

interface RawExtRepo {
  url?: string;
  name?: string;
  website?: string;
}

interface RawBackupPlugin {
  key?: string;
  name?: string;
  prefs?: Record<string, Object>;
  secureKeys?: Array<Object>;
}

interface RawBackupTrack {
  syncId?: number;
  sourceKey?: string;
  url?: string;
  remoteId?: number;
  libraryId?: number;
  title?: string;
  status?: number;
  lastChapterRead?: number;
  score?: number;
  totalChapters?: number;
  remoteUrl?: string;
  startDate?: number;
  finishDate?: number;
  isPrivate?: number;
}

interface RawSecureBlob {
  v?: number;
  kdf?: string;
  iterations?: number;
  salt?: string;
  iv?: string;
  ct?: string;
}

interface RawTrackCredential {
  pass?: string;
  token?: string;
}

// secure 段解密后的敏感载荷宽松模型
interface RawSecurePayload {
  track?: Record<string, Object>;
  ddp?: string;
  plugin?: Record<string, Object>;
  settings?: Record<string, Object>;
}

interface RawBackupRoot {
  version?: number;
  categories?: string[];
  work?: RawBackupWork[];
  extensionRepos?: RawExtRepo[];
  plugins?: RawBackupPlugin[];
  settings?: Record<string, Object>;
  track?: RawBackupTrack[];
  secure?: RawSecureBlob;
}

export interface BackupChapter {
  url: string;
  name: string;
  chapterNumber: number;
  read: boolean;
  lastPageRead: number;
}

export interface BackupWork {
  sourceKey: string;
  url: string;
  title: string;
  thumbnailUrl: string;
  author: string;
  description: string;
  genre: string;
  status: string;
  category: string;
  contentType?: string;
  chapters: BackupChapter[];
}

export interface BackupExtRepo {
  url: string;
  name: string;
  website: string;
}

// 备份插件清单条目：携带识别信息（key + 展示名）供导入时从仓库索引定位安装；
// 完整档在条目下嵌套该插件的明文偏好（prefs）与敏感键注册表（secureKeys），
// 空值省略；信任状态绝不进备份——新设备上安装后一律"未受信任"，由用户重新确认
export interface BackupPluginItem {
  key: string;
  name: string;
  prefs?: Record<string, string>;
  secureKeys?: string[];
}

export interface BackupTrackItem {
  syncId: number;
  sourceKey: string;
  url: string;
  remoteId: number;
  libraryId: number;
  title: string;
  status: number;
  lastChapterRead: number;
  score: number;
  totalChapters: number;
  remoteUrl: string;
  startDate: number;
  finishDate: number;
  isPrivate: number;
}

export interface BackupRoot {
  version: number;
  categories: string[];
  work: BackupWork[];
  extensionRepos?: BackupExtRepo[];
  plugins?: BackupPluginItem[];
  settings?: Record<string, Object>;
  track?: BackupTrackItem[];
  secure?: BackupSecureBlob;
}

// 作品区段（分类 + 作品）：导入导出共用
interface WorksData {
  categories: string[];
  work: BackupWork[];
}

// secure 段解密后的严格敏感载荷
interface TrackCredential {
  pass: string;
  token: string;
}

interface SecurePayload {
  track: Record<string, TrackCredential>;
  ddp: string;
  plugin: Record<string, Record<string, string>>;
  settings: Record<string, string>;
}

// 导出密码最短长度
const MIN_PASSWORD_LEN: number = 6;

export class BackupService {
  // 含加密段的导入：等待密码重试的文本与上下文缓存（成功/取消后清空）
  private static pendingText: string = '';
  private static pendingContext: common.UIAbilityContext | undefined = undefined;

  static async exportBackup(context: common.UIAbilityContext,
    options: BackupOptions): Promise<boolean> {
    const root: BackupRoot = await BackupService.buildRoot(context, options);
    const text: string = JSON.stringify(root);
    return BackupService.saveTextViaPicker(context, text, `honyomi_backup_${Date.now()}.json`);
  }

  // v3 根对象组装：精简档（作品 + 插件仓库 + 插件清单）；
  // 完整档追加设置/追踪绑定，插件条目下嵌套该插件的明文偏好与敏感键注册表，
  // 可选加密敏感段
  private static async buildRoot(context: common.UIAbilityContext,
    options: BackupOptions): Promise<BackupRoot> {
    const works: WorksData = await BackupService.buildWorks();
    const root: BackupRoot = {
      version: 3,
      categories: works.categories,
      work: works.work,
      extensionRepos: BackupService.buildExtRepos(),
    };
    if (options.full) {
      // 插件偏好读取前先就绪偏好存储（完整档条目要嵌套 prefs）
      await PluginPrefs.ensureInit(context);
    }
    // 已安装插件清单：空清单不输出 plugins 字段（避免冗余空段）
    const plugins: BackupPluginItem[] = await BackupService.buildPluginItems(options.full);
    if (plugins.length > 0) {
      root.plugins = plugins;
    }
    if (options.full) {
      root.settings = Settings.exportAll();
      root.track = await BackupService.buildTrackItems();
      if (options.includeSensitive) {
        if (options.password.length < MIN_PASSWORD_LEN) {
          throw new Error('backup_password_too_short');
        }
        const payload: SecurePayload = await BackupService.buildSecurePayload();
        root.secure = await BackupCrypto.encryptJson(options.password, JSON.stringify(payload));
      }
    }
    return root;
  }

  // 返回恢复的漫画数；-1 未选择文件；-2 解析失败；
  // -3 文件含加密敏感段、等待密码（页面弹密码框后调 retryImportBackup）；
  // -4 密码错误（缓存保留，可再次重试）
  static async importBackup(context: common.UIAbilityContext): Promise<number> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.json'];
    const docPicker = new picker.DocumentViewPicker(context);
    const uris: Array<string> = await docPicker.select(options);
    if (uris.length === 0) {
      BackupService.clearPending();
      return -1;
    }
    // 选择器返回 file://docs|media/... 虚拟 URI（仅临时授权），copyFileSync 只认沙箱路径会报 ENOENT；
    // 须以 URI openSync 打开后按 fd 读取（与导出侧 saveTextViaPicker 同模式），不再落 cache 副本
    let file: fileIo.File;
    try {
      file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
    } catch (e) {
      throw new Error(`open backup file failed: ${e}`);
    }
    let text: string;
    try {
      const size: number = fileIo.statSync(file.fd).size;
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      fileIo.readSync(file.fd, buffer);
      text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
    } finally {
      try {
        fileIo.closeSync(file);
      } catch (e) {
      }
    }
    return BackupService.restoreFromText(text, '', context);
  }

  // 密码重试（importBackup 返回 -3/-4 后调用）
  static async retryImportBackup(password: string): Promise<number> {
    if (BackupService.pendingText === '' || BackupService.pendingContext === undefined) {
      return -1;
    }
    return BackupService.restoreFromText(BackupService.pendingText, password, BackupService.pendingContext);
  }

  // 自动备份到应用私有目录 backups/，保留最近 3 份；返回写入的文件路径。
  // 恒为 v3 精简档：敏感配置绝不进入未加密的自动备份
  static async autoBackup(context: common.UIAbilityContext): Promise<string> {
    const root: BackupRoot = await BackupService.buildRoot(context,
      { full: false, includeSensitive: false, password: '' });
    const text: string = JSON.stringify(root);
    const dir: string = `${context.filesDir}/backups`;
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
    } catch (e) {
      throw new Error(`create backup dir failed: ${e}`);
    }
    const path: string = `${dir}/honyomi_backup_${Date.now()}.json`;
    let file: fileIo.File;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    } catch (e) {
      throw new Error(`open backup file failed: ${e}`);
    }
    try {
      BackupService.writeTextSync(file.fd, text);
    } finally {
      try {
        fileIo.closeSync(file);
      } catch (e) {
      }
    }
    BackupService.pruneBackups(dir);
    return path;
  }

  // 到期则执行自动备份（频率 0 = 关闭；距上次备份超过频率间隔才触发）
  static async runAutoBackupIfDue(context: common.UIAbilityContext): Promise<void> {
    const intervalHours: number = Settings.getBackupInterval();
    if (intervalHours <= 0) {
      return;
    }
    const last: number = Settings.getLastAutoBackupTimestamp();
    if (last > 0 && Date.now() - last < intervalHours * 3600 * 1000) {
      return;
    }
    try {
      await BackupService.autoBackup(context);
      Settings.setLastAutoBackupTimestamp(Date.now());
      AppStorage.setOrCreate(AppKeys.LAST_BACKUP_FAILED, false);
    } catch (e) {
      // 失败状态经 AppStorage 上报供设置页提示
      AppStorage.setOrCreate(AppKeys.LAST_BACKUP_FAILED, true);
      hilog.error(0x0001, 'Backup', 'auto backup failed: %{public}s', (e as Error).message);
    }
  }

  // 返回 false 表示用户取消选择保存位置
  static async exportLibraryCsv(context: common.UIAbilityContext,
    includeTitle: boolean, includeAuthor: boolean): Promise<boolean> {
    const library: MangaRecord[] = await MangaRepo.getLibrary();
    const rows: string[] = [];
    for (const m of library) {
      const cols: string[] = [];
      if (includeTitle) {
        cols.push(BackupService.csvCell(m.title));
      }
      if (includeAuthor) {
        cols.push(BackupService.csvCell(m.author));
      }
      rows.push(cols.join(','));
    }
    const text: string = rows.join('\r\n');
    return BackupService.saveTextViaPicker(context, text, 'honyomi_library.csv');
  }

  // 校验写入字节数与文本字节长度一致，防止超大备份部分写入
  private static writeTextSync(fd: number, text: string): void {
    let written: number = 0;
    try {
      written = fileIo.writeSync(fd, text);
    } catch (e) {
      throw new Error(`write backup file failed: ${e}`);
    }
    const expected: number = util.TextEncoder.create('utf-8').encodeInto(text).length;
    if (written !== expected) {
      throw new Error(`备份写入不完整（${written}/${expected} 字节）`);
    }
  }

  // 经系统文档保存器导出文本；返回 false 表示用户取消保存位置
  private static async saveTextViaPicker(context: common.UIAbilityContext, text: string,
    defaultName: string): Promise<boolean> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [defaultName];
    const docPicker = new picker.DocumentViewPicker(context);
    const uris: Array<string> = await docPicker.save(options);
    if (uris.length === 0) {
      return false;
    }
    let file: fileIo.File;
    try {
      file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    } catch (e) {
      throw new Error(`open backup file failed: ${e}`);
    }
    try {
      BackupService.writeTextSync(file.fd, text);
    } finally {
      try {
        fileIo.closeSync(file);
      } catch (e) {
      }
    }
    return true;
  }

  // ---- 导出组装 ----

  // 作品区段组装（分类名映射 + 章节进度）
  private static async buildWorks(): Promise<WorksData> {
    const categories: CategoryRecord[] = await CategoryRepo.list();
    const categoryNames: string[] = [];
    const categoryById = new Map<number, string>();
    for (const c of categories) {
      categoryNames.push(c.name);
      categoryById.set(c.id, c.name);
    }
    const library: MangaRecord[] = await MangaRepo.getLibrary();
    const workList: BackupWork[] = [];
    for (const m of library) {
      const chapters: ChapterRecord[] = await ChapterRepo.listByManga(m.id);
      const backupChapters: BackupChapter[] = [];
      for (const c of chapters) {
        const bc: BackupChapter = {
          url: c.url,
          name: c.name,
          chapterNumber: c.chapterNumber,
          read: c.read,
          lastPageRead: c.lastPageRead,
        };
        backupChapters.push(bc);
      }
      const bm: BackupWork = {
        sourceKey: m.sourceKey,
        url: m.url,
        title: m.title,
        thumbnailUrl: m.thumbnailUrl,
        author: m.author,
        description: m.description,
        genre: m.genre,
        status: m.status,
        category: categoryById.get(m.categoryId) !== undefined ?
          categoryById.get(m.categoryId) as string : ContentType.categoryName(m.contentType),
        contentType: ContentType.normalize(m.contentType),
        chapters: backupChapters,
      };
      workList.push(bm);
    }
    return { categories: categoryNames, work: workList };
  }

  // 插件仓库列表（两种档位都导出）
  private static buildExtRepos(): BackupExtRepo[] {
    const stores: PluginStoreRecord[] = Settings.getPluginStores();
    const out: BackupExtRepo[] = [];
    for (const s of stores) {
      const repo: BackupExtRepo = { url: s.url, name: s.name, website: s.website };
      out.push(repo);
    }
    return out;
  }

  // 已安装插件清单（两种档位都导出）：key + 展示名，供导入时从仓库索引定位重装；
  // 版本取导入时仓库最新，信任状态不导出。完整档（withPrefs=true）在条目下嵌套
  // 该插件的明文偏好（prefs，绝不混入 SecureStore 敏感值）与敏感键注册表
  // （secureKeys），均为空时省略
  private static async buildPluginItems(withPrefs: boolean): Promise<BackupPluginItem[]> {
    const records: PluginRecord[] = await PluginRepo.list();
    const out: BackupPluginItem[] = [];
    for (const r of records) {
      const item: BackupPluginItem = { key: r.key, name: r.name };
      if (withPrefs) {
        const prefs: Record<string, string> = PluginPrefs.plainPrefsOf(r.key);
        if (Object.keys(prefs).length > 0) {
          item.prefs = prefs;
        }
        const secureKeys: string[] = PluginPrefs.secureKeysOf(r.key);
        if (secureKeys.length > 0) {
          item.secureKeys = secureKeys;
        }
      }
      out.push(item);
    }
    return out;
  }

  // 追踪绑定导出：track 联表 manga 取源身份（跨设备按 sourceKey + url 定位）
  private static async buildTrackItems(): Promise<BackupTrackItem[]> {
    const rows: TrackExportRow[] = await TrackRepo.listAllWithManga();
    const items: BackupTrackItem[] = [];
    for (const row of rows) {
      const t: TrackRecord = row.track;
      const item: BackupTrackItem = {
        syncId: t.syncId,
        sourceKey: row.sourceKey,
        url: row.url,
        remoteId: t.remoteId,
        libraryId: t.libraryId,
        title: t.title,
        status: t.status,
        lastChapterRead: t.lastChapterRead,
        score: t.score,
        totalChapters: t.totalChapters,
        remoteUrl: t.remoteUrl,
        startDate: t.startDate,
        finishDate: t.finishDate,
        isPrivate: t.isPrivate ? 1 : 0,
      };
      items.push(item);
    }
    return items;
  }

  // 敏感载荷组装（进 secure 加密段）：追踪器凭据 / 弹幕账号 / 插件敏感偏好 / 翻译密钥
  private static async buildSecurePayload(): Promise<SecurePayload> {
    const trackCreds: Record<string, TrackCredential> = {};
    const trackers: Tracker[] = TrackerManager.trackers;
    for (const t of trackers) {
      const pass: string = SecureStore.getSync(Tracker.passwordAlias(t.syncId));
      const token: string = SecureStore.getSync(Tracker.tokenAlias(t.syncId));
      if (pass !== '' || token !== '') {
        trackCreds[`${t.syncId}`] = { pass: pass, token: token };
      }
    }
    const payload: SecurePayload = {
      track: trackCreds,
      ddp: DanmakuService.exportAccount(),
      plugin: PluginPrefs.exportSecureValues(),
      settings: Settings.exportSensitive(),
    };
    return payload;
  }

  // ---- 导入 ----

  private static clearPending(): void {
    BackupService.pendingText = '';
    BackupService.pendingContext = undefined;
  }

  private static async restoreFromText(text: string, password: string,
    context: common.UIAbilityContext): Promise<number> {
    let raw: RawBackupRoot;
    try {
      raw = JSON.parse(text) as RawBackupRoot;
    } catch (e) {
      hilog.error(0x0001, 'Backup', 'parse backup json failed');
      BackupService.clearPending();
      return -2;
    }
    if (raw === null || raw.version !== 3 || raw.work === undefined || raw.categories === undefined) {
      BackupService.clearPending();
      return -2;
    }
    const blob: BackupSecureBlob | undefined = BackupService.parseSecureBlob(raw.secure);
    if (blob !== undefined && password === '') {
      // 含加密敏感段且未提供密码：缓存文本等待重试
      BackupService.pendingText = text;
      BackupService.pendingContext = context;
      return -3;
    }
    const count: number = await BackupService.restoreV3(raw, password, blob, context);
    if (count >= 0) {
      BackupService.clearPending();
    }
    return count;
  }

  // secure 段宽松解析：字段缺失/类型不符视为损坏文件，如实抛错
  private static parseSecureBlob(raw: RawSecureBlob | undefined): BackupSecureBlob | undefined {
    if (raw === undefined || raw === null) {
      return undefined;
    }
    if (typeof raw.v !== 'number' || typeof raw.kdf !== 'string' ||
      typeof raw.iterations !== 'number' || typeof raw.salt !== 'string' ||
      typeof raw.iv !== 'string' || typeof raw.ct !== 'string') {
      throw new Error('backup_secure_unsupported');
    }
    const blob: BackupSecureBlob = {
      v: raw.v,
      kdf: raw.kdf,
      iterations: raw.iterations,
      salt: raw.salt,
      iv: raw.iv,
      ct: raw.ct,
    };
    return blob;
  }

  // v3 恢复：先解密 secure（密码错误在改动任何本地数据前早退，返回 -4），
  // 再按区段恢复：作品（单事务）→ 插件仓库 → 插件安装（尽力而为）→ 设置 → 插件偏好 → 追踪绑定 → 敏感段
  private static async restoreV3(raw: RawBackupRoot, password: string,
    blob: BackupSecureBlob | undefined, context: common.UIAbilityContext): Promise<number> {
    let secure: SecurePayload | undefined = undefined;
    if (blob !== undefined) {
      let plain: string;
      try {
        plain = await BackupCrypto.decryptJson(password, blob);
      } catch (e) {
        const err = e as Error;
        if (err.message === 'backup_bad_password') {
          return -4;
        }
        throw new Error(`restore backup failed: ${e}`);
      }
      secure = BackupService.parseSecurePayload(plain);
    }
    // 1. 作品/分类/章节（恢复全程单事务，失败整体回滚）
    const works: WorksData = BackupService.parseWorks(raw);
    const count: number = await BackupService.restoreWorks(works);
    // 2. 插件仓库合并（按 url 去重追加）
    BackupService.restoreExtRepos(raw.extensionRepos);
    // 3. 插件安装（尽力而为：从刷新后的仓库索引定位备份清单中的插件并安装，
    //    安装后一律未受信任；网络/仓库缺失不阻断恢复，可稍后在扩展页手动安装）
    await BackupService.restorePlugins(raw.plugins);
    // 4. 应用设置 + 立即生效的副作用（语言/主题/全局开关）
    const rawSettings: Record<string, Object> | undefined = raw.settings;
    if (rawSettings !== undefined && rawSettings !== null) {
      Settings.importAll(rawSettings);
      const dark: boolean = AppStorage.get<boolean>(AppKeys.IS_DARK) ?? false;
      Settings.applyAppLanguage();
      Settings.applyTheme(dark);
      Settings.applyColorMode(context);
      Settings.pushGlobalFlags();
    }
    // 5. 插件明文偏好 + 敏感键注册表（嵌套在 plugins[].prefs / plugins[].secureKeys，
    //    重组为内部前缀键后写入；插件安装失败也不丢——安装后 seedScript 采用）
    const rawPlugins: RawBackupPlugin[] | undefined = raw.plugins;
    if (rawPlugins !== undefined && rawPlugins !== null && rawPlugins.length > 0) {
      const entries: Record<string, string> = {};
      for (const p of rawPlugins) {
        if (p === null || p === undefined || typeof p.key !== 'string' || p.key === '') {
          continue;
        }
        const rawPrefs: Record<string, Object> | undefined = p.prefs;
        if (rawPrefs !== undefined && rawPrefs !== null) {
          const prefs: Record<string, string> = {};
          const prefKeys = Object.keys(rawPrefs);
          for (const k of prefKeys) {
            const v: Object | undefined = rawPrefs[k];
            if (typeof v === 'string' && v !== '') {
              prefs[k] = v;
            }
          }
          if (Object.keys(prefs).length > 0) {
            entries[`__extprefs:${p.key}`] = JSON.stringify(prefs);
          }
        }
        const rawSecureKeys: Array<Object> | undefined = p.secureKeys;
        if (rawSecureKeys !== undefined && rawSecureKeys !== null) {
          const registry: string[] = [];
          for (const k of rawSecureKeys) {
            if (typeof k === 'string' && k !== '') {
              registry.push(k);
            }
          }
          if (registry.length > 0) {
            entries[`__extsecure:${p.key}`] = JSON.stringify(registry);
          }
        }
      }
      if (Object.keys(entries).length > 0) {
        await PluginPrefs.ensureInit(context);
        PluginPrefs.importEntries(entries);
      }
    }
    // 6. 追踪绑定（按 sourceKey + url 映射回本地作品）
    await BackupService.restoreTracks(raw.track);
    // 7. 敏感段恢复（凭据 / 账号 / 密钥 / 插件敏感值）
    if (secure !== undefined) {
      BackupService.restoreSecure(secure);
    }
    return count;
  }

  // 敏感载荷宽松解析（解密后的明文 JSON），逐字段校验拷入严格模型
  private static parseSecurePayload(plain: string): SecurePayload {
    let raw: RawSecurePayload;
    try {
      raw = JSON.parse(plain) as RawSecurePayload;
    } catch (e) {
      throw new Error('backup_secure_unsupported');
    }
    const payload: SecurePayload = { track: {}, ddp: '', plugin: {}, settings: {} };
    if (raw === null || raw === undefined) {
      return payload;
    }
    if (raw.track !== undefined && raw.track !== null) {
      const keys = Object.keys(raw.track);
      for (const k of keys) {
        const v: Object | undefined = raw.track[k];
        if (v === null || v === undefined || typeof v !== 'object') {
          continue;
        }
        const cred: RawTrackCredential = v as RawTrackCredential;
        const item: TrackCredential = {
          pass: typeof cred.pass === 'string' ? cred.pass : '',
          token: typeof cred.token === 'string' ? cred.token : '',
        };
        if (item.pass !== '' || item.token !== '') {
          payload.track[k] = item;
        }
      }
    }
    if (typeof raw.ddp === 'string') {
      payload.ddp = raw.ddp;
    }
    // plugin/settings 内层键值由 importSecureValues / importSensitive 逐项校验
    if (raw.plugin !== undefined && raw.plugin !== null) {
      payload.plugin = raw.plugin as Record<string, Record<string, string>>;
    }
    if (raw.settings !== undefined && raw.settings !== null) {
      payload.settings = raw.settings as Record<string, string>;
    }
    return payload;
  }

  // 插件仓库导入：仅接受合法 url，按 url 去重合并
  private static restoreExtRepos(raw: RawExtRepo[] | undefined): void {
    if (raw === undefined) {
      return;
    }
    for (const r of raw) {
      if (r === null || r === undefined || typeof r.url !== 'string' || r.url === '') {
        continue;
      }
      if (Settings.hasPluginStore(r.url)) {
        continue;
      }
      const record: PluginStoreRecord = {
        url: r.url,
        name: typeof r.name === 'string' && r.name !== '' ? r.name : Settings.urlHostOf(r.url),
        website: typeof r.website === 'string' ? r.website : '',
      };
      Settings.addPluginStore(record);
    }
  }

  // 插件安装导入（尽力而为）：备份清单中的未安装插件从刷新后的仓库索引定位条目并
  // 安装。同 key 多仓库取 versionCode 最高条目；逐个容错——索引拉取失败、仓库无此
  // 插件、下载/校验失败均仅记日志跳过，不阻断整体恢复。新环境无信任记录，安装结果
  // 恒为"未受信任"（installZip 信任门禁不通过即只落元数据索引），由用户在扩展页
  // 逐一确认信任后才注册源、执行插件代码
  private static async restorePlugins(raw: RawBackupPlugin[] | undefined): Promise<void> {
    if (raw === undefined || raw === null || raw.length === 0) {
      return;
    }
    const wanted: BackupPluginItem[] = [];
    for (const p of raw) {
      if (p === null || p === undefined || typeof p.key !== 'string' || p.key === '') {
        continue;
      }
      const item: BackupPluginItem = {
        key: p.key,
        name: typeof p.name === 'string' ? p.name : '',
      };
      wanted.push(item);
    }
    if (wanted.length === 0) {
      return;
    }
    const installed: PluginRecord[] = await PluginRepo.list();
    const installedKeys: string[] = [];
    for (const r of installed) {
      installedKeys.push(r.key);
    }
    const missing: BackupPluginItem[] = [];
    for (const item of wanted) {
      if (installedKeys.indexOf(item.key) < 0) {
        missing.push(item);
      }
    }
    if (missing.length === 0) {
      return;
    }
    let entries: RepoEntry[] = [];
    try {
      entries = await PluginService.refreshRepoEntries();
    } catch (e) {
      hilog.warn(0x0001, 'Backup', 'refresh repos for plugin install failed: %{public}s', (e as Error).message);
      return;
    }
    let okCount: number = 0;
    for (const item of missing) {
      let best: RepoEntry | undefined = undefined;
      for (const entry of entries) {
        if (entry.key === item.key && (best === undefined || entry.versionCode > best.versionCode)) {
          best = entry;
        }
      }
      if (best === undefined) {
        hilog.warn(0x0001, 'Backup', 'backup plugin %{public}s not found in repos, skip', item.key);
        continue;
      }
      try {
        await PluginService.installFromRepo(best);
        okCount++;
      } catch (e) {
        hilog.warn(0x0001, 'Backup', 'install backup plugin %{public}s failed: %{public}s',
          item.key, (e as Error).message);
      }
    }
    hilog.info(0x0001, 'Backup', 'backup plugins installed: %{public}d/%{public}d', okCount, missing.length);
  }

  // 追踪绑定导入：源身份映射本地作品后按 mangaId + syncId upsert；找不到的作品跳过
  private static async restoreTracks(raw: RawBackupTrack[] | undefined): Promise<void> {
    if (raw === undefined) {
      return;
    }
    for (const rt of raw) {
      if (rt === null || rt === undefined || typeof rt.syncId !== 'number' ||
        typeof rt.sourceKey !== 'string' || rt.sourceKey === '' ||
        typeof rt.url !== 'string' || rt.url === '') {
        continue;
      }
      const manga: MangaRecord | undefined = await MangaRepo.getBySourceUrl(rt.sourceKey, rt.url);
      if (manga === undefined) {
        continue;
      }
      const rec: TrackRecord = new TrackRecord();
      rec.mangaId = manga.id;
      rec.syncId = rt.syncId;
      rec.remoteId = typeof rt.remoteId === 'number' ? rt.remoteId : 0;
      rec.libraryId = typeof rt.libraryId === 'number' ? rt.libraryId : 0;
      rec.title = typeof rt.title === 'string' ? rt.title : '';
      rec.status = typeof rt.status === 'number' ? rt.status : 0;
      rec.lastChapterRead = typeof rt.lastChapterRead === 'number' ? rt.lastChapterRead : 0;
      rec.score = typeof rt.score === 'number' ? rt.score : 0;
      rec.totalChapters = typeof rt.totalChapters === 'number' ? rt.totalChapters : 0;
      rec.remoteUrl = typeof rt.remoteUrl === 'string' ? rt.remoteUrl : '';
      rec.startDate = typeof rt.startDate === 'number' ? rt.startDate : 0;
      rec.finishDate = typeof rt.finishDate === 'number' ? rt.finishDate : 0;
      rec.isPrivate = rt.isPrivate === 1;
      await TrackRepo.upsert(rec);
    }
  }

  // 敏感段恢复：追踪器凭据 / 弹幕账号 / 插件敏感偏好 / 敏感设置键
  private static restoreSecure(secure: SecurePayload): void {
    const credKeys = Object.keys(secure.track);
    for (const key of credKeys) {
      const syncId: number = parseInt(key, 10);
      if (!Number.isInteger(syncId) || syncId <= 0) {
        continue;
      }
      const cred: TrackCredential | undefined = secure.track[key];
      if (cred === undefined || cred === null) {
        continue;
      }
      if (cred.pass !== '') {
        SecureStore.putSync(Tracker.passwordAlias(syncId), cred.pass);
      }
      if (cred.token !== '') {
        SecureStore.putSync(Tracker.tokenAlias(syncId), cred.token);
      }
    }
    if (secure.ddp !== '') {
      DanmakuService.importAccount(secure.ddp);
    }
    PluginPrefs.importSecureValues(secure.plugin);
    Settings.importSensitive(secure.settings);
  }

  // ---- 作品区段 ----

  // 逐字段校验并拷入严格模型，坏条目跳过不中断整体恢复
  private static parseWorks(raw: RawBackupRoot): WorksData {
    const categories: string[] = [];
    const rawCategories: string[] = raw.categories === undefined ? [] : raw.categories;
    for (const item of rawCategories) {
      if (typeof item === 'string' && item !== '') {
        categories.push(item);
      }
    }
    const workList: BackupWork[] = [];
    const rawWork: RawBackupWork[] = raw.work === undefined ? [] : raw.work;
    for (const rm of rawWork) {
      if (rm === null || typeof rm.sourceKey !== 'string' || rm.sourceKey === '' ||
        typeof rm.url !== 'string' || rm.url === '') {
        continue;
      }
      const chapters: BackupChapter[] = [];
      const rawChapters: RawBackupChapter[] = rm.chapters === undefined ? [] : rm.chapters;
      for (const rc of rawChapters) {
        if (rc === null || typeof rc.url !== 'string' || rc.url === '') {
          continue;
        }
        const bc: BackupChapter = {
          url: rc.url,
          name: typeof rc.name === 'string' ? rc.name : '',
          chapterNumber: typeof rc.chapterNumber === 'number' ? rc.chapterNumber : 0,
          read: rc.read === true,
          lastPageRead: typeof rc.lastPageRead === 'number' ? rc.lastPageRead : 0,
        };
        chapters.push(bc);
      }
      const bm: BackupWork = {
        sourceKey: rm.sourceKey,
        url: rm.url,
        title: typeof rm.title === 'string' ? rm.title : '',
        thumbnailUrl: typeof rm.thumbnailUrl === 'string' ? rm.thumbnailUrl : '',
        author: typeof rm.author === 'string' ? rm.author : '',
        description: typeof rm.description === 'string' ? rm.description : '',
        genre: typeof rm.genre === 'string' ? rm.genre : '',
        status: typeof rm.status === 'string' ? rm.status : '',
        category: typeof rm.category === 'string' && rm.category !== '' ? rm.category :
          ContentType.categoryName(typeof rm.contentType === 'string' ? rm.contentType : ContentType.MANGA),
        contentType: typeof rm.contentType === 'string' ? rm.contentType : 'manga',
        chapters: chapters,
      };
      workList.push(bm);
    }
    return { categories: categories, work: workList };
  }

  // 作品恢复：恢复全程单事务，任一环节失败整体回滚，书架保持恢复前状态
  private static async restoreWorks(works: WorksData): Promise<number> {
    const categories: string[] = works.categories;
    const workList: BackupWork[] = works.work;
    const store = await AppDb.get();
    try {
      store.beginTransaction();
    } catch (e) {
      throw new Error(`restore backup failed: ${e}`);
    }
    try {
      // 分类按 name 映射，缺失则补建
      const existing: CategoryRecord[] = await CategoryRepo.list();
      const existingNames = new Set<string>();
      for (const c of existing) {
        existingNames.add(c.name);
      }
      for (const name of categories) {
        if (!existingNames.has(name)) {
          await CategoryRepo.add(name);
        }
      }
      const mapped: CategoryRecord[] = await CategoryRepo.list();
      const categoryIdByName = new Map<string, number>();
      for (const c of mapped) {
        categoryIdByName.set(c.name, c.id);
      }
      let count = 0;
      for (const bm of workList) {
        const sm: SManga = {
          key: bm.url,
          title: bm.title,
          coverUrl: bm.thumbnailUrl,
          author: bm.author,
          description: bm.description,
          genre: bm.genre,
          status: bm.status,
        };
        const mangaId = await MangaRepo.upsertFromSource(bm.sourceKey, sm, ContentType.normalize(bm.contentType));
        if (mangaId < 0) {
          continue;
        }
        await MangaRepo.setInLibrary(mangaId, true);
        const categoryId = categoryIdByName.get(bm.category);
        if (categoryId !== undefined && categoryId !== 1) {
          await MangaRepo.setCategory(mangaId, categoryId);
        }
        for (const bc of bm.chapters) {
          await ChapterRepo.upsertBackup(mangaId, bc.url, bc.name, bc.chapterNumber, bc.read, bc.lastPageRead);
        }
        count += 1;
      }
      store.commit();
      const dirty = AppStorage.get<number>(AppKeys.LIB_DIRTY);
      AppStorage.setOrCreate(AppKeys.LIB_DIRTY, (dirty !== undefined ? dirty : 0) + 1);
      return count;
    } catch (e) {
      try {
        store.rollBack();
      } catch (e2) {
      }
      throw new Error(`restore backup failed: ${e}`);
    }
  }

  // ---- 自动备份（对齐 Mihon BackupCreateJob 定时任务，应用启动时检查到期与否）----

  // 只保留最近 3 份自动备份（文件名含时间戳，字典序即时间序）
  private static pruneBackups(dir: string): void {
    try {
      const names: string[] = fileIo.listFileSync(dir);
      const backups: string[] = [];
      for (const name of names) {
        if (name.indexOf('honyomi_backup_') === 0 && name.indexOf('.json') === name.length - 5) {
          backups.push(name);
        }
      }
      backups.sort();
      while (backups.length > 3) {
        const oldest: string | undefined = backups.shift();
        if (oldest !== undefined) {
          fileIo.unlinkSync(`${dir}/${oldest}`);
        }
      }
    } catch (e) {
    }
  }

  // ---- 书架列表 CSV 导出（对齐 Mihon LibraryExporter）----

  // CSV 单元格转义：包含换行/引号/逗号时用双引号包裹并双写内部引号
  private static csvCell(value: string): string {
    if (value === '') {
      return '';
    }
    if (value.indexOf('\r') >= 0 || value.indexOf('\n') >= 0 ||
      value.indexOf('"') >= 0 || value.indexOf(',') >= 0) {
      return `"${value.replace(/"/g, '""')}"`;
    }
    return value;
  }
}
