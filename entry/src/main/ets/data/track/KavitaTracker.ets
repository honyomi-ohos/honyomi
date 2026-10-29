// Kavita 追踪器（syncId=8）：自托管服务器（对齐 Mihon kavita/Kavita.kt + KavitaApi.kt）
// - EnhancedTracker：仅接受 kavita 源，按漫画 url 末段 seriesId 自动匹配，无需搜索
// - 登录：服务器地址 + API Key（POST /api/Plugin/authenticate 换 JWT）；服务器地址存 trackUsername_8，
//   API Key 入 Asset Store 密码槽，JWT 存 OAuthToken tokenAlias
// - 端点（抄录参考实现）：
//   登录       POST {server}/api/Plugin/authenticate?apiKey={key}&pluginName=Tachiyomi-Kavita（body {}）
//   匹配/刷新  GET  {trackingUrl}（{server}/api/Series/{id}，Bearer JWT）
//   总章节数   GET  {api}/Series/volumes?seriesId={id}（卷/章统计，单文件卷计为章节）
//   最新已读   GET  {api}/Tachiyomi/latest-chapter?seriesId={id}（200 有值 / 204 为 0）
//   进度更新   POST {api}/Tachiyomi/mark-chapter-until-as-read?seriesId={id}&chapterNumber={n}（body {}）
import { MangaRecord, TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { OAuthToken, Tracker, TrackHttp } from './Tracker';
import { Http } from '../../net/Http';

const KAVITA_PLUGIN_NAME = 'Tachiyomi-Kavita';

// ---- 原始 JSON 模型（对齐 KavitaModels.kt）----

interface KavitaAuthRaw {
  username?: string;
  token?: string;
}

interface KavitaSeriesRaw {
  id?: number;
  name?: string;
  thumbnailUrl?: string;
  pages?: number;
  pagesRead?: number;
}

interface KavitaChapterRaw {
  id?: number;
  number?: string;
}

interface KavitaVolumeRaw {
  chapters?: KavitaChapterRaw[];
}

interface KavitaLatestChapterRaw {
  number?: string;
}

export class KavitaTracker extends Tracker {
  static readonly UNREAD: number = 1;
  static readonly READING: number = 2;
  static readonly COMPLETED: number = 3;

  constructor() {
    super(8, 'Kavita', '#4AC69D');
    this.isEnhanced = true;
  }

  getStatusList(): number[] {
    return [KavitaTracker.UNREAD, KavitaTracker.READING, KavitaTracker.COMPLETED];
  }

  getStatusLabel(status: number): ResourceStr {
    switch (status) {
      case KavitaTracker.UNREAD:
        return $r('app.string.track_unread');
      case KavitaTracker.READING:
        return $r('app.string.track_reading');
      case KavitaTracker.COMPLETED:
        return $r('app.string.track_completed');
      default:
        return $r('app.string.track_unknown_status');
    }
  }

  getReadingStatus(): number {
    return KavitaTracker.READING;
  }

  getRereadingStatus(): number {
    return -1;
  }

  getCompletionStatus(): number {
    return KavitaTracker.COMPLETED;
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
    throw new Error('Kavita only supports server address login');
  }

  async loginWithCredentials(_username: string, _password: string): Promise<void> {
    throw new Error('Kavita only supports server address login');
  }

  // 登录：服务器地址 + API Key → JWT（对齐 KavitaApi.getNewToken）
  async loginWithServer(serverUrl: string, _username: string, secret: string): Promise<void> {
    const server = KavitaTracker.normalizeServer(serverUrl);
    if (server === '') {
      throw new Error('Kavita: invalid server address');
    }
    if (secret === '') {
      throw new Error('Kavita: missing API key');
    }
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    const resp = await TrackHttp.send('POST',
      `${server}/api/Plugin/authenticate?apiKey=${encodeURIComponent(secret)}&pluginName=${KAVITA_PLUGIN_NAME}`,
      headers, '{}');
    const auth = JSON.parse(resp) as KavitaAuthRaw;
    if (typeof auth.token !== 'string' || auth.token === '') {
      throw new Error('Kavita: login failed (check API key)');
    }
    this.saveCredentials(server, secret);
    const token = new OAuthToken();
    token.accessToken = auth.token;
    this.saveToken(token);
    Settings.setTrackDisplay(this.syncId, auth.username ?? server);
  }

  async search(_query: string): Promise<TrackSearchResult[]> {
    // 增强型追踪器不支持标题搜索（对齐 Mihon Kavita.search TODO）
    throw new Error('Kavita: search unsupported (auto-matched by source)');
  }

  async bind(track: TrackRecord, _hasReadChapters: boolean): Promise<TrackRecord> {
    return track;
  }

  async update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    if (track.status !== KavitaTracker.COMPLETED) {
      if (didReadChapter) {
        if (track.lastChapterRead === track.totalChapters && track.totalChapters > 0) {
          track.status = KavitaTracker.COMPLETED;
        } else {
          track.status = KavitaTracker.READING;
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
    return sourceKey.startsWith('kavita');
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

  // 服务器地址（trackUsername_8，去尾部斜杠与 /api）
  private serverUrl(): string {
    return KavitaTracker.normalizeServer(this.getUsername());
  }

  // API 根（{server}/api）
  private apiBase(): string {
    return `${this.serverUrl()}/api`;
  }

  // Bearer JWT 头（token 存 OAuthToken tokenAlias）
  private authHeaders(): Record<string, string> {
    const token = this.loadToken();
    if (token === undefined || token.accessToken === '') {
      throw new Error('Kavita: not logged in');
    }
    return {
      'Authorization': `Bearer ${token.accessToken}`,
      'Accept': 'application/json',
    };
  }

  // url 末段数字即 seriesId（对齐 KavitaApi.getIdFromUrl）
  private idFromUrl(url: string): number {
    return parseInt(url.substring(url.lastIndexOf('/') + 1), 10);
  }

  // 由漫画 url 推导追踪地址：已是 /api/Series/ 地址直接用；否则取末段数字拼 server
  private trackingUrlFor(mangaUrl: string): string {
    if (mangaUrl.includes('/api/Series/')) {
      return mangaUrl;
    }
    const seriesId = parseInt(mangaUrl.substring(mangaUrl.lastIndexOf('/') + 1), 10);
    if (isNaN(seriesId) || seriesId <= 0) {
      return '';
    }
    const server = this.serverUrl();
    return server === '' ? '' : `${server}/api/Series/${seriesId}`;
  }

  // 条目详情 + 进度 → TrackSearchResult（对齐 KavitaApi.getTrackSearch）
  private async getTrackSearch(trackingUrl: string): Promise<TrackSearchResult> {
    const seriesId = this.idFromUrl(trackingUrl);
    if (isNaN(seriesId) || seriesId <= 0) {
      throw new Error('Kavita: invalid series id');
    }
    const api = this.apiBase();
    const r = new TrackSearchResult();
    r.syncId = this.syncId;
    r.remoteId = seriesId;
    r.trackingUrl = trackingUrl;
    // 系列详情
    const seriesBody = await TrackHttp.send('GET', trackingUrl, this.authHeaders(), '');
    const series = JSON.parse(seriesBody) as KavitaSeriesRaw;
    r.title = series.name ?? '';
    r.coverUrl = series.thumbnailUrl ?? '';
    // 总章节数：卷/章扁平统计（单文件卷计为章节，对齐 KavitaApi.getTotalChapters）
    const volumesBody = await TrackHttp.send('GET', `${api}/Series/volumes?seriesId=${seriesId}`,
      this.authHeaders(), '');
    const volumes = JSON.parse(volumesBody) as KavitaVolumeRaw[];
    let volumeNumber = 0;
    let maxChapterNumber = 0;
    for (const volume of volumes) {
      let maxInVolume = 0;
      for (const chapter of volume.chapters ?? []) {
        const n = parseFloat((chapter.number ?? '0').replace(',', '.'));
        if (!isNaN(n) && n > maxInVolume) {
          maxInVolume = n;
        }
      }
      if (maxInVolume === 0) {
        volumeNumber++;
      } else if (maxChapterNumber < maxInVolume) {
        maxChapterNumber = Math.floor(maxInVolume);
      }
    }
    r.totalChapters = maxChapterNumber > volumeNumber ? maxChapterNumber : volumeNumber;
    // 最新已读章节（200 有值 / 204 未读，对齐 KavitaApi.getLatestChapterRead）
    const latest = await Http.requestRaw('GET', `${api}/Tachiyomi/latest-chapter?seriesId=${seriesId}`, '',
      this.authHeaders());
    if (latest.code === 200) {
      const chapter = JSON.parse(latest.body) as KavitaLatestChapterRaw;
      const n = parseFloat((chapter.number ?? '0').replace(',', '.'));
      r.lastChapterRead = isNaN(n) ? 0 : n;
    } else if (latest.code !== 204) {
      throw new Error(`Kavita: HTTP ${latest.code}`);
    }
    // 状态按已读页数（对齐参考实现：pagesRead == pages → COMPLETED；0 → UNREAD；否则 READING）
    const pages = series.pages ?? 0;
    const pagesRead = series.pagesRead ?? 0;
    if (pagesRead === pages) {
      r.status = KavitaTracker.COMPLETED;
    } else if (pagesRead === 0) {
      r.status = KavitaTracker.UNREAD;
    } else {
      r.status = KavitaTracker.READING;
    }
    return r;
  }

  // 进度更新（对齐 KavitaApi.updateProgress）：标记章节及之前全部已读，再取回远端状态
  private async updateProgress(track: TrackRecord): Promise<void> {
    const seriesId = this.idFromUrl(track.remoteUrl);
    if (isNaN(seriesId) || seriesId <= 0) {
      throw new Error('Kavita: invalid series id');
    }
    const headers = this.authHeaders();
    headers['Content-Type'] = 'application/json';
    await TrackHttp.send('POST',
      `${this.apiBase()}/Tachiyomi/mark-chapter-until-as-read?seriesId=${seriesId}&chapterNumber=${track.lastChapterRead}`,
      headers, '{}');
  }
}
