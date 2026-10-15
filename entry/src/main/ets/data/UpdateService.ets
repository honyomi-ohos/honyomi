import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDb } from './AppDb';
import { MangaRepo, ChapterRepo } from './Repos';
import { SourceRegistry, Source } from '../source/Source';
import { MangaRecord, ContentType } from '../model/Models';
import { WidgetUpdater } from '../form/WidgetUpdater';
import { AppKeys } from '../common/AppKeys';

// 书架更新服务：按源分组刷新最新章节（组内串行、组间最多 3 组并发）
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
    // 按源分组：同一源的请求串行避免打挂源站，不同源之间最多 3 组并发
    const groups = new Map<string, MangaRecord[]>();
    for (const manga of list) {
      if (ContentType.isLocal(manga.sourceKey)) {
        continue;
      }
      if (SourceRegistry.get(manga.sourceKey) === undefined) {
        continue;
      }
      let group: MangaRecord[] | undefined = groups.get(manga.sourceKey);
      if (group === undefined) {
        group = [];
        groups.set(manga.sourceKey, group);
      }
      group.push(manga);
    }
    const sourceKeys: string[] = [];
    groups.forEach((_group: MangaRecord[], key: string) => {
      sourceKeys.push(key);
    });
    let newCount = 0;
    let failedCount = 0;
    let next = 0;
    const worker = async (): Promise<void> => {
      while (next < sourceKeys.length) {
        const key: string = sourceKeys[next];
        next += 1;
        const group: MangaRecord[] | undefined = groups.get(key);
        const source: Source | undefined = SourceRegistry.get(key);
        if (group === undefined || source === undefined) {
          continue;
        }
        for (const manga of group) {
          try {
            const chapters = await source.getChapterList(manga.url);
            const n = await ChapterRepo.syncFromSource(manga.id, chapters);
            await MangaRepo.touch(manga.id, n > 0);
            newCount += n;
          } catch (e) {
            // 单本失败不中断整体刷新，记录失败供上层提示
            failedCount += 1;
            hilog.warn(0x0001, 'Update', 'refresh manga %{public}d failed: %{public}s',
              manga.id, (e as Error).message);
          }
        }
      }
    };
    const workers: Array<Promise<void>> = [];
    const concurrency: number = Math.min(3, sourceKeys.length);
    for (let i = 0; i < concurrency; i++) {
      workers.push(worker());
    }
    await Promise.all(workers);
    // 失败计数经 AppStorage 暴露给上层（设置/刷新入口提示）
    AppStorage.setOrCreate(AppKeys.UPDATE_FAILED_COUNT, failedCount);
    WidgetUpdater.refreshAll(context).catch((_e: Error) => {
      // 卡片刷新失败不影响主流程
    });
    return newCount;
  }
}
