import { insightIntent, InsightIntentEntry, InsightIntentEntryExecutor } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { HistoryRepo } from '../data/Repos';
import { HistoryItem } from '../model/Models';
import { AppKeys } from '../common/AppKeys';
import { TtsPlaybackService } from '../common/TtsPlaybackService';
import EntryAbility from './EntryAbility';

// 自定义意图：继续听书（"用 Honyomi 继续听书"）。
// 听书服务存活：暂停则续播并打开播放器页；
// 未存活（应用被杀/首次）：取最近一部小说的历史记录从头朗读本章。
@InsightIntentEntry({
  intentName: 'ContinueListening',
  domain: 'ReadingDomain',
  intentVersion: '1.0.1',
  displayName: '继续听书',
  icon: $r('app.media.ic_playlist_play'),
  llmDescription: '继续收听有声书（小说朗读）。当用户表达"继续听书/接着听小说"等需求时使用，例如："用Honyomi继续听书"、"接着听上次听的小说"。听书服务正在运行时直接续播；未在播放时从最近听读的小说继续朗读。',
  keywords: ['继续听书', '听小说', '续听'],
  abilityName: 'EntryAbility',
  executeMode: [insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND]
})
export default class ContinueListeningImpl extends InsightIntentEntryExecutor<string> {
  private static result(code: number, msg: string): insightIntent.IntentResult<string> {
    return { code: code, result: msg };
  }

  onExecute(): Promise<insightIntent.IntentResult<string>> {
    return this.doContinue();
  }

  private async doContinue(): Promise<insightIntent.IntentResult<string>> {
    const context = EntryAbility.appContext;
    if (context === undefined) {
      return ContinueListeningImpl.result(-1, 'app context unavailable');
    }
    // 听书服务存活：续播并直达播放器页
    if (TtsPlaybackService.isActive()) {
      if (TtsPlaybackService.isPaused()) {
        TtsPlaybackService.resume();
      }
      this.openTtsPlayer();
      return ContinueListeningImpl.result(0,
        context.resourceManager.getStringSync($r('app.string.intent_continue_listening_resumed').id));
    }
    try {
      await AppDb.ready(context);
    } catch (e) {
      return ContinueListeningImpl.result(-1, 'db init failed');
    }
    const last: HistoryItem | undefined = await HistoryRepo.lastNovel();
    if (last === undefined) {
      this.openHistory();
      return ContinueListeningImpl.result(1,
        context.resourceManager.getStringSync($r('app.string.intent_continue_listening_no_novel').id));
    }
    const started: boolean = await TtsPlaybackService.start(last.mangaId, last.chapterId, 0, context);
    if (!started) {
      this.openHistory();
      return ContinueListeningImpl.result(1,
        context.resourceManager.getStringSync($r('app.string.intent_continue_listening_failed').id));
    }
    this.openTtsPlayer();
    return ContinueListeningImpl.result(0,
      context.resourceManager.getStringSync($r('app.string.intent_continue_listening_opened').id, last.mangaTitle));
  }

  private openTtsPlayer(): void {
    const payload: Record<string, string | number> = {
      'target': 'ttsplayer',
      'mangaId': 0,
      'chapterId': 0,
      'contentType': ''
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
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
