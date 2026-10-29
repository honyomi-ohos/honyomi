// Suwayomi 追踪器（syncId=9）：自托管服务器（对齐 Mihon suwayomi/Suwayomi.kt + SuwayomiApi.kt）
// - EnhancedTracker：仅接受 suwayomi/tachidesk 源，按漫画 url 末段 mangaId 自动匹配，无需搜索
// - 登录：服务器地址（可选 basic auth 用户名/密码）；服务器地址存 trackUsername_9，
//   密码入 Asset Store 密码槽，basic 用户名存 trackDisplay_9
// - 端点（抄录参考实现，GraphQL：{server}/api/graphql）：
//   登录校验   query { about { version } }
//   匹配/刷新  query GetManga($mangaId: Int!) { manga(id: $mangaId) { ...MangaFragment } }
//   未读章节   query GetMangaUnreadChapters($mangaId: Int!) { chapters(condition: {...}) { nodes { id chapterNumber } } }
//   标记已读   mutation updateChapters(input: {ids, patch: {isRead: true}})
//   上报进度   mutation trackProgress(input: {mangaId})
import { MangaRecord, TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { GraphqlErrorRaw, Tracker, TrackHttp } from './Tracker';

// ---- 原始 JSON 模型（对齐 SuwayomiModels.kt）----

interface SuwayomiChaptersRaw {
  totalCount?: number;
}

interface SuwayomiLatestReadRaw {
  chapterNumber?: number;
}

interface SuwayomiMangaRaw {
  id?: number;
  title?: string;
  description?: string;
  status?: string;
  thumbnailUrl?: string;
  chapters?: SuwayomiChaptersRaw;
  latestReadChapter?: SuwayomiLatestReadRaw;
  unreadCount?: number;
}

interface SuwayomiMangaResultRaw {
  data?: SuwayomiMangaDataRaw;
  errors?: GraphqlErrorRaw[];
}

interface SuwayomiMangaDataRaw {
  manga?: SuwayomiMangaRaw;
}

interface SuwayomiUnreadNodeRaw {
  id?: number;
  chapterNumber?: number;
}

interface SuwayomiUnreadChaptersRaw {
  nodes?: SuwayomiUnreadNodeRaw[];
}

interface SuwayomiUnreadResultRaw {
  data?: SuwayomiUnreadDataRaw;
  errors?: GraphqlErrorRaw[];
}

interface SuwayomiUnreadDataRaw {
  chapters?: SuwayomiUnreadChaptersRaw;
}

interface SuwayomiMutationDataRaw {
  __typename?: string;
}

interface SuwayomiMutationResultRaw {
  data?: SuwayomiMutationDataRaw;
  errors?: GraphqlErrorRaw[];
}

export class SuwayomiTracker extends Tracker {
  static readonly UNREAD: number = 1;
  static readonly READING: number = 2;
  static readonly COMPLETED: number = 3;

  constructor() {
    super(9, 'Suwayomi', '#5C6BC0');
    this.isEnhanced = true;
  }

  getStatusList(): number[] {
    return [SuwayomiTracker.UNREAD, SuwayomiTracker.READING, SuwayomiTracker.COMPLETED];
  }

  getStatusLabel(status: number): ResourceStr {
    switch (status) {
      case SuwayomiTracker.UNREAD:
        return $r('app.string.track_unread');
      case SuwayomiTracker.READING:
        return $r('app.string.track_reading');
      case SuwayomiTracker.COMPLETED:
        return $r('app.string.track_completed');
      default:
        return $r('app.string.track_unknown_status');
    }
  }

  getReadingStatus(): number {
    return SuwayomiTracker.READING;
  }

  getRereadingStatus(): number {
    return -1;
  }

  getCompletionStatus(): number {
    return SuwayomiTracker.COMPLETED;
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
    throw new Error('Suwayomi only supports server address login');
  }

  async loginWithCredentials(_username: string, _password: string): Promise<void> {
    throw new Error('Suwayomi only supports server address login');
  }

  // 登录：服务器地址 + 可选 basic auth；先校验服务器可达（about 查询）再保存
  async loginWithServer(serverUrl: string, username: string, secret: string): Promise<void> {
    const server = SuwayomiTracker.normalizeServer(serverUrl);
    if (server === '') {
      throw new Error('Suwayomi: invalid server address');
    }
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (secret !== '') {
      headers['Authorization'] = TrackHttp.basic(username, secret);
    }
    const query = 'query { about { version } }';
    const resp = await TrackHttp.send('POST', `${server}/api/graphql`, headers,
      TrackHttp.graphql(query, '{}'));
    this.checkGraphqlErrors(resp);
    this.saveCredentials(server, secret);
    Settings.setTrackDisplay(this.syncId, username !== '' ? username : server);
  }

  // Suwayomi 可无认证：只要配置了服务器地址即视为已登录
  isLoggedIn(): boolean {
    return this.getUsername() !== '';
  }

  async search(_query: string): Promise<TrackSearchResult[]> {
    // 增强型追踪器不支持标题搜索（对齐 Mihon Suwayomi.search TODO）
    throw new Error('Suwayomi: search unsupported (auto-matched by source)');
  }

  async bind(track: TrackRecord, _hasReadChapters: boolean): Promise<TrackRecord> {
    return track;
  }

  async update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    if (track.status !== SuwayomiTracker.COMPLETED) {
      if (didReadChapter) {
        if (track.lastChapterRead === track.totalChapters && track.totalChapters > 0) {
          track.status = SuwayomiTracker.COMPLETED;
        } else {
          track.status = SuwayomiTracker.READING;
        }
      }
    }
    await this.updateProgress(track);
    const remote = await this.getTrackSearch(track.remoteId);
    this.copyPersonalFromSearch(track, remote);
    return track;
  }

  async refresh(track: TrackRecord): Promise<TrackRecord> {
    const remote = await this.getTrackSearch(track.remoteId);
    this.copyPersonalFromSearch(track, remote);
    return track;
  }

  // ---- EnhancedTracker ----

  acceptsSourceKey(sourceKey: string): boolean {
    return sourceKey.startsWith('suwayomi') || sourceKey.startsWith('tachidesk');
  }

  async match(manga: MangaRecord): Promise<TrackSearchResult | undefined> {
    if (!this.acceptsSourceKey(manga.sourceKey)) {
      return undefined;
    }
    const mangaId = parseInt(manga.url.substring(manga.url.lastIndexOf('/') + 1), 10);
    if (isNaN(mangaId) || mangaId <= 0) {
      return undefined;
    }
    try {
      return await this.getTrackSearch(mangaId);
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

  // 服务器地址（trackUsername_9，去尾部斜杠与 /api）
  private serverUrl(): string {
    return SuwayomiTracker.normalizeServer(this.getUsername());
  }

  // GraphQL 端点
  private graphqlUrl(): string {
    return `${this.serverUrl()}/api/graphql`;
  }

  // 可选 basic auth 头（密码在 Asset Store；无密码则匿名访问）
  private authHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    const password = this.getPassword();
    if (password !== '') {
      headers['Authorization'] = TrackHttp.basic(Settings.getTrackDisplay(this.syncId), password);
    }
    return headers;
  }

  // GraphQL errors 数组非空即抛错
  private checkGraphqlErrors(body: string): void {
    const parsed = JSON.parse(body) as SuwayomiMutationResultRaw;
    if (parsed.errors !== undefined && parsed.errors.length > 0) {
      throw new Error(parsed.errors[0].message ?? 'Suwayomi: graphql error');
    }
  }

  // 条目详情 → TrackSearchResult（对齐 SuwayomiApi.getTrackSearch，字段全量对齐 MangaFragment）
  private async getTrackSearch(mangaId: number): Promise<TrackSearchResult> {
    if (!(mangaId > 0)) {
      throw new Error('Suwayomi: invalid manga id');
    }
    const query = 'query GetManga($mangaId: Int!) { manga(id: $mangaId) { artist author description id ' +
      'status thumbnailUrl title url genre inLibraryAt chapters { totalCount } ' +
      'latestUploadedChapter { uploadDate } latestFetchedChapter { fetchedAt } ' +
      'latestReadChapter { lastReadAt chapterNumber } unreadCount downloadCount } }';
    const resp = await TrackHttp.send('POST', this.graphqlUrl(), this.authHeaders(),
      TrackHttp.graphql(query, `{"mangaId":${mangaId}}`));
    this.checkGraphqlErrors(resp);
    const parsed = JSON.parse(resp) as SuwayomiMangaResultRaw;
    const manga = parsed.data?.manga;
    if (manga === undefined) {
      throw new Error('Suwayomi: manga not found');
    }
    const server = this.serverUrl();
    const r = new TrackSearchResult();
    r.syncId = this.syncId;
    r.remoteId = mangaId;
    r.title = manga.title ?? '';
    r.summary = manga.description ?? '';
    r.publishingStatus = manga.status ?? '';
    const thumbnail = manga.thumbnailUrl ?? '';
    r.coverUrl = thumbnail === '' ? '' : `${server}/${thumbnail.replace(/^\/+/, '')}`;
    r.trackingUrl = `${server}/manga/${mangaId}`;
    const totalCount = manga.chapters?.totalCount ?? 0;
    r.totalChapters = totalCount;
    r.lastChapterRead = manga.latestReadChapter?.chapterNumber ?? 0;
    const unread = manga.unreadCount ?? 0;
    if (unread === totalCount) {
      r.status = SuwayomiTracker.UNREAD;
    } else if (unread === 0) {
      r.status = SuwayomiTracker.COMPLETED;
    } else {
      r.status = SuwayomiTracker.READING;
    }
    return r;
  }

  // 进度更新（对齐 SuwayomiApi.updateProgress）：未读章节过滤 → 批量标记已读 → 上报进度
  private async updateProgress(track: TrackRecord): Promise<void> {
    const mangaId = track.remoteId;
    if (!(mangaId > 0)) {
      throw new Error('Suwayomi: invalid manga id');
    }
    // 1. 未读章节列表
    const unreadQuery = 'query GetMangaUnreadChapters($mangaId: Int!) { chapters(condition: ' +
      '{mangaId: $mangaId, isRead: false}) { nodes { id chapterNumber } } }';
    const unreadResp = await TrackHttp.send('POST', this.graphqlUrl(), this.authHeaders(),
      TrackHttp.graphql(unreadQuery, `{"mangaId":${mangaId}}`));
    this.checkGraphqlErrors(unreadResp);
    const unreadParsed = JSON.parse(unreadResp) as SuwayomiUnreadResultRaw;
    const ids: number[] = [];
    for (const node of unreadParsed.data?.chapters?.nodes ?? []) {
      const id = node.id ?? 0;
      const chapterNumber = node.chapterNumber ?? 0;
      if (id > 0 && chapterNumber <= track.lastChapterRead + 0.001) {
        ids.push(id);
      }
    }
    // 2. 批量标记已读
    if (ids.length > 0) {
      const markQuery = 'mutation MarkChaptersRead($chapters: [Int!]!) { updateChapters(input: ' +
        '{ids: $chapters, patch: {isRead: true}}) { __typename } }';
      const idsJson = `[${ids.join(',')}]`;
      const markResp = await TrackHttp.send('POST', this.graphqlUrl(), this.authHeaders(),
        TrackHttp.graphql(markQuery, `{"chapters":${idsJson}}`));
      this.checkGraphqlErrors(markResp);
    }
    // 3. 上报进度（对齐 mutation TrackManga）
    const trackQuery = 'mutation TrackManga($mangaId: Int!) { trackProgress(input: {mangaId: $mangaId}) ' +
      '{ __typename } }';
    const trackResp = await TrackHttp.send('POST', this.graphqlUrl(), this.authHeaders(),
      TrackHttp.graphql(trackQuery, `{"mangaId":${mangaId}}`));
    this.checkGraphqlErrors(trackResp);
  }
}
