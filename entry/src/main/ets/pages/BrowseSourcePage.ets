import { AppDb } from '../data/AppDb';
import { SheetPreset } from './components/SheetPreset';
import { CategoryRepo, MangaRepo } from '../data/Repos';
import { Source, SourceRegistry } from '../source/Source';
import { JsvmSource, RawFilter } from '../source/JsvmSource';
import { LocalFolderManager } from '../source/LocalFolderManager';
import { CategoryRecord, ContentType, MangaRecord, SManga, WorksPage } from '../model/Models';
import { BrowseSourceParams, DetailParams, DetailSearchResult } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { MangaCard } from './components/MangaCard';
import { MangaSkeletonGrid } from './components/MangaSkeletonGrid';
import { EmptyScreen } from './components/EmptyScreen';
import { AppIcon } from './components/AppIcon';
import { PickerSheet } from './components/PickerSheet';
import { CategoryDialog } from './components/Dialogs';
import { AppKeys } from '../common/AppKeys';
import { CoverStore } from '../common/CoverStore';

// 单源浏览页（图源 Tab 点进某个源）：顶栏返回 + 搜索 + 热门/最新/过滤切换行 + 结果网格
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
  @State results: MangaRecord[] = [];
  @State searching: boolean = false;
  @State page: number = 1;
  @State hasNextPage: boolean = false;
  @State loadingMore: boolean = false;
  @State contentW: number = 0;
  @State folderReady: boolean = false;
  @State syncing: boolean = false;
  @State showFolderSheet: boolean = false;
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
      record.contentType = src !== undefined ? src.contentType : ContentType.MANGA;
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

  // 已在书架 → 提示；存在自建分类 → 弹分类选择；否则直接入库（默认分类）
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
      const categories: CategoryRecord[] = await CategoryRepo.list();
      const hasCustom = categories.some((c: CategoryRecord): boolean => !ContentType.isBuiltinCategory(c.name));
      if (hasCustom) {
        this.showQuickAddCategoryDialog(id, record, categories);
        return;
      }
      await this.quickAddToLibraryInCategory(id, record, -1);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
    }
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

  build() {
    NavDestination() {
      Stack() {
        Column() {
          // 顶栏
          Row() {
            AppIcon({ name: 'arrow_back', iconSize: 24 })
              .onClick(() => {
                this.pathStack.pop();
              })
            Text(this.currentSource() !== undefined ?
              Util.localSourceName(this.getUIContext(), this.sourceKey, (this.currentSource() as Source).name) : '')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal.text)
              .margin({ left: 8 })
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

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
              if (this.searchOpen) {
                AppIcon({ name: 'close', iconSize: 20 })
                  .padding({ left: 10, right: 10 })
                  .onClick(() => {
                    this.searchOpen = false;
                    this.query = '';
                    this.loadFirst();
                  })
              } else {
                AppIcon({ name: 'search', iconSize: 20 })
                  .padding({ left: 10, right: 10 })
                  .onClick(() => {
                    this.searchOpen = true;
                  })
              }
            }
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: this.statusBarH + 10,
            bottom: 8
          })

          // 搜索栏
          if (this.searchOpen && this.sourceKey !== 'local') {
            Row({ space: 8 }) {
              TextInput({ text: this.query, placeholder: $r('app.string.browse_search_hint') })
                .layoutWeight(1)
                .height(38)
                .backgroundColor(this.pal.card)
                .enterKeyType(EnterKeyType.Search)
                .onChange((value: string) => {
                  this.query = value;
                })
                .onSubmit(() => {
                  this.search();
                })
              Button($r('app.string.common_search'))
                .fontSize(14)
                .height(38)
                .backgroundColor(this.pal.primary)
                .fontColor(this.pal.onPrimary)
                .onClick(() => {
                  this.search();
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 8 })
          }

          // 模式切换行：热门 / 最近更新 / 过滤 同行（对齐 Mihon BrowseSourceScreen FilterChip 行）
          if (!ContentType.isLocal(this.sourceKey) &&
            (this.currentSource()?.supportsLatest === true || this.sourceSupportsFilters())) {
            Row({ space: 8 }) {
              Text($r('app.string.browse_popular'))
                .fontSize(13)
                .fontColor(!this.filterSearch && this.mode === 'popular' ? this.pal.onPrimary : this.pal.sub)
                .backgroundColor(!this.filterSearch && this.mode === 'popular' ? this.pal.primary : this.pal.chip)
                .borderRadius(12)
                .padding({
                  left: 12,
                  right: 12,
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
                Text($r('app.string.browse_latest'))
                  .fontSize(13)
                  .fontColor(!this.filterSearch && this.mode === 'latest' ? this.pal.onPrimary : this.pal.sub)
                  .backgroundColor(!this.filterSearch && this.mode === 'latest' ? this.pal.primary : this.pal.chip)
                  .borderRadius(12)
                  .padding({
                    left: 12,
                    right: 12,
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
              // 插件自定义过滤器入口（过滤器激活时高亮）
              if (this.sourceSupportsFilters()) {
                Text($r('app.string.action_filter'))
                  .fontSize(13)
                  .fontColor(this.filterSearch ? this.pal.onPrimary : this.pal.sub)
                  .backgroundColor(this.filterSearch ? this.pal.primary : this.pal.chip)
                  .borderRadius(12)
                  .padding({
                    left: 12,
                    right: 12,
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
                  MangaCard({
                    record: record,
                    badge: this.nsfwBadge(),
                    onCardClick: (r: MangaRecord): void => {
                      this.openDetail(r);
                    },
                    onCardLongPress: (r: MangaRecord): void => {
                      this.quickAddToLibrary(r);
                    },
                    onCardMenuAddToLibrary: (r: MangaRecord): void => {
                      this.quickAddToLibrary(r);
                    },
                  })
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
                this.contentW = w;
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
            this.contentW = w;
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
      this.folderReady = LocalFolderManager.hasFolder();
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
    // 行高 = 封面（宽高比 0.7）+ 标题两行 + 行间距
    const rowH = cardW / 0.7 + 56;
    // 多备一行缓冲：内容恰好等于视口高度时仍不可滚动，预留余量保证 onReachEnd 可触发
    const rowsNeeded = Math.ceil(this.gridH / rowH) + 1;
    if (this.results.length < rowsNeeded * columns) {
      this.fillChecked = this.results.length;
      this.loadMore();
    }
  }

  // NSFW 源内的漫画卡片角标（MangaCard 右下红标）
  private nsfwBadge(): string {
    const source = this.currentSource();
    return source !== undefined && source.nsfw ? 'NSFW' : '';
  }

  // 结果网格列数：手机双列，平板/横屏按约 160vp 一卡自适应增加列数
  private gridColumns(): number {
    const w = this.contentW > 0 ? this.contentW : 360;
    return Math.max(2, Math.floor((w - 32 - 12) / 160));
  }

  private columnsTpl(): string {
    let tpl = '';
    for (let i = 0; i < this.gridColumns(); i++) {
      tpl += '1fr ';
    }
    return tpl.trim();
  }

  // 当前模式下的列表页（最新模式仅在源支持时生效）
  private fetchPage(source: Source, page: number): Promise<WorksPage> {
    if (this.mode === 'latest' && source.supportsLatest) {
      return source.getLatestWorks(page);
    }
    return source.getPopularWorks(page);
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

  // 快速入库分类选择弹窗（存在自建分类时），选中分类即确认入库
  private showQuickAddCategoryDialog(id: number, record: MangaRecord, categories: CategoryRecord[]): void {
    const dialog = new CustomDialogController({
      builder: CategoryDialog({
        categories: categories,
        onPick: (categoryId: number): void => {
          this.quickAddToLibraryInCategory(id, record, categoryId).catch((_e: Error): void => {
            Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
          });
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  // 入库并刷新书架（categoryId >= 0 时覆盖默认分类）
  private async quickAddToLibraryInCategory(id: number, record: MangaRecord, categoryId: number): Promise<void> {
    await MangaRepo.setInLibrary(id, true);
    if (categoryId >= 0) {
      await MangaRepo.setCategory(id, categoryId);
    }
    AppStorage.setOrCreate(AppKeys.LIB_DIRTY, (AppStorage.get<number>(AppKeys.LIB_DIRTY) ?? 0) + 1);
    // 入库即持久化封面（fire-and-forget）：书架离线可显、无插件注册竞态
    this.persistQuickAddCover(id, record);
    Util.toastRes(this.getUIContext(), $r('app.string.detail_added_to_library'));
  }

  // 封面持久化（fire-and-forget）：完成后再写 libDirty 刷新书架显示
  private async persistQuickAddCover(id: number, record: MangaRecord): Promise<void> {
    try {
      const url = record.thumbnailUrl;
      if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
        return;
      }
      const context = Util.hostAbilityContext(this.getUIContext());
      const path = await CoverStore.persistFromUrl(context, id, url, record.sourceKey);
      if (path === '') {
        return;
      }
      await MangaRepo.setLocalCover(id, path, url);
      AppStorage.setOrCreate(AppKeys.LIB_DIRTY, (AppStorage.get<number>(AppKeys.LIB_DIRTY) ?? 0) + 1);
    } catch (_e) {
      // 持久化失败不阻塞入库，书架回退在线封面路径
    }
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

  private localEmptyMessage(): Resource {
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
