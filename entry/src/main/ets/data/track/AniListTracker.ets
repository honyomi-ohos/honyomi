// AniList 追踪器（syncId=2）：GraphQL API + implicit OAuth（token 位于重定向 URL fragment）
import { TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { GraphqlErrorRaw, OAuthToken, TrackDate, Tracker, TrackHttp } from './Tracker';

const AL_API_URL = 'https://graphql.anilist.co/';
const AL_AUTH_URL = 'https://anilist.co/api/v2/oauth/authorize?client_id=16329&response_type=token';
const AL_MANGA_URL_PREFIX = 'https://anilist.co/manga/';
// implicit token 有效期 1 年
const AL_TOKEN_LIFETIME_SEC = 31536000;

// ---- 原始 JSON 模型 ----
interface AlFuzzyDateRaw {
  year?: number;
  month?: number;
  day?: number;
}

interface AlTitleRaw {
  userPreferred: string;
}

interface AlCoverRaw {
  large: string;
}

interface AlMediaItemRaw {
  id: number;
  title?: AlTitleRaw;
  coverImage?: AlCoverRaw;
  description?: string;
  format?: string;
  status?: string;
  chapters?: number;
  averageScore?: number;
  startDate?: AlFuzzyDateRaw;
}

interface AlSearchResultRaw {
  data?: AlSearchPageRaw;
  errors?: GraphqlErrorRaw[];
}

interface AlSearchPageRaw {
  Page?: AlSearchMediaRaw;
}

interface AlSearchMediaRaw {
  media?: AlMediaItemRaw[];
}

interface AlUserListItemRaw {
  id: number;
  status: string;
  scoreRaw: number;
  progress: number;
  private: boolean;
  startedAt?: AlFuzzyDateRaw;
  completedAt?: AlFuzzyDateRaw;
  media?: AlMediaItemRaw;
}

interface AlUserListResultRaw {
  data?: AlUserListPageRaw;
  errors?: GraphqlErrorRaw[];
}

interface AlUserListPageRaw {
  Page?: AlUserListMediaRaw;
}

interface AlUserListMediaRaw {
  mediaList?: AlUserListItemRaw[];
}

interface AlAddResultRaw {
  data?: AlAddDataRaw;
  errors?: GraphqlErrorRaw[];
}

interface AlAddDataRaw {
  SaveMediaListEntry?: AlAddEntryRaw;
}

interface AlAddEntryRaw {
  id: number;
}

interface AlViewerResultRaw {
  data?: AlViewerDataRaw;
  errors?: GraphqlErrorRaw[];
}

interface AlViewerDataRaw {
  Viewer?: AlViewerRaw;
}

interface AlViewerRaw {
  id: number;
  name: string;
  mediaListOptions?: AlScoreFormatRaw;
}

interface AlScoreFormatRaw {
  scoreFormat: string;
}

export class AniListTracker extends Tracker {
  static readonly READING: number = 1;
  static readonly COMPLETED: number = 2;
  static readonly ON_HOLD: number = 3;
  static readonly DROPPED: number = 4;
  static readonly PLAN_TO_READ: number = 5;
  static readonly REREADING: number = 6;

  constructor() {
    super(2, 'AniList', '#02A9FF');
    this.supportsReadingDates = true;
    this.supportsPrivateTracking = true;
  }

  getStatusList(): number[] {
    return [AniListTracker.READING, AniListTracker.COMPLETED, AniListTracker.ON_HOLD,
      AniListTracker.DROPPED, AniListTracker.PLAN_TO_READ, AniListTracker.REREADING];
  }

  getStatusLabel(status: number): ResourceStr {
    switch (status) {
      case AniListTracker.READING:
        return $r('app.string.track_reading');
      case AniListTracker.COMPLETED:
        return $r('app.string.track_completed');
      case AniListTracker.ON_HOLD:
        return $r('app.string.track_on_hold');
      case AniListTracker.DROPPED:
        return $r('app.string.track_dropped');
      case AniListTracker.PLAN_TO_READ:
        return $r('app.string.track_plan_to_read');
      case AniListTracker.REREADING:
        return $r('app.string.track_repeating');
      default:
        return $r('app.string.track_unknown_status');
    }
  }

  getReadingStatus(): number {
    return AniListTracker.READING;
  }

  getRereadingStatus(): number {
    return AniListTracker.REREADING;
  }

  getCompletionStatus(): number {
    return AniListTracker.COMPLETED;
  }

  getScoreList(): string[] {
    const list: string[] = [];
    switch (Settings.getAnilistScoreType()) {
      case 'POINT_10':
        for (let i = 0; i <= 10; i++) {
          list.push(`${i}`);
        }
        break;
      case 'POINT_5':
        list.push('0');
        for (let i = 1; i <= 5; i++) {
          list.push(`${i} ★`);
        }
        break;
      case 'POINT_3':
        list.push('-', ':(', ':|', ':)');
        break;
      case 'POINT_10_DECIMAL':
        for (let i = 0; i <= 100; i++) {
          list.push((i / 10).toFixed(1));
        }
        break;
      default:
        for (let i = 0; i <= 100; i++) {
          list.push(`${i}`);
        }
        break;
    }
    return list;
  }

  indexToScore(index: number): number {
    switch (Settings.getAnilistScoreType()) {
      case 'POINT_10':
        return index * 10;
      case 'POINT_5':
        return index === 0 ? 0 : index * 20 - 10;
      case 'POINT_3':
        return index === 0 ? 0 : index * 25 + 10;
      default:
        return index;
    }
  }

  scoreIndex(score: number): number {
    switch (Settings.getAnilistScoreType()) {
      case 'POINT_10':
        return Math.round(score / 10);
      case 'POINT_5':
        return score === 0 ? 0 : Math.round((score + 10) / 20);
      case 'POINT_3':
        return score === 0 ? 0 : score <= 35 ? 1 : score <= 60 ? 2 : 3;
      default:
        return Math.round(score);
    }
  }

  displayScore(track: TrackRecord): string {
    const score = track.score;
    switch (Settings.getAnilistScoreType()) {
      case 'POINT_5':
        return score === 0 ? '0' : `${Math.round((score + 10) / 20)} ★`;
      case 'POINT_3':
        return score === 0 ? '0' : score <= 35 ? ':(' : score <= 60 ? ':|' : ':)';
      case 'POINT_10':
        return `${Math.round(score / 10)}`;
      case 'POINT_10_DECIMAL':
        return (score / 10).toFixed(1);
      default:
        return `${Math.round(score)}`;
    }
  }

  async getAuthUrl(): Promise<string> {
    return AL_AUTH_URL;
  }

  async loginWithCode(tokenStr: string): Promise<void> {
    const token = new OAuthToken();
    token.accessToken = tokenStr;
    token.refreshToken = '';
    token.createdAt = TrackDate.nowSec();
    token.expiresIn = AL_TOKEN_LIFETIME_SEC;
    this.saveToken(token);
    const user = await this.getCurrentUser();
    const format = user.mediaListOptions?.scoreFormat;
    if (typeof format === 'string' && format !== '') {
      Settings.setAnilistScoreType(format);
    }
    this.saveCredentials(`${user.id}`, token.accessToken);
    Settings.setTrackDisplay(this.syncId, user.name);
  }

  async loginWithCredentials(_username: string, _password: string): Promise<void> {
    throw new Error('AniList only supports OAuth login');
  }

  async search(query: string): Promise<TrackSearchResult[]> {
    if (query.startsWith('id:')) {
      const id = parseInt(query.substring(3).trim(), 10);
      if (!isNaN(id)) {
        const item = await this.getMangaDetails(id);
        return item !== undefined ? [item] : [];
      }
    }
    const gql = 'query Search($query: String) { Page (perPage: 50) { media(search: $query, type: MANGA, ' +
      'format_not_in: [NOVEL]) { id title { userPreferred } coverImage { large } format status chapters ' +
      'averageScore startDate { year month day } } } }';
    const resp = await TrackHttp.send('POST', AL_API_URL, await this.authHeaders(),
      TrackHttp.graphql(gql, `{"query":${JSON.stringify(query)}}`));
    const raw = JSON.parse(resp) as AlSearchResultRaw;
    this.checkErrors(raw.errors);
    const items = raw.data?.Page?.media ?? [];
    const results: TrackSearchResult[] = [];
    for (const item of items) {
      results.push(this.itemToSearch(item));
    }
    return results;
  }

  async bind(track: TrackRecord, hasReadChapters: boolean): Promise<TrackRecord> {
    const remote = await this.findLibManga(track);
    if (remote !== undefined) {
      this.copyPersonalFrom(track, remote, false);
      track.libraryId = remote.libraryId;
      if (track.status !== AniListTracker.COMPLETED) {
        const isRereading = track.status === AniListTracker.REREADING;
        track.status = !isRereading && hasReadChapters ? AniListTracker.READING : track.status;
      }
      return await this.update(track, false);
    }
    track.status = hasReadChapters ? AniListTracker.READING : AniListTracker.PLAN_TO_READ;
    track.score = 0;
    return await this.addLibManga(track);
  }

  async update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    if (track.libraryId === 0) {
      const lib = await this.findLibManga(track);
      if (lib === undefined) {
        throw new Error(`${track.title} not found in AniList library`);
      }
      track.libraryId = lib.libraryId;
    }
    if (track.status !== AniListTracker.COMPLETED) {
      if (didReadChapter) {
        if (track.totalChapters > 0 && Math.round(track.lastChapterRead) === track.totalChapters) {
          track.status = AniListTracker.COMPLETED;
          track.finishDate = Date.now();
        } else if (track.status !== AniListTracker.REREADING) {
          track.status = AniListTracker.READING;
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
    track.title = remote.title;
    track.totalChapters = remote.totalChapters;
    return track;
  }

  async deleteRemote(track: TrackRecord): Promise<void> {
    let listId = track.libraryId;
    if (listId === 0) {
      const lib = await this.findLibManga(track);
      if (lib === undefined) {
        return;
      }
      listId = lib.libraryId;
    }
    const gql = 'mutation DeleteManga($listId: Int) { DeleteMediaListEntry(id: $listId) { deleted } }';
    await TrackHttp.send('POST', AL_API_URL, await this.authHeaders(),
      TrackHttp.graphql(gql, `{"listId":${listId}}`));
  }

  // ---- 内部实现 ----

  private async authHeaders(): Promise<Record<string, string>> {
    const token = this.loadToken();
    if (token === undefined) {
      throw new Error('AniList: not logged in');
    }
    if (token.isExpired()) {
      this.logout();
      throw new Error('AniList: token expired, please log in again');
    }
    return TrackHttp.bearer(token.accessToken);
  }

  private async getCurrentUser(): Promise<AlViewerRaw> {
    const gql = 'query User { Viewer { id name mediaListOptions { scoreFormat } } }';
    const resp = await TrackHttp.send('POST', AL_API_URL, await this.authHeaders(), TrackHttp.graphql(gql, '{}'));
    const raw = JSON.parse(resp) as AlViewerResultRaw;
    this.checkErrors(raw.errors);
    const viewer = raw.data?.Viewer;
    if (viewer === undefined) {
      throw new Error('AniList: failed to get current user');
    }
    return viewer;
  }

  private async getMangaDetails(id: number): Promise<TrackSearchResult | undefined> {
    const gql = 'query Search($manga_id: Int) { Page (perPage: 1) { media(id: $manga_id, type: MANGA, ' +
      'format_not_in: [NOVEL]) { id title { userPreferred } coverImage { large } format status chapters ' +
      'averageScore startDate { year month day } } } }';
    const resp = await TrackHttp.send('POST', AL_API_URL, await this.authHeaders(),
      TrackHttp.graphql(gql, `{"manga_id":${id}}`));
    const raw = JSON.parse(resp) as AlSearchResultRaw;
    this.checkErrors(raw.errors);
    const item = raw.data?.Page?.media ?? [];
    return item.length > 0 ? this.itemToSearch(item[0]) : undefined;
  }

  private async findLibManga(track: TrackRecord): Promise<TrackRecord | undefined> {
    const userId = parseInt(this.getUsername(), 10);
    if (isNaN(userId)) {
      throw new Error('AniList: not logged in');
    }
    const gql = 'query ($id: Int!, $manga_id: Int!) { Page { mediaList(userId: $id, type: MANGA, ' +
      'mediaId: $manga_id) { id status scoreRaw: score(format: POINT_100) progress private ' +
      'startedAt { year month day } completedAt { year month day } ' +
      'media { id title { userPreferred } chapters } } } }';
    const resp = await TrackHttp.send('POST', AL_API_URL, await this.authHeaders(),
      TrackHttp.graphql(gql, `{"id":${userId},"manga_id":${track.remoteId}}`));
    const raw = JSON.parse(resp) as AlUserListResultRaw;
    this.checkErrors(raw.errors);
    const items = raw.data?.Page?.mediaList ?? [];
    if (items.length === 0) {
      return undefined;
    }
    const first = items[0];
    const remote = new TrackRecord();
    remote.remoteId = track.remoteId;
    remote.libraryId = first.id;
    remote.status = this.toLocalStatus(first.status);
    remote.score = first.scoreRaw;
    remote.lastChapterRead = first.progress;
    remote.startDate = this.fuzzyToEpoch(first.startedAt);
    remote.finishDate = this.fuzzyToEpoch(first.completedAt);
    remote.isPrivate = first.private;
    remote.totalChapters = first.media?.chapters ?? 0;
    remote.title = first.media?.title?.userPreferred ?? track.title;
    return remote;
  }

  private async addLibManga(track: TrackRecord): Promise<TrackRecord> {
    const gql = 'mutation AddManga($mangaId: Int, $progress: Int, $status: MediaListStatus, $private: Boolean) ' +
      '{ SaveMediaListEntry (mediaId: $mangaId, progress: $progress, status: $status, private: $private) ' +
      '{ id status } }';
    const vars = `{"mangaId":${track.remoteId},"progress":${Math.floor(track.lastChapterRead)}` +
      `,"status":"${this.toApiStatus(track.status)}","private":${track.isPrivate}}`;
    const resp = await TrackHttp.send('POST', AL_API_URL, await this.authHeaders(), TrackHttp.graphql(gql, vars));
    const raw = JSON.parse(resp) as AlAddResultRaw;
    this.checkErrors(raw.errors);
    const id = raw.data?.SaveMediaListEntry?.id;
    if (typeof id === 'number') {
      track.libraryId = id;
    }
    return track;
  }

  private async updateLibManga(track: TrackRecord): Promise<TrackRecord> {
    const gql = 'mutation UpdateManga($listId: Int, $progress: Int, $status: MediaListStatus, $private: Boolean, ' +
      '$score: Int, $startedAt: FuzzyDateInput, $completedAt: FuzzyDateInput) ' +
      '{ SaveMediaListEntry(id: $listId, progress: $progress, status: $status, private: $private, ' +
      'scoreRaw: $score, startedAt: $startedAt, completedAt: $completedAt) { id status progress } }';
    const vars = `{"listId":${track.libraryId},"progress":${Math.floor(track.lastChapterRead)}` +
      `,"status":"${this.toApiStatus(track.status)}","score":${Math.round(track.score)}` +
      `,"startedAt":${this.fuzzyInput(track.startDate)},"completedAt":${this.fuzzyInput(track.finishDate)}` +
      `,"private":${track.isPrivate}}`;
    const resp = await TrackHttp.send('POST', AL_API_URL, await this.authHeaders(), TrackHttp.graphql(gql, vars));
    const raw = JSON.parse(resp) as AlAddResultRaw;
    this.checkErrors(raw.errors);
    return track;
  }

  private itemToSearch(item: AlMediaItemRaw): TrackSearchResult {
    const r = new TrackSearchResult();
    r.syncId = this.syncId;
    r.remoteId = item.id;
    r.title = item.title?.userPreferred ?? '';
    r.coverUrl = item.coverImage?.large ?? '';
    r.summary = item.description ?? '';
    r.totalChapters = item.chapters ?? 0;
    r.score = item.averageScore ?? -1;
    r.trackingUrl = `${AL_MANGA_URL_PREFIX}${item.id}`;
    r.publishingStatus = item.status ?? '';
    r.publishingType = item.format ?? '';
    r.startDate = TrackDate.toIsoDate(this.fuzzyToEpoch(item.startDate));
    return r;
  }

  private toApiStatus(status: number): string {
    switch (status) {
      case AniListTracker.READING:
        return 'CURRENT';
      case AniListTracker.COMPLETED:
        return 'COMPLETED';
      case AniListTracker.ON_HOLD:
        return 'PAUSED';
      case AniListTracker.DROPPED:
        return 'DROPPED';
      case AniListTracker.PLAN_TO_READ:
        return 'PLANNING';
      case AniListTracker.REREADING:
        return 'REPEATING';
      default:
        throw new Error(`Unknown status: ${status}`);
    }
  }

  private toLocalStatus(api: string): number {
    switch (api) {
      case 'CURRENT':
        return AniListTracker.READING;
      case 'COMPLETED':
        return AniListTracker.COMPLETED;
      case 'PAUSED':
        return AniListTracker.ON_HOLD;
      case 'DROPPED':
        return AniListTracker.DROPPED;
      case 'PLANNING':
        return AniListTracker.PLAN_TO_READ;
      case 'REPEATING':
        return AniListTracker.REREADING;
      default:
        throw new Error(`Unknown status: ${api}`);
    }
  }

  private fuzzyToEpoch(raw: AlFuzzyDateRaw | undefined): number {
    if (raw === undefined || raw === null) {
      return 0;
    }
    if (typeof raw.year !== 'number' || typeof raw.month !== 'number' || typeof raw.day !== 'number') {
      return 0;
    }
    return new Date(raw.year, raw.month - 1, raw.day).getTime();
  }

  private fuzzyInput(epochMs: number): string {
    if (epochMs <= 0) {
      return '{"year":null,"month":null,"day":null}';
    }
    const d = new Date(epochMs);
    return `{"year":${d.getFullYear()},"month":${d.getMonth() + 1},"day":${d.getDate()}}`;
  }

  private checkErrors(errors: GraphqlErrorRaw[] | undefined): void {
    if (errors !== undefined && errors !== null && errors.length > 0) {
      throw new Error(errors[0].message ?? 'AniList request failed');
    }
  }
}
