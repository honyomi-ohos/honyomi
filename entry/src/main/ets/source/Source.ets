import { SManga, SChapter, SPage, SVideo, MangasPage } from '../model/Models';

// 源抽象接口。contentType 为 manga / novel / video，缺省实现视为漫画。
// 漫画走 getPageList；小说走 getChapterText；视频走 getVideoList。宿主只按类型调用。
export interface Source {
  readonly key: string;
  readonly name: string;
  readonly lang: string;
  readonly supportsLatest: boolean;
  readonly contentType: string;
  // 源图标（file:// 路径或网络 URL）；空字符串表示无图标，由 UI 回退首字母
  readonly iconPath: string;

  getPopularManga(page: number): Promise<MangasPage>;
  // 最新更新（supportsLatest 为 false 时宿主不会调用）
  getLatestManga(page: number): Promise<MangasPage>;
  getSearchManga(page: number, query: string): Promise<MangasPage>;
  getMangaDetail(mangaKey: string): Promise<SManga>;
  getChapterList(mangaKey: string): Promise<SChapter[]>;
  getPageList(chapterKey: string): Promise<SPage[]>;
  // 小说正文（纯文本或简单 HTML）。非小说源返回空字符串。
  getChapterText(chapterKey: string): Promise<string>;
  // 视频流列表。非视频源返回空数组。m3u8 与直链都可播。
  getVideoList(chapterKey: string): Promise<SVideo[]>;
  // 图片加载附加请求头；undefined = 直连加载（系统 Image 网络栈）
  imageRequestHeaders(): Record<string, string> | undefined;
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
