import { fileIo, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { Settings } from '../common/Settings';
import { AppKeys } from '../common/AppKeys';
import { AppDb } from './AppDb';
import { CategoryRepo, ChapterRepo, MangaRepo } from './Repos';
import { CategoryRecord, ChapterRecord, ContentType, MangaRecord, SManga } from '../model/Models';

// 备份/恢复（对齐 Mihon BackupCreator / BackupRestore 的 JSON 子集）

// JSON 解析的宽松原始模型（字段可缺失/类型不定），校验后拷入严格模型
interface RawBackupChapter {
  url?: string;
  name?: string;
  chapterNumber?: number;
  read?: boolean;
  lastPageRead?: number;
}

interface RawBackupManga {
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

interface RawBackupRoot {
  version?: number;
  categories?: string[];
  manga?: RawBackupManga[];
}

export interface BackupChapter {
  url: string;
  name: string;
  chapterNumber: number;
  read: boolean;
  lastPageRead: number;
}

export interface BackupManga {
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

export interface BackupRoot {
  version: number;
  categories: string[];
  manga: BackupManga[];
}

export class BackupService {
  static async exportBackup(context: common.UIAbilityContext): Promise<boolean> {
    const root: BackupRoot = await BackupService.buildBackup();
    const text: string = JSON.stringify(root);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`honyomi_backup_${Date.now()}.json`];
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

  static async importBackup(context: common.UIAbilityContext): Promise<number> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.json'];
    const docPicker = new picker.DocumentViewPicker(context);
    const uris: Array<string> = await docPicker.select(options);
    if (uris.length === 0) {
      return -1;
    }
    const cachePath = `${context.cacheDir}/backup_import.json`;
    let text: string;
    try {
      if (fileIo.accessSync(cachePath)) {
        fileIo.unlinkSync(cachePath);
      }
      fileIo.copyFileSync(uris[0], cachePath);
      text = fileIo.readTextSync(cachePath);
      // 读取完成后立即删除 cache 副本，避免残留
      if (fileIo.accessSync(cachePath)) {
        fileIo.unlinkSync(cachePath);
      }
    } catch (e) {
      throw new Error(`import backup file failed: ${e}`);
    }
    return BackupService.restore(text);
  }

  // 自动备份到应用私有目录 backups/，保留最近 3 份；返回写入的文件路径
  static async autoBackup(context: common.UIAbilityContext): Promise<string> {
    const root: BackupRoot = await BackupService.buildBackup();
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
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = ['honyomi_library.csv'];
    const docPicker = new picker.DocumentViewPicker(context);
    const uris: Array<string> = await docPicker.save(options);
    if (uris.length === 0) {
      return false;
    }
    let file: fileIo.File;
    try {
      file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    } catch (e) {
      throw new Error(`open csv file failed: ${e}`);
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

  private static async buildBackup(): Promise<BackupRoot> {
    const categories: CategoryRecord[] = await CategoryRepo.list();
    const categoryNames: string[] = [];
    const categoryById = new Map<number, string>();
    for (const c of categories) {
      categoryNames.push(c.name);
      categoryById.set(c.id, c.name);
    }
    const library: MangaRecord[] = await MangaRepo.getLibrary();
    const mangaList: BackupManga[] = [];
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
      const bm: BackupManga = {
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
      mangaList.push(bm);
    }
    const root: BackupRoot = {
      version: 2,
      categories: categoryNames,
      manga: mangaList,
    };
    return root;
  }

  // ---- 自动备份（对齐 Mihon BackupCreateJob 定时任务，应用启动时检查到期与否）----

  // 旧备份分类名（中文历史值）→ 内容类型 code；新备份/自建分类原样
  private static mapCategoryName(name: string): string {
    if (name === '漫画' || name === '默认') {
      return 'manga';
    }
    if (name === '小说') {
      return 'novel';
    }
    if (name === '动画') {
      return 'video';
    }
    return name;
  }

  // 旧备份连载状态（中文历史值）→ 状态 code；其余原样
  private static mapStatus(status: string): string {
    switch (status) {
      case '连载中':
        return 'ongoing';
      case '已完结':
        return 'completed';
      case '已授权':
        return 'licensed';
      case '出版完毕':
        return 'publication_complete';
      case '已取消':
        return 'cancelled';
      case '休刊':
        return 'hiatus';
      case '未知':
        return 'unknown';
      default:
        return status;
    }
  }

  // 返回恢复的漫画数；-1 表示未选择文件；-2 表示解析失败
  private static async restore(text: string): Promise<number> {
    let raw: RawBackupRoot;
    try {
      raw = JSON.parse(text) as RawBackupRoot;
    } catch (e) {
      hilog.error(0x0001, 'Backup', 'parse backup json failed');
      return -2;
    }
    if (raw === null || raw.manga === undefined || raw.categories === undefined) {
      return -2;
    }
    // 逐字段校验并拷入严格模型，坏条目跳过不中断整体恢复
    const categories: string[] = [];
    for (const item of raw.categories) {
      if (typeof item === 'string' && item !== '') {
        categories.push(BackupService.mapCategoryName(item));
      }
    }
    const mangaList: BackupManga[] = [];
    for (const rm of raw.manga) {
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
      const bm: BackupManga = {
        sourceKey: rm.sourceKey,
        url: rm.url,
        title: typeof rm.title === 'string' ? rm.title : '',
        thumbnailUrl: typeof rm.thumbnailUrl === 'string' ? rm.thumbnailUrl : '',
        author: typeof rm.author === 'string' ? rm.author : '',
        description: typeof rm.description === 'string' ? rm.description : '',
        genre: typeof rm.genre === 'string' ? rm.genre : '',
        status: typeof rm.status === 'string' ? BackupService.mapStatus(rm.status) : '',
        category: typeof rm.category === 'string' && rm.category !== '' ? rm.category :
          ContentType.categoryName(typeof rm.contentType === 'string' ? rm.contentType : ContentType.MANGA),
        contentType: typeof rm.contentType === 'string' ? rm.contentType : 'manga',
        chapters: chapters,
      };
      mangaList.push(bm);
    }
    const store = await AppDb.get();
    // 恢复全程单事务：任一环节失败整体回滚，书架保持恢复前状态
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
      for (const bm of mangaList) {
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

  // ---- 书架列表 CSV 导出（对齐 Mihon LibraryExporter）----

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
