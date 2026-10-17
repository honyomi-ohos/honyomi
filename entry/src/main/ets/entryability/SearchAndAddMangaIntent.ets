import { insightIntent, InsightIntentEntry, InsightIntentEntryExecutor } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { Source, SourceRegistry } from '../source/Source';
import { SManga, WorksPage } from '../model/Models';
import { AppKeys } from '../common/AppKeys';
import { TitleMatch } from '../common/TitleMatch';
import EntryAbility from './EntryAbility';

const DOMAIN = 0x0001;
const SEARCH_TIMEOUT_MS: number = 12000;

// 意图执行返回值
export class SearchAndAddResultDef {
  public msg?: string = '';
}

// 自定义意图：搜索作品并加入书架（由小艺解析用户自然语言触发）。
// 触发语料须包含应用名，如"用 Mihon 搜索海贼王并加入书架"。
// 执行流程：指定/全部书源并发搜索 → 标题相似度评分选最佳 → 入库并加入书架 → 跳详情页；
// 未找到高置信匹配时降级为全局搜索页（携带搜索词，由用户手动挑选）。
@InsightIntentEntry({
  intentName: 'SearchAndAddManga',
  domain: 'ReadingDomain',
  intentVersion: '1.0.1',
  displayName: '搜索作品并加入书架',
  icon: $r('app.media.ic_bookmark'),
  llmDescription: '按作品名称在漫画阅读应用的书源（插件）中搜索漫画/小说，将标题最匹配的作品自动加入书架（收藏），并打开该作品的详情页。当用户明确表达"搜索某作品并加入书架/收藏"的需求时使用，例如："用Mihon搜索海贼王并加入书架"、"帮我在Mihon里收藏航海王"。若用户只是想打开应用页面或浏览内容，不应调用此意图。可选择性指定书源（插件）名称以缩小搜索范围。',
  keywords: ['搜索漫画', '加入书架', '收藏漫画', '搜书'],
  abilityName: 'EntryAbility',
  executeMode: [insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND],
  parameters: {
    'type': 'object',
    'description': '按作品名称搜索并加入书架的参数',
    'properties': {
      'mangaTitle': {
        'type': 'string',
        'description': '要搜索的作品名称',
        'minLength': 1
      },
      'sourceName': {
        'type': 'string',
        'description': '书源（插件）名称，可选；未提供时搜索全部已安装书源'
      }
    },
    'required': ['mangaTitle']
  }
})
export default class SearchAndAddMangaImpl extends InsightIntentEntryExecutor<SearchAndAddResultDef> {
  public mangaTitle: string = '';
  public sourceName?: string = '';

  private static result(code: number, msg: string): insightIntent.IntentResult<SearchAndAddResultDef> {
    const def = new SearchAndAddResultDef();
    def.msg = msg;
    return { code: code, result: def };
  }

  onExecute(): Promise<insightIntent.IntentResult<SearchAndAddResultDef>> {
    const query: string = this.mangaTitle.trim();
    if (query === '') {
      return Promise.resolve(SearchAndAddMangaImpl.result(-1, 'mangaTitle is empty'));
    }
    return this.doSearchAndAdd(query);
  }

  private async doSearchAndAdd(query: string): Promise<insightIntent.IntentResult<SearchAndAddResultDef>> {
    const context = EntryAbility.appContext;
    if (context === undefined) {
      return SearchAndAddMangaImpl.result(-1, 'app context unavailable');
    }
    try {
      await AppDb.ready(context);
    } catch (e) {
      return SearchAndAddMangaImpl.result(-1, 'db init failed');
    }
    const sources: Source[] = this.resolveSources();
    if (sources.length === 0) {
      this.fallbackGlobalSearch(query);
      return SearchAndAddMangaImpl.result(1, 'no source available');
    }
    // 并发搜索全部候选源（每源带超时，超时/失败按空结果处理）
    const searchTasks: Promise<SManga[]>[] = [];
    for (const s of sources) {
      searchTasks.push(this.searchSource(s, query));
    }
    const allResults: SManga[][] = await Promise.all(searchTasks);
    let best: SManga | undefined = undefined;
    let bestSource: Source | undefined = undefined;
    let bestScore: number = 0;
    for (let i: number = 0; i < allResults.length; i++) {
      for (const m of allResults[i]) {
        const score: number = TitleMatch.score(query, m.title);
        if (score > bestScore) {
          bestScore = score;
          best = m;
          bestSource = sources[i];
        }
      }
    }
    // 无高置信匹配（评分 0）：交给用户在全局搜索页手动挑选，避免错误入库
    if (best === undefined || bestSource === undefined || bestScore <= 0) {
      this.fallbackGlobalSearch(query);
      return SearchAndAddMangaImpl.result(1, 'no confident match, open global search');
    }
    try {
      const mangaId: number = await MangaRepo.upsertFromSource(bestSource.key, best, bestSource.contentType);
      await MangaRepo.setInLibrary(mangaId, true);
      this.goDetail(mangaId);
      hilog.info(DOMAIN, 'Mihon', 'SearchAndAddManga added "%{public}s" (id %{public}d)', best.title, mangaId);
      return SearchAndAddMangaImpl.result(0, `已加入书架：${best.title}`);
    } catch (e) {
      hilog.error(DOMAIN, 'Mihon', 'SearchAndAddManga add failed: %{public}s', `${e}`);
      this.fallbackGlobalSearch(query);
      return SearchAndAddMangaImpl.result(-1, 'add to library failed');
    }
  }

  // 解析目标书源：按插件名模糊匹配；未命中或未指定时回退全源搜索
  private resolveSources(): Source[] {
    const all: Source[] = SourceRegistry.all();
    const wanted: string = (this.sourceName ?? '').trim().toLowerCase();
    if (wanted === '') {
      return all;
    }
    const matched: Source[] = [];
    for (const s of all) {
      const name: string = s.name.toLowerCase();
      if (name === wanted || name.includes(wanted) || wanted.includes(name)) {
        matched.push(s);
      }
    }
    return matched.length > 0 ? matched : all;
  }

  // 单源搜索（带超时保护）
  private searchSource(source: Source, query: string): Promise<SManga[]> {
    return new Promise<SManga[]>((resolve: (value: SManga[]) => void) => {
      let settled: boolean = false;
      const finish = (value: SManga[]): void => {
        if (settled) {
          return;
        }
        settled = true;
        resolve(value);
      };
      const timerId: number = setTimeout(() => {
        finish([]);
      }, SEARCH_TIMEOUT_MS);
      source.getSearchWorks(1, query).then((page: WorksPage) => {
        clearTimeout(timerId);
        finish(page.works);
      }).catch((_e: Error) => {
        clearTimeout(timerId);
        finish([]);
      });
    });
  }

  // 跳转作品详情页（复用 cardAction 通道，Index 统一消费）
  private goDetail(mangaId: number): void {
    const payload: Record<string, string | number> = {
      'target': 'detail',
      'mangaId': mangaId,
      'chapterId': 0,
      'contentType': ''
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
  }

  // 降级：打开全局搜索页并携带搜索词
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
