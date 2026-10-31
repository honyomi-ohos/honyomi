// Bangumi（bgm.tv）公开数据 API：每日放送日历 + 条目详情
// 旧版 /calendar 返回七组「星期 + 条目列表」，v0 /v0/subjects/{id} 返回单条目详情；
// 图片地址可能为协议相对形式（//lain.bgm.tv/...），统一补 https 前缀
import { Http } from '../net/Http';
import { Settings } from '../common/Settings';
import { AppDb } from './AppDb';

// ---- 原始 JSON 模型 ----

interface BgmWeekdayRaw {
  id?: number;
  en?: string;
  cn?: string;
  ja?: string;
}

interface BgmImagesRaw {
  large?: string;
  common?: string;
  medium?: string;
}

interface BgmRatingRaw {
  score?: number;
  total?: number;
  rank?: number;
  // 评分直方图：键为 "1".."10"（星级），值为该星级人数
  count?: Record<string, number>;
}

// v0 subject 收藏统计
interface BgmCollectionRaw {
  wish?: number;
  collect?: number;
  doing?: number;
  on_hold?: number;
  dropped?: number;
}

interface BgmTagRaw {
  name?: string;
  count?: number;
}

interface BgmCalendarItemRaw {
  id: number;
  name?: string;
  name_cn?: string;
  summary?: string;
  air_date?: string;
  air_weekday?: number;
  images?: BgmImagesRaw;
  eps?: number;
  rating?: BgmRatingRaw;
}

interface BgmCalendarDayRaw {
  weekday?: BgmWeekdayRaw;
  items?: BgmCalendarItemRaw[];
}

interface BgmSubjectRaw {
  id: number;
  name?: string;
  name_cn?: string;
  summary?: string;
  date?: string;
  platform?: string;
  images?: BgmImagesRaw;
  eps?: number;
  total_episodes?: number;
  rating?: BgmRatingRaw;
  collection?: BgmCollectionRaw;
  tags?: BgmTagRaw[];
  infobox?: BgmInfoboxRowRaw[];
}

// v0 subject infobox 键值行（value 为字符串或 [{v}] 数组，此处宽松建模）
interface BgmInfoboxRowRaw {
  key?: string;
  value?: string | BgmInfoboxValueItemRaw[];
}

interface BgmInfoboxValueItemRaw {
  v?: string;
}

// v0 /v0/search/subjects 响应与条目
interface BgmSearchRespRaw {
  data?: BgmSearchItemRaw[];
}

interface BgmSearchItemRaw {
  id?: number;
  name?: string;
  name_cn?: string;
  images?: BgmImagesRaw;
}

interface BgmSearchFilter {
  type: number[];
}

interface BgmSearchRequest {
  keyword: string;
  filter: BgmSearchFilter;
}

// v0 /v0/subjects/{id}/subjects 扁平条目
interface BgmRelatedSubjectRaw {
  id?: number;
  name?: string;
  name_cn?: string;
  relation?: string;
  images?: BgmImagesRaw;
}

// v0 /v0/subjects/{id}/characters 角色项
interface BgmCharacterRaw {
  id?: number;
  name?: string;
  // 1=主角 2=配角 3=客串
  type?: number;
  images?: BgmImagesRaw;
  // 出演声优（取首位）
  actors?: BgmActorRaw[];
}

interface BgmActorRaw {
  id?: number;
  name?: string;
}

// v0 /v0/subjects/{id}/persons 制作人员项
interface BgmPersonRaw {
  id?: number;
  name?: string;
  // 职务列表（如 ["导演","分镜"]），以「/」连接
  career?: string[];
  images?: BgmImagesRaw;
}

// v0 /v0/episodes 分页响应
interface BgmEpisodesRespRaw {
  data?: BgmEpisodeRaw[];
  total?: number;
  limit?: number;
  offset?: number;
}

// v0 /v0/episodes 单集项
interface BgmEpisodeRaw {
  id?: number;
  subject_id?: number;
  // 集类型：0=正片 1=SP 2=OP 3=ED 4=预告/宣传 6=其他
  type?: number;
  airdate?: string;
  name?: string;
  name_cn?: string;
  // 集号（正片从 1 起）
  ep?: number;
  sort?: number;
  comment?: number;
}

// ---- 公开模型 ----

// 每日放送条目（日历卡片）
export class BgmCalendarItem {
  id: number = 0;
  name: string = '';
  nameCn: string = '';
  airDate: string = '';
  cover: string = '';
  eps: number = 0;
  score: number = 0;
  // JS 星期（0=周日 .. 6=周六，与 Date.getDay() 一致）
  jsDay: number = 0;
}

// 条目详情（v0 subject）
export class BgmSubjectDetail {
  id: number = 0;
  name: string = '';
  nameCn: string = '';
  summary: string = '';
  date: string = '';
  platform: string = '';
  cover: string = '';
  eps: number = 0;
  // v0 total_episodes：动画正片总集数（0 = 未知）
  totalEps: number = 0;
  score: number = 0;
  // 评分人数与排名（0 = 无）
  ratingTotal: number = 0;
  ratingRank: number = 0;
  // 评分直方图：索引 0..9 对应 1..10 星人数
  scoreHistogram: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  // infobox 作者/原作（作者校验用；解析不到为空串）
  author: string = '';
  // 标签（含热度）
  tags: BgmTag[] = [];
  // infobox 键值行（作品信息表）
  infobox: BgmInfoboxEntry[] = [];
  // 收藏统计
  collection: BgmCollectionStats = new BgmCollectionStats();
}

// 条目标签（bgm.tv 热门标签，count = 标记人数）
export class BgmTag {
  name: string = '';
  count: number = 0;
}

// infobox 键值行（作品信息表展示用）
export class BgmInfoboxEntry {
  key: string = '';
  text: string = '';
}

// 收藏统计（wish 想看 / collect 看过 / doing 在看 / onHold 搁置 / dropped 抛弃）
export class BgmCollectionStats {
  wish: number = 0;
  collect: number = 0;
  doing: number = 0;
  onHold: number = 0;
  dropped: number = 0;
}

// 角色（含出演声优）
export class BgmCharacter {
  id: number = 0;
  name: string = '';
  // 1=主角 2=配角 3=客串
  roleType: number = 0;
  cover: string = '';
  actorName: string = '';
}

// 制作人员
export class BgmPerson {
  id: number = 0;
  name: string = '';
  // 职务（「/」连接，如「导演/分镜」）
  career: string = '';
  cover: string = '';
}

// 相关条目卡片（v0 /v0/subjects/{id}/subjects）
export class BgmRelatedSubject {
  id: number = 0;
  name: string = '';
  nameCn: string = '';
  // bgm.tv 原始中文关系串（"续集"/"前传"/"番外篇"/"衍生"/"主线故事"/"总集篇" 等）
  relation: string = '';
  cover: string = '';
}

// 单集（v0 /v0/episodes，id 即 Bangumi ep id，可用于评论/吐槽定位）
export class BgmEpisode {
  id: number = 0;
  // 0=正片 1=SP 2=OP 3=ED 4=预告/宣传 6=其他
  type: number = 0;
  airdate: string = '';
  name: string = '';
  nameCn: string = '';
  // 集号（正片从 1 起，0 = 未知）
  ep: number = 0;
  sort: number = 0;
  comment: number = 0;
}

export class BangumiApi {
  // API 基地址：默认 api.bgm.tv；用户在高级设置配置镜像后经 Settings 动态读取
  private static readonly UA: string = 'Honyomi/1.0 (HarmonyOS)';
  private static readonly CACHE_MS: number = 30 * 60 * 1000;
  // 日历内存缓存（整周日历一次拉取，30 分钟内复用）
  private static calendarCache: BgmCalendarItem[] = [];
  private static calendarFetchedAt: number = 0;
  private static calendarInflight: Promise<BgmCalendarItem[]> | undefined = undefined;
  // 条目详情缓存
  private static subjectCache: Map<number, BgmSubjectDetail> = new Map<number, BgmSubjectDetail>();
  // 相关条目缓存
  private static relatedCache: Map<number, BgmRelatedSubject[]> = new Map<number, BgmRelatedSubject[]>();
  // 角色缓存
  private static charactersCache: Map<number, BgmCharacter[]> = new Map<number, BgmCharacter[]>();
  // 制作人员缓存
  private static personsCache: Map<number, BgmPerson[]> = new Map<number, BgmPerson[]>();
  // 分集列表缓存
  private static episodesCache: Map<number, BgmEpisode[]> = new Map<number, BgmEpisode[]>();
  // 名称+作者匹配结果缓存（key = type|title|author → 条目 id，0 = 无匹配）
  private static matchCache: Map<string, number> = new Map<string, number>();

  // ---- 本地数据库缓存（bgmCache 表）----
  // Bangumi 数据变动频率低（放送表每日微调、条目详情/相关系列近乎静态），
  // 原始响应整体落库，命中后重走解析路径（图片镜像等设置实时生效）；
  // 数据库未初始化时静默跳过缓存，仅走网络
  // 每日放送缓存有效期（放送表按天变化）
  private static readonly DB_CAL_TTL_MS: number = 24 * 60 * 60 * 1000;
  // 条目详情/相关系列/匹配结果缓存有效期（近乎静态，7 天）
  private static readonly DB_TTL_MS: number = 7 * 24 * 60 * 60 * 1000;

  // 读缓存：超龄按未命中返回 undefined；行损坏/库未就绪同样返回 undefined
  private static async cacheGet(key: string, maxAgeMs: number): Promise<string | undefined> {
    try {
      const store = await AppDb.get();
      const rs = await store.querySql(`SELECT payload, fetchedAt FROM bgmCache WHERE key = ?`, [key]);
      try {
        if (!rs.goToNextRow()) {
          return undefined;
        }
        const fetchedAt: number = rs.getLong(rs.getColumnIndex('fetchedAt'));
        if (Date.now() - fetchedAt >= maxAgeMs) {
          return undefined;
        }
        return rs.getString(rs.getColumnIndex('payload'));
      } finally {
        rs.close();
      }
    } catch (e) {
      return undefined;
    }
  }

  // 读缓存（忽略过期时间）：网络失败时的旧数据回退通道
  private static async cacheGetAnyAge(key: string): Promise<string | undefined> {
    try {
      const store = await AppDb.get();
      const rs = await store.querySql(`SELECT payload FROM bgmCache WHERE key = ?`, [key]);
      try {
        return rs.goToNextRow() ? rs.getString(rs.getColumnIndex('payload')) : undefined;
      } finally {
        rs.close();
      }
    } catch (e) {
      return undefined;
    }
  }

  // 写缓存（upsert）：失败仅吞掉，不影响主流程
  private static async cachePut(key: string, payload: string): Promise<void> {
    try {
      const store = await AppDb.get();
      await store.executeSql(
        `INSERT INTO bgmCache(key, payload, fetchedAt) VALUES(?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET payload = excluded.payload, fetchedAt = excluded.fetchedAt`,
        [key, payload, Date.now()]);
    } catch (e) {
      // 缓存写失败忽略
    }
  }

  // 每日放送整周日历：内存缓存 → 本地数据库缓存（24h）→ 网络（响应落库）；
  // 网络失败回退本地旧缓存（忽略过期），无缓存才抛错；force=true 时强制走网络
  static async getCalendar(force: boolean): Promise<BgmCalendarItem[]> {
    if (!force && BangumiApi.calendarCache.length > 0 &&
      Date.now() - BangumiApi.calendarFetchedAt < BangumiApi.CACHE_MS) {
      return BangumiApi.calendarCache;
    }
    if (!force) {
      const persisted: string | undefined = await BangumiApi.cacheGet('calendar', BangumiApi.DB_CAL_TTL_MS);
      if (persisted !== undefined) {
        try {
          const items: BgmCalendarItem[] = BangumiApi.parseCalendar(persisted);
          if (items.length > 0) {
            BangumiApi.calendarCache = items;
            BangumiApi.calendarFetchedAt = Date.now();
            return items;
          }
        } catch (e) {
          // 缓存行损坏按未命中处理
        }
      }
    }
    if (BangumiApi.calendarInflight !== undefined) {
      return BangumiApi.calendarInflight;
    }
    const task: Promise<BgmCalendarItem[]> = BangumiApi.fetchCalendarRaw().then(
      (raw: string): BgmCalendarItem[] => {
        const items: BgmCalendarItem[] = BangumiApi.parseCalendar(raw);
        BangumiApi.calendarCache = items;
        BangumiApi.calendarFetchedAt = Date.now();
        BangumiApi.calendarInflight = undefined;
        BangumiApi.cachePut('calendar', raw);
        return items;
      },
      (e: Object): Promise<BgmCalendarItem[]> => {
        BangumiApi.calendarInflight = undefined;
        // 网络失败回退本地旧缓存（忽略过期），仍无则原样抛错
        return BangumiApi.cacheGetAnyAge('calendar').then((stale: string | undefined): BgmCalendarItem[] => {
          if (stale !== undefined) {
            try {
              const items: BgmCalendarItem[] = BangumiApi.parseCalendar(stale);
              if (items.length > 0) {
                return items;
              }
            } catch (e2) {
              // 旧缓存损坏继续走抛错
            }
          }
          throw new Error(e instanceof Error ? e.message : String(e));
        });
      });
    BangumiApi.calendarInflight = task;
    return task;
  }

  // 条目详情：内存缓存 → 本地数据库缓存（7 天）→ 网络（响应落库）；网络失败回退本地旧缓存
  static async getSubject(id: number): Promise<BgmSubjectDetail> {
    const cached: BgmSubjectDetail | undefined = BangumiApi.subjectCache.get(id);
    if (cached !== undefined) {
      return cached;
    }
    const persisted: string | undefined = await BangumiApi.cacheGet(`subject:${id}`, BangumiApi.DB_TTL_MS);
    if (persisted !== undefined) {
      try {
        const detail: BgmSubjectDetail = BangumiApi.parseSubject(persisted);
        BangumiApi.subjectCache.set(id, detail);
        return detail;
      } catch (e) {
        // 缓存行损坏按未命中处理
      }
    }
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = BangumiApi.UA;
    let raw: string;
    try {
      raw = await Http.get(`${Settings.bangumiApiBase()}/v0/subjects/${id}`, headers);
    } catch (e) {
      // 网络失败回退本地旧缓存（忽略过期），仍无则原样抛错
      const stale: string | undefined = await BangumiApi.cacheGetAnyAge(`subject:${id}`);
      if (stale !== undefined) {
        try {
          const detail: BgmSubjectDetail = BangumiApi.parseSubject(stale);
          BangumiApi.subjectCache.set(id, detail);
          return detail;
        } catch (e2) {
          // 旧缓存损坏继续走抛错
        }
      }
      const subjErr = e as Error;
      throw subjErr;
    }
    const detail: BgmSubjectDetail = BangumiApi.parseSubject(raw);
    BangumiApi.subjectCache.set(id, detail);
    BangumiApi.cachePut(`subject:${id}`, raw);
    return detail;
  }

  // 相关条目列表（内存缓存 → 本地数据库缓存 7 天 → 网络落库；失败回退旧缓存；
  // 排序对齐 animeko：前传 > 续集 > 衍生 > 番外篇 > 其他）
  static async getSubjectRelations(id: number): Promise<BgmRelatedSubject[]> {
    const cached: BgmRelatedSubject[] | undefined = BangumiApi.relatedCache.get(id);
    if (cached !== undefined) {
      return cached;
    }
    const persisted: string | undefined = await BangumiApi.cacheGet(`relations:${id}`, BangumiApi.DB_TTL_MS);
    if (persisted !== undefined) {
      try {
        const items: BgmRelatedSubject[] = BangumiApi.parseRelations(persisted);
        BangumiApi.relatedCache.set(id, items);
        return items;
      } catch (e) {
        // 缓存行损坏按未命中处理
      }
    }
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = BangumiApi.UA;
    let raw: string;
    try {
      raw = await Http.get(`${Settings.bangumiApiBase()}/v0/subjects/${id}/subjects`, headers);
    } catch (e) {
      // 网络失败回退本地旧缓存（忽略过期），仍无则原样抛错
      const stale: string | undefined = await BangumiApi.cacheGetAnyAge(`relations:${id}`);
      if (stale !== undefined) {
        try {
          const items: BgmRelatedSubject[] = BangumiApi.parseRelations(stale);
          BangumiApi.relatedCache.set(id, items);
          return items;
        } catch (e2) {
          // 旧缓存损坏继续走抛错
        }
      }
      const relErr = e as Error;
      throw relErr;
    }
    const items: BgmRelatedSubject[] = BangumiApi.parseRelations(raw);
    BangumiApi.relatedCache.set(id, items);
    BangumiApi.cachePut(`relations:${id}`, raw);
    return items;
  }

  // 角色列表（内存缓存 → 本地数据库缓存 7 天 → 网络落库；失败回退旧缓存）
  static async getSubjectCharacters(id: number): Promise<BgmCharacter[]> {
    const cached: BgmCharacter[] | undefined = BangumiApi.charactersCache.get(id);
    if (cached !== undefined) {
      return cached;
    }
    const persisted: string | undefined = await BangumiApi.cacheGet(`characters:${id}`, BangumiApi.DB_TTL_MS);
    if (persisted !== undefined) {
      try {
        const items: BgmCharacter[] = BangumiApi.parseCharacters(persisted);
        BangumiApi.charactersCache.set(id, items);
        return items;
      } catch (e) {
        // 缓存行损坏按未命中处理
      }
    }
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = BangumiApi.UA;
    let raw: string;
    try {
      raw = await Http.get(`${Settings.bangumiApiBase()}/v0/subjects/${id}/characters`, headers);
    } catch (e) {
      // 网络失败回退本地旧缓存（忽略过期），仍无则原样抛错
      const stale: string | undefined = await BangumiApi.cacheGetAnyAge(`characters:${id}`);
      if (stale !== undefined) {
        try {
          const items: BgmCharacter[] = BangumiApi.parseCharacters(stale);
          BangumiApi.charactersCache.set(id, items);
          return items;
        } catch (e2) {
          // 旧缓存损坏继续走抛错
        }
      }
      const charErr = e as Error;
      throw charErr;
    }
    const items: BgmCharacter[] = BangumiApi.parseCharacters(raw);
    BangumiApi.charactersCache.set(id, items);
    BangumiApi.cachePut(`characters:${id}`, raw);
    return items;
  }

  // 制作人员列表（内存缓存 → 本地数据库缓存 7 天 → 网络落库；失败回退旧缓存）
  static async getSubjectPersons(id: number): Promise<BgmPerson[]> {
    const cached: BgmPerson[] | undefined = BangumiApi.personsCache.get(id);
    if (cached !== undefined) {
      return cached;
    }
    const persisted: string | undefined = await BangumiApi.cacheGet(`persons:${id}`, BangumiApi.DB_TTL_MS);
    if (persisted !== undefined) {
      try {
        const items: BgmPerson[] = BangumiApi.parsePersons(persisted);
        BangumiApi.personsCache.set(id, items);
        return items;
      } catch (e) {
        // 缓存行损坏按未命中处理
      }
    }
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = BangumiApi.UA;
    let raw: string;
    try {
      raw = await Http.get(`${Settings.bangumiApiBase()}/v0/subjects/${id}/persons`, headers);
    } catch (e) {
      // 网络失败回退本地旧缓存（忽略过期），仍无则原样抛错
      const stale: string | undefined = await BangumiApi.cacheGetAnyAge(`persons:${id}`);
      if (stale !== undefined) {
        try {
          const items: BgmPerson[] = BangumiApi.parsePersons(stale);
          BangumiApi.personsCache.set(id, items);
          return items;
        } catch (e2) {
          // 旧缓存损坏继续走抛错
        }
      }
      const personErr = e as Error;
      throw personErr;
    }
    const items: BgmPerson[] = BangumiApi.parsePersons(raw);
    BangumiApi.personsCache.set(id, items);
    BangumiApi.cachePut(`persons:${id}`, raw);
    return items;
  }

  // 分集列表（内存缓存 → 本地数据库缓存 7 天 → 网络落库；失败回退旧缓存）：
  // limit=100 分页拉全（最多 10 页），按 type/ep/sort 排序对齐 bgm.tv 展示顺序
  static async getEpisodes(id: number): Promise<BgmEpisode[]> {
    const cached: BgmEpisode[] | undefined = BangumiApi.episodesCache.get(id);
    if (cached !== undefined) {
      return cached;
    }
    const persisted: string | undefined = await BangumiApi.cacheGet(`episodes:${id}`, BangumiApi.DB_TTL_MS);
    if (persisted !== undefined) {
      try {
        const items: BgmEpisode[] = BangumiApi.parseEpisodes(persisted);
        if (items.length > 0) {
          BangumiApi.episodesCache.set(id, items);
          return items;
        }
      } catch (e) {
        // 缓存行损坏按未命中处理
      }
    }
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = BangumiApi.UA;
    const all: BgmEpisode[] = [];
    const pageSize: number = 100;
    for (let offset = 0; offset < pageSize * 10; offset += pageSize) {
      let raw: string;
      try {
        raw = await Http.get(`${Settings.bangumiApiBase()}/v0/episodes?subject_id=${id}&limit=${pageSize}&offset=${offset}`, headers);
      } catch (e) {
        // 首页失败回退本地旧缓存（忽略过期），仍无则原样抛错；
        // 后续页失败则用已拉到的部分集
        if (offset === 0) {
          const stale: string | undefined = await BangumiApi.cacheGetAnyAge(`episodes:${id}`);
          if (stale !== undefined) {
            try {
              const items: BgmEpisode[] = BangumiApi.parseEpisodes(stale);
              if (items.length > 0) {
                BangumiApi.episodesCache.set(id, items);
                return items;
              }
            } catch (e2) {
              // 旧缓存损坏继续走抛错
            }
          }
          const epErr = e as Error;
          throw epErr;
        }
        break;
      }
      const page: BgmEpisode[] = BangumiApi.parseEpisodes(raw);
      for (let i = 0; i < page.length; i++) {
        all.push(page[i]);
      }
      if (page.length < pageSize) {
        break;
      }
    }
    BangumiApi.episodesCache.set(id, all);
    const cachedRows: BgmEpisodeRaw[] = all.map((item: BgmEpisode): BgmEpisodeRaw => {
      const row: BgmEpisodeRaw = {};
      row.id = item.id;
      row.type = item.type;
      row.airdate = item.airdate;
      row.name = item.name;
      row.name_cn = item.nameCn;
      row.ep = item.ep;
      row.sort = item.sort;
      row.comment = item.comment;
      return row;
    });
    const cachedPayload: BgmEpisodesRespRaw = { data: cachedRows };
    BangumiApi.cachePut(`episodes:${id}`, JSON.stringify(cachedPayload));
    return all;
  }

  // ---- 内部实现 ----

  // 名称+作者匹配 Bangumi 条目（ACGN 源作品 → 相关系列入口）：
  // v0 搜索（按内容类型过滤：书籍=1 / 动画=2）→ 标题精确/包含匹配 → 作者校验（infobox 作者/原作）。
  // 返回匹配条目 id；搜索失败/无匹配返回 0（调用方静默隐藏区块）。
  // 结果按 key 记忆化并落库（含 0=无匹配，7 天内复用）
  static async matchSubject(title: string, author: string, type: number): Promise<number> {
    const t: string = title.trim();
    const a: string = author.trim();
    if (t === '') {
      return 0;
    }
    const cacheKey: string = `${type}|${t}|${a}`;
    const dbKey: string = `match:${cacheKey}`;
    const cached: number | undefined = BangumiApi.matchCache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    // 本地数据库缓存（7 天内有效，含“无匹配”0 值）
    const persisted: string | undefined = await BangumiApi.cacheGet(dbKey, BangumiApi.DB_TTL_MS);
    if (persisted !== undefined) {
      const id: number = Number(persisted);
      if (Math.floor(id) === id && id >= 0) {
        BangumiApi.matchCache.set(cacheKey, id);
        return id;
      }
    }
    const results: BgmRelatedSubject[] = await BangumiApi.fetchSearchResults(t, type);
    const lowerTitle: string = t.toLowerCase();
    const exact: BgmRelatedSubject[] = [];
    const partial: BgmRelatedSubject[] = [];
    for (let i = 0; i < results.length; i++) {
      const r: BgmRelatedSubject = results[i];
      const name: string = r.name.toLowerCase();
      const nameCn: string = r.nameCn.toLowerCase();
      if (nameCn === lowerTitle || name === lowerTitle) {
        exact.push(r);
      } else if ((nameCn !== '' && (nameCn.indexOf(lowerTitle) >= 0 || lowerTitle.indexOf(nameCn) >= 0)) ||
        (name !== '' && (name.indexOf(lowerTitle) >= 0 || lowerTitle.indexOf(name) >= 0))) {
        partial.push(r);
      }
    }
    const candidates: BgmRelatedSubject[] = exact.length > 0 ? exact : partial;
    if (candidates.length === 0) {
      BangumiApi.matchCache.set(cacheKey, 0);
      BangumiApi.cachePut(dbKey, '0');
      return 0;
    }
    if (a !== '') {
      // 作者校验：前 3 个候选逐条拉详情比对 infobox 作者/原作（命中即返回）
      for (let i = 0; i < candidates.length && i < 3; i++) {
        try {
          const subject: BgmSubjectDetail = await BangumiApi.getSubject(candidates[i].id);
          if (BangumiApi.authorMatch(subject.author, a)) {
            BangumiApi.matchCache.set(cacheKey, candidates[i].id);
            BangumiApi.cachePut(dbKey, `${candidates[i].id}`);
            return candidates[i].id;
          }
        } catch (e) {
          // 单条目详情失败忽略，继续下一候选
        }
      }
    }
    BangumiApi.matchCache.set(cacheKey, candidates[0].id);
    BangumiApi.cachePut(dbKey, `${candidates[0].id}`);
    return candidates[0].id;
  }

  // v0 条目搜索（POST /v0/search/subjects，filter.type 限定内容类型），最多取 20 条
  private static async fetchSearchResults(keyword: string, type: number): Promise<BgmRelatedSubject[]> {
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = BangumiApi.UA;
    const filter: BgmSearchFilter = { type: [type] };
    const request: BgmSearchRequest = { keyword: keyword, filter: filter };
    const raw: string = await Http.post(`${Settings.bangumiApiBase()}/v0/search/subjects`,
      JSON.stringify(request), headers);
    let parsed: BgmSearchRespRaw;
    try {
      parsed = JSON.parse(raw) as BgmSearchRespRaw;
    } catch (e) {
      throw new Error('bgm_search_invalid');
    }
    const data: BgmSearchItemRaw[] | undefined = parsed.data;
    const items: BgmRelatedSubject[] = [];
    if (data === undefined || data === null || !Array.isArray(data)) {
      return items;
    }
    for (let i = 0; i < data.length && items.length < 20; i++) {
      const entry: BgmSearchItemRaw = data[i];
      if (typeof entry.id !== 'number' || entry.id <= 0) {
        continue;
      }
      const item: BgmRelatedSubject = new BgmRelatedSubject();
      item.id = entry.id;
      item.name = typeof entry.name === 'string' ? entry.name : '';
      item.nameCn = typeof entry.name_cn === 'string' ? entry.name_cn : '';
      item.cover = BangumiApi.imageUrl(entry.images);
      items.push(item);
    }
    return items;
  }

  // infobox 作者/原作提取（取首个非空值）
  private static infoboxAuthor(infobox: BgmInfoboxRowRaw[] | undefined): string {
    if (infobox === undefined || infobox === null || !Array.isArray(infobox)) {
      return '';
    }
    for (let i = 0; i < infobox.length; i++) {
      const row: BgmInfoboxRowRaw = infobox[i];
      if (row.key === '作者' || row.key === '原作') {
        const text: string = BangumiApi.infoboxValueText(row.value);
        if (text !== '') {
          return text;
        }
      }
    }
    return '';
  }

  // infobox 值归一：字符串原样；[{v}] 数组用「、」连接
  private static infoboxValueText(value: string | BgmInfoboxValueItemRaw[] | undefined): string {
    if (typeof value === 'string') {
      return value.trim();
    }
    if (value === undefined || value === null || !Array.isArray(value)) {
      return '';
    }
    const parts: string[] = [];
    for (let i = 0; i < value.length; i++) {
      const item: BgmInfoboxValueItemRaw = value[i];
      if (typeof item.v === 'string' && item.v.trim() !== '') {
        parts.push(item.v.trim());
      }
    }
    return parts.join('、');
  }

  // 作者匹配（双向包含，忽略大小写）：源作者多人与 Bangumi 单人、或反之均可命中
  private static authorMatch(bgmAuthor: string, author: string): boolean {
    if (bgmAuthor === '') {
      return false;
    }
    const a: string = bgmAuthor.toLowerCase();
    const b: string = author.toLowerCase();
    return a.indexOf(b) >= 0 || b.indexOf(a) >= 0;
  }

  // 关系文案：已知关系本地化，未知（如“游戏”“角色出演”）原样展示
  static relationLabelRes(relation: string): ResourceStr {
    if (relation === '前传') {
      return $r('app.string.subject_relation_prequel');
    }
    if (relation === '续集') {
      return $r('app.string.subject_relation_sequel');
    }
    if (relation === '衍生') {
      return $r('app.string.subject_relation_derived');
    }
    if (relation === '番外篇') {
      return $r('app.string.subject_relation_special');
    }
    if (relation === '主线故事') {
      return $r('app.string.subject_relation_main_story');
    }
    if (relation === '总集篇') {
      return $r('app.string.subject_relation_compilation');
    }
    return relation;
  }

  // 关系排序权重（对齐 animeko RelatedSubjectInfo.sortList）
  private static relationWeight(relation: string): number {
    if (relation === '前传') {
      return 10;
    }
    if (relation === '续集') {
      return 9;
    }
    if (relation === '衍生') {
      return 8;
    }
    if (relation === '番外篇') {
      return 7;
    }
    return 0;
  }

  // 每日放送原始响应拉取（解析由 parseCalendar 统一完成，缓存命中共用同一路径）
  private static async fetchCalendarRaw(): Promise<string> {
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = BangumiApi.UA;
    return Http.get(`${Settings.bangumiApiBase()}/calendar`, headers);
  }

  // 条目详情原始响应解析（结构非法抛 bgm_subject_invalid）
  private static parseSubject(raw: string): BgmSubjectDetail {
    let parsed: BgmSubjectRaw;
    try {
      parsed = JSON.parse(raw) as BgmSubjectRaw;
    } catch (e) {
      throw new Error('bgm_subject_invalid');
    }
    const detail: BgmSubjectDetail = new BgmSubjectDetail();
    detail.id = parsed.id;
    detail.name = typeof parsed.name === 'string' ? parsed.name : '';
    detail.nameCn = typeof parsed.name_cn === 'string' ? parsed.name_cn : '';
    detail.summary = typeof parsed.summary === 'string' ? parsed.summary : '';
    detail.date = typeof parsed.date === 'string' ? parsed.date : '';
    detail.platform = typeof parsed.platform === 'string' ? parsed.platform : '';
    detail.eps = typeof parsed.eps === 'number' ? Math.floor(parsed.eps) : 0;
    detail.totalEps = typeof parsed.total_episodes === 'number' ? Math.floor(parsed.total_episodes) : 0;
    if (parsed.rating !== undefined && parsed.rating !== null) {
      detail.score = typeof parsed.rating.score === 'number' ? parsed.rating.score : 0;
      detail.ratingTotal = typeof parsed.rating.total === 'number' ? Math.floor(parsed.rating.total) : 0;
      detail.ratingRank = typeof parsed.rating.rank === 'number' ? Math.floor(parsed.rating.rank) : 0;
      detail.scoreHistogram = BangumiApi.parseHistogram(parsed.rating.count);
    }
    if (parsed.collection !== undefined && parsed.collection !== null) {
      detail.collection = BangumiApi.parseCollection(parsed.collection);
    }
    detail.tags = BangumiApi.parseTags(parsed.tags);
    detail.infobox = BangumiApi.parseInfobox(parsed.infobox);
    detail.author = BangumiApi.infoboxAuthor(parsed.infobox);
    detail.cover = BangumiApi.imageUrl(parsed.images);
    return detail;
  }

  // 评分直方图：{"1":n,..."10":n} → 长度 10 数组（索引 0..9 对应 1..10 星）
  private static parseHistogram(count: Record<string, number> | undefined): number[] {
    const histogram: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    if (count === undefined || count === null) {
      return histogram;
    }
    for (let star = 1; star <= 10; star++) {
      const value: number = count[String(star)];
      if (typeof value === 'number' && value >= 0) {
        histogram[star - 1] = Math.floor(value);
      }
    }
    return histogram;
  }

  private static parseCollection(raw: BgmCollectionRaw): BgmCollectionStats {
    const stats: BgmCollectionStats = new BgmCollectionStats();
    stats.wish = typeof raw.wish === 'number' ? Math.floor(raw.wish) : 0;
    stats.collect = typeof raw.collect === 'number' ? Math.floor(raw.collect) : 0;
    stats.doing = typeof raw.doing === 'number' ? Math.floor(raw.doing) : 0;
    stats.onHold = typeof raw.on_hold === 'number' ? Math.floor(raw.on_hold) : 0;
    stats.dropped = typeof raw.dropped === 'number' ? Math.floor(raw.dropped) : 0;
    return stats;
  }

  // 标签解析（name + count），过滤空名并按 count 降序
  private static parseTags(raw: BgmTagRaw[] | undefined): BgmTag[] {
    const tags: BgmTag[] = [];
    if (raw === undefined || raw === null || !Array.isArray(raw)) {
      return tags;
    }
    for (let i = 0; i < raw.length; i++) {
      const entry: BgmTagRaw = raw[i];
      if (typeof entry.name !== 'string' || entry.name.trim() === '') {
        continue;
      }
      const tag: BgmTag = new BgmTag();
      tag.name = entry.name.trim();
      tag.count = typeof entry.count === 'number' && entry.count >= 0 ? Math.floor(entry.count) : 0;
      tags.push(tag);
    }
    tags.sort((a: BgmTag, b: BgmTag): number => b.count - a.count);
    return tags;
  }

  // infobox 键值行解析（作者/原作保留在作者校验通道，信息表同样展示）
  private static parseInfobox(infobox: BgmInfoboxRowRaw[] | undefined): BgmInfoboxEntry[] {
    const entries: BgmInfoboxEntry[] = [];
    if (infobox === undefined || infobox === null || !Array.isArray(infobox)) {
      return entries;
    }
    for (let i = 0; i < infobox.length; i++) {
      const row: BgmInfoboxRowRaw = infobox[i];
      if (typeof row.key !== 'string' || row.key.trim() === '') {
        continue;
      }
      const text: string = BangumiApi.infoboxValueText(row.value);
      if (text === '') {
        continue;
      }
      const entry: BgmInfoboxEntry = new BgmInfoboxEntry();
      entry.key = row.key.trim();
      entry.text = text;
      entries.push(entry);
    }
    return entries;
  }

  // 角色原始响应解析（结构非法抛 bgm_characters_invalid）：
  // 主角 → 配角 → 客串 排序，最多保留 30 条（横滑头像条 + 展开全部够用）
  private static parseCharacters(raw: string): BgmCharacter[] {
    let parsed: BgmCharacterRaw[];
    try {
      parsed = JSON.parse(raw) as BgmCharacterRaw[];
    } catch (e) {
      throw new Error('bgm_characters_invalid');
    }
    if (!Array.isArray(parsed)) {
      throw new Error('bgm_characters_invalid');
    }
    const items: BgmCharacter[] = [];
    for (let i = 0; i < parsed.length; i++) {
      const entry: BgmCharacterRaw = parsed[i];
      if (typeof entry.id !== 'number' || entry.id <= 0) {
        continue;
      }
      if (typeof entry.name !== 'string' || entry.name.trim() === '') {
        continue;
      }
      const item: BgmCharacter = new BgmCharacter();
      item.id = entry.id;
      item.name = entry.name.trim();
      item.roleType = typeof entry.type === 'number' ? entry.type : 0;
      item.cover = BangumiApi.imageUrl(entry.images);
      if (entry.actors !== undefined && Array.isArray(entry.actors) && entry.actors.length > 0) {
        const actor: BgmActorRaw = entry.actors[0];
        item.actorName = typeof actor.name === 'string' ? actor.name.trim() : '';
      }
      items.push(item);
    }
    items.sort((a: BgmCharacter, b: BgmCharacter): number => a.roleType - b.roleType);
    return items.length > 30 ? items.slice(0, 30) : items;
  }

  // 制作人员原始响应解析（结构非法抛 bgm_persons_invalid），最多保留 40 条
  private static parsePersons(raw: string): BgmPerson[] {
    let parsed: BgmPersonRaw[];
    try {
      parsed = JSON.parse(raw) as BgmPersonRaw[];
    } catch (e) {
      throw new Error('bgm_persons_invalid');
    }
    if (!Array.isArray(parsed)) {
      throw new Error('bgm_persons_invalid');
    }
    const items: BgmPerson[] = [];
    for (let i = 0; i < parsed.length; i++) {
      const entry: BgmPersonRaw = parsed[i];
      if (typeof entry.id !== 'number' || entry.id <= 0) {
        continue;
      }
      if (typeof entry.name !== 'string' || entry.name.trim() === '') {
        continue;
      }
      const item: BgmPerson = new BgmPerson();
      item.id = entry.id;
      item.name = entry.name.trim();
      item.career = entry.career !== undefined && Array.isArray(entry.career)
        ? entry.career.filter((c: string): boolean => typeof c === 'string' && c.trim() !== '').join('/') : '';
      item.cover = BangumiApi.imageUrl(entry.images);
      items.push(item);
    }
    return items.length > 40 ? items.slice(0, 40) : items;
  }

  // 分集原始响应解析（结构非法抛 bgm_episodes_invalid）：
  // 首选中文名，缺失回退原名；排序 type(正片优先) → sort → ep
  private static parseEpisodes(raw: string): BgmEpisode[] {
    let parsed: BgmEpisodesRespRaw;
    try {
      parsed = JSON.parse(raw) as BgmEpisodesRespRaw;
    } catch (e) {
      throw new Error('bgm_episodes_invalid');
    }
    const data: BgmEpisodeRaw[] | undefined = parsed.data;
    if (data === undefined || data === null || !Array.isArray(data)) {
      throw new Error('bgm_episodes_invalid');
    }
    const items: BgmEpisode[] = [];
    for (let i = 0; i < data.length; i++) {
      const entry: BgmEpisodeRaw = data[i];
      if (typeof entry.id !== 'number' || entry.id <= 0) {
        continue;
      }
      const item: BgmEpisode = new BgmEpisode();
      item.id = entry.id;
      item.type = typeof entry.type === 'number' ? entry.type : 0;
      item.airdate = typeof entry.airdate === 'string' ? entry.airdate : '';
      item.name = typeof entry.name === 'string' ? entry.name : '';
      item.nameCn = typeof entry.name_cn === 'string' && entry.name_cn !== '' ? entry.name_cn : item.name;
      item.ep = typeof entry.ep === 'number' ? entry.ep : 0;
      item.sort = typeof entry.sort === 'number' ? entry.sort : 0;
      item.comment = typeof entry.comment === 'number' ? Math.floor(entry.comment) : 0;
      items.push(item);
    }
    items.sort((a: BgmEpisode, b: BgmEpisode): number => {
      if (a.type !== b.type) {
        // 正片（0）在前，其余按 type 值排
        return a.type === 0 ? -1 : (b.type === 0 ? 1 : a.type - b.type);
      }
      if (a.sort !== b.sort) {
        return a.sort - b.sort;
      }
      return a.ep - b.ep;
    });
    return items;
  }

  // 相关条目原始响应解析（结构非法抛 bgm_relations_invalid；排序权重同 animeko）
  private static parseRelations(raw: string): BgmRelatedSubject[] {
    let parsed: BgmRelatedSubjectRaw[];
    try {
      parsed = JSON.parse(raw) as BgmRelatedSubjectRaw[];
    } catch (e) {
      throw new Error('bgm_relations_invalid');
    }
    if (!Array.isArray(parsed)) {
      throw new Error('bgm_relations_invalid');
    }
    const items: BgmRelatedSubject[] = [];
    for (let i = 0; i < parsed.length; i++) {
      const entry: BgmRelatedSubjectRaw = parsed[i];
      if (typeof entry.id !== 'number' || entry.id <= 0) {
        continue;
      }
      const item: BgmRelatedSubject = new BgmRelatedSubject();
      item.id = entry.id;
      item.name = typeof entry.name === 'string' ? entry.name : '';
      item.nameCn = typeof entry.name_cn === 'string' ? entry.name_cn : '';
      item.relation = typeof entry.relation === 'string' ? entry.relation : '';
      item.cover = BangumiApi.imageUrl(entry.images);
      items.push(item);
    }
    items.sort((a: BgmRelatedSubject, b: BgmRelatedSubject): number =>
      BangumiApi.relationWeight(b.relation) - BangumiApi.relationWeight(a.relation));
    return items;
  }

  // 每日放送原始响应解析（结构非法抛 bgm_calendar_invalid）
  private static parseCalendar(raw: string): BgmCalendarItem[] {
    let parsed: BgmCalendarDayRaw[];
    try {
      parsed = JSON.parse(raw) as BgmCalendarDayRaw[];
    } catch (e) {
      throw new Error('bgm_calendar_invalid');
    }
    if (!Array.isArray(parsed)) {
      throw new Error('bgm_calendar_invalid');
    }
    const items: BgmCalendarItem[] = [];
    for (let i = 0; i < parsed.length; i++) {
      const day: BgmCalendarDayRaw = parsed[i];
      const jsDay: number = BangumiApi.jsDayOf(day.weekday);
      const dayItems: BgmCalendarItemRaw[] | undefined = day.items;
      if (dayItems === undefined || dayItems === null) {
        continue;
      }
      for (let j = 0; j < dayItems.length; j++) {
        const item: BgmCalendarItem | undefined = BangumiApi.parseCalendarItem(dayItems[j], jsDay);
        if (item !== undefined) {
          items.push(item);
        }
      }
    }
    return items;
  }

  private static parseCalendarItem(raw: BgmCalendarItemRaw, jsDay: number): BgmCalendarItem | undefined {
    if (typeof raw.id !== 'number' || raw.id <= 0) {
      return undefined;
    }
    const item: BgmCalendarItem = new BgmCalendarItem();
    item.id = raw.id;
    item.name = typeof raw.name === 'string' ? raw.name : '';
    item.nameCn = typeof raw.name_cn === 'string' ? raw.name_cn : '';
    item.airDate = typeof raw.air_date === 'string' ? raw.air_date : '';
    item.eps = typeof raw.eps === 'number' ? Math.floor(raw.eps) : 0;
    item.score = raw.rating !== undefined && typeof raw.rating.score === 'number' ? raw.rating.score : 0;
    item.cover = BangumiApi.imageUrl(raw.images);
    item.jsDay = jsDay;
    return item;
  }

  // 星期组 → JS 星期（0=周日..6=周六）：优先按本地化名称匹配，
  // 名称缺失时回退 weekday.id（旧接口约定 1=周一..7=周日）
  private static jsDayOf(weekday: BgmWeekdayRaw | undefined): number {
    if (weekday !== undefined && typeof weekday.cn === 'string' && weekday.cn !== '') {
      const day: number = BangumiApi.jsDayFromCn(weekday.cn);
      if (day >= 0) {
        return day;
      }
    }
    if (weekday !== undefined && typeof weekday.id === 'number' && weekday.id >= 1 && weekday.id <= 7) {
      return weekday.id % 7;
    }
    return 0;
  }

  private static jsDayFromCn(cn: string): number {
    if (cn.indexOf('日') >= 0) {
      return 0;
    }
    if (cn.indexOf('一') >= 0) {
      return 1;
    }
    if (cn.indexOf('二') >= 0) {
      return 2;
    }
    if (cn.indexOf('三') >= 0) {
      return 3;
    }
    if (cn.indexOf('四') >= 0) {
      return 4;
    }
    if (cn.indexOf('五') >= 0) {
      return 5;
    }
    if (cn.indexOf('六') >= 0) {
      return 6;
    }
    return -1;
  }

  // 图片地址归一：协议相对（//lain.bgm.tv/...）补 https 并按设置重写到图片镜像
  private static imageUrl(images: BgmImagesRaw | undefined): string {
    if (images === undefined || images === null) {
      return '';
    }
    const candidates: string[] = [];
    if (typeof images.large === 'string') {
      candidates.push(images.large);
    }
    if (typeof images.common === 'string') {
      candidates.push(images.common);
    }
    if (typeof images.medium === 'string') {
      candidates.push(images.medium);
    }
    for (let i = 0; i < candidates.length; i++) {
      const url: string = candidates[i];
      if (url !== '') {
        return Settings.rewriteBangumiImageUrl(url);
      }
    }
    return '';
  }
}
