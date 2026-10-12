import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from '../common/Settings';
import { MangaRepo, ChapterRepo, CategoryRepo } from './Repos';
import { SManga, CategoryRecord, MangaRecord, ChapterRecord, ContentType } from '../model/Models';

// 备份/恢复（对齐 Mihon BackupCreator / BackupRestore 的 JSON 子集）

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
    const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      fileIo.closeSync(file);
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
    if (fileIo.accessSync(cachePath)) {
      fileIo.unlinkSync(cachePath);
    }
    fileIo.copyFileSync(uris[0], cachePath);
    const text: string = fileIo.readTextSync(cachePath);
    return BackupService.restore(text);
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
          categoryById.get(m.categoryId) as string : '默认',
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

  // 返回恢复的漫画数；-1 表示未选择文件；-2 表示解析失败
  private static async restore(text: string): Promise<number> {
    let root: BackupRoot;
    try {
      root = JSON.parse(text) as BackupRoot;
    } catch (e) {
      hilog.error(0x0001, 'Backup', 'parse backup json failed');
      return -2;
    }
    if (root.manga === undefined || root.categories === undefined) {
      return -2;
    }
    // 分类按 name 映射，缺失则补建
    const existing: CategoryRecord[] = await CategoryRepo.list();
    const existingNames = new Set<string>();
    for (const c of existing) {
      existingNames.add(c.name);
    }
    for (const name of root.categories) {
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
    for (const bm of root.manga) {
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
    const dirty = AppStorage.get<number>('libDirty');
    AppStorage.setOrCreate('libDirty', (dirty !== undefined ? dirty : 0) + 1);
    return count;
  }

  // ---- 自动备份（对齐 Mihon BackupCreateJob 定时任务，应用启动时检查到期与否）----

  // 自动备份到应用私有目录 backups/，保留最近 3 份；返回写入的文件路径
  static async autoBackup(context: common.UIAbilityContext): Promise<string> {
    const root: BackupRoot = await BackupService.buildBackup();
    const text: string = JSON.stringify(root);
    const dir: string = `${context.filesDir}/backups`;
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
    const path: string = `${dir}/honyomi_backup_${Date.now()}.json`;
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      fileIo.closeSync(file);
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
    } catch (e) {
      hilog.error(0x0001, 'Backup', 'auto backup failed');
    }
  }

  // 只保留最近 3 份自动备份（文件名含时间戳，字典序即时间序）
  private static pruneBackups(dir: string): void {
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
  }

  // ---- 书架列表 CSV 导出（对齐 Mihon LibraryExporter）----

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
    const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      fileIo.closeSync(file);
    }
    return true;
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
