import { SManga, SChapter, SPage, SVideo, MangasPage, ContentType } from '../model/Models';
import { Source } from './Source';
import { JsvmExtensionManager } from '../jsvm/JsvmExtensionManager';
import { WebChallengeError } from '../jsvm/NativeHttpBridge';
import { Http } from '../net/Http';
import { util } from '@kit.ArkTS';

// 插件包 manifest.json 模型（宽松字段，解析时校验必填项）
export interface PluginManifest {
  key: string;
  name: string;
  lang: string;
  version: string;
  versionCode: number;
  baseUrl: string;
  nsfw: boolean;
  supportsLatest: boolean;
  minAppVersion: number;
  dslVersion: number;
  // 可选：插件包内图标文件名（如 icon.png）
  icon: string;
  // 可选：共享运行时名（如 'wp'）——非空时 App 在 main.js 前拼接 rawfile plugin_runtime_<name>.js
  runtime: string;
  // 执行引擎：唯一合法值 'jsvm'（纯 JSVM 隔离引擎，本机 C++ JSVM + Worker）
  engine: string;
  // manga | novel | video，缺省 manga
  contentType: string;
}

// 插件返回值（宽松 JSON 形态，兼容 tachiyomi 编译产物与简单契约两种 key 命名）
interface RawManga {
  key?: string;
  url?: string;
  title?: string;
  coverUrl?: string;
  thumbnailUrl?: string;
  author?: string;
  artist?: string;
  description?: string;
  genre?: string[] | string;
  status?: number | string;
}

interface RawMangasPage {
  mangas?: RawManga[];
  hasNextPage?: boolean;
}

interface RawChapter {
  key?: string;
  url?: string;
  name?: string;
  chapterNumber?: number;
  dateUpload?: number;
  scanlator?: string;
  pages?: number;
  sortOrder?: number;
}

interface RawPage {
  index?: number;
  url?: string;
  imageUrl?: string;
  pageUrl?: string;
}

interface RawTextBody {
  text?: string;
  content?: string;
}

interface RawVideo {
  url?: string;
  quality?: string;
  headers?: Record<string, Object>;
}

// 插件设置项（getSettingsSchema 契约：type = 'switch' | 'select' | 'edit'）
export interface SourcePrefOption {
  value: string;
  label: string;
}

export interface SourcePrefItem {
  type: string;
  key: string;
  title: string;
  summary: string;
  value: string;
  options: SourcePrefOption[];
}

interface RawPrefOption {
  value?: string;
  label?: string;
}

interface RawPrefItem {
  type?: string;
  key?: string;
  title?: string;
  summary?: string;
  value?: string | boolean | number;
  defaultValue?: string | boolean | number;
  default?: string | boolean | number | string[];
  options?: RawPrefOption[];
  values?: string[];
  titles?: string[];
}

// tachiyomi-js getManifest() 里的单个源
export interface CompiledSourceInfo {
  id?: string;
  name?: string;
  lang?: string;
  baseUrl?: string;
  supportsLatest?: boolean;
}

// JSVM 插件适配器：实现 Source 接口，方法经专属 Worker 转发到隔离 JSVM 引擎
export class JsvmSource implements Source {
  readonly key: string;
  readonly name: string;
  readonly lang: string;
  readonly supportsLatest: boolean;
  readonly contentType: string;
  readonly manifest: PluginManifest;
  // 插件包目录名。多语言扩展共用一个 JSVM 引擎，浏览列表里每个语言各有自己的 key。
  readonly packageKey: string;
  // tachiyomi 编译产物的 source id；空字符串表示简单契约插件。
  readonly sourceId: string;
  // 插件图标（file:// 路径）；空字符串表示包内无图标
  readonly iconPath: string;

  private exportedMethods: string[] = [];
  private customImageHeaders: Record<string, string> | undefined = undefined;
  private imageViaHost: boolean = false;
  // getHeaders 预热的 Promise 缓存：并发去重，调用方可 await 保证首图带 Referer/Cookie
  private warmHeadersPromise: Promise<void> | undefined = undefined;

  constructor(manifest: PluginManifest, exportedMethods: string[] = [], packageKey: string = '',
    sourceId: string = '', iconPath: string = '') {
    this.manifest = manifest;
    this.key = manifest.key;
    this.name = manifest.name;
    this.lang = manifest.lang;
    this.packageKey = packageKey !== '' ? packageKey : manifest.key;
    this.sourceId = sourceId;
    this.iconPath = iconPath;
    this.exportedMethods = exportedMethods;
    this.supportsLatest = manifest.supportsLatest && exportedMethods.indexOf('getLatestManga') >= 0;
    this.contentType = ContentType.normalize(manifest.contentType);
  }

  setImageHeaders(headers: Record<string, string> | undefined): void {
    if (headers === undefined) {
      this.imageViaHost = false;
      this.customImageHeaders = undefined;
    } else {
      this.imageViaHost = true;
      this.customImageHeaders = headers;
    }
  }

  imageRequestHeaders(): Record<string, string> | undefined {
    if (!this.imageViaHost) {
      return undefined;
    }
    const merged: Record<string, string> = { 'User-Agent': Http.USER_AGENT };
    if (this.customImageHeaders !== undefined) {
      const keys = Object.keys(this.customImageHeaders);
      for (const k of keys) {
        merged[k] = this.customImageHeaders[k];
      }
    }
    return merged;
  }

  async fetchPageImage(pageUrl: string, imageUrl: string): Promise<ArrayBuffer | undefined> {
    if (this.exportedMethods.indexOf('fetchImage') < 0) {
      return undefined;
    }
    const raw = await this.call<string>('fetchImage', this.callArgs([pageUrl, imageUrl]));
    if (raw === undefined || raw === '') {
      return undefined;
    }
    const helper = new util.Base64Helper();
    const bytes = helper.decodeSync(raw);
    return bytes.buffer;
  }

  async getFilterList(): Promise<object[]> {
    if (this.exportedMethods.indexOf('getFilterList') < 0) {
      return [];
    }
    const raw = await this.call<object[]>('getFilterList', this.callArgs([]));
    return Array.isArray(raw) ? raw : [];
  }

  async applyFilterState(state: object[]): Promise<void> {
    if (this.exportedMethods.indexOf('applyFilterState') < 0) {
      return;
    }
    await this.call<object>('applyFilterState', this.callArgs([JSON.stringify(state)]));
  }

  async resetFilters(): Promise<void> {
    if (this.exportedMethods.indexOf('resetFilters') < 0) {
      return;
    }
    await this.call<object>('resetFilters', this.callArgs([]));
  }

  async setPreference(key: string, value: string): Promise<void> {
    if (this.exportedMethods.indexOf('setPreference') < 0) {
      return;
    }
    await this.call<object>('setPreference', this.callArgs([key, value]));
  }

  // 插件是否导出某方法（用于设置页判断源是否可配置）
  hasMethod(name: string): boolean {
    return this.exportedMethods.indexOf(name) >= 0;
  }

  // 插件设置声明（getSettingsSchema）：设置页据此渲染 switch/select/edit 行
  async getSettingsSchema(): Promise<SourcePrefItem[]> {
    if (this.exportedMethods.indexOf('getSettingsSchema') < 0) {
      return [];
    }
    const raw = await this.call<object>('getSettingsSchema', this.callArgs([]));
    const list = JsvmSource.prefListOf(raw);
    const items: SourcePrefItem[] = [];
    for (const r of list) {
      const item = JsvmSource.toPrefItem(r);
      if (item !== undefined) {
        items.push(item);
      }
    }
    return items;
  }

  private static prefValueToString(v: string | boolean | number | undefined): string {
    if (v === undefined) {
      return '';
    }
    if (typeof v === 'string') {
      return v;
    }
    return `${v}`;
  }

  // tachiyomi-js 把 schema 再包成 JSON 字符串，字段是 type/values/titles/default。
  private static prefListOf(raw: object): RawPrefItem[] {
    let text = '';
    if (typeof raw === 'string') {
      text = raw;
    } else {
      try {
        text = JSON.stringify(raw);
      } catch (e) {
        return [];
      }
    }
    try {
      const parsed = JSON.parse(text) as RawPrefItem[];
      if (Array.isArray(parsed)) {
        return parsed;
      }
    } catch (e) {
      return [];
    }
    return [];
  }

  private static toPrefItem(raw: RawPrefItem | undefined): SourcePrefItem | undefined {
    if (raw === undefined || raw.key === undefined || raw.key === '') {
      return undefined;
    }
    const options: SourcePrefOption[] = [];
    if (Array.isArray(raw.options)) {
      for (const o of raw.options) {
        if (o !== undefined && o.value !== undefined) {
          const opt: SourcePrefOption = {
            value: o.value,
            label: o.label ?? o.value,
          };
          options.push(opt);
        }
      }
    } else if (Array.isArray(raw.values)) {
      for (let i = 0; i < raw.values.length; i++) {
        const value = raw.values[i];
        const label = raw.titles !== undefined && i < raw.titles.length ? raw.titles[i] : value;
        const opt: SourcePrefOption = { value: value, label: label };
        options.push(opt);
      }
    }
    let stored: string | boolean | number | undefined = raw.value;
    if (stored === undefined && typeof raw.default === 'string') {
      stored = raw.default;
    } else if (stored === undefined && typeof raw.default === 'boolean') {
      stored = raw.default;
    } else if (stored === undefined && typeof raw.default === 'number') {
      stored = raw.default;
    }
    if (stored === undefined) {
      stored = raw.defaultValue;
    }
    let type = raw.type ?? 'switch';
    if (type === 'text') {
      type = 'edit';
    } else if (type === 'multi-select') {
      type = 'select';
    }
    const item: SourcePrefItem = {
      type: type,
      key: raw.key,
      title: raw.title ?? raw.key,
      summary: raw.summary ?? '',
      value: JsvmSource.prefValueToString(stored),
      options: options,
    };
    return item;
  }

  async getPopularManga(page: number): Promise<MangasPage> {
    const raw = await this.call<RawMangasPage>('getPopularManga', this.callArgs([page]));
    return JsvmSource.toMangasPage(raw);
  }

  async getLatestManga(page: number): Promise<MangasPage> {
    if (this.supportsLatest) {
      const raw = await this.call<RawMangasPage>('getLatestManga', this.callArgs([page]));
      return JsvmSource.toMangasPage(raw);
    }
    return this.getPopularManga(page);
  }

  async getSearchManga(page: number, query: string): Promise<MangasPage> {
    const raw = await this.call<RawMangasPage>('getSearchManga', this.callArgs([page, query]));
    return JsvmSource.toMangasPage(raw);
  }

  async getMangaDetail(mangaKey: string): Promise<SManga> {
    const raw = await this.call<RawManga | undefined>('getMangaDetail', this.callArgs([mangaKey]));
    const manga = JsvmSource.toSManga(raw);
    if (manga === undefined) {
      throw new Error('plugin_invalid_detail');
    }
    return manga;
  }

  async getChapterList(mangaKey: string): Promise<SChapter[]> {
    const raw = await this.call<RawChapter[]>('getChapterList', this.callArgs([mangaKey]));
    const chapters: SChapter[] = [];
    if (!Array.isArray(raw)) {
      return chapters;
    }
    for (let i = 0; i < raw.length; i++) {
      const c = JsvmSource.toSChapter(raw[i], i);
      if (c !== undefined) {
        chapters.push(c);
      }
    }
    return chapters;
  }

  async getPageList(chapterKey: string): Promise<SPage[]> {
    const raw = await this.call<RawPage[]>('getPageList', this.callArgs([chapterKey]));
    const pages: SPage[] = [];
    if (!Array.isArray(raw)) {
      return pages;
    }
    for (let i = 0; i < raw.length; i++) {
      const item = raw[i];
      const imageUrl = item.imageUrl ?? item.url ?? '';
      if (imageUrl === '') {
        continue;
      }
      let chapterUrl = item.pageUrl ?? '';
      if (chapterUrl === '' && item.imageUrl !== undefined && item.imageUrl !== '') {
        chapterUrl = item.url ?? '';
      }
      const page: SPage = {
        index: item.index ?? i,
        url: imageUrl,
        pageUrl: chapterUrl,
      };
      pages.push(page);
    }
    return pages;
  }

  async getChapterText(chapterKey: string): Promise<string> {
    if (this.exportedMethods.indexOf('getChapterText') < 0) {
      if (this.contentType === ContentType.NOVEL) {
        throw new Error('plugin_no_chapter_text');
      }
      return '';
    }
    const raw: Object = await this.call<Object>('getChapterText', this.callArgs([chapterKey]));
    return JsvmSource.textFromRaw(raw);
  }

  async getVideoList(chapterKey: string): Promise<SVideo[]> {
    if (this.exportedMethods.indexOf('getVideoList') < 0) {
      if (this.contentType === ContentType.VIDEO) {
        throw new Error('plugin_no_video_list');
      }
      return [];
    }
    const raw: Object = await this.call<Object>('getVideoList', this.callArgs([chapterKey]));
    return JsvmSource.videosFromRaw(raw);
  }

  // ---------------- 内部实现 ----------------

  // 统一调用入口：CF 盾挑战异常上抛前触发全局验证页
  // 编译产物按 sourceId 选源；简单契约插件不传这个前缀参数。
  private callArgs(args: Array<string | number | boolean | object>): Array<string | number | boolean | object> {
    if (this.sourceId === '') {
      return args;
    }
    const next: Array<string | number | boolean | object> = [this.sourceId];
    for (const item of args) {
      next.push(item);
    }
    return next;
  }

  private async call<T>(method: string, args: Array<string | number | boolean | object>): Promise<T> {
    try {
      return await JsvmExtensionManager.callData<T>(this.packageKey, method, args);
    } catch (e) {
      if (e instanceof WebChallengeError) {
        AppStorage.setOrCreate('cfChallengeUrl', e.challengeUrl);
        // 挂起等待用户在验证页完成质询：通过后 cfVerifiedTick 增长，携新
        // cf_clearance 自动重试一次；用户放弃（验证页关闭未通过）则原样上抛
        const solved = await JsvmSource.waitChallengeSolved();
        if (solved) {
          return await JsvmExtensionManager.callData<T>(this.packageKey, method, args);
        }
      }
      throw e as Error;
    }
  }

  // 轮询等待 CF 验证结果：cfVerifiedTick 增长代表通过；cfChallengeUrl 复空代表放弃；
  // 上限 2 分钟（验证页超时关闭后调用方收到原始错误）。
  // 并发去重：模块级共享同一轮询/等待 promise，多处调用同时挂起时只跑一个轮询。
  private static challengeWait: Promise<boolean> | undefined = undefined;

  private static waitChallengeSolved(): Promise<boolean> {
    if (JsvmSource.challengeWait === undefined) {
      JsvmSource.challengeWait = JsvmSource.pollChallengeSolved();
    }
    return JsvmSource.challengeWait;
  }

  private static pollChallengeSolved(): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      const startTick = AppStorage.get<number>('cfVerifiedTick') ?? 0;
      const deadline = Date.now() + 120000;
      const timer = setInterval(() => {
        const tick = AppStorage.get<number>('cfVerifiedTick') ?? 0;
        if (tick > startTick) {
          clearInterval(timer);
          JsvmSource.challengeWait = undefined;
          resolve(true);
          return;
        }
        const url = AppStorage.get<string>('cfChallengeUrl') ?? '';
        if (url === '' || Date.now() > deadline) {
          clearInterval(timer);
          JsvmSource.challengeWait = undefined;
          resolve(false);
        }
      }, 500);
    });
  }

  private static textFromRaw(raw: Object): string {
    if (typeof raw === 'string') {
      return raw as string;
    }
    if (raw === null || raw === undefined) {
      return '';
    }
    // 已是反序列化对象：直接按字段取，避免 JSON 双重往返
    const body = raw as RawTextBody;
    return body.text ?? body.content ?? '';
  }

  private static videosFromRaw(raw: Object): SVideo[] {
    if (raw === null || raw === undefined) {
      return [];
    }
    const parsed = raw as RawVideo[];
    const videos: SVideo[] = [];
    if (!Array.isArray(parsed)) {
      return videos;
    }
    for (let i = 0; i < parsed.length; i++) {
      const item = parsed[i];
      const url = item.url ?? '';
      if (url === '') {
        continue;
      }
      const video: SVideo = {
        url: url,
        quality: item.quality !== undefined && item.quality !== '' ? item.quality : `${i + 1}`,
        headers: JsvmSource.headerMap(item.headers),
      };
      videos.push(video);
    }
    return videos;
  }

  private static headerMap(raw: Record<string, Object> | undefined): Record<string, string> {
    const headers: Record<string, string> = {};
    if (raw === undefined) {
      return headers;
    }
    const keys = Object.keys(raw);
    for (let i = 0; i < keys.length; i++) {
      const v = raw[keys[i]];
      if (typeof v === 'string') {
        headers[keys[i]] = v as string;
      }
    }
    return headers;
  }

  // 插件可选导出 getHeaders：声明后图片经宿主 http 管线加载（Referer/Cookie）。
  // 可等待 + 并发去重：Promise 缓存使多次调用共享同一次 getHeaders 请求，
  // 调用方 await 后可保证图片首请求带上 Referer/Cookie。
  warmImageHeaders(): Promise<void> {
    if (this.warmHeadersPromise === undefined) {
      this.warmHeadersPromise = this.doWarmImageHeaders();
    }
    return this.warmHeadersPromise;
  }

  private doWarmImageHeaders(): Promise<void> {
    if (this.exportedMethods.indexOf('getHeaders') < 0) {
      return Promise.resolve();
    }
    return JsvmExtensionManager.callData<Record<string, Object>>(this.packageKey, 'getHeaders', this.callArgs([]))
      .then((raw: Record<string, Object>): void => {
        const keys = Object.keys(raw);
        const headers: Record<string, string> = {};
        for (const k of keys) {
          const v = raw[k];
          if (typeof v === 'string') {
            headers[k] = v;
          }
        }
        this.setImageHeaders(headers);
      })
      .catch((_e: Error): void => {
        // 插件未有效导出 getHeaders：直连加载
      });
  }

  private static toMangasPage(raw: RawMangasPage | undefined): MangasPage {
    const mangas: SManga[] = [];
    if (raw !== undefined && Array.isArray(raw.mangas)) {
      for (let i = 0; i < raw.mangas.length; i++) {
        const m = JsvmSource.toSManga(raw.mangas[i]);
        if (m !== undefined) {
          mangas.push(m);
        }
      }
    }
    const result: MangasPage = {
      mangas: mangas,
      hasNextPage: raw !== undefined && raw.hasNextPage === true,
    };
    return result;
  }

  private static toSManga(raw: RawManga | undefined): SManga | undefined {
    if (raw === undefined) {
      return undefined;
    }
    const key = raw.key ?? raw.url ?? '';
    if (key === '') {
      return undefined;
    }
    const manga: SManga = {
      key: key,
      title: raw.title ?? '',
      coverUrl: raw.coverUrl ?? raw.thumbnailUrl ?? '',
      author: raw.author ?? raw.artist ?? '',
      description: raw.description ?? '',
      genre: JsvmSource.toGenre(raw.genre),
      status: JsvmSource.toStatus(raw.status),
    };
    return manga;
  }

  private static toSChapter(raw: RawChapter | undefined, index: number): SChapter | undefined {
    if (raw === undefined) {
      return undefined;
    }
    const key = raw.key ?? raw.url ?? '';
    if (key === '') {
      return undefined;
    }
    const chapter: SChapter = {
      key: key,
      name: raw.name ?? '',
      chapterNumber: raw.chapterNumber ?? -1,
      dateUpload: raw.dateUpload ?? 0,
      pages: raw.pages ?? 0,
      sortOrder: raw.sortOrder !== undefined ? raw.sortOrder : index,
    };
    return chapter;
  }

  private static toGenre(genre: string[] | string | undefined): string {
    if (genre === undefined) {
      return '';
    }
    if (Array.isArray(genre)) {
      return (genre as string[]).join(', ');
    }
    return genre as string;
  }

  // tachiyomi MangaStatus 枚举 -> 状态 code（显示层经 Util.statusLabel 资源映射）
  private static toStatus(status: number | string | undefined): string {
    if (status === undefined) {
      return '';
    }
    if (typeof status === 'string') {
      return status as string;
    }
    switch (status as number) {
      case 1:
        return 'ongoing';
      case 2:
        return 'completed';
      case 3:
        return 'licensed';
      case 4:
        return 'publication_complete';
      case 5:
        return 'cancelled';
      case 6:
        return 'hiatus';
      default:
        return 'unknown';
    }
  }
}
