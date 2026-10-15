// Bangumi 追踪器（syncId=5）：OAuth code 授权 + bgm.tv v0 API
import { TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { OAuthToken, TrackDate, Tracker, TrackHttp } from './Tracker';
import { Http } from '../../net/Http';

const BGM_API_URL = 'https://api.bgm.tv';
const BGM_OAUTH_URL = 'https://bgm.tv/oauth/access_token';
const BGM_LOGIN_URL = 'https://bgm.tv/oauth/authorize';
const BGM_CLIENT_ID = 'bgm291665acbd06a4c28';
const BGM_CLIENT_SECRET = '43e5ce36b207de16e5d3cfd3e79118db';
const BGM_REDIRECT_URL = 'mihon://bangumi-auth';
const BGM_USER_AGENT = 'mihon-harmony/1.0 (HarmonyOS) (https://github.com/mihonapp/mihon)';
const BGM_SUBJECT_URL_PREFIX = 'https://bangumi.tv/subject/';

// ---- 原始 JSON 模型 ----
interface BgmSlimSubjectRaw {
  volumes?: number;
  eps?: number;
}

interface BgmCollectionRaw {
  rate?: number;
  type?: number;
  ep_status?: number;
  vol_status?: number;
  private?: boolean;
  subject?: BgmSlimSubjectRaw;
}

interface BgmImagesRaw {
  common?: string;
}

interface BgmRatingRaw {
  score?: number;
}

interface BgmSubjectRaw {
  id: number;
  name: string;
  name_cn: string;
  summary?: string;
  date?: string;
  images?: BgmImagesRaw;
  volumes?: number;
  eps?: number;
  rating?: BgmRatingRaw;
  platform?: string;
}

interface BgmSearchResultRaw {
  data?: BgmSubjectRaw[];
}

interface BgmUserRaw {
  username: string;
  nickname?: string;
}

interface BgmTokenRaw {
  access_token?: string;
  refresh_token?: string;
  created_at?: number;
  expires_in?: number;
}

export class BangumiTracker extends Tracker {
  static readonly PLAN_TO_READ: number = 1;
  static readonly COMPLETED: number = 2;
  static readonly READING: number = 3;
  static readonly ON_HOLD: number = 4;
  static readonly DROPPED: number = 5;

  constructor() {
    super(5, 'Bangumi', '#F09199');
    this.supportsPrivateTracking = true;
  }

  private static parseToken(resp: string): OAuthToken {
    const raw = JSON.parse(resp) as BgmTokenRaw;
    if (typeof raw.access_token !== 'string' || raw.access_token === '') {
      throw new Error('Bangumi: token response invalid');
    }
    const t = new OAuthToken();
    t.accessToken = raw.access_token;
    t.refreshToken = typeof raw.refresh_token === 'string' ? raw.refresh_token : '';
    t.createdAt = typeof raw.created_at === 'number' ? raw.created_at : TrackDate.nowSec();
    t.expiresIn = typeof raw.expires_in === 'number' ? raw.expires_in : 0;
    return t;
  }

  private static fromApiType(type: number): number {
    switch (type) {
      case 1:
        return BangumiTracker.PLAN_TO_READ;
      case 2:
        return BangumiTracker.COMPLETED;
      case 3:
        return BangumiTracker.READING;
      case 4:
        return BangumiTracker.ON_HOLD;
      case 5:
        return BangumiTracker.DROPPED;
      default:
        throw new Error(`Unknown status: ${type}`);
    }
  }

  private static clampScore(score: number): number {
    const v = Math.round(score);
    return v < 0 ? 0 : (v > 10 ? 10 : v);
  }

  getStatusList(): number[] {
    return [BangumiTracker.READING, BangumiTracker.COMPLETED, BangumiTracker.ON_HOLD,
      BangumiTracker.DROPPED, BangumiTracker.PLAN_TO_READ];
  }

  getStatusLabel(status: number): ResourceStr {
    switch (status) {
      case BangumiTracker.READING:
        return $r('app.string.track_reading');
      case BangumiTracker.COMPLETED:
        return $r('app.string.track_completed');
      case BangumiTracker.ON_HOLD:
        return $r('app.string.track_on_hold');
      case BangumiTracker.DROPPED:
        return $r('app.string.track_dropped');
      case BangumiTracker.PLAN_TO_READ:
        return $r('app.string.track_plan_to_read');
      default:
        return $r('app.string.track_unknown_status');
    }
  }

  getReadingStatus(): number {
    return BangumiTracker.READING;
  }

  getRereadingStatus(): number {
    return -1;
  }

  getCompletionStatus(): number {
    return BangumiTracker.COMPLETED;
  }

  getScoreList(): string[] {
    const list: string[] = [];
    for (let i = 0; i <= 10; i++) {
      list.push(`${i}`);
    }
    return list;
  }

  indexToScore(index: number): number {
    return index;
  }

  scoreIndex(score: number): number {
    return Math.round(score);
  }

  displayScore(track: TrackRecord): string {
    return `${Math.round(track.score)}`;
  }

  async getAuthUrl(): Promise<string> {
    return `${BGM_LOGIN_URL}?client_id=${BGM_CLIENT_ID}&response_type=code` +
      `&redirect_uri=${encodeURIComponent(BGM_REDIRECT_URL)}`;
  }

  async loginWithCode(code: string): Promise<void> {
    const form: Record<string, string> = {
      'grant_type': 'authorization_code',
      'client_id': BGM_CLIENT_ID,
      'client_secret': BGM_CLIENT_SECRET,
      'code': code,
      'redirect_uri': BGM_REDIRECT_URL,
    };
    const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    const resp = await TrackHttp.send('POST', BGM_OAUTH_URL, headers, TrackHttp.formEncode(form));
    const token = BangumiTracker.parseToken(resp);
    this.saveToken(token);
    const user = await this.getCurrentUser();
    const nickname = (user.nickname ?? '').trim();
    const display = nickname !== '' ? nickname : user.username;
    this.saveCredentials(user.username, token.accessToken);
    Settings.setTrackDisplay(this.syncId, display);
  }

  async loginWithCredentials(_username: string, _password: string): Promise<void> {
    throw new Error('Bangumi only supports OAuth login');
  }

  async search(query: string): Promise<TrackSearchResult[]> {
    if (query.startsWith('id:')) {
      const id = parseInt(query.substring(3).trim(), 10);
      if (!isNaN(id)) {
        const item = await this.getMangaDetails(id);
        return item !== undefined ? [item] : [];
      }
    }
    const body = `{"keyword":${JSON.stringify(query)},"sort":"match","filter":{"type":[1]}}`;
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    const resp = await TrackHttp.send('POST', `${BGM_API_URL}/v0/search/subjects?limit=20`, headers, body);
    const raw = JSON.parse(resp) as BgmSearchResultRaw;
    const results: TrackSearchResult[] = [];
    for (const subject of raw.data ?? []) {
      if (this.isMangaPlatform(subject.platform)) {
        results.push(this.subjectToSearch(subject));
      }
    }
    return results;
  }

  // ---- 内部实现 ----

  async bind(track: TrackRecord, hasReadChapters: boolean): Promise<TrackRecord> {
    const status = await this.statusLibManga(track);
    if (status !== undefined) {
      if (track.status !== BangumiTracker.COMPLETED) {
        track.status = hasReadChapters ? BangumiTracker.READING : track.status;
      }
      return await this.update(track, false);
    }
    track.status = hasReadChapters ? BangumiTracker.READING : BangumiTracker.PLAN_TO_READ;
    track.score = 0;
    return await this.addLibManga(track);
  }

  async update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    if (track.status !== BangumiTracker.COMPLETED) {
      if (didReadChapter) {
        if (track.totalChapters > 0 && Math.round(track.lastChapterRead) === track.totalChapters) {
          track.status = BangumiTracker.COMPLETED;
        } else {
          track.status = BangumiTracker.READING;
        }
      }
    }
    return await this.updateLibManga(track);
  }

  async refresh(track: TrackRecord): Promise<TrackRecord> {
    const status = await this.statusLibManga(track);
    if (status === undefined) {
      throw new Error('Could not find manga');
    }
    return track;
  }

  private async authHeaders(): Promise<Record<string, string>> {
    const token = await this.ensureToken((t: OAuthToken) => this.refreshToken(t));
    const headers = TrackHttp.bearer(token.accessToken);
    headers['User-Agent'] = BGM_USER_AGENT;
    return headers;
  }

  private async refreshToken(token: OAuthToken): Promise<OAuthToken> {
    const form: Record<string, string> = {
      'grant_type': 'refresh_token',
      'client_id': BGM_CLIENT_ID,
      'client_secret': BGM_CLIENT_SECRET,
      'refresh_token': token.refreshToken,
      'redirect_uri': BGM_REDIRECT_URL,
    };
    const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    const resp = await TrackHttp.send('POST', BGM_OAUTH_URL, headers, TrackHttp.formEncode(form));
    return BangumiTracker.parseToken(resp);
  }

  private async getCurrentUser(): Promise<BgmUserRaw> {
    const resp = await TrackHttp.send('GET', `${BGM_API_URL}/v0/me`, await this.authHeaders(), '');
    const raw = JSON.parse(resp) as BgmUserRaw;
    if (typeof raw.username !== 'string' || raw.username === '') {
      throw new Error('Bangumi: failed to get current user');
    }
    return raw;
  }

  private async addLibManga(track: TrackRecord): Promise<TrackRecord> {
    const body = `{"type":${this.toApiStatus(track.status)},"rate":${BangumiTracker.clampScore(track.score)}` +
      `,"ep_status":${Math.floor(track.lastChapterRead)},"private":${track.isPrivate}}`;
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    // 成功返回 202，无响应体
    await TrackHttp.send('POST', `${BGM_API_URL}/v0/users/-/collections/${track.remoteId}`, headers, body);
    return track;
  }

  private async updateLibManga(track: TrackRecord): Promise<TrackRecord> {
    const body = `{"type":${this.toApiStatus(track.status)},"rate":${BangumiTracker.clampScore(track.score)}` +
      `,"ep_status":${Math.floor(track.lastChapterRead)},"private":${track.isPrivate}}`;
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    // 成功返回 204
    await TrackHttp.send('PATCH', `${BGM_API_URL}/v0/users/-/collections/${track.remoteId}`, headers, body);
    return track;
  }

  // 查询用户收藏状态：直接更新 track 的 status/score/lastChapterRead/totalChapters；未收藏返回 undefined
  private async statusLibManga(track: TrackRecord): Promise<TrackRecord | undefined> {
    const username = this.getUsername();
    if (username === '') {
      throw new Error('Bangumi: not logged in');
    }
    const headers = await this.authHeaders();
    const resp = await Http.requestRaw('GET',
      `${BGM_API_URL}/v0/users/${encodeURIComponent(username)}/collections/${track.remoteId}`, '', headers);
    if (resp.code === 404) {
      return undefined;
    }
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`HTTP ${resp.code}: ${resp.body.substring(0, 200)}`);
    }
    const raw = JSON.parse(resp.body) as BgmCollectionRaw;
    if (typeof raw.type !== 'number') {
      return undefined;
    }
    track.status = BangumiTracker.fromApiType(raw.type);
    track.lastChapterRead = raw.ep_status ?? 0;
    track.score = raw.rate ?? 0;
    track.totalChapters = raw.subject?.eps ?? 0;
    return track;
  }

  private async getMangaDetails(id: number): Promise<TrackSearchResult | undefined> {
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    const resp = await TrackHttp.send('GET', `${BGM_API_URL}/v0/subjects/${id}`, headers, '');
    const raw = JSON.parse(resp) as BgmSubjectRaw;
    if (!this.isMangaPlatform(raw.platform)) {
      return undefined;
    }
    return this.subjectToSearch(raw);
  }

  // platform 为空或“漫画”视为漫画条目
  private isMangaPlatform(platform: string | undefined): boolean {
    return platform === undefined || platform === null || platform === '' || platform === '漫画';
  }

  private subjectToSearch(subject: BgmSubjectRaw): TrackSearchResult {
    const r = new TrackSearchResult();
    r.syncId = this.syncId;
    r.remoteId = subject.id;
    const nameCn = subject.name_cn ?? '';
    r.title = nameCn !== '' ? nameCn : subject.name;
    r.coverUrl = subject.images?.common ?? '';
    const summary = (subject.summary ?? '').trim();
    r.summary = nameCn !== '' ? `作品原名：${subject.name}\n${summary}` : summary;
    r.score = subject.rating?.score ?? -1;
    r.trackingUrl = `${BGM_SUBJECT_URL_PREFIX}${subject.id}`;
    r.totalChapters = subject.eps ?? 0;
    r.startDate = subject.date ?? '';
    return r;
  }

  private toApiStatus(status: number): number {
    switch (status) {
      case BangumiTracker.PLAN_TO_READ:
        return 1;
      case BangumiTracker.COMPLETED:
        return 2;
      case BangumiTracker.READING:
        return 3;
      case BangumiTracker.ON_HOLD:
        return 4;
      case BangumiTracker.DROPPED:
        return 5;
      default:
        throw new Error(`Unknown status: ${status}`);
    }
  }
}
