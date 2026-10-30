// 源层数据模型（对齐 Mihon source-api 的 SManga / SChapter / Page）

export interface SManga {
  key: string;
  title: string;
  coverUrl: string;
  author: string;
  description: string;
  genre: string;
  status: string;
  // 作品级内容类型声明（manga | novel | video）：多类型插件区分单部作品归属；
  // 未声明（undefined）时入库回退源（插件）类型
  contentType?: string;
}

export interface SChapter {
  key: string;
  name: string;
  chapterNumber: number;
  dateUpload: number;
  pages: number;
  sortOrder: number;
  // 汉化组（对齐 Mihon SChapter.scanlator）：源显式提供或由章节名前缀 [组名] 解析
  scanlator?: string;
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

  // m3u8(HLS) 播放列表识别：下载优先直链，仅剩 m3u8 时走 HLS 下载管线
  static isPlaylist(url: string): boolean {
    return url.toLowerCase().indexOf('.m3u8') >= 0;
  }
}

export interface WorksPage {
  works: SManga[];
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
  // 作品级自定义更新间隔（小时，对齐 Mihon manga.updateInterval）：
  // 0 = 跟随默认（每次全局刷新都检查）；-1 = 从不参与全局更新；>0 = 距上次更新超过 N 小时才刷新
  updateInterval: number = 0;
  // 用户备注（详情页编辑与展示，对齐 Mihon manga.notes）
  notes: string = '';
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
  // 汉化组（对齐 Mihon SChapter.scanlator；空串 = 未知）
  scanlator: string = '';
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
  // 所属源 key：关闭“显示 NSFW 源”时按源过滤更新条目
  sourceKey: string = '';

  static of(mangaId: number, chapterId: number, mangaTitle: string, coverUrl: string,
    chapterName: string, dateUpload: number, read: boolean, bookmark: boolean,
    sourceKey: string = ''): UpdateItem {
    const item = new UpdateItem();
    item.mangaId = mangaId;
    item.chapterId = chapterId;
    item.mangaTitle = mangaTitle;
    item.coverUrl = coverUrl;
    item.chapterName = chapterName;
    item.dateUpload = dateUpload;
    item.read = read;
    item.bookmark = bookmark;
    item.sourceKey = sourceKey;
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
  // 所属源 key：关闭“显示 NSFW 源”时按源过滤历史条目
  sourceKey: string = '';
  // 是否已在书架：历史页非在库条目显示心形入库按钮
  inLibrary: boolean = false;

  static of(mangaId: number, chapterId: number, mangaTitle: string, coverUrl: string,
    chapterName: string, seenAt: number, lastPageRead: number, sourceKey: string = ''): HistoryItem {
    const item = new HistoryItem();
    item.mangaId = mangaId;
    item.chapterId = chapterId;
    item.mangaTitle = mangaTitle;
    item.coverUrl = coverUrl;
    item.chapterName = chapterName;
    item.seenAt = seenAt;
    item.lastPageRead = lastPageRead;
    item.sourceKey = sourceKey;
    return item;
  }
}

// 疑似重复的库内作品（加入书架前查重，对齐 Mihon MangaWithChapterCount 子集）
export class DuplicateManga {
  id: number = 0;
  title: string = '';
  coverUrl: string = '';
  author: string = '';
  status: string = '';
  sourceKey: string = '';
  chapterCount: number = 0;
}

// 已安装插件元数据索引（plugin 表记录）：启动时据此注册占位源，引擎按需惰性拉起
export class PluginRecord {
  // 插件包 key（plugins/ 目录名，多源包的引擎 key）
  key: string = '';
  name: string = '';
  lang: string = 'multi';
  version: string = '';
  versionCode: number = 0;
  baseUrl: string = '';
  nsfw: boolean = false;
  // BT 源标记（manifest bt，缺省 false）
  bt: boolean = false;
  supportsLatest: boolean = false;
  minAppVersion: number = 1;
  dslVersion: number = 1;
  // 包内图标文件名（如 icon.png）
  icon: string = '';
  // 内容类型全量列表（逗号分隔，主类型在前）
  contentTypes: string = '';
  // 引擎探测到的导出方法列表（JSON string[]），占位源据此判断 hasMethod/supportsLatest
  methodsJson: string = '[]';
  // 最终注册源规格（JSON SourceSpec[]，含子源注册 key），manga.sourceKey 引用其 key
  sourcesJson: string = '[]';
  installedAt: number = 0;
}

// P2 模型

// 追踪记录（对齐 Mihon Track）：status/score 存储 tracker 原生值，syncId 见 TrackerManager
export class TrackRecord {
  id: number = 0;
  mangaId: number = 0;
  syncId: number = 0;
  remoteId: number = 0;
  libraryId: number = 0;
  title: string = '';
  // tracker 原生状态码（各追踪器常量）
  status: number = 0;
  lastChapterRead: number = 0;
  // tracker 原生评分（0-10 / 0-100 等）
  score: number = 0;
  totalChapters: number = 0;
  remoteUrl: string = '';
  // 阅读起止日期（epoch 毫秒，0 = 未设置）
  startDate: number = 0;
  finishDate: number = 0;
  isPrivate: boolean = false;
}

// 追踪搜索结果（对齐 Mihon TrackSearch）
export class TrackSearchResult {
  syncId: number = 0;
  remoteId: number = 0;
  libraryId: number = 0;
  title: string = '';
  totalChapters: number = 0;
  coverUrl: string = '';
  summary: string = '';
  // 站点平均评分
  score: number = 0;
  trackingUrl: string = '';
  publishingStatus: string = '';
  publishingType: string = '';
  startDate: string = '';
  authors: string[] = [];
  artists: string[] = [];
  // 已在用户库中时的条目状态
  status: number = 0;
  lastChapterRead: number = 0;
  isPrivate: boolean = false;
  startReadDate: number = 0;
  finishReadDate: number = 0;
}

// AniList 搜索结果
export class ALMediaItem {
  id: number = 0;
  title: string = '';
}

export class DownloadTask {
  mangaId: number = 0;
  mangaTitle: string = '';
  chapterId: number = 0;
  chapterName: string = '';
  // 章节号/上传时间：下载管理页排序（对齐 Mihon chapterNumber/dateUpload 排序键）
  chapterNumber: number = 0;
  dateUpload: number = 0;
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
