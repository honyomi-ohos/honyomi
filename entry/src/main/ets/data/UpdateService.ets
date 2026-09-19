import { common } from '@kit.AbilityKit';
import { AppDb } from './AppDb';
import { MangaRepo, ChapterRepo } from './Repos';
import { SourceRegistry } from '../source/Source';
import { MangaRecord } from '../model/Models';

// 书架更新服务：遍历收藏漫画拉取最新章节
export class UpdateService {
  static async refreshLibrary(context: common.UIAbilityContext): Promise<number> {
    await AppDb.ready(context);
    const library = await MangaRepo.getLibrary();
    let newCount = 0;
    for (const manga of library) {
      if (manga.sourceKey === 'local') {
        continue;
      }
      const source = SourceRegistry.get(manga.sourceKey);
      if (source === undefined) {
        continue;
      }
      try {
        const chapters = await source.getChapterList(manga.url);
        newCount += await ChapterRepo.syncFromSource(manga.id, chapters);
      } catch (e) {
        // 单本失败不中断整体刷新
      }
    }
    return newCount;
  }
}
