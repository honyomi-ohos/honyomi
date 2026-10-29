// Bangumi（bgm.tv）公开数据 API：每日放送日历 + 条目详情
// 旧版 /calendar 返回七组「星期 + 条目列表」，v0 /v0/subjects/{id} 返回单条目详情；
// 图片地址可能为协议相对形式（//lain.bgm.tv/...），统一补 https 前缀
import { Http } from '../net/Http';

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
}

export class BangumiApi {
  private static readonly API_URL: string = 'https://api.bgm.tv';
  private static readonly UA: string = 'Honyomi/1.0 (HarmonyOS)';
  private static readonly CACHE_MS: number = 30 * 60 * 1000;
  // 日历内存缓存（整周日历一次拉取，30 分钟内复用）
  private static calendarCache: BgmCalendarItem[] = [];
  private static calendarFetchedAt: number = 0;
  private static calendarInflight: Promise<BgmCalendarItem[]> | undefined = undefined;
  // 条目详情缓存
  private static subjectCache: Map<number, BgmSubjectDetail> = new Map<number, BgmSubjectDetail>();

  // 每日放送整周日历；force=true 时强制刷新缓存
  static async getCalendar(force: boolean): Promise<BgmCalendarItem[]> {
    if (!force && BangumiApi.calendarCache.length > 0 &&
      Date.now() - BangumiApi.calendarFetchedAt < BangumiApi.CACHE_MS) {
      return BangumiApi.calendarCache;
    }
    if (BangumiApi.calendarInflight !== undefined) {
      return BangumiApi.calendarInflight;
    }
    const task: Promise<BgmCalendarItem[]> = BangumiApi.fetchCalendar().then(
      (items: BgmCalendarItem[]): BgmCalendarItem[] => {
        BangumiApi.calendarCache = items;
        BangumiApi.calendarFetchedAt = Date.now();
        BangumiApi.calendarInflight = undefined;
        return items;
      },
      (e: Object): BgmCalendarItem[] => {
        BangumiApi.calendarInflight = undefined;
        throw new Error(e instanceof Error ? e.message : String(e));
      });
    BangumiApi.calendarInflight = task;
    return task;
  }

  // 条目详情（带内存缓存）
  static async getSubject(id: number): Promise<BgmSubjectDetail> {
    const cached: BgmSubjectDetail | undefined = BangumiApi.subjectCache.get(id);
    if (cached !== undefined) {
      return cached;
    }
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = BangumiApi.UA;
    const raw: string = await Http.get(`${BangumiApi.API_URL}/v0/subjects/${id}`, headers);
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
    detail.cover = BangumiApi.imageUrl(parsed.images);
    BangumiApi.subjectCache.set(id, detail);
    return detail;
  }

  // ---- 内部实现 ----

  private static async fetchCalendar(): Promise<BgmCalendarItem[]> {
    const headers: Record<string, string> = Http.defaultHeaders();
    headers['User-Agent'] = BangumiApi.UA;
    const raw: string = await Http.get(`${BangumiApi.API_URL}/calendar`, headers);
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

  // 图片地址归一：协议相对（//lain.bgm.tv/...）补 https，空串保留
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
        return url.indexOf('//') === 0 ? `https:${url}` : url;
      }
    }
    return '';
  }
}
