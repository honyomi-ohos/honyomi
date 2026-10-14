import { Http } from '../net/Http';
import { ALMediaItem, ContentType } from '../model/Models';
import { hilog } from '@kit.PerformanceAnalysisKit';

// AniList GraphQL 追踪（对齐 Mihon AnilistTracker 的最小集）
const AL_ENDPOINT = 'https://graphql.anilist.co';

const SEARCH_MANGA = `query Search($search: String) {
  Page(perPage: 20) {
    media(search: $search, type: MANGA, format_not: NOVEL) {
      id
      title { romaji english native }
    }
  }
}`;

const SEARCH_NOVEL = `query Search($search: String) {
  Page(perPage: 20) {
    media(search: $search, type: MANGA, format: NOVEL) {
      id
      title { romaji english native }
    }
  }
}`;

const SEARCH_ANIME = `query Search($search: String) {
  Page(perPage: 20) {
    media(search: $search, type: ANIME) {
      id
      title { romaji english native }
    }
  }
}`;

const PROGRESS_MUTATION = `mutation Progress($mediaId: Int, $progress: Int) {
  SaveMediaListEntry(mediaId: $mediaId, progress: $progress) {
    id
  }
}`;

interface ALTitle {
  romaji: string;
  english: string;
  native: string;
}

interface ALError {
  message: string;
}

interface ALMediaNode {
  id: number;
  title: ALTitle;
}

interface ALPageData {
  media?: ALMediaNode[];
}

interface ALSearchData {
  Page?: ALPageData;
}

interface ALSearchResponse {
  data?: ALSearchData;
  errors?: ALError[];
}

interface ALSaveData {
  SaveMediaListEntry: Record<string, Object>;
}

interface ALSaveResponse {
  data?: ALSaveData;
  errors?: ALError[];
}

interface ALSearchVars {
  search: string;
}

interface ALProgressVars {
  mediaId: number;
  progress: number;
}

export class AniListTracker {
  // GraphQL errors 字段拼接为可读错误信息，无错误返回空串
  private static errorsText(errors: ALError[] | undefined): string {
    if (errors === undefined || errors === null || errors.length === 0) {
      return '';
    }
    const messages: string[] = [];
    for (const e of errors) {
      if (e !== undefined && e !== null && typeof e.message === 'string' && e.message !== '') {
        messages.push(e.message);
      }
    }
    return messages.join('; ');
  }

  // 搜索 AniList 漫画条目（需 access token）
  static async search(query: string, token: string, contentType: string): Promise<ALMediaItem[]> {
    const vars: ALSearchVars = { search: query };
    let queryText = SEARCH_MANGA;
    if (contentType === ContentType.NOVEL) {
      queryText = SEARCH_NOVEL;
    } else if (contentType === ContentType.VIDEO) {
      queryText = SEARCH_ANIME;
    }
    const body: Record<string, Object> = { 'query': queryText, 'variables': vars };
    const headers: Record<string, string> = {
      'Authorization': `Bearer ${token}`,
    };
    const text: string = await Http.post(AL_ENDPOINT, JSON.stringify(body), headers);
    const resp = JSON.parse(text) as ALSearchResponse;
    const errText: string = AniListTracker.errorsText(resp.errors);
    if (errText !== '') {
      throw new Error(`AniList 请求失败: ${errText}`);
    }
    const result: ALMediaItem[] = [];
    // 错误响应可能缺 data/Page/media，判空防护后降级为空结果
    if (resp.data === undefined || resp.data.Page === undefined || resp.data.Page.media === undefined) {
      return result;
    }
    const media: ALMediaNode[] = resp.data.Page.media;
    for (const node of media) {
      const item = new ALMediaItem();
      item.id = node.id;
      const title = node.title;
      item.title = (title.romaji !== undefined && title.romaji !== null && title.romaji !== '') ? title.romaji :
        ((title.english !== undefined && title.english !== null && title.english !== '') ? title.english :
          ((title.native !== undefined && title.native !== null) ? title.native : ''));
      result.push(item);
    }
    return result;
  }

  // 同步阅读进度（第几话）
  static async updateProgress(token: string, mediaId: number, progress: number): Promise<void> {
    const vars: ALProgressVars = { mediaId: mediaId, progress: progress };
    const body: Record<string, Object> = { 'query': PROGRESS_MUTATION, 'variables': vars };
    const headers: Record<string, string> = {
      'Authorization': `Bearer ${token}`,
    };
    const text: string = await Http.post(AL_ENDPOINT, JSON.stringify(body), headers);
    const resp = JSON.parse(text) as ALSaveResponse;
    const errText: string = AniListTracker.errorsText(resp.errors);
    if (errText !== '') {
      throw new Error(`AniList 请求失败: ${errText}`);
    }
    if (resp.data === undefined || resp.data.SaveMediaListEntry === undefined) {
      hilog.error(0x0001, 'AniList', 'save progress failed for media %{public}d', mediaId);
      throw new Error('AniList save failed');
    }
  }
}
