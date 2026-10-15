// MangaBaka 追踪器（syncId=11）：OAuth code + S256 PKCE + state；评分 0-100 步进制
import { TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { Tracker, TrackHttp, OAuthToken, TrackDate, Pkce } from './Tracker';
import { Http } from '../../net/Http';

const MB_CLIENT_ID = 'zEZYMHXLWsLsafgbvJHXqzGvqQNOdkpo';
const MB_BASE_URL = 'https://mangabaka.org';
const MB_API_BASE_URL = 'https://api.mangabaka.org';
const MB_LIBRARY_API_URL = `${MB_API_BASE_URL}/v1/my/library`;
const MB_OAUTH_URL = `${MB_BASE_URL}/auth/oauth2`;
const MB_SCOPES = 'library.read library.write offline_access openid';
const MB_REDIRECT_URI = 'mihon://mangabaka-auth';
// 标题语言优先级（对齐 MangaBaka titles v2 规则）
const MB_TITLE_LANGS: string[] = ['en', 'ja-Latn', 'ja', 'ko-Latn', 'ko', 'zh-Latn', 'zh'];

// ---- 原始 JSON 模型 ----
interface MbTokenRaw {
  access_token?: string;
  refresh_token?: string;
  expires_at?: number;
}

interface MbProfileRaw {
  id?: string;
  rating_steps?: number;
  nickname?: string;
  preferred_username?: string;
}

interface MbProfileRespRaw {
  data?: MbProfileRaw;
}

interface MbScaledCoverRaw {
  x1?: string;
}

interface MbCoverRaw {
  x250?: MbScaledCoverRaw;
}

interface MbPublishRaw {
  start_date?: string;
}

interface MbTitleRaw {
  language?: string;
  traits?: string[];
  title?: string;
  is_primary?: boolean;
}

interface MbItemRaw {
  id?: number;
  cover?: MbCoverRaw;
  authors?: string[];
  artists?: string[];
  description?: string;
  published?: MbPublishRaw;
  status?: string;
  type?: string;
  rating?: number;
  titles?: MbTitleRaw[];
}

interface MbItemRespRaw {
  data?: MbItemRaw;
}

interface MbSearchRespRaw {
  data?: MbItemRaw[];
}

interface MbListEntryRaw {
  state?: string;
  start_date?: string;
  finish_date?: string;
  is_private?: boolean;
  progress_chapter?: number;
  rating?: number;
}

interface MbListRespRaw {
  data?: MbListEntryRaw;
}

export class MangaBakaTracker extends Tracker {
  static readonly READING: number = 1;
  static readonly COMPLETED: number = 2;
  static readonly PAUSED: number = 3;
  static readonly DROPPED: number = 4;
  static readonly PLAN_TO_READ: number = 5;
  static readonly REREADING: number = 6;
  static readonly CONSIDERING: number = 7;

  private codeVerifier: string = '';

  constructor() {
    super(11, 'MangaBaka', '#F97316');
    this.supportsReadingDates = true;
    this.supportsPrivateTracking = true;
  }

  getStatusList(): number[] {
    return [MangaBakaTracker.READING, MangaBakaTracker.COMPLETED, MangaBakaTracker.PAUSED,
      MangaBakaTracker.DROPPED, MangaBakaTracker.PLAN_TO_READ, MangaBakaTracker.REREADING,
      MangaBakaTracker.CONSIDERING];
  }

  getStatusLabel(status: number): ResourceStr {
    switch (status) {
      case MangaBakaTracker.READING:
        return $r('app.string.track_reading');
      case MangaBakaTracker.COMPLETED:
        return $r('app.string.track_completed');
      case MangaBakaTracker.PAUSED:
        return $r('app.string.track_paused');
      case MangaBakaTracker.DROPPED:
        return $r('app.string.track_dropped');
      case MangaBakaTracker.PLAN_TO_READ:
        return $r('app.string.track_plan_to_read');
      case MangaBakaTracker.REREADING:
        return $r('app.string.track_repeating');
      case MangaBakaTracker.CONSIDERING:
        return $r('app.string.track_considering');
      default:
        return $r('app.string.track_unknown_status');
    }
  }

  getReadingStatus(): number {
    return MangaBakaTracker.READING;
  }

  getRereadingStatus(): number {
    return MangaBakaTracker.REREADING;
  }

  getCompletionStatus(): number {
    return MangaBakaTracker.COMPLETED;
  }

  // 评分制仅为步长（0-100 步进），分数恒为 0-100
  getScoreList(): string[] {
    const step = MangaBakaTracker.scoreStep();
    const list: string[] = [];
    for (let s = 0; s <= 100; s += step) {
      list.push(`${s}`);
    }
    return list;
  }

  indexToScore(index: number): number {
    return index * MangaBakaTracker.scoreStep();
  }

  scoreIndex(score: number): number {
    const step = MangaBakaTracker.scoreStep();
    const maxIndex = Math.floor(100 / step);
    const idx = Math.round(score / step);
    if (idx < 0) {
      return 0;
    }
    return idx > maxIndex ? maxIndex : idx;
  }

  displayScore(track: TrackRecord): string {
    return `${Math.round(track.score)}`;
  }

  async getAuthUrl(): Promise<string> {
    const pair = await Pkce.generate();
    this.codeVerifier = pair.verifier;
    return `${MB_OAUTH_URL}/authorize?client_id=${MB_CLIENT_ID}` +
      `&code_challenge=${pair.challenge}&code_challenge_method=S256&response_type=code` +
      `&scope=${encodeURIComponent(MB_SCOPES)}&redirect_uri=${encodeURIComponent(MB_REDIRECT_URI)}` +
      `&state=${encodeURIComponent(Pkce.verifier())}`;
  }

  async loginWithCode(code: string): Promise<void> {
    try {
      const form: Record<string, string> = {
        'client_id': MB_CLIENT_ID,
        'code': code,
        'code_verifier': this.codeVerifier,
        'code_challenge_method': 'S256',
        'grant_type': 'authorization_code',
        'redirect_uri': MB_REDIRECT_URI,
        'scope': MB_SCOPES,
      };
      const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
      const resp = await TrackHttp.send('POST', `${MB_OAUTH_URL}/token`, headers, TrackHttp.formEncode(form));
      const token = MangaBakaTracker.parseToken(resp);
      this.saveToken(token);
      const profile = await this.getCurrentUser();
      const stepName = MangaBakaTracker.stepNameOf(profile.rating_steps ?? 0);
      Settings.setMangabakaScoreType(stepName);
      const display = profile.nickname ?? profile.preferred_username ?? profile.id ?? '';
      Settings.setTrackDisplay(this.syncId, display);
      this.saveCredentials('user', token.accessToken);
    } catch (e) {
      this.logout();
      throw e as Error;
    }
  }

  async loginWithCredentials(_username: string, _password: string): Promise<void> {
    throw new Error('MangaBaka only supports OAuth login');
  }

  async search(query: string): Promise<TrackSearchResult[]> {
    if (query.startsWith('id:')) {
      const id = parseInt(query.substring(3).trim(), 10);
      if (!isNaN(id)) {
        const item = await this.getMangaDetails(id);
        return item !== undefined ? [item] : [];
      }
    }
    const url = `${MB_API_BASE_URL}/v1/series/search?q=${encodeURIComponent(query)}&type_not=novel`;
    const resp = await TrackHttp.send('GET', url, undefined, '');
    const raw = JSON.parse(resp) as MbSearchRespRaw;
    const results: TrackSearchResult[] = [];
    for (const item of raw.data ?? []) {
      results.push(this.itemToSearch(item));
    }
    return results;
  }

  async bind(track: TrackRecord, hasReadChapters: boolean): Promise<TrackRecord> {
    const remote = await this.findLibManga(track);
    if (remote !== undefined) {
      this.copyPersonalFrom(track, remote, false);
      track.title = remote.title;
      track.remoteId = remote.remoteId;
      if (track.status !== MangaBakaTracker.COMPLETED) {
        const isRereading = track.status === MangaBakaTracker.REREADING;
        track.status = !isRereading && hasReadChapters ? MangaBakaTracker.READING : track.status;
      }
      return await this.update(track, false);
    }
    track.status = hasReadChapters ? MangaBakaTracker.READING : MangaBakaTracker.PLAN_TO_READ;
    track.score = 0;
    return await this.addLibManga(track);
  }

  async update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    if (track.status !== MangaBakaTracker.COMPLETED && didReadChapter) {
      if (track.totalChapters > 0 && Math.round(track.lastChapterRead) === track.totalChapters) {
        track.status = MangaBakaTracker.COMPLETED;
        track.finishDate = Date.now();
      } else if (track.status !== MangaBakaTracker.REREADING) {
        track.status = MangaBakaTracker.READING;
        if (Math.round(track.lastChapterRead) === 1) {
          track.startDate = Date.now();
        }
      }
    }
    return await this.updateLibManga(track);
  }

  async refresh(track: TrackRecord): Promise<TrackRecord> {
    const remote = await this.findLibManga(track);
    if (remote === undefined) {
      throw new Error('MangaBaka: could not find manga');
    }
    this.copyPersonalFrom(track, remote);
    track.remoteId = remote.remoteId;
    track.title = remote.title;
    return track;
  }

  async deleteRemote(track: TrackRecord): Promise<void> {
    await TrackHttp.send('DELETE', `${MB_LIBRARY_API_URL}/${track.remoteId}`, await this.authHeaders(), '');
  }

  // ---- 内部实现 ----

  private async authHeaders(): Promise<Record<string, string>> {
    const token = await this.ensureToken((t: OAuthToken) => this.refreshToken(t));
    return TrackHttp.bearer(token.accessToken);
  }

  private async refreshToken(token: OAuthToken): Promise<OAuthToken> {
    const form: Record<string, string> = {
      'grant_type': 'refresh_token',
      'client_id': MB_CLIENT_ID,
      'refresh_token': token.refreshToken,
      'redirect_uri': MB_REDIRECT_URI,
    };
    const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    const resp = await TrackHttp.send('POST', `${MB_OAUTH_URL}/token`, headers, TrackHttp.formEncode(form));
    return MangaBakaTracker.parseToken(resp);
  }

  private static parseToken(resp: string): OAuthToken {
    const raw = JSON.parse(resp) as MbTokenRaw;
    if (typeof raw.access_token !== 'string' || raw.access_token === '') {
      throw new Error('MangaBaka: token response invalid');
    }
    const t = new OAuthToken();
    t.accessToken = raw.access_token;
    t.refreshToken = typeof raw.refresh_token === 'string' ? raw.refresh_token : '';
    t.createdAt = TrackDate.nowSec();
    t.expiresIn = 0;
    t.expiresAt = typeof raw.expires_at === 'number' ? raw.expires_at : 0;
    return t;
  }

  private async getCurrentUser(): Promise<MbProfileRaw> {
    const resp = await TrackHttp.send('GET', `${MB_API_BASE_URL}/v1/my/profile`, await this.authHeaders(), '');
    const raw = JSON.parse(resp) as MbProfileRespRaw;
    if (raw.data === undefined || raw.data === null) {
      throw new Error('MangaBaka: failed to get current user');
    }
    return raw.data;
  }

  private async getMangaDetails(id: number): Promise<TrackSearchResult | undefined> {
    const resp = await TrackHttp.sendOptional('GET', `${MB_API_BASE_URL}/v1/series/${id}`,
      await this.authHeaders(), '');
    if (resp === undefined) {
      return undefined;
    }
    const raw = JSON.parse(resp) as MbItemRespRaw;
    if (raw.data === undefined || raw.data === null) {
      return undefined;
    }
    return this.itemToSearch(raw.data);
  }

  private async addLibManga(track: TrackRecord): Promise<TrackRecord> {
    const apiStatus = MangaBakaTracker.toApiStatus(track.status);
    let body = `{"is_private":${track.isPrivate},"state":"${apiStatus}"`;
    if (track.lastChapterRead > 0) {
      body += `,"progress_chapter":${track.lastChapterRead}`;
    }
    if (track.score > 0) {
      body += `,"rating":${MangaBakaTracker.clampScore(track.score)}`;
    }
    if (track.startDate > 0) {
      body += `,"start_date":"${TrackDate.toIsoDate(track.startDate)}"`;
    }
    if (track.finishDate > 0) {
      body += `,"finish_date":"${TrackDate.toIsoDate(track.finishDate)}"`;
    }
    body += '}';
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    await TrackHttp.send('POST', `${MB_LIBRARY_API_URL}/${track.remoteId}`, headers, body);
    return track;
  }

  private async updateLibManga(track: TrackRecord): Promise<TrackRecord> {
    const apiStatus = MangaBakaTracker.toApiStatus(track.status);
    const progress = track.lastChapterRead > 0 ? `${track.lastChapterRead}` : 'null';
    const rating = track.score > 0 ? `${MangaBakaTracker.clampScore(track.score)}` : 'null';
    const startDate = track.startDate > 0 ? `"${TrackDate.toIsoDate(track.startDate)}"` : 'null';
    const finishDate = track.finishDate > 0 ? `"${TrackDate.toIsoDate(track.finishDate)}"` : 'null';
    const body = `{"state":"${apiStatus}","is_private":${track.isPrivate}` +
      `,"progress_chapter":${progress},"rating":${rating}` +
      `,"start_date":${startDate},"finish_date":${finishDate}}`;
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    await TrackHttp.send('PUT', `${MB_LIBRARY_API_URL}/${track.remoteId}`, headers, body);
    return track;
  }

  private async findLibManga(track: TrackRecord): Promise<TrackRecord | undefined> {
    const headers = await this.authHeaders();
    const resp = await Http.requestRaw('GET', `${MB_LIBRARY_API_URL}/${track.remoteId}`, '', headers);
    if (resp.code === 404) {
      return undefined;
    }
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`HTTP ${resp.code}: ${resp.body.substring(0, 200)}`);
    }
    const userData = JSON.parse(resp.body) as MbListRespRaw;
    const entry = userData.data;
    if (entry === undefined || entry === null) {
      return undefined;
    }
    const addResp = await TrackHttp.send('GET', `${MB_API_BASE_URL}/v1/series/${track.remoteId}`, headers, '');
    const additional = JSON.parse(addResp) as MbItemRespRaw;
    const remote = new TrackRecord();
    remote.remoteId = track.remoteId;
    remote.title = MangaBakaTracker.chooseBestTitle(additional.data);
    remote.status = MangaBakaTracker.toLocalStatus(entry.state ?? '');
    remote.score = entry.rating ?? 0;
    remote.startDate = MangaBakaTracker.parseIsoDateTime(entry.start_date);
    remote.finishDate = MangaBakaTracker.parseIsoDateTime(entry.finish_date);
    remote.lastChapterRead = entry.progress_chapter ?? 0;
    remote.isPrivate = entry.is_private === true;
    return remote;
  }

  private itemToSearch(item: MbItemRaw): TrackSearchResult {
    const r = new TrackSearchResult();
    r.syncId = this.syncId;
    r.remoteId = item.id ?? 0;
    r.title = MangaBakaTracker.chooseBestTitle(item);
    r.summary = (item.description ?? '').trim();
    r.score = item.rating !== undefined && item.rating !== null ? Math.round(item.rating * 100) / 100 : -1;
    r.coverUrl = item.cover?.x250?.x1 ?? '';
    r.trackingUrl = `${MB_BASE_URL}/${r.remoteId}`;
    r.startDate = item.published?.start_date ?? '';
    r.publishingStatus = item.status ?? '';
    r.publishingType = MangaBakaTracker.capitalize(item.type ?? '');
    r.authors = item.authors ?? [];
    r.artists = item.artists ?? [];
    return r;
  }

  // 标题择优：按语言优先级取最小权重项（is_primary > official > native > 其他）
  private static chooseBestTitle(item: MbItemRaw | undefined): string {
    const titles = (item !== undefined && item !== null) ? (item.titles ?? []) : [];
    for (const lang of MB_TITLE_LANGS) {
      let best: MbTitleRaw | undefined = undefined;
      let bestRank = 4;
      for (const t of titles) {
        if (t.language !== lang) {
          continue;
        }
        const traits = t.traits ?? [];
        let rank = 3;
        if (t.is_primary === true) {
          rank = 0;
        } else if (traits.includes('official')) {
          rank = 1;
        } else if (traits.includes('native')) {
          rank = 2;
        }
        if (rank < bestRank) {
          bestRank = rank;
          best = t;
        }
      }
      if (best !== undefined && typeof best.title === 'string' && best.title !== '') {
        return best.title;
      }
    }
    const first = titles.length > 0 ? titles[0] : undefined;
    if (first !== undefined && typeof first.title === 'string' && first.title !== '') {
      return first.title;
    }
    const id = item !== undefined && item !== null && typeof item.id === 'number' ? item.id : 0;
    return `ID: ${id}`;
  }

  // v1 API 返回带 T 时间成分的 ISO 8601 字符串，取日期部分按本地零点解析
  private static parseIsoDateTime(iso: string | undefined): number {
    if (typeof iso !== 'string' || iso === '') {
      return 0;
    }
    return TrackDate.parseIsoDate(iso.split('T')[0]);
  }

  private static capitalize(s: string): string {
    if (s === '') {
      return '';
    }
    return s.charAt(0).toUpperCase() + s.substring(1);
  }

  private static clampScore(score: number): number {
    const v = Math.round(score);
    if (v < 0) {
      return 0;
    }
    return v > 100 ? 100 : v;
  }

  private static scoreStep(): number {
    switch (Settings.getMangabakaScoreType()) {
      case 'STEP_1':
        return 1;
      case 'STEP_5':
        return 5;
      case 'STEP_20':
        return 20;
      case 'STEP_25':
        return 25;
      case 'STEP_10':
      default:
        return 10;
    }
  }

  private static stepNameOf(steps: number): string {
    switch (steps) {
      case 1:
        return 'STEP_1';
      case 5:
        return 'STEP_5';
      case 10:
        return 'STEP_10';
      case 20:
        return 'STEP_20';
      case 25:
        return 'STEP_25';
      default:
        throw new Error(`MangaBaka: unknown score step size ${steps}`);
    }
  }

  private static toApiStatus(status: number): string {
    switch (status) {
      case MangaBakaTracker.READING:
        return 'reading';
      case MangaBakaTracker.COMPLETED:
        return 'completed';
      case MangaBakaTracker.PAUSED:
        return 'paused';
      case MangaBakaTracker.DROPPED:
        return 'dropped';
      case MangaBakaTracker.PLAN_TO_READ:
        return 'plan_to_read';
      case MangaBakaTracker.REREADING:
        return 'rereading';
      case MangaBakaTracker.CONSIDERING:
        return 'considering';
      default:
        throw new Error(`MangaBaka: unknown status ${status}`);
    }
  }

  private static toLocalStatus(state: string): number {
    switch (state) {
      case 'considering':
        return MangaBakaTracker.CONSIDERING;
      case 'completed':
        return MangaBakaTracker.COMPLETED;
      case 'dropped':
        return MangaBakaTracker.DROPPED;
      case 'paused':
        return MangaBakaTracker.PAUSED;
      case 'plan_to_read':
        return MangaBakaTracker.PLAN_TO_READ;
      case 'reading':
        return MangaBakaTracker.READING;
      case 'rereading':
        return MangaBakaTracker.REREADING;
      default:
        throw new Error(`MangaBaka: unknown state ${state}`);
    }
  }
}
