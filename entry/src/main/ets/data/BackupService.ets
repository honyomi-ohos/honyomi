import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MangaRepo, ChapterRepo, CategoryRepo } from './Repos';
import { SManga, CategoryRecord, MangaRecord, ChapterRecord } from '../model/Models';

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
        chapters: backupChapters,
      };
      mangaList.push(bm);
    }
    const root: BackupRoot = {
      version: 1,
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
      const mangaId = await MangaRepo.upsertFromSource(bm.sourceKey, sm);
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
}
