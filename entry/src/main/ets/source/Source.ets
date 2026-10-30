import { SChapter, SManga, SPage, SVideo, WorksPage } from '../model/Models';

// 源抽象接口。contentType 为 manga / novel / video，缺省 manga。
// 漫画走 getPageList；小说走 getChapterText；视频走 getVideoList。宿主只按类型调用。
export interface Source {
  readonly key: string;
  readonly name: string;
  readonly lang: string;
  readonly supportsLatest: boolean;
  readonly contentType: string;

  // NSFW 源标记（插件 manifest 声明）；关闭“显示 NSFW 源”时在浏览/搜索中隐藏
  readonly nsfw: boolean;

  // BT 源标记（插件 manifest 声明）：内容为种子/magnet 下载，UI 展示 BT 徽标
  readonly bt: boolean;

  // ACGN 内容标记（插件 manifest 声明）：true = 源内容为动画/漫画/游戏/小说，
  // 作品详情页按名称+作者匹配 Bangumi 条目并展示相关系列；图片站等非 ACGN 源为 false
  readonly acgn: boolean;

  // 源图标（file:// 路径或网络 URL）；空字符串表示无图标，由 UI 回退首字母
  readonly iconPath: string;

  getPopularWorks(page: number): Promise<WorksPage>;

  // 最新更新（supportsLatest 为 false 时宿主不会调用）
  getLatestWorks(page: number): Promise<WorksPage>;

  getSearchWorks(page: number, query: string): Promise<WorksPage>;

  getWorkDetail(workKey: string): Promise<SManga>;

  // 相关/推荐作品（插件可选导出 getRelatedWorks 时才有数据；本地源恒为空）
  getRelatedWorks(workKey: string): Promise<SManga[]>;

  getChapterList(workKey: string): Promise<SChapter[]>;

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
    // 返回拷贝，防止调用方破坏注册表内部数组
    return SourceRegistry.sources.slice();
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
