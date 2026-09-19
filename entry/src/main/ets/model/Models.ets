// 源层数据模型（对齐 Mihon source-api 的 SManga / SChapter / Page）

export interface SManga {
  key: string;
  title: string;
  coverUrl: string;
  author: string;
  description: string;
  genre: string;
  status: string;
}

export interface SChapter {
  key: string;
  name: string;
  chapterNumber: number;
  dateUpload: number;
  pages: number;
  sortOrder: number;
}

export interface SPage {
  index: number;
  url: string;
}

export interface MangasPage {
  mangas: SManga[];
  hasNextPage: boolean;
}

// 数据库记录模型

export class MangaRecord {
  id: number = 0;
  sourceKey: string = '';
  url: string = '';
  title: string = '';
  thumbnailUrl: string = '';
  author: string = '';
  description: string = '';
  genre: string = '';
  status: string = '';
  inLibrary: boolean = false;
  categoryId: number = 1;
  addedAt: number = 0;
}

export class ChapterRecord {
  id: number = 0;
  mangaId: number = 0;
  url: string = '';
  name: string = '';
  chapterNumber: number = 0;
  dateUpload: number = 0;
  pages: number = 0;
  sortOrder: number = 0;
  read: boolean = false;
  bookmark: boolean = false;
  lastPageRead: number = 0;
}

export class CategoryRecord {
  id: number = 1;
  name: string = '';
  sortOrder: number = 0;
}

// 列表展示模型（联表查询结果）

export class UpdateItem {
  mangaId: number = 0;
  chapterId: number = 0;
  mangaTitle: string = '';
  coverUrl: string = '';
  chapterName: string = '';
  dateUpload: number = 0;

  static of(mangaId: number, chapterId: number, mangaTitle: string, coverUrl: string,
    chapterName: string, dateUpload: number): UpdateItem {
    const item = new UpdateItem();
    item.mangaId = mangaId;
    item.chapterId = chapterId;
    item.mangaTitle = mangaTitle;
    item.coverUrl = coverUrl;
    item.chapterName = chapterName;
    item.dateUpload = dateUpload;
    return item;
  }
}

export class HistoryItem {
  mangaId: number = 0;
  chapterId: number = 0;
  mangaTitle: string = '';
  coverUrl: string = '';
  chapterName: string = '';
  seenAt: number = 0;
  lastPageRead: number = 0;

  static of(mangaId: number, chapterId: number, mangaTitle: string, coverUrl: string,
    chapterName: string, seenAt: number, lastPageRead: number): HistoryItem {
    const item = new HistoryItem();
    item.mangaId = mangaId;
    item.chapterId = chapterId;
    item.mangaTitle = mangaTitle;
    item.coverUrl = coverUrl;
    item.chapterName = chapterName;
    item.seenAt = seenAt;
    item.lastPageRead = lastPageRead;
    return item;
  }
}
