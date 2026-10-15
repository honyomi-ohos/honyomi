import { Http } from '../net/Http';
import { ChapterRecord, MangaRecord } from '../model/Models';

// 单条弹幕（时间毫秒 + dandanplay 模式 + 24bit 颜色 + 文本）
export class DanmakuItem {
  timeMs: number = 0;
  mode: number = 1; // 1 滚动 4 底部 5 顶部
  color: number = 0xFFFFFF;
  text: string = '';
}

interface DdpEpisodeRaw {
  episodeId: number;
  episodeTitle: string;
}

interface DdpMatchRaw {
  animeId: number;
  animeTitle: string;
  episodes: DdpEpisodeRaw[];
}

interface DdpSearchRaw {
  count: number;
  matches: DdpMatchRaw[];
}

interface DdpCommentRaw {
  cid: number;
  p: string;
  m: string;
}

interface DdpCommentRootRaw {
  count: number;
  comments: DdpCommentRaw[];
}

// 弹幕数据服务：按作品标题 + 集数匹配 dandanplay 剧集并拉取弹幕池
export class DanmakuService {
  private static cache: Map<number, DanmakuItem[]> = new Map();
  // 同章并发调用去重：在途请求复用同一 Promise
  private static inflight: Map<number, Promise<DanmakuItem[]>> = new Map();
  private static readonly MAX_ITEMS: number = 5000;
  // 缓存 LRU 上限：最多保留 10 章弹幕，超出淘汰最旧
  private static readonly MAX_CHAPTERS: number = 10;

  static async loadForChapter(manga: MangaRecord, chapter: ChapterRecord): Promise<DanmakuItem[]> {
    const cached: DanmakuItem[] | undefined = DanmakuService.cache.get(chapter.id);
    if (cached !== undefined) {
      // 命中缓存时刷新 LRU 顺序
      DanmakuService.cache.delete(chapter.id);
      DanmakuService.cache.set(chapter.id, cached);
      return cached;
    }
    const pending: Promise<DanmakuItem[]> | undefined = DanmakuService.inflight.get(chapter.id);
    if (pending !== undefined) {
      return pending;
    }
    const task: Promise<DanmakuItem[]> = DanmakuService.fetchDanmaku(manga, chapter).then(
      (items: DanmakuItem[]): DanmakuItem[] => {
        DanmakuService.putCache(chapter.id, items);
        DanmakuService.inflight.delete(chapter.id);
        return items;
      },
      (e: Object): DanmakuItem[] => {
        DanmakuService.inflight.delete(chapter.id);
        throw new Error(e instanceof Error ? e.message : String(e));
      });
    DanmakuService.inflight.set(chapter.id, task);
    return task;
  }

  private static async fetchDanmaku(manga: MangaRecord, chapter: ChapterRecord): Promise<DanmakuItem[]> {
    const title: string = DanmakuService.cleanTitle(manga.title);
    if (title === '') {
      return [];
    }
    // 1. 按标题搜索剧集
    const searchUrl: string =
      `https://api.dandanplay.net/api/v2/search/episodes?anime=${encodeURIComponent(title)}&withRelated=true`;
    const searchRaw: string = await Http.get(searchUrl, Http.defaultHeaders());
    let parsed: DdpSearchRaw;
    try {
      parsed = JSON.parse(searchRaw) as DdpSearchRaw;
    } catch (e) {
      return [];
    }
    const episodeId: number = DanmakuService.pickEpisodeId(parsed, chapter);
    if (episodeId <= 0) {
      return [];
    }
    // 2. 拉取该集弹幕池（chConvert=1 繁转简）
    const commentUrl: string =
      `https://api.dandanplay.net/api/v2/comment/${episodeId}?withRelated=true&chConvert=1`;
    const commentRaw: string = await Http.get(commentUrl, Http.defaultHeaders());
    let parsedComments: DdpCommentRootRaw;
    try {
      parsedComments = JSON.parse(commentRaw) as DdpCommentRootRaw;
    } catch (e) {
      return [];
    }
    const items: DanmakuItem[] = [];
    const comments: DdpCommentRaw[] = parsedComments.comments === undefined ? [] : parsedComments.comments;
    for (let i = 0; i < comments.length; i++) {
      const item: DanmakuItem | undefined = DanmakuService.parseComment(comments[i]);
      if (item !== undefined) {
        items.push(item);
      }
      if (items.length >= DanmakuService.MAX_ITEMS) {
        break;
      }
    }
    items.sort((a: DanmakuItem, b: DanmakuItem): number => a.timeMs - b.timeMs);
    return items;
  }

  // 写入缓存并维持 LRU 上限（Map 迭代序即最近使用序，淘汰首个即最旧）
  private static putCache(chapterId: number, items: DanmakuItem[]): void {
    DanmakuService.cache.delete(chapterId);
    DanmakuService.cache.set(chapterId, items);
    while (DanmakuService.cache.size > DanmakuService.MAX_CHAPTERS) {
      let oldest: number = -1;
      DanmakuService.cache.forEach((_items: DanmakuItem[], key: number) => {
        if (oldest === -1) {
          oldest = key;
        }
      });
      if (oldest === -1) {
        break;
      }
      DanmakuService.cache.delete(oldest);
    }
  }

  // 解析 dandanplay 弹幕条目，p = "时间秒,模式,颜色,来源"
  private static parseComment(raw: DdpCommentRaw): DanmakuItem | undefined {
    if (typeof raw.p !== 'string' || typeof raw.m !== 'string' || raw.m === '') {
      return undefined;
    }
    const segs: string[] = raw.p.split(',');
    if (segs.length < 3) {
      return undefined;
    }
    const timeSec: number = Number(segs[0]);
    const mode: number = Number(segs[1]);
    const color: number = Number(segs[2]);
    if (!isFinite(timeSec) || timeSec < 0) {
      return undefined;
    }
    const item: DanmakuItem = new DanmakuItem();
    item.timeMs = Math.floor(timeSec * 1000);
    item.mode = mode === 4 || mode === 5 ? mode : 1;
    item.color = isFinite(color) && color >= 0 ? Math.floor(color) & 0xFFFFFF : 0xFFFFFF;
    item.text = raw.m;
    return item;
  }

  // 标题清洗：去掉括号补充说明与季节后缀，提高搜索命中率
  private static cleanTitle(title: string): string {
    let t: string = title.trim();
    t = t.replace(/[(（【\[][^)）】\]]*[)）】\]]/g, '');
    t = t.replace(/\s*(第[一二三四五]季|Season\s*\d+|S\d+)$/i, '');
    return t.trim();
  }

  // 集数匹配：优先按集号精确匹配集标题，退化为序号/首集
  private static pickEpisodeId(parsed: DdpSearchRaw, chapter: ChapterRecord): number {
    const matches: DdpMatchRaw[] | undefined = parsed.matches;
    if (matches === undefined || matches === null || matches.length === 0) {
      return -1;
    }
    const wantNum: number = chapter.chapterNumber > 0 ?
      Math.floor(chapter.chapterNumber) : DanmakuService.extractNumber(chapter.name);
    for (let mi = 0; mi < matches.length; mi++) {
      const episodes: DdpEpisodeRaw[] | undefined = matches[mi].episodes;
      if (episodes === undefined || episodes === null) {
        continue;
      }
      for (let ei = 0; ei < episodes.length; ei++) {
        const epNum: number = DanmakuService.extractNumber(episodes[ei].episodeTitle);
        if (wantNum > 0 && epNum === wantNum) {
          return episodes[ei].episodeId;
        }
      }
    }
    const firstEpisodes: DdpEpisodeRaw[] | undefined = matches[0].episodes;
    if (wantNum > 0) {
      if (firstEpisodes !== undefined && firstEpisodes !== null && wantNum <= firstEpisodes.length) {
        return firstEpisodes[wantNum - 1].episodeId;
      }
    } else if (firstEpisodes !== undefined && firstEpisodes !== null && firstEpisodes.length > 0) {
      return firstEpisodes[0].episodeId;
    }
    return -1;
  }

  // 从文本提取集号：“第01话”“第 1 集”“EP03”“01” 均可
  private static extractNumber(text: string): number {
    const ep: RegExpMatchArray | null = text.match(/第\s*(\d+)\s*[话話集]/);
    if (ep !== null && ep.length > 1) {
      const n: number = parseInt(ep[1] ?? '-1', 10);
      if (n > 0) {
        return n;
      }
    }
    const digits: RegExpMatchArray | null = text.match(/(\d+)/);
    if (digits !== null && digits.length > 1) {
      const n: number = parseInt(digits[1] ?? '-1', 10);
      if (n > 0) {
        return n;
      }
    }
    return -1;
  }
}
