// Hikka 追踪器（syncId=10）：网页授权得到 reference code 换取 token（auth 头）
import { TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { Tracker, TrackHttp, OAuthToken, TrackDate } from './Tracker';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

const HIKKA_BASE_URL = 'https://hikka.io';
const HIKKA_API_URL = 'https://api.hikka.io';
const HIKKA_CLIENT_REFERENCE = '598ef1f5-b9d2-4e66-8b65-06949d5e14fc';
const HIKKA_CLIENT_SECRET = 'OKwzrNOZxq40psFgfcCUYddnvaeZWDnd34rt7fdcB5GmHoBBQuNTWX' +
  '61sZs8KECEWVXtMUDtq8QC4t9WX4DwWWYLXEVlgnlUXGT1fWCb-18c' +
  'Zd2m8Co-8HN6JQcjoP-B';

// ---- 原始 JSON 模型 ----
interface HikkaMangaRaw {
  title_original: string;
  title_ua?: string;
  title_en?: string;
  media_type?: string;
  chapters?: number;
  status?: string;
  image?: string;
  score?: number;
  slug: string;
  start_date?: number;
  read?: HikkaReadRaw[];
}

interface HikkaReadRaw {
  status: string;
  chapters: number;
  volumes?: number;
  rereads?: number;
  score: number;
  start_date?: number;
  end_date?: number;
  content?: HikkaMangaRaw;
}

interface HikkaSearchRaw {
  list?: HikkaMangaRaw[];
}

interface HikkaUserRaw {
  reference: string;
  username: string;
}

interface HikkaOAuthRaw {
  secret?: string;
  expiration?: number;
  created?: number;
}

interface HikkaTokenInfoRaw {
  expiration?: number;
  created?: number;
}

export class HikkaTracker extends Tracker {
  static readonly READING: number = 0;
  static readonly COMPLETED: number = 1;
  static readonly ON_HOLD: number = 2;
  static readonly DROPPED: number = 3;
  static readonly PLAN_TO_READ: number = 4;
  static readonly REREADING: number = 5;

  constructor() {
    super(10, 'Hikka', '#EC407A');
    this.supportsReadingDates = true;
  }

  getStatusList(): number[] {
    return [HikkaTracker.READING, HikkaTracker.COMPLETED, HikkaTracker.ON_HOLD,
      HikkaTracker.DROPPED, HikkaTracker.PLAN_TO_READ, HikkaTracker.REREADING];
  }

  getStatusLabel(status: number): ResourceStr {
    switch (status) {
      case HikkaTracker.READING:
        return $r('app.string.track_reading');
      case HikkaTracker.COMPLETED:
        return $r('app.string.track_completed');
      case HikkaTracker.ON_HOLD:
        return $r('app.string.track_on_hold');
      case HikkaTracker.DROPPED:
        return $r('app.string.track_dropped');
      case HikkaTracker.PLAN_TO_READ:
        return $r('app.string.track_plan_to_read');
      case HikkaTracker.REREADING:
        return $r('app.string.track_repeating');
      default:
        return $r('app.string.track_unknown_status');
    }
  }

  getReadingStatus(): number {
    return HikkaTracker.READING;
  }

  getRereadingStatus(): number {
    return HikkaTracker.REREADING;
  }

  getCompletionStatus(): number {
    return HikkaTracker.COMPLETED;
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
    // 用户在网页授权后获得 reference code，回填到应用内完成登录
    return `${HIKKA_BASE_URL}/oauth?reference=${HIKKA_CLIENT_REFERENCE}&scope=readlist,read:user-details`;
  }

  async loginWithCode(_code: string): Promise<void> {
    throw new Error('Hikka only supports reference-code login');
  }

  async loginWithCredentials(_username: string, reference: string): Promise<void> {
    const body = `{"request_reference":${JSON.stringify(reference)},"client_secret":"${HIKKA_CLIENT_SECRET}"}`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    const resp = await TrackHttp.send('POST', `${HIKKA_API_URL}/auth/token`, headers, body);
    const raw = JSON.parse(resp) as HikkaOAuthRaw;
    if (typeof raw.secret !== 'string' || raw.secret === '') {
      throw new Error('Hikka: invalid reference code');
    }
    const expiration = typeof raw.expiration === 'number' ? raw.expiration : 0;
    const token = new OAuthToken();
    token.accessToken = raw.secret;
    token.refreshToken = '';
    token.createdAt = TrackDate.nowSec();
    token.expiresIn = expiration > 0 ? expiration - token.createdAt - 300 : 0;
    this.saveToken(token);
    const user = await this.getCurrentUser();
    this.saveCredentials(user.reference, raw.secret);
    Settings.setTrackDisplay(this.syncId, user.username);
  }

  async search(query: string): Promise<TrackSearchResult[]> {
    if (query.startsWith('id:')) {
      const slug = query.substring(3).trim();
      if (slug !== '') {
        const item = await this.getMangaDetails(slug);
        return item !== undefined ? [item] : [];
      }
    }
    const body = `{"media_type":[],"status":[],"only_translated":false,"magazines":[],"genres":[],` +
      `"score":[0,10],"query":${JSON.stringify(query)},"sort":["score:desc","scored_by:desc"]}`;
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    const resp = await TrackHttp.send('POST', `${HIKKA_API_URL}/manga?page=1&size=50`, headers, body);
    const raw = JSON.parse(resp) as HikkaSearchRaw;
    const results: TrackSearchResult[] = [];
    for (const m of raw.list ?? []) {
      results.push(this.mangaToSearch(m));
    }
    return results;
  }

  async bind(track: TrackRecord, hasReadChapters: boolean): Promise<TrackRecord> {
    const readContent = await this.getRead(track);
    const manga = await this.getManga(track);
    const remoteTrack = this.mangaToRemote(manga);
    this.copyPersonalFrom(track, remoteTrack);
    track.remoteId = remoteTrack.remoteId;
    track.libraryId = remoteTrack.libraryId;
    if (track.status !== HikkaTracker.COMPLETED) {
      const isRereading = track.status === HikkaTracker.REREADING;
      track.status = !isRereading && hasReadChapters ? HikkaTracker.READING : track.status;
    }
    if (readContent !== undefined) {
      track.score = readContent.score;
      track.lastChapterRead = readContent.chapters;
      track.startDate = (readContent.start_date ?? 0) * 1000;
      track.finishDate = (readContent.end_date ?? 0) * 1000;
      return await this.update(track, false);
    }
    track.status = hasReadChapters ? HikkaTracker.READING : HikkaTracker.PLAN_TO_READ;
    track.score = 0;
    return await this.update(track, false);
  }

  async update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    if (track.status !== HikkaTracker.COMPLETED) {
      if (didReadChapter) {
        if (track.totalChapters > 0 && Math.round(track.lastChapterRead) === track.totalChapters) {
          track.status = HikkaTracker.COMPLETED;
          track.finishDate = Date.now();
        } else if (track.status !== HikkaTracker.REREADING) {
          track.status = HikkaTracker.READING;
          if (Math.round(track.lastChapterRead) === 1) {
            track.startDate = Date.now();
          }
        }
      }
    }
    await this.updateUserManga(track);
    return track;
  }

  async refresh(track: TrackRecord): Promise<TrackRecord> {
    const manga = await this.getManga(track);
    const remoteTrack = this.mangaToRemote(manga);
    this.copyPersonalFrom(track, remoteTrack);
    track.totalChapters = remoteTrack.totalChapters;
    const read = await this.getRead(track);
    if (read === undefined) {
      throw new Error('Could not find manga');
    }
    track.score = read.score;
    track.lastChapterRead = read.chapters;
    track.status = HikkaTracker.toLocalStatus(read.status);
    track.startDate = (read.start_date ?? 0) * 1000;
    track.finishDate = (read.end_date ?? 0) * 1000;
    return track;
  }

  async deleteRemote(track: TrackRecord): Promise<void> {
    await TrackHttp.send('DELETE', `${HIKKA_API_URL}/read/manga/${this.slugOf(track)}`,
      await this.authHeaders(), '');
  }

  // ---- 内部实现 ----

  private async authHeaders(): Promise<Record<string, string>> {
    const token = await this.ensureToken((t: OAuthToken) => this.refreshToken(t));
    return {
      'auth': token.accessToken,
      'accept': 'application/json',
    };
  }

  private async refreshToken(token: OAuthToken): Promise<OAuthToken> {
    // 拉取 token 信息刷新有效期；失败则视为已过期
    const headers: Record<string, string> = {
      'auth': token.accessToken,
      'accept': 'application/json',
    };
    const resp = await TrackHttp.send('GET', `${HIKKA_API_URL}/auth/token/info`, headers, '');
    const raw = JSON.parse(resp) as HikkaTokenInfoRaw;
    const expiration = typeof raw.expiration === 'number' ? raw.expiration : 0;
    if (expiration <= 0) {
      throw new Error('Hikka: the token is expired');
    }
    const refreshed = new OAuthToken();
    refreshed.accessToken = token.accessToken;
    refreshed.refreshToken = '';
    refreshed.createdAt = TrackDate.nowSec();
    refreshed.expiresIn = expiration - refreshed.createdAt - 300;
    return refreshed;
  }

  private async getCurrentUser(): Promise<HikkaUserRaw> {
    const resp = await TrackHttp.send('GET', `${HIKKA_API_URL}/user/me`, await this.authHeaders(), '');
    const raw = JSON.parse(resp) as HikkaUserRaw;
    if (typeof raw.reference !== 'string' || raw.reference === '') {
      throw new Error('Hikka: failed to get current user');
    }
    return raw;
  }

  private async getMangaDetails(slug: string): Promise<TrackSearchResult | undefined> {
    const resp = await TrackHttp.sendOptional('GET', `${HIKKA_API_URL}/manga/${slug}`,
      await this.authHeaders(), '');
    if (resp === undefined) {
      return undefined;
    }
    const raw = JSON.parse(resp) as HikkaMangaRaw;
    if (raw === null || raw === undefined || typeof raw !== 'object') {
      return undefined;
    }
    return this.mangaToSearch(raw);
  }

  private async getManga(track: TrackRecord): Promise<HikkaMangaRaw> {
    const resp = await TrackHttp.send('GET', `${HIKKA_API_URL}/manga/${this.slugOf(track)}`,
      await this.authHeaders(), '');
    const raw = JSON.parse(resp) as HikkaMangaRaw;
    if (raw === null || raw === undefined || typeof raw !== 'object') {
      throw new Error('Hikka: invalid manga response');
    }
    return raw;
  }

  private async getRead(track: TrackRecord): Promise<HikkaReadRaw | undefined> {
    const resp = await TrackHttp.sendOptional('GET', `${HIKKA_API_URL}/read/manga/${this.slugOf(track)}`,
      await this.authHeaders(), '');
    if (resp === undefined) {
      return undefined;
    }
    const raw = JSON.parse(resp) as HikkaReadRaw;
    return raw === null || raw === undefined || typeof raw !== 'object' ? undefined : raw;
  }

  private async updateUserManga(track: TrackRecord): Promise<void> {
    const slug = this.slugOf(track);
    const existing = await this.getRead(track);
    let rereads = existing?.rereads ?? 0;
    if (track.status === HikkaTracker.REREADING && rereads === 0) {
      rereads = 1;
    }
    const body = `{"note":"","chapters":${Math.floor(track.lastChapterRead)},"volumes":0,` +
      `"rereads":${rereads},"score":${Math.round(track.score)},"status":"${this.toApiStatus(track.status)}",` +
      `"start_date":${track.startDate > 0 ? Math.floor(track.startDate / 1000) : 'null'},` +
      `"end_date":${track.finishDate > 0 ? Math.floor(track.finishDate / 1000) : 'null'}}`;
    const headers = await this.authHeaders();
    headers['Content-Type'] = 'application/json';
    await TrackHttp.send('PUT', `${HIKKA_API_URL}/read/manga/${slug}`, headers, body);
  }

  private slugOf(track: TrackRecord): string {
    const parts = track.remoteUrl.split('/');
    return parts.length > 4 ? parts[4] : '';
  }

  private mangaToSearch(m: HikkaMangaRaw): TrackSearchResult {
    const r = new TrackSearchResult();
    r.syncId = this.syncId;
    r.remoteId = HikkaTracker.slugToId(m.slug);
    r.libraryId = r.remoteId;
    r.title = m.title_ua ?? m.title_en ?? m.title_original;
    r.totalChapters = m.chapters ?? 0;
    r.coverUrl = m.image ?? '';
    r.score = m.score ?? -1;
    r.trackingUrl = `${HIKKA_BASE_URL}/manga/${m.slug}`;
    r.publishingStatus = m.status ?? '';
    r.publishingType = (m.media_type ?? '').replace(/_/g, ' ');
    r.startDate = (m.start_date ?? 0) > 0 ? TrackDate.toIsoDate((m.start_date as number) * 1000) : '';
    const userProgress = (m.read !== undefined && m.read !== null && m.read.length > 0) ? m.read[0] : undefined;
    if (userProgress !== undefined) {
      r.status = HikkaTracker.toLocalStatus(userProgress.status);
      r.lastChapterRead = userProgress.chapters;
      r.score = userProgress.score;
      r.startReadDate = (userProgress.start_date ?? 0) * 1000;
      r.finishReadDate = (userProgress.end_date ?? 0) * 1000;
    }
    return r;
  }

  private mangaToRemote(m: HikkaMangaRaw): TrackRecord {
    const remote = new TrackRecord();
    remote.remoteId = HikkaTracker.slugToId(m.slug);
    remote.libraryId = remote.remoteId;
    remote.title = m.title_ua ?? m.title_en ?? m.title_original;
    remote.totalChapters = m.chapters ?? 0;
    const userProgress = (m.read !== undefined && m.read !== null && m.read.length > 0) ? m.read[0] : undefined;
    if (userProgress !== undefined) {
      remote.status = HikkaTracker.toLocalStatus(userProgress.status);
      remote.lastChapterRead = userProgress.chapters;
      remote.score = userProgress.score;
      remote.startDate = (userProgress.start_date ?? 0) * 1000;
      remote.finishDate = (userProgress.end_date ?? 0) * 1000;
    }
    return remote;
  }

  // slug → 48 位稳定数字 ID（对齐 Mihon 的 UUID.nameUUIDFromBytes，避免 64 位精度丢失）
  private static slugToId(slug: string): number {
    if (canIUse('SystemCapability.Security.CryptoFramework.MessageDigest')) {
      try {
        const bytes: Uint8Array = new util.TextEncoder().encodeInto(slug);
        const md = cryptoFramework.createMd('MD5');
        md.updateSync({ data: bytes });
        const digest = md.digestSync();
        const d = digest.data;
        let v = d[0] & 0x7f;
        for (let i = 1; i <= 5; i++) {
          v = v * 256 + d[i];
        }
        return v;
      } catch (_e) {
        return 0;
      }
    }
    return 0;
  }

  private toApiStatus(status: number): string {
    switch (status) {
      case HikkaTracker.READING:
        return 'reading';
      case HikkaTracker.COMPLETED:
        return 'completed';
      case HikkaTracker.ON_HOLD:
        return 'on_hold';
      case HikkaTracker.DROPPED:
        return 'dropped';
      case HikkaTracker.PLAN_TO_READ:
        return 'planned';
      case HikkaTracker.REREADING:
        return 'reading';
      default:
        throw new Error(`Unknown status: ${status}`);
    }
  }

  private static toLocalStatus(status: string): number {
    switch (status) {
      case 'reading':
        return HikkaTracker.READING;
      case 'completed':
        return HikkaTracker.COMPLETED;
      case 'on_hold':
        return HikkaTracker.ON_HOLD;
      case 'dropped':
        return HikkaTracker.DROPPED;
      case 'planned':
        return HikkaTracker.PLAN_TO_READ;
      default:
        throw new Error(`Unknown status: ${status}`);
    }
  }
}
