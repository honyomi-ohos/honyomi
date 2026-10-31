import { AppDb } from '../data/AppDb';
import { SheetPreset } from './components/SheetPreset';
import { CategoryRepo, MangaRepo } from '../data/Repos';
import { Source, SourceRegistry } from '../source/Source';
import { JsvmSource, RawFilter } from '../source/JsvmSource';
import { LocalFolderManager } from '../source/LocalFolderManager';
import { LocalSource } from '../source/LocalSource';
import { DuplicateManga, CategoryRecord, ContentType, MangaRecord, SManga, WorksPage } from '../model/Models';
import { BrowseSourceParams, DetailParams, DetailSearchResult, ExtensionDetailParams, MigrateSearchParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { LibGrid, Util } from '../common/Util';
import { Bp } from '../common/Breakpoint';
import { MangaCard } from './components/MangaCard';
import { MangaRow } from './components/MangaRow';
import { MangaSkeletonGrid } from './components/MangaSkeletonGrid';
import { EmptyScreen } from './components/EmptyScreen';
import { AppIcon, AppIconRes } from './components/AppIcon';
import { PickerSheet } from './components/PickerSheet';
import { SitePreviewSheet } from './components/SitePreviewSheet';
import { ChangeCategoryDialog, DuplicateMangaDialog } from './components/Dialogs';
import { AppKeys } from '../common/AppKeys';
import { Settings } from '../common/Settings';
import { LibraryAddFlow } from '../common/LibraryAddFlow';
import { IncognitoSourceBanner } from './components/IncognitoSourceBanner';

// 布局切换菜单选项（对齐 Mihon BrowseSourceToolbar 显示模式下拉）
class BrowseDisplayOption {
  key: string = '';
  label: ResourceStr = '';
}

// 单源浏览页（图源 Tab 点进某个源）：顶栏返回 + 标题 + 搜索/布局切换/更多 +
// 顶栏内搜索框（对齐 Mihon SearchToolbar）+ 热门/最新/过滤胶囊行（带图标）+ 结果网格
// 本地源：固定一个本地文件夹（授权持久化），同步进沙箱后按内容归类扫描
@Component
export struct BrowseSourcePage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @State sourceKey: string = '';
  @State mode: string = 'popular';
  @State query: string = '';
  // 标签过滤搜索模式：query 为空仍走 getSearchWorks（过滤器在插件侧生效）
  @State filterSearch: boolean = false;
  @State searchOpen: boolean = false;
  // 结果显示模式：'comfortable' 松散网格 / 'compact' 紧凑网格 / 'list' 列表
  @State displayMode: string = 'comfortable';
  @State showWebView: boolean = false;
  @State results: MangaRecord[] = [];
  @State searching: boolean = false;
  @State page: number = 1;
  @State hasNextPage: boolean = false;
  @State loadingMore: boolean = false;
  @State contentW: number = 0;
  @State folderReady: boolean = false;
  @State syncing: boolean = false;
  @State showFolderSheet: boolean = false;
  // 本地源文件夹模式（对齐 Mihon LocalSource In-folder）：folderPath 为当前相对目录（''=根）
  @State folderMode: boolean = false;
  @State folderPath: string = '';
  // 插件自定义过滤器（getFilterList 拉取，select/checkbox/tristate/text/group）
  @State filters: RawFilter[] = [];
  // 过滤器面板刷新计数：嵌套 state 变更后递增触发 ForEach 重建
  @State filterRev: number = 0;
  @State showFilterSheet: boolean = false;
  // Index 根节点 Esc 广播：关闭文件夹/过滤弹层（计数器递增触发）
  @StorageLink('sheetEsc') @Watch('onSheetEsc') sheetEsc: number = 0;
  // 结果网格视口高度（补拉判定用，不参与渲染）
  private gridH: number = 0;
  // 上次补拉触发时的条数（加载后条数无增长时终止补拉链）
  private fillChecked: number = -1;

  currentSource(): Source | undefined {
    return SourceRegistry.get(this.sourceKey);
  }

  async loadFirst(): Promise<void> {
    const source = this.currentSource();
    if (source === undefined) {
      return;
    }
    if (this.filterSearch) {
      // 离开过滤模式（关闭搜索/切换模式）：复位插件过滤器状态
      this.filterSearch = false;
      if (source instanceof JsvmSource) {
        await source.resetFilters().catch((_e: Error): void => {
        });
      }
    }
    this.searching = true;
    this.results = [];
    this.page = 1;
    this.fillChecked = -1;
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const result = await this.fetchPage(source, 1);
      this.results = await this.toRecords(source.key, result.works);
      this.hasNextPage = result.hasNextPage;
      this.ensureFilled();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_load_failed'),
        [Util.errText(this.getUIContext(), (e as Error).message)]);
    }
    this.searching = false;
  }

  // Esc 广播：关闭文件夹/过滤半模态弹层
  onSheetEsc(): void {
    if (this.showFolderSheet) {
      this.showFolderSheet = false;
    }
    if (this.showFilterSheet) {
      this.showFilterSheet = false;
    }
  }

  async search(): Promise<void> {
    const source = this.currentSource();
    if (source === undefined) {
      return;
    }
    this.searching = true;
    this.results = [];
    this.page = 1;
    this.fillChecked = -1;
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const q = this.query.trim();
      if (q !== '' && this.filterSearch) {
        // 文本搜索前清掉标签过滤残留（对齐 Mihon：每次搜索使用全新默认过滤器）
        this.filterSearch = false;
        if (source instanceof JsvmSource) {
          await source.resetFilters();
        }
      }
      // 过滤搜索模式下空查询仍走搜索接口（过滤器在插件侧生效）
      const result =
        q === '' && !this.filterSearch ? await source.getPopularWorks(1) : await source.getSearchWorks(1, q);
      this.results = await this.toRecords(source.key, result.works);
      this.hasNextPage = result.hasNextPage;
      this.ensureFilled();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_search_failed'),
        [Util.errText(this.getUIContext(), (e as Error).message)]);
    }
    this.searching = false;
  }

  // 命中则以空查询执行过滤器搜索；未命中或源不支持过滤器时回退文本搜索
  async searchGenre(genre: string): Promise<void> {
    const g = genre.trim();
    const source = this.currentSource();
    if (g !== '' && source instanceof JsvmSource &&
      source.hasMethod('getFilterList') && source.hasMethod('applyFilterState')) {
      try {
        const applied = await this.applyGenreFilter(source, g);
        if (applied) {
          this.filterSearch = true;
          this.query = '';
          this.searchOpen = true;
          await this.search();
          return;
        }
      } catch (_e) {
        // 过滤器获取/应用失败：回退文本搜索
      }
    }
    this.filterSearch = false;
    this.query = g;
    this.searchOpen = true;
    await this.search();
  }

  // select 过滤器：标签 + 下拉框（点击展开选项列表）
  @Builder
  filterSelectBuilder(filter: RawFilter) {
    Column() {
      Text(filter.name ?? '')
        .fontSize(14)
        .fontColor(this.pal.sub)
        .margin({ top: 12, bottom: 8 })
      Select(this.selectOptions(filter))
        .selected(this.selectIndex(filter))
        .value(this.selectValueText(filter))
        .width('100%')
        .height(40)
        .font({ size: 16 })
        .fontColor(this.pal.text)
        .backgroundColor(this.pal.chip)
        .borderRadius(8)
        .onSelect((index: number, _text?: string) => {
          this.setFilterSelect(filter, index);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // checkbox 过滤器：图标 + 名称整行，点击勾选/取消（对齐 Mihon CheckboxItem）
  @Builder
  filterCheckboxBuilder(filter: RawFilter) {
    Row() {
      AppIcon({
        name: filter.state === true ? 'check_box' : 'check_box_outline_blank',
        iconSize: 24,
        tint: filter.state === true ? this.pal.primary : this.pal.sub,
      })
        .margin({ right: 16 })
      Text(filter.name ?? '')
        .fontSize(16)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.toggleFilterCheckbox(filter);
    })
  }

  // tri-state 过滤器：图标 + 名称整行，点击循环 忽略→包含→排除（对齐 Mihon TriStateItem）
  @Builder
  filterTristateBuilder(filter: RawFilter) {
    Row() {
      AppIcon({
        name: this.filterTriIcon(this.filterNumberState(filter, 0)),
        iconSize: 24,
        tint: this.filterNumberState(filter, 0) === 0 ? this.pal.sub : this.pal.primary,
      })
        .margin({ right: 16 })
      Text(filter.name ?? '')
        .fontSize(16)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.cycleFilterTristate(filter);
    })
  }

  // 按标签过滤/搜索（对齐 Mihon BrowseSourceViewModel.searchGenre）：
  // 插件源先在过滤器列表中按名匹配标签（tri-state→INCLUDE / checkbox→勾选 / select→选中同值项），

  async loadMore(): Promise<void> {
    const source = this.currentSource();
    if (source === undefined || this.loadingMore || !this.hasNextPage) {
      return;
    }
    this.loadingMore = true;
    let ok = false;
    try {
      const nextPage = this.page + 1;
      const q = this.query.trim();
      const result = q === '' && !this.filterSearch ? await this.fetchPage(source, nextPage) :
        await source.getSearchWorks(nextPage, q);
      const more = await this.toRecords(source.key, result.works);
      this.results = this.results.concat(more);
      this.page = nextPage;
      this.hasNextPage = result.hasNextPage;
      ok = true;
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_load_more_failed'));
    }
    this.loadingMore = false;
    if (ok) {
      // 每次加载完成后都重新判断：单页仍不足以铺满时继续拉下一页，直到铺满或无更多页
      this.ensureFilled();
    }
  }

  // 内容不足一屏时的补拉兜底：大屏列数多 + 插件单页条数少（如哔咔 20 条/页）时，
  // Grid 内容不溢出无法滚动，onReachEnd 永远不触发。按卡片实际尺寸估算铺满视口所需条数，

  async toRecords(sourceKey: string, mangas: SManga[]): Promise<MangaRecord[]> {
    const records: MangaRecord[] = [];
    for (const m of mangas) {
      const record = new MangaRecord();
      record.sourceKey = sourceKey;
      record.url = m.key;
      record.title = m.title;
      record.thumbnailUrl = m.coverUrl;
      record.author = m.author;
      record.description = m.description;
      record.genre = m.genre;
      record.status = m.status;
      const src = SourceRegistry.get(sourceKey);
      // 作品级类型声明优先，未声明回退源（插件）类型
      record.contentType = m.contentType !== undefined && m.contentType !== '' ?
        m.contentType : (src !== undefined ? src.contentType : ContentType.MANGA);
      records.push(record);
    }
    return records;
  }

  async openDetail(record: MangaRecord): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const id = await MangaRepo.upsertFromSource(record.sourceKey, this.toSManga(record), record.contentType);
      const params: DetailParams = { mangaId: id };
      // 详情页内“搜索此处”（源名点击/标签菜单“搜索”）经 popWithResult 回传，回到本页后执行
      this.pathStack.pushPathByName('MangaDetail', params, (popInfo: PopInfo): void => {
        this.onDetailSearchResult(popInfo.result);
      });
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_open_detail_failed'));
    }
  }

  // 已在书架 → 提示；查重提示 → 默认分类分流 → 入库（对齐详情页收藏入库分支）
  async quickAddToLibrary(record: MangaRecord): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const id = await MangaRepo.upsertFromSource(record.sourceKey, this.toSManga(record), record.contentType);
      const existing = await MangaRepo.get(id);
      if (existing !== undefined && existing.inLibrary) {
        Util.toastRes(this.getUIContext(), $r('app.string.detail_in_library'));
        return;
      }
      if (existing === undefined) {
        return;
      }
      // 库内疑似重复（同名标题或相同追踪器绑定）
      const duplicates = await MangaRepo.getDuplicateLibraryManga(id, existing.title);
      if (duplicates.length > 0) {
        this.showQuickDuplicateDialog(existing, duplicates);
        return;
      }
      await this.pickCategoriesAndQuickAdd(existing);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
    }
  }

  // 默认归入分类偏好分流（对齐 MangaViewModel.kt:366-387）；null 时弹分类多选
  private async pickCategoriesAndQuickAdd(record: MangaRecord): Promise<void> {
    const categories = await CategoryRepo.list();
    const preset = LibraryAddFlow.resolveDefaultCategoryIds(categories, Settings.getDefaultCategory());
    if (preset !== null) {
      await LibraryAddFlow.commit(this.getUIContext(), record, preset);
      return;
    }
    this.showQuickAddCategoryDialog(record, categories);
  }

  // ---- 过滤器面板 Builder（对齐 Mihon SourceFilterDialog：下拉/整行切换，不用胶囊） ----

  toSManga(record: MangaRecord): SManga {
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
    return m;
  }

  // text 过滤器：标签 + 输入框
  @Builder
  filterTextBuilder(filter: RawFilter) {
    Column() {
      Text(filter.name ?? '')
        .fontSize(14)
        .fontColor(this.pal.sub)
        .margin({ top: 12, bottom: 8 })
      TextInput({ text: typeof filter.state === 'string' ? filter.state as string : '' })
        .height(40)
        .fontSize(16)
        .backgroundColor(this.pal.chip)
        .onChange((value: string) => {
          filter.state = value;
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 单个过滤器分发（未知类型不渲染）
  @Builder
  filterLeafBuilder(filter: RawFilter) {
    Column() {
      if (filter.type === 'select') {
        this.filterSelectBuilder(filter)
      } else if (filter.type === 'checkbox') {
        this.filterCheckboxBuilder(filter)
      } else if (filter.type === 'tristate' || filter.type === 'tri-state') {
        this.filterTristateBuilder(filter)
      } else if (filter.type === 'text') {
        this.filterTextBuilder(filter)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // group 过滤器：组名标题 + 子项逐行展示（对齐 Mihon Filter.Group）
  @Builder
  filterGroupBuilder(group: RawFilter, idPrefix: string) {
    Column() {
      if ((group.name ?? '') !== '') {
        Text(group.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.sub)
          .margin({ top: 16, bottom: 8 })
      }
      ForEach(group.filters ?? [], (sub: RawFilter, subIndex: number) => {
        this.filterLeafBuilder(sub)
      }, (sub: RawFilter, subIndex: number): string => `${idPrefix}-g${subIndex}-${this.filterRev}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 过滤器面板（HDS 半模态规范，高度自适应内容）：选项区在上、底部固定操作区（重置 | 过滤）在下，
  // 单个筛选项时弹层贴内容收起；选项行 48vp 触控高度、16fp 正文、24vp 侧边距，
  // 列表超出系统限高时在 Scroll 内滚动，底部按钮始终可见
  @Builder
  filterSheetBuilder() {
    Column() {
      if (this.filters.length === 0) {
        Text($r('app.string.browse_filter_empty'))
          .fontSize(14)
          .fontColor(this.pal.sub)
          .padding({ top: 32, bottom: 32 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.filters, (filter: RawFilter, index: number) => {
              if (filter.type === 'group') {
                this.filterGroupBuilder(filter, `f${index}`)
              } else {
                this.filterLeafBuilder(filter)
              }
            }, (filter: RawFilter, index: number): string => `flt-${index}-${this.filterRev}`)
          }
          .width('100%')
          .padding({
            left: 24,
            right: 24,
            top: 4,
            bottom: 8
          })
        }
        .width('100%')
        .scrollBar(BarState.Off)
      }

      Divider()
        .color(this.pal.divider)
        .margin({ left: 24, right: 24 })

      // 底部操作区：重置（次要）+ 过滤（主操作）等宽双按钮
      Row({ space: 12 }) {
        Button($r('app.string.browse_filter_reset'))
          .layoutWeight(1)
          .height(40)
          .fontSize(16)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.resetFilterSheet();
          })
        Button($r('app.string.action_filter'))
          .layoutWeight(1)
          .height(40)
          .fontSize(16)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .onClick(() => {
            this.applyFilters();
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 24 })
    }
    .width('100%')
  }

  @Builder
  folderSheetBuilder() {
    PickerSheet({
      options: [$r('app.string.browse_local_sync'), $r('app.string.browse_local_change')],
      icons: ['refresh', 'folder'],
      selectedIndex: -1,
      onPick: (index: number): void => {
        this.showFolderSheet = false;
        if (index === 0) {
          this.syncNow();
        } else {
          this.chooseFolder();
        }
      },
    })
  }

  // 布局切换下拉（对齐 Mihon BrowseSourceToolbar 显示模式 DropdownMenu）：标准 MenuItem，无选中标记
  @Builder
  displayModeMenuBuilder() {
    Menu() {
      ForEach(this.displayModeOptions(), (opt: BrowseDisplayOption) => {
        MenuItem({ content: opt.label })
          .onClick(() => {
            this.applyDisplayMode(opt.key);
          })
      }, (opt: BrowseDisplayOption) => `dm-${opt.key}`)
    }
  }

  // 右上角更多菜单（对齐 Mihon BrowseSourceToolbar 溢出菜单）：
  // 插件源：网页视图（源站首页）/ 设置（插件详情页）；本地源：帮助
  @Builder
  sourceMenuBuilder() {
    Menu() {
      if (this.sourceHomeUrl() !== '') {
        MenuItem({ content: $r('app.string.detail_action_webview') })
          .onClick(() => {
            this.showWebView = true;
          })
      }
      if (this.currentSource() instanceof JsvmSource) {
        MenuItem({ content: $r('app.string.settings_title') })
          .onClick(() => {
            this.openSourceSettings();
          })
      }
      if (ContentType.isLocal(this.sourceKey)) {
        MenuItem({ content: $r('app.string.help_title') })
          .onClick(() => {
            this.pathStack.pushPathByName('Help', null);
          })
      }
    }
  }

  // 源站首页 WebView 半模态（复用 SitePreviewSheet：注入 CookieJar 会话）
  @Builder
  webViewSheetBuilder() {
    SitePreviewSheet({
      siteUrl: this.sourceHomeUrl(),
      defaultTitle: this.currentSource() !== undefined ?
        Util.localSourceName(this.getUIContext(), this.sourceKey, (this.currentSource() as Source).name) : '',
      onClose: (): void => {
        this.showWebView = false;
      }
    })
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          // 顶栏（对齐 Mihon SearchToolbar/BrowseSourceToolbar）：
          // 常态：返回 + 标题 + [搜索 | 布局切换 | 更多]；
          // 搜索态：返回（关闭搜索）+ 顶栏内搜索框 + [布局切换 | 更多]（对齐浏览页头部的插件搜索）
          Row() {
            AppIcon({ name: 'arrow_back', iconSize: 24 })
              .onClick(() => {
                if (this.searchOpen && !ContentType.isLocal(this.sourceKey)) {
                  this.closeSearch();
                } else {
                  this.pathStack.pop();
                }
              })
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -16 })))

            if (this.searchOpen && !ContentType.isLocal(this.sourceKey)) {
              TextInput({
                text: this.query,
                placeholder: $r('app.string.browse_search_hint')
              })
                .id('sourceSearchInput')
                .layoutWeight(1)
                .height(38)
                .fontSize(15)
                .fontColor(this.pal.text)
                .placeholderColor(this.pal.sub)
                .caretColor(this.pal.primary)
                .backgroundColor(this.pal.chip)
                .borderRadius(19)
                .padding({ left: 16, right: 16 })
                .margin({ left: 8 })
                .enterKeyType(EnterKeyType.Search)
                .onChange((value: string) => {
                  this.query = value;
                })
                .onSubmit(() => {
                  this.search();
                })
                .transition(TransitionEffect.OPACITY)
            } else {
              Text(this.currentSource() !== undefined ?
                Util.localSourceName(this.getUIContext(), this.sourceKey, (this.currentSource() as Source).name) : '')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal.text)
                .margin({ left: 8 })
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .transition(TransitionEffect.OPACITY)
            }

            if (ContentType.isLocal(this.sourceKey)) {
              Text(this.folderReady ? $r('app.string.browse_local_sync') : $r('app.string.browse_local_setup'))
                .fontSize(13)
                .fontColor(this.pal.primary)
                .padding({ left: 8, right: 8 })
                .onClick(() => {
                  if (this.folderReady) {
                    this.showFolderSheet = true;
                  } else {
                    this.chooseFolder();
                  }
                })
            } else {
              if (!this.searchOpen) {
                AppIcon({ name: 'search', iconSize: 20 })
                  .padding({ left: 10, right: 10 })
                  .onClick(() => {
                    this.openSearch();
                  })
                  .transition(TransitionEffect.OPACITY)
              }
            }

            // 布局切换（当前为列表时显示列表图标，否则网格图标；点击下拉选择显示模式）
            AppIcon({ name: this.displayMode === 'list' ? 'view_list' : 'view_module', iconSize: 20 })
              .padding({ left: 10, right: 10 })
              .bindMenu(this.displayModeMenuBuilder)

            // 更多菜单
            AppIcon({ name: 'more_vert', iconSize: 20 })
              .padding({ left: 0, right: 4 })
              .bindMenu(this.sourceMenuBuilder)
          }
          .width('100%')
          // 固定内容高度 = 搜索态行高（容纳 38 高搜索框），避免展开搜索时顶栏高度跳变；
          // statusBar 间距用 margin 外扩（height 含 padding 会挤压内容导致溢出重叠）
          .height(48)
          .padding({ left: 16, right: 16 })
          .margin({ top: this.statusBarH })
          .bindSheet($$this.showWebView, this.webViewSheetBuilder(),
            SheetPreset.fit(this.windowW, {
              height: SheetSize.LARGE,
              detents: [SheetSize.MEDIUM, SheetSize.LARGE],
              showClose: false,
              wideWidth: 560,
              maskColor: 'rgba(0,0,0,0.45)'
            }))

          // 按插件隐身提示条（所属插件开启「隐身浏览」时显示）
          IncognitoSourceBanner({ sourceKey: this.sourceKey })
            .padding({
              left: 16,
              right: 16,
              bottom: 6
            })

          // 模式切换行：热门 / 最近更新 / 过滤 同行（对齐 Mihon BrowseSourceScreen FilterChip 行，胶囊带图标）
          if (!ContentType.isLocal(this.sourceKey) &&
            (this.currentSource()?.supportsLatest === true || this.sourceSupportsFilters())) {
            Row({ space: 8 }) {
              // 热门（Mihon FilterChip leadingIcon: RoundedFilled.Favorite）
              Row({ space: 5 }) {
                AppIcon({
                  name: 'favorite',
                  iconSize: 15,
                  tint: !this.filterSearch && this.mode === 'popular' ? this.pal.onPrimary : this.pal.sub,
                })
                Text($r('app.string.browse_popular'))
                  .fontSize(13)
                  .fontColor(!this.filterSearch && this.mode === 'popular' ? this.pal.onPrimary : this.pal.sub)
              }
              .backgroundColor(!this.filterSearch && this.mode === 'popular' ? this.pal.primary : this.pal.chip)
              .borderRadius(12)
              .padding({
                left: 12,
                right: 14,
                top: 4,
                bottom: 4
              })
              .onClick(() => {
                if (this.mode !== 'popular' || this.filterSearch) {
                  this.mode = 'popular';
                  this.loadFirst();
                }
              })
              if (this.currentSource()?.supportsLatest === true) {
                // 最新（Mihon FilterChip leadingIcon: Rounded.NewReleases）
                Row({ space: 5 }) {
                  AppIcon({
                    name: 'new_releases',
                    iconSize: 15,
                    tint: !this.filterSearch && this.mode === 'latest' ? this.pal.onPrimary : this.pal.sub,
                  })
                  Text($r('app.string.browse_latest'))
                    .fontSize(13)
                    .fontColor(!this.filterSearch && this.mode === 'latest' ? this.pal.onPrimary : this.pal.sub)
                }
                .backgroundColor(!this.filterSearch && this.mode === 'latest' ? this.pal.primary : this.pal.chip)
                .borderRadius(12)
                .padding({
                  left: 12,
                  right: 14,
                  top: 4,
                  bottom: 4
                })
                .onClick(() => {
                  if (this.mode !== 'latest' || this.filterSearch) {
                    this.mode = 'latest';
                    this.loadFirst();
                  }
                })
              }
              // 插件自定义过滤器入口（过滤器激活时高亮；Mihon leadingIcon: Rounded.FilterList）
              if (this.sourceSupportsFilters()) {
                Row({ space: 5 }) {
                  AppIcon({
                    name: 'filter_list',
                    iconSize: 15,
                    tint: this.filterSearch ? this.pal.onPrimary : this.pal.sub,
                  })
                  Text($r('app.string.action_filter'))
                    .fontSize(13)
                    .fontColor(this.filterSearch ? this.pal.onPrimary : this.pal.sub)
                }
                .backgroundColor(this.filterSearch ? this.pal.primary : this.pal.chip)
                .borderRadius(12)
                .padding({
                  left: 12,
                  right: 14,
                  top: 4,
                  bottom: 4
                })
                .onClick(() => {
                  this.openFilterSheet();
                })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 8 })
          }

          // 本地源模式切换行：热门 / 文件夹（+ 返回上级），对齐 Mihon LocalSource In-folder，胶囊带图标
          if (this.currentSource() instanceof LocalSource) {
            Row({ space: 8 }) {
              Row({ space: 5 }) {
                AppIcon({
                  name: 'favorite',
                  iconSize: 15,
                  tint: !this.folderMode ? this.pal.onPrimary : this.pal.sub,
                })
                Text($r('app.string.browse_popular'))
                  .fontSize(13)
                  .fontColor(!this.folderMode ? this.pal.onPrimary : this.pal.sub)
              }
              .backgroundColor(!this.folderMode ? this.pal.primary : this.pal.chip)
              .borderRadius(12)
              .padding({
                left: 12,
                right: 14,
                top: 4,
                bottom: 4
              })
              .onClick(() => {
                if (this.folderMode) {
                  this.folderMode = false;
                  this.folderPath = '';
                  this.loadFirst();
                }
              })
              Row({ space: 5 }) {
                AppIcon({
                  name: 'folder',
                  iconSize: 15,
                  tint: this.folderMode ? this.pal.onPrimary : this.pal.sub,
                })
                Text($r('app.string.browse_local_folders'))
                  .fontSize(13)
                  .fontColor(this.folderMode ? this.pal.onPrimary : this.pal.sub)
              }
              .backgroundColor(this.folderMode ? this.pal.primary : this.pal.chip)
              .borderRadius(12)
              .padding({
                left: 12,
                right: 14,
                top: 4,
                bottom: 4
              })
              .onClick(() => {
                if (!this.folderMode) {
                  this.folderMode = true;
                  this.folderPath = '';
                  this.loadFolder();
                }
              })
              if (this.folderMode && this.folderPath !== '') {
                Text($r('app.string.browse_folder_up'))
                  .fontSize(13)
                  .fontColor(this.pal.sub)
                  .backgroundColor(this.pal.chip)
                  .borderRadius(12)
                  .padding({
                    left: 12,
                    right: 12,
                    top: 4,
                    bottom: 4
                  })
                  .onClick(() => {
                    this.openParentFolder();
                  })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 8 })
          }

          // 结果网格
          if (this.currentSource() === undefined) {
            Column() {
              EmptyScreen({ message: $r('app.string.browse_source_missing') })
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.searching) {
            // 首次加载骨架屏（与结果网格同布局的占位卡片）
            MangaSkeletonGrid({ columns: this.gridColumns() })
          } else if (this.results.length === 0) {
            Column() {
              EmptyScreen({
                message: this.localEmptyMessage(),
              })
              if (ContentType.isLocal(this.sourceKey) && !this.folderReady) {
                Button($r('app.string.browse_local_setup'))
                  .fontSize(14)
                  .height(38)
                  .padding({ left: 20, right: 20 })
                  .backgroundColor(this.pal.primary)
                  .fontColor(this.pal.onPrimary)
                  .borderRadius(19)
                  .margin({ top: 20 })
                  .onClick(() => {
                    this.chooseFolder();
                  })
              }
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Grid() {
              ForEach(this.results, (record: MangaRecord) => {
                GridItem() {
                  if (this.displayMode === 'list') {
                    // 列表模式（对齐 Mihon BrowseSourceList）
                    MangaRow({
                      record: record,
                      onRowClick: (r: MangaRecord): void => {
                        this.onResultItemClicked(r);
                      },
                      onRowLongPress: (r: MangaRecord): void => {
                        if (this.folderMode && r.status === 'local_folder') {
                          return;
                        }
                        this.quickAddToLibrary(r);
                      },
                    })
                  } else {
                    MangaCard({
                      record: record,
                      badge: this.nsfwBadge(),
                      mode: this.displayMode,
                      onCardClick: (r: MangaRecord): void => {
                        this.onResultItemClicked(r);
                      },
                      onCardLongPress: (r: MangaRecord): void => {
                        if (this.folderMode && r.status === 'local_folder') {
                          return;
                        }
                        this.quickAddToLibrary(r);
                      },
                      onCardMenuAddToLibrary: (r: MangaRecord): void => {
                        if (this.folderMode && r.status === 'local_folder') {
                          return;
                        }
                        this.quickAddToLibrary(r);
                      },
                    })
                  }
                }
              }, (record: MangaRecord) => `bs-${record.sourceKey}-${record.url}`)
            }
            .columnsTemplate(this.columnsTpl())
            .columnsGap(12)
            .rowsGap(16)
            .padding({ left: 16, right: 16, top: 4 })
            .contentEndOffset(this.navBarH + 16)
            .layoutWeight(1)
            .onReachEnd(() => {
              this.loadMore();
            })
            .onAreaChange((_old: Area, newArea: Area) => {
              // Grid 首次上屏时 gridH 才有值，此处启动补拉链；窗口/旋转变化时同样补拉
              const w = newArea.width;
              if (typeof w === 'number') {
                this.applyContentW(w);
              }
              const h = newArea.height;
              if (typeof h === 'number') {
                this.gridH = h;
              }
              this.ensureFilled();
            })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.pal.bg)
        .bindSheet($$this.showFolderSheet, this.folderSheetBuilder(),
          SheetPreset.fit(this.windowW, {
            title: $r('app.string.browse_local_folder_title'),
            showClose: false
          }))
        .onAreaChange((_old: Area, newArea: Area) => {
          const w = newArea.width;
          if (typeof w === 'number') {
            this.applyContentW(w);
          }
        })

        // 同步中遮罩
        if (this.syncing) {
          Column() {
            Column() {
              LoadingProgress()
                .width(44)
                .height(44)
                .color(this.pal.primary)
              Text($r('app.string.browse_local_syncing'))
                .fontSize(14)
                .fontColor(this.pal.text)
                .margin({ top: 12 })
            }
            .padding({
              left: 36,
              right: 36,
              top: 28,
              bottom: 28
            })
            .borderRadius(20)
            .backgroundColor(this.pal.card)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(0,0,0,0.45)')
        }
      }
      .width('100%')
      .height('100%')
      // 插件自定义过滤器半模态（挂在 Stack 根上，与内层 Column 的文件夹 Sheet 分离）：
      // 高度自适应内容（SheetPreset 默认 FIT_CONTENT），筛选项少时弹层收起，多时滚动
      .bindSheet($$this.showFilterSheet, this.filterSheetBuilder(),
        SheetPreset.fit(this.windowW, {
          title: $r('app.string.action_filter'),
          showClose: true
        }))
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as BrowseSourceParams;
      this.sourceKey = params !== undefined && params !== null ? params.sourceKey : '';
      this.mode = params !== undefined && params !== null && params.mode === 'latest' ? 'latest' : 'popular';
      // 记录最近使用（图源 Tab 顶部“最近使用”分组数据源）
      Settings.touchRecentSource(this.sourceKey);
      this.folderMode = false;
      this.folderPath = '';
      this.folderReady = LocalFolderManager.hasFolder();
      // 显示模式偏好（布局切换菜单写入）；非法值回退松散网格
      const savedView = Settings.getBrowseView();
      this.displayMode = savedView === 'compact' || savedView === 'list' ? savedView : 'comfortable';
      // 外部"打开方式"导入书籍后跳入：预填搜索词并直接执行，定位导入的书籍
      const prefill = params !== undefined && params !== null && params.query !== undefined ? params.query : '';
      if (prefill !== '') {
        this.searchOpen = true;
        this.query = prefill;
        this.search();
      } else {
        this.loadFirst();
      }
    })
  }

  // 不足则继续加载下一页；loadMore 成功后回到这里形成补拉链。
  private ensureFilled(): void {
    if (this.gridH <= 0 || this.results.length === 0 || this.loadingMore || !this.hasNextPage) {
      return;
    }
    // 上次补拉后条数没有增长（插件返回空页）：终止补拉链，避免死循环
    if (this.results.length === this.fillChecked) {
      return;
    }
    const columns = this.gridColumns();
    // 卡片宽度 = (网格宽 - 左右内边距 32 - 列间距 12*(cols-1)) / cols
    const cardW = (this.contentW - 32 - (columns - 1) * 12) / columns;
    const rowH = this.rowHeightEstimate(cardW);
    // 多备一行缓冲：内容恰好等于视口高度时仍不可滚动，预留余量保证 onReachEnd 可触发
    const rowsNeeded = Math.ceil(this.gridH / rowH) + 1;
    if (this.results.length < rowsNeeded * columns) {
      this.fillChecked = this.results.length;
      this.loadMore();
    }
  }

  // 各显示模式下的行高估计（补拉判定用）：列表固定行高；紧凑网格无下方标题；
  // 松散网格 = 封面（宽高比 0.7）+ 标题两行 + 行间距
  private rowHeightEstimate(cardW: number): number {
    if (this.displayMode === 'list') {
      return 74;
    }
    if (this.displayMode === 'compact') {
      return cardW / 0.7;
    }
    return cardW / 0.7 + 56;
  }

  // NSFW 源内的漫画卡片角标（MangaCard 右下红标）
  private nsfwBadge(): string {
    const source = this.currentSource();
    return source !== undefined && source.nsfw ? 'NSFW' : '';
  }

  // 结果网格列数：与书架保持一致——手动列数按可行区间收敛，0=自动（约 128vp 一格）
  private colsForWidth(w: number): number {
    const manual: number = Settings.getLibraryGridCols();
    if (manual > 0) {
      return LibGrid.clampCols(manual, w);
    }
    return LibGrid.autoCols(w);
  }

  // 首帧宽度估计：窗口宽扣除宽屏侧边导航栏（真实宽度待 onAreaChange 首次测量回填），
  // 避免大屏首帧按 360vp 兜底算出 2 列、骨架/网格先渲染出超大封面
  private estContentW(): number {
    if (this.windowW <= 0) {
      return 360;
    }
    return Math.max(0, this.windowW - (Bp.isWide(this.windowW) ? Bp.WIDE_RAIL_W : 0));
  }

  private gridColumns(): number {
    // 列表模式固定单列（对齐 Mihon BrowseSourceList）
    if (this.displayMode === 'list') {
      return 1;
    }
    const w = this.contentW > 0 ? this.contentW : this.estContentW();
    return this.colsForWidth(w);
  }

  // 网格宽变化：列数档位变化时包 animateTo，让网格重排带过渡动画；
  // 首次测量回填不包动画——首帧已按窗口宽估计列数，档位校正即时生效，不播收缩动画
  private applyContentW(w: number): void {
    if (w === this.contentW) {
      return;
    }
    const firstMeasure: boolean = this.contentW <= 0;
    const reflow: boolean = this.colsForWidth(w) !== this.gridColumns();
    if (!firstMeasure && reflow) {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, (): void => {
        this.contentW = w;
      });
    } else {
      this.contentW = w;
    }
  }

  private columnsTpl(): string {
    let tpl = '';
    for (let i = 0; i < this.gridColumns(); i++) {
      tpl += '1fr ';
    }
    return tpl.trim();
  }

  // 结果条目点击（网格/列表共用）：文件夹模式目录条目下钻而非进详情
  private onResultItemClicked(record: MangaRecord): void {
    if (this.folderMode && record.status === 'local_folder') {
      this.folderPath = record.url;
      this.loadFolder();
      return;
    }
    this.openDetail(record);
  }

  // 打开顶栏搜索框（展开动画结束后自动聚焦拉起键盘，对齐浏览页头部的插件搜索）
  private openSearch(): void {
    this.getUIContext().animateTo({
      duration: 250,
      curve: Curve.Friction,
      onFinish: (): void => {
        this.getUIContext().getFocusController().requestFocus('sourceSearchInput');
      }
    }, (): void => {
      this.searchOpen = true;
    });
  }

  // 关闭顶栏搜索框并复位列表
  private closeSearch(): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, (): void => {
      this.searchOpen = false;
      this.query = '';
    });
    this.loadFirst();
  }

  // 布局切换下拉选项（对齐 Mihon BrowseSourceToolbar：松散网格 / 紧凑网格 / 列表）
  private displayModeOptions(): BrowseDisplayOption[] {
    const opts: BrowseDisplayOption[] = [];
    const comfortable = new BrowseDisplayOption();
    comfortable.key = 'comfortable';
    comfortable.label = $r('app.string.lib_display_comfortable');
    opts.push(comfortable);
    const compact = new BrowseDisplayOption();
    compact.key = 'compact';
    compact.label = $r('app.string.lib_display_compact');
    opts.push(compact);
    const list = new BrowseDisplayOption();
    list.key = 'list';
    list.label = $r('app.string.lib_display_list');
    opts.push(list);
    return opts;
  }

  // 切换结果显示模式：包 animateTo 配合网格/列表分支转场；持久化偏好
  private applyDisplayMode(nextMode: string): void {
    if (this.displayMode === nextMode) {
      return;
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, (): void => {
      this.displayMode = nextMode;
    });
    Settings.setBrowseView(nextMode);
    this.fillChecked = -1;
    this.ensureFilled();
  }

  // 源站首页地址（网页视图菜单用）：插件 manifest.baseUrl，非 http(s) 返回空
  private sourceHomeUrl(): string {
    const source = this.currentSource();
    if (source instanceof JsvmSource) {
      const base = source.manifest.baseUrl;
      if (base.startsWith('http://') || base.startsWith('https://')) {
        return base;
      }
    }
    return '';
  }

  // 更多菜单 → 设置：跳转所属插件详情页（插件设置/源设置入口）
  private openSourceSettings(): void {
    const source = this.currentSource();
    if (source instanceof JsvmSource) {
      const params: ExtensionDetailParams = { pluginKey: source.packageKey };
      this.pathStack.pushPathByName('ExtensionDetail', params);
    }
  }

  // 当前模式下的列表页（最新模式仅在源支持时生效）
  private fetchPage(source: Source, page: number): Promise<WorksPage> {
    if (this.mode === 'latest' && source.supportsLatest) {
      return source.getLatestWorks(page);
    }
    return source.getPopularWorks(page);
  }

  // 文件夹模式加载：browseFolder 不分页（hasNextPage 恒 false，loadMore 自然短路）
  private async loadFolder(): Promise<void> {
    const source = this.currentSource();
    if (!(source instanceof LocalSource)) {
      return;
    }
    this.searching = true;
    this.results = [];
    this.hasNextPage = false;
    try {
      const works = await source.browseFolder(this.folderPath);
      this.results = await this.toRecords(source.key, works);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_load_failed'),
        [Util.errText(this.getUIContext(), (e as Error).message)]);
    }
    this.searching = false;
  }

  // 返回上级目录：folderPath 去掉最后一段；根目录时按钮不显示
  private openParentFolder(): void {
    const segs = this.folderPath.split('/');
    segs.pop();
    this.folderPath = segs.join('/');
    this.loadFolder();
  }

  // 在插件过滤器列表中按名匹配标签并置位；命中返回 true（未命中不改过滤器状态）
  private async applyGenreFilter(source: JsvmSource, genre: string): Promise<boolean> {
    const list = await source.getFilterList();
    if (!Array.isArray(list) || list.length === 0) {
      return false;
    }
    let matched = false;
    for (let i = 0; i < list.length; i++) {
      const filter = list[i];
      // applyFilterState 契约：顶层序号由宿主回传前写入
      filter.index = i;
      const type = filter.type ?? '';
      if (type === 'group' && filter.filters !== undefined) {
        for (let j = 0; j < filter.filters.length; j++) {
          if (this.matchGenreFilter(filter.filters[j], genre)) {
            matched = true;
          }
        }
      } else if (this.matchGenreFilter(filter, genre)) {
        matched = true;
      }
    }
    if (!matched) {
      return false;
    }
    await source.applyFilterState(list);
    return true;
  }

  // 单个过滤器按名匹配置位：tri-state→1(INCLUDE)、checkbox→勾选、select→选中同值项
  private matchGenreFilter(filter: RawFilter, genre: string): boolean {
    const name = filter.name ?? '';
    if (name.toLowerCase() !== genre.toLowerCase()) {
      return false;
    }
    const type = filter.type ?? '';
    if (type === 'tristate' || type === 'tri-state') {
      filter.state = 1;
      return true;
    }
    if (type === 'checkbox') {
      filter.state = true;
      return true;
    }
    if (type === 'select' && filter.values !== undefined) {
      for (let i = 0; i < filter.values.length; i++) {
        const v = filter.values[i];
        if (typeof v === 'string' && (v as string).toLowerCase() === genre.toLowerCase()) {
          filter.state = i;
          return true;
        }
      }
    }
    return false;
  }

  // 源是否支持自定义过滤器（插件导出 getFilterList + applyFilterState）
  private sourceSupportsFilters(): boolean {
    const source = this.currentSource();
    return source instanceof JsvmSource &&
      source.hasMethod('getFilterList') && source.hasMethod('applyFilterState');
  }

  // 打开过滤器面板：拉取插件当前过滤器（state 反映插件侧偏好持久值）
  private async openFilterSheet(): Promise<void> {
    const source = this.currentSource();
    if (!(source instanceof JsvmSource)) {
      return;
    }
    try {
      this.filters = await source.getFilterList();
    } catch (_e) {
      this.filters = [];
    }
    this.filterRev++;
    this.showFilterSheet = true;
  }

  // 应用过滤器并触发过滤搜索：空查询走搜索接口（过滤器在插件侧生效）
  private async applyFilters(): Promise<void> {
    const source = this.currentSource();
    if (!(source instanceof JsvmSource)) {
      return;
    }
    // applyFilterState 契约：顶层序号由宿主回传前写入
    for (let i = 0; i < this.filters.length; i++) {
      this.filters[i].index = i;
    }
    this.showFilterSheet = false;
    await source.applyFilterState(this.filters).catch((_e: Error): void => {
    });
    this.filterSearch = true;
    this.query = '';
    this.searchOpen = true;
    await this.search();
  }

  // 重置插件过滤器并刷新面板
  private async resetFilterSheet(): Promise<void> {
    const source = this.currentSource();
    if (!(source instanceof JsvmSource)) {
      return;
    }
    try {
      await source.resetFilters();
      this.filters = await source.getFilterList();
    } catch (_e) {
      // 重置失败：保留当前面板内容
    }
    this.filterRev++;
  }

  // 长按卡片快速加入书架（对齐详情页入库逻辑）：

  private setFilterSelect(filter: RawFilter, index: number): void {
    filter.state = index;
    this.filterRev++;
  }

  private toggleFilterCheckbox(filter: RawFilter): void {
    filter.state = filter.state !== true;
    this.filterRev++;
  }

  // tri-state 点击循环：0 忽略 → 1 包含 → 2 排除 → 0（对齐 Mihon TriStateItem）
  private cycleFilterTristate(filter: RawFilter): void {
    const cur = this.filterNumberState(filter, 0);
    filter.state = cur === 0 ? 1 : (cur === 1 ? 2 : 0);
    this.filterRev++;
  }

  // tri-state 图标：0 空心 / 1 勾选 / 2 禁用（对齐 Mihon TriState 图标）
  private filterTriIcon(state: number): string {
    if (state === 1) {
      return 'check_box';
    }
    if (state === 2) {
      return 'disabled_by_default';
    }
    return 'check_box_outline_blank';
  }

  // 详情页回传的搜索请求（对齐 Mihon BrowseSourceController.search/searchGenre）：

  private filterNumberState(filter: RawFilter, fallback: number): number {
    return typeof filter.state === 'number' ? filter.state as number : fallback;
  }

  // select 过滤器选中下标（越界钳制到有效范围）
  private selectIndex(filter: RawFilter): number {
    const len = (filter.values ?? []).length;
    if (len === 0) {
      return 0;
    }
    const idx = this.filterNumberState(filter, 0);
    return Math.min(Math.max(idx, 0), len - 1);
  }

  // select 过滤器下拉选项（对齐 Mihon SelectItem 的 ExposedDropdownMenu）
  private selectOptions(filter: RawFilter): SelectOption[] {
    const options: SelectOption[] = [];
    const values = filter.values ?? [];
    for (let i = 0; i < values.length; i++) {
      const opt: SelectOption = { value: String(values[i]) };
      options.push(opt);
    }
    return options;
  }

  // select 过滤器当前选中值文本
  private selectValueText(filter: RawFilter): string {
    const values = filter.values ?? [];
    const idx = this.selectIndex(filter);
    if (idx < values.length) {
      return String(values[idx]);
    }
    return '';
  }

  // 快速入库分类多选弹窗（默认分类为「每次都询问」时）
  private showQuickAddCategoryDialog(record: MangaRecord, categories: CategoryRecord[]): void {
    const dialog = new CustomDialogController({
      builder: ChangeCategoryDialog({
        categories: categories,
        preselectedIds: [],
        title: $r('app.string.detail_add_to_library'),
        onConfirm: (categoryIds: number[]): void => {
          LibraryAddFlow.commit(this.getUIContext(), record,
            LibraryAddFlow.normalizeCategoryIds(categoryIds)).catch((_e: Error): void => {
            Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
          });
        },
        onEditCategories: (): void => {
          this.pathStack.pushPathByName('Categories', null);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  // 快速入库查重弹窗：依然添加继续入库；点卡片迁移、长按打开详情
  private showQuickDuplicateDialog(record: MangaRecord, duplicates: DuplicateManga[]): void {
    const dialog = new CustomDialogController({
      builder: DuplicateMangaDialog({
        duplicates: duplicates,
        onAddAnyway: (): void => {
          this.pickCategoriesAndQuickAdd(record).catch((_e: Error): void => {
            Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
          });
        },
        onOpenManga: (mangaId: number): void => {
          const params: DetailParams = { mangaId: mangaId };
          this.pathStack.pushPathByName('MangaDetail', params);
        },
        onMigrate: (mangaId: number): void => {
          const params: MigrateSearchParams = { mangaIds: [mangaId] };
          this.pathStack.pushPathByName('MigrateSearch', params);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  // search = 页内文本搜索；searchGenre = 按标签过滤（源不支持过滤器时回退文本搜索）
  private onDetailSearchResult(result: Object): void {
    const r = result as DetailSearchResult;
    if (r === undefined || r === null || r.query === undefined) {
      return;
    }
    if (r.action === 'search') {
      this.query = r.query;
      this.searchOpen = true;
      this.search();
    } else if (r.action === 'searchGenre') {
      this.searchGenre(r.query);
    }
  }

  private localEmptyMessage(): ResourceStr {
    // 文件夹模式：目录为空
    if (this.folderMode) {
      return $r('app.string.browse_folder_empty');
    }
    if (ContentType.isLocal(this.sourceKey)) {
      if (!this.folderReady) {
        return $r('app.string.browse_local_folder_empty');
      }
      if (this.sourceKey === 'local') {
        return $r('app.string.browse_local_comic_empty');
      }
      if (this.sourceKey === 'local_novel') {
        return $r('app.string.browse_local_novel_empty');
      }
      return $r('app.string.browse_local_anime_empty');
    }
    return $r('app.string.browse_no_results');
  }

  // 设备是否支持文件夹选择（FOLDER 模式 Picker）
  private folderSupported(): boolean {
    return canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection');
  }

  // 选择本地源文件夹（授权持久化）并立即同步
  private async chooseFolder(): Promise<void> {
    if (!this.folderSupported()) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_local_folder_unsupported'));
      return;
    }
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const ok = await LocalFolderManager.chooseFolder(context);
      if (!ok) {
        return;
      }
      this.folderReady = true;
      await this.syncNow();
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'PERSIST') {
        Util.toastRes(this.getUIContext(), $r('app.string.browse_local_persist_failed'));
      } else if (msg === 'NOT_FOLDER') {
        Util.toastRes(this.getUIContext(), $r('app.string.browse_pick_not_folder'));
      } else {
        Util.toastRes(this.getUIContext(), $r('app.string.browse_pick_folder_failed'));
      }
    }
  }

  // 重新同步本地源文件夹（整树拷贝进沙箱后刷新列表）
  private async syncNow(): Promise<void> {
    this.syncing = true;
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await LocalFolderManager.sync(context);
      this.syncing = false;
      Util.toastRes(this.getUIContext(), $r('app.string.browse_local_sync_done'));
      await this.loadFirst();
    } catch (e) {
      this.syncing = false;
      const msg = (e as Error).message;
      if (msg === 'ACCESS') {
        Util.toastRes(this.getUIContext(), $r('app.string.browse_local_access_failed'));
      } else {
        Util.toastRes(this.getUIContext(), $r('app.string.browse_local_sync_failed'),
          [Util.errText(this.getUIContext(), msg)]);
      }
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function BrowseSourceBuilder() {
  BrowseSourcePage()
}
