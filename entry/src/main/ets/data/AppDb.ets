import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// RelationalStore 数据库（对齐 Mihon Room schema 的 P1 子集）
export class AppDb {
  private static store: relationalStore.RdbStore | undefined = undefined;
  private static initPromise: Promise<void> | undefined = undefined;

  static ready(context: common.Context): Promise<void> {
    if (AppDb.initPromise === undefined) {
      AppDb.initPromise = AppDb.doInit(context);
    }
    return AppDb.initPromise;
  }

  static async get(): Promise<relationalStore.RdbStore> {
    if (AppDb.store === undefined) {
      throw new Error('database not initialized');
    }
    return AppDb.store;
  }

  private static async doInit(context: common.Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: 'honyomi.db',
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    const store = await relationalStore.getRdbStore(context, config);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS manga (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sourceKey TEXT NOT NULL,
      url TEXT NOT NULL,
      title TEXT NOT NULL,
      thumbnailUrl TEXT DEFAULT '',
      author TEXT DEFAULT '',
      description TEXT DEFAULT '',
      genre TEXT DEFAULT '',
      status TEXT DEFAULT '',
      inLibrary INTEGER DEFAULT 0,
      categoryId INTEGER DEFAULT 1,
      addedAt INTEGER DEFAULT 0,
      lastUpdateAt INTEGER DEFAULT 0,
      fetchedAt INTEGER DEFAULT 0,
      UNIQUE(sourceKey, url)
    )`);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS chapter (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      mangaId INTEGER NOT NULL,
      url TEXT NOT NULL,
      name TEXT NOT NULL,
      chapterNumber REAL DEFAULT 0,
      dateUpload INTEGER DEFAULT 0,
      pages INTEGER DEFAULT 0,
      sortOrder INTEGER DEFAULT 0,
      read INTEGER DEFAULT 0,
      bookmark INTEGER DEFAULT 0,
      lastPageRead INTEGER DEFAULT 0,
      UNIQUE(mangaId, url)
    )`);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS category (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      sortOrder INTEGER DEFAULT 0
    )`);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      mangaId INTEGER NOT NULL,
      chapterId INTEGER NOT NULL,
      seenAt INTEGER NOT NULL,
      lastPageRead INTEGER DEFAULT 0
    )`);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS readingSession (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      mangaId INTEGER NOT NULL,
      chapterId INTEGER NOT NULL,
      day TEXT NOT NULL,
      startTime INTEGER NOT NULL,
      duration INTEGER NOT NULL
    )`);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS track (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      mangaId INTEGER NOT NULL,
      syncId INTEGER NOT NULL DEFAULT 1,
      remoteId INTEGER NOT NULL,
      title TEXT DEFAULT '',
      status TEXT DEFAULT '',
      lastChapterRead INTEGER DEFAULT 0,
      score REAL DEFAULT 0,
      UNIQUE(mangaId, syncId)
    )`);
    await store.executeSql(
      `INSERT INTO category(id, name, sortOrder)
       SELECT 1, '默认', 0
       WHERE NOT EXISTS (SELECT 1 FROM category WHERE id = 1)`);
    AppDb.store = store;
    hilog.info(0x0001, 'AppDb', 'database ready');
  }
}
