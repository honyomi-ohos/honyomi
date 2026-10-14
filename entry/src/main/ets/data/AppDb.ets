import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// RelationalStore 数据库（对齐 Mihon Room schema 的 P1 子集）
// 迁移策略：PRAGMA user_version 版本号顺序迁移，失败即抛出（不吞真实错误）
export class AppDb {
  private static store: relationalStore.RdbStore | undefined = undefined;
  private static initPromise: Promise<void> | undefined = undefined;

  static ready(context: common.Context): Promise<void> {
    if (AppDb.initPromise === undefined) {
      // 初始化失败允许下次 ready() 重试（如首次启动磁盘瞬时异常）
      AppDb.initPromise = AppDb.doInit(context).catch((e: Error) => {
        AppDb.initPromise = undefined;
        throw e;
      });
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
    await AppDb.createTables(store);
    await AppDb.migrate(store);
    await AppDb.createIndexes(store);
    await store.executeSql(
      `INSERT INTO category(id, name, sortOrder)
       SELECT 1, '默认', 0
       WHERE NOT EXISTS (SELECT 1 FROM category WHERE id = 1)`);
    AppDb.store = store;
    hilog.info(0x0001, 'AppDb', 'database ready');
  }

  private static async createTables(store: relationalStore.RdbStore): Promise<void> {
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
      contentType TEXT DEFAULT 'manga',
      origThumbnail TEXT DEFAULT '',
      chapterFlags INTEGER DEFAULT 0,
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
  }

  // 版本号顺序迁移：0 = 无版本历史（全新库或 ALTER TABLE 时代的旧库）
  private static async migrate(store: relationalStore.RdbStore): Promise<void> {
    let version = 0;
    const rs = await store.querySql(`PRAGMA user_version`);
    if (rs.goToNextRow()) {
      version = rs.getLong(rs.getColumnIndex('user_version'));
    }
    rs.close();
    // v0 -> v1：早期旧库补列（新库建表已含，ALTER 失败按真实错误抛出前先校验列存在）
    if (version < 1) {
      const cols = new Set<string>();
      const colRs = await store.querySql(`PRAGMA table_info(manga)`);
      while (colRs.goToNextRow()) {
        cols.add(colRs.getString(colRs.getColumnIndex('name')));
      }
      colRs.close();
      if (!cols.has('contentType')) {
        await store.executeSql(`ALTER TABLE manga ADD COLUMN contentType TEXT DEFAULT 'manga'`);
      }
      if (!cols.has('origThumbnail')) {
        await store.executeSql(`ALTER TABLE manga ADD COLUMN origThumbnail TEXT DEFAULT ''`);
      }
      await store.executeSql(`PRAGMA user_version = 1`);
      version = 1;
      hilog.info(0x0001, 'AppDb', 'migrated schema to v1');
    }
    // v1 -> v2：history 按 (mangaId, chapterId) 去重后建唯一索引，
    // 使 HistoryRepo.upsert 可用单条 INSERT ON CONFLICT 原子完成（消除查后写竞态）
    if (version < 2) {
      await store.executeSql(`DELETE FROM history WHERE id NOT IN (
        SELECT h.id FROM history h
        WHERE h.id = (
          SELECT h2.id FROM history h2
          WHERE h2.mangaId = h.mangaId AND h2.chapterId = h.chapterId
          ORDER BY h2.seenAt DESC, h2.id DESC LIMIT 1))`);
      await store.executeSql(`CREATE UNIQUE INDEX IF NOT EXISTS idx_history_unique ON history(mangaId, chapterId)`);
      await store.executeSql(`PRAGMA user_version = 2`);
      hilog.info(0x0001, 'AppDb', 'migrated schema to v2');
    }
    // v2 -> v3：manga 增加章节排序/筛选标志位（对齐 Mihon chapterFlags，
    // 详情页排序模式/方向与三态筛选按部持久化）
    if (version < 3) {
      const cols3 = new Set<string>();
      const colRs3 = await store.querySql(`PRAGMA table_info(manga)`);
      while (colRs3.goToNextRow()) {
        cols3.add(colRs3.getString(colRs3.getColumnIndex('name')));
      }
      colRs3.close();
      if (!cols3.has('chapterFlags')) {
        await store.executeSql(`ALTER TABLE manga ADD COLUMN chapterFlags INTEGER DEFAULT 0`);
      }
      await store.executeSql(`PRAGMA user_version = 3`);
      version = 3;
      hilog.info(0x0001, 'AppDb', 'migrated schema to v3');
    }
  }

  // 二级索引：书架/更新/历史/统计的高频查询列
  private static async createIndexes(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_manga_inLibrary ON manga(inLibrary, categoryId)`);
    await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_chapter_read_upload ON chapter(read, dateUpload)`);
    await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_chapter_sortOrder ON chapter(mangaId, sortOrder)`);
    await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_history_mangaId ON history(mangaId, seenAt)`);
    await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_session_day ON readingSession(day)`);
  }
}
