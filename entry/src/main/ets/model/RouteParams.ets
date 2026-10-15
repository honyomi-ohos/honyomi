// Navigation 路由参数（全工程唯一声明处）

export interface DetailParams {
  mangaId: number;
}

export interface ReaderParams {
  mangaId: number;
  chapterId: number;
}

export interface BrowseSourceParams {
  sourceKey: string;
  mode: string; // 'popular' | 'latest'
}

export interface GlobalSearchParams {
  // 进入页面即自动执行的初始搜索词（详情页标题/作者/标签点击跳转）
  query: string;
}

// 详情页 popWithResult 回传给上一页的搜索请求
export interface DetailSearchResult {
  // 'search'：上一页文本搜索（源名点击）；'searchGenre'：上一页按标签过滤/搜索（标签菜单“搜索”）
  action: string;
  query: string;
}

export interface MigrateMangaParams {
  sourceKey: string;
}

export interface MigrateSearchParams {
  mangaIds: number[];
}

export interface ExtensionDetailParams {
  pluginKey: string;
}

export interface OnboardingParams {
  // true：首启自动拉起（未完成引导时拦截返回，防止跳过）
  firstRun: boolean;
}
