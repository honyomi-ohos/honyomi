import { SManga, SChapter, SPage, MangasPage } from '../model/Models';

// 漫画源抽象接口（对齐 Mihon source-api 的 Source，P1 精简版）
export interface Source {
  readonly key: string;
  readonly name: string;
  readonly lang: string;
  readonly supportsLatest: boolean;

  getPopularManga(page: number): Promise<MangasPage>;
  getSearchManga(page: number, query: string): Promise<MangasPage>;
  getMangaDetail(mangaKey: string): Promise<SManga>;
  getChapterList(mangaKey: string): Promise<SChapter[]>;
  getPageList(chapterKey: string): Promise<SPage[]>;
}

// 源注册表（内置源编译期注册；插件源运行期动态注册/注销）
export class SourceRegistry {
  private static sources: Source[] = [];

  static register(source: Source): void {
    SourceRegistry.unregister(source.key);
    SourceRegistry.sources.push(source);
  }

  static unregister(key: string): void {
    const kept: Source[] = [];
    for (const s of SourceRegistry.sources) {
      if (s.key !== key) {
        kept.push(s);
      }
    }
    SourceRegistry.sources = kept;
  }

  static all(): Source[] {
    return SourceRegistry.sources;
  }

  static get(key: string): Source | undefined {
    for (const s of SourceRegistry.sources) {
      if (s.key === key) {
        return s;
      }
    }
    return undefined;
  }
}
