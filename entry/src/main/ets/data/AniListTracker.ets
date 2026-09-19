import { Http } from '../net/Http';
import { ALMediaItem } from '../model/Models';
import { hilog } from '@kit.PerformanceAnalysisKit';

// AniList GraphQL 追踪（对齐 Mihon AnilistTracker 的最小集）
const AL_ENDPOINT = 'https://graphql.anilist.co';

const SEARCH_QUERY = `query Search($search: String) {
  Page(perPage: 20) {
    media(search: $search, type: MANGA) {
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

interface ALMediaNode {
  id: number;
  title: ALTitle;
}

interface ALPageData {
  media: ALMediaNode[];
}

interface ALSearchData {
  Page: ALPageData;
}

interface ALSearchResponse {
  data: ALSearchData;
}

interface ALSaveData {
  SaveMediaListEntry: Record<string, Object>;
}

interface ALSaveResponse {
  data: ALSaveData;
}

interface ALSearchVars {
  search: string;
}

interface ALProgressVars {
  mediaId: number;
  progress: number;
}

export class AniListTracker {
  // 搜索 AniList 漫画条目（需 access token）
  static async search(query: string, token: string): Promise<ALMediaItem[]> {
    const vars: ALSearchVars = { search: query };
    const body: Record<string, Object> = { 'query': SEARCH_QUERY, 'variables': vars };
    const headers: Record<string, string> = {
      'Authorization': `Bearer ${token}`,
    };
    const text: string = await Http.post(AL_ENDPOINT, JSON.stringify(body), headers);
    const resp = JSON.parse(text) as ALSearchResponse;
    const result: ALMediaItem[] = [];
    const media = resp.data.Page.media;
    if (media === undefined) {
      return result;
    }
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
    if (resp.data.SaveMediaListEntry === undefined) {
      hilog.error(0x0001, 'AniList', 'save progress failed for media %{public}d', mediaId);
      throw new Error('AniList save failed');
    }
  }
}
