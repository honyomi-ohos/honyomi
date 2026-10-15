// MangaUpdates 追踪器（syncId=7）：用户名密码登录（session token）
import { TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { Tracker, TrackHttp } from './Tracker';

const MU_BASE_URL = 'https://api.mangaupdates.com';
const MU_USER_AGENT = 'Mihon-Harmony/1.0 (HarmonyOS)';

// ---- 原始 JSON 模型 ----
interface MuContextRaw {
  session_token?: string;
  uid?: number;
}

interface MuLoginRaw {
  context?: MuContextRaw;
}

interface MuSeriesRaw {
  id?: number;
  title?: string;
}

interface MuStatusRaw {
  volume?: number;
  chapter?: number;
}

interface MuListItemRaw {
  series?: MuSeriesRaw;
  list_id?: number;
  status?: MuStatusRaw;
  priority?: number;
}

interface MuRatingRaw {
  rating?: number;
}

interface MuImageUrlRaw {
  original?: string;
  thumb?: string;
}

interface MuImageRaw {
  url?: MuImageUrlRaw;
}

interface MuAuthorRaw {
  name?: string;
  type?: string;
}

interface MuRecordRaw {
  series_id?: number;
  title?: string;
  url?: string;
  description?: string;
  image?: MuImageRaw;
  type?: string;
  year?: string;
  bayesian_rating?: number;
  rating_votes?: number;
  latest_chapter?: number;
  authors?: MuAuthorRaw[];
}

interface MuSearchItemRaw {
  record?: MuRecordRaw;
}

interface MuSearchRaw {
  results?: MuSearchItemRaw[];
}

interface MuProfileRaw {
  username: string;
}

export class MangaUpdatesTracker extends Tracker {
  static readonly READING_LIST: number = 0;
  static readonly WISH_LIST: number = 1;
  static readonly COMPLETE_LIST: number = 2;
  static readonly UNFINISHED_LIST: number = 3;
  static readonly ON_HOLD_LIST: number = 4;

  constructor() {
    super(7, 'MangaUpdates', '#7CB342');
  }

  getStatusList(): number[] {
    return [MangaUpdatesTracker.READING_LIST, MangaUpdatesTracker.COMPLETE_LIST,
      MangaUpdatesTracker.ON_HOLD_LIST, MangaUpdatesTracker.UNFINISHED_LIST, MangaUpdatesTracker.WISH_LIST];
  }

  getStatusLabel(status: number): ResourceStr {
    switch (status) {
      case MangaUpdatesTracker.READING_LIST:
        return $r('app.string.track_reading_list');
      case MangaUpdatesTracker.WISH_LIST:
        return $r('app.string.track_wish_list');
      case MangaUpdatesTracker.COMPLETE_LIST:
        return $r('app.string.track_complete_list');
      case MangaUpdatesTracker.ON_HOLD_LIST:
        return $r('app.string.track_on_hold_list');
      case MangaUpdatesTracker.UNFINISHED_LIST:
        return $r('app.string.track_unfinished_list');
      default:
        return $r('app.string.track_unknown_status');
    }
  }

  getReadingStatus(): number {
    return MangaUpdatesTracker.READING_LIST;
  }

  getRereadingStatus(): number {
    return -1;
  }

  getCompletionStatus(): number {
    return MangaUpdatesTracker.COMPLETE_LIST;
  }

  getScoreList(): string[] {
    const list: string[] = ['-'];
    for (let decimal = 1; decimal <= 9; decimal++) {
      for (let fraction = 0; fraction <= 9; fraction++) {
        list.push(`${decimal}.${fraction}`);
      }
    }
    list.push('10.0');
    return list;
  }

  indexToScore(index: number): number {
    if (index === 0) {
      return 0;
    }
    const list = this.getScoreList();
    return index < list.length ? parseFloat(list[index]) : 0;
  }

  scoreIndex(score: number): number {
    if (score <= 0) {
      return 0;
    }
    const index = Math.round(score * 10) - 9;
    return index > 91 ? 91 : index;
  }

  displayScore(track: TrackRecord): string {
    return track.score.toFixed(1);
  }

  async getAuthUrl(): Promise<string> {
    return '';
  }

  async loginWithCode(_code: string): Promise<void> {
    throw new Error('MangaUpdates only supports username/password login');
  }

  async loginWithCredentials(username: string, password: string): Promise<void> {
    const body = `{"username":${JSON.stringify(username)},"password":${JSON.stringify(password)}}`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    const resp = await TrackHttp.send('PUT', `${MU_BASE_URL}/v1/account/login`, headers, body);
    const raw = JSON.parse(resp) as MuLoginRaw;
    const context = raw.context;
    if (context === undefined || typeof context.session_token !== 'string' || context.session_token === '') {
      throw new Error('MangaUpdates: login failed (check username/password)');
    }
    this.saveCredentials(`${context.uid ?? 0}`, context.session_token);
    // 获取展示用户名
    const authHeaders = await this.authHeaders();
    const profileResp = await TrackHttp.send('GET', `${MU_BASE_URL}/v1/account/profile`, authHeaders, '');
    const profile = JSON.parse(profileResp) as MuProfileRaw;
    Settings.setTrackDisplay(this.syncId, profile.username ?? username);
  }

  async search(query: string): Promise<TrackSearchResult[]> {
    if (query.startsWith('id:')) {
      const stringId = query.substring(3).trim();
      let searchId = parseInt(stringId, 10);
      if (isNaN(searchId)) {
        searchId = parseInt(stringId, 36);
      }
      if (!isNaN(searchId)) {
        const details = await this.getSeriesDetails(searchId);
        return details !== undefined ? [details] : [];
      }
      return [];
    }
    const body = `{"search":${JSON.stringify(query)},"filter_types":["drama cd","novel"]}`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    const resp = await TrackHttp.send('POST', `${MU_BASE_URL}/v1/series/search`, headers, body);
    const raw = JSON.parse(resp) as MuSearchRaw;
    const results: TrackSearchResult[] = [];
    for (const item of raw.results ?? []) {
      if (item.record !== undefined) {
        results.push(this.recordToSearch(item.record));
      }
    }
    return results;
  }

  async bind(track: TrackRecord, hasReadChapters: boolean): Promise<TrackRecord> {
    try {
      await this.getSeriesListItem(track);
      return track;
    } catch (_e) {
      track.score = 0;
      await this.addSeriesToList(track, hasReadChapters);
      return track;
    }
  }

  async update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    if (track.status !== MangaUpdatesTracker.COMPLETE_LIST && didReadChapter) {
      track.status = MangaUpdatesTracker.READING_LIST;
    }
    await this.updateSeriesListItem(track);
    return track;
  }

  async refresh(track: TrackRecord): Promise<TrackRecord> {
    await this.getSeriesListItem(track);
    return track;
  }

  async deleteRemote(track: TrackRecord): Promise<void> {
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    await TrackHttp.send('POST', `${MU_BASE_URL}/v1/lists/series/delete`, headers, `[${track.remoteId}]`);
  }

  // ---- 内部实现 ----

  private async authHeaders(): Promise<Record<string, string>> {
    const token = this.getPassword();
    if (token === '') {
      throw new Error('MangaUpdates: not logged in');
    }
    const headers = TrackHttp.bearer(token);
    headers['User-Agent'] = MU_USER_AGENT;
    return headers;
  }

  // 读取列表条目 + 评分：不在列表时抛错
  private async getSeriesListItem(track: TrackRecord): Promise<void> {
    const resp = await TrackHttp.send('GET', `${MU_BASE_URL}/v1/lists/series/${track.remoteId}`,
      await this.authHeaders(), '');
    const item = JSON.parse(resp) as MuListItemRaw;
    track.status = item.list_id ?? MangaUpdatesTracker.READING_LIST;
    track.lastChapterRead = item.status?.chapter ?? 0;
    try {
      const ratingResp = await TrackHttp.send('GET', `${MU_BASE_URL}/v1/series/${track.remoteId}/rating`,
        await this.authHeaders(), '');
      track.score = (JSON.parse(ratingResp) as MuRatingRaw).rating ?? 0;
    } catch (_e) {
      track.score = 0;
    }
  }

  private async addSeriesToList(track: TrackRecord, hasReadChapters: boolean): Promise<void> {
    const status = hasReadChapters ? MangaUpdatesTracker.READING_LIST : MangaUpdatesTracker.WISH_LIST;
    const body = `[{"series":{"id":${track.remoteId}},"list_id":${status}}]`;
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    await TrackHttp.send('POST', `${MU_BASE_URL}/v1/lists/series`, headers, body);
    track.status = status;
    track.lastChapterRead = 1;
  }

  private async updateSeriesListItem(track: TrackRecord): Promise<void> {
    const body = `[{"series":{"id":${track.remoteId}},"list_id":${track.status}` +
      `,"status":{"chapter":${Math.floor(track.lastChapterRead)}}}]`;
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    await TrackHttp.send('POST', `${MU_BASE_URL}/v1/lists/series/update`, headers, body);
    await this.updateSeriesRating(track);
  }

  private async updateSeriesRating(track: TrackRecord): Promise<void> {
    if (track.score < 0) {
      return;
    }
    if (track.score !== 0) {
      const body = `{"rating":${track.score}}`;
      const headers = await this.authHeaders();
      headers['Content-Type'] = 'application/json';
      await TrackHttp.send('PUT', `${MU_BASE_URL}/v1/series/${track.remoteId}/rating`, headers, body);
    } else {
      await TrackHttp.send('DELETE', `${MU_BASE_URL}/v1/series/${track.remoteId}/rating`,
        await this.authHeaders(), '');
    }
  }

  private async getSeriesDetails(id: number): Promise<TrackSearchResult | undefined> {
    const headers: Record<string, string> = { 'Accept': 'application/json' };
    const resp = await TrackHttp.sendOptional('GET', `${MU_BASE_URL}/v1/series/${id}`, headers, '');
    if (resp === undefined) {
      return undefined;
    }
    return this.recordToSearch(JSON.parse(resp) as MuRecordRaw);
  }

  private recordToSearch(record: MuRecordRaw): TrackSearchResult {
    const r = new TrackSearchResult();
    r.syncId = this.syncId;
    r.remoteId = record.series_id ?? 0;
    r.title = record.title ?? '';
    r.totalChapters = 0;
    r.coverUrl = record.image?.url?.original ?? '';
    r.summary = record.description ?? '';
    r.trackingUrl = record.url ?? '';
    r.publishingStatus = '';
    r.publishingType = record.type ?? '';
    r.startDate = record.year ?? '';
    r.score = (record.bayesian_rating ?? 0) > 0 ? record.bayesian_rating as number : -1;
    for (const author of record.authors ?? []) {
      const name = author.name ?? '';
      if (name === '') {
        continue;
      }
      if (author.type === 'Author') {
        r.authors.push(name);
      }
      if (author.type === 'Artist') {
        r.artists.push(name);
      }
    }
    return r;
  }
}
