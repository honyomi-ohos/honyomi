import { SManga, SChapter, SPage, MangasPage } from '../model/Models';
import { Source } from './Source';
import { PluginHost } from '../data/PluginHost';

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
}

// 插件返回值（JSON 宽松形态）
interface RawManga {
  key?: string;
  title?: string;
  coverUrl?: string;
  author?: string;
  description?: string;
  genre?: string;
  status?: string;
}

interface RawMangasPage {
  mangas?: RawManga[];
  hasNextPage?: boolean;
}

interface RawChapter {
  key?: string;
  name?: string;
  chapterNumber?: number;
  dateUpload?: number;
  pages?: number;
  sortOrder?: number;
}

interface RawPage {
  index?: number;
  url?: string;
}

// 脚本插件适配器：实现 Source 接口，方法经 Web 桥转发到沙箱内插件
export class PluginSource implements Source {
  readonly key: string;
  readonly name: string;
  readonly lang: string;
  readonly supportsLatest: boolean;
  readonly manifest: PluginManifest;

  constructor(manifest: PluginManifest) {
    this.manifest = manifest;
    this.key = manifest.key;
    this.name = manifest.name;
    this.lang = manifest.lang;
    this.supportsLatest = manifest.supportsLatest;
  }

  async getPopularManga(page: number): Promise<MangasPage> {
    const json = await PluginHost.getInstance().callPlugin(this.key, 'getPopularManga', [page]);
    return PluginSource.toMangasPage(json);
  }

  async getSearchManga(page: number, query: string): Promise<MangasPage> {
    const json = await PluginHost.getInstance().callPlugin(this.key, 'getSearchManga', [page, query]);
    return PluginSource.toMangasPage(json);
  }

  async getMangaDetail(mangaKey: string): Promise<SManga> {
    const json = await PluginHost.getInstance().callPlugin(this.key, 'getMangaDetail', [mangaKey]);
    const raw = JSON.parse(json) as RawManga;
    const manga = PluginSource.toSManga(raw);
    if (manga === undefined) {
      throw new Error('插件详情返回无效');
    }
    return manga;
  }

  async getChapterList(mangaKey: string): Promise<SChapter[]> {
    const json = await PluginHost.getInstance().callPlugin(this.key, 'getChapterList', [mangaKey]);
    const raw = JSON.parse(json) as RawChapter[];
    const chapters: SChapter[] = [];
    if (!Array.isArray(raw)) {
      return chapters;
    }
    for (let i = 0; i < raw.length; i++) {
      const c = PluginSource.toSChapter(raw[i], i);
      if (c !== undefined) {
        chapters.push(c);
      }
    }
    return chapters;
  }

  async getPageList(chapterKey: string): Promise<SPage[]> {
    const json = await PluginHost.getInstance().callPlugin(this.key, 'getPageList', [chapterKey]);
    const raw = JSON.parse(json) as RawPage[];
    const pages: SPage[] = [];
    if (!Array.isArray(raw)) {
      return pages;
    }
    for (let i = 0; i < raw.length; i++) {
      const item = raw[i];
      const url = item.url ?? '';
      if (url === '') {
        continue;
      }
      const page: SPage = { index: i, url: url };
      pages.push(page);
    }
    return pages;
  }

  // ---------------- 宽松 JSON -> 强类型映射 ----------------

  private static toMangasPage(json: string): MangasPage {
    const raw = JSON.parse(json) as RawMangasPage;
    const mangas: SManga[] = [];
    const list = raw.mangas;
    if (Array.isArray(list)) {
      for (let i = 0; i < list.length; i++) {
        const m = PluginSource.toSManga(list[i]);
        if (m !== undefined) {
          mangas.push(m);
        }
      }
    }
    const result: MangasPage = {
      mangas: mangas,
      hasNextPage: raw.hasNextPage === true,
    };
    return result;
  }

  private static toSManga(raw: RawManga): SManga | undefined {
    const key = raw.key ?? '';
    if (key === '') {
      return undefined;
    }
    const manga: SManga = {
      key: key,
      title: raw.title ?? '',
      coverUrl: raw.coverUrl ?? '',
      author: raw.author ?? '',
      description: raw.description ?? '',
      genre: raw.genre ?? '',
      status: raw.status ?? '',
    };
    return manga;
  }

  private static toSChapter(raw: RawChapter, index: number): SChapter | undefined {
    const key = raw.key ?? '';
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
}
