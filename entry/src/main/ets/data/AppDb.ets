import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ContentType } from '../model/Models';

function closeQuietly(rs: relationalStore.ResultSet): void {
  try {
    rs.close();
  } catch (e) {
  }
}

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
    let store: relationalStore.RdbStore;
    try {
      store = await relationalStore.getRdbStore(context, config);
    } catch (e) {
      throw new Error(`init rdb store failed: ${e}`);
    }
    await AppDb.createTables(store);
    await AppDb.migrate(store);
    await AppDb.createIndexes(store);
    await AppDb.ensureDefaultCategories(store);
    AppDb.store = store;
    hilog.info(0x0001, 'AppDb', 'database ready');
  }

  // 初始分类：漫画 / 小说 / 动画（对应三种内容类型），每次启动幂等执行；
  // 旧库「默认」更名为「漫画」（id = 1 为删除分类/入库缺省的回退分类），
  // 另两类按名补建（用户已建同名分类则复用，不占固定 id）
  private static async ensureDefaultCategories(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql(
        `INSERT INTO category(id, name, sortOrder)
         SELECT 1, ?, 0
         WHERE NOT EXISTS (SELECT 1 FROM category WHERE id = 1)`,
        [ContentType.CATEGORY_MANGA]);
      await store.executeSql(
        `UPDATE category SET name = ? WHERE id = 1 AND name = '默认'`,
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
        syncId INTEGER NOT NULL DEFAULT 1,
        remoteId INTEGER NOT NULL,
        title TEXT DEFAULT '',
        status TEXT DEFAULT '',
        lastChapterRead INTEGER DEFAULT 0,
        score REAL DEFAULT 0,
        UNIQUE(mangaId, syncId)
      )`);
    } catch (e) {
      throw new Error(`create tables failed: ${e}`);
    }
  }

  // 版本号顺序迁移：0 = 无版本历史（全新库或 ALTER TABLE 时代的旧库）
  private static async migrate(store: relationalStore.RdbStore): Promise<void> {
    let version = 0;
    try {
      const rs = await store.querySql(`PRAGMA user_version`);
      if (rs.goToNextRow()) {
        version = rs.getLong(rs.getColumnIndex('user_version'));
      }
      closeQuietly(rs);
    } catch (e) {
      throw new Error(`read user_version failed: ${e}`);
    }
    // v0 -> v1：早期旧库补列（新库建表已含，ALTER 失败按真实错误抛出前先校验列存在）
    if (version < 1) {
      try {
        store.beginTransaction();
      } catch (e) {
        throw new Error(`migrate to v1 failed: ${e}`);
      }
      try {
        const cols = new Set<string>();
        const colRs = await store.querySql(`PRAGMA table_info(manga)`);
        while (colRs.goToNextRow()) {
          cols.add(colRs.getString(colRs.getColumnIndex('name')));
        }
        closeQuietly(colRs);
        if (!cols.has('contentType')) {
          await store.executeSql(`ALTER TABLE manga ADD COLUMN contentType TEXT DEFAULT 'manga'`);
        }
        if (!cols.has('origThumbnail')) {
          await store.executeSql(`ALTER TABLE manga ADD COLUMN origThumbnail TEXT DEFAULT ''`);
        }
        await store.executeSql(`PRAGMA user_version = 1`);
        store.commit();
      } catch (e) {
        try {
          store.rollBack();
        } catch (e2) {
        }
        throw new Error(`migrate to v1 failed: ${e}`);
      }
      version = 1;
      hilog.info(0x0001, 'AppDb', 'migrated schema to v1');
    }
    // v1 -> v2：history 按 (mangaId, chapterId) 去重后建唯一索引，
    // 使 HistoryRepo.upsert 可用单条 INSERT ON CONFLICT 原子完成（消除查后写竞态）
    if (version < 2) {
      try {
        store.beginTransaction();
      } catch (e) {
        throw new Error(`migrate to v2 failed: ${e}`);
      }
      try {
        await store.executeSql(`DELETE FROM history WHERE id NOT IN (
          SELECT h.id FROM history h
          WHERE h.id = (
            SELECT h2.id FROM history h2
            WHERE h2.mangaId = h.mangaId AND h2.chapterId = h.chapterId
            ORDER BY h2.seenAt DESC, h2.id DESC LIMIT 1))`);
        await store.executeSql(`CREATE UNIQUE INDEX IF NOT EXISTS idx_history_unique ON history(mangaId, chapterId)`);
        await store.executeSql(`PRAGMA user_version = 2`);
        store.commit();
      } catch (e) {
        try {
          store.rollBack();
        } catch (e2) {
        }
        throw new Error(`migrate to v2 failed: ${e}`);
      }
      hilog.info(0x0001, 'AppDb', 'migrated schema to v2');
    }
    // v2 -> v3：manga 增加章节排序/筛选标志位（对齐 Mihon chapterFlags，
    // 详情页排序模式/方向与三态筛选按部持久化）
    if (version < 3) {
      try {
        store.beginTransaction();
      } catch (e) {
        throw new Error(`migrate to v3 failed: ${e}`);
      }
      try {
        const cols3 = new Set<string>();
        const colRs3 = await store.querySql(`PRAGMA table_info(manga)`);
        while (colRs3.goToNextRow()) {
          cols3.add(colRs3.getString(colRs3.getColumnIndex('name')));
        }
        closeQuietly(colRs3);
        if (!cols3.has('chapterFlags')) {
          await store.executeSql(`ALTER TABLE manga ADD COLUMN chapterFlags INTEGER DEFAULT 0`);
        }
        await store.executeSql(`PRAGMA user_version = 3`);
        store.commit();
      } catch (e) {
        try {
          store.rollBack();
        } catch (e2) {
        }
        throw new Error(`migrate to v3 failed: ${e}`);
      }
      version = 3;
      hilog.info(0x0001, 'AppDb', 'migrated schema to v3');
    }
    // v3 -> v4：内置数据 code 化（分类名/连载状态改存 code，显示层经资源映射多语言）
    if (version < 4) {
      try {
        store.beginTransaction();
      } catch (e) {
        throw new Error(`migrate to v4 failed: ${e}`);
      }
      try {
        // 分类名：内置默认分类的中文历史值 → 内容类型 code（用户自建/改名分类不动）
        await store.executeSql(`UPDATE category SET name = 'manga' WHERE name IN ('漫画', '默认')`);
        await store.executeSql(`UPDATE category SET name = 'novel' WHERE name = '小说'`);
        await store.executeSql(`UPDATE category SET name = 'video' WHERE name = '动画'`);
        // 连载状态：中文历史值 → tachiyomi 状态 code
        await store.executeSql(`UPDATE manga SET status = 'ongoing' WHERE status = '连载中'`);
        await store.executeSql(`UPDATE manga SET status = 'completed' WHERE status = '已完结'`);
        await store.executeSql(`UPDATE manga SET status = 'licensed' WHERE status = '已授权'`);
        await store.executeSql(`UPDATE manga SET status = 'publication_complete' WHERE status = '出版完毕'`);
        await store.executeSql(`UPDATE manga SET status = 'cancelled' WHERE status = '已取消'`);
        await store.executeSql(`UPDATE manga SET status = 'hiatus' WHERE status = '休刊'`);
        await store.executeSql(`UPDATE manga SET status = 'unknown' WHERE status = '未知'`);
        await store.executeSql(`PRAGMA user_version = 4`);
        store.commit();
      } catch (e) {
        try {
          store.rollBack();
        } catch (e2) {
        }
        throw new Error(`migrate to v4 failed: ${e}`);
      }
      version = 4;
      hilog.info(0x0001, 'AppDb', 'migrated schema to v4');
    }
  }

  // 二级索引：书架/更新/历史/统计的高频查询列
  private static async createIndexes(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_manga_inLibrary ON manga(inLibrary, categoryId)`);
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_chapter_read_upload ON chapter(read, dateUpload)`);
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_chapter_sortOrder ON chapter(mangaId, sortOrder)`);
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_history_mangaId ON history(mangaId, seenAt)`);
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_session_day ON readingSession(day)`);
    } catch (e) {
      throw new Error(`create indexes failed: ${e}`);
    }
  }
}
