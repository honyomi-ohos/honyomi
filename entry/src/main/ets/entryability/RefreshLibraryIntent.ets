import { insightIntent, InsightIntentEntry, InsightIntentEntryExecutor } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UpdateService } from '../data/UpdateService';
import { Settings } from '../common/Settings';
import { AppKeys } from '../common/AppKeys';
import EntryAbility from './EntryAbility';

const DOMAIN = 0x0001;

// 自定义意图：刷新书库检查更新（"用 Mihon 检查更新"）。
// 切到更新页签 + 异步触发全库刷新（不阻塞意图返回，网络刷新耗时较长）；
// 成功推进刷新时间戳并标记书库脏（与 Index.autoRefresh 同一套约定）。
@InsightIntentEntry({
  intentName: 'RefreshLibrary',
  domain: 'ReadingDomain',
  intentVersion: '1.0.1',
  displayName: '刷新书库检查更新',
  icon: $r('app.media.ic_sync'),
  llmDescription: '刷新书架全部作品，检查是否有新章节更新。当用户表达"检查更新/刷新书库/看看有没有更新"等需求时使用，例如："用Mihon检查更新"、"刷新一下书库"。',
  keywords: ['刷新书库', '检查更新', '检查新章节'],
  abilityName: 'EntryAbility',
  executeMode: [insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND]
})
export default class RefreshLibraryImpl extends InsightIntentEntryExecutor<string> {
  private static result(code: number, msg: string): insightIntent.IntentResult<string> {
    return { code: code, result: msg };
  }

  onExecute(): Promise<insightIntent.IntentResult<string>> {
    const context = EntryAbility.appContext;
    if (context === undefined) {
      return Promise.resolve(RefreshLibraryImpl.result(-1, 'app context unavailable'));
    }
    // 切到更新页签，让用户实时看到刷新出的新章节
    const payload: Record<string, string | number> = {
      'target': 'updates',
      'mangaId': 0,
      'chapterId': 0,
      'contentType': ''
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
    // 异步刷新：不阻塞意图返回
    UpdateService.refreshLibrary(context).then((newCount: number) => {
      Settings.setLastRefreshAt(Date.now());
      if (newCount > 0) {
        AppStorage.setOrCreate(AppKeys.LIB_DIRTY, (AppStorage.get<number>(AppKeys.LIB_DIRTY) ?? 0) + 1);
      }
      hilog.info(DOMAIN, 'Mihon', 'RefreshLibrary intent done, new chapters: %{public}d', newCount);
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, 'Mihon', 'RefreshLibrary intent failed: %{public}s', e.message);
    });
    return Promise.resolve(RefreshLibraryImpl.result(0, '书库刷新已开始'));
  }
}
