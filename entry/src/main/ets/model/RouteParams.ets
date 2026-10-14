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
