// Komga 追踪器（syncId=6）：自托管服务器（对齐 Mihon komga/Komga.kt + KomgaApi.kt）
// - EnhancedTracker：仅接受 komga 源，按漫画 url 中的 /series/<id> 自动匹配，无需搜索
// - 登录：服务器地址 + 邮箱/密码（basic auth）；服务器地址存 trackUsername_6，密码入 Asset Store
// - 端点（抄录参考实现）：
//   匹配/刷新  GET {trackingUrl}（/api/v1/series/<id> 或 /api/v1/readlists/<id>）
//   阅读进度   GET {trackingUrl 的 v1→v2}/read-progress/tachiyomi
//   进度更新   PUT  同上；body 按 v1 系列地址 {"lastBookNumberSortRead":n} 或 {"lastBookRead":n}
//   登录校验   GET  {server}/api/v1/users/me（basic auth）
import { MangaRecord, TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { Tracker, TrackHttp } from './Tracker';
import { Http } from '../../net/Http';

// ---- 原始 JSON 模型（对齐 KomgaModels.kt）----

interface KomgaSeriesMetadataRaw {
  title?: string;
  summary?: string;
  status?: string;
}

interface KomgaSeriesRaw {
  id?: string;
  metadata?: KomgaSeriesMetadataRaw;
}

interface KomgaReadListRaw {
  id?: string;
  name?: string;
}

// v2 阅读进度（/api/v1/series/ 地址）
interface KomgaReadProgressV2Raw {
  booksCount?: number;
  booksReadCount?: number;
  booksUnreadCount?: number;
  lastReadContinuousNumberSort?: number;
  maxNumberSort?: number;
}

// v1 阅读进度（readlists 地址）：lastReadContinuousIndex ↔ v2 lastReadContinuousNumberSort
interface KomgaReadProgressRaw {
  booksCount?: number;
  booksReadCount?: number;
  booksUnreadCount?: number;
  lastReadContinuousIndex?: number;
}

export class KomgaTracker extends Tracker {
  static readonly UNREAD: number = 1;
  static readonly READING: number = 2;
  static readonly COMPLETED: number = 3;

  constructor() {
    super(6, 'Komga', '#4CC094');
    this.isEnhanced = true;
  }

  getStatusList(): number[] {
    return [KomgaTracker.UNREAD, KomgaTracker.READING, KomgaTracker.COMPLETED];
  }

  getStatusLabel(status: number): ResourceStr {
    switch (status) {
      case KomgaTracker.UNREAD:
        return $r('app.string.track_unread');
      case KomgaTracker.READING:
        return $r('app.string.track_reading');
      case KomgaTracker.COMPLETED:
        return $r('app.string.track_completed');
      default:
        return $r('app.string.track_unknown_status');
    }
  }

  getReadingStatus(): number {
    return KomgaTracker.READING;
  }

  getRereadingStatus(): number {
    return -1;
  }

  getCompletionStatus(): number {
    return KomgaTracker.COMPLETED;
  }

  getScoreList(): string[] {
    return [];
  }

  indexToScore(_index: number): number {
    return 0;
  }

  scoreIndex(_score: number): number {
    return 0;
  }

  displayScore(_track: TrackRecord): string {
    return '';
  }

  async getAuthUrl(): Promise<string> {
    return '';
  }

  async loginWithCode(_code: string): Promise<void> {
    throw new Error('Komga only supports server address login');
  }

  async loginWithCredentials(_username: string, _password: string): Promise<void> {
    throw new Error('Komga only supports server address login');
  }

  // 登录：服务器地址 + 邮箱/密码（basic auth）；先校验凭据再保存
  async loginWithServer(serverUrl: string, username: string, secret: string): Promise<void> {
    const server = KomgaTracker.normalizeServer(serverUrl);
    if (server === '') {
      throw new Error('Komga: invalid server address');
    }
    if (username === '' || secret === '') {
      throw new Error('Komga: missing email/password');
    }
    const headers: Record<string, string> = {
      'Authorization': TrackHttp.basic(username, secret),
      'Accept': 'application/json',
    };
    const resp = await Http.requestRaw('GET', `${server}/api/v1/users/me`, '', headers);
    if (resp.code === 401 || resp.code === 403) {
      throw new Error('Komga: login failed (check email/password)');
    }
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`Komga: HTTP ${resp.code}`);
    }
    this.saveCredentials(server, secret);
    Settings.setTrackDisplay(this.syncId, username);
  }

  async search(_query: string): Promise<TrackSearchResult[]> {
    // 增强型追踪器不支持标题搜索（对齐 Mihon Komga.search TODO）
    throw new Error('Komga: search unsupported (auto-matched by source)');
  }

  async bind(track: TrackRecord, _hasReadChapters: boolean): Promise<TrackRecord> {
    return track;
  }

  async update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    if (track.status !== KomgaTracker.COMPLETED) {
      if (didReadChapter) {
        if (track.lastChapterRead === track.totalChapters && track.totalChapters > 0) {
          track.status = KomgaTracker.COMPLETED;
        } else {
          track.status = KomgaTracker.READING;
        }
      }
    }
    await this.updateProgress(track);
    const remote = await this.getTrackSearch(track.remoteUrl);
    this.copyPersonalFromSearch(track, remote);
    return track;
  }

  async refresh(track: TrackRecord): Promise<TrackRecord> {
    const remote = await this.getTrackSearch(track.remoteUrl);
    this.copyPersonalFromSearch(track, remote);
    return track;
  }

  // ---- EnhancedTracker ----

  acceptsSourceKey(sourceKey: string): boolean {
    return sourceKey.startsWith('komga');
  }

  async match(manga: MangaRecord): Promise<TrackSearchResult | undefined> {
    if (!this.acceptsSourceKey(manga.sourceKey)) {
      return undefined;
    }
    const trackingUrl = this.trackingUrlFor(manga.url);
    if (trackingUrl === '') {
      return undefined;
    }
    try {
      return await this.getTrackSearch(trackingUrl);
    } catch (_e) {
      return undefined;
    }
  }

  // ---- 内部实现 ----

  private static normalizeServer(serverUrl: string): string {
    let server = serverUrl.trim();
    server = server.replace(/\/+$/, '');
    if (server.endsWith('/api')) {
      server = server.substring(0, server.length - '/api'.length);
    }
    return server;
  }

  // 服务器地址（trackUsername_6，去尾部斜杠与 /api）
  private serverUrl(): string {
    return KomgaTracker.normalizeServer(this.getUsername());
  }

  // basic auth 头：邮箱（trackDisplay_6）+ 密码（Asset Store）
  private authHeaders(): Record<string, string> {
    const password = this.getPassword();
    if (password === '') {
      throw new Error('Komga: not logged in');
    }
    return {
      'Authorization': TrackHttp.basic(Settings.getTrackDisplay(this.syncId), password),
      'Accept': 'application/json',
    };
  }

  // 由漫画 url 推导追踪地址：已是 API 地址直接用；否则取 /series/<id> 拼 server
  private trackingUrlFor(mangaUrl: string): string {
    if (mangaUrl.includes('/api/v1/series/') || mangaUrl.includes('/api/v1/readlists')) {
      return mangaUrl;
    }
    const marker = '/series/';
    const idx = mangaUrl.indexOf(marker);
    if (idx < 0) {
      return '';
    }
    const rest = mangaUrl.substring(idx + marker.length);
    const slash = rest.indexOf('/');
    const seriesId = slash >= 0 ? rest.substring(0, slash) : rest;
    if (seriesId === '') {
      return '';
    }
    const server = this.serverUrl();
    return server === '' ? '' : `${server}/api/v1/series/${seriesId}`;
  }

  // 条目详情 + 阅读进度 → TrackSearchResult（对齐 KomgaApi.getTrackSearch）
  private async getTrackSearch(trackingUrl: string): Promise<TrackSearchResult> {
    const r = new TrackSearchResult();
    r.syncId = this.syncId;
    r.trackingUrl = trackingUrl;
    r.coverUrl = `${trackingUrl}/thumbnail`;
    const body = await TrackHttp.send('GET', trackingUrl, this.authHeaders(), '');
    if (trackingUrl.includes('/api/v1/readlists')) {
      const readList = JSON.parse(body) as KomgaReadListRaw;
      r.title = readList.name ?? '';
    } else {
      const series = JSON.parse(body) as KomgaSeriesRaw;
      r.title = series.metadata?.title ?? '';
      r.summary = series.metadata?.summary ?? '';
      r.publishingStatus = series.metadata?.status ?? '';
    }
    // 阅读进度：v1 系列地址升级到 v2；readlists 地址保持 v1
    const progressUrl =
      `${trackingUrl.replace('/api/v1/series/', '/api/v2/series/')}/read-progress/tachiyomi`;
    const progressBody = await TrackHttp.send('GET', progressUrl, this.authHeaders(), '');
    let booksCount = 0;
    let booksReadCount = 0;
    let booksUnreadCount = 0;
    let lastChapterRead = 0;
    let maxNumberSort = 0;
    if (trackingUrl.includes('/api/v1/series/')) {
      const p = JSON.parse(progressBody) as KomgaReadProgressV2Raw;
      booksCount = p.booksCount ?? 0;
      booksReadCount = p.booksReadCount ?? 0;
      booksUnreadCount = p.booksUnreadCount ?? 0;
      lastChapterRead = p.lastReadContinuousNumberSort ?? 0;
      maxNumberSort = p.maxNumberSort ?? 0;
    } else {
      const p = JSON.parse(progressBody) as KomgaReadProgressRaw;
      booksCount = p.booksCount ?? 0;
      booksReadCount = p.booksReadCount ?? 0;
      booksUnreadCount = p.booksUnreadCount ?? 0;
      lastChapterRead = p.lastReadContinuousIndex ?? 0;
      maxNumberSort = booksCount;
    }
    r.totalChapters = maxNumberSort;
    r.lastChapterRead = lastChapterRead;
    if (booksUnreadCount === booksCount) {
      r.status = KomgaTracker.UNREAD;
    } else if (booksReadCount === booksCount) {
      r.status = KomgaTracker.COMPLETED;
    } else {
      r.status = KomgaTracker.READING;
    }
    return r;
  }

  // 进度更新（对齐 KomgaApi.updateProgress）：v1 系列用 lastBookNumberSortRead，其余 lastBookRead
  private async updateProgress(track: TrackRecord): Promise<void> {
    const progressUrl =
      `${track.remoteUrl.replace('/api/v1/series/', '/api/v2/series/')}/read-progress/tachiyomi`;
    const body = track.remoteUrl.includes('/api/v1/series/')
      ? `{"lastBookNumberSortRead":${track.lastChapterRead}}`
      : `{"lastBookRead":${Math.floor(track.lastChapterRead)}}`;
    const headers = this.authHeaders();
    headers['Content-Type'] = 'application/json';
    await TrackHttp.send('PUT', progressUrl, headers, body);
  }
}
