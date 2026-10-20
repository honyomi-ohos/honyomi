import { insightIntent, InsightIntentEntry, InsightIntentEntryExecutor } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { MangaRecord } from '../model/Models';
import { AppKeys } from '../common/AppKeys';
import { TitleMatch } from '../common/TitleMatch';
import EntryAbility from './EntryAbility';

// 自定义意图：打开书架作品（"用 Honyomi 打开海贼王"）。
// 书架内标题模糊匹配 → 命中打开详情页；未命中降级全局搜索（携带搜索词）。
@InsightIntentEntry({
  intentName: 'OpenManga',
  domain: 'ReadingDomain',
  intentVersion: '1.0.1',
  displayName: '打开书架作品',
  icon: $r('app.media.ic_collections_bookmark'),
  llmDescription: '打开书架（收藏）中已有作品的详情页。当用户想查看或打开某部已收藏的漫画、小说、视频时使用，例如："用Honyomi打开海贼王"、"打开书架里的航海王"。若作品不在书架中，将打开全局搜索帮助用户查找。',
  keywords: ['打开漫画', '打开作品', '查看作品'],
  abilityName: 'EntryAbility',
  executeMode: [insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND],
  parameters: {
    'type': 'object',
    'description': '按作品名称打开书架中的作品',
    'properties': {
      'mangaTitle': {
        'type': 'string',
        'description': '要打开的作品名称',
        'minLength': 1
      }
    },
    'required': ['mangaTitle']
  }
})
export default class OpenMangaImpl extends InsightIntentEntryExecutor<string> {
  public mangaTitle: string = '';

  private static result(code: number, msg: string): insightIntent.IntentResult<string> {
    return { code: code, result: msg };
  }

  onExecute(): Promise<insightIntent.IntentResult<string>> {
    const query: string = this.mangaTitle.trim();
    if (query === '') {
      return Promise.resolve(OpenMangaImpl.result(-1, 'mangaTitle is empty'));
    }
    return this.doOpen(query);
  }

  private async doOpen(query: string): Promise<insightIntent.IntentResult<string>> {
    const context = EntryAbility.appContext;
    if (context === undefined) {
      return OpenMangaImpl.result(-1, 'app context unavailable');
    }
    try {
      await AppDb.ready(context);
    } catch (e) {
      return OpenMangaImpl.result(-1, 'db init failed');
    }
    let library: MangaRecord[] = [];
    try {
      library = await MangaRepo.getLibrary();
    } catch (e) {
      library = [];
    }
    let best: MangaRecord | undefined = undefined;
    let bestScore: number = 0;
    for (const m of library) {
      const score: number = TitleMatch.score(query, m.title);
      if (score > bestScore) {
        bestScore = score;
        best = m;
      }
    }
    if (best === undefined || bestScore <= 0) {
      this.fallbackGlobalSearch(query);
      return OpenMangaImpl.result(1, `书架未找到"${query}"，已打开全局搜索`);
    }
    const payload: Record<string, string | number> = {
      'target': 'detail',
      'mangaId': best.id,
      'chapterId': 0,
      'contentType': ''
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
    return OpenMangaImpl.result(0, `已打开：${best.title}`);
  }

  private fallbackGlobalSearch(query: string): void {
    const payload: Record<string, string | number> = {
      'target': 'globalsearch',
      'mangaId': 0,
      'chapterId': 0,
      'contentType': '',
      'query': query
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
  }
}
