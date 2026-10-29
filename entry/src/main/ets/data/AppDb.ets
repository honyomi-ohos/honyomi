import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ContentType } from '../model/Models';

// RelationalStore 数据库（对齐 Mihon Room schema 的 P1 子集）
// 开发阶段：无版本迁移，建表语句即完整 schema（结构变更需清除应用数据重建）
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
    let store: relationalStore.RdbStore;
    try {
      store = await relationalStore.getRdbStore(context, config);
    } catch (e) {
      throw new Error(`init rdb store failed: ${e}`);
    }
    await AppDb.createTables(store);
    await AppDb.createIndexes(store);
    await AppDb.ensureDefaultCategories(store);
    AppDb.store = store;
    hilog.info(0x0001, 'AppDb', 'database ready');
  }

  // 初始分类：漫画 / 小说 / 动画（对应三种内容类型），每次启动幂等执行；
  // id = 1 为删除分类/入库缺省的回退分类，另两类按名补建（用户已建同名分类则复用，不占固定 id）
  private static async ensureDefaultCategories(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql(
        `INSERT INTO category(id, name, sortOrder)
         SELECT 1, ?, 0
         WHERE NOT EXISTS (SELECT 1 FROM category WHERE id = 1)`,
        [ContentType.CATEGORY_MANGA]);
      await store.executeSql(
        `INSERT INTO category(name, sortOrder)
         SELECT ?, (SELECT COUNT(*) FROM category)
         WHERE NOT EXISTS (SELECT 1 FROM category WHERE name = ?)`,
        [ContentType.CATEGORY_NOVEL, ContentType.CATEGORY_NOVEL]);
      await store.executeSql(
        `INSERT INTO category(name, sortOrder)
         SELECT ?, (SELECT COUNT(*) FROM category)
         WHERE NOT EXISTS (SELECT 1 FROM category WHERE name = ?)`,
        [ContentType.CATEGORY_VIDEO, ContentType.CATEGORY_VIDEO]);
    } catch (e) {
      throw new Error(`ensure default categories failed: ${e}`);
    }
  }

  private static async createTables(store: relationalStore.RdbStore): Promise<void> {
    try {
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
        localCover TEXT DEFAULT '',
        localCoverUrl TEXT DEFAULT '',
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
        syncId INTEGER NOT NULL,
        remoteId INTEGER NOT NULL,
        libraryId INTEGER DEFAULT 0,
        title TEXT DEFAULT '',
        status INTEGER DEFAULT 0,
        lastChapterRead REAL DEFAULT 0,
        score REAL DEFAULT 0,
        totalChapters INTEGER DEFAULT 0,
        remoteUrl TEXT DEFAULT '',
        startDate INTEGER DEFAULT 0,
        finishDate INTEGER DEFAULT 0,
        isPrivate INTEGER DEFAULT 0,
        UNIQUE(mangaId, syncId)
      )`);
      // 漫画 × 分类多对多（对齐 Mihon MangaCategory）；manga.categoryId 保留为主分类冗余列
      await store.executeSql(`CREATE TABLE IF NOT EXISTS manga_category (
        mangaId INTEGER NOT NULL,
        categoryId INTEGER NOT NULL,
        UNIQUE(mangaId, categoryId)
      )`);
      await store.executeSql(`CREATE TABLE IF NOT EXISTS plugin (
        key TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        lang TEXT DEFAULT 'multi',
        version TEXT DEFAULT '',
        versionCode INTEGER DEFAULT 0,
        baseUrl TEXT DEFAULT '',
        nsfw INTEGER DEFAULT 0,
        bt INTEGER DEFAULT 0,
        supportsLatest INTEGER DEFAULT 0,
        minAppVersion INTEGER DEFAULT 1,
        dslVersion INTEGER DEFAULT 1,
        icon TEXT DEFAULT '',
        contentType TEXT DEFAULT 'manga',
        methodsJson TEXT DEFAULT '[]',
        sourcesJson TEXT DEFAULT '[]',
        installedAt INTEGER DEFAULT 0
      )`);
    } catch (e) {
      throw new Error(`create tables failed: ${e}`);
    }
  }

  // 二级索引：书架/更新/历史/统计的高频查询列
  private static async createIndexes(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_manga_inLibrary ON manga(inLibrary, categoryId)`);
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_manga_category ON manga_category(categoryId, mangaId)`);
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_manga_category_manga ON manga_category(mangaId)`);
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_chapter_read_upload ON chapter(read, dateUpload)`);
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_chapter_sortOrder ON chapter(mangaId, sortOrder)`);
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_history_mangaId ON history(mangaId, seenAt)`);
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_session_day ON readingSession(day)`);
      // history 唯一索引：HistoryRepo.upsert 单条 INSERT ON CONFLICT 原子完成（消除查后写竞态）
      await store.executeSql(`CREATE UNIQUE INDEX IF NOT EXISTS idx_history_unique ON history(mangaId, chapterId)`);
    } catch (e) {
      throw new Error(`create indexes failed: ${e}`);
    }
  }
}
