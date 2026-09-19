import { SManga, SChapter, SPage, MangasPage } from '../model/Models';
import { Source } from './Source';
import { Http } from '../net/Http';

// MangaDex JSON API 响应模型
interface MDRelationshipAttr {
  fileName?: string;
  name?: string;
}

interface MDRelationship {
  type: string;
  id: string;
  attributes?: MDRelationshipAttr;
}

interface MDTagAttributes {
  name: Record<string, string>;
}

interface MDTag {
  attributes: MDTagAttributes;
}

interface MDMangaAttributes {
  title?: Record<string, string>;
  altTitles?: Array<Record<string, string>>;
  description?: Record<string, string>;
  status?: string;
  tags?: Array<MDTag>;
}

interface MDMangaItem {
  id: string;
  attributes: MDMangaAttributes;
  relationships?: Array<MDRelationship>;
}

interface MDMangaListResponse {
  result: string;
  data: Array<MDMangaItem>;
  total?: number;
}

interface MDChapterAttributes {
  chapter?: string;
  title?: string;
  translatedLanguage?: string;
  pages?: number;
  publishAt?: string;
  externalUrl?: string;
}

interface MDChapterItem {
  id: string;
  attributes: MDChapterAttributes;
}

interface MDChapterListResponse {
  result: string;
  data: Array<MDChapterItem>;
  total?: number;
}

interface MDAtHomeChapter {
  hash: string;
  data: Array<string>;
}

interface MDAtHomeResponse {
  baseUrl: string;
  chapter: MDAtHomeChapter;
}

// MangaDex 在线源（api.mangadex.org，免认证 JSON API）
export class MangaDexSource implements Source {
  readonly key = 'mangadex';
  readonly name = 'MangaDex';
  readonly lang = 'multi';
  readonly supportsLatest = true;

  private readonly apiUrl = 'https://api.mangadex.org';
  private readonly coverUrl = 'https://uploads.mangadex.org/covers';
  private readonly pageSize = 24;
  private readonly feedLanguages: string[] = ['zh', 'en'];

  async getPopularManga(page: number): Promise<MangasPage> {
    const url = `${this.apiUrl}/manga?order[followedCount]=desc&limit=${this.pageSize}` +
      `&offset=${(page - 1) * this.pageSize}&includes[]=cover_art` +
      `&contentRating[]=safe&contentRating[]=suggestive`;
    return this.fetchMangaList(url);
  }

  async getSearchManga(page: number, query: string): Promise<MangasPage> {
    const url = `${this.apiUrl}/manga?title=${encodeURIComponent(query)}` +
      `&order[followedCount]=desc&limit=${this.pageSize}` +
      `&offset=${(page - 1) * this.pageSize}&includes[]=cover_art` +
      `&contentRating[]=safe&contentRating[]=suggestive`;
    return this.fetchMangaList(url);
  }

  async getMangaDetail(mangaKey: string): Promise<SManga> {
    const url = `${this.apiUrl}/manga/${mangaKey}?includes[]=cover_art&includes[]=author`;
    const text = await Http.get(url, undefined);
    const resp = JSON.parse(text) as MDResponseSingle;
    if (resp.data === undefined) {
      throw new Error('漫画详情为空');
    }
    return this.toSManga(resp.data);
  }

  async getChapterList(mangaKey: string): Promise<SChapter[]> {
    const chapters: SChapter[] = [];
    const limit = 500;
    let offset = 0;
    let total = Number.MAX_SAFE_INTEGER;
    while (offset < total && offset < 2000) {
      const langParams = this.feedLanguages
        .map((lang: string): string => `translatedLanguage[]=${lang}`)
        .join('&');
      const url = `${this.apiUrl}/manga/${mangaKey}/feed?order[chapter]=asc&limit=${limit}` +
        `&offset=${offset}&${langParams}&includeExternalUrl=0` +
        `&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica`;
      const text = await Http.get(url, undefined);
      const resp = JSON.parse(text) as MDChapterListResponse;
      if (resp.result !== 'ok') {
        throw new Error('章节列表获取失败');
      }
      if (resp.total !== undefined) {
        total = resp.total;
      }
      for (const item of resp.data) {
        const chapter = this.toSChapter(item, chapters.length);
        if (chapter !== undefined) {
          chapters.push(chapter);
        }
      }
      if (resp.data.length < limit) {
        break;
      }
      offset += limit;
    }
    return chapters;
  }

  async getPageList(chapterKey: string): Promise<SPage[]> {
    const url = `${this.apiUrl}/at-home/server/${chapterKey}`;
    const text = await Http.get(url, undefined);
    const resp = JSON.parse(text) as MDAtHomeResponse;
    if (resp.baseUrl === undefined || resp.chapter === undefined) {
      throw new Error('图片服务器响应异常');
    }
    const pages: SPage[] = [];
    const files = resp.chapter.data !== undefined ? resp.chapter.data : [];
    for (let i = 0; i < files.length; i++) {
      const imgUrl = `${resp.baseUrl}/data/${resp.chapter.hash}/${files[i]}`;
      const page: SPage = { index: i, url: imgUrl };
      pages.push(page);
    }
    return pages;
  }

  private async fetchMangaList(url: string): Promise<MangasPage> {
    const text = await Http.get(url, undefined);
    const resp = JSON.parse(text) as MDMangaListResponse;
    if (resp.result !== 'ok') {
      throw new Error('漫画列表获取失败');
    }
    const mangas: SManga[] = [];
    for (const item of resp.data) {
      mangas.push(this.toSManga(item));
    }
    const total = resp.total !== undefined ? resp.total : 0;
    const result: MangasPage = {
      mangas: mangas,
      hasNextPage: total > 0 && (total - mangas.length) > 0,
    };
    return result;
  }

  private toSManga(item: MDMangaItem): SManga {
    const attrs = item.attributes;
    let title = this.pickLang(attrs.title);
    if (title === '' && attrs.altTitles !== undefined) {
      for (const alt of attrs.altTitles) {
        title = this.pickLang(alt);
        if (title !== '') {
          break;
        }
      }
    }
    if (title === '') {
      title = '未命名';
    }
    let cover = '';
    if (item.relationships !== undefined) {
      for (const rel of item.relationships) {
        if (rel.type === 'cover_art' && rel.attributes !== undefined &&
          rel.attributes.fileName !== undefined && rel.attributes.fileName !== '') {
          cover = `${this.coverUrl}/${item.id}/${rel.attributes.fileName}`;
          break;
        }
      }
    }
    let author = '';
    if (item.relationships !== undefined) {
      for (const rel of item.relationships) {
        if (rel.type === 'author' && rel.attributes !== undefined &&
          rel.attributes.name !== undefined) {
          author = rel.attributes.name;
          break;
        }
      }
    }
    let description = this.pickLang(attrs.description);
    description = description.replace(new RegExp('\\[[^\\]]*\\]', 'g'), '');
    const genres: string[] = [];
    if (attrs.tags !== undefined) {
      for (const tag of attrs.tags) {
        const name = this.pickLang(tag.attributes.name);
        if (name !== '') {
          genres.push(name);
        }
      }
    }
    const manga: SManga = {
      key: item.id,
      title: title,
      coverUrl: cover,
      author: author,
      description: description,
      genre: genres.join(', '),
      status: attrs.status !== undefined ? attrs.status : '',
    };
    return manga;
  }

  private toSChapter(item: MDChapterItem, sortOrder: number): SChapter | undefined {
    const attrs = item.attributes;
    if (attrs.externalUrl !== undefined && attrs.externalUrl !== null && attrs.externalUrl !== '') {
      return undefined;
    }
    const numStr = attrs.chapter !== undefined ? attrs.chapter : '';
    const num = numStr !== '' ? parseFloat(numStr) : -1;
    let name = '';
    if (attrs.chapter !== undefined && attrs.chapter !== null && attrs.chapter !== '') {
      name = `第 ${attrs.chapter} 话`;
      if (attrs.title !== undefined && attrs.title !== null && attrs.title !== '') {
        name = `${name} ${attrs.title}`;
      }
    } else if (attrs.title !== undefined && attrs.title !== null && attrs.title !== '') {
      name = attrs.title;
    } else {
      name = '单话';
    }
    let dateUpload = 0;
    if (attrs.publishAt !== undefined && attrs.publishAt !== null) {
      const t = Date.parse(attrs.publishAt);
      if (!Number.isNaN(t)) {
        dateUpload = t;
      }
    }
    const chapter: SChapter = {
      key: item.id,
      name: name,
      chapterNumber: num,
      dateUpload: dateUpload,
      pages: attrs.pages !== undefined && attrs.pages !== null ? attrs.pages : 0,
      sortOrder: sortOrder,
    };
    return chapter;
  }

  // 语言优先级：zh > zh-hans > en > ja > 任意
  private pickLang(rec: Record<string, string> | undefined): string {
    if (rec === undefined || rec === null) {
      return '';
    }
    const v1 = rec['zh'];
    if (v1 !== undefined && v1 !== '') {
      return v1;
    }
    const v2 = rec['zh-hans'];
    if (v2 !== undefined && v2 !== '') {
      return v2;
    }
    const v3 = rec['en'];
    if (v3 !== undefined && v3 !== '') {
      return v3;
    }
    const v4 = rec['ja'];
    if (v4 !== undefined && v4 !== '') {
      return v4;
    }
    for (const key of Object.keys(rec)) {
      const v = rec[key];
      if (v !== undefined && v !== '') {
        return v;
      }
    }
    return '';
  }
}

interface MDResponseSingle {
  result: string;
  data?: MDMangaItem;
}
