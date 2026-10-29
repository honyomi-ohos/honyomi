import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import { AppDb } from './AppDb';
import { ChapterRepo, MangaRepo } from './Repos';
import { Source, SourceRegistry } from '../source/Source';
import { ChapterRecord, ContentType, MangaRecord } from '../model/Models';
import { WidgetUpdater } from '../form/WidgetUpdater';
import { AppKeys } from '../common/AppKeys';
import { Settings } from '../common/Settings';
import { DownloadRules } from './DownloadRules';
import { NetworkMonitor } from '../common/NetworkMonitor';

// 书架更新服务：按源分组刷新最新章节（组内串行、组间最多 3 组并发）
export class UpdateService {
  static async refreshLibrary(context: common.UIAbilityContext): Promise<number> {
    return UpdateService.refreshCategory(context, 0);
  }

  // 批量库更新的网络/电源限制检查（对齐 Mihon updateRestrictions）：
  // 返回 '' 表示允许更新，否则返回跳过原因（供 UI 入口 toast 提示）
  static checkUpdateRestrictions(): string {
    if (Settings.getLibraryUpdateWifiOnly() && !NetworkMonitor.isWifiLike()) {
      return '已开启「仅 Wi-Fi 时更新」，当前网络不满足，已跳过本次更新';
    }
    if (Settings.getLibraryUpdateChargingOnly() && !UpdateService.isCharging()) {
      return '已开启「仅充电时更新」，请连接充电器后再更新';
    }
    return '';
  }

  // 充电中判定：ENABLE（充电中）或 FULL（充电已满，仍连接电源）均视为已连接电源
  private static isCharging(): boolean {
    const status: batteryInfo.BatteryChargeState = batteryInfo.chargingStatus;
    return status === batteryInfo.BatteryChargeState.ENABLE || status === batteryInfo.BatteryChargeState.FULL;
  }

  // 作品更新间隔到期判定（对齐 Mihon manga.updateInterval / "Restrict updates"）：
  // -1 = 从不参与全局更新；>0 = 距上次拉取超过 N 小时才到期；0 = 跟随默认（不限制）
  static isMangaDue(m: MangaRecord): boolean {
    if (m.updateInterval === -1) {
      return false;
    }
    if (m.updateInterval > 0) {
      // 以 fetchedAt（每次刷新都会推进）为基准，回退 lastUpdateAt；从未拉取视为到期
      const last: number = m.fetchedAt > 0 ? m.fetchedAt : m.lastUpdateAt;
      if (last <= 0) {
        return true;
      }
      return Date.now() - last >= m.updateInterval * 3600 * 1000;
    }
    return true;
  }

  // categoryId 为 0 时刷新全部书架；指定分类按 membership 过滤（含任一 membership 即算）
  static async refreshCategory(context: common.UIAbilityContext, categoryId: number): Promise<number> {
    // 网络限制不满足时跳过本次批量更新（调用方 UI 入口经 checkUpdateRestrictions 提示用户）
    const blockReason = UpdateService.checkUpdateRestrictions();
    if (blockReason !== '') {
      hilog.info(0x0001, 'Update', 'skip library update: %{public}s', blockReason);
      return 0;
    }
    await AppDb.ready(context);
    const library = await MangaRepo.getLibrary();
    let list: MangaRecord[] = library;
    if (categoryId > 0) {
      const memberships: Map<number, number[]> = await MangaRepo.libraryCategoryIds();
      list = library.filter((m: MangaRecord): boolean => {
        const ids: number[] | undefined = memberships.get(m.id);
        return ids !== undefined ? ids.includes(categoryId) : m.categoryId === categoryId;
      });
    }
    // 更新间隔过滤：-1 从不更新，>0 未到期跳过（0 跟随默认不限制）
    list = list.filter((m: MangaRecord): boolean => UpdateService.isMangaDue(m));
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
            // 自动下载开启时：同步前记录已有章节，同步后按新增章节入队（对齐 Mihon Download new chapters）
            const autoDl = Settings.getDownloadNewChapters();
            const beforeUrls = new Set<string>();
            if (autoDl) {
              const before = await ChapterRepo.listByManga(manga.id);
              for (const c of before) {
                beforeUrls.add(c.url);
              }
            }
            const n = await ChapterRepo.syncFromSource(manga.id, chapters);
            await MangaRepo.touch(manga.id, n > 0);
            if (autoDl && n > 0) {
              const after = await ChapterRepo.listByManga(manga.id);
              const fresh: ChapterRecord[] = after.filter((c: ChapterRecord): boolean => {
                return !beforeUrls.has(c.url);
              });
              DownloadRules.autoDownloadNewChapters(manga, fresh);
            }
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
