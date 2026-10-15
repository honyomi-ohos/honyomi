// Kitsu 追踪器（syncId=3）：GraphQL API + 用户名密码登录（password grant）
import { TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { Tracker, TrackHttp, OAuthToken, TrackDate } from './Tracker';
import { Http } from '../../net/Http';

const KITSU_CLIENT_ID = 'dd031b32d2f56c990b1425efe6c42ad847e7fe3ab46bf1299f05ecd856bdb7dd';
const KITSU_CLIENT_SECRET = '54d7307928f63414defd96399fc31ba847961ceaecef3a5fd93144e960c0e151';
const KITSU_GRAPHQL_URL = 'https://kitsu.app/api/graphql';
const KITSU_LOGIN_URL = 'https://kitsu.app/api/oauth/token';
const KITSU_MANGA_URL_PREFIX = 'https://kitsu.app/manga/';
const KITSU_COMMON_MANGA = 'id titles { preferred } chapterCount staff(first: 5) { nodes { role person { name } } } ' +
  'posterImage { views(names: "small") { name url } original { name url } } ' +
  'description(locales: "en") status subtype startDate endDate slug averageRating';

// ---- 原始 JSON 模型 ----
interface KitsuTitlesRaw {
  preferred: string;
}

interface KitsuPersonRaw {
  name: string;
}

interface KitsuStaffNodeRaw {
  role: string;
  person?: KitsuPersonRaw;
}

interface KitsuStaffDataRaw {
  nodes?: KitsuStaffNodeRaw[];
}

interface KitsuPosterRaw {
  url: string;
}

interface KitsuPostersRaw {
  views?: KitsuPosterRaw[];
  original?: KitsuPosterRaw;
}

interface KitsuMangaRaw {
  id: string;
  titles?: KitsuTitlesRaw;
  chapterCount?: number;
  staff?: KitsuStaffDataRaw;
  posterImage?: KitsuPostersRaw;
  description?: Record<string, string>;
  status?: string;
  subtype?: string;
  startDate?: string;
  slug?: string;
  averageRating?: number;
  myLibraryEntry?: KitsuLibraryEntryRaw;
}

interface KitsuLibraryEntryRaw {
  id: string;
  private?: boolean;
  progress?: number;
  rating?: number;
  reconsuming?: boolean;
  status?: string;
  startedAt?: string;
  finishedAt?: string;
}

interface KitsuErrorRaw {
  message?: string;
}

interface KitsuMutationDataRaw {
  libraryEntry?: KitsuMutationEntryRaw;
}

interface KitsuMutationEntryRaw {
  create?: KitsuEntryResultRaw;
  update?: KitsuEntryResultRaw;
  delete?: KitsuEntryResultRaw;
}

interface KitsuEntryResultRaw {
  libraryEntry?: KitsuSparseEntryRaw;
}

interface KitsuSparseEntryRaw {
  id?: string;
}

interface KitsuMutationRaw {
  data?: KitsuMutationDataRaw;
  errors?: KitsuErrorRaw[];
  error?: KitsuErrorRaw;
}

interface KitsuSearchTitleRaw {
  data?: KitsuSearchTitleDataRaw;
}

interface KitsuSearchTitleDataRaw {
  searchMangaByTitle?: KitsuSearchNodesRaw;
}

interface KitsuSearchNodesRaw {
  nodes?: KitsuMangaRaw[];
}

interface KitsuFindByIdRaw {
  data?: KitsuFindByIdDataRaw;
}

interface KitsuFindByIdDataRaw {
  findMangaById?: KitsuMangaRaw;
}

interface KitsuFindBySlugRaw {
  data?: KitsuFindBySlugDataRaw;
}

interface KitsuFindBySlugDataRaw {
  findMangaBySlug?: KitsuMangaRaw;
}

interface KitsuAccountRaw {
  id: string;
  ratingSystem: string;
  profile: KitsuProfileRaw;
}

interface KitsuProfileRaw {
  name: string;
}

interface KitsuAccountResultRaw {
  data?: KitsuAccountDataRaw;
}

interface KitsuAccountDataRaw {
  currentAccount?: KitsuAccountRaw;
}

interface KitsuTokenRaw {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  created_at?: number;
}

// 评分体系：显示列表 + Kitsu 原生 2-20 分值刻度
class KitsuRatingSystem {
  scoreList: string[] = [];
  twentyScale: number[] = [];
}

export class KitsuTracker extends Tracker {
  static readonly READING: number = 1;
  static readonly COMPLETED: number = 2;
  static readonly ON_HOLD: number = 3;
  static readonly DROPPED: number = 4;
  static readonly PLAN_TO_READ: number = 5;

  constructor() {
    super(3, 'Kitsu', '#F65440');
    this.supportsReadingDates = true;
    this.supportsPrivateTracking = true;
  }

  getStatusList(): number[] {
    return [KitsuTracker.READING, KitsuTracker.COMPLETED, KitsuTracker.ON_HOLD,
      KitsuTracker.DROPPED, KitsuTracker.PLAN_TO_READ];
  }

  getStatusLabel(status: number): ResourceStr {
    switch (status) {
      case KitsuTracker.READING:
        return $r('app.string.track_reading');
      case KitsuTracker.COMPLETED:
        return $r('app.string.track_completed');
      case KitsuTracker.ON_HOLD:
        return $r('app.string.track_on_hold');
      case KitsuTracker.DROPPED:
        return $r('app.string.track_dropped');
      case KitsuTracker.PLAN_TO_READ:
        return $r('app.string.track_plan_to_read');
      default:
        return $r('app.string.track_unknown_status');
    }
  }

  getReadingStatus(): number {
    return KitsuTracker.READING;
  }

  getRereadingStatus(): number {
    return -1;
  }

  getCompletionStatus(): number {
    return KitsuTracker.COMPLETED;
  }

  getScoreList(): string[] {
    return this.currentRatingSystem().scoreList;
  }

  indexToScore(index: number): number {
    if (index === 0) {
      return 0;
    }
    const sys = this.currentRatingSystem();
    return index - 1 < sys.twentyScale.length ? sys.twentyScale[index - 1] : 0;
  }

  scoreIndex(score: number): number {
    const idx = this.getScoreList().indexOf(this.displayScoreOf(score));
    return idx >= 0 ? idx : 0;
  }

  displayScore(track: TrackRecord): string {
    return this.displayScoreOf(track.score);
  }

  async getAuthUrl(): Promise<string> {
    return '';
  }

  async loginWithCode(_code: string): Promise<void> {
    throw new Error('Kitsu only supports username/password login');
  }

  async loginWithCredentials(username: string, password: string): Promise<void> {
    const form: Record<string, string> = {
      'username': username,
      'password': password,
      'grant_type': 'password',
      'client_id': KITSU_CLIENT_ID,
      'client_secret': KITSU_CLIENT_SECRET,
    };
    const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    const resp = await TrackHttp.send('POST', KITSU_LOGIN_URL, headers, TrackHttp.formEncode(form));
    this.saveToken(KitsuTracker.parseToken(resp));
    const account = await this.getCurrentAccount();
    const ratingSystem = account.ratingSystem.toLowerCase();
    if (ratingSystem === 'simple' || ratingSystem === 'regular' || ratingSystem === 'advanced') {
      Settings.setKitsuScoreType(ratingSystem);
    } else {
      Settings.setKitsuScoreType('advanced');
    }
    this.saveCredentials(username, account.id);
    Settings.setTrackDisplay(this.syncId, account.profile.name);
  }

  async search(query: string): Promise<TrackSearchResult[]> {
    if (query.startsWith('id:')) {
      const idOrSlug = query.substring(3).trim();
      if (idOrSlug !== '') {
        const item = await this.getMangaDetails(idOrSlug);
        return item !== undefined ? [item] : [];
      }
    }
    const gql = `query Query($query: String!) { searchMangaByTitle(title: $query, first: 20) ` +
      `{ nodes { ${KITSU_COMMON_MANGA} } } }`;
    const resp = await this.sendGql(gql, `{"query":${JSON.stringify(query)}}`);
    const raw = JSON.parse(resp) as KitsuSearchTitleRaw;
    const nodes = raw.data?.searchMangaByTitle?.nodes ?? [];
    const results: TrackSearchResult[] = [];
    for (const node of nodes) {
      results.push(this.mangaToSearch(node));
    }
    return results;
  }

  async bind(track: TrackRecord, hasReadChapters: boolean): Promise<TrackRecord> {
    const remote = await this.findLibManga(track);
    if (remote !== undefined) {
      this.copyPersonalFrom(track, remote, false);
      track.remoteId = remote.remoteId;
      track.libraryId = remote.libraryId;
      if (track.status !== KitsuTracker.COMPLETED) {
        track.status = hasReadChapters ? KitsuTracker.READING : track.status;
      }
      return await this.update(track, false);
    }
    track.status = hasReadChapters ? KitsuTracker.READING : KitsuTracker.PLAN_TO_READ;
    track.score = 0;
    return await this.addLibManga(track);
  }

  async update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    if (track.status !== KitsuTracker.COMPLETED) {
      if (didReadChapter) {
        if (track.totalChapters > 0 && Math.round(track.lastChapterRead) === track.totalChapters) {
          track.status = KitsuTracker.COMPLETED;
          track.finishDate = Date.now();
        } else {
          track.status = KitsuTracker.READING;
          if (Math.round(track.lastChapterRead) === 1) {
            track.startDate = Date.now();
          }
        }
      }
    }
    return await this.updateLibManga(track);
  }

  async refresh(track: TrackRecord): Promise<TrackRecord> {
    const remote = await this.findLibManga(track);
    if (remote === undefined) {
      throw new Error('Could not find manga');
    }
    this.copyPersonalFrom(track, remote);
    track.totalChapters = remote.totalChapters;
    return track;
  }

  async deleteRemote(track: TrackRecord): Promise<void> {
    const gql = 'mutation DeleteLibEntry($library_id: ID!) { libraryEntry { delete(input: { id: $library_id }) ' +
      '{ errors { message } libraryEntry { id } } } }';
    // 删除不在库中的条目会返回 500 "Couldn't find LibraryEntry"，视为成功
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    const resp = await Http.requestRaw('POST', KITSU_GRAPHQL_URL,
      TrackHttp.graphql(gql, `{"library_id":"${track.libraryId}"}`), headers);
    if (resp.body.includes('Couldn\'t find')) {
      return;
    }
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`HTTP ${resp.code}: ${resp.body.substring(0, 200)}`);
    }
    const raw = JSON.parse(resp.body) as KitsuMutationRaw;
    this.checkMutation(raw, 'delete');
  }

  // ---- 内部实现 ----

  private async authHeaders(): Promise<Record<string, string>> {
    const token = await this.ensureToken((t: OAuthToken) => this.refreshToken(t));
    const headers = TrackHttp.bearer(token.accessToken);
    headers['Accept'] = 'application/vnd.api+json';
    headers['Content-Type'] = 'application/vnd.api+json';
    return headers;
  }

  private async refreshToken(token: OAuthToken): Promise<OAuthToken> {
    const form: Record<string, string> = {
      'grant_type': 'refresh_token',
      'refresh_token': token.refreshToken,
      'client_id': KITSU_CLIENT_ID,
      'client_secret': KITSU_CLIENT_SECRET,
    };
    const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    const resp = await TrackHttp.send('POST', KITSU_LOGIN_URL, headers, TrackHttp.formEncode(form));
    return KitsuTracker.parseToken(resp);
  }

  private static parseToken(resp: string): OAuthToken {
    const raw = JSON.parse(resp) as KitsuTokenRaw;
    if (typeof raw.access_token !== 'string' || raw.access_token === '') {
      throw new Error('Kitsu: token response invalid');
    }
    const t = new OAuthToken();
    t.accessToken = raw.access_token;
    t.refreshToken = typeof raw.refresh_token === 'string' ? raw.refresh_token : '';
    t.createdAt = typeof raw.created_at === 'number' ? raw.created_at : TrackDate.nowSec();
    t.expiresIn = typeof raw.expires_in === 'number' ? raw.expires_in : 0;
    return t;
  }

  private async sendGql(query: string, variables: string): Promise<string> {
    return TrackHttp.send('POST', KITSU_GRAPHQL_URL, await this.authHeaders(), TrackHttp.graphql(query, variables));
  }

  private async getCurrentAccount(): Promise<KitsuAccountRaw> {
    const gql = 'query Query { currentAccount { id ratingSystem profile { name } } }';
    const resp = await this.sendGql(gql, '{}');
    const raw = JSON.parse(resp) as KitsuAccountResultRaw;
    const account = raw.data?.currentAccount;
    if (account === undefined) {
      throw new Error('Kitsu: failed to get current account');
    }
    return account;
  }

  private async getMangaDetails(idOrSlug: string): Promise<TrackSearchResult | undefined> {
    const byId = /^\d+$/.test(idOrSlug);
    const gql = byId
      ? `query Query($query: ID!) { findMangaById(id: $query) { ${KITSU_COMMON_MANGA} } }`
      : `query Query($query: String!) { findMangaBySlug(slug: $query) { ${KITSU_COMMON_MANGA} } }`;
    const resp = await this.sendGql(gql, `{"query":${JSON.stringify(idOrSlug)}}`);
    // 解析一次为 raw 模型再按分支取字段（避免同响应重复 parse + 链式深取）
    const raw = byId
      ? JSON.parse(resp) as KitsuFindByIdRaw
      : JSON.parse(resp) as KitsuFindBySlugRaw;
    const manga = byId
      ? (raw as KitsuFindByIdRaw).data?.findMangaById
      : (raw as KitsuFindBySlugRaw).data?.findMangaBySlug;
    return manga !== undefined ? this.mangaToSearch(manga) : undefined;
  }

  private async findLibManga(track: TrackRecord): Promise<TrackRecord | undefined> {
    const gql = `query Query($remote_id: ID!) { findMangaById(id: $remote_id) { ${KITSU_COMMON_MANGA} ` +
      'myLibraryEntry { id private progress rating reconsuming status startedAt finishedAt } } }';
    const resp = await this.sendGql(gql, `{"remote_id":${track.remoteId}}`);
    const raw = JSON.parse(resp) as KitsuFindByIdRaw;
    const manga = raw.data?.findMangaById;
    if (manga === undefined || manga.myLibraryEntry === undefined || manga.myLibraryEntry === null) {
      return undefined;
    }
    const entry = manga.myLibraryEntry;
    const remote = new TrackRecord();
    remote.remoteId = parseInt(manga.id, 10);
    remote.libraryId = parseInt(entry.id, 10);
    remote.title = manga.titles?.preferred ?? track.title;
    remote.totalChapters = manga.chapterCount ?? 0;
    remote.status = KitsuTracker.toLocalStatus(entry.status ?? 'CURRENT');
    remote.score = entry.rating ?? 0;
    remote.lastChapterRead = entry.progress ?? 0;
    remote.isPrivate = entry.private === true;
    remote.startDate = KitsuTracker.isoToEpoch(entry.startedAt);
    remote.finishDate = KitsuTracker.isoToEpoch(entry.finishedAt);
    return remote;
  }

  private async addLibManga(track: TrackRecord): Promise<TrackRecord> {
    const gql = 'mutation AddManga($media_id: ID!, $status: LibraryEntryStatusEnum!, $progress: Int!, ' +
      '$private: Boolean!, $rating: Int) { libraryEntry { create(input: { mediaId: $media_id mediaType: MANGA ' +
      'status: $status progress: $progress private: $private rating: $rating }) ' +
      '{ errors { message } libraryEntry { id } } } }';
    const vars = `{"media_id":${track.remoteId},"status":"${this.toApiStatus(track.status)}"` +
      `,"progress":${Math.floor(track.lastChapterRead)},"private":${track.isPrivate}` +
      `,"rating":${track.score > 0 ? Math.round(track.score) : 'null'}}`;
    const resp = await this.sendGql(gql, vars);
    const raw = JSON.parse(resp) as KitsuMutationRaw;
    this.checkMutation(raw, 'add');
    const id = raw.data?.libraryEntry?.create?.libraryEntry?.id;
    if (typeof id === 'string' && id !== '') {
      track.libraryId = parseInt(id, 10);
    }
    return track;
  }

  private async updateLibManga(track: TrackRecord): Promise<TrackRecord> {
    const gql = 'mutation UpdateManga($library_id: ID!, $status: LibraryEntryStatusEnum!, $progress: Int!, ' +
      '$private: Boolean!, $rating: Int, $startedAt: ISO8601DateTime, $finishedAt: ISO8601DateTime) ' +
      '{ libraryEntry { update(input: { id: $library_id status: $status progress: $progress private: $private ' +
      'rating: $rating startedAt: $startedAt finishedAt: $finishedAt }) ' +
      '{ errors { message } libraryEntry { id } } } }';
    const vars = `{"library_id":${track.libraryId},"status":"${this.toApiStatus(track.status)}"` +
      `,"progress":${Math.floor(track.lastChapterRead)},"private":${track.isPrivate}` +
      `,"rating":${track.score > 0 ? Math.round(track.score) : 'null'}` +
      `,"startedAt":${KitsuTracker.epochToIsoVar(track.startDate)}` +
      `,"finishedAt":${KitsuTracker.epochToIsoVar(track.finishDate)}}`;
    const resp = await this.sendGql(gql, vars);
    const raw = JSON.parse(resp) as KitsuMutationRaw;
    this.checkMutation(raw, 'update');
    return track;
  }

  private mangaToSearch(m: KitsuMangaRaw): TrackSearchResult {
    const r = new TrackSearchResult();
    r.syncId = this.syncId;
    r.remoteId = parseInt(m.id, 10);
    r.title = m.titles?.preferred ?? '';
    r.totalChapters = m.chapterCount ?? 0;
    const views = m.posterImage?.views;
    r.coverUrl = (views !== undefined && views.length > 0 ? views[0].url : m.posterImage?.original?.url) ?? '';
    r.summary = m.description?.['en'] ?? '';
    r.trackingUrl = `${KITSU_MANGA_URL_PREFIX}${m.slug ?? ''}`;
    r.score = m.averageRating ?? -1;
    r.publishingStatus = KitsuTracker.prettyStatus(m.status ?? '');
    r.publishingType = KitsuTracker.prettyType(m.subtype ?? '');
    r.startDate = m.startDate ?? '';
    const nodes = m.staff?.nodes ?? [];
    for (const node of nodes) {
      const name = node.person?.name ?? '';
      if (name === '') {
        continue;
      }
      if (node.role.includes('Story')) {
        r.authors.push(name);
      }
      if (node.role.includes('Art')) {
        r.artists.push(name);
      }
    }
    return r;
  }

  private currentRatingSystem(): KitsuRatingSystem {
    const sys = new KitsuRatingSystem();
    switch (Settings.getKitsuScoreType()) {
      case 'simple':
        sys.scoreList = ['-', ':(', ':|', ':)', ':D'];
        sys.twentyScale = [2, 8, 14, 20];
        break;
      case 'regular':
        for (let i = 0; i <= 10; i++) {
          sys.scoreList.push(`${i / 2} ★`);
        }
        for (let v = 2; v <= 20; v += 2) {
          sys.twentyScale.push(v);
        }
        break;
      default:
        sys.scoreList.push('0');
        for (let i = 2; i <= 20; i++) {
          sys.scoreList.push(`${i / 2}`);
        }
        for (let v = 2; v <= 20; v++) {
          sys.twentyScale.push(v);
        }
        break;
    }
    return sys;
  }

  private displayScoreOf(score: number): string {
    const sys = this.currentRatingSystem();
    let idx = -1;
    for (let i = 0; i < sys.twentyScale.length; i++) {
      if (sys.twentyScale[i] <= score) {
        idx = i;
      }
    }
    return sys.scoreList[idx + 1];
  }

  private toApiStatus(status: number): string {
    switch (status) {
      case KitsuTracker.READING:
        return 'CURRENT';
      case KitsuTracker.COMPLETED:
        return 'COMPLETED';
      case KitsuTracker.ON_HOLD:
        return 'ON_HOLD';
      case KitsuTracker.DROPPED:
        return 'DROPPED';
      case KitsuTracker.PLAN_TO_READ:
        return 'PLANNED';
      default:
        throw new Error(`Unknown status: ${status}`);
    }
  }

  private static toLocalStatus(api: string): number {
    switch (api) {
      case 'CURRENT':
        return KitsuTracker.READING;
      case 'COMPLETED':
        return KitsuTracker.COMPLETED;
      case 'ON_HOLD':
        return KitsuTracker.ON_HOLD;
      case 'DROPPED':
        return KitsuTracker.DROPPED;
      case 'PLANNED':
        return KitsuTracker.PLAN_TO_READ;
      default:
        throw new Error(`Unknown status: ${api}`);
    }
  }

  private static isoToEpoch(iso: string | undefined): number {
    if (typeof iso !== 'string' || iso === '') {
      return 0;
    }
    const ms = Date.parse(iso);
    return isNaN(ms) ? 0 : ms;
  }

  private static epochToIsoVar(epochMs: number): string {
    return epochMs > 0 ? `"${new Date(epochMs).toISOString()}"` : 'null';
  }

  private static prettyStatus(status: string): string {
    if (status === 'TBA') {
      return 'TBA';
    }
    if (status === 'CURRENT') {
      return 'Publishing';
    }
    const lower = status.toLowerCase();
    return lower.charAt(0).toUpperCase() + lower.substring(1);
  }

  private static prettyType(subtype: string): string {
    if (subtype === 'OEL') {
      return subtype;
    }
    const lower = subtype.toLowerCase();
    return lower.charAt(0).toUpperCase() + lower.substring(1);
  }

  private checkMutation(raw: KitsuMutationRaw, action: string): void {
    if (raw.error !== undefined && raw.error !== null) {
      throw new Error(`Kitsu: failed to ${action} manga`);
    }
    if (raw.errors !== undefined && raw.errors !== null && raw.errors.length > 0) {
      throw new Error(`Kitsu: failed to ${action} manga`);
    }
    if (raw.data === undefined || raw.data === null) {
      throw new Error(`Kitsu: unexpected error while ${action === 'delete' ? 'deleting' : action + 'ing'} manga`);
    }
  }
}
