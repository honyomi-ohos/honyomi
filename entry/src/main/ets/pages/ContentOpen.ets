import { MangaRepo } from '../data/Repos';
import { ContentType } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';

// 按作品类型打开章节：漫画阅读器、小说正文、视频播放
export class ContentOpen {
  static routeOf(contentType: string): string {
    if (contentType === ContentType.NOVEL) {
      return 'NovelReader';
    }
    if (contentType === ContentType.VIDEO) {
      return 'VideoPlayer';
    }
    return 'Reader';
  }

  static push(stack: NavPathStack, contentType: string, mangaId: number, chapterId: number): void {
    const params: ReaderParams = { mangaId: mangaId, chapterId: chapterId };
    stack.pushPathByName(ContentOpen.routeOf(contentType), params);
  }

  static async open(stack: NavPathStack, mangaId: number, chapterId: number): Promise<void> {
    const manga = await MangaRepo.get(mangaId);
    const type = manga !== undefined ? manga.contentType : ContentType.MANGA;
    ContentOpen.push(stack, type, mangaId, chapterId);
  }
}
