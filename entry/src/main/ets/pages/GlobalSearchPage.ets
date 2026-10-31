import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { Source, SourceRegistry } from '../source/Source';
import { MangaRecord, SManga, WorksPage } from '../model/Models';
import { BrowseSourceParams, DetailParams, GlobalSearchParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { AppIcon } from './components/AppIcon';
import { LoadingState } from './components/LoadingState';
import { ErrorState } from './components/ErrorState';
import { SmartImage } from './components/SmartImage';

// 语言显示名（与 BrowsePage 保持一致，对齐 Mihon 源列表语言标签）
const LANG_NAMES: Record<string, string> = {
  'en': 'English',
  'ja': '日本語',
  'zh': '中文',
  'zh-Hans': '中文',
  'zh-Hant': '中文（繁）',
  'ko': '한국어',
  'multi': 'Multi',
  'all': 'Multi',
};

function langDisplayName(lang: string): string {
  const name: string | undefined = LANG_NAMES[lang];
  return name !== undefined ? name : lang.toUpperCase();
}

// 全局搜索结果分节（每源一节，对齐 Mihon SearchItemResult）
export class SearchSection {
  sourceKey: string = '';
  name: string = '';
  lang: string = '';
  pinned: boolean = false;
  results: MangaRecord[] = [];
  state: string = 'loading'; // loading | done | error
  errorMessage: string = '';
}

// 分节排序（对齐 Mihon sortComparator）：有结果在前 → 置顶在前 → 名称
function sectionCompare(a: SearchSection, b: SearchSection): number {
  const aHas = a.state === 'done' && a.results.length > 0;
  const bHas = b.state === 'done' && b.results.length > 0;
  if (aHas !== bHas) {
    return aHas ? -1 : 1;
  }
  const ap = a.pinned ? 0 : 1;
  const bp = b.pinned ? 0 : 1;
  if (ap !== bp) {
    return ap - bp;
  }
  const an = a.name.toLowerCase();
  const bn = b.name.toLowerCase();
  return an < bn ? -1 : (an > bn ? 1 : 0);
}

// 搜索结果卡片（对齐 Mihon MangaComfortableGridItem + InLibraryBadge）：
// 96 宽封面卡（2:3）+ 下方标题（最多 3 行），已在库时封面半透明并叠加入库徽标
@Component
struct SearchCard {
  @ObjectLink record: MangaRecord;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onCardClick: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Stack() {
          SmartImage({
            url: this.record.thumbnailUrl,
            sourceKey: this.record.sourceKey,
            fit: ImageFit.Cover,
            fill: true,
            placeholderIconSize: 20
          })
        }
        .width('100%')
        .aspectRatio(2 / 3)
        .borderRadius(4)
        .clip(true)
        .backgroundColor(this.pal.chip)
        .opacity(this.record.inLibrary ? 0.34 : 1)

        if (this.record.inLibrary) {
          Row() {
            AppIcon({ name: 'collections_bookmark', iconSize: 12, tint: this.pal.onPrimary })
          }
          .backgroundColor(this.pal.primary)
          .borderRadius(4)
          .padding(3)
          .margin(4)
        }
      }
      .width('100%')

      Text(this.record.title)
        .fontSize(12)
        .fontColor(this.pal.text)
        .minLines(2)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
    }
    .width(96)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onCardClick(this.record);
    })
  }
}

// 全局搜索页（图源 Tab 顶栏按钮进入）：一次搜索所有已启用源
// 布局对齐 Mihon GlobalSearchScreen：搜索栏 + 进度条 → 筛选 Chip 行 → 按源分节横向卡片结果
@Component
export struct GlobalSearchPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @State searchQuery: string = '';
  // 'pinned'：只搜已置顶源（Mihon SourceFilter.PinnedOnly 默认值）| 'all'：全部源
  @State sourceFilter: string = 'pinned';
  // “有结果”筛选开关（持久化，对齐 Mihon globalSearchFilterState）
  @State onlyHasResults: boolean = false;
  @State sections: SearchSection[] = [];
  private lastQuery: string = '';

  aboutToAppear(): void {
    this.onlyHasResults = Settings.getGlobalSearchFilterResults();
  }

  async openDetail(record: MangaRecord): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const m: SManga = {
        key: record.url,
        title: record.title,
        coverUrl: record.thumbnailUrl,
        author: record.author,
        description: record.description,
        genre: record.genre,
        status: record.status,
        contentType: record.contentType,
      };
      const id = await MangaRepo.upsertFromSource(record.sourceKey, m, record.contentType);
      const params: DetailParams = { mangaId: id };
      this.pathStack.pushPathByName('MangaDetail', params);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_open_detail_failed'));
    }
  }

  build() {
    NavDestination() {
      this.bodyContent()
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      // 进入搜索页自动聚焦输入框（等待页面构建完成后拉起键盘）
      setTimeout(() => {
        this.getUIContext().getFocusController().requestFocus('globalSearchInput');
      }, 100);
      // 详情页跳转携带初始搜索词：进入即自动执行搜索
      const params = ctx.pathInfo.param as GlobalSearchParams;
      if (params !== undefined && params !== null && params.query.trim() !== '') {
        this.searchQuery = params.query.trim();
        this.startSearch();
      }
    })
  }

  @Builder
  bodyContent() {
    Column() {
      // 搜索栏 + 进度条叠加层：进度条浮在搜索栏底部 padding 区，出现/消失不挤压下方内容
      Stack({ alignContent: Alignment.Bottom }) {
        // 搜索栏（对齐 Mihon SearchToolbar：返回 + 搜索输入 + 清除）
        Row() {
          AppIcon({ name: 'arrow_back', iconSize: 24 })
            .padding(12)
            .onClick(() => {
              this.pathStack.pop();
            })

          Row() {
            AppIcon({ name: 'search', iconSize: 20, tint: this.pal.sub })
            TextInput({
              text: this.searchQuery,
              placeholder: $r('app.string.global_search_hint')
            })
              .id('globalSearchInput')
              .layoutWeight(1)
              .height(38)
              .backgroundColor(Color.Transparent)
              .padding(0)
              .fontSize(15)
              .fontColor(this.pal.text)
              .placeholderColor(this.pal.sub)
              .caretColor(this.pal.primary)
              .enterKeyType(EnterKeyType.Search)
              .onChange((value: string) => {
                this.searchQuery = value;
              })
              .onSubmit(() => {
                this.startSearch();
              })
            if (this.searchQuery !== '') {
              AppIcon({ name: 'close', iconSize: 18, tint: this.pal.sub })
                .padding(6)
                .onClick(() => {
                  this.searchQuery = '';
                })
            }
          }
          .layoutWeight(1)
          .height(38)
          .borderRadius(19)
          .backgroundColor(this.pal.chip)
          .alignItems(VerticalAlign.Center)
          .padding({ left: 10, right: 4 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({
          left: 4,
          right: 12,
          top: this.statusBarH + 8,
          bottom: 8
        })

        // 搜索进度条（对齐 Mihon：完成数在 1..<总数 时显示于搜索栏下方）
        if (this.sections.length > 0 && this.doneCount() > 0 && this.doneCount() < this.sections.length) {
          Progress({ value: this.doneCount(), total: this.sections.length, type: ProgressType.Linear })
            .width('100%')
            .height(4)
            .color(this.pal.primary)
            .backgroundColor(Color.Transparent)
            .padding(0)
        }
      }
      .width('100%')

      // 筛选 Chip 行（对齐 Mihon GlobalSearchToolbar：已置顶 / 全部 | 有结果）
      Scroll() {
        Row() {
          this.filterChip('pinned', $r('app.string.browse_pinned'), 'push_pin')
          this.filterChip('all', $r('app.string.common_all'), 'done_all')
          Divider()
            .vertical(true)
            .height(24)
            .color(this.pal.divider)
            .margin({ right: 8 })
          this.filterChip('results', $r('app.string.has_results'), 'filter_list')
        }
        .alignItems(VerticalAlign.Center)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      // 内容窄于视口时贴左（通用 align 默认 Center 会导致胶囊整体居中）
      .align(Alignment.Start)
      .padding({
        left: 8,
        right: 8,
        top: 4,
        bottom: 8
      })

      Divider()
        .color(this.pal.divider)
        .width('100%')

      // 结果列表：每源一节
      Scroll() {
        Column() {
          ForEach(this.visibleSections(), (section: SearchSection) => {
            this.sectionItem(section)
          }, (section: SearchSection) => `sec-${section.sourceKey}-${section.state}-${section.results.length}`)
        }
        .width('100%')
        .padding({ bottom: this.navBarH + 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }

  // 筛选 Chip（对齐 Mihon FilterChip：图标 + 文案，选中反色）
  // 选中态必须在 Builder 内经 this 读取状态变量：@Builder 按值参数不随状态变化刷新 UI
  @Builder
  filterChip(kind: string, label: ResourceStr, iconName: string) {
    Row() {
      AppIcon({
        name: iconName,
        iconSize: 16,
        tint: this.chipSelected(kind) ? this.pal.onPrimarySoft : this.pal.sub
      })
      Text(label)
        .fontSize(13)
        .fontColor(this.chipSelected(kind) ? this.pal.onPrimarySoft : this.pal.text)
        .margin({ left: 6 })
    }
    .height(32)
    .padding({ left: 14, right: 14 })
    .borderRadius(16)
    .backgroundColor(this.chipSelected(kind) ? this.pal.primarySoft : this.pal.chip)
    .margin({ right: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onChipTap(kind);
    })
  }

  // Chip 选中判定：results 对应“有结果”开关，其余对应源范围筛选
  private chipSelected(kind: string): boolean {
    if (kind === 'results') {
      return this.onlyHasResults;
    }
    return this.sourceFilter === kind;
  }

  private onChipTap(kind: string): void {
    if (kind === 'results') {
      this.toggleResults();
      return;
    }
    this.setSourceFilter(kind);
  }

  @Builder
  sectionItem(section: SearchSection) {
    Column() {
      this.sectionHeader(section)
      this.sectionBody(section)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    // 搜索/筛选驱动的分节增删转场：淡入淡出 + 轻微位移
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
      .animation({ duration: 200, curve: Curve.Friction }))
  }

  // 源标题行（对齐 Mihon GlobalSearchResultItem：源名 + 语言 + 右侧箭头，整行可点进源）
  @Builder
  sectionHeader(section: SearchSection) {
    Row() {
      Column() {
        Text(section.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(langDisplayName(section.lang))
          .fontSize(12)
          .fontColor(this.pal.sub)
          .margin({ top: 1 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      AppIcon({ name: 'arrow_forward', iconSize: 24, tint: this.pal.sub })
        .padding(12)
        .onClick(() => {
          this.openSourceBrowse(section);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 4 })
    .onClick(() => {
      this.openSourceBrowse(section);
    })
  }

  // 分节内容（对齐 Mihon：加载中转圈 / 出错图标+文案 / 无结果文案 / 横向卡片行）
  @Builder
  sectionBody(section: SearchSection) {
    if (section.state === 'loading') {
      LoadingState({ spinnerSize: 16, fill: false })
        .width('100%')
        .padding({ top: 16, bottom: 16 })
    } else if (section.state === 'error') {
      ErrorState({
        message: section.errorMessage !== '' ? section.errorMessage : $r('app.string.global_search_failed')
      })
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 8
        })
    } else if (section.results.length === 0) {
      Text($r('app.string.no_results_found'))
        .fontSize(13)
        .fontColor(this.pal.sub)
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 8
        })
    } else {
      Scroll() {
        Row({ space: 4 }) {
          ForEach(section.results, (record: MangaRecord) => {
            SearchCard({
              record: record,
              onCardClick: (r: MangaRecord): void => {
                this.openDetail(r);
              }
            })
          }, (record: MangaRecord) => `gs-${section.sourceKey}-${record.url}`)
        }
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Top)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .align(Alignment.Start)
    }
  }

  // 点击源标题行：进入该源浏览页并携带当前搜索词（对齐 Mihon onClickSource）
  private openSourceBrowse(section: SearchSection): void {
    const params: BrowseSourceParams = { sourceKey: section.sourceKey, mode: 'popular', query: this.searchQuery };
    this.pathStack.pushPathByName('BrowseSource', params);
  }

  private doneCount(): number {
    let n = 0;
    for (const s of this.sections) {
      if (s.state !== 'loading') {
        n++;
      }
    }
    return n;
  }

  // “只显示有结果的源”过滤后的分节列表
  private visibleSections(): SearchSection[] {
    if (!this.onlyHasResults) {
      return this.sections;
    }
    const list: SearchSection[] = [];
    for (const s of this.sections) {
      if (s.state === 'done' && s.results.length > 0) {
        list.push(s);
      }
    }
    return list;
  }

  // 切换源范围筛选（对齐 Mihon setSourceFilter：切换后立即重搜，同词复用已有结果）
  private setSourceFilter(filter: string): void {
    if (this.sourceFilter === filter) {
      return;
    }
    this.sourceFilter = filter;
    this.startSearch();
  }

  // 切换“只显示有结果的源”（持久化）：“有结果”过滤列表变化包 animateTo 播放分节增删转场
  private toggleResults(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, (): void => {
      this.onlyHasResults = !this.onlyHasResults;
    });
    Settings.setGlobalSearchFilterResults(this.onlyHasResults);
  }

  private updateSection(sourceKey: string, results: MangaRecord[], state: string, errorMessage: string): void {
    const next: SearchSection[] = [];
    for (const s of this.sections) {
      if (s.sourceKey === sourceKey) {
        const updated: SearchSection = new SearchSection();
        updated.sourceKey = s.sourceKey;
        updated.name = s.name;
        updated.lang = s.lang;
        updated.pinned = s.pinned;
        updated.results = results;
        updated.state = state;
        updated.errorMessage = errorMessage;
        next.push(updated);
      } else {
        next.push(s);
      }
    }
    next.sort(sectionCompare);
    this.sections = next;
  }

  // 单源搜索：结果标记“已在库”状态（对齐 Mihon favorite 徽标 + 封面半透明）
  private searchOne(source: Source, q: string): void {
    source.getSearchWorks(1, q).then(async (result: WorksPage) => {
      const libUrls = new Set<string>();
      try {
        const lib = await MangaRepo.getLibraryBySource(source.key);
        for (const r of lib) {
          libUrls.add(r.url);
        }
      } catch (_e) {
      }
      const records: MangaRecord[] = [];
      const seen = new Set<string>();
      for (const m of result.works) {
        if (seen.has(m.key)) {
          continue;
        }
        seen.add(m.key);
        const record = new MangaRecord();
        record.sourceKey = source.key;
        record.url = m.key;
        record.title = m.title;
        record.thumbnailUrl = m.coverUrl;
        // 作品级类型声明优先，未声明回退源（插件）类型
        record.contentType = m.contentType !== undefined && m.contentType !== '' ?
          m.contentType : source.contentType;
        record.inLibrary = libUrls.has(m.key);
        records.push(record);
      }
      this.updateSection(source.key, records, 'done', '');
    }).catch((e: Error) => {
      this.updateSection(source.key, [], 'error', e.message);
    });
  }

  private pinnedKeys(): string[] {
    try {
      const parsed = JSON.parse(Settings.getPinnedSources()) as string[];
      if (Array.isArray(parsed)) {
        const keys: string[] = [];
        for (const k of parsed) {
          if (typeof k === 'string') {
            keys.push(k);
          }
        }
        return keys;
      }
    } catch (_e) {
    }
    return [];
  }

  private sourceTitle(s: Source): string {
    if (s.key === 'local' || s.key === 'local_novel' || s.key === 'local_video') {
      const context = Util.hostAbilityContext(this.getUIContext());
      try {
        if (s.key === 'local') {
          return context.resourceManager.getStringSync($r('app.string.browse_local_source_name').id);
        }
        if (s.key === 'local_novel') {
          return context.resourceManager.getStringSync($r('app.string.browse_local_novel_name').id);
        }
        return context.resourceManager.getStringSync($r('app.string.browse_local_video_name').id);
      } catch (_e) {
        return s.name;
      }
    }
    return s.name;
  }

  private startSearch(): void {
    const q = this.searchQuery.trim();
    if (q === '') {
      return;
    }
    const pinned = this.pinnedKeys();
    // 关闭“显示 NSFW 源”时全局搜索跳过 NSFW 源；置顶筛选只搜已置顶源
    const all: Source[] = SourceRegistry.all();
    const selected: Source[] = [];
    for (const s of all) {
      if (s.nsfw && !Settings.getShowNsfw()) {
        continue;
      }
      if (this.sourceFilter === 'pinned' && pinned.indexOf(s.key) < 0) {
        continue;
      }
      selected.push(s);
    }
    // 源排序：置顶在前，其余按名称（对齐 Mihon getEnabledSources）
    selected.sort((a: Source, b: Source): number => {
      const ap = pinned.indexOf(a.key) >= 0 ? 0 : 1;
      const bp = pinned.indexOf(b.key) >= 0 ? 0 : 1;
      if (ap !== bp) {
        return ap - bp;
      }
      const an = a.name.toLowerCase();
      const bn = b.name.toLowerCase();
      return an < bn ? -1 : (an > bn ? 1 : 0);
    });
    // 同词重搜时复用各源已有结果（对齐 Mihon search 的 sameQuery 复用）
    const reuse = this.lastQuery === q;
    this.lastQuery = q;
    const prevMap = new Map<string, SearchSection>();
    for (const s of this.sections) {
      prevMap.set(s.sourceKey, s);
    }
    const sections: SearchSection[] = [];
    for (const src of selected) {
      const old = prevMap.get(src.key);
      if (reuse && old !== undefined && old.state !== 'loading') {
        const updated: SearchSection = new SearchSection();
        updated.sourceKey = old.sourceKey;
        updated.name = this.sourceTitle(src);
        updated.lang = src.lang;
        updated.pinned = pinned.indexOf(src.key) >= 0;
        updated.results = old.results;
        updated.state = old.state;
        updated.errorMessage = old.errorMessage;
        sections.push(updated);
      } else {
        const section: SearchSection = new SearchSection();
        section.sourceKey = src.key;
        section.name = this.sourceTitle(src);
        section.lang = src.lang;
        section.pinned = pinned.indexOf(src.key) >= 0;
        sections.push(section);
      }
    }
    sections.sort(sectionCompare);
    // 搜索提交/源范围筛选驱动的分节列表变化：包 animateTo，配合分节 transition 播放增删转场
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, (): void => {
      this.sections = sections;
    });
    const context = Util.hostAbilityContext(this.getUIContext());
    AppDb.ready(context).then(() => {
      for (const s of sections) {
        if (s.state !== 'loading') {
          continue;
        }
        const src = SourceRegistry.get(s.sourceKey);
        if (src !== undefined) {
          this.searchOne(src, q);
        } else {
          this.updateSection(s.sourceKey, [], 'error', '');
        }
      }
    }).catch((_e: Error) => {
    });
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function GlobalSearchBuilder() {
  GlobalSearchPage()
}
