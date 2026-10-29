import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ContentType } from '../model/Models';

// 单个迁移步骤：必须幂等（重复执行无副作用），
// 同一套步骤同时服务"全量建表后的新装库"与"旧版本升级库"
interface DbMigrationStep {
  desc: string;
  run: (store: relationalStore.RdbStore) => Promise<void>;
}

// 版本化迁移（对齐 Mihon SQLDelight .sqm 增量迁移）：
// - 版本记录：RdbStore.version（PRAGMA user_version）
// - v1：基线 schema（迁移框架引入前的建表全集，含既有安装）
// - v2：manga.updateInterval / manga.notes / chapter.scanlator / excluded_scanlators
// - v3：plugin.contentTypes（内容类型全量列表，逗号分隔，主类型在前）
// 新增 schema 变更时：更新 createTables 到最新结构 + 追加 DbMigration 条目 + DB_VERSION 递增
interface DbMigration {
  toVersion: number;
  steps: DbMigrationStep[];
}

// RelationalStore 数据库（对齐 Mihon Room schema 的 P1 子集）
export class AppDb {
  private static readonly DB_VERSION: number = 3;
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
    hilog.info(0x0001, 'AppDb', 'database ready (v%{public}d)', AppDb.DB_VERSION);
  }

  // 版本迁移：步骤全部幂等（addColumnIfMissing / CREATE IF NOT EXISTS / INSERT OR IGNORE），
  // 新装库（建表已是最新结构）与升级库（旧表缺列）执行同一套步骤；
  // 全部成功后把 user_version 推进到 DB_VERSION，任何失败如实上抛阻止数据库就绪
  private static async migrate(store: relationalStore.RdbStore): Promise<void> {
    let version: number = 0;
    try {
      version = store.version;
    } catch (_e) {
      version = 0;
    }
    if (version >= AppDb.DB_VERSION) {
      return;
    }
    const migrations: DbMigration[] = [AppDb.MIGRATION_V2, AppDb.MIGRATION_V3];
    for (const migration of migrations) {
      if (migration.toVersion <= version) {
        continue;
      }
      for (const step of migration.steps) {
        try {
          await step.run(store);
        } catch (e) {
          throw new Error(`migrate db to v${migration.toVersion} (${step.desc}) failed: ${e}`);
        }
      }
      hilog.info(0x0001, 'AppDb', 'database migrated to v%{public}d', migration.toVersion);
    }
    try {
      store.version = AppDb.DB_VERSION;
    } catch (e) {
      throw new Error(`set db version failed: ${e}`);
    }
  }

  // v1 → v2：作品级更新间隔 / 作品备注 / 章节汉化组 / 汉化组排除表
  private static readonly MIGRATION_V2: DbMigration = {
    toVersion: 2,
    steps: [
      {
        desc: 'manga.updateInterval',
        run: (store: relationalStore.RdbStore): Promise<void> =>
          AppDb.addColumnIfMissing(store, 'manga', 'updateInterval', 'INTEGER DEFAULT 0'),
      },
      {
        desc: 'manga.notes',
        run: (store: relationalStore.RdbStore): Promise<void> =>
          AppDb.addColumnIfMissing(store, 'manga', 'notes', `TEXT DEFAULT ''`),
      },
      {
        desc: 'chapter.scanlator',
        run: (store: relationalStore.RdbStore): Promise<void> =>
          AppDb.addColumnIfMissing(store, 'chapter', 'scanlator', `TEXT DEFAULT ''`),
      },
      {
        desc: 'excluded_scanlators',
        run: (store: relationalStore.RdbStore): Promise<void> =>
          store.executeSql(`CREATE TABLE IF NOT EXISTS excluded_scanlators (
            scanlator TEXT PRIMARY KEY
          )`),
      },
    ],
  };

  // v2 → v3：多类型插件全量内容类型列表（逗号分隔，主类型在前）
  private static readonly MIGRATION_V3: DbMigration = {
    toVersion: 3,
    steps: [
      {
        desc: 'plugin.contentTypes',
        run: (store: relationalStore.RdbStore): Promise<void> =>
          AppDb.addColumnIfMissing(store, 'plugin', 'contentTypes', `TEXT DEFAULT ''`),
      },
    ],
  };

  // 已有表安全加列：先探测列存在性，缺列才 ALTER TABLE ADD COLUMN（幂等）
  private static async addColumnIfMissing(store: relationalStore.RdbStore,
    table: string, column: string, typeDef: string): Promise<void> {
    let rs: relationalStore.ResultSet | undefined = undefined;
    let has = false;
    try {
      rs = await store.querySql(`SELECT * FROM ${table} LIMIT 0`);
      has = rs.getColumnIndex(column) >= 0;
    } catch (_e) {
      has = false;
    } finally {
      if (rs !== undefined) {
        try {
          rs.close();
        } catch (_e) {
        }
      }
    }
    if (!has) {
      await store.executeSql(`ALTER TABLE ${table} ADD COLUMN ${column} ${typeDef}`);
    }
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

  // 全量建表（CREATE IF NOT EXISTS，新装库直接落最新 schema；升级库由 migrate 补齐差异）
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
        updateInterval INTEGER DEFAULT 0,
        notes TEXT DEFAULT '',
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
        scanlator TEXT DEFAULT '',
        UNIQUE(mangaId, url)
      )`);
      await store.executeSql(`CREATE TABLE IF NOT EXISTS category (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sortOrder INTEGER DEFAULT 0
      )`);
      await store.executeSql(`CREATE TABLE IF NOT EXISTS excluded_scanlators (
        scanlator TEXT PRIMARY KEY
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
        contentTypes TEXT DEFAULT '',
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
