// 追踪器基类与共用工具（对齐 Mihon BaseTracker / Tracker / PkceUtil）
// - 凭据持久化：密码 / OAuth token 经 SecureStore（Asset Store）加密存储；
//   用户名与展示名（非敏感）仍在 Settings trackUsername_/trackDisplay_{syncId}
// - Asset Store 为唯一凭据存储：写入失败直接抛错（调用方 toast），不回退明文
// - token：OAuthToken JSON 存 honyomi.track.token.{syncId}，过期前 60s 视为过期
// - PKCE：随机 32 字节 base64url verifier + S256 challenge
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { MangaRecord, TrackRecord, TrackSearchResult } from '../../model/Models';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { SecureStore } from '../../common/SecureStore';
import { TrackRepo } from '../Repos';
import { Http, RawResponse } from '../../net/Http';

// OAuth token（各追踪器通用：授权码换回的 access/refresh token + 有效期）
export class OAuthToken {
  accessToken: string = '';
  refreshToken: string = '';
  createdAt: number = 0; // epoch 秒
  expiresIn: number = 0; // 秒；<=0 表示未知（不主动判定过期）
  // 绝对过期时间（epoch 秒）；>0 时优先于 createdAt+expiresIn 判定
  expiresAt: number = 0;

  static fromJson(raw: string): OAuthToken | undefined {
    try {
      const parsed = JSON.parse(raw) as OAuthToken;
      if (typeof parsed.accessToken === 'string' && parsed.accessToken !== '') {
        const t = new OAuthToken();
        t.accessToken = parsed.accessToken;
        t.refreshToken = typeof parsed.refreshToken === 'string' ? parsed.refreshToken : '';
        t.createdAt = typeof parsed.createdAt === 'number' ? parsed.createdAt : 0;
        t.expiresIn = typeof parsed.expiresIn === 'number' ? parsed.expiresIn : 0;
        t.expiresAt = typeof parsed.expiresAt === 'number' ? parsed.expiresAt : 0;
        return t;
      }
    } catch (_e) {
    }
    return undefined;
  }

  isExpired(): boolean {
    if (this.expiresAt > 0) {
      return Math.floor(Date.now() / 1000) + 60 > this.expiresAt;
    }
    if (this.expiresIn <= 0) {
      return false;
    }
    return Math.floor(Date.now() / 1000) + 60 > this.createdAt + this.expiresIn;
  }

  toJson(): string {
    return JSON.stringify(this);
  }
}

// PKCE code verifier + S256 challenge
export class PkcePair {
  verifier: string = '';
  challenge: string = '';
}

export class Pkce {
  static async generate(): Promise<PkcePair> {
    const pair = new PkcePair();
    pair.verifier = Pkce.verifier();
    pair.challenge = await Pkce.s256(pair.verifier);
    return pair;
  }

  // 同步生成随机 verifier（plain PKCE / state 参数用）
  static verifier(): string {
    if (canIUse('SystemCapability.Security.CryptoFramework.Rand')) {
      try {
        const random = cryptoFramework.createRandom().generateRandomSync(32);
        return Pkce.b64Url(random.data).replace(/=/g, '');
      } catch (_e) {
      }
    }
    const fallback: number[] = [];
    for (let i = 0; i < 32; i++) {
      fallback.push(Math.floor(Math.random() * 256));
    }
    return Pkce.b64Url(new Uint8Array(fallback)).replace(/=/g, '');
  }

  private static async s256(input: string): Promise<string> {
    if (canIUse('SystemCapability.Security.CryptoFramework.MessageDigest')) {
      try {
        const bytes: Uint8Array = new util.TextEncoder().encodeInto(input);
        const md = cryptoFramework.createMd('SHA256');
        await md.update({ data: bytes });
        const digest = await md.digest();
        return Pkce.b64Url(digest.data).replace(/=/g, '');
      } catch (e) {
        throw new Error(`pkce_failed|${Util.errSummary(e)}`);
      }
    }
    throw new Error('pkce_unsupported');
  }

  private static b64Url(data: Uint8Array): string {
    const helper = new util.Base64Helper();
    return helper.encodeToStringSync(data, util.Type.BASIC_URL_SAFE);
  }
}

// GraphQL 错误项（原始 JSON）
export interface GraphqlErrorRaw {
  message?: string;
}

// 追踪器 HTTP 工具：统一 JSON/表单请求，非 2xx 抛错，404 可选降级 undefined
export class TrackHttp {
  // GraphQL 请求体构造（query 原文转义，variables 为已构造好的 JSON 字符串）
  static graphql(query: string, variables: string): string {
    return `{"query":${JSON.stringify(query)},"variables":${variables}}`;
  }

  // 表单编码（application/x-www-form-urlencoded）
  static formEncode(form: Record<string, string>): string {
    const parts: string[] = [];
    const keys = Object.keys(form);
    for (const k of keys) {
      parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(form[k])}`);
    }
    return parts.join('&');
  }

  static bearer(token: string): Record<string, string> {
    return {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/json',
    };
  }

  // Basic Auth 头（用户名:密码 base64）
  static basic(username: string, password: string): string {
    const raw: Uint8Array = new util.TextEncoder().encodeInto(`${username}:${password}`);
    const helper = new util.Base64Helper();
    return `Basic ${helper.encodeToStringSync(raw, util.Type.BASIC)}`;
  }

  // 非 2xx 抛错；返回响应体
  static async send(method: string, url: string, headers: Record<string, string> | undefined,
    body: string): Promise<string> {
    const resp: RawResponse = await Http.requestRaw(method, url, body, headers);
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`HTTP ${resp.code}: ${resp.body.substring(0, 200)}`);
    }
    return resp.body;
  }

  // 404 → undefined；其余非 2xx 抛错
  static async sendOptional(method: string, url: string, headers: Record<string, string> | undefined,
    body: string): Promise<string | undefined> {
    const resp: RawResponse = await Http.requestRaw(method, url, body, headers);
    if (resp.code === 404) {
      return undefined;
    }
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`HTTP ${resp.code}: ${resp.body.substring(0, 200)}`);
    }
    return resp.body;
  }
}

// 追踪器日期工具：epoch 毫秒 ↔ ISO yyyy-MM-dd
export class TrackDate {
  static toIsoDate(epochMs: number): string {
    if (epochMs <= 0) {
      return '';
    }
    const d = new Date(epochMs);
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }

  // 支持 yyyy-MM-dd / yyyy-MM / yyyy；非法或空返回 0
  static parseIsoDate(iso: string | undefined | null): number {
    if (typeof iso !== 'string' || iso === '') {
      return 0;
    }
    const parts = iso.split('-');
    const year = parseInt(parts[0], 10);
    if (isNaN(year)) {
      return 0;
    }
    const month = parts.length > 1 ? parseInt(parts[1], 10) : 1;
    const day = parts.length > 2 ? parseInt(parts[2], 10) : 1;
    return new Date(year, isNaN(month) ? 0 : month - 1, isNaN(day) ? 1 : day).getTime();
  }

  static nowSec(): number {
    return Math.floor(Date.now() / 1000);
  }
}

// 追踪器抽象基类（对齐 Mihon Tracker 接口）
export abstract class Tracker {
  readonly syncId: number;
  readonly name: string;
  // 品牌色（TrackLogo 徽标底色）
  readonly brandColor: string;
  supportsReadingDates: boolean = false;
  supportsPrivateTracking: boolean = false;

  constructor(syncId: number, name: string, brandColor: string) {
    this.syncId = syncId;
    this.name = name;
    this.brandColor = brandColor;
  }

  // ---- 凭据 ----
  // Asset Store 别名（密码 / token 各一条，syncId 保证唯一）
  static passwordAlias(syncId: number): string {
    return `honyomi.track.pass.${syncId}`;
  }

  static tokenAlias(syncId: number): string {
    return `honyomi.track.token.${syncId}`;
  }

  getUsername(): string {
    return Settings.getTrackUsername(this.syncId);
  }

  // 密码 / OAuth access token：仅存 Asset Store
  getPassword(): string {
    return SecureStore.getSync(Tracker.passwordAlias(this.syncId));
  }

  getDisplayUsername(): string {
    const display = Settings.getTrackDisplay(this.syncId);
    return display !== '' ? display : this.getUsername();
  }

  // 写入失败（Asset 服务异常 / secret 超 1024 字节）抛错，由登录流程 toast
  saveCredentials(username: string, password: string): void {
    Settings.setTrackUsername(this.syncId, username);
    if (!SecureStore.putSync(Tracker.passwordAlias(this.syncId), password)) {
      throw new Error('secure_store_unavailable');
    }
  }

  isLoggedIn(): boolean {
    return this.getUsername() !== '' && this.getPassword() !== '';
  }

  logout(): void {
    Settings.setTrackUsername(this.syncId, '');
    Settings.setTrackDisplay(this.syncId, '');
    SecureStore.removeSync(Tracker.passwordAlias(this.syncId));
    SecureStore.removeSync(Tracker.tokenAlias(this.syncId));
  }

  // ---- OAuth token 存储 ----
  saveToken(token: OAuthToken): void {
    if (!SecureStore.putSync(Tracker.tokenAlias(this.syncId), token.toJson())) {
      throw new Error('secure_store_unavailable');
    }
  }

  loadToken(): OAuthToken | undefined {
    return OAuthToken.fromJson(SecureStore.getSync(Tracker.tokenAlias(this.syncId)));
  }

  // ---- 增强型追踪器（对齐 Mihon EnhancedTracker）----
  // 是否增强型：仅与特定源绑定，按 sourceKey + url 自动匹配（无需用户搜索）
  isEnhanced: boolean = false;

  // 增强型：是否接受该源（sourceKey 前缀约定由各追踪器实现）
  acceptsSourceKey(_sourceKey: string): boolean {
    return false;
  }

  // 增强型：按漫画记录自动匹配远端条目（零或一条结果）；不匹配返回 undefined
  async match(_manga: MangaRecord): Promise<TrackSearchResult | undefined> {
    return undefined;
  }

  // 自托管服务器型登录：服务器地址 + 可选用户名/密钥（非服务器型追踪器抛错）
  // 服务器地址存 Settings trackUsername_{syncId}；密码/密钥经 saveCredentials 入 Asset Store
  async loginWithServer(_serverUrl: string, _username: string, _secret: string): Promise<void> {
    throw new Error('unsupported');
  }

  // ---- 抽象接口 ----
  abstract getStatusList(): number[];

  // 状态显示文案（本地化资源）
  abstract getStatusLabel(status: number): ResourceStr;

  abstract getReadingStatus(): number;

  abstract getRereadingStatus(): number;

  abstract getCompletionStatus(): number;

  // 评分选项列表（原生分值字符串）
  abstract getScoreList(): string[];

  // 评分列表索引 → 原生分值
  abstract indexToScore(index: number): number;

  // 原生分值 → 评分列表索引（选中态回显）
  abstract scoreIndex(score: number): number;

  abstract displayScore(track: TrackRecord): string;

  abstract search(query: string): Promise<TrackSearchResult[]>;

  abstract bind(track: TrackRecord, hasReadChapters: boolean): Promise<TrackRecord>;

  abstract update(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord>;

  abstract refresh(track: TrackRecord): Promise<TrackRecord>;

  // OAuth 授权地址（'' 表示用户名密码登录型追踪器）
  abstract getAuthUrl(): Promise<string>;

  // OAuth 授权码登录
  abstract loginWithCode(code: string): Promise<void>;

  // 用户名密码登录（OAuth 型追踪器抛错）
  abstract loginWithCredentials(username: string, password: string): Promise<void>;

  // 远端删除条目（不支持删除的追踪器抛错）
  async deleteRemote(_track: TrackRecord): Promise<void> {
    throw new Error('unsupported');
  }

  // 绑定新条目：从搜索结果构造记录 → bind（远端存在则合并远端状态）→ 落库
  async register(item: TrackSearchResult, mangaId: number, hasReadChapters: boolean): Promise<TrackRecord> {
    const track = new TrackRecord();
    track.mangaId = mangaId;
    track.syncId = this.syncId;
    track.remoteId = item.remoteId;
    track.libraryId = item.libraryId;
    track.title = item.title;
    track.totalChapters = item.totalChapters;
    track.remoteUrl = item.trackingUrl;
    track.status = item.status;
    track.score = 0;
    track.lastChapterRead = item.lastChapterRead;
    track.startDate = item.startReadDate;
    track.finishDate = item.finishReadDate;
    track.isPrivate = item.isPrivate;
    const bound = await this.bind(track, hasReadChapters);
    await TrackRepo.upsert(bound);
    return bound;
  }

  // ---- 共用工具 ----

  async setRemoteStatus(track: TrackRecord, status: number): Promise<TrackRecord> {
    track.status = status;
    if (track.status === this.getCompletionStatus() && track.totalChapters !== 0) {
      track.lastChapterRead = track.totalChapters;
    }
    return this.updateAndSave(track, false);
  }

  // ---- 注册与字段更新（落库）----

  async setRemoteLastChapterRead(track: TrackRecord, chapterNumber: number): Promise<TrackRecord> {
    if (track.lastChapterRead === 0 && track.status !== this.getRereadingStatus()) {
      track.status = this.getReadingStatus();
    }
    track.lastChapterRead = chapterNumber;
    if (track.totalChapters !== 0 && track.lastChapterRead >= track.totalChapters) {
      track.status = this.getCompletionStatus();
      track.finishDate = Date.now();
    }
    return this.updateAndSave(track, true);
  }

  async setRemoteScore(track: TrackRecord, index: number): Promise<TrackRecord> {
    track.score = this.indexToScore(index);
    return this.updateAndSave(track, false);
  }

  async setRemoteStartDate(track: TrackRecord, epochMs: number): Promise<TrackRecord> {
    track.startDate = epochMs;
    return this.updateAndSave(track, false);
  }

  async setRemoteFinishDate(track: TrackRecord, epochMs: number): Promise<TrackRecord> {
    track.finishDate = epochMs;
    return this.updateAndSave(track, false);
  }

  async setRemotePrivate(track: TrackRecord, isPrivate: boolean): Promise<TrackRecord> {
    track.isPrivate = isPrivate;
    return this.updateAndSave(track, false);
  }

  // update + 落库；失败抛错（调用方 toast）
  async updateAndSave(track: TrackRecord, didReadChapter: boolean): Promise<TrackRecord> {
    const updated = await this.update(track, didReadChapter);
    await TrackRepo.upsert(updated);
    return updated;
  }

  // 取有效 token：缺失抛错；过期时用 refreshFn 刷新并保存（refreshFn 返回新 token）
  protected async ensureToken(refreshFn: (token: OAuthToken) => Promise<OAuthToken>): Promise<OAuthToken> {
    const token = this.loadToken();
    if (token === undefined) {
      throw new Error(`${this.name}: not logged in`);
    }
    if (token.isExpired()) {
      const refreshed = await refreshFn(token);
      this.saveToken(refreshed);
      return refreshed;
    }
    return token;
  }

  // 从远端记录拷贝个人进度字段（对齐 Mihon Track.copyPersonalFrom）
  protected copyPersonalFrom(track: TrackRecord, remote: TrackRecord, copyRemotePrivate: boolean = true): void {
    track.status = remote.status;
    track.lastChapterRead = remote.lastChapterRead;
    track.score = remote.score;
    track.startDate = remote.startDate;
    track.finishDate = remote.finishDate;
    if (copyRemotePrivate) {
      track.isPrivate = remote.isPrivate;
    }
  }

  // 从搜索结果拷贝个人进度字段（增强型追踪器 refresh/update：远端状态即 TrackSearchResult）
  protected copyPersonalFromSearch(track: TrackRecord, remote: TrackSearchResult): void {
    track.status = remote.status;
    track.lastChapterRead = remote.lastChapterRead;
    track.score = remote.score;
    track.startDate = remote.startReadDate;
    track.finishDate = remote.finishReadDate;
    track.totalChapters = remote.totalChapters;
  }
}
