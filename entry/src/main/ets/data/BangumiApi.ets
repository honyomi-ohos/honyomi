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
  rating?: BgmRatingRaw;
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
  score: number = 0;
  // infobox 作者/原作（作者校验用；解析不到为空串）
  author: string = '';
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
    detail.score = parsed.rating !== undefined && typeof parsed.rating.score === 'number' ?
      parsed.rating.score : 0;
    detail.author = BangumiApi.infoboxAuthor(parsed.infobox);
    detail.cover = BangumiApi.imageUrl(parsed.images);
    return detail;
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
