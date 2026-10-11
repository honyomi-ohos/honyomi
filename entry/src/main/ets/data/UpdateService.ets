import { common } from '@kit.AbilityKit';
import { AppDb } from './AppDb';
import { MangaRepo, ChapterRepo } from './Repos';
import { SourceRegistry } from '../source/Source';
import { MangaRecord } from '../model/Models';
import { WidgetUpdater } from '../form/WidgetUpdater';

// 书架更新服务：遍历收藏漫画拉取最新章节
export class UpdateService {
  static async refreshLibrary(context: common.UIAbilityContext): Promise<number> {
    return UpdateService.refreshCategory(context, 0);
  }

  // categoryId 为 0 时刷新全部书架
  static async refreshCategory(context: common.UIAbilityContext, categoryId: number): Promise<number> {
    await AppDb.ready(context);
    const library = await MangaRepo.getLibrary();
    const list: MangaRecord[] = categoryId > 0
      ? library.filter((m: MangaRecord): boolean => m.categoryId === categoryId)
      : library;
    let newCount = 0;
    for (const manga of list) {
      if (manga.sourceKey === 'local') {
        continue;
      }
      const source = SourceRegistry.get(manga.sourceKey);
      if (source === undefined) {
        continue;
      }
      try {
        const chapters = await source.getChapterList(manga.url);
        const n = await ChapterRepo.syncFromSource(manga.id, chapters);
        await MangaRepo.touch(manga.id, n > 0);
        newCount += n;
      } catch (e) {
        // 单本失败不中断整体刷新
      }
    }
    WidgetUpdater.refreshAll(context).catch((_e: Error) => {
      // 卡片刷新失败不影响主流程
    });
    return newCount;
  }
}
