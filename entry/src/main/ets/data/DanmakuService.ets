import { Http } from '../net/Http';
import { ChapterRecord, MangaRecord } from '../model/Models';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { SecureStore } from '../common/SecureStore';
import { Settings } from '../common/Settings';

// 单条弹幕（时间毫秒 + dandanplay 模式 + 24bit 颜色 + 文本）
export class DanmakuItem {
  timeMs: number = 0;
  mode: number = 1; // 1 滚动 4 底部 5 顶部
  color: number = 0xFFFFFF;
  text: string = '';
}

// dandanplay 登录账号（token 持久化于 SecureStore）
export class DdpAccount {
  accessToken: string = '';
  // 过期时间（unix 秒；0 表示未知）
  expires: number = 0;
  userId: number = 0;
  userName: string = '';
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

// POST /api/v2/login 请求体
interface DdpLoginReq {
  userName: string;
  password: string;
}

// 登录响应（token 直接位于根对象）
interface DdpLoginResRaw {
  accessToken?: string;
  expires?: number;
  userId?: number;
  userName?: string;
}

// POST /api/v2/comment/{episodeId} 请求体（time 单位秒）
interface DdpSendReq {
  time: number;
  mode: number;
  color: number;
  text: string;
}

// 弹幕数据服务：按作品标题 + 集数匹配 dandanplay 剧集并拉取弹幕池
export class DanmakuService {
  private static cache: Map<number, DanmakuItem[]> = new Map();
  // 同章并发调用去重：在途请求复用同一 Promise
  private static inflight: Map<number, Promise<DanmakuItem[]>> = new Map();
  // 章节 → dandanplay 剧集 ID（发送弹幕时需要）
  private static episodeIds: Map<number, number> = new Map();
  private static readonly MAX_ITEMS: number = 5000;
  // 缓存 LRU 上限：最多保留 10 章弹幕，超出淘汰最旧
  private static readonly MAX_CHAPTERS: number = 10;
  // dandanplay 登录凭据的 SecureStore 别名
  private static readonly TOKEN_ALIAS: string = 'ddp_token';
  // dandanplay 开放弹幕网络应用凭证（dev.dandanplay.com 申请；应用审核通过后生效）
  private static readonly APP_ID: string = 'vgdq26b2dw';
  private static readonly APP_SECRET: string = 'B8RQi45EvYIczfbAuvZb5uC4StuqWLzj';

  // 章节对应的 dandanplay 剧集 ID（拉取过弹幕后有效；-1 未知）
  static episodeIdOf(chapterId: number): number {
    const id: number | undefined = DanmakuService.episodeIds.get(chapterId);
    return id !== undefined ? id : -1;
  }

  // 清空弹幕缓存（屏蔽规则变更后调用，强制下次重新拉取过滤）
  static clearCache(): void {
    DanmakuService.cache.clear();
  }

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
    const searchRaw: string = await Http.get(searchUrl, await DanmakuService.authHeaders(searchUrl));
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
    DanmakuService.episodeIds.set(chapter.id, episodeId);
    // 2. 拉取该集弹幕池（chConvert=1 繁转简）
    const commentUrl: string =
      `https://api.dandanplay.net/api/v2/comment/${episodeId}?withRelated=true&chConvert=1`;
    const commentRaw: string = await Http.get(commentUrl, await DanmakuService.authHeaders(commentUrl));
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
    // 3. 应用用户屏蔽规则（正则命中即隐藏；无效正则跳过）
    let filtered: DanmakuItem[] = items;
    const filters: string[] = Settings.getDanmakuFilters();
    if (filters.length > 0) {
      const regexes: RegExp[] = [];
      for (let fi = 0; fi < filters.length; fi++) {
        try {
          regexes.push(new RegExp(filters[fi]));
        } catch (_e) {
          // 无效正则：忽略该条规则
        }
      }
      if (regexes.length > 0) {
        filtered = [];
        for (let i = 0; i < items.length; i++) {
          if (!DanmakuService.matchesAny(items[i].text, regexes)) {
            filtered.push(items[i]);
          }
        }
      }
    }
    filtered.sort((a: DanmakuItem, b: DanmakuItem): number => a.timeMs - b.timeMs);
    return filtered;
  }

  // 文本是否命中任一屏蔽正则
  private static matchesAny(text: string, regexes: RegExp[]): boolean {
    for (let i = 0; i < regexes.length; i++) {
      if (regexes[i].test(text)) {
        return true;
      }
    }
    return false;
  }

  // ---- 弹幕发送（dandanplay 账号） ----

  // 读取已保存的登录账号；不存在或已过期返回 undefined
  static savedAccount(): DdpAccount | undefined {
    const raw: string = SecureStore.getSync(DanmakuService.TOKEN_ALIAS);
    if (raw === '') {
      return undefined;
    }
    try {
      const parsed: DdpLoginResRaw = JSON.parse(raw) as DdpLoginResRaw;
      const acct: DdpAccount | undefined = DanmakuService.parseAccount(parsed);
      if (acct === undefined) {
        return undefined;
      }
      if (acct.expires > 0 && acct.expires * 1000 < Date.now()) {
        return undefined;
      }
      return acct;
    } catch (_e) {
      return undefined;
    }
  }

  // dandanplay 账号登录（POST /api/v2/login）；成功后凭据持久化到 SecureStore
  static async login(userName: string, password: string): Promise<DdpAccount> {
    const url: string = 'https://api.dandanplay.net/api/v2/login';
    const req: DdpLoginReq = { userName: userName, password: password };
    const raw: string = await Http.post(url, JSON.stringify(req), await DanmakuService.authHeaders(url));
    let parsed: DdpLoginResRaw;
    try {
      parsed = JSON.parse(raw) as DdpLoginResRaw;
    } catch (e) {
      throw new Error('ddp_login_invalid');
    }
    const acct: DdpAccount | undefined = DanmakuService.parseAccount(parsed);
    if (acct === undefined || acct.accessToken === '') {
      throw new Error('ddp_login_failed');
    }
    SecureStore.putSync(DanmakuService.TOKEN_ALIAS, JSON.stringify(acct));
    return acct;
  }

  // 退出登录：清除持久化凭据
  static logout(): void {
    SecureStore.removeSync(DanmakuService.TOKEN_ALIAS);
  }

  // ---- 备份导出/导入（配合 BackupService v3 敏感加密段）----

  // 导出 dandanplay 登录凭据原始 JSON（未登录返回空串；进 secure 加密段）
  static exportAccount(): string {
    return SecureStore.getSync(DanmakuService.TOKEN_ALIAS);
  }

  // 导入登录凭据（secure 段解密后调用）：仅接受能解析出 accessToken 的合法载荷
  static importAccount(raw: string): void {
    if (raw === '') {
      return;
    }
    try {
      const parsed: DdpLoginResRaw = JSON.parse(raw) as DdpLoginResRaw;
      const acct: DdpAccount | undefined = DanmakuService.parseAccount(parsed);
      if (acct !== undefined && acct.accessToken !== '') {
        SecureStore.putSync(DanmakuService.TOKEN_ALIAS, raw);
      }
    } catch (_e) {
    }
  }

  // 发送弹幕到当前章节对应剧集（POST /api/v2/comment/{episodeId}，需已登录）
  static async send(chapterId: number, text: string, timeMs: number, mode: number, color: number): Promise<void> {
    const episodeId: number = DanmakuService.episodeIdOf(chapterId);
    if (episodeId <= 0) {
      throw new Error('ddp_no_episode');
    }
    const acct: DdpAccount | undefined = DanmakuService.savedAccount();
    if (acct === undefined) {
      throw new Error('ddp_login_required');
    }
    const url: string = `https://api.dandanplay.net/api/v2/comment/${episodeId}`;
    const req: DdpSendReq = {
      time: Math.round(timeMs) / 1000,
      mode: mode,
      color: color & 0xFFFFFF,
      text: text
    };
    const headers: Record<string, string> = await DanmakuService.authHeaders(url);
    headers['Authorization'] = `Bearer ${acct.accessToken}`;
    await Http.post(url, JSON.stringify(req), headers);
  }

  // 从登录响应提取账号；token 缺失返回 undefined
  private static parseAccount(parsed: DdpLoginResRaw): DdpAccount | undefined {
    if (typeof parsed.accessToken !== 'string' || parsed.accessToken === '') {
      return undefined;
    }
    const acct: DdpAccount = new DdpAccount();
    acct.accessToken = parsed.accessToken;
    acct.expires = typeof parsed.expires === 'number' ? parsed.expires : 0;
    acct.userId = typeof parsed.userId === 'number' ? parsed.userId : 0;
    acct.userName = typeof parsed.userName === 'string' ? parsed.userName : '';
    return acct;
  }

  // dandanplay 请求鉴权（官方规范，doc.dandanplay.com/open）：
  // 签名模式 X-AppId/X-Timestamp/X-Signature，签名 = base64(sha256(AppId + Timestamp + Path + AppSecret))，
  // Path 为不含 query 的接口路径；SHA256 能力不可用时退化为凭证模式（X-AppId/X-AppSecret）
  private static async authHeaders(url: string): Promise<Record<string, string>> {
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['X-AppId'] = DanmakuService.APP_ID;
    const ts: number = Math.floor(Date.now() / 1000);
    // 带版本后缀的 syscap 查询运行时恒为 false：if 分支仅为抑制编译告警，真实签名路径在 else
    if (canIUse('SystemCapability.Security.CryptoFramework.MessageDigest [since 12]')) {
      headers['X-AppSecret'] = DanmakuService.APP_SECRET;
      return headers;
    } else {
      try {
        const data: string =
          `${DanmakuService.APP_ID}${ts}${DanmakuService.apiPath(url)}${DanmakuService.APP_SECRET}`;
        const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
        await md.update({ data: new util.TextEncoder().encodeInto(data) });
        const digest: cryptoFramework.DataBlob = await md.digest();
        headers['X-Timestamp'] = `${ts}`;
        headers['X-Signature'] = new util.Base64Helper().encodeToStringSync(digest.data);
        return headers;
      } catch (_e) {
      }
    }
    headers['X-AppSecret'] = DanmakuService.APP_SECRET;
    return headers;
  }

  // 提取签名用接口路径：去掉协议与域名、去掉 query，统一小写
  private static apiPath(url: string): string {
    let rest: string = url;
    const schemeIdx: number = url.indexOf('://');
    if (schemeIdx >= 0) {
      const slashIdx: number = url.indexOf('/', schemeIdx + 3);
      rest = slashIdx >= 0 ? url.substring(slashIdx) : '/';
    }
    const qIdx: number = rest.indexOf('?');
    if (qIdx >= 0) {
      rest = rest.substring(0, qIdx);
    }
    return rest.toLowerCase();
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
