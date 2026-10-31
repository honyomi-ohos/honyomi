// 剧集评论（Bangumi 吐槽箱，next.bgm.tv 新版接口）：
// 章节 → Bangumi 动画条目（matchSubject）→ 分集（getEpisodes）→ 单集评论全量拉取。
// 评论正文为 BBCode：[b][i][u][s][color=][size=][url][img][mask] 与 (bgmN)/(tvN) 表情；
// 接口无分页参数，一次返回全量数组且各评论内嵌 replies 楼中楼
import { Http } from '../net/Http';
import { Settings } from '../common/Settings';
import { BangumiApi, BgmEpisode } from './BangumiApi';
import { ChapterRecord, MangaRecord } from '../model/Models';

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

// 表情回应（仅统计参与人数）
interface BgmNextReactionRaw {
  users?: Object[];
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
// masked = 片段位于 [mask] 内（揭示前不渲染），其余字段为 BBCode 样式
export class CommentSegment {
  kind: number = 0;
  text: string = '';
  emojiUrl: string = '';
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

export class EpisodeCommentReply {
  id: number = 0;
  content: string = '';
  createdAtMs: number = 0;
  nickname: string = '';
  avatar: string = '';
  segments: CommentSegment[] = [];
  hasMask: boolean = false;
}

export class EpisodeComment {
  id: number = 0;
  content: string = '';
  createdAtMs: number = 0;
  nickname: string = '';
  avatar: string = '';
  // 表情回应总人数（各 reactions.users 人数之和）
  reactionCount: number = 0;
  segments: CommentSegment[] = [];
  // 含 [mask] 剧透段（点击遮罩可揭示）
  hasMask: boolean = false;
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
}

export class EpisodeCommentService {
  private static readonly UA: string = 'Honyomi/1.0 (HarmonyOS)';
  // 评论缓存 10 分钟（评论实时性要求不高，翻回同集直接复用）
  private static readonly CACHE_MS: number = 10 * 60 * 1000;
  // 表情合法编号：bgm 1..63 / tv 1..116（超范围保留原文）
  private static readonly BGM_EMOJI_MAX: number = 63;
  private static readonly TV_EMOJI_MAX: number = 116;
  // 章节 → Bangumi ep id（0 = 无匹配；同章节再次进入直接命中）
  private static epIdCache: Map<number, number> = new Map<number, number>();
  // ep id → 评论列表
  private static commentsCache: Map<number, CommentsCacheEntry> = new Map<number, CommentsCacheEntry>();

  // 加载章节对应评论：无匹配剧集抛 comments_no_episode，网络失败原样抛错
  static async loadForChapter(manga: MangaRecord, chapter: ChapterRecord): Promise<EpisodeComment[]> {
    const epId: number = await EpisodeCommentService.resolveEpisodeId(manga, chapter);
    if (epId <= 0) {
      throw new Error('comments_no_episode');
    }
    return EpisodeCommentService.fetchComments(epId);
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

  // 单集评论：内存缓存 → next API 全量拉取（无分页，replies 内嵌于各评论）
  static async fetchComments(epId: number): Promise<EpisodeComment[]> {
    const entry: CommentsCacheEntry | undefined = EpisodeCommentService.commentsCache.get(epId);
    if (entry !== undefined && Date.now() - entry.fetchedAt < EpisodeCommentService.CACHE_MS) {
      return entry.items;
    }
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = EpisodeCommentService.UA;
    const raw: string = await Http.get(
      `${Settings.bangumiNextBase()}/p1/episodes/${epId}/comments`, headers);
    const items: EpisodeComment[] = EpisodeCommentService.parseComments(raw);
    const fresh: CommentsCacheEntry = new CommentsCacheEntry();
    fresh.items = items;
    fresh.fetchedAt = Date.now();
    EpisodeCommentService.commentsCache.set(epId, fresh);
    return items;
  }

  // ---- 内部实现 ----

  // 评论解析：顶层为全量数组；按时间倒序（最新在前）
  private static parseComments(raw: string): EpisodeComment[] {
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
      const item: EpisodeComment | undefined = EpisodeCommentService.parseComment(parsed[i]);
      if (item !== undefined) {
        items.push(item);
      }
    }
    items.sort((a: EpisodeComment, b: EpisodeComment): number => b.createdAtMs - a.createdAtMs);
    return items;
  }

  private static parseComment(entry: BgmNextCommentRaw): EpisodeComment | undefined {
    if (typeof entry.id !== 'number' || entry.id <= 0 || typeof entry.content !== 'string') {
      return undefined;
    }
    const item: EpisodeComment = new EpisodeComment();
    item.id = entry.id;
    item.content = entry.content;
    item.createdAtMs = EpisodeCommentService.createdMs(entry.createdAt);
    item.nickname = EpisodeCommentService.displayName(entry.user);
    item.avatar = EpisodeCommentService.avatarUrl(entry.user);
    let reactions: number = 0;
    const rs: BgmNextReactionRaw[] | undefined = entry.reactions;
    if (rs !== undefined && rs !== null) {
      for (let i = 0; i < rs.length; i++) {
        const users: Object[] | undefined = rs[i].users;
        if (users !== undefined && users !== null) {
          reactions += users.length;
        }
      }
    }
    item.reactionCount = reactions;
    item.segments = EpisodeCommentService.parseSegments(item.content);
    item.hasMask = EpisodeCommentService.listHasMask(item.segments);
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
        reply.segments = EpisodeCommentService.parseSegments(reply.content);
        reply.hasMask = EpisodeCommentService.listHasMask(reply.segments);
        item.replies.push(reply);
      }
    }
    return item;
  }

  private static listHasMask(segments: CommentSegment[]): boolean {
    for (let i = 0; i < segments.length; i++) {
      if (segments[i].kind === 2) {
        return true;
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

  // 正文解析为扁平片段序列：单个正则同时消费 BBCode 标签与 (bgmN)/(tvN) 表情，
  // 按出现顺序扫描；未知标签静默剥离，未闭合标签样式保持到结尾
  private static parseSegments(content: string): CommentSegment[] {
    const segments: CommentSegment[] = [];
    const st: BbState = new BbState();
    const re: RegExp = /\[(\/?)([a-z]+)(?:=([^\[\]]*))?\]|\((bgm|tv)\s*(\d{1,3})\)/gi;
    let last: number = 0;
    let m: RegExpExecArray | null = re.exec(content);
    while (m !== null) {
      if (m.index > last) {
        EpisodeCommentService.pushText(segments, st, content.substring(last, m.index));
      }
      if (m[4] !== undefined) {
        EpisodeCommentService.pushEmoji(segments, st, m[4], m[5] ?? '');
      } else {
        EpisodeCommentService.handleTag(segments, st, m[1] === '/',
          (m[2] ?? '').toLowerCase(), (m[3] ?? '').trim());
      }
      last = m.index + m[0].length;
      m = re.exec(content);
    }
    if (last < content.length) {
      EpisodeCommentService.pushText(segments, st, content.substring(last));
    }
    // 未闭合的 [img] 兜底：缓冲内容仍按图片渲染
    if (st.inImg && st.imgBuf.trim() !== '') {
      EpisodeCommentService.pushImage(segments, st, st.imgBuf.trim());
    }
    return segments;
  }

  // BBCode 标签开合处理：b/i/u/s/color/size/url/img/mask，其余忽略
  private static handleTag(segments: CommentSegment[], st: BbState, closing: boolean,
    name: string, value: string): void {
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
          segments.push(placeholder);
        }
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
          EpisodeCommentService.pushImage(segments, st, url);
        }
      }
    } else if (name === 'mask') {
      st.masked = false;
    }
  }

  // 文本片段：套用当前 BBCode 样式入列；[img] 内文本累积为图片地址；空片段跳过
  private static pushText(segments: CommentSegment[], st: BbState, text: string): void {
    if (st.inImg) {
      st.imgBuf += text;
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
    segments.push(seg);
  }

  // 表情片段：编号合法转 lain.bgm.tv 表情图（经图片镜像出口），超范围保留原文
  private static pushEmoji(segments: CommentSegment[], st: BbState, set: string, numText: string): void {
    const lower: string = set.toLowerCase();
    const n: number = parseInt(numText !== '' ? numText : '-1', 10);
    const max: number = lower === 'bgm' ?
      EpisodeCommentService.BGM_EMOJI_MAX : EpisodeCommentService.TV_EMOJI_MAX;
    if ((lower === 'bgm' || lower === 'tv') && n >= 1 && n <= max) {
      const seg: CommentSegment = new CommentSegment();
      seg.kind = 1;
      seg.masked = st.masked;
      seg.emojiUrl = Settings.rewriteBangumiImageUrl(`https://lain.bgm.tv/img/smiles/${lower}/${n}.gif`);
      segments.push(seg);
    } else {
      EpisodeCommentService.pushText(segments, st, `(${set}${numText})`);
    }
  }

  // 内联图片片段（[img]，经图片镜像出口）；[url=x][img]..[/img][/url] 时图片继承链接
  private static pushImage(segments: CommentSegment[], st: BbState, url: string): void {
    const seg: CommentSegment = new CommentSegment();
    seg.kind = 3;
    seg.masked = st.masked;
    if (st.inUrl) {
      seg.linkUrl = st.linkUrl !== '' ? st.linkUrl : url;
    }
    seg.imageUrl = Settings.rewriteBangumiImageUrl(url);
    segments.push(seg);
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
