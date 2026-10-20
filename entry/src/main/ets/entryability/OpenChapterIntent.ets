import { insightIntent, InsightIntentEntry, InsightIntentEntryExecutor } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { ChapterRepo, MangaRepo } from '../data/Repos';
import { ChapterRecord, MangaRecord } from '../model/Models';
import { AppKeys } from '../common/AppKeys';
import { TitleMatch } from '../common/TitleMatch';
import EntryAbility from './EntryAbility';

// 自定义意图：打开指定章节（"用 Honyomi 打开海贼王第10话"）。
// 书架内标题匹配定位作品 → 章节号/章节名匹配定位章节 → 直达对应类型阅读器；
// 作品未命中降级全局搜索，章节未命中打开作品详情页。
@InsightIntentEntry({
  intentName: 'OpenChapter',
  domain: 'ReadingDomain',
  intentVersion: '1.0.1',
  displayName: '打开指定章节',
  icon: $r('app.media.ic_playlist_play'),
  llmDescription: '打开书架（收藏）中某部作品的指定章节开始阅读。当用户想直接跳到某一话/某一章时使用，例如："用Honyomi打开海贼王第10话"、"看火影忍者的最终话"。作品需已在书架中，章节支持章节号（如"第10话"）或章节名。',
  keywords: ['打开章节', '看某一话', '跳到章节'],
  abilityName: 'EntryAbility',
  executeMode: [insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND],
  parameters: {
    'type': 'object',
    'description': '按作品名与章节打开指定章节',
    'properties': {
      'mangaTitle': {
        'type': 'string',
        'description': '作品名称',
        'minLength': 1
      },
      'chapterName': {
        'type': 'string',
        'description': '章节号或章节名，例如"第10话"、"10"、"最终话"',
        'minLength': 1
      }
    },
    'required': ['mangaTitle', 'chapterName']
  }
})
export default class OpenChapterImpl extends InsightIntentEntryExecutor<string> {
  public mangaTitle: string = '';
  public chapterName: string = '';

  // 章节定位：章节号精确匹配 > 名称包含"第X话/章/回" > 名称模糊匹配
  private static matchChapter(chapterQuery: string, chapters: ChapterRecord[]): ChapterRecord | undefined {
    const q: string = chapterQuery.trim().toLowerCase();
    if (q === '' || chapters.length === 0) {
      return undefined;
    }
    const numMatch: RegExpMatchArray | null = q.match(/\d+/);
    const num: number = numMatch !== null ? parseInt(numMatch[0]) : -1;
    let best: ChapterRecord | undefined = undefined;
    let bestScore: number = 0;
    for (const ch of chapters) {
      let score: number = 0;
      if (num > 0 && ch.chapterNumber === num) {
        score = 1000;
      } else if (num > 0) {
        const lower: string = ch.name.toLowerCase();
        if (lower.includes(`第${num}话`) || lower.includes(`第${num}章`) || lower.includes(`第${num}回`)) {
          score = 900;
        }
      }
      const nameScore: number = TitleMatch.score(chapterQuery, ch.name);
      if (nameScore > score) {
        score = nameScore;
      }
      if (score > bestScore) {
        bestScore = score;
        best = ch;
      }
    }
    return bestScore > 0 ? best : undefined;
  }

  private static result(code: number, msg: string): insightIntent.IntentResult<string> {
    return { code: code, result: msg };
  }

  onExecute(): Promise<insightIntent.IntentResult<string>> {
    const mangaQuery: string = this.mangaTitle.trim();
    const chapterQuery: string = this.chapterName.trim();
    if (mangaQuery === '' || chapterQuery === '') {
      return Promise.resolve(OpenChapterImpl.result(-1, 'mangaTitle or chapterName is empty'));
    }
    return this.doOpen(mangaQuery, chapterQuery);
  }

  private async doOpen(mangaQuery: string,
    chapterQuery: string): Promise<insightIntent.IntentResult<string>> {
    const context = EntryAbility.appContext;
    if (context === undefined) {
      return OpenChapterImpl.result(-1, 'app context unavailable');
    }
    try {
      await AppDb.ready(context);
    } catch (e) {
      return OpenChapterImpl.result(-1, 'db init failed');
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
      const score: number = TitleMatch.score(mangaQuery, m.title);
      if (score > bestScore) {
        bestScore = score;
        best = m;
      }
    }
    if (best === undefined || bestScore <= 0) {
      this.fallbackGlobalSearch(mangaQuery);
      return OpenChapterImpl.result(1, `书架未找到"${mangaQuery}"，已打开全局搜索`);
    }
    let chapters: ChapterRecord[] = [];
    try {
      chapters = await ChapterRepo.listByManga(best.id);
    } catch (e) {
      chapters = [];
    }
    const chapter: ChapterRecord | undefined = OpenChapterImpl.matchChapter(chapterQuery, chapters);
    if (chapter === undefined) {
      this.openDetail(best.id);
      return OpenChapterImpl.result(1, `书架已找到《${best.title}》，未匹配到章节"${chapterQuery}"，已打开作品详情`);
    }
    const payload: Record<string, string | number> = {
      'target': 'reader',
      'mangaId': best.id,
      'chapterId': chapter.id,
      'contentType': best.contentType
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
    return OpenChapterImpl.result(0, `已打开：《${best.title}》${chapter.name}`);
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

  private openDetail(mangaId: number): void {
    const payload: Record<string, string | number> = {
      'target': 'detail',
      'mangaId': mangaId,
      'chapterId': 0,
      'contentType': ''
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
  }
}
