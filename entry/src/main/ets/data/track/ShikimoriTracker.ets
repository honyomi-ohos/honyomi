// Shikimori 追踪器（syncId=4）：OAuth code 授权 + REST(v2) / GraphQL 混合 API
import { TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { OAuthToken, TrackDate, Tracker, TrackHttp } from './Tracker';

const SM_BASE_URL = 'https://shikimori.one';
const SM_API_URL = `${SM_BASE_URL}/api`;
const SM_GRAPHQL_URL = `${SM_BASE_URL}/api/graphql`;
const SM_OAUTH_URL = `${SM_BASE_URL}/oauth/token`;
const SM_LOGIN_URL = `${SM_BASE_URL}/oauth/authorize`;
const SM_CLIENT_ID = 'PB9dq8DzI405s7wdtwTdirYqHiyVMh--djnP7lBUqSA';
const SM_CLIENT_SECRET = 'NajpZcOBKB9sJtgNcejf8OB9jBN1OYYoo-k4h2WWZus';
const SM_REDIRECT_URL = 'mihon://shikimori-auth';
const SM_USER_AGENT = 'Mihon-Harmony/1.0 (HarmonyOS)';

// ---- 原始 JSON 模型 ----
interface SmPosterRaw {
  mainUrl?: string;
}

interface SmAiredRaw {
  date?: string;
}

interface SmPersonRaw {
  name?: string;
}

interface SmPersonRoleRaw {
  person?: SmPersonRaw;
  rolesEn?: string[];
}

interface SmMangaRaw {
  id: number;
  name: string;
  chapters?: number;
  score?: number;
  url?: string;
  status?: string;
  poster?: SmPosterRaw;
  airedOn?: SmAiredRaw;
  description?: string;
  kind?: string;
  personRoles?: SmPersonRoleRaw[];
}

interface SmMangaResultsRaw {
  mangas?: SmMangaRaw[];
}

interface SmSearchResultRaw {
  data?: SmMangaResultsRaw;
}

interface SmUserRaw {
  id: string;
  nickname: string;
}

interface SmCurrentUserRaw {
  currentUser?: SmUserRaw;
}

interface SmUserResultRaw {
  data?: SmCurrentUserRaw;
}

interface SmUserRateRaw {
  id: string;
  chapters?: number;
  status?: string;
  score?: number;
}

interface SmUserListMangaRaw {
  id: string;
  url?: string;
  name?: string;
  chapters?: number;
  userRate?: SmUserRateRaw;
}

interface SmUserListEntriesRaw {
  mangas?: SmUserListMangaRaw[];
}

interface SmUserListResultRaw {
  data?: SmUserListEntriesRaw;
}

interface SmLibraryIdRaw {
  id: number;
}

interface SmTokenRaw {
  access_token?: string;
  refresh_token?: string;
  created_at?: number;
  expires_in?: number;
}

export class ShikimoriTracker extends Tracker {
  static readonly READING: number = 1;
  static readonly COMPLETED: number = 2;
  static readonly ON_HOLD: number = 3;
  static readonly DROPPED: number = 4;
  static readonly PLAN_TO_READ: number = 5;
  static readonly REREADING: number = 6;

  constructor() {
    super(4, 'Shikimori', '#343434');
  }

  private static parseToken(resp: string): OAuthToken {
    const raw = JSON.parse(resp) as SmTokenRaw;
    if (typeof raw.access_token !== 'string' || raw.access_token === '') {
      throw new Error('Shikimori: token response invalid');
    }
    const t = new OAuthToken();
    t.accessToken = raw.access_token;
    t.refreshToken = typeof raw.refresh_token === 'string' ? raw.refresh_token : '';
    t.createdAt = typeof raw.created_at === 'number' ? raw.created_at : TrackDate.nowSec();
    t.expiresIn = typeof raw.expires_in === 'number' ? raw.expires_in : 0;
    return t;
  }

  private static toLocalStatus(api: string): number {
    switch (api) {
      case 'watching':
        return ShikimoriTracker.READING;
      case 'completed':
        return ShikimoriTracker.COMPLETED;
      case 'on_hold':
        return ShikimoriTracker.ON_HOLD;
      case 'dropped':
        return ShikimoriTracker.DROPPED;
      case 'planned':
        return ShikimoriTracker.PLAN_TO_READ;
      case 'rewatching':
        return ShikimoriTracker.REREADING;
      default:
        throw new Error(`Unknown status: ${api}`);
    }
  }

  getStatusList(): number[] {
    return [ShikimoriTracker.READING, ShikimoriTracker.COMPLETED, ShikimoriTracker.ON_HOLD,
      ShikimoriTracker.DROPPED, ShikimoriTracker.PLAN_TO_READ, ShikimoriTracker.REREADING];
  }

  getStatusLabel(status: number): ResourceStr {
    switch (status) {
      case ShikimoriTracker.READING:
        return $r('app.string.track_reading');
      case ShikimoriTracker.COMPLETED:
        return $r('app.string.track_completed');
      case ShikimoriTracker.ON_HOLD:
        return $r('app.string.track_on_hold');
      case ShikimoriTracker.DROPPED:
        return $r('app.string.track_dropped');
      case ShikimoriTracker.PLAN_TO_READ:
        return $r('app.string.track_plan_to_read');
      case ShikimoriTracker.REREADING:
        return $r('app.string.track_repeating');
      default:
        return $r('app.string.track_unknown_status');
    }
  }

  getReadingStatus(): number {
    return ShikimoriTracker.READING;
  }

  getRereadingStatus(): number {
    return ShikimoriTracker.REREADING;
  }

  getCompletionStatus(): number {
    return ShikimoriTracker.COMPLETED;
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
    return `${SM_LOGIN_URL}?client_id=${SM_CLIENT_ID}&redirect_uri=${encodeURIComponent(SM_REDIRECT_URL)}` +
      `&response_type=code`;
  }

  async loginWithCode(code: string): Promise<void> {
    const form: Record<string, string> = {
      'grant_type': 'authorization_code',
      'client_id': SM_CLIENT_ID,
      'client_secret': SM_CLIENT_SECRET,
      'code': code,
      'redirect_uri': SM_REDIRECT_URL,
    };
    const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    const resp = await TrackHttp.send('POST', SM_OAUTH_URL, headers, TrackHttp.formEncode(form));
    const token = ShikimoriTracker.parseToken(resp);
    this.saveToken(token);
    const user = await this.getCurrentUser();
    this.saveCredentials(user.id, token.accessToken);
    Settings.setTrackDisplay(this.syncId, user.nickname);
  }

  async loginWithCredentials(_username: string, _password: string): Promise<void> {
    throw new Error('Shikimori only supports OAuth login');
  }

  async search(query: string): Promise<TrackSearchResult[]> {
    if (query.startsWith('id:')) {
      const id = parseInt(query.substring(3).trim(), 10);
      if (!isNaN(id)) {
        const item = await this.getMangaDetails(id);
        return item !== undefined ? [item] : [];
      }
    }
    const gql = 'query($query: String) { mangas(search: $query, limit: 20, kind:"!light_novel,!novel") ' +
      '{ id name chapters kind poster { mainUrl } score url status airedOn { date } description ' +
      'personRoles { person { name } rolesEn } } }';
    const resp = await this.sendGql(gql, `{"query":${JSON.stringify(query)}}`);
    const raw = JSON.parse(resp) as SmSearchResultRaw;
    const results: TrackSearchResult[] = [];
    for (const m of raw.data?.mangas ?? []) {
      results.push(this.mangaToSearch(m));
    }
    return results;
  }

  async bind(track: TrackRecord, hasReadChapters: boolean): Promise<TrackRecord> {
    const remote = await this.findLibManga(track);
    if (remote !== undefined) {
      this.copyPersonalFrom(track, remote);
      track.libraryId = remote.libraryId;
      if (track.status !== ShikimoriTracker.COMPLETED) {
        const isRereading = track.status === ShikimoriTracker.REREADING;
        track.status = !isRereading && hasReadChapters ? ShikimoriTracker.READING : track.status;
      }
      return await this.update(track, false);
    }
    track.status = hasReadChapters ? ShikimoriTracker.READING : ShikimoriTracker.PLAN_TO_READ;
    track.score = 0;
    return await this.addLibManga(track);
  }

  async update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    if (track.status !== ShikimoriTracker.COMPLETED) {
      if (didReadChapter) {
        if (track.totalChapters > 0 && Math.round(track.lastChapterRead) === track.totalChapters) {
          track.status = ShikimoriTracker.COMPLETED;
        } else if (track.status !== ShikimoriTracker.REREADING) {
          track.status = ShikimoriTracker.READING;
        }
      }
    }
    return await this.updateLibManga(track);
  }

  // ---- 内部实现 ----

  async refresh(track: TrackRecord): Promise<TrackRecord> {
    const remote = await this.findLibManga(track);
    if (remote === undefined) {
      throw new Error('Could not find manga');
    }
    track.libraryId = remote.libraryId;
    this.copyPersonalFrom(track, remote);
    track.totalChapters = remote.totalChapters;
    return track;
  }

  async deleteRemote(track: TrackRecord): Promise<void> {
    await TrackHttp.send('DELETE', `${SM_API_URL}/v2/user_rates/${track.libraryId}`, await this.authHeaders(), '');
  }

  private async authHeaders(): Promise<Record<string, string>> {
    const token = await this.ensureToken((t: OAuthToken) => this.refreshToken(t));
    const headers = TrackHttp.bearer(token.accessToken);
    headers['User-Agent'] = SM_USER_AGENT;
    return headers;
  }

  private async refreshToken(token: OAuthToken): Promise<OAuthToken> {
    const form: Record<string, string> = {
      'grant_type': 'refresh_token',
      'client_id': SM_CLIENT_ID,
      'client_secret': SM_CLIENT_SECRET,
      'refresh_token': token.refreshToken,
    };
    const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    const resp = await TrackHttp.send('POST', SM_OAUTH_URL, headers, TrackHttp.formEncode(form));
    return ShikimoriTracker.parseToken(resp);
  }

  private async sendGql(query: string, variables: string): Promise<string> {
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    return TrackHttp.send('POST', SM_GRAPHQL_URL, headers, TrackHttp.graphql(query, variables));
  }

  private async getCurrentUser(): Promise<SmUserRaw> {
    const gql = '{ currentUser { id nickname } }';
    const resp = await this.sendGql(gql, '{}');
    const raw = JSON.parse(resp) as SmUserResultRaw;
    const user = raw.data?.currentUser;
    if (user === undefined || typeof user.id !== 'string' || user.id === '') {
      throw new Error('Shikimori: failed to get current user');
    }
    return user;
  }

  private async getMangaDetails(id: number): Promise<TrackSearchResult | undefined> {
    const gql = 'query($query: String) { mangas(ids: $query, limit: 1, kind:"!light_novel,!novel") ' +
      '{ id name chapters kind poster { mainUrl } score url status airedOn { date } description ' +
      'personRoles { person { name } rolesEn } } }';
    const resp = await this.sendGql(gql, `{"query":"${id}"}`);
    const raw = JSON.parse(resp) as SmSearchResultRaw;
    const mangas = raw.data?.mangas ?? [];
    return mangas.length > 0 ? this.mangaToSearch(mangas[0]) : undefined;
  }

  private async findLibManga(track: TrackRecord): Promise<TrackRecord | undefined> {
    const gql = 'query($id: String) { mangas(ids: $id, limit: 1) ' +
      '{ id url name chapters userRate { id chapters status score } } }';
    const resp = await this.sendGql(gql, `{"id":"${track.remoteId}"}`);
    const raw = JSON.parse(resp) as SmUserListResultRaw;
    const mangas = raw.data?.mangas ?? [];
    if (mangas.length === 0) {
      return undefined;
    }
    const manga = mangas[0];
    const rate = manga.userRate;
    if (rate === undefined || rate === null) {
      // 条目已从 Shikimori 用户列表移除
      return undefined;
    }
    const remote = new TrackRecord();
    remote.remoteId = track.remoteId;
    remote.libraryId = parseInt(rate.id, 10);
    remote.title = manga.name ?? track.title;
    remote.totalChapters = manga.chapters ?? 0;
    remote.lastChapterRead = rate.chapters ?? 0;
    remote.score = rate.score ?? 0;
    remote.status = ShikimoriTracker.toLocalStatus(rate.status ?? 'watching');
    return remote;
  }

  private async addLibManga(track: TrackRecord): Promise<TrackRecord> {
    const userId = this.getUsername();
    if (userId === '') {
      throw new Error('Shikimori: not logged in');
    }
    const body = `{"user_rate":{"user_id":"${userId}","target_id":${track.remoteId}` +
      `,"target_type":"Manga","chapters":${Math.floor(track.lastChapterRead)}` +
      `,"score":${Math.round(track.score)},"status":"${this.toApiStatus(track.status)}"}}`;
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    const resp = await TrackHttp.send('POST', `${SM_API_URL}/v2/user_rates`, headers, body);
    const raw = JSON.parse(resp) as SmLibraryIdRaw;
    if (typeof raw.id === 'number') {
      track.libraryId = raw.id;
    }
    return track;
  }

  private async updateLibManga(track: TrackRecord): Promise<TrackRecord> {
    const body = `{"user_rate":{"chapters":${Math.floor(track.lastChapterRead)}` +
      `,"score":${Math.round(track.score)},"status":"${this.toApiStatus(track.status)}"}}`;
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    const resp = await TrackHttp.send('PUT', `${SM_API_URL}/v2/user_rates/${track.libraryId}`, headers, body);
    const raw = JSON.parse(resp) as SmLibraryIdRaw;
    if (typeof raw.id === 'number') {
      track.libraryId = raw.id;
    }
    return track;
  }

  private mangaToSearch(m: SmMangaRaw): TrackSearchResult {
    const r = new TrackSearchResult();
    r.syncId = this.syncId;
    r.remoteId = m.id;
    r.title = m.name;
    r.totalChapters = m.chapters ?? 0;
    r.coverUrl = m.poster?.mainUrl ?? '';
    r.summary = m.description ?? '';
    r.score = (m.score ?? 0) > 0 ? m.score as number : -1;
    r.trackingUrl = m.url ?? '';
    r.publishingStatus = m.status ?? '';
    r.publishingType = (m.kind ?? '').replace('one_shot', 'oneshot');
    r.startDate = m.airedOn?.date ?? '';
    for (const personRole of m.personRoles ?? []) {
      const name = personRole.person?.name ?? '';
      if (name === '') {
        continue;
      }
      for (const role of personRole.rolesEn ?? []) {
        if (role.includes('Story')) {
          r.authors.push(name);
        }
        if (role.includes('Art')) {
          r.artists.push(name);
        }
      }
    }
    return r;
  }

  private toApiStatus(status: number): string {
    switch (status) {
      case ShikimoriTracker.READING:
        return 'watching';
      case ShikimoriTracker.COMPLETED:
        return 'completed';
      case ShikimoriTracker.ON_HOLD:
        return 'on_hold';
      case ShikimoriTracker.DROPPED:
        return 'dropped';
      case ShikimoriTracker.PLAN_TO_READ:
        return 'planned';
      case ShikimoriTracker.REREADING:
        return 'rewatching';
      default:
        throw new Error(`Unknown status: ${status}`);
    }
  }
}
