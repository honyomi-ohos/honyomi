// MyAnimeList 追踪器（syncId=1）：OAuth code + plain PKCE
import { TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { Tracker, TrackHttp, OAuthToken, TrackDate, Pkce } from './Tracker';
import { Http } from '../../net/Http';

const MAL_CLIENT_ID = 'c46c9e24640a64dad5be5ca7a1a53a0f';
const MAL_OAUTH_BASE = 'https://myanimelist.net/v1/oauth2';
const MAL_API_BASE = 'https://api.myanimelist.net/v2';
const MAL_MANGA_URL_PREFIX = 'https://myanimelist.net/manga/';
const MAL_SEARCH_FIELDS = 'id,title,synopsis,num_chapters,mean,main_picture,status,media_type,start_date,' +
  'authors{first_name,last_name}';
const MAL_LIST_PAGE_SIZE = 250;

// ---- 原始 JSON 模型 ----
interface MalTokenRaw {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  created_at?: number;
}

interface MalUserRaw {
  name: string;
}

interface MalAuthorRaw {
  first_name?: string;
  last_name?: string;
}

interface MalAuthorNodeRaw {
  node?: MalAuthorRaw;
  role?: string;
}

interface MalPictureRaw {
  large?: string;
  medium?: string;
}

interface MalMangaRaw {
  id: number;
  title: string;
  synopsis?: string;
  num_chapters?: number;
  mean?: number;
  main_picture?: MalPictureRaw;
  status?: string;
  media_type?: string;
  start_date?: string;
  authors?: MalAuthorNodeRaw[];
}

interface MalSearchNodeRaw {
  node: MalMangaRaw;
}

interface MalPagingRaw {
  next?: string;
}

interface MalSearchRaw {
  data?: MalSearchNodeRaw[];
  paging?: MalPagingRaw;
}

interface MalListStatusRaw {
  is_rereading?: boolean;
  status?: string;
  num_chapters_read?: number;
  score?: number;
  start_date?: string;
  finish_date?: string;
}

interface MalListItemRaw {
  num_chapters?: number;
  my_list_status?: MalListStatusRaw;
}

export class MalTracker extends Tracker {
  static readonly READING: number = 1;
  static readonly COMPLETED: number = 2;
  static readonly ON_HOLD: number = 3;
  static readonly DROPPED: number = 4;
  static readonly PLAN_TO_READ: number = 6;
  static readonly REREADING: number = 7;

  private codeVerifier: string = '';

  constructor() {
    super(1, 'MyAnimeList', '#2E51A2');
    this.supportsReadingDates = true;
  }

  getStatusList(): number[] {
    return [MalTracker.READING, MalTracker.COMPLETED, MalTracker.ON_HOLD,
      MalTracker.DROPPED, MalTracker.PLAN_TO_READ, MalTracker.REREADING];
  }

  getStatusLabel(status: number): ResourceStr {
    switch (status) {
      case MalTracker.READING:
        return $r('app.string.track_reading');
      case MalTracker.COMPLETED:
        return $r('app.string.track_completed');
      case MalTracker.ON_HOLD:
        return $r('app.string.track_on_hold');
      case MalTracker.DROPPED:
        return $r('app.string.track_dropped');
      case MalTracker.PLAN_TO_READ:
        return $r('app.string.track_plan_to_read');
      case MalTracker.REREADING:
        return $r('app.string.track_repeating');
      default:
        return $r('app.string.track_unknown_status');
    }
  }

  getReadingStatus(): number {
    return MalTracker.READING;
  }

  getRereadingStatus(): number {
    return MalTracker.REREADING;
  }

  getCompletionStatus(): number {
    return MalTracker.COMPLETED;
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
    this.codeVerifier = Pkce.verifier();
    return `${MAL_OAUTH_BASE}/authorize?client_id=${MAL_CLIENT_ID}` +
      `&code_challenge=${this.codeVerifier}&response_type=code`;
  }

  async loginWithCode(code: string): Promise<void> {
    const form: Record<string, string> = {
      'client_id': MAL_CLIENT_ID,
      'code': code,
      'code_verifier': this.codeVerifier,
      'grant_type': 'authorization_code',
    };
    const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    const resp = await TrackHttp.send('POST', `${MAL_OAUTH_BASE}/token`, headers, TrackHttp.formEncode(form));
    const token = MalTracker.parseToken(resp);
    this.saveToken(token);
    const username = await this.getCurrentUser();
    this.saveCredentials(username, token.accessToken);
    Settings.setTrackDisplay(this.syncId, username);
  }

  async loginWithCredentials(_username: string, _password: string): Promise<void> {
    throw new Error('MyAnimeList only supports OAuth login');
  }

  async search(query: string): Promise<TrackSearchResult[]> {
    if (query.startsWith('id:')) {
      const id = parseInt(query.substring(3).trim(), 10);
      if (!isNaN(id)) {
        const item = await this.getMangaDetails(id);
        return item !== undefined ? [item] : [];
      }
    }
    if (query.startsWith('my:')) {
      return await this.findListItems(query.substring(3), 0);
    }
    // MAL API 对超过 64 字符的查询返回 400
    const q = query.substring(0, 64);
    const url = `${MAL_API_BASE}/manga?q=${encodeURIComponent(q)}&nsfw=true` +
      `&fields=${encodeURIComponent(MAL_SEARCH_FIELDS)}`;
    const resp = await TrackHttp.send('GET', url, await this.authHeaders(), '');
    const raw = JSON.parse(resp) as MalSearchRaw;
    const results: TrackSearchResult[] = [];
    for (const entry of raw.data ?? []) {
      if (!(entry.node.media_type ?? '').includes('novel')) {
        results.push(this.itemToSearch(entry.node));
      }
    }
    return results;
  }

  async bind(track: TrackRecord, hasReadChapters: boolean): Promise<TrackRecord> {
    const remote = await this.findListItem(track);
    if (remote !== undefined) {
      this.copyPersonalFrom(track, remote);
      track.remoteId = remote.remoteId;
      if (track.status !== MalTracker.COMPLETED) {
        const isRereading = track.status === MalTracker.REREADING;
        track.status = !isRereading && hasReadChapters ? MalTracker.READING : track.status;
      }
      return await this.update(track, false);
    }
    track.status = hasReadChapters ? MalTracker.READING : MalTracker.PLAN_TO_READ;
    track.score = 0;
    return await this.updateItem(track);
  }

  async update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    if (track.status !== MalTracker.COMPLETED) {
      if (didReadChapter) {
        if (track.totalChapters > 0 && Math.round(track.lastChapterRead) === track.totalChapters) {
          track.status = MalTracker.COMPLETED;
          track.finishDate = Date.now();
        } else if (track.status !== MalTracker.REREADING) {
          track.status = MalTracker.READING;
          if (Math.round(track.lastChapterRead) === 1) {
            track.startDate = Date.now();
          }
        }
      }
    }
    return await this.updateItem(track);
  }

  async refresh(track: TrackRecord): Promise<TrackRecord> {
    const remote = await this.findListItem(track);
    return remote !== undefined ? remote : await this.updateItem(track);
  }

  async deleteRemote(track: TrackRecord): Promise<void> {
    await TrackHttp.send('DELETE', `${MAL_API_BASE}/manga/${track.remoteId}/my_list_status`,
      await this.authHeaders(), '');
  }

  // ---- 内部实现 ----

  private async authHeaders(): Promise<Record<string, string>> {
    const token = await this.ensureToken((t: OAuthToken) => this.refreshToken(t));
    return TrackHttp.bearer(token.accessToken);
  }

  private async refreshToken(token: OAuthToken): Promise<OAuthToken> {
    const form: Record<string, string> = {
      'grant_type': 'refresh_token',
      'client_id': MAL_CLIENT_ID,
      'refresh_token': token.refreshToken,
    };
    const headers = TrackHttp.bearer(token.accessToken);
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    const resp = await TrackHttp.send('POST', `${MAL_OAUTH_BASE}/token`, headers, TrackHttp.formEncode(form));
    return MalTracker.parseToken(resp);
  }

  private static parseToken(resp: string): OAuthToken {
    const raw = JSON.parse(resp) as MalTokenRaw;
    if (typeof raw.access_token !== 'string' || raw.access_token === '') {
      throw new Error('MyAnimeList: token response invalid');
    }
    const t = new OAuthToken();
    t.accessToken = raw.access_token;
    t.refreshToken = typeof raw.refresh_token === 'string' ? raw.refresh_token : '';
    t.createdAt = typeof raw.created_at === 'number' ? raw.created_at : TrackDate.nowSec();
    t.expiresIn = typeof raw.expires_in === 'number' ? raw.expires_in : 0;
    return t;
  }

  private async getCurrentUser(): Promise<string> {
    const resp = await TrackHttp.send('GET', `${MAL_API_BASE}/users/@me`, await this.authHeaders(), '');
    const raw = JSON.parse(resp) as MalUserRaw;
    if (typeof raw.name !== 'string' || raw.name === '') {
      throw new Error('MyAnimeList: failed to get current user');
    }
    return raw.name;
  }

  private async getMangaDetails(id: number): Promise<TrackSearchResult | undefined> {
    const url = `${MAL_API_BASE}/manga/${id}?fields=${encodeURIComponent(MAL_SEARCH_FIELDS)}`;
    const resp = await TrackHttp.send('GET', url, await this.authHeaders(), '');
    const raw = JSON.parse(resp) as MalMangaRaw;
    return this.itemToSearch(raw);
  }

  private async findListItems(query: string, offset: number): Promise<TrackSearchResult[]> {
    let url = `${MAL_API_BASE}/users/@me/mangalist?fields=${encodeURIComponent(MAL_SEARCH_FIELDS)}` +
      `&limit=${MAL_LIST_PAGE_SIZE}`;
    if (offset > 0) {
      url += `&offset=${offset}`;
    }
    const resp = await TrackHttp.send('GET', url, await this.authHeaders(), '');
    const raw = JSON.parse(resp) as MalSearchRaw;
    const lower = query.toLowerCase();
    const results: TrackSearchResult[] = [];
    for (const entry of raw.data ?? []) {
      if (entry.node.title.toLowerCase().includes(lower)) {
        results.push(this.itemToSearch(entry.node));
      }
    }
    if (typeof raw.paging?.next === 'string' && raw.paging.next !== '') {
      const more = await this.findListItems(query, offset + MAL_LIST_PAGE_SIZE);
      return results.concat(more);
    }
    return results;
  }

  private async findListItem(track: TrackRecord): Promise<TrackRecord | undefined> {
    const url = `${MAL_API_BASE}/manga/${track.remoteId}` +
      `?fields=${encodeURIComponent('num_chapters,my_list_status{start_date,finish_date}')}`;
    const resp = await TrackHttp.send('GET', url, await this.authHeaders(), '');
    const raw = JSON.parse(resp) as MalListItemRaw;
    track.totalChapters = raw.num_chapters ?? 0;
    const status = raw.my_list_status;
    if (status === undefined || status === null) {
      return undefined;
    }
    return this.parseListItem(status, track);
  }

  private async updateItem(track: TrackRecord): Promise<TrackRecord> {
    const form: Record<string, string> = {
      'status': MalTracker.toApiStatus(track.status) ?? 'reading',
      'is_rereading': `${track.status === MalTracker.REREADING}`,
      'score': `${Math.round(track.score)}`,
      'num_chapters_read': `${Math.floor(track.lastChapterRead)}`,
    };
    if (track.startDate > 0) {
      form['start_date'] = TrackDate.toIsoDate(track.startDate);
    }
    if (track.finishDate > 0) {
      form['finish_date'] = TrackDate.toIsoDate(track.finishDate);
    }
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    const resp = await Http.requestRaw('PUT', `${MAL_API_BASE}/manga/${track.remoteId}/my_list_status`,
      TrackHttp.formEncode(form), headers);
    if (resp.code === 400 && resp.body.includes('invalid_content')) {
      // 未过审条目：搜索可返回但无法加入列表
      throw new Error('MyAnimeList: this title cannot be added because it is waiting for approval');
    }
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`HTTP ${resp.code}: ${resp.body.substring(0, 200)}`);
    }
    const status = JSON.parse(resp.body) as MalListStatusRaw;
    return this.parseListItem(status, track);
  }

  private parseListItem(status: MalListStatusRaw, track: TrackRecord): TrackRecord {
    const isRereading = status.is_rereading === true;
    track.status = isRereading ? MalTracker.REREADING : MalTracker.toLocalStatus(status.status ?? '');
    track.lastChapterRead = status.num_chapters_read ?? 0;
    track.score = status.score ?? 0;
    if (typeof status.start_date === 'string' && status.start_date !== '') {
      track.startDate = TrackDate.parseIsoDate(status.start_date);
    }
    if (typeof status.finish_date === 'string' && status.finish_date !== '') {
      track.finishDate = TrackDate.parseIsoDate(status.finish_date);
    }
    return track;
  }

  private itemToSearch(node: MalMangaRaw): TrackSearchResult {
    const r = new TrackSearchResult();
    r.syncId = this.syncId;
    r.remoteId = node.id;
    r.title = node.title;
    r.summary = node.synopsis ?? '';
    r.totalChapters = node.num_chapters ?? 0;
    r.score = node.mean ?? -1;
    r.coverUrl = node.main_picture?.large ?? '';
    r.trackingUrl = `${MAL_MANGA_URL_PREFIX}${node.id}`;
    r.publishingStatus = (node.status ?? '').replace(/_/g, ' ');
    r.publishingType = (node.media_type ?? '').replace(/_/g, ' ');
    r.startDate = node.start_date ?? '';
    const authors = node.authors ?? [];
    for (const authorNode of authors) {
      const name = `${authorNode.node?.first_name ?? ''} ${authorNode.node?.last_name ?? ''}`.trim();
      if (name === '') {
        continue;
      }
      const role = authorNode.role ?? '';
      if (role.includes('Art')) {
        r.artists.push(name);
      }
      if (role.includes('Story')) {
        r.authors.push(name);
      }
    }
    return r;
  }

  private static toApiStatus(status: number): string | undefined {
    switch (status) {
      case MalTracker.READING:
        return 'reading';
      case MalTracker.COMPLETED:
        return 'completed';
      case MalTracker.ON_HOLD:
        return 'on_hold';
      case MalTracker.DROPPED:
        return 'dropped';
      case MalTracker.PLAN_TO_READ:
        return 'plan_to_read';
      case MalTracker.REREADING:
        return 'reading';
      default:
        return undefined;
    }
  }

  private static toLocalStatus(api: string): number {
    switch (api) {
      case 'reading':
        return MalTracker.READING;
      case 'completed':
        return MalTracker.COMPLETED;
      case 'on_hold':
        return MalTracker.ON_HOLD;
      case 'dropped':
        return MalTracker.DROPPED;
      case 'plan_to_read':
        return MalTracker.PLAN_TO_READ;
      default:
        return MalTracker.READING;
    }
  }
}
