import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppDb } from './AppDb';
import { Settings } from '../common/Settings';
import {
  CategoryRecord,
  ChapterRecord,
  ContentType,
  DuplicateManga,
  HistoryItem,
  MangaRecord,
  MangaStats,
  PluginRecord,
  SChapter,
  SManga,
  TrackRecord,
  UpcomingManga,
  UpdateItem
} from '../model/Models';

// plugin.sourcesJson 条目的最小形状（避免 Repos ↔ PluginService 循环依赖，仅解析 key 字段）
interface PluginSourceSpecRaw {
  key?: Object;
}

function closeQuietly(rs: relationalStore.ResultSet): void {
  try {
    rs.close();
  } catch (e) {
  }
}

// 异常安全的行集合读取：行映射抛错也保证游标关闭（ResultSet 为 native 资源，必须 finally 释放）
async function queryAll<R>(query: Promise<relationalStore.ResultSet>,
  mapRow: (rs: relationalStore.ResultSet) => R, context: string): Promise<R[]> {
  const rs = await query;
  const out: R[] = [];
  try {
    while (rs.goToNextRow()) {
      out.push(mapRow(rs));
    }
    return out;
  } catch (e) {
    throw new Error(`${context}: ${e}`);
  } finally {
    closeQuietly(rs);
  }
}

// 异常安全的单行读取：无行返回 undefined，行映射抛错也保证游标关闭
async function queryFirst<R>(query: Promise<relationalStore.ResultSet>,
  mapRow: (rs: relationalStore.ResultSet) => R, context: string): Promise<R | undefined> {
  const rs = await query;
  try {
    return rs.goToNextRow() ? mapRow(rs) : undefined;
  } catch (e) {
    throw new Error(`${context}: ${e}`);
  } finally {
    closeQuietly(rs);
  }
}

// 漫画仓库
export class MangaRepo {
  private static readonly COLUMNS: string[] = [
    'id', 'sourceKey', 'url', 'title', 'thumbnailUrl', 'origThumbnail', 'author',
    'description', 'genre', 'status', 'contentType', 'inLibrary', 'categoryId', 'addedAt',
    'lastUpdateAt', 'fetchedAt', 'chapterFlags', 'localCover', 'localCoverUrl',
    'updateInterval', 'notes',
  ];

  static async upsertFromSource(sourceKey: string, m: SManga, contentType: string): Promise<number> {
    // 作品级类型声明优先（SManga.contentType），未声明回退源（插件）类型
    const effectiveType: string = m.contentType !== undefined && m.contentType !== '' ?
      ContentType.normalize(m.contentType) : ContentType.normalize(contentType);
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('sourceKey', sourceKey).and().equalTo('url', m.key);
    let id = -1;
    let inLibrary = 0;
    let oldTitle = '';
    let oldThumb = '';
    let oldOrigThumb = '';
    let oldAuthor = '';
    let oldDesc = '';
    let oldGenre = '';
    let oldStatus = '';
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await store.query(pred,
        ['id', 'inLibrary', 'title', 'thumbnailUrl', 'origThumbnail', 'author', 'description', 'genre', 'status']);
      if (rs.goToNextRow()) {
        id = rs.getLong(rs.getColumnIndex('id'));
        inLibrary = rs.getLong(rs.getColumnIndex('inLibrary'));
        oldTitle = rs.getString(rs.getColumnIndex('title'));
        oldThumb = rs.getString(rs.getColumnIndex('thumbnailUrl'));
        oldOrigThumb = rs.getString(rs.getColumnIndex('origThumbnail'));
        oldAuthor = rs.getString(rs.getColumnIndex('author'));
        oldDesc = rs.getString(rs.getColumnIndex('description'));
        oldGenre = rs.getString(rs.getColumnIndex('genre'));
        oldStatus = rs.getString(rs.getColumnIndex('status'));
      }
    } catch (e) {
      throw new Error(`query manga failed: ${e}`);
    } finally {
      if (rs !== undefined) {
        closeQuietly(rs);
      }
    }
    if (id >= 0) {
      // 源返回空字段时保留旧值，避免解析回退把已有信息清空
      // 自定义封面生效中（origThumbnail 非空）不覆盖当前封面，只同步原封面地址
      let newThumb = oldThumb;
      let newOrig = oldOrigThumb;
      if (oldOrigThumb !== '') {
        newOrig = m.coverUrl !== '' ? m.coverUrl : oldOrigThumb;
      } else {
        newThumb = m.coverUrl !== '' ? m.coverUrl : oldThumb;
      }
      const values: relationalStore.ValuesBucket = {
        'title': m.title !== '' ? m.title : oldTitle,
        'thumbnailUrl': newThumb,
        'origThumbnail': newOrig,
        'author': m.author !== '' ? m.author : oldAuthor,
        'description': m.description !== '' ? m.description : oldDesc,
        'genre': m.genre !== '' ? m.genre : oldGenre,
        'status': m.status !== '' ? m.status : oldStatus,
        'contentType': effectiveType,
      };
      try {
        await store.update(values, pred);
      } catch (e) {
        throw new Error(`update manga failed: ${e}`);
      }
      return id;
    }
    const values: relationalStore.ValuesBucket = {
      'sourceKey': sourceKey,
      'url': m.key,
      'title': m.title,
      'thumbnailUrl': m.coverUrl,
      'author': m.author,
      'description': m.description,
      'genre': m.genre,
      'status': m.status,
      'contentType': effectiveType,
      'inLibrary': 0,
      'categoryId': 1,
      'addedAt': Date.now(),
    };
    const rowId = await store.insert('manga', values).catch(async (e: Object): Promise<number> => {
      const err = e as BusinessError;
      // 仅 UNIQUE(sourceKey, url) 冲突（错误码 1480009）才走回查覆盖，其余错误如实上抛
      if (err.code !== 1480009) {
        throw new Error(`manga insert failed: ${err.message}`);
      }
      // 并发插入撞 UNIQUE(sourceKey, url)：回查已存在行，按新源数据覆盖
      let rs2: relationalStore.ResultSet | undefined = undefined;
      let existingId = -1;
      try {
        rs2 = await store.query(pred, ['id']);
        if (rs2.goToNextRow()) {
          existingId = rs2.getLong(rs2.getColumnIndex('id'));
        }
      } finally {
        if (rs2 !== undefined) {
          closeQuietly(rs2);
        }
      }
      if (existingId >= 0) {
        const retry: relationalStore.ValuesBucket = {
          'title': m.title,
          'thumbnailUrl': m.coverUrl,
          'author': m.author,
          'description': m.description,
          'genre': m.genre,
          'status': m.status,
          'contentType': effectiveType,
        };
        await store.update(retry, pred);
      }
      return existingId;
    });
    return rowId;
  }

  static async get(id: number): Promise<MangaRecord | undefined> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    return queryFirst<MangaRecord>(store.query(pred, MangaRepo.COLUMNS),
      (rs: relationalStore.ResultSet): MangaRecord => MangaRepo.rowToManga(rs), 'get manga failed');
  }

  // 跨设备接续：各设备本地 mangaId 不同，须以源身份（sourceKey + 源内 url）定位作品
  static async getBySourceUrl(sourceKey: string, url: string): Promise<MangaRecord | undefined> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('sourceKey', sourceKey).and().equalTo('url', url);
    return queryFirst<MangaRecord>(store.query(pred, MangaRepo.COLUMNS),
      (rs: relationalStore.ResultSet): MangaRecord => MangaRepo.rowToManga(rs), 'get manga by source url failed');
  }

  static async getLibrary(): Promise<MangaRecord[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('inLibrary', 1).orderByAsc('categoryId').orderByAsc('id');
    return queryAll<MangaRecord>(store.query(pred, MangaRepo.COLUMNS),
      (rs: relationalStore.ResultSet): MangaRecord => MangaRepo.rowToManga(rs), 'get library failed');
  }

  // 仅切换书架标记；首次加入时按内容类型落对应默认分类（小说→小说、视频→动画、
  // 其余→漫画；同名分类被删/改名时回退 id = 1）与 addedAt，

  // 按连载状态获取书架漫画（即将推出页/卡片：连载中 + 完结连载）
  static async getLibraryByStatus(statuses: string[]): Promise<MangaRecord[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('inLibrary', 1).in('status', statuses).orderByAsc('title');
    return queryAll<MangaRecord>(store.query(pred, MangaRepo.COLUMNS),
      (rs: relationalStore.ResultSet): MangaRecord => MangaRepo.rowToManga(rs), 'get library by status failed');
  }

  // 重新加入/移出不得抹掉用户已设置的 categoryId/addedAt；
  // 首次加入按内容类型落默认分类，并在 manga_category 种子 membership（已有 membership 时不覆盖）
  static async setInLibrary(id: number, inLibrary: boolean): Promise<void> {
    const store = await AppDb.get();
    const flag = inLibrary ? 1 : 0;
    try {
      store.beginTransaction();
    } catch (e) {
      throw new Error(`set inLibrary failed: ${e}`);
    }
    try {
      await store.executeSql(
        `UPDATE manga SET inLibrary = ?,` +
          ` categoryId = CASE WHEN ? = 1 AND inLibrary = 0 THEN` +
          ` COALESCE((SELECT c.id FROM category c WHERE c.name =` +
          ` CASE manga.contentType WHEN ? THEN ? WHEN ? THEN ? ELSE ? END` +
          ` ORDER BY c.sortOrder ASC, c.id ASC LIMIT 1), 1) ELSE categoryId END,` +
          ` addedAt = CASE WHEN ? = 1 AND inLibrary = 0 THEN ? ELSE addedAt END` +
          ` WHERE id = ?`,
        [flag, flag,
          ContentType.NOVEL, ContentType.CATEGORY_NOVEL,
          ContentType.VIDEO, ContentType.CATEGORY_VIDEO,
          ContentType.CATEGORY_MANGA,
          flag, Date.now(), id]);
      if (inLibrary) {
        await store.executeSql(
          `INSERT OR IGNORE INTO manga_category(mangaId, categoryId)
           SELECT id, categoryId FROM manga WHERE id = ?`, [id]);
      }
      store.commit();
    } catch (e) {
      try {
        store.rollBack();
      } catch (e2) {
      }
      throw new Error(`set inLibrary failed: ${e}`);
    }
  }

  // 兼容包装：单分类设置（备份恢复等旧调用方），内部走多分类事务
  static async setCategory(id: number, categoryId: number): Promise<void> {
    await MangaRepo.setCategories(id, [categoryId]);
  }

  // 多分类设置（对齐 Mihon setCategories）：重写 membership，
  // manga.categoryId 冗余为 membership 中 id 最小的分类 id（空则回退 1）
  static async setCategories(id: number, categoryIds: number[]): Promise<void> {
    const store = await AppDb.get();
    const ids: number[] = [];
    const seen: Set<number> = new Set<number>();
    for (const cid of categoryIds) {
      if (!seen.has(cid)) {
        seen.add(cid);
        ids.push(cid);
      }
    }
    try {
      store.beginTransaction();
    } catch (e) {
      throw new Error(`set categories failed: ${e}`);
    }
    try {
      const pred = new relationalStore.RdbPredicates('manga_category');
      pred.equalTo('mangaId', id);
      await store.delete(pred);
      for (const cid of ids) {
        const values: relationalStore.ValuesBucket = {
          'mangaId': id,
          'categoryId': cid,
        };
        await store.insert('manga_category', values);
      }
      const primaryId: number = ids.length > 0 ? Math.min(...ids) : 1;
      const valuesManga: relationalStore.ValuesBucket = { 'categoryId': primaryId };
      const predManga = new relationalStore.RdbPredicates('manga');
      predManga.equalTo('id', id);
      await store.update(valuesManga, predManga);
      store.commit();
    } catch (e) {
      try {
        store.rollBack();
      } catch (e2) {
      }
      throw new Error(`set categories failed: ${e}`);
    }
  }

  // 某部漫画的全部分类 id（对齐 Mihon getCategories），空返回 []
  static async getCategoryIds(id: number): Promise<number[]> {
    const store = await AppDb.get();
    return queryAll<number>(store.querySql(
      `SELECT categoryId FROM manga_category WHERE mangaId = ? ORDER BY categoryId`, [id]),
      (rs: relationalStore.ResultSet): number => rs.getLong(rs.getColumnIndex('categoryId')),
      'get category ids failed');
  }

  // 全部漫画的多分类 membership（书架分组/计数/过滤用），空 membership 视为不属任何分类
  static async libraryCategoryIds(): Promise<Map<number, number[]>> {
    const store = await AppDb.get();
    const map: Map<number, number[]> = new Map<number, number[]>();
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await store.querySql(
        `SELECT mc.mangaId AS mangaId, mc.categoryId AS categoryId
         FROM manga_category mc
         JOIN manga m ON m.id = mc.mangaId
         WHERE m.inLibrary = 1
         ORDER BY mc.mangaId, mc.categoryId`);
      while (rs.goToNextRow()) {
        const mangaId: number = rs.getLong(rs.getColumnIndex('mangaId'));
        const categoryId: number = rs.getLong(rs.getColumnIndex('categoryId'));
        let list: number[] | undefined = map.get(mangaId);
        if (list === undefined) {
          list = [];
          map.set(mangaId, list);
        }
        list.push(categoryId);
      }
    } catch (e) {
      throw new Error(`library category ids failed: ${e}`);
    } finally {
      if (rs !== undefined) {
        closeQuietly(rs);
      }
    }
    return map;
  }

  // 库内疑似重复作品（对齐 Mihon getDuplicateLibraryManga）：
  // 标题互相包含（instr 忽略大小写）或绑定相同追踪器（syncId + remoteId）
  static async getDuplicateLibraryManga(id: number, title: string): Promise<DuplicateManga[]> {
    const store = await AppDb.get();
    return queryAll<DuplicateManga>(store.querySql(
      `SELECT m.id AS id, m.title AS title, m.thumbnailUrl AS coverUrl, m.author AS author,
              m.status AS status, m.sourceKey AS sourceKey,
              (SELECT COUNT(*) FROM chapter c WHERE c.mangaId = m.id) AS chapterCount
       FROM manga m
       WHERE m.inLibrary = 1 AND m.id != ?
         AND (instr(lower(m.title), lower(?)) > 0
           OR EXISTS (
             SELECT 1 FROM track t1
             JOIN track t2 ON t2.syncId = t1.syncId AND t2.remoteId = t1.remoteId
             WHERE t2.mangaId = m.id AND t1.mangaId = ?))
       ORDER BY m.title ASC`,
      [id, title, id]),
      (rs: relationalStore.ResultSet): DuplicateManga => {
        const d = new DuplicateManga();
        d.id = rs.getLong(rs.getColumnIndex('id'));
        d.title = rs.getString(rs.getColumnIndex('title'));
        d.coverUrl = rs.getString(rs.getColumnIndex('coverUrl'));
        d.author = rs.getString(rs.getColumnIndex('author'));
        d.status = rs.getString(rs.getColumnIndex('status'));
        d.sourceKey = rs.getString(rs.getColumnIndex('sourceKey'));
        d.chapterCount = rs.getLong(rs.getColumnIndex('chapterCount'));
        return d;
      }, 'get duplicate library manga failed');
  }

  // 章节列表排序/筛选标志位持久化（对齐 Mihon SetMangaChapterFlags）
  static async setChapterFlags(id: number, flags: number): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'chapterFlags': flags };
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`set chapter flags failed: ${e}`);
    }
  }

  // 按源获取书架漫画（迁移选择列表）
  static async getLibraryBySource(sourceKey: string): Promise<MangaRecord[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('inLibrary', 1).and().equalTo('sourceKey', sourceKey).orderByAsc('title');
    return queryAll<MangaRecord>(store.query(pred, MangaRepo.COLUMNS),
      (rs: relationalStore.ResultSet): MangaRecord => MangaRepo.rowToManga(rs), 'get library by source failed');
  }

  // 书架内各源漫画数（迁移源列表）
  static async countBySource(): Promise<Record<string, number>> {
    const store = await AppDb.get();
    const counts: Record<string, number> = {};
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await store.querySql(
        `SELECT sourceKey, COUNT(*) AS cnt FROM manga WHERE inLibrary = 1 GROUP BY sourceKey`);
      while (rs.goToNextRow()) {
        counts[rs.getString(rs.getColumnIndex('sourceKey'))] = rs.getLong(rs.getColumnIndex('cnt'));
      }
    } catch (e) {
      throw new Error(`count by source failed: ${e}`);
    } finally {
      if (rs !== undefined) {
        closeQuietly(rs);
      }
    }
    return counts;
  }

  // 迁移：切换源与地址并更新元数据，清空旧章节/历史/阅读时长记录（进度不保留）；自定义封面保留（对齐 Mihon）
  static async migrate(id: number, sourceKey: string, url: string, m: SManga, contentType: string): Promise<void> {
    // 作品级类型声明优先，未声明回退目标源（插件）类型
    const effectiveType: string = m.contentType !== undefined && m.contentType !== '' ?
      ContentType.normalize(m.contentType) : ContentType.normalize(contentType);
    const store = await AppDb.get();
    const predOld = new relationalStore.RdbPredicates('manga');
    predOld.equalTo('id', id);
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    try {
      store.beginTransaction();
    } catch (e) {
      throw new Error(`migrate failed: ${e}`);
    }
    try {
      // 旧封面读取移入事务内，消除读-改-写间隙的 TOCTOU
      let rsOld: relationalStore.ResultSet | undefined = undefined;
      let oldThumb = '';
      let oldOrigThumb = '';
      try {
        rsOld = await store.query(predOld, ['thumbnailUrl', 'origThumbnail']);
        if (rsOld.goToNextRow()) {
          oldThumb = rsOld.getString(rsOld.getColumnIndex('thumbnailUrl'));
          oldOrigThumb = rsOld.getString(rsOld.getColumnIndex('origThumbnail'));
        }
      } finally {
        if (rsOld !== undefined) {
          closeQuietly(rsOld);
        }
      }
      let newThumb = m.coverUrl;
      let newOrig = '';
      if (oldOrigThumb !== '') {
        // 自定义封面跟随迁移，新源封面地址顶替"原封面"待恢复地址
        newThumb = oldThumb;
        newOrig = m.coverUrl;
      }
      const values: relationalStore.ValuesBucket = {
        'sourceKey': sourceKey,
        'url': url,
        'title': m.title !== '' ? m.title : ' ',
        'thumbnailUrl': newThumb,
        'origThumbnail': newOrig,
        'author': m.author,
        'description': m.description,
        'genre': m.genre,
        'status': m.status,
        'contentType': effectiveType,
      };
      await store.update(values, pred);
      await store.executeSql(`DELETE FROM chapter WHERE mangaId = ?`, [id]);
      // 同步清理旧章节对应的历史与阅读时长记录，避免永久孤儿
      await store.executeSql(`DELETE FROM history WHERE mangaId = ?`, [id]);
      await store.executeSql(`DELETE FROM readingSession WHERE mangaId = ?`, [id]);
      store.commit();
    } catch (e) {
      try {
        store.rollBack();
      } catch (e2) {
      }
      throw new Error(`migrate failed: ${e}`);
    }
  }

  // 启用自定义封面：封面切到本地文件，原封面地址存入 origThumbnail（对齐 Mihon Edit cover）
  static async applyCustomCover(id: number, coverPath: string): Promise<void> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    let oldThumb = '';
    let oldOrigThumb = '';
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await store.query(pred, ['thumbnailUrl', 'origThumbnail']);
      if (rs.goToNextRow()) {
        oldThumb = rs.getString(rs.getColumnIndex('thumbnailUrl'));
        oldOrigThumb = rs.getString(rs.getColumnIndex('origThumbnail'));
      }
    } catch (e) {
      throw new Error(`query cover failed: ${e}`);
    } finally {
      if (rs !== undefined) {
        closeQuietly(rs);
      }
    }
    const values: relationalStore.ValuesBucket = {
      'thumbnailUrl': coverPath,
      'origThumbnail': oldOrigThumb !== '' ? oldOrigThumb : oldThumb,
    };
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`apply cover failed: ${e}`);
    }
  }

  // 恢复原封面：回退到源封面地址并清除自定义标记（对齐 Mihon Reset cover）
  static async resetCover(id: number): Promise<void> {
    const store = await AppDb.get();
    try {
      await store.executeSql(
        `UPDATE manga SET thumbnailUrl = origThumbnail, origThumbnail = '' WHERE id = ?`, [id]);
    } catch (e) {
      throw new Error(`reset cover failed: ${e}`);
    }
  }

  // 写入书架持久化封面（入库/回填时调用；srcUrl 为持久化时的源封面地址，用于变更检测）
  static async setLocalCover(id: number, path: string, srcUrl: string): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = {
      'localCover': path,
      'localCoverUrl': srcUrl,
    };
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`set local cover failed: ${e}`);
    }
  }

  // 刷新完成时写入时间戳：fetchedAt 总是更新，有新章节时一并更新 lastUpdateAt
  static async touch(id: number, updated: boolean): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = updated
      ? { 'fetchedAt': Date.now(), 'lastUpdateAt': Date.now() }
      : { 'fetchedAt': Date.now() };
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`touch manga failed: ${e}`);
    }
  }

  // 清理数据库：删除所有不在书库的作品及其章节/历史/阅读统计/追踪数据
  // （对齐 Mihon ClearDatabase 的 clearAll；书库内数据不受影响）。返回删除的作品数
  static async clearNonLibrary(): Promise<number> {
    const store = await AppDb.get();
    let count = 0;
    try {
      store.beginTransaction();
    } catch (e) {
      throw new Error(`clear database failed: ${e}`);
    }
    try {
      let rs: relationalStore.ResultSet | undefined = undefined;
      try {
        rs = await store.querySql(`SELECT COUNT(*) AS cnt FROM manga WHERE inLibrary = 0`);
        if (rs.goToNextRow()) {
          count = rs.getLong(rs.getColumnIndex('cnt'));
        }
      } finally {
        if (rs !== undefined) {
          closeQuietly(rs);
        }
      }
      await store.executeSql(`DELETE FROM chapter WHERE mangaId IN
        (SELECT id FROM manga WHERE inLibrary = 0)`);
      await store.executeSql(`DELETE FROM history WHERE mangaId IN
        (SELECT id FROM manga WHERE inLibrary = 0)`);
      await store.executeSql(`DELETE FROM readingSession WHERE mangaId IN
        (SELECT id FROM manga WHERE inLibrary = 0)`);
      await store.executeSql(`DELETE FROM track WHERE mangaId IN
        (SELECT id FROM manga WHERE inLibrary = 0)`);
      await store.executeSql(`DELETE FROM manga WHERE inLibrary = 0`);
      store.commit();
    } catch (e) {
      try {
        store.rollBack();
      } catch (e2) {
      }
      throw new Error(`clear database failed: ${e}`);
    }
    return count;
  }

  // 章节/历史聚合统计（书架排序与筛选用），一次查询全部漫画
  static async stats(): Promise<Record<string, MangaStats>> {
    const store = await AppDb.get();
    const map: Record<string, MangaStats> = {};
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await store.querySql(
        `SELECT c.mangaId AS mangaId, COUNT(*) AS total, SUM(c.read) AS readCnt,
                SUM(c.bookmark) AS bookmarkCnt, MAX(c.dateUpload) AS latest,
                (SELECT MAX(h.seenAt) FROM history h WHERE h.mangaId = c.mangaId) AS lastRead
         FROM chapter c GROUP BY c.mangaId`);
      while (rs.goToNextRow()) {
        const s = new MangaStats();
        s.mangaId = rs.getLong(rs.getColumnIndex('mangaId'));
        s.total = rs.getLong(rs.getColumnIndex('total'));
        s.readCount = rs.getLong(rs.getColumnIndex('readCnt'));
        s.bookmarkCount = rs.getLong(rs.getColumnIndex('bookmarkCnt'));
        s.latest = rs.getLong(rs.getColumnIndex('latest'));
        s.lastRead = rs.getLong(rs.getColumnIndex('lastRead'));
        s.unread = s.total - s.readCount;
        map[`${s.mangaId}`] = s;
      }
    } catch (e) {
      throw new Error(`stats failed: ${e}`);
    } finally {
      if (rs !== undefined) {
        closeQuietly(rs);
      }
    }
    return map;
  }

  // 作品级自定义更新间隔（小时：0 跟随默认 / -1 从不 / >0 小时，对齐 Mihon manga.updateInterval）
  static async setUpdateInterval(id: number, hours: number): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'updateInterval': hours };
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`set update interval failed: ${e}`);
    }
  }

  // 用户备注（对齐 Mihon manga.notes）
  static async setNotes(id: number, notes: string): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'notes': notes };
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`set notes failed: ${e}`);
    }
  }

  private static rowToManga(rs: relationalStore.ResultSet): MangaRecord {
    try {
      const m = new MangaRecord();
      m.id = rs.getLong(rs.getColumnIndex('id'));
      m.sourceKey = rs.getString(rs.getColumnIndex('sourceKey'));
      m.url = rs.getString(rs.getColumnIndex('url'));
      m.title = rs.getString(rs.getColumnIndex('title'));
      m.thumbnailUrl = rs.getString(rs.getColumnIndex('thumbnailUrl'));
      m.origThumbnail = rs.getString(rs.getColumnIndex('origThumbnail'));
      m.author = rs.getString(rs.getColumnIndex('author'));
      m.description = rs.getString(rs.getColumnIndex('description'));
      m.genre = rs.getString(rs.getColumnIndex('genre'));
      m.status = rs.getString(rs.getColumnIndex('status'));
      m.contentType = ContentType.normalize(rs.getString(rs.getColumnIndex('contentType')));
      m.inLibrary = rs.getLong(rs.getColumnIndex('inLibrary')) === 1;
      m.categoryId = rs.getLong(rs.getColumnIndex('categoryId'));
      m.addedAt = rs.getLong(rs.getColumnIndex('addedAt'));
      m.lastUpdateAt = rs.getLong(rs.getColumnIndex('lastUpdateAt'));
      m.fetchedAt = rs.getLong(rs.getColumnIndex('fetchedAt'));
      m.chapterFlags = rs.getLong(rs.getColumnIndex('chapterFlags'));
      m.localCover = rs.getString(rs.getColumnIndex('localCover'));
      m.localCoverUrl = rs.getString(rs.getColumnIndex('localCoverUrl'));
      m.updateInterval = rs.getLong(rs.getColumnIndex('updateInterval'));
      m.notes = rs.getString(rs.getColumnIndex('notes'));
      return m;
    } catch (e) {
      throw new Error(`map manga row failed: ${e}`);
    }
  }
}

// 章节仓库
export class ChapterRepo {
  private static readonly COLUMNS: string[] = [
    'id', 'mangaId', 'url', 'name', 'chapterNumber', 'dateUpload',
    'pages', 'sortOrder', 'read', 'bookmark', 'lastPageRead', 'scanlator',
  ];

  static async getById(id: number): Promise<ChapterRecord | undefined> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('id', id);
    return queryFirst<ChapterRecord>(store.query(pred, ChapterRepo.COLUMNS),
      (rs: relationalStore.ResultSet): ChapterRecord => ChapterRepo.rowToChapter(rs), 'get chapter failed');
  }

  // 跨设备接续：按作品 id + 源内 url 定位章节（对端 chapterId 与本机不可比）
  static async getByMangaUrl(mangaId: number, url: string): Promise<ChapterRecord | undefined> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('mangaId', mangaId).and().equalTo('url', url);
    return queryFirst<ChapterRecord>(store.query(pred, ChapterRepo.COLUMNS),
      (rs: relationalStore.ResultSet): ChapterRecord => ChapterRepo.rowToChapter(rs), 'get chapter by url failed');
  }

  static async listByManga(mangaId: number): Promise<ChapterRecord[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('mangaId', mangaId).orderByAsc('sortOrder').orderByAsc('id');
    return queryAll<ChapterRecord>(store.query(pred, ChapterRepo.COLUMNS),
      (rs: relationalStore.ResultSet): ChapterRecord => ChapterRepo.rowToChapter(rs), 'list chapters failed');
  }

  // 用源返回的章节列表全量刷新本地记录：保留仍在源中的章节已读状态、

  // 第一条未读章节完整记录（漫画卡片续读回退；id 版本见 firstUnread）
  static async firstUnreadChapter(mangaId: number): Promise<ChapterRecord | undefined> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('mangaId', mangaId)
      .and()
      .equalTo('read', 0)
      .orderByAsc('sortOrder')
      .orderByAsc('id');
    pred.limitAs(1);
    return queryFirst<ChapterRecord>(store.query(pred, ChapterRepo.COLUMNS),
      (rs: relationalStore.ResultSet): ChapterRecord => ChapterRepo.rowToChapter(rs), 'first unread chapter failed');
  }

  // 删除源已移除的章节（含历史，章节可能在源端被删除）；返回新增章节数
  static async syncFromSource(mangaId: number, chapters: SChapter[]): Promise<number> {
    const store = await AppDb.get();
    let newCount = 0;
    try {
      store.beginTransaction();
    } catch (e) {
      throw new Error(`syncFromSource failed: ${e}`);
    }
    try {
      // existing 读取移入事务内，避免读取与写入之间被并发更新插入竞态
      const existing = await ChapterRepo.listByManga(mangaId);
      const existingKeys = new Set<string>();
      for (const c of existing) {
        existingKeys.add(c.url);
      }
      const sourceKeys = new Set<string>();
      for (const c of chapters) {
        sourceKeys.add(c.key);
      }
      for (const c of chapters) {
        if (existingKeys.has(c.key)) {
          const values: relationalStore.ValuesBucket = {
            'name': c.name,
            'chapterNumber': c.chapterNumber,
            'dateUpload': c.dateUpload,
            'pages': c.pages,
            'sortOrder': c.sortOrder,
            'scanlator': c.scanlator ?? '',
          };
          const pred = new relationalStore.RdbPredicates('chapter');
          pred.equalTo('mangaId', mangaId).and().equalTo('url', c.key);
          await store.update(values, pred);
        } else {
          const values: relationalStore.ValuesBucket = {
            'mangaId': mangaId,
            'url': c.key,
            'name': c.name,
            'chapterNumber': c.chapterNumber,
            'dateUpload': c.dateUpload,
            'pages': c.pages,
            'sortOrder': c.sortOrder,
            'read': 0,
            'bookmark': 0,
            'lastPageRead': 0,
            'scanlator': c.scanlator ?? '',
          };
          await store.insert('chapter', values);
          newCount += 1;
        }
      }
      // 移除源已删除的章节及其历史记录
      for (const c of existing) {
        if (!sourceKeys.has(c.url)) {
          const chapterPred = new relationalStore.RdbPredicates('chapter');
          chapterPred.equalTo('id', c.id);
          await store.delete(chapterPred);
          const historyPred = new relationalStore.RdbPredicates('history');
          historyPred.equalTo('chapterId', c.id);
          await store.delete(historyPred);
        }
      }
      store.commit();
    } catch (e) {
      try {
        store.rollBack();
      } catch (e2) {
      }
      throw new Error(`syncFromSource failed: ${e}`);
    }
    return newCount;
  }

  static async setRead(id: number, read: boolean): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'read': read ? 1 : 0 };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('id', id);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`set read failed: ${e}`);
    }
  }

  static async setBookmark(id: number, bookmark: boolean): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'bookmark': bookmark ? 1 : 0 };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('id', id);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`set bookmark failed: ${e}`);
    }
  }

  // 批量设置已读状态（章节多选"标为已读/未读"，单条 IN 谓词一次提交）
  static async setReadForIds(ids: number[], read: boolean): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'read': read ? 1 : 0 };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.in('id', ids);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`set read for ids failed: ${e}`);
    }
  }

  // 批量设置书签（章节多选"添加/移除书签"，单条 IN 谓词一次提交）
  static async setBookmarkForIds(ids: number[], bookmark: boolean): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'bookmark': bookmark ? 1 : 0 };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.in('id', ids);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`set bookmark for ids failed: ${e}`);
    }
  }

  static async setLastPageRead(id: number, page: number): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'lastPageRead': page };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('id', id);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`set last page read failed: ${e}`);
    }
  }

  static async markAllRead(mangaId: number, read: boolean): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'read': read ? 1 : 0 };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('mangaId', mangaId);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`mark all read failed: ${e}`);
    }
  }

  static async unreadCount(mangaId: number): Promise<number> {
    const store = await AppDb.get();
    return await queryFirst<number>(store.querySql(
      `SELECT COUNT(*) AS cnt FROM chapter WHERE mangaId = ? AND read = 0`, [mangaId]),
      (rs: relationalStore.ResultSet): number => rs.getLong(rs.getColumnIndex('cnt')),
      'unread count failed') ?? 0;
  }

  // 备份恢复用：章节不存在则插入，存在则仅恢复阅读状态；

  // 备份恢复用：按 mangaId+url 更新阅读状态
  static async applyStateByUrl(mangaId: number, url: string, read: boolean, lastPageRead: number): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = {
      'read': read ? 1 : 0,
      'lastPageRead': lastPageRead,
    };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('mangaId', mangaId).and().equalTo('url', url);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`apply state failed: ${e}`);
    }
  }

  // chapter 表 UNIQUE(mangaId, url) 支撑单条 INSERT ON CONFLICT 原子完成
  static async upsertBackup(mangaId: number, url: string, name: string, chapterNumber: number,
    read: boolean, lastPageRead: number): Promise<void> {
    const store = await AppDb.get();
    try {
      await store.executeSql(
        `INSERT INTO chapter (mangaId, url, name, chapterNumber, dateUpload, pages, sortOrder, read, bookmark, lastPageRead)
         VALUES (?, ?, ?, ?, 0, 0, 0, ?, 0, ?)
         ON CONFLICT(mangaId, url) DO UPDATE SET read = excluded.read, lastPageRead = excluded.lastPageRead`,
        [mangaId, url, name, chapterNumber, read ? 1 : 0, lastPageRead]);
    } catch (e) {
      throw new Error(`upsert backup failed: ${e}`);
    }
  }

  static async setPages(id: number, pages: number): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'pages': pages };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('id', id);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`set pages failed: ${e}`);
    }
  }

  // 第一个未读章节 id（无未读返回 -1），供"继续阅读"按钮
  static async firstUnread(mangaId: number): Promise<number> {
    const store = await AppDb.get();
    return await queryFirst<number>(store.querySql(
      `SELECT id FROM chapter WHERE mangaId = ? AND read = 0 ORDER BY sortOrder ASC, id ASC LIMIT 1`, [mangaId]),
      (rs: relationalStore.ResultSet): number => rs.getLong(rs.getColumnIndex('id')),
      'first unread failed') ?? -1;
  }

  static async countRead(mangaId: number): Promise<number> {
    const store = await AppDb.get();
    return await queryFirst<number>(store.querySql(
      `SELECT COUNT(*) AS cnt FROM chapter WHERE mangaId = ? AND read = 1`, [mangaId]),
      (rs: relationalStore.ResultSet): number => rs.getLong(rs.getColumnIndex('cnt')),
      'count read failed') ?? 0;
  }

  private static rowToChapter(rs: relationalStore.ResultSet): ChapterRecord {
    try {
      const c = new ChapterRecord();
      c.id = rs.getLong(rs.getColumnIndex('id'));
      c.mangaId = rs.getLong(rs.getColumnIndex('mangaId'));
      c.url = rs.getString(rs.getColumnIndex('url'));
      c.name = rs.getString(rs.getColumnIndex('name'));
      c.chapterNumber = rs.getDouble(rs.getColumnIndex('chapterNumber'));
      c.dateUpload = rs.getLong(rs.getColumnIndex('dateUpload'));
      c.pages = rs.getLong(rs.getColumnIndex('pages'));
      c.sortOrder = rs.getLong(rs.getColumnIndex('sortOrder'));
      c.read = rs.getLong(rs.getColumnIndex('read')) === 1;
      c.bookmark = rs.getLong(rs.getColumnIndex('bookmark')) === 1;
      c.lastPageRead = rs.getLong(rs.getColumnIndex('lastPageRead'));
      c.scanlator = rs.getString(rs.getColumnIndex('scanlator'));
      return c;
    } catch (e) {
      throw new Error(`map chapter row failed: ${e}`);
    }
  }
}

// 汉化组排除仓库（excluded_scanlators 表，对齐 Mihon ExcludedScanlators）：
// 全局隐藏指定汉化组的章节（详情页章节列表与阅读器换章时过滤）
export class ExcludedScanlatorRepo {
  static async list(): Promise<string[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('excluded_scanlators');
    pred.orderByAsc('scanlator');
    return queryAll<string>(store.query(pred, ['scanlator']),
      (rs: relationalStore.ResultSet): string => rs.getString(rs.getColumnIndex('scanlator')),
      'list excluded scanlators failed');
  }

  static async add(name: string): Promise<void> {
    const trimmed = name.trim();
    if (trimmed === '') {
      return;
    }
    const store = await AppDb.get();
    try {
      await store.executeSql(`INSERT OR IGNORE INTO excluded_scanlators (scanlator) VALUES (?)`, [trimmed]);
    } catch (e) {
      throw new Error(`add excluded scanlator failed: ${e}`);
    }
  }

  static async remove(name: string): Promise<void> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('excluded_scanlators');
    pred.equalTo('scanlator', name);
    try {
      await store.delete(pred);
    } catch (e) {
      throw new Error(`remove excluded scanlator failed: ${e}`);
    }
  }
}

// 分类仓库
export class CategoryRepo {
  static async list(): Promise<CategoryRecord[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('category');
    pred.orderByAsc('sortOrder').orderByAsc('id');
    return queryAll<CategoryRecord>(store.query(pred, ['id', 'name', 'sortOrder']),
      (rs: relationalStore.ResultSet): CategoryRecord => {
        const c = new CategoryRecord();
        c.id = rs.getLong(rs.getColumnIndex('id'));
        c.name = rs.getString(rs.getColumnIndex('name'));
        c.sortOrder = rs.getLong(rs.getColumnIndex('sortOrder'));
        return c;
      }, 'list categories failed');
  }

  static async add(name: string): Promise<void> {
    // 禁止用内置分类 code 建分类（会造成同名默认分类且不可编辑）
    if (ContentType.isBuiltinCategory(name)) {
      return;
    }
    const store = await AppDb.get();
    // sortOrder 取当前总数，单条语句原子完成（消除查后写竞态）
    try {
      await store.executeSql(
        `INSERT INTO category (name, sortOrder) VALUES (?, (SELECT COUNT(*) FROM category))`, [name]);
    } catch (e) {
      throw new Error(`add category failed: ${e}`);
    }
  }

  static async rename(id: number, name: string): Promise<void> {
    if (id === 1 || name === '') {
      return;
    }
    const store = await AppDb.get();
    // 内置默认分类（漫画/小说/动画）不可改名；也不允许改成内置 code
    const current = await CategoryRepo.nameOf(store, id);
    if (ContentType.isBuiltinCategory(current) || ContentType.isBuiltinCategory(name)) {
      return;
    }
    const values: relationalStore.ValuesBucket = { 'name': name };
    const pred = new relationalStore.RdbPredicates('category');
    pred.equalTo('id', id);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`rename category failed: ${e}`);
    }
  }

  // 按给定顺序重写 sortOrder（拖拽排序持久化），事务内完成
  static async reorder(orderedIds: number[]): Promise<void> {
    const store = await AppDb.get();
    try {
      store.beginTransaction();
    } catch (e) {
      throw new Error(`category reorder failed: ${e}`);
    }
    try {
      for (let i = 0; i < orderedIds.length; i++) {
        const values: relationalStore.ValuesBucket = { 'sortOrder': i };
        const pred = new relationalStore.RdbPredicates('category');
        pred.equalTo('id', orderedIds[i]);
        await store.update(values, pred);
      }
      store.commit();
    } catch (e) {
      try {
        store.rollBack();
      } catch (e2) {
      }
      throw new Error(`category reorder failed: ${e}`);
    }
  }

  static async remove(id: number): Promise<void> {
    if (id === 1) {
      return;
    }
    const store = await AppDb.get();
    // 内置默认分类（漫画/小说/动画）不可删除
    if (ContentType.isBuiltinCategory(await CategoryRepo.nameOf(store, id))) {
      return;
    }
    // 清理/回填 membership + 重算主分类 + 删除分类，同一事务内完成
    const predCategory = new relationalStore.RdbPredicates('category');
    predCategory.equalTo('id', id);
    try {
      store.beginTransaction();
    } catch (e) {
      throw new Error(`category remove failed: ${e}`);
    }
    try {
      // 1) 删除该分类的全部 membership
      await store.executeSql(`DELETE FROM manga_category WHERE categoryId = ?`, [id]);
      // 2) membership 清空的在库漫画回退默认分类 1
      await store.executeSql(
        `INSERT OR IGNORE INTO manga_category(mangaId, categoryId)
         SELECT id, 1 FROM manga
         WHERE inLibrary = 1
           AND NOT EXISTS (SELECT 1 FROM manga_category mc WHERE mc.mangaId = manga.id)`);
      // 3) 主分类冗余列统一按 membership 最小 id 重算
      await store.executeSql(
        `UPDATE manga SET categoryId = COALESCE(
           (SELECT MIN(mc.categoryId) FROM manga_category mc WHERE mc.mangaId = manga.id), 1)`);
      await store.delete(predCategory);
      store.commit();
    } catch (e) {
      try {
        store.rollBack();
      } catch (e2) {
      }
      throw new Error(`category remove failed: ${e}`);
    }
  }

  // 按分类 id 查分类名（编辑守卫用；查不到返回空串）
  private static async nameOf(store: relationalStore.RdbStore, id: number): Promise<string> {
    const pred = new relationalStore.RdbPredicates('category');
    pred.equalTo('id', id);
    try {
      return await queryFirst<string>(store.query(pred, ['name']),
        (rs: relationalStore.ResultSet): string => rs.getString(rs.getColumnIndex('name')),
        'name of category failed') ?? '';
    } catch (e) {
    }
    return '';
  }
}

// 阅读历史仓库
export class HistoryRepo {
  static async upsert(mangaId: number, chapterId: number, lastPageRead: number): Promise<void> {
    // 无痕模式（全局开关 / 作品所属插件被「按插件隐身」）不记录阅读历史
    // （对齐 Mihon incognito / incognitoExtensions）
    if (await HistoryRepo.isIncognitoFor(mangaId)) {
      return;
    }
    const store = await AppDb.get();
    // v2 起有 UNIQUE(mangaId, chapterId) 索引，单条原子 upsert
    try {
      await store.executeSql(
        `INSERT INTO history (mangaId, chapterId, seenAt, lastPageRead) VALUES (?, ?, ?, ?)
         ON CONFLICT(mangaId, chapterId) DO UPDATE SET seenAt = excluded.seenAt, lastPageRead = excluded.lastPageRead`,
        [mangaId, chapterId, Date.now(), lastPageRead]);
    } catch (e) {
      throw new Error(`upsert history failed: ${e}`);
    }
  }

  // 无痕判定（中心化消费点）：全局无痕开启，或作品所属插件被「按插件隐身」。
  // 返回 true 时 history / readingStats 一律不落库。
  static async isIncognitoFor(mangaId: number): Promise<boolean> {
    if (Settings.getIncognito()) {
      return true;
    }
    if (!Settings.hasIncognitoPlugins()) {
      return false;
    }
    const store = await AppDb.get();
    const sourceKey = await queryFirst<string>(
      store.querySql(`SELECT sourceKey FROM manga WHERE id = ?`, [mangaId]),
      (rs: relationalStore.ResultSet): string => rs.getString(rs.getColumnIndex('sourceKey')),
      'sourceKey of manga failed') ?? '';
    if (sourceKey === '') {
      return false;
    }
    const pluginKey = await PluginRepo.pluginKeyOfSource(sourceKey);
    return Settings.isPluginIncognito(pluginKey);
  }

  static async recent(limit: number): Promise<HistoryItem[]> {
    const store = await AppDb.get();
    return queryAll<HistoryItem>(store.querySql(
      `SELECT h.mangaId AS mangaId, h.chapterId AS chapterId, h.seenAt AS seenAt,
              h.lastPageRead AS lastPageRead, m.title AS mangaTitle,
              m.sourceKey AS sourceKey,
              m.thumbnailUrl AS coverUrl, c.name AS chapterName,
              m.inLibrary AS inLibrary
       FROM history h
       JOIN manga m ON m.id = h.mangaId
       JOIN chapter c ON c.id = h.chapterId
       ORDER BY h.seenAt DESC LIMIT ?`, [limit]),
      (rs: relationalStore.ResultSet): HistoryItem => HistoryRepo.rowToItem(rs), 'recent history failed');
  }

  // 某部漫画最近一条阅读记录（漫画卡片续读章节）
  static async lastForManga(mangaId: number): Promise<HistoryItem | undefined> {
    const store = await AppDb.get();
    return queryFirst<HistoryItem>(store.querySql(
      `SELECT h.mangaId AS mangaId, h.chapterId AS chapterId, h.seenAt AS seenAt,
              h.lastPageRead AS lastPageRead, m.title AS mangaTitle,
              m.sourceKey AS sourceKey,
              m.thumbnailUrl AS coverUrl, c.name AS chapterName
       FROM history h
       JOIN manga m ON m.id = h.mangaId
       JOIN chapter c ON c.id = h.chapterId
       WHERE h.mangaId = ?
       ORDER BY h.seenAt DESC LIMIT 1`, [mangaId]),
      (rs: relationalStore.ResultSet): HistoryItem => HistoryRepo.rowToItem(rs), 'last for manga failed');
  }

  // 最近阅读的书架内漫画（漫画卡片默认绑定）
  static async lastInLibrary(): Promise<HistoryItem | undefined> {
    const store = await AppDb.get();
    return queryFirst<HistoryItem>(store.querySql(
      `SELECT h.mangaId AS mangaId, h.chapterId AS chapterId, h.seenAt AS seenAt,
              h.lastPageRead AS lastPageRead, m.title AS mangaTitle,
              m.sourceKey AS sourceKey,
              m.thumbnailUrl AS coverUrl, c.name AS chapterName
       FROM history h
       JOIN manga m ON m.id = h.mangaId
       JOIN chapter c ON c.id = h.chapterId
       WHERE m.inLibrary = 1
       ORDER BY h.seenAt DESC LIMIT 1`, []),
      (rs: relationalStore.ResultSet): HistoryItem => HistoryRepo.rowToItem(rs), 'last in library failed');
  }

  // 最近一次听读的小说记录（意图"继续听书"：按小说类型过滤最近历史）
  static async lastNovel(): Promise<HistoryItem | undefined> {
    const store = await AppDb.get();
    return queryFirst<HistoryItem>(store.querySql(
      `SELECT h.mangaId AS mangaId, h.chapterId AS chapterId, h.seenAt AS seenAt,
              h.lastPageRead AS lastPageRead, m.title AS mangaTitle,
              m.sourceKey AS sourceKey,
              m.thumbnailUrl AS coverUrl, c.name AS chapterName
       FROM history h
       JOIN manga m ON m.id = h.mangaId
       JOIN chapter c ON c.id = h.chapterId
       WHERE m.contentType = 'novel'
       ORDER BY h.seenAt DESC LIMIT 1`, []),
      (rs: relationalStore.ResultSet): HistoryItem => HistoryRepo.rowToItem(rs), 'last novel failed');
  }

  static async clear(): Promise<void> {
    const store = await AppDb.get();
    try {
      await store.delete(new relationalStore.RdbPredicates('history'));
    } catch (e) {
      throw new Error(`clear history failed: ${e}`);
    }
  }

  // 删除指定章节的阅读记录（历史页多选删除）
  static async removeByChapters(chapterIds: number[]): Promise<void> {
    if (chapterIds.length === 0) {
      return;
    }
    const store = await AppDb.get();
    try {
      const pred = new relationalStore.RdbPredicates('history');
      pred.in('chapterId', chapterIds);
      await store.delete(pred);
    } catch (e) {
      throw new Error(`remove history failed: ${e}`);
    }
  }

  // 行 → HistoryItem 统一映射（recent/lastForManga/lastInLibrary 共用）；
  // inLibrary 列仅 recent 查询携带，其余查询走列存在性探测
  private static rowToItem(rs: relationalStore.ResultSet): HistoryItem {
    try {
      const item = HistoryItem.of(
        rs.getLong(rs.getColumnIndex('mangaId')),
        rs.getLong(rs.getColumnIndex('chapterId')),
        rs.getString(rs.getColumnIndex('mangaTitle')),
        rs.getString(rs.getColumnIndex('coverUrl')),
        rs.getString(rs.getColumnIndex('chapterName')),
        rs.getLong(rs.getColumnIndex('seenAt')),
        rs.getLong(rs.getColumnIndex('lastPageRead')),
        rs.getString(rs.getColumnIndex('sourceKey')));
      const inLibraryIdx: number = rs.getColumnIndex('inLibrary');
      if (inLibraryIdx >= 0) {
        item.inLibrary = rs.getLong(inLibraryIdx) === 1;
      }
      return item;
    } catch (e) {
      throw new Error(`map history row failed: ${e}`);
    }
  }
}

// 更新页查询
export class UpdatesRepo {
  static async unreadChapters(limit: number): Promise<UpdateItem[]> {
    const store = await AppDb.get();
    return queryAll<UpdateItem>(store.querySql(
      `SELECT c.id AS chapterId, c.mangaId AS mangaId, c.name AS chapterName,
              c.dateUpload AS dateUpload, c.read AS readFlag, c.bookmark AS bookmarkFlag,
              m.title AS mangaTitle, m.sourceKey AS sourceKey, m.thumbnailUrl AS coverUrl
       FROM chapter c
       JOIN manga m ON m.id = c.mangaId
       WHERE m.inLibrary = 1 AND c.read = 0
       ORDER BY c.dateUpload DESC LIMIT ?`, [limit]),
      (rs: relationalStore.ResultSet): UpdateItem => UpdateItem.of(
        rs.getLong(rs.getColumnIndex('mangaId')),
        rs.getLong(rs.getColumnIndex('chapterId')),
        rs.getString(rs.getColumnIndex('mangaTitle')),
        rs.getString(rs.getColumnIndex('coverUrl')),
        rs.getString(rs.getColumnIndex('chapterName')),
        rs.getLong(rs.getColumnIndex('dateUpload')),
        rs.getLong(rs.getColumnIndex('readFlag')) === 1,
        rs.getLong(rs.getColumnIndex('bookmarkFlag')) === 1,
        rs.getString(rs.getColumnIndex('sourceKey'))), 'unread chapters failed');
  }

  // 未读章节总数（更新卡片角标）
  static async unreadCount(): Promise<number> {
    const store = await AppDb.get();
    return await queryFirst<number>(store.querySql(
      `SELECT COUNT(*) AS n
       FROM chapter c
       JOIN manga m ON m.id = c.mangaId
       WHERE m.inLibrary = 1 AND c.read = 0`),
      (rs: relationalStore.ResultSet): number => rs.getLong(rs.getColumnIndex('n')),
      'updates unread count failed') ?? 0;
  }

  // 按筛选条件查询更新章节（对齐 Mihon GetUpdates：unread/started/bookmarked/分类走 SQL，downloaded 由调用方内存过滤）
  static async filteredChapters(query: UpdatesQuery, limit: number): Promise<UpdateItem[]> {
    const store = await AppDb.get();
    let sql: string =
      `SELECT c.id AS chapterId, c.mangaId AS mangaId, c.name AS chapterName,
              c.dateUpload AS dateUpload, c.read AS readFlag, c.bookmark AS bookmarkFlag,
              m.title AS mangaTitle, m.sourceKey AS sourceKey, m.thumbnailUrl AS coverUrl
       FROM chapter c
       JOIN manga m ON m.id = c.mangaId
       WHERE m.inLibrary = 1`;
    const args: Array<string | number> = [];
    if (query.unread === 'include') {
      sql += ' AND c.read = 0';
    } else if (query.unread === 'exclude') {
      sql += ' AND c.read = 1';
    }
    if (query.bookmarked === 'include') {
      sql += ' AND c.bookmark = 1';
    } else if (query.bookmarked === 'exclude') {
      sql += ' AND c.bookmark = 0';
    }
    if (query.started === 'include') {
      sql += ' AND c.lastPageRead > 0';
    } else if (query.started === 'exclude') {
      sql += ' AND c.lastPageRead = 0';
    }
    if (query.includedCategories.length > 0) {
      const marks: string[] = [];
      for (const id of query.includedCategories) {
        marks.push('?');
        args.push(id);
      }
      sql += ` AND m.categoryId IN (${marks.join(',')})`;
    }
    if (query.excludedCategories.length > 0) {
      const marks: string[] = [];
      for (const id of query.excludedCategories) {
        marks.push('?');
        args.push(id);
      }
      sql += ` AND m.categoryId NOT IN (${marks.join(',')})`;
    }
    sql += ' ORDER BY c.dateUpload DESC LIMIT ?';
    args.push(limit);
    return queryAll<UpdateItem>(store.querySql(sql, args),
      (rs: relationalStore.ResultSet): UpdateItem => UpdateItem.of(
        rs.getLong(rs.getColumnIndex('mangaId')),
        rs.getLong(rs.getColumnIndex('chapterId')),
        rs.getString(rs.getColumnIndex('mangaTitle')),
        rs.getString(rs.getColumnIndex('coverUrl')),
        rs.getString(rs.getColumnIndex('chapterName')),
        rs.getLong(rs.getColumnIndex('dateUpload')),
        rs.getLong(rs.getColumnIndex('readFlag')) === 1,
        rs.getLong(rs.getColumnIndex('bookmarkFlag')) === 1,
        rs.getString(rs.getColumnIndex('sourceKey'))), 'filtered chapters failed');
  }
}

// 更新页筛选条件（对齐 Mihon UpdatesPreferences：三态 + 分类包含/排除）
export class UpdatesQuery {
  downloaded: string = 'ignore';
  unread: string = 'ignore';
  started: string = 'ignore';
  bookmarked: string = 'ignore';
  includedCategories: number[] = [];
  excludedCategories: number[] = [];
}

// 即将推出页查询（对齐 Mihon GetUpcomingManga + FetchInterval 的预计更新推算）
export class UpcomingRepo {
  private static readonly DAY_MS: number = 24 * 60 * 60 * 1000;
  private static readonly MAX_INTERVAL: number = 28;

  // 书架内连载中/完结连载漫画的预计更新列表（按预计时间升序、标题次序），
  // 即将推出页与桌面卡片共用；分类筛选由调用方自行应用
  static async upcomingList(): Promise<UpcomingManga[]> {
    const library = await MangaRepo.getLibraryByStatus(['ongoing', 'publication_complete']);
    const dates = await UpcomingRepo.chapterUploadDates();
    const now: number = Date.now();
    const list: UpcomingManga[] = [];
    for (const m of library) {
      const um: UpcomingManga = new UpcomingManga();
      um.mangaId = m.id;
      um.title = m.title;
      um.coverUrl = m.thumbnailUrl;
      um.categoryId = m.categoryId;
      const chapterDates: number[] = dates[`${m.id}`] ?? [];
      um.expectedAt = UpcomingRepo.nextUpdate(m.lastUpdateAt, UpcomingRepo.calcInterval(chapterDates), now);
      list.push(um);
    }
    list.sort((a: UpcomingManga, b: UpcomingManga): number => {
      if (a.expectedAt !== b.expectedAt) {
        return a.expectedAt - b.expectedAt;
      }
      return a.title < b.title ? -1 : (a.title > b.title ? 1 : 0);
    });
    return list;
  }

  // 各书架漫画的章节上传时间（降序，每部限量 200 条供间隔推算：批量更新时也能取满去重天数）
  static async chapterUploadDates(): Promise<Record<string, number[]>> {
    const store = await AppDb.get();
    const map: Record<string, number[]> = {};
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await store.querySql(
        `SELECT c.mangaId AS mangaId, c.dateUpload AS dateUpload
         FROM chapter c
         JOIN manga m ON m.id = c.mangaId
         WHERE m.inLibrary = 1 AND c.dateUpload > 0
         ORDER BY c.dateUpload DESC`);
      while (rs.goToNextRow()) {
        const key: string = `${rs.getLong(rs.getColumnIndex('mangaId'))}`;
        let list: number[] | undefined = map[key];
        if (list === undefined) {
          list = [];
          map[key] = list;
        }
        if (list.length < 200) {
          list.push(rs.getLong(rs.getColumnIndex('dateUpload')));
        }
      }
    } catch (e) {
      throw new Error(`chapter upload dates failed: ${e}`);
    } finally {
      if (rs !== undefined) {
        closeQuietly(rs);
      }
    }
    return map;
  }

  // 章节发布间隔（天）：上传日去重后取相邻间隔中位数，不足 3 天回退 7 天（对齐 FetchInterval.calculateInterval）
  static calcInterval(dates: number[]): number {
    const win: number = dates.length <= 8 ? 3 : 10;
    const dayStarts: number[] = [];
    for (const t of dates) {
      if (t <= 0) {
        continue;
      }
      const ds: number = UpcomingRepo.startOfDay(t);
      if (dayStarts.length === 0 || dayStarts[dayStarts.length - 1] !== ds) {
        dayStarts.push(ds);
      }
      if (dayStarts.length >= win) {
        break;
      }
    }
    let interval: number = 7;
    if (dayStarts.length >= 3) {
      const ranges: number[] = [];
      for (let i = 1; i < dayStarts.length; i++) {
        ranges.push(Math.round((dayStarts[i - 1] - dayStarts[i]) / UpcomingRepo.DAY_MS));
      }
      ranges.sort((a: number, b: number): number => a - b);
      interval = ranges[Math.floor((ranges.length - 1) / 2)];
    }
    if (interval < 1) {
      interval = 1;
    }
    if (interval > UpcomingRepo.MAX_INTERVAL) {
      interval = UpcomingRepo.MAX_INTERVAL;
    }
    return interval;
  }

  // 倍增后的 adjusted 全程统一使用，确保不返回过去的时间
  static nextUpdate(lastUpdateAt: number, interval: number, now: number): number {
    const latest: number = UpcomingRepo.startOfDay(lastUpdateAt > 0 ? lastUpdateAt : now);
    const daysSince: number = Math.max(0, Math.floor((now - latest) / UpcomingRepo.DAY_MS));
    const adjusted: number = UpcomingRepo.increaseInterval(interval, daysSince);
    const cycle: number = Math.floor(daysSince / adjusted);
    let next: number = latest + (cycle + 1) * adjusted * UpcomingRepo.DAY_MS;
    if (next <= now) {
      next = latest + (cycle + 2) * adjusted * UpcomingRepo.DAY_MS;
    }
    return next;
  }

  private static startOfDay(ms: number): number {
    const d: Date = new Date(ms);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  }

  // 预计下次更新时间（对齐 FetchInterval.calculateNextUpdate，返回当日零点时间戳）；

  // 逾期超过 10 个周期时倍增检查周期（对齐 FetchInterval.increaseInterval）
  private static increaseInterval(delta: number, daysSinceLatest: number): number {
    if (delta >= UpcomingRepo.MAX_INTERVAL) {
      return UpcomingRepo.MAX_INTERVAL;
    }
    const cycle: number = Math.floor(daysSinceLatest / delta) + 1;
    if (cycle > 10) {
      return UpcomingRepo.increaseInterval(delta * 2, daysSinceLatest);
    }
    return delta;
  }
}

// 追踪仓库（多追踪器，对齐 Mihon TrackRepo：每漫画 × 每 syncId 一条记录）
export class TrackRepo {
  private static readonly COLUMNS: string[] = [
    'id', 'mangaId', 'syncId', 'remoteId', 'libraryId', 'title', 'status', 'lastChapterRead',
    'score', 'totalChapters', 'remoteUrl', 'startDate', 'finishDate', 'isPrivate',
  ];

  // 已绑定追踪的漫画 id 集合（书架"已追踪"筛选用）
  static async trackedMangaIds(): Promise<Set<number>> {
    const store = await AppDb.get();
    const rows = await queryAll<number>(store.querySql(`SELECT DISTINCT mangaId FROM track`),
      (rs: relationalStore.ResultSet): number => rs.getLong(rs.getColumnIndex('mangaId')),
      'tracked manga ids failed');
    const ids = new Set<number>();
    for (const id of rows) {
      ids.add(id);
    }
    return ids;
  }

  // 全部已评分记录的分数（统计页平均评分用）
  static async allScores(): Promise<number[]> {
    const store = await AppDb.get();
    return queryAll<number>(store.querySql(`SELECT score FROM track WHERE score > 0`),
      (rs: relationalStore.ResultSet): number => rs.getDouble(rs.getColumnIndex('score')),
      'all scores failed');
  }

  // 某漫画的全部追踪记录
  static async listByManga(mangaId: number): Promise<TrackRecord[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('track');
    pred.equalTo('mangaId', mangaId);
    return queryAll<TrackRecord>(store.query(pred, TrackRepo.COLUMNS),
      (rs: relationalStore.ResultSet): TrackRecord => TrackRepo.rowToTrack(rs), 'list tracks failed');
  }

  // 某漫画的第一条追踪记录（单追踪器 UI 用；无记录返回 undefined）
  static async get(mangaId: number): Promise<TrackRecord | undefined> {
    const list = await TrackRepo.listByManga(mangaId);
    return list.length > 0 ? list[0] : undefined;
  }

  // 绑定 AniList 条目（syncId=2，对齐 Mihon Anilist sync id）
  static async bind(mangaId: number, remoteId: number, title: string): Promise<void> {
    const record = new TrackRecord();
    record.mangaId = mangaId;
    record.syncId = 2;
    record.remoteId = remoteId;
    record.title = title;
    await TrackRepo.upsert(record);
  }

  // 解除某漫画的全部追踪绑定
  static async unbind(mangaId: number): Promise<void> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('track');
    pred.equalTo('mangaId', mangaId);
    try {
      await store.delete(pred);
    } catch (e) {
      throw new Error(`unbind tracks failed: ${e}`);
    }
  }

  // 更新某漫画全部追踪记录的已读进度（同步后回写本地）
  static async setLastChapterRead(mangaId: number, progress: number): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = {
      'lastChapterRead': progress,
    };
    const pred = new relationalStore.RdbPredicates('track');
    pred.equalTo('mangaId', mangaId);
    try {
      await store.update(values, pred);
    } catch (e) {
      throw new Error(`update track progress failed: ${e}`);
    }
  }

  static async getBySyncId(mangaId: number, syncId: number): Promise<TrackRecord | undefined> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('track');
    pred.equalTo('mangaId', mangaId).and().equalTo('syncId', syncId);
    return queryFirst<TrackRecord>(store.query(pred, TrackRepo.COLUMNS),
      (rs: relationalStore.ResultSet): TrackRecord => TrackRepo.rowToTrack(rs), 'get track failed');
  }

  // 插入或更新（按 mangaId + syncId 唯一）
  static async upsert(track: TrackRecord): Promise<void> {
    const store = await AppDb.get();
    const existing = await TrackRepo.getBySyncId(track.mangaId, track.syncId);
    const values: relationalStore.ValuesBucket = {
      'mangaId': track.mangaId,
      'syncId': track.syncId,
      'remoteId': track.remoteId,
      'libraryId': track.libraryId,
      'title': track.title,
      'status': track.status,
      'lastChapterRead': track.lastChapterRead,
      'score': track.score,
      'totalChapters': track.totalChapters,
      'remoteUrl': track.remoteUrl,
      'startDate': track.startDate,
      'finishDate': track.finishDate,
      'isPrivate': track.isPrivate ? 1 : 0,
    };
    try {
      if (existing !== undefined) {
        track.id = existing.id;
        values['id'] = existing.id;
        const pred = new relationalStore.RdbPredicates('track');
        pred.equalTo('id', existing.id);
        await store.update(values, pred);
      } else {
        await store.insert('track', values);
      }
    } catch (e) {
      throw new Error(`upsert track failed: ${e}`);
    }
  }

  static async delete(mangaId: number, syncId: number): Promise<void> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('track');
    pred.equalTo('mangaId', mangaId).and().equalTo('syncId', syncId);
    try {
      await store.delete(pred);
    } catch (e) {
      throw new Error(`delete track failed: ${e}`);
    }
  }

  private static rowToTrack(rs: relationalStore.ResultSet): TrackRecord {
    try {
      const t = new TrackRecord();
      t.id = rs.getLong(rs.getColumnIndex('id'));
      t.mangaId = rs.getLong(rs.getColumnIndex('mangaId'));
      t.syncId = rs.getLong(rs.getColumnIndex('syncId'));
      t.remoteId = rs.getLong(rs.getColumnIndex('remoteId'));
      t.libraryId = rs.getLong(rs.getColumnIndex('libraryId'));
      t.title = rs.getString(rs.getColumnIndex('title'));
      t.status = rs.getLong(rs.getColumnIndex('status'));
      t.lastChapterRead = rs.getDouble(rs.getColumnIndex('lastChapterRead'));
      t.score = rs.getDouble(rs.getColumnIndex('score'));
      t.totalChapters = rs.getLong(rs.getColumnIndex('totalChapters'));
      t.remoteUrl = rs.getString(rs.getColumnIndex('remoteUrl'));
      t.startDate = rs.getLong(rs.getColumnIndex('startDate'));
      t.finishDate = rs.getLong(rs.getColumnIndex('finishDate'));
      t.isPrivate = rs.getLong(rs.getColumnIndex('isPrivate')) !== 0;
      return t;
    } catch (e) {
      throw new Error(`map track row failed: ${e}`);
    }
  }
}

// 插件元数据索引仓库（plugin 表）：安装/卸载同步维护记录，
// 启动时据此注册占位源（不扫盘、不拉引擎），支撑千级插件
export class PluginRepo {
  private static readonly COLUMNS: string[] = [
    'key', 'name', 'lang', 'version', 'versionCode', 'baseUrl', 'nsfw', 'bt', 'supportsLatest',
    'minAppVersion', 'dslVersion', 'icon', 'contentTypes',
    'methodsJson', 'sourcesJson', 'installedAt',
  ];

  // sourceKey → pluginKey 进程内缓存（启动/安装后懒加载，未命中重建一次）
  private static sourceMap: Map<string, string> | undefined = undefined;

  static async upsert(record: PluginRecord): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = {
      'key': record.key,
      'name': record.name,
      'lang': record.lang,
      'version': record.version,
      'versionCode': record.versionCode,
      'baseUrl': record.baseUrl,
      'nsfw': record.nsfw ? 1 : 0,
      'bt': record.bt ? 1 : 0,
      'supportsLatest': record.supportsLatest ? 1 : 0,
      'minAppVersion': record.minAppVersion,
      'dslVersion': record.dslVersion,
      'icon': record.icon,
      'contentTypes': record.contentTypes,
      'methodsJson': record.methodsJson,
      'sourcesJson': record.sourcesJson,
      'installedAt': record.installedAt,
    };
    try {
      // key 为主键：INSERT OR REPLACE 原子完成重装/升级覆盖
      await store.executeSql(
        `INSERT INTO plugin (key, name, lang, version, versionCode, baseUrl, nsfw, bt, supportsLatest,
          minAppVersion, dslVersion, icon, contentTypes, methodsJson, sourcesJson, installedAt)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET
          name = excluded.name, lang = excluded.lang, version = excluded.version,
          versionCode = excluded.versionCode, baseUrl = excluded.baseUrl, nsfw = excluded.nsfw,
          bt = excluded.bt,
          supportsLatest = excluded.supportsLatest, minAppVersion = excluded.minAppVersion,
          dslVersion = excluded.dslVersion, icon = excluded.icon,
          contentTypes = excluded.contentTypes,
          methodsJson = excluded.methodsJson, sourcesJson = excluded.sourcesJson,
          installedAt = excluded.installedAt`,
        [record.key, record.name, record.lang, record.version, record.versionCode, record.baseUrl,
          record.nsfw ? 1 : 0, record.bt ? 1 : 0, record.supportsLatest ? 1 : 0, record.minAppVersion,
          record.dslVersion,
          record.icon, record.contentTypes,
          record.methodsJson, record.sourcesJson, record.installedAt]);
    } catch (e) {
      throw new Error(`upsert plugin failed: ${e}`);
    }
  }

  static async remove(key: string): Promise<void> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('plugin');
    pred.equalTo('key', key);
    try {
      await store.delete(pred);
    } catch (e) {
      throw new Error(`remove plugin failed: ${e}`);
    }
  }

  static async list(): Promise<PluginRecord[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('plugin');
    pred.orderByAsc('installedAt').orderByAsc('key');
    return queryAll<PluginRecord>(store.query(pred, PluginRepo.COLUMNS),
      (rs: relationalStore.ResultSet): PluginRecord => PluginRepo.rowToPlugin(rs), 'list plugins failed');
  }

  static async count(): Promise<number> {
    const store = await AppDb.get();
    return await queryFirst<number>(store.querySql(`SELECT COUNT(*) AS n FROM plugin`),
      (rs: relationalStore.ResultSet): number => rs.getLong(rs.getColumnIndex('n')),
      'count plugins failed') ?? 0;
  }

  // sourceKey → 所属插件 key（无痕判定、插件详情跳转等用）。
  // 未命中缓存时重建一次；查不到返回原 sourceKey（内置源/单源插件 key 即 sourceKey 前缀）
  static async pluginKeyOfSource(sourceKey: string): Promise<string> {
    if (PluginRepo.sourceMap === undefined) {
      await PluginRepo.rebuildSourceMap();
    }
    let mapped: string | undefined = PluginRepo.sourceMap?.get(sourceKey);
    if (mapped === undefined) {
      // 可能刚安装/升级插件，重建一次再查
      await PluginRepo.rebuildSourceMap();
      mapped = PluginRepo.sourceMap?.get(sourceKey);
    }
    return mapped !== undefined ? mapped : sourceKey;
  }

  // 失效缓存（插件安装/卸载/升级后由 PluginService 调用）
  static invalidateSourceMap(): void {
    PluginRepo.sourceMap = undefined;
  }

  private static async rebuildSourceMap(): Promise<void> {
    const map = new Map<string, string>();
    try {
      const plugins = await PluginRepo.list();
      for (const p of plugins) {
        // 插件 key 本身也是合法 sourceKey（单源插件）
        map.set(p.key, p.key);
        if (p.sourcesJson === '') {
          continue;
        }
        try {
          const specs = JSON.parse(p.sourcesJson) as PluginSourceSpecRaw[];
          if (Array.isArray(specs)) {
            for (const spec of specs) {
              if (spec !== null && spec !== undefined && typeof spec.key === 'string' && spec.key !== '') {
                map.set(spec.key as string, p.key);
              }
            }
          }
        } catch (e2) {
        }
      }
    } catch (e) {
    }
    PluginRepo.sourceMap = map;
  }

  private static rowToPlugin(rs: relationalStore.ResultSet): PluginRecord {
    try {
      const p = new PluginRecord();
      p.key = rs.getString(rs.getColumnIndex('key'));
      p.name = rs.getString(rs.getColumnIndex('name'));
      p.lang = rs.getString(rs.getColumnIndex('lang'));
      p.version = rs.getString(rs.getColumnIndex('version'));
      p.versionCode = rs.getLong(rs.getColumnIndex('versionCode'));
      p.baseUrl = rs.getString(rs.getColumnIndex('baseUrl'));
      p.nsfw = rs.getLong(rs.getColumnIndex('nsfw')) === 1;
      p.bt = rs.getLong(rs.getColumnIndex('bt')) === 1;
      p.supportsLatest = rs.getLong(rs.getColumnIndex('supportsLatest')) === 1;
      p.minAppVersion = rs.getLong(rs.getColumnIndex('minAppVersion'));
      p.dslVersion = rs.getLong(rs.getColumnIndex('dslVersion'));
      p.icon = rs.getString(rs.getColumnIndex('icon'));
      p.contentTypes = rs.getString(rs.getColumnIndex('contentTypes'));
      p.methodsJson = rs.getString(rs.getColumnIndex('methodsJson'));
      p.sourcesJson = rs.getString(rs.getColumnIndex('sourcesJson'));
      p.installedAt = rs.getLong(rs.getColumnIndex('installedAt'));
      return p;
    } catch (e) {
      throw new Error(`map plugin row failed: ${e}`);
    }
  }
}
