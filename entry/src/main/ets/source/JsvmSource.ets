import { SManga, SChapter, SPage, MangasPage } from '../model/Models';
import { Source } from './Source';
import { JsvmExtensionManager } from '../jsvm/JsvmExtensionManager';
import { WebChallengeError } from '../jsvm/NativeHttpBridge';
import { Http } from '../net/Http';

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
}

// JSVM 插件适配器：实现 Source 接口，方法经专属 Worker 转发到隔离 JSVM 引擎
export class JsvmSource implements Source {
  readonly key: string;
  readonly name: string;
  readonly lang: string;
  readonly supportsLatest: boolean;
  readonly manifest: PluginManifest;

  private exportedMethods: string[] = [];
  private customImageHeaders: Record<string, string> | undefined = undefined;
  private imageViaHost: boolean = false;

  constructor(manifest: PluginManifest, exportedMethods: string[] = []) {
    this.manifest = manifest;
    this.key = manifest.key;
    this.name = manifest.name;
    this.lang = manifest.lang;
    this.exportedMethods = exportedMethods;
    this.supportsLatest = manifest.supportsLatest && exportedMethods.indexOf('getLatestManga') >= 0;
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

  async getPopularManga(page: number): Promise<MangasPage> {
    const raw = await this.call<RawMangasPage>('getPopularManga', [page]);
    return JsvmSource.toMangasPage(raw);
  }

  async getLatestManga(page: number): Promise<MangasPage> {
    if (this.supportsLatest) {
      const raw = await this.call<RawMangasPage>('getLatestManga', [page]);
      return JsvmSource.toMangasPage(raw);
    }
    return this.getPopularManga(page);
  }

  async getSearchManga(page: number, query: string): Promise<MangasPage> {
    const raw = await this.call<RawMangasPage>('getSearchManga', [page, query]);
    return JsvmSource.toMangasPage(raw);
  }

  async getMangaDetail(mangaKey: string): Promise<SManga> {
    const raw = await this.call<RawManga | undefined>('getMangaDetail', [mangaKey]);
    const manga = JsvmSource.toSManga(raw);
    if (manga === undefined) {
      throw new Error('插件详情返回无效');
    }
    return manga;
  }

  async getChapterList(mangaKey: string): Promise<SChapter[]> {
    const raw = await this.call<RawChapter[]>('getChapterList', [mangaKey]);
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
    const raw = await this.call<RawPage[]>('getPageList', [chapterKey]);
    const pages: SPage[] = [];
    if (!Array.isArray(raw)) {
      return pages;
    }
    for (let i = 0; i < raw.length; i++) {
      const item = raw[i];
      const url = item.imageUrl ?? item.url ?? '';
      if (url === '') {
        continue;
      }
      const page: SPage = { index: item.index ?? i, url: url };
      pages.push(page);
    }
    return pages;
  }

  // ---------------- 内部实现 ----------------

  // 统一调用入口：CF 盾挑战异常上抛前触发全局验证页
  private async call<T>(method: string, args: Array<string | number>): Promise<T> {
    try {
      return await JsvmExtensionManager.callData<T>(this.key, method, args);
    } catch (e) {
      if (e instanceof WebChallengeError) {
        AppStorage.setOrCreate('cfChallengeUrl', e.challengeUrl);
      }
      throw e as Error;
    }
  }

  // 插件可选导出 getHeaders：声明后图片经宿主 http 管线加载（Referer/Cookie）
  warmImageHeaders(): void {
    if (this.exportedMethods.indexOf('getHeaders') < 0) {
      return;
    }
    JsvmExtensionManager.callData<Record<string, Object>>(this.key, 'getHeaders', [])
      .then((raw: Record<string, Object>) => {
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
      .catch((_e: Error) => {
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

  // tachiyomi MangaStatus 枚举 -> 展示文本
  private static toStatus(status: number | string | undefined): string {
    if (status === undefined) {
      return '';
    }
    if (typeof status === 'string') {
      return status as string;
    }
    switch (status as number) {
      case 1:
        return '连载中';
      case 2:
        return '已完结';
      case 3:
        return '已授权';
      case 4:
        return '出版完毕';
      case 5:
        return '已取消';
      case 6:
        return '休刊';
      default:
        return '未知';
    }
  }
}
