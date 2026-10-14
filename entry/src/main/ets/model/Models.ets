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
  pageUrl?: string;
}

// 视频章节的一条可播放流（直链或 m3u8）
export interface SVideo {
  url: string;
  quality: string;
  headers: Record<string, string>;
}

// 作品类型：漫画 / 小说 / 视频。未声明时一律视为漫画。
export class ContentType {
  static readonly MANGA: string = 'manga';
  static readonly NOVEL: string = 'novel';
  static readonly VIDEO: string = 'video';

  // 各类型对应的默认分类名（书架初始三分类，首次入库时按类型落分类）；
  // 值为内容类型 code，显示层经资源映射为多语言
  static readonly CATEGORY_MANGA: string = 'manga';
  static readonly CATEGORY_NOVEL: string = 'novel';
  static readonly CATEGORY_VIDEO: string = 'video';

  // 内容类型 → 默认分类名
  static categoryName(raw: string | undefined): string {
    if (raw === ContentType.NOVEL) {
      return ContentType.CATEGORY_NOVEL;
    }
    if (raw === ContentType.VIDEO) {
      return ContentType.CATEGORY_VIDEO;
    }
    return ContentType.CATEGORY_MANGA;
  }

  // 是否内置默认分类（漫画/小说/视频三种内容类型 code）；用户自建/改名分类返回 false
  static isBuiltinCategory(name: string): boolean {
    return name === ContentType.CATEGORY_MANGA ||
      name === ContentType.CATEGORY_NOVEL ||
      name === ContentType.CATEGORY_VIDEO;
  }

  static normalize(raw: string | undefined): string {
    if (raw === ContentType.NOVEL || raw === ContentType.VIDEO) {
      return raw;
    }
    return ContentType.MANGA;
  }

  static isLocal(sourceKey: string): boolean {
    return sourceKey === 'local' || sourceKey === 'local_novel' || sourceKey === 'local_video';
  }

  // m3u8 只在线播放，不进下载队列
  static isPlaylist(url: string): boolean {
    return url.toLowerCase().indexOf('.m3u8') >= 0;
  }
}

export interface MangasPage {
  mangas: SManga[];
  hasNextPage: boolean;
}

// 数据库记录模型

// @Observed：配合列表条目组件的 @ObjectLink，避免 @Prop 对类对象逐条深拷贝
@Observed
export class MangaRecord {
  id: number = 0;
  sourceKey: string = '';
  url: string = '';
  title: string = '';
  thumbnailUrl: string = '';
  // 非空表示 thumbnailUrl 正在展示用户自定义封面，此字段保存源原封面地址
  origThumbnail: string = '';
  // 书架持久化封面：入库时经图片管线下载（AVIF→JPEG 转码）复制到 files/covers 的裸绝对路径
  localCover: string = '';
  // localCover 持久化时的源封面地址（变更检测：与当前源封面不一致时回填流程重新持久化）
  localCoverUrl: string = '';
  author: string = '';
  description: string = '';
  genre: string = '';
  status: string = '';
  contentType: string = 'manga';
  inLibrary: boolean = false;
  categoryId: number = 1;
  addedAt: number = 0;
  lastUpdateAt: number = 0;
  fetchedAt: number = 0;
  // 章节列表排序/筛选标志位（位常量见 common/ChapterFlags，对齐 Mihon chapterFlags）
  chapterFlags: number = 0;
}

// 书架统计（章节/历史聚合查询结果）
export class MangaStats {
  mangaId: number = 0;
  total: number = 0;
  unread: number = 0;
  readCount: number = 0;
  bookmarkCount: number = 0;
  latest: number = 0; // 最新章节上传时间 MAX(chapter.dateUpload)
  lastRead: number = 0; // 最近阅读时间 MAX(history.seenAt)
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
  read: boolean = false;
  bookmark: boolean = false;

  static of(mangaId: number, chapterId: number, mangaTitle: string, coverUrl: string,
    chapterName: string, dateUpload: number, read: boolean, bookmark: boolean): UpdateItem {
    const item = new UpdateItem();
    item.mangaId = mangaId;
    item.chapterId = chapterId;
    item.mangaTitle = mangaTitle;
    item.coverUrl = coverUrl;
    item.chapterName = chapterName;
    item.dateUpload = dateUpload;
    item.read = read;
    item.bookmark = bookmark;
    return item;
  }
}

// 即将推出页条目（书架连载中漫画 + 预计下次更新时间）
export class UpcomingManga {
  mangaId: number = 0;
  title: string = '';
  coverUrl: string = '';
  categoryId: number = 1;
  expectedAt: number = 0;
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

// P2 模型

export class TrackRecord {
  id: number = 0;
  mangaId: number = 0;
  syncId: number = 1; // 1 = AniList
  remoteId: number = 0;
  title: string = '';
  status: string = '';
  lastChapterRead: number = 0;
  score: number = 0;
}

export class DownloadTask {
  mangaId: number = 0;
  mangaTitle: string = '';
  chapterId: number = 0;
  chapterName: string = '';
  sourceKey: string = '';
  mangaUrl: string = '';
  chapterUrl: string = '';
  state: number = 0; // 0=队列 1=下载中 2=完成 3=失败
  progress: number = 0; // 已下载页数
  total: number = 0;
  error: string = '';

  key(): string {
    return `${this.chapterId}`;
  }
}

export class DownloadedChapter {
  mangaId: number = 0;
  mangaTitle: string = '';
  chapterId: number = 0;
  chapterName: string = '';

  static of(mangaId: number, mangaTitle: string, chapterId: number, chapterName: string): DownloadedChapter {
    const item = new DownloadedChapter();
    item.mangaId = mangaId;
    item.mangaTitle = mangaTitle;
    item.chapterId = chapterId;
    item.chapterName = chapterName;
    return item;
  }
}

export class DownloadedManga {
  mangaId: number = 0;
  mangaTitle: string = '';
  chapters: DownloadedChapter[] = [];
}

// AniList 搜索结果
export class ALMediaItem {
  id: number = 0;
  title: string = '';
}
