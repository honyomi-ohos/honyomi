import { insightIntent, InsightIntentEntry, InsightIntentEntryExecutor } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { ChapterRepo, HistoryRepo } from '../data/Repos';
import { HistoryItem } from '../model/Models';
import { AppKeys } from '../common/AppKeys';
import EntryAbility from './EntryAbility';

// 自定义意图：继续阅读（"用 Honyomi 继续看漫画"）。
// 取最近一条阅读记录 → 第一个未读章节（全部已读则重读最近章节）→ 经 cardAction 通道由 Index 拉起阅读器。
@InsightIntentEntry({
  intentName: 'ContinueReading',
  domain: 'ReadingDomain',
  intentVersion: '1.0.1',
  displayName: '继续阅读',
  icon: $r('app.media.ic_play_arrow'),
  llmDescription: '继续阅读上次看的作品（漫画/小说/视频）。当用户表达"继续看/继续读/接着看上次的作品"等需求时使用，例如："用Honyomi继续看漫画"、"继续阅读上次的作品"。应用需已有阅读历史才能继续。',
  keywords: ['继续阅读', '续读', '接着看'],
  abilityName: 'EntryAbility',
  executeMode: [insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND]
})
export default class ContinueReadingImpl extends InsightIntentEntryExecutor<string> {
  private static result(code: number, msg: string): insightIntent.IntentResult<string> {
    return { code: code, result: msg };
  }

  onExecute(): Promise<insightIntent.IntentResult<string>> {
    return this.doContinue();
  }

  private async doContinue(): Promise<insightIntent.IntentResult<string>> {
    const context = EntryAbility.appContext;
    if (context === undefined) {
      return ContinueReadingImpl.result(-1, 'app context unavailable');
    }
    try {
      await AppDb.ready(context);
    } catch (e) {
      return ContinueReadingImpl.result(-1, 'db init failed');
    }
    const recent: HistoryItem[] = await HistoryRepo.recent(1);
    if (recent.length === 0) {
      this.openHistory();
      return ContinueReadingImpl.result(1,
        context.resourceManager.getStringSync($r('app.string.intent_continue_reading_no_history').id));
    }
    const last: HistoryItem = recent[0];
    const nextId: number = await ChapterRepo.firstUnread(last.mangaId);
    // 全部已读时回看最近章节
    const chapterId: number = nextId > 0 ? nextId : last.chapterId;
    if (chapterId <= 0) {
      this.openHistory();
      return ContinueReadingImpl.result(1,
        context.resourceManager.getStringSync($r('app.string.intent_continue_reading_no_chapter').id));
    }
    const payload: Record<string, string | number> = {
      'target': 'reader',
      'mangaId': last.mangaId,
      'chapterId': chapterId,
      'contentType': ''
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
    return ContinueReadingImpl.result(0,
      context.resourceManager.getStringSync($r('app.string.intent_continue_reading_opened').id, last.mangaTitle));
  }

  private openHistory(): void {
    const payload: Record<string, string | number> = {
      'target': 'history',
      'mangaId': 0,
      'chapterId': 0,
      'contentType': ''
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
  }
}
