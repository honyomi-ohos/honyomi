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
