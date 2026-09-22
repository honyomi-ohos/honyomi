import { relationalStore } from '@kit.ArkData';
import { AppDb } from './AppDb';
import { SManga, SChapter, MangaRecord, ChapterRecord, CategoryRecord, UpdateItem, HistoryItem, TrackRecord } from '../model/Models';

// 漫画仓库
export class MangaRepo {
  static async upsertFromSource(sourceKey: string, m: SManga): Promise<number> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('sourceKey', sourceKey).and().equalTo('url', m.key);
    const rs = await store.query(pred,
      ['id', 'inLibrary', 'title', 'thumbnailUrl', 'author', 'description', 'genre', 'status']);
    let id = -1;
    let inLibrary = 0;
    let oldTitle = '';
    let oldThumb = '';
    let oldAuthor = '';
    let oldDesc = '';
    let oldGenre = '';
    let oldStatus = '';
    if (rs.goToNextRow()) {
      id = rs.getLong(rs.getColumnIndex('id'));
      inLibrary = rs.getLong(rs.getColumnIndex('inLibrary'));
      oldTitle = rs.getString(rs.getColumnIndex('title'));
      oldThumb = rs.getString(rs.getColumnIndex('thumbnailUrl'));
      oldAuthor = rs.getString(rs.getColumnIndex('author'));
      oldDesc = rs.getString(rs.getColumnIndex('description'));
      oldGenre = rs.getString(rs.getColumnIndex('genre'));
      oldStatus = rs.getString(rs.getColumnIndex('status'));
    }
    rs.close();
    if (id >= 0) {
      // 源返回空字段时保留旧值，避免解析回退把已有信息清空
      const values: relationalStore.ValuesBucket = {
        'title': m.title !== '' ? m.title : oldTitle,
        'thumbnailUrl': m.coverUrl !== '' ? m.coverUrl : oldThumb,
        'author': m.author !== '' ? m.author : oldAuthor,
        'description': m.description !== '' ? m.description : oldDesc,
        'genre': m.genre !== '' ? m.genre : oldGenre,
        'status': m.status !== '' ? m.status : oldStatus,
      };
      await store.update(values, pred);
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
      'inLibrary': 0,
      'categoryId': 1,
      'addedAt': Date.now(),
    };
    const rowId = await store.insert('manga', values);
    return rowId;
  }

  static async get(id: number): Promise<MangaRecord | undefined> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    const rs = await store.query(pred, MangaRepo.COLUMNS);
    const result: MangaRecord | undefined = rs.goToNextRow() ? MangaRepo.rowToManga(rs) : undefined;
    rs.close();
    return result;
  }

  static async getLibrary(): Promise<MangaRecord[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('inLibrary', 1).orderByAsc('categoryId').orderByAsc('id');
    const rs = await store.query(pred, MangaRepo.COLUMNS);
    const list: MangaRecord[] = [];
    while (rs.goToNextRow()) {
      list.push(MangaRepo.rowToManga(rs));
    }
    rs.close();
    return list;
  }

  static async setInLibrary(id: number, inLibrary: boolean): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = {
      'inLibrary': inLibrary ? 1 : 0,
      'categoryId': 1,
      'addedAt': Date.now(),
    };
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    await store.update(values, pred);
  }

  static async setCategory(id: number, categoryId: number): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'categoryId': categoryId };
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    await store.update(values, pred);
  }

  // 按源获取书架漫画（迁移选择列表）
  static async getLibraryBySource(sourceKey: string): Promise<MangaRecord[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('inLibrary', 1).and().equalTo('sourceKey', sourceKey).orderByAsc('title');
    const rs = await store.query(pred, MangaRepo.COLUMNS);
    const list: MangaRecord[] = [];
    while (rs.goToNextRow()) {
      list.push(MangaRepo.rowToManga(rs));
    }
    rs.close();
    return list;
  }

  // 书架内各源漫画数（迁移源列表）
  static async countBySource(): Promise<Record<string, number>> {
    const store = await AppDb.get();
    const rs = await store.querySql(
      `SELECT sourceKey, COUNT(*) AS cnt FROM manga WHERE inLibrary = 1 GROUP BY sourceKey`);
    const counts: Record<string, number> = {};
    while (rs.goToNextRow()) {
      counts[rs.getString(rs.getColumnIndex('sourceKey'))] = rs.getLong(rs.getColumnIndex('cnt'));
    }
    rs.close();
    return counts;
  }

  // 迁移：切换源与地址并更新元数据，清空旧章节记录（进度不保留）
  static async migrate(id: number, sourceKey: string, url: string, m: SManga): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = {
      'sourceKey': sourceKey,
      'url': url,
      'title': m.title !== '' ? m.title : ' ',
      'thumbnailUrl': m.coverUrl,
      'author': m.author,
      'description': m.description,
      'genre': m.genre,
      'status': m.status,
    };
    const pred = new relationalStore.RdbPredicates('manga');
    pred.equalTo('id', id);
    await store.update(values, pred);
    await store.executeSql(`DELETE FROM chapter WHERE mangaId = ?`, [id]);
  }

  private static readonly COLUMNS: string[] = [
    'id', 'sourceKey', 'url', 'title', 'thumbnailUrl', 'author',
    'description', 'genre', 'status', 'inLibrary', 'categoryId', 'addedAt',
  ];

  private static rowToManga(rs: relationalStore.ResultSet): MangaRecord {
    const m = new MangaRecord();
    m.id = rs.getLong(rs.getColumnIndex('id'));
    m.sourceKey = rs.getString(rs.getColumnIndex('sourceKey'));
    m.url = rs.getString(rs.getColumnIndex('url'));
    m.title = rs.getString(rs.getColumnIndex('title'));
    m.thumbnailUrl = rs.getString(rs.getColumnIndex('thumbnailUrl'));
    m.author = rs.getString(rs.getColumnIndex('author'));
    m.description = rs.getString(rs.getColumnIndex('description'));
    m.genre = rs.getString(rs.getColumnIndex('genre'));
    m.status = rs.getString(rs.getColumnIndex('status'));
    m.inLibrary = rs.getLong(rs.getColumnIndex('inLibrary')) === 1;
    m.categoryId = rs.getLong(rs.getColumnIndex('categoryId'));
    m.addedAt = rs.getLong(rs.getColumnIndex('addedAt'));
    return m;
  }
}

// 章节仓库
export class ChapterRepo {
  static async getById(id: number): Promise<ChapterRecord | undefined> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('id', id);
    const rs = await store.query(pred, ChapterRepo.COLUMNS);
    const result: ChapterRecord | undefined = rs.goToNextRow() ? ChapterRepo.rowToChapter(rs) : undefined;
    rs.close();
    return result;
  }

  static async listByManga(mangaId: number): Promise<ChapterRecord[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('mangaId', mangaId).orderByAsc('sortOrder').orderByAsc('id');
    const rs = await store.query(pred, ChapterRepo.COLUMNS);
    const list: ChapterRecord[] = [];
    while (rs.goToNextRow()) {
      list.push(ChapterRepo.rowToChapter(rs));
    }
    rs.close();
    return list;
  }

  // 用源返回的章节列表刷新本地记录，保留已读状态；返回新增章节数
  static async syncFromSource(mangaId: number, chapters: SChapter[]): Promise<number> {
    const store = await AppDb.get();
    const existing = await ChapterRepo.listByManga(mangaId);
    const existingKeys = new Set<string>();
    for (const c of existing) {
      existingKeys.add(c.url);
    }
    let newCount = 0;
    for (const c of chapters) {
      if (existingKeys.has(c.key)) {
        const values: relationalStore.ValuesBucket = {
          'name': c.name,
          'chapterNumber': c.chapterNumber,
          'dateUpload': c.dateUpload,
          'pages': c.pages,
          'sortOrder': c.sortOrder,
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
        };
        await store.insert('chapter', values);
        newCount += 1;
      }
    }
    return newCount;
  }

  static async setRead(id: number, read: boolean): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'read': read ? 1 : 0 };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('id', id);
    await store.update(values, pred);
  }

  static async setLastPageRead(id: number, page: number): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'lastPageRead': page };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('id', id);
    await store.update(values, pred);
  }

  static async markAllRead(mangaId: number, read: boolean): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'read': read ? 1 : 0 };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('mangaId', mangaId);
    await store.update(values, pred);
  }

  static async unreadCount(mangaId: number): Promise<number> {
    const store = await AppDb.get();
    const rs = await store.querySql(
      `SELECT COUNT(*) AS cnt FROM chapter WHERE mangaId = ? AND read = 0`, [mangaId]);
    let count = 0;
    if (rs.goToNextRow()) {
      count = rs.getLong(rs.getColumnIndex('cnt'));
    }
    rs.close();
    return count;
  }

  // 备份恢复用：按 mangaId+url 更新阅读状态
  static async applyStateByUrl(mangaId: number, url: string, read: boolean, lastPageRead: number): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = {
      'read': read ? 1 : 0,
      'lastPageRead': lastPageRead,
    };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('mangaId', mangaId).and().equalTo('url', url);
    await store.update(values, pred);
  }

  // 备份恢复用：章节不存在则插入，存在则仅恢复阅读状态
  static async upsertBackup(mangaId: number, url: string, name: string, chapterNumber: number,
    read: boolean, lastPageRead: number): Promise<void> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('mangaId', mangaId).and().equalTo('url', url);
    const rs = await store.query(pred, ['id']);
    const exists = rs.goToNextRow();
    rs.close();
    if (exists) {
      const values: relationalStore.ValuesBucket = {
        'read': read ? 1 : 0,
        'lastPageRead': lastPageRead,
      };
      await store.update(values, pred);
      return;
    }
    const values: relationalStore.ValuesBucket = {
      'mangaId': mangaId,
      'url': url,
      'name': name,
      'chapterNumber': chapterNumber,
      'dateUpload': 0,
      'pages': 0,
      'sortOrder': 0,
      'read': read ? 1 : 0,
      'bookmark': 0,
      'lastPageRead': lastPageRead,
    };
    await store.insert('chapter', values);
  }

  static async setPages(id: number, pages: number): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'pages': pages };
    const pred = new relationalStore.RdbPredicates('chapter');
    pred.equalTo('id', id);
    await store.update(values, pred);
  }

  static async countRead(mangaId: number): Promise<number> {
    const store = await AppDb.get();
    const rs = await store.querySql(
      `SELECT COUNT(*) AS cnt FROM chapter WHERE mangaId = ? AND read = 1`, [mangaId]);
    let count = 0;
    if (rs.goToNextRow()) {
      count = rs.getLong(rs.getColumnIndex('cnt'));
    }
    rs.close();
    return count;
  }

  private static readonly COLUMNS: string[] = [
    'id', 'mangaId', 'url', 'name', 'chapterNumber', 'dateUpload',
    'pages', 'sortOrder', 'read', 'bookmark', 'lastPageRead',
  ];

  private static rowToChapter(rs: relationalStore.ResultSet): ChapterRecord {
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
    return c;
  }
}

// 分类仓库
export class CategoryRepo {
  static async list(): Promise<CategoryRecord[]> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('category');
    pred.orderByAsc('sortOrder').orderByAsc('id');
    const rs = await store.query(pred, ['id', 'name', 'sortOrder']);
    const list: CategoryRecord[] = [];
    while (rs.goToNextRow()) {
      const c = new CategoryRecord();
      c.id = rs.getLong(rs.getColumnIndex('id'));
      c.name = rs.getString(rs.getColumnIndex('name'));
      c.sortOrder = rs.getLong(rs.getColumnIndex('sortOrder'));
      list.push(c);
    }
    rs.close();
    return list;
  }

  static async add(name: string): Promise<void> {
    const store = await AppDb.get();
    const rs = await store.querySql(`SELECT COUNT(*) AS cnt FROM category`);
    let count = 0;
    if (rs.goToNextRow()) {
      count = rs.getLong(rs.getColumnIndex('cnt'));
    }
    rs.close();
    const values: relationalStore.ValuesBucket = { 'name': name, 'sortOrder': count };
    await store.insert('category', values);
  }

  static async rename(id: number, name: string): Promise<void> {
    if (id === 1 || name === '') {
      return;
    }
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'name': name };
    const pred = new relationalStore.RdbPredicates('category');
    pred.equalTo('id', id);
    await store.update(values, pred);
  }

  static async remove(id: number): Promise<void> {
    if (id === 1) {
      return;
    }
    const store = await AppDb.get();
    // 该分类下的漫画移回默认分类
    const values: relationalStore.ValuesBucket = { 'categoryId': 1 };
    const predManga = new relationalStore.RdbPredicates('manga');
    predManga.equalTo('categoryId', id);
    await store.update(values, predManga);
    const predCategory = new relationalStore.RdbPredicates('category');
    predCategory.equalTo('id', id);
    await store.delete(predCategory);
  }
}

// 阅读历史仓库
export class HistoryRepo {
  static async upsert(mangaId: number, chapterId: number, lastPageRead: number): Promise<void> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('history');
    pred.equalTo('mangaId', mangaId).and().equalTo('chapterId', chapterId);
    const rs = await store.query(pred, ['id']);
    const exists = rs.goToNextRow();
    rs.close();
    if (exists) {
      const values: relationalStore.ValuesBucket = {
        'seenAt': Date.now(),
        'lastPageRead': lastPageRead,
      };
      await store.update(values, pred);
    } else {
      const values: relationalStore.ValuesBucket = {
        'mangaId': mangaId,
        'chapterId': chapterId,
        'seenAt': Date.now(),
        'lastPageRead': lastPageRead,
      };
      await store.insert('history', values);
    }
  }

  static async recent(limit: number): Promise<HistoryItem[]> {
    const store = await AppDb.get();
    const rs = await store.querySql(
      `SELECT h.mangaId AS mangaId, h.chapterId AS chapterId, h.seenAt AS seenAt,
              h.lastPageRead AS lastPageRead, m.title AS mangaTitle,
              m.thumbnailUrl AS coverUrl, c.name AS chapterName
       FROM history h
       JOIN manga m ON m.id = h.mangaId
       JOIN chapter c ON c.id = h.chapterId
       ORDER BY h.seenAt DESC LIMIT ?`, [limit]);
    const list: HistoryItem[] = [];
    while (rs.goToNextRow()) {
      list.push(HistoryItem.of(
        rs.getLong(rs.getColumnIndex('mangaId')),
        rs.getLong(rs.getColumnIndex('chapterId')),
        rs.getString(rs.getColumnIndex('mangaTitle')),
        rs.getString(rs.getColumnIndex('coverUrl')),
        rs.getString(rs.getColumnIndex('chapterName')),
        rs.getLong(rs.getColumnIndex('seenAt')),
        rs.getLong(rs.getColumnIndex('lastPageRead'))));
    }
    rs.close();
    return list;
  }

  static async clear(): Promise<void> {
    const store = await AppDb.get();
    await store.delete(new relationalStore.RdbPredicates('history'));
  }
}

// 更新页查询
export class UpdatesRepo {
  static async unreadChapters(limit: number): Promise<UpdateItem[]> {
    const store = await AppDb.get();
    const rs = await store.querySql(
      `SELECT c.id AS chapterId, c.mangaId AS mangaId, c.name AS chapterName,
              c.dateUpload AS dateUpload, m.title AS mangaTitle, m.thumbnailUrl AS coverUrl
       FROM chapter c
       JOIN manga m ON m.id = c.mangaId
       WHERE m.inLibrary = 1 AND c.read = 0
       ORDER BY c.dateUpload DESC LIMIT ?`, [limit]);
    const list: UpdateItem[] = [];
    while (rs.goToNextRow()) {
      list.push(UpdateItem.of(
        rs.getLong(rs.getColumnIndex('mangaId')),
        rs.getLong(rs.getColumnIndex('chapterId')),
        rs.getString(rs.getColumnIndex('mangaTitle')),
        rs.getString(rs.getColumnIndex('coverUrl')),
        rs.getString(rs.getColumnIndex('chapterName')),
        rs.getLong(rs.getColumnIndex('dateUpload'))));
    }
    rs.close();
    return list;
  }
}

// 追踪仓库（AniList）
export class TrackRepo {
  private static readonly COLUMNS: string[] = [
    'id', 'mangaId', 'syncId', 'remoteId', 'title', 'status', 'lastChapterRead', 'score',
  ];

  static async get(mangaId: number): Promise<TrackRecord | undefined> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('track');
    pred.equalTo('mangaId', mangaId).and().equalTo('syncId', 1);
    const rs = await store.query(pred, TrackRepo.COLUMNS);
    const result: TrackRecord | undefined = rs.goToNextRow() ? TrackRepo.rowToTrack(rs) : undefined;
    rs.close();
    return result;
  }

  static async bind(mangaId: number, remoteId: number, title: string): Promise<void> {
    const store = await AppDb.get();
    const existing = await TrackRepo.get(mangaId);
    if (existing !== undefined) {
      const values: relationalStore.ValuesBucket = {
        'remoteId': remoteId,
        'title': title,
      };
      const pred = new relationalStore.RdbPredicates('track');
      pred.equalTo('id', existing.id);
      await store.update(values, pred);
      return;
    }
    const values: relationalStore.ValuesBucket = {
      'mangaId': mangaId,
      'syncId': 1,
      'remoteId': remoteId,
      'title': title,
      'status': '',
      'lastChapterRead': 0,
      'score': 0,
    };
    await store.insert('track', values);
  }

  static async unbind(mangaId: number): Promise<void> {
    const store = await AppDb.get();
    const pred = new relationalStore.RdbPredicates('track');
    pred.equalTo('mangaId', mangaId).and().equalTo('syncId', 1);
    await store.delete(pred);
  }

  static async setLastChapterRead(mangaId: number, lastChapterRead: number): Promise<void> {
    const store = await AppDb.get();
    const values: relationalStore.ValuesBucket = { 'lastChapterRead': lastChapterRead };
    const pred = new relationalStore.RdbPredicates('track');
    pred.equalTo('mangaId', mangaId).and().equalTo('syncId', 1);
    await store.update(values, pred);
  }

  private static rowToTrack(rs: relationalStore.ResultSet): TrackRecord {
    const t = new TrackRecord();
    t.id = rs.getLong(rs.getColumnIndex('id'));
    t.mangaId = rs.getLong(rs.getColumnIndex('mangaId'));
    t.syncId = rs.getLong(rs.getColumnIndex('syncId'));
    t.remoteId = rs.getLong(rs.getColumnIndex('remoteId'));
    t.title = rs.getString(rs.getColumnIndex('title'));
    t.status = rs.getString(rs.getColumnIndex('status'));
    t.lastChapterRead = rs.getLong(rs.getColumnIndex('lastChapterRead'));
    t.score = rs.getDouble(rs.getColumnIndex('score'));
    return t;
  }
}
