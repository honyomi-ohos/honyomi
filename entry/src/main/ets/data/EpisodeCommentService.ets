// 剧集评论（Bangumi 吐槽箱，next.bgm.tv 新版接口）：
// 章节 → Bangumi 动画条目（matchSubject）→ 分集（getEpisodes）→ 单集评论全量拉取。
// 评论正文为 BBCode：[b][i][u][s][color=][size=][url][img][mask] 与 Bangumi 表情
// （(bgmN) 各组、(musume_N)/(blake_N) 大表情、颜文字）；接口无分页参数，
// 一次返回全量数组且各评论内嵌 replies 楼中楼
import { Http, RawResponse } from '../net/Http';
import { Settings } from '../common/Settings';
import { BangumiApi, BgmEpisode } from './BangumiApi';
import { ChapterRecord, MangaRecord } from '../model/Models';
import { TrackerManager } from './track/TrackerManager';

// ---- 原始 JSON 模型（next.bgm.tv /p1）----

// 用户头像（三档尺寸，列表用 medium）
interface BgmNextAvatarRaw {
  small?: string;
  medium?: string;
  large?: string;
}

interface BgmNextUserRaw {
  nickname?: string;
  username?: string;
  avatar?: BgmNextAvatarRaw;
}

// 表情回应明细用户（样本实测：[{id, username, nickname}]）
interface BgmNextReactionUserRaw {
  id?: number;
  username?: string;
  nickname?: string;
}

// 表情回应（value = 表情编号，users = 参与用户列表）
interface BgmNextReactionRaw {
  value?: number;
  users?: BgmNextReactionUserRaw[];
}

// GET /p1/me 响应（仅需 id）
interface BgmNextMeRaw {
  id?: number;
}

// POST 评论响应（{id}）
interface BgmNextPostCommentRespRaw {
  id?: number;
}

interface BgmNextCommentRaw {
  id?: number;
  content?: string;
  // unix 秒
  createdAt?: number;
  state?: number;
  replies?: BgmNextCommentRaw[];
  user?: BgmNextUserRaw;
  reactions?: BgmNextReactionRaw[];
}

// ---- 公开模型 ----

// 评论内容解析片段（扁平序列，按序渲染进同一 Text）：
// 0 文本 1 表情 2 剧透遮罩占位 3 内联图片（[img]）
// masked = 片段位于 [mask] 内（揭示前不渲染），其余字段为 BBCode 样式；
// 表情片段 emojiLarge = musume/blake 240px 大表情（渲染放大），其余为小表情
export class CommentSegment {
  kind: number = 0;
  text: string = '';
  emojiUrl: string = '';
  emojiLarge: boolean = false;
  imageUrl: string = '';
  masked: boolean = false;
  bold: boolean = false;
  italic: boolean = false;
  underline: boolean = false;
  strike: boolean = false;
  color: string = '';
  fontSize: number = 0;
  linkUrl: string = '';
}

// 评论内容块：块级 BBCode（quote/code/align/indent）将正文切分为多块，逐块独立渲染；
// align 0 左 1 中 2 右；indent 缩进层级；quote 引用块（左竖线 + 次要色文字）；
// code 代码块（等宽字体，内容不解析其余 BBCode）
export class CommentBlock {
  align: number = 0;
  indent: number = 0;
  quote: boolean = false;
  code: boolean = false;
  segments: CommentSegment[] = [];
}

// 表情回应明细（value = 12 个合法反应值之一，count = 参与人数，mine = 当前用户已参与）
export class EpisodeReaction {
  value: number = 0;
  count: number = 0;
  mine: boolean = false;
}

export class EpisodeCommentReply {
  id: number = 0;
  content: string = '';
  createdAtMs: number = 0;
  nickname: string = '';
  avatar: string = '';
  blocks: CommentBlock[] = [];
  hasMask: boolean = false;
  reactions: EpisodeReaction[] = [];
  // 当前用户已选反应值（0 = 未回应）
  myReactionValue: number = 0;
}

export class EpisodeComment {
  id: number = 0;
  content: string = '';
  createdAtMs: number = 0;
  nickname: string = '';
  avatar: string = '';
  // 表情回应总人数（各 reactions.users 人数之和）
  reactionCount: number = 0;
  blocks: CommentBlock[] = [];
  // 含 [mask] 剧透段（点击遮罩可揭示）
  hasMask: boolean = false;
  // 表情回应明细（value + 人数 + 是否已回应）
  reactions: EpisodeReaction[] = [];
  // 当前用户已选反应值（0 = 未回应）
  myReactionValue: number = 0;
  replies: EpisodeCommentReply[] = [];
}

// 评论内存缓存条目（TTL 内直接复用）
class CommentsCacheEntry {
  items: EpisodeComment[] = [];
  fetchedAt: number = 0;
}

// BBCode 解析中间态：当前生效的样式与标签上下文
class BbState {
  bold: boolean = false;
  italic: boolean = false;
  underline: boolean = false;
  strike: boolean = false;
  color: string = '';
  fontSize: number = 0;
  linkUrl: string = '';
  inUrl: boolean = false;
  inImg: boolean = false;
  imgBuf: string = '';
  masked: boolean = false;
  // 块级标签状态
  align: number = 0;
  quoteDepth: number = 0;
  indentDepth: number = 0;
  // [code] 原文缓冲（内容不解析其余 BBCode）
  inCode: boolean = false;
  codeBuf: string = '';
  // [user] 用户名缓冲
  inUser: boolean = false;
  userBuf: string = '';
}

// BBCode 解析上下文：已产出的块 + 当前进行中的块
class BbCtx {
  blocks: CommentBlock[] = [];
  cur: CommentBlock | undefined = undefined;
  st: BbState = new BbState();
}

export class EpisodeCommentService {
  private static readonly UA: string = 'Honyomi/1.0 (HarmonyOS)';
  // 评论缓存 10 分钟（评论实时性要求不高，翻回同集直接复用）
  private static readonly CACHE_MS: number = 10 * 60 * 1000;
  // 表情合法编号（规则取自 next.bgm.tv 前端表情面板定义，逐 URL 实测验证）：
  // bgm 1..23 站娘组（bgm/ 目录）；24..125 旧版组（bgm.tv 已迁入 tv/ 目录，编号 -23）；
  // 200..238 tv_vs 组；500..529 tv_500 组；musume/blake 1..118 大表情组；超范围保留原文
  private static readonly BGM_EMOJI_NEW_MAX: number = 23;
  private static readonly BGM_EMOJI_LEGACY_MAX: number = 125;
  private static readonly BGM_EMOJI_VS_MIN: number = 200;
  private static readonly BGM_EMOJI_VS_MAX: number = 238;
  private static readonly BGM_EMOJI_500_MIN: number = 500;
  private static readonly BGM_EMOJI_500_MAX: number = 529;
  private static readonly STICKER_ID_MAX: number = 118;
  // 颜文字：文本代码 → img/smiles/{n}.gif 序号（next.bgm.tv 前端固定顺序）
  private static readonly KAOMOJI_INDEX: Record<string, number> = {
    '(=A=)': 1, '(=w=)': 2, '(-w=)': 3, '(S_S)': 4, '(=v=)': 5, '(@_@)': 6,
    '(=W=)': 7, '(TAT)': 8, '(T_T)': 9, "(='=)": 10, '(=3=)': 11, "(= =')": 12,
    '(=///=)': 13, '(=.,=)': 14, '(:P)': 15, '(LOL)': 16
  };
  // 章节 → Bangumi ep id（0 = 无匹配；同章节再次进入直接命中）
  private static epIdCache: Map<number, number> = new Map<number, number>();
  // ep id → 评论列表
  private static commentsCache: Map<number, CommentsCacheEntry> = new Map<number, CommentsCacheEntry>();
  // 当前登录用户 id（-1 未查询，0 未登录/查询失败；用于判定"我是否已回应"）
  private static myUserIdCache: number = -1;

  // ---- 表情回应（点赞）----
  // 12 个合法反应值（next.bgm.tv 前端反应选择器全集，实测自源码映射表）
  static readonly REACTION_VALUES: number[] = [0, 54, 62, 79, 80, 85, 88, 90, 104, 122, 140, 141];
  // 反应值 → lain.bgm.tv tv/ 表情文件名（前端映射表 j）
  private static readonly REACTION_FILE: Record<string, string> = {
    '0': '44', '54': '15', '62': '23', '79': '40', '80': '41',
    '85': '46', '88': '49', '90': '51', '104': '65', '122': '83',
    '140': '101', '141': '102'
  };

  // 反应值对应表情图 URL（经图片镜像出口；非法值返回 ''）
  static reactionEmojiUrl(value: number): string {
    const file: string | undefined = EpisodeCommentService.REACTION_FILE[`${value}`];
    if (file === undefined) {
      return '';
    }
    return Settings.rewriteBangumiImageUrl(`https://lain.bgm.tv/img/smiles/tv/${file}.gif`);
  }

  // ---- 认证（Bangumi OAuth access token 复用为 /p1 Bearer）----

  // 有效 access token（'' = 未登录）：OAuth token 优先，回退登录时存的凭据
  static accessToken(): string {
    const t = TrackerManager.bangumi.loadToken();
    if (t !== undefined && t.accessToken !== '') {
      return t.accessToken;
    }
    return TrackerManager.bangumi.getPassword();
  }

  static isLoggedIn(): boolean {
    return EpisodeCommentService.accessToken() !== '';
  }

  // 登录/登出后重置用户缓存（下次拉取重新查询 /p1/me）
  static resetMyUser(): void {
    EpisodeCommentService.myUserIdCache = -1;
  }

  // 当前登录用户 id（缓存；未登录/失败返回 0，不缓存以便下次重试）
  static async myUserId(): Promise<number> {
    if (EpisodeCommentService.myUserIdCache >= 0) {
      return EpisodeCommentService.myUserIdCache;
    }
    const token: string = EpisodeCommentService.accessToken();
    if (token === '') {
      EpisodeCommentService.myUserIdCache = 0;
      return 0;
    }
    const resp: RawResponse = await Http.requestRaw('GET',
      `${Settings.bangumiNextBase()}/p1/me`, '', EpisodeCommentService.authHeaders(token));
    if (resp.code < 200 || resp.code >= 300) {
      return 0;
    }
    let id: number = 0;
    try {
      const parsed = JSON.parse(resp.body) as BgmNextMeRaw;
      if (typeof parsed.id === 'number' && parsed.id > 0) {
        id = parsed.id;
      }
    } catch (_e) {
    }
    EpisodeCommentService.myUserIdCache = id;
    return id;
  }

  // ---- 写操作（/p1，Bearer 认证）----

  // 发评论 / 楼中楼回复：replyTo = 0 顶层，主评论 id = 楼中楼；
  // 成功返回新评论 id 并清掉该集缓存；401 未登录，429 限流
  static async postComment(epId: number, content: string, replyTo: number,
    turnstileToken: string): Promise<number> {
    const token: string = EpisodeCommentService.accessToken();
    if (token === '') {
      throw new Error('comments_unauthorized');
    }
    const body: string = `{"content":${JSON.stringify(content)},"replyTo":${replyTo}` +
      `,"turnstileToken":${JSON.stringify(turnstileToken)}}`;
    const resp: RawResponse = await Http.requestRaw('POST',
      `${Settings.bangumiNextBase()}/p1/episodes/${epId}/comments`,
      body, EpisodeCommentService.authHeaders(token));
    if (resp.code === 401) {
      throw new Error('comments_unauthorized');
    }
    if (resp.code === 429) {
      throw new Error('comments_rate_limited');
    }
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`comments_http_${resp.code}`);
    }
    let id: number = 0;
    try {
      const parsed = JSON.parse(resp.body) as BgmNextPostCommentRespRaw;
      if (typeof parsed.id === 'number' && parsed.id > 0) {
        id = parsed.id;
      }
    } catch (_e) {
    }
    EpisodeCommentService.commentsCache.delete(epId);
    return id;
  }

  // 表情回应（value 必须是 REACTION_VALUES 之一）
  static async react(commentId: number, value: number): Promise<void> {
    await EpisodeCommentService.likeRequest('PUT', commentId, `{"value":${value}}`);
  }

  // 取消表情回应
  static async unreact(commentId: number): Promise<void> {
    await EpisodeCommentService.likeRequest('DELETE', commentId, '');
  }

  private static async likeRequest(method: string, commentId: number, body: string): Promise<void> {
    const token: string = EpisodeCommentService.accessToken();
    if (token === '') {
      throw new Error('comments_unauthorized');
    }
    const resp: RawResponse = await Http.requestRaw(method,
      `${Settings.bangumiNextBase()}/p1/episodes/-/comments/${commentId}/like`,
      body, EpisodeCommentService.authHeaders(token));
    if (resp.code === 401) {
      throw new Error('comments_unauthorized');
    }
    if (resp.code === 429) {
      throw new Error('comments_rate_limited');
    }
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`comments_http_${resp.code}`);
    }
  }

  // Bearer 请求头（JSON 写请求共用）
  private static authHeaders(token: string): Record<string, string> {
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = EpisodeCommentService.UA;
    headers['Authorization'] = `Bearer ${token}`;
    headers['Accept'] = 'application/json';
    headers['Content-Type'] = 'application/json';
    return headers;
  }

  // 加载章节对应评论：无匹配剧集抛 comments_no_episode，网络失败原样抛错；
  // force = 跳过缓存强制拉取（发评/回应后刷新用）
  static async loadForChapter(manga: MangaRecord, chapter: ChapterRecord,
    force: boolean = false): Promise<EpisodeComment[]> {
    const epId: number = await EpisodeCommentService.resolveEpisodeId(manga, chapter);
    if (epId <= 0) {
      throw new Error('comments_no_episode');
    }
    return EpisodeCommentService.fetchComments(epId, force);
  }

  // 章节对应的 Bangumi 分集 id（内存缓存；0 = 无匹配）：
  // 集号精确匹配（ep/sort）→ 序号退化（第 N 集取列表第 N 项）→ 无集号取首集
  static async resolveEpisodeId(manga: MangaRecord, chapter: ChapterRecord): Promise<number> {
    const cached: number | undefined = EpisodeCommentService.epIdCache.get(chapter.id);
    if (cached !== undefined) {
      return cached;
    }
    const subjectId: number = await BangumiApi.matchSubject(manga.title, manga.author, 2);
    if (subjectId <= 0) {
      EpisodeCommentService.epIdCache.set(chapter.id, 0);
      return 0;
    }
    const episodes: BgmEpisode[] = await BangumiApi.getEpisodes(subjectId);
    // 正片分集优先（type=0），无正片时退化为全集列表
    const main: BgmEpisode[] = episodes.filter((e: BgmEpisode): boolean => e.type === 0);
    const pool: BgmEpisode[] = main.length > 0 ? main : episodes;
    let matched: number = 0;
    if (pool.length > 0) {
      const wantNum: number = chapter.chapterNumber > 0 ?
        Math.floor(chapter.chapterNumber) : EpisodeCommentService.extractNumber(chapter.name);
      for (let i = 0; i < pool.length; i++) {
        const e: BgmEpisode = pool[i];
        if (wantNum > 0 && (e.ep === wantNum || e.sort === wantNum)) {
          matched = e.id;
          break;
        }
      }
      if (matched === 0) {
        if (wantNum > 0) {
          if (wantNum <= pool.length) {
            matched = pool[wantNum - 1].id;
          }
        } else {
          matched = pool[0].id;
        }
      }
    }
    EpisodeCommentService.epIdCache.set(chapter.id, matched);
    return matched;
  }

  // 单集评论：内存缓存 → next API 全量拉取（无分页，replies 内嵌于各评论）；
  // force = 跳过缓存；拉取后按当前登录用户计算"我是否已回应"
  static async fetchComments(epId: number, force: boolean = false): Promise<EpisodeComment[]> {
    const entry: CommentsCacheEntry | undefined = EpisodeCommentService.commentsCache.get(epId);
    if (!force && entry !== undefined && Date.now() - entry.fetchedAt < EpisodeCommentService.CACHE_MS) {
      return entry.items;
    }
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = EpisodeCommentService.UA;
    const raw: string = await Http.get(
      `${Settings.bangumiNextBase()}/p1/episodes/${epId}/comments`, headers);
    const myId: number = await EpisodeCommentService.myUserId();
    const items: EpisodeComment[] = EpisodeCommentService.parseComments(raw, myId);
    const fresh: CommentsCacheEntry = new CommentsCacheEntry();
    fresh.items = items;
    fresh.fetchedAt = Date.now();
    EpisodeCommentService.commentsCache.set(epId, fresh);
    return items;
  }

  // ---- 内部实现 ----

  // 评论解析：顶层为全量数组；按时间倒序（最新在前）
  private static parseComments(raw: string, myId: number): EpisodeComment[] {
    let parsed: BgmNextCommentRaw[];
    try {
      parsed = JSON.parse(raw) as BgmNextCommentRaw[];
    } catch (e) {
      throw new Error('comments_invalid');
    }
    if (!Array.isArray(parsed)) {
      throw new Error('comments_invalid');
    }
    const items: EpisodeComment[] = [];
    for (let i = 0; i < parsed.length; i++) {
      const item: EpisodeComment | undefined = EpisodeCommentService.parseComment(parsed[i], myId);
      if (item !== undefined) {
        items.push(item);
      }
    }
    items.sort((a: EpisodeComment, b: EpisodeComment): number => b.createdAtMs - a.createdAtMs);
    return items;
  }

  private static parseComment(entry: BgmNextCommentRaw, myId: number): EpisodeComment | undefined {
    if (typeof entry.id !== 'number' || entry.id <= 0 || typeof entry.content !== 'string') {
      return undefined;
    }
    const item: EpisodeComment = new EpisodeComment();
    item.id = entry.id;
    item.content = entry.content;
    item.createdAtMs = EpisodeCommentService.createdMs(entry.createdAt);
    item.nickname = EpisodeCommentService.displayName(entry.user);
    item.avatar = EpisodeCommentService.avatarUrl(entry.user);
    item.reactions = EpisodeCommentService.parseReactions(entry.reactions, myId);
    item.reactionCount = EpisodeCommentService.reactionTotal(item.reactions);
    item.myReactionValue = EpisodeCommentService.myReaction(item.reactions);
    item.blocks = EpisodeCommentService.parseBlocks(item.content);
    item.hasMask = EpisodeCommentService.listHasMask(item.blocks);
    const repliesRaw: BgmNextCommentRaw[] | undefined = entry.replies;
    if (repliesRaw !== undefined && repliesRaw !== null) {
      for (let i = 0; i < repliesRaw.length; i++) {
        const r: BgmNextCommentRaw = repliesRaw[i];
        if (typeof r.id !== 'number' || r.id <= 0 || typeof r.content !== 'string') {
          continue;
        }
        const reply: EpisodeCommentReply = new EpisodeCommentReply();
        reply.id = r.id;
        reply.content = r.content;
        reply.createdAtMs = EpisodeCommentService.createdMs(r.createdAt);
        reply.nickname = EpisodeCommentService.displayName(r.user);
        reply.avatar = EpisodeCommentService.avatarUrl(r.user);
        reply.reactions = EpisodeCommentService.parseReactions(r.reactions, myId);
        reply.myReactionValue = EpisodeCommentService.myReaction(reply.reactions);
        reply.blocks = EpisodeCommentService.parseBlocks(reply.content);
        reply.hasMask = EpisodeCommentService.listHasMask(reply.blocks);
        item.replies.push(reply);
      }
    }
    return item;
  }

  // reactions 原始数组 → 明细列表（人数为 0 的项丢弃）
  private static parseReactions(rs: BgmNextReactionRaw[] | undefined,
    myId: number): EpisodeReaction[] {
    const out: EpisodeReaction[] = [];
    if (rs === undefined || rs === null) {
      return out;
    }
    for (let i = 0; i < rs.length; i++) {
      const users: BgmNextReactionUserRaw[] | undefined = rs[i].users;
      const count: number = users !== undefined && users !== null ? users.length : 0;
      if (count <= 0) {
        continue;
      }
      const re: EpisodeReaction = new EpisodeReaction();
      re.value = typeof rs[i].value === 'number' ? (rs[i].value ?? 0) : 0;
      re.count = count;
      if (myId > 0 && users !== undefined && users !== null) {
        for (let u = 0; u < users.length; u++) {
          if (users[u].id === myId) {
            re.mine = true;
            break;
          }
        }
      }
      out.push(re);
    }
    return out;
  }

  // 各反应人数合计
  private static reactionTotal(reactions: EpisodeReaction[]): number {
    let total: number = 0;
    for (let i = 0; i < reactions.length; i++) {
      total += reactions[i].count;
    }
    return total;
  }

  // 当前用户已选反应值（0 = 未回应）
  private static myReaction(reactions: EpisodeReaction[]): number {
    for (let i = 0; i < reactions.length; i++) {
      if (reactions[i].mine) {
        return reactions[i].value;
      }
    }
    return 0;
  }

  private static listHasMask(blocks: CommentBlock[]): boolean {
    for (let i = 0; i < blocks.length; i++) {
      const segs: CommentSegment[] = blocks[i].segments;
      for (let j = 0; j < segs.length; j++) {
        if (segs[j].kind === 2) {
          return true;
        }
      }
    }
    return false;
  }

  // 秒级时间戳转毫秒（异常值归 0）
  private static createdMs(createdAt: number | undefined): number {
    if (typeof createdAt !== 'number' || !Number.isFinite(createdAt) || createdAt <= 0) {
      return 0;
    }
    return createdAt < 1000000000000 ? createdAt * 1000 : createdAt;
  }

  private static displayName(user: BgmNextUserRaw | undefined): string {
    if (user === undefined || user === null) {
      return '';
    }
    if (typeof user.nickname === 'string' && user.nickname !== '') {
      return user.nickname;
    }
    return typeof user.username === 'string' ? user.username : '';
  }

  private static avatarUrl(user: BgmNextUserRaw | undefined): string {
    if (user === undefined || user === null) {
      return '';
    }
    const avatar: BgmNextAvatarRaw | undefined = user.avatar;
    if (avatar === undefined || avatar === null) {
      return '';
    }
    let url: string = '';
    if (typeof avatar.medium === 'string' && avatar.medium !== '') {
      url = avatar.medium;
    } else if (typeof avatar.large === 'string' && avatar.large !== '') {
      url = avatar.large;
    } else if (typeof avatar.small === 'string' && avatar.small !== '') {
      url = avatar.small;
    }
    return Settings.rewriteBangumiImageUrl(url);
  }

  // 从文本提取集号：“第01话”“第 1 集” 均可（与 DanmakuService 同规则）
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

  // 正文解析为内容块序列：单个正则同时消费 BBCode 标签、(bgmN) 编号表情、
  // (musume_N)/(blake_N) 大表情与颜文字，按出现顺序扫描；
  // 块级标签（quote/code/align/left/center/right/indent）切块，行内样式作用于片段；
  // [code] 内容原样保留（内部其余 BBCode 不解析）；未知标签静默剥离，未闭合标签样式保持到结尾
  private static parseBlocks(content: string): CommentBlock[] {
    const ctx: BbCtx = new BbCtx();
    const re: RegExp =
      /\[(\/?)([a-zA-Z]+)(?:=([^\[\]]*))?\]|\(bgm(\d{1,3})\)|\((musume|blake)_(\d{1,3})\)|\((=A=|=w=|-w=|S_S|=v=|@_@|=W=|TAT|T_T|='=|=3=|= ='|=\/\/\/=|=\.,=|:P|LOL)\)/g;
    let last: number = 0;
    let m: RegExpExecArray | null = re.exec(content);
    while (m !== null) {
      // [code] 内：除 [/code] 外一切匹配按原文累积（内部 BBCode 不解析）
      if (ctx.st.inCode) {
        if (m.index > last) {
          ctx.st.codeBuf += content.substring(last, m.index);
        }
        if (m[1] === '/' && (m[2] ?? '').toLowerCase() === 'code') {
          EpisodeCommentService.closeCode(ctx);
        } else {
          ctx.st.codeBuf += m[0];
        }
        last = m.index + m[0].length;
        m = re.exec(content);
        continue;
      }
      if (m.index > last) {
        EpisodeCommentService.pushText(ctx, content.substring(last, m.index));
      }
      if (m[4] !== undefined) {
        EpisodeCommentService.pushBgmEmoji(ctx, m[4] ?? '');
      } else if (m[5] !== undefined) {
        EpisodeCommentService.pushSticker(ctx, m[5] ?? '', m[6] ?? '');
      } else if (m[7] !== undefined) {
        EpisodeCommentService.pushKaomoji(ctx, m[7] ?? '');
      } else {
        EpisodeCommentService.handleTag(ctx, m[1] === '/',
          (m[2] ?? '').toLowerCase(), (m[3] ?? '').trim());
      }
      last = m.index + m[0].length;
      m = re.exec(content);
    }
    if (ctx.st.inCode) {
      // 未闭合 [code] 兜底：剩余原文仍按代码块渲染
      if (last < content.length) {
        ctx.st.codeBuf += content.substring(last);
      }
      EpisodeCommentService.closeCode(ctx);
    } else if (last < content.length) {
      EpisodeCommentService.pushText(ctx, content.substring(last));
    }
    // 未闭合的 [img] 兜底：缓冲内容仍按图片渲染
    if (ctx.st.inImg && ctx.st.imgBuf.trim() !== '') {
      EpisodeCommentService.pushImage(ctx, ctx.st.imgBuf.trim());
    }
    EpisodeCommentService.closeBlock(ctx);
    return ctx.blocks;
  }

  // 当前块（懒创建：首次有内容时按 BbState 固化块级属性）
  private static ensureBlock(ctx: BbCtx): CommentBlock {
    if (ctx.cur === undefined) {
      const block: CommentBlock = new CommentBlock();
      block.align = ctx.st.align;
      block.indent = ctx.st.indentDepth;
      block.quote = ctx.st.quoteDepth > 0;
      ctx.cur = block;
    }
    return ctx.cur;
  }

  // 结束当前块（无片段的空块丢弃）
  private static closeBlock(ctx: BbCtx): void {
    if (ctx.cur !== undefined && ctx.cur.segments.length > 0) {
      ctx.blocks.push(ctx.cur);
    }
    ctx.cur = undefined;
  }

  // [code] 收束：缓冲原文作为独立代码块（空白内容丢弃）
  private static closeCode(ctx: BbCtx): void {
    ctx.st.inCode = false;
    const text: string = ctx.st.codeBuf;
    ctx.st.codeBuf = '';
    EpisodeCommentService.closeBlock(ctx);
    if (text.trim() === '') {
      return;
    }
    const seg: CommentSegment = new CommentSegment();
    seg.kind = 0;
    seg.text = text;
    const block: CommentBlock = new CommentBlock();
    block.code = true;
    block.segments.push(seg);
    ctx.blocks.push(block);
  }

  // [align=] 取值 → 对齐值（center 1，right 2，left/其余 0）
  private static mapAlign(value: string): number {
    const v: string = value.toLowerCase();
    return v === 'center' ? 1 : (v === 'right' ? 2 : 0);
  }

  // BBCode 标签开合处理：行内 b/i/u/s/color/size/url/img/mask/user，
  // 块级 quote/code/align/left/center/right/indent（开合均切块），其余忽略
  private static handleTag(ctx: BbCtx, closing: boolean,
    name: string, value: string): void {
    const st: BbState = ctx.st;
    if (!closing) {
      if (name === 'b') {
        st.bold = true;
      } else if (name === 'i') {
        st.italic = true;
      } else if (name === 'u') {
        st.underline = true;
      } else if (name === 's') {
        st.strike = true;
      } else if (name === 'color') {
        st.color = EpisodeCommentService.sanitizeColor(value);
      } else if (name === 'size') {
        st.fontSize = EpisodeCommentService.clampSize(value);
      } else if (name === 'url') {
        st.inUrl = true;
        st.linkUrl = value;
      } else if (name === 'img') {
        st.inImg = true;
        st.imgBuf = '';
      } else if (name === 'mask') {
        if (!st.masked) {
          st.masked = true;
          const placeholder: CommentSegment = new CommentSegment();
          placeholder.kind = 2;
          EpisodeCommentService.ensureBlock(ctx).segments.push(placeholder);
        }
      } else if (name === 'user') {
        st.inUser = true;
        st.userBuf = '';
      } else if (name === 'quote') {
        st.quoteDepth++;
        EpisodeCommentService.closeBlock(ctx);
      } else if (name === 'align') {
        st.align = EpisodeCommentService.mapAlign(value);
        EpisodeCommentService.closeBlock(ctx);
      } else if (name === 'left' || name === 'center' || name === 'right') {
        st.align = name === 'center' ? 1 : (name === 'right' ? 2 : 0);
        EpisodeCommentService.closeBlock(ctx);
      } else if (name === 'indent') {
        st.indentDepth++;
        EpisodeCommentService.closeBlock(ctx);
      } else if (name === 'code') {
        st.inCode = true;
        st.codeBuf = '';
        EpisodeCommentService.closeBlock(ctx);
      }
      return;
    }
    if (name === 'b') {
      st.bold = false;
    } else if (name === 'i') {
      st.italic = false;
    } else if (name === 'u') {
      st.underline = false;
    } else if (name === 's') {
      st.strike = false;
    } else if (name === 'color') {
      st.color = '';
    } else if (name === 'size') {
      st.fontSize = 0;
    } else if (name === 'url') {
      st.inUrl = false;
      st.linkUrl = '';
    } else if (name === 'img') {
      if (st.inImg) {
        st.inImg = false;
        const url: string = st.imgBuf.trim();
        st.imgBuf = '';
        if (url !== '') {
          EpisodeCommentService.pushImage(ctx, url);
        }
      }
    } else if (name === 'mask') {
      st.masked = false;
    } else if (name === 'user') {
      // [user]用户名[/user] → 主站用户页链接（@用户名）
      st.inUser = false;
      const userName: string = st.userBuf.trim();
      st.userBuf = '';
      if (userName !== '') {
        const seg: CommentSegment = new CommentSegment();
        seg.kind = 0;
        seg.text = `@${userName}`;
        seg.linkUrl = `${Settings.bangumiWebBase()}/user/${encodeURIComponent(userName)}`;
        EpisodeCommentService.ensureBlock(ctx).segments.push(seg);
      }
    } else if (name === 'quote') {
      if (st.quoteDepth > 0) {
        st.quoteDepth--;
      }
      EpisodeCommentService.closeBlock(ctx);
    } else if (name === 'align' || name === 'left' || name === 'center' || name === 'right') {
      st.align = 0;
      EpisodeCommentService.closeBlock(ctx);
    } else if (name === 'indent') {
      if (st.indentDepth > 0) {
        st.indentDepth--;
      }
      EpisodeCommentService.closeBlock(ctx);
    }
  }

  // 文本片段：套用当前 BBCode 样式入列；[img] 内文本累积为图片地址，
  // [user] 内文本累积为用户名；空片段跳过
  private static pushText(ctx: BbCtx, text: string): void {
    const st: BbState = ctx.st;
    if (st.inImg) {
      st.imgBuf += text;
      return;
    }
    if (st.inUser) {
      st.userBuf += text;
      return;
    }
    if (text === '') {
      return;
    }
    const seg: CommentSegment = new CommentSegment();
    seg.kind = 0;
    seg.text = text;
    seg.masked = st.masked;
    seg.bold = st.bold;
    seg.italic = st.italic;
    seg.underline = st.underline;
    seg.strike = st.strike;
    seg.color = st.color;
    seg.fontSize = st.fontSize;
    if (st.inUrl) {
      // [url=地址]文字[/url]：linkUrl 为显式地址；[url]裸地址[/url]：文本即地址
      seg.linkUrl = st.linkUrl !== '' ? st.linkUrl : text.trim();
    }
    EpisodeCommentService.ensureBlock(ctx).segments.push(seg);
  }

  // (bgmN) 编号表情 → lain.bgm.tv 表情图（经图片镜像出口），超范围保留原文：
  // 1..23 站娘组（bgm/，两位补零，11/23 为 gif 其余 png）；24..125 旧版组
  // （tv/，编号 -23，两位补零 gif）；200..238 tv_vs 组（png）；
  // 500..529 tv_500 组（500,501,505,515..519,521..523 为 gif 其余 png）
  private static pushBgmEmoji(ctx: BbCtx, numText: string): void {
    const n: number = parseInt(numText !== '' ? numText : '-1', 10);
    let url: string = '';
    if (n >= 1 && n <= EpisodeCommentService.BGM_EMOJI_NEW_MAX) {
      const ext: string = (n === 11 || n === 23) ? 'gif' : 'png';
      url = `https://lain.bgm.tv/img/smiles/bgm/${EpisodeCommentService.pad2(n)}.${ext}`;
    } else if (n >= 24 && n <= EpisodeCommentService.BGM_EMOJI_LEGACY_MAX) {
      url = `https://lain.bgm.tv/img/smiles/tv/${EpisodeCommentService.pad2(n - 23)}.gif`;
    } else if (n >= EpisodeCommentService.BGM_EMOJI_VS_MIN &&
      n <= EpisodeCommentService.BGM_EMOJI_VS_MAX) {
      url = `https://lain.bgm.tv/img/smiles/tv_vs/bgm_${n}.png`;
    } else if (n >= EpisodeCommentService.BGM_EMOJI_500_MIN &&
      n <= EpisodeCommentService.BGM_EMOJI_500_MAX) {
      const ext: string = EpisodeCommentService.isTv500Gif(n) ? 'gif' : 'png';
      url = `https://lain.bgm.tv/img/smiles/tv_500/bgm_${n}.${ext}`;
    }
    if (url !== '') {
      EpisodeCommentService.pushEmojiSegment(ctx, url, false);
    } else {
      EpisodeCommentService.pushText(ctx, `(bgm${numText})`);
    }
  }

  // tv_500 组 gif 扩展名判定（next.bgm.tv 前端 F 集合）
  private static isTv500Gif(n: number): boolean {
    return n === 500 || n === 501 || n === 505 ||
      (n >= 515 && n <= 519) || n === 521 || n === 522 || n === 523;
  }

  // (musume_N)/(blake_N) 大表情（240 原图，渲染约 55）：编号 1..118 全 gif，
  // musume 无 97/98（blake 独有）；编号两位补零（≥100 不补）
  private static pushSticker(ctx: BbCtx, set: string, numText: string): void {
    const n: number = parseInt(numText !== '' ? numText : '-1', 10);
    const valid: boolean = n >= 1 && n <= EpisodeCommentService.STICKER_ID_MAX &&
      !(set === 'musume' && (n === 97 || n === 98));
    if (valid) {
      const file: string = n < 100 ? EpisodeCommentService.pad2(n) : `${n}`;
      const url: string = `https://lain.bgm.tv/img/smiles/${set}/${set}_${file}.gif`;
      EpisodeCommentService.pushEmojiSegment(ctx, url, true);
    } else {
      EpisodeCommentService.pushText(ctx, `(${set}_${numText})`);
    }
  }

  // 颜文字表情：KAOMOJI_INDEX 精确匹配 → img/smiles/{序号}.gif，未命中保留原文
  private static pushKaomoji(ctx: BbCtx, code: string): void {
    const idx: number | undefined = EpisodeCommentService.KAOMOJI_INDEX[code];
    if (idx !== undefined) {
      EpisodeCommentService.pushEmojiSegment(ctx,
        `https://lain.bgm.tv/img/smiles/${idx}.gif`, false);
    } else {
      EpisodeCommentService.pushText(ctx, `(${code})`);
    }
  }

  // 表情片段统一入列（url 经图片镜像出口）
  private static pushEmojiSegment(ctx: BbCtx, url: string, large: boolean): void {
    const seg: CommentSegment = new CommentSegment();
    seg.kind = 1;
    seg.masked = ctx.st.masked;
    seg.emojiLarge = large;
    seg.emojiUrl = Settings.rewriteBangumiImageUrl(url);
    EpisodeCommentService.ensureBlock(ctx).segments.push(seg);
  }

  // 表情文件名两位补零（无补零一律 404）
  private static pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  // 内联图片片段（[img]，经图片镜像出口）；[url=x][img]..[/img][/url] 时图片继承链接
  private static pushImage(ctx: BbCtx, url: string): void {
    const seg: CommentSegment = new CommentSegment();
    seg.kind = 3;
    seg.masked = ctx.st.masked;
    if (ctx.st.inUrl) {
      seg.linkUrl = ctx.st.linkUrl !== '' ? ctx.st.linkUrl : url;
    }
    seg.imageUrl = Settings.rewriteBangumiImageUrl(url);
    EpisodeCommentService.ensureBlock(ctx).segments.push(seg);
  }

  // 常见色名 → hex（ArkUI fontColor 仅接受 hex 串，色名需映射）
  private static readonly COLOR_NAMES: Record<string, string> = {
    'black': '#000000', 'white': '#FFFFFF', 'red': '#FF0000', 'green': '#008000',
    'blue': '#0000FF', 'yellow': '#FFFF00', 'orange': '#FFA500', 'purple': '#800080',
    'pink': '#FFC0CB', 'brown': '#A52A2A', 'gray': '#808080', 'grey': '#808080',
    'silver': '#C0C0C0', 'cyan': '#00FFFF', 'magenta': '#FF00FF', 'olive': '#808000',
    'navy': '#000080', 'lime': '#00FF00', 'teal': '#008080', 'maroon': '#800000',
    'gold': '#FFD700', 'indigo': '#4B0082', 'violet': '#EE82EE', 'skyblue': '#87CEEB'
  };

  // [color=] 值清洗：#RGB/#RRGGBB/#AARRGGBB 原样放行，常见色名转 hex，其余丢弃
  private static sanitizeColor(value: string): string {
    if (value === '') {
      return '';
    }
    if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(value)) {
      return value;
    }
    const mapped: string = EpisodeCommentService.COLOR_NAMES[value.toLowerCase()];
    return mapped !== undefined ? mapped : '';
  }

  // [size=] 值清洗：6..60 视为字号，非法归 0（渲染端用默认字号）
  private static clampSize(value: string): number {
    const n: number = parseInt(value !== '' ? value : '-1', 10);
    if (Number.isNaN(n) || n < 6 || n > 60) {
      return 0;
    }
    return n;
  }
}
