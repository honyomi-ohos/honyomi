import { AppDb } from '../data/AppDb';
import { SheetPreset } from './components/SheetPreset';
import { CategoryRepo, UpdatesQuery, UpdatesRepo } from '../data/Repos';
import { DownloadService } from '../data/DownloadService';
import { UpdateService } from '../data/UpdateService';
import { BangumiApi, BgmCalendarItem } from '../data/BangumiApi';
import { CategoryRecord, UpdateItem } from '../model/Models';
import { DetailParams, SubjectDetailParams } from '../model/RouteParams';
import { ContentOpen } from './ContentOpen';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Settings } from '../common/Settings';
import { Util, LibGrid } from '../common/Util';
import { AppKeys } from '../common/AppKeys';
import { EmptyScreen } from './components/EmptyScreen';
import { LoadingState } from './components/LoadingState';
import { AppIcon } from './components/AppIcon';
import { SmartImage } from './components/SmartImage';
import { UpdatesFilterSheet } from './components/UpdatesFilterSheet';
import { SourceRegistry } from '../source/Source';

// 时间表星期 chips 顺序：周一起排（周日殿后）
const SCHEDULE_DAY_ORDER: number[] = [1, 2, 3, 4, 5, 6, 0];

// 更新页：书架最新章节（对齐 Mihon UpdatesScreen）
// 顶栏三操作：筛选（FilterList）/ 查看即将推出（CalendarMonth）/ 更新书架（Refresh）
// 顶栏已抽取为 UpdatesHeader（本文件底部）供 Index 挂载到 Navigation 标题栏，
// 头部随页签切换卸载，双方仅经 AppStorage 通信（updates* 键见 AppKeys）
@Component
export struct UpdatesPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  // 页签浮动条避让高度：宽屏无页签条时为 0（Index 按断点发布）
  @StorageProp('tabPadH') tabPadH: number = 76;
  @StorageProp('windowW') windowW: number = 0;
  // 时间表网格内容区宽度镜像：列数与书架同规则（LibGrid 推导），档位跨越时经 animateTo 平滑重排
  @State schedW: number = 0;
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;
  // 关闭“显示 NSFW 源”时隐藏 NSFW 插件源的更新；插件注册完成后（pluginsDirty）重算过滤
  @StorageProp('showNsfw') @Watch('onLibDirty') showNsfw: boolean = false;
  @StorageProp('pluginsDirty') @Watch('onLibDirty') pluginsDirty: number = 0;
  @State items: UpdateItem[] = [];
  @State loading: boolean = true;
  // 刷新中：经 AppStorage 发布给 UpdatesHeader 的 spinner（头部读 updatesRefreshing）
  @StorageLink('updatesRefreshing') refreshing: boolean = false;
  @State showFilterSheet: boolean = false;
  // 筛选生效标记：发布给 UpdatesHeader 的筛选图标着色（头部读 updatesFilterActive）
  @StorageLink('updatesFilterActive') filterActivePub: boolean = false;
  // 头部 → 内容区信号（计数器递增触发 @Watch）：打开筛选弹层 / 刷新书架
  @StorageLink('updatesFilterSheetReq') @Watch('onFilterSheetReq') updatesFilterSheetReq: number = 0;
  @StorageLink('updatesRefreshReq') @Watch('onRefreshReq') updatesRefreshReq: number = 0;
  // Index 根节点 Esc 广播：关闭筛选弹层（计数器递增触发）
  @StorageLink('sheetEsc') @Watch('onSheetEsc') sheetEsc: number = 0;
  // 筛选状态（对齐 Mihon UpdatesPreferences）
  @State fDownloaded: string = 'ignore';
  @State fUnread: string = 'ignore';
  @State fStarted: string = 'ignore';
  @State fBookmarked: string = 'ignore';
  @State includedCats: number[] = [];
  @State excludedCats: number[] = [];
  @State categories: CategoryRecord[] = [];
  // 页内分段：'updates' 更新列表 | 'schedule' 新番时间表
  @State updTab: string = 'updates';
  // 时间表状态（Bangumi 每日放送）
  @State scheduleLoading: boolean = false;
  @State scheduleError: string = '';
  @State scheduleAll: BgmCalendarItem[] = [];
  // 选中星期（JS 约定 0=周日..6=周六），初始为今天
  @State scheduleDay: number = new Date().getDay();
  // 星期短标签（索引 = JS 星期）
  @State weekdayLabels: string[] = [];
  private todayJs: number = new Date().getDay();

  aboutToAppear(): void {
    this.fDownloaded = Settings.getUpdatesTriState('downloaded');
    this.fUnread = Settings.getUpdatesTriState('unread');
    this.fStarted = Settings.getUpdatesTriState('started');
    this.fBookmarked = Settings.getUpdatesTriState('bookmarked');
    this.includedCats = Settings.getUpdatesIncludedCategories();
    this.excludedCats = Settings.getUpdatesExcludedCategories();
    this.publishFilterActive();
    this.buildWeekdayLabels();
    this.loadData();
    this.loadCategories();
  }

  onLibDirty(): void {
    this.loadData();
  }

  // Esc 广播：关闭筛选半模态弹层
  onSheetEsc(): void {
    if (this.showFilterSheet) {
      this.showFilterSheet = false;
    }
  }

  // 头部筛选图标请求：打开筛选半模态弹层（弹层与 filterSheetBuilder 仍由本页持有）
  onFilterSheetReq(): void {
    this.showFilterSheet = true;
  }

  // 头部刷新图标请求：时间表页刷新 Bangumi 日历，否则刷新书架
  onRefreshReq(): void {
    if (this.updTab === 'schedule') {
      this.loadSchedule(true);
    } else {
      this.refreshLibrary();
    }
  }

  async loadCategories(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    await AppDb.ready(context);
    this.categories = await CategoryRepo.list();
  }

  async loadData(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    await AppDb.ready(context);
    const query = new UpdatesQuery();
    query.downloaded = this.fDownloaded;
    query.unread = this.fUnread;
    query.started = this.fStarted;
    query.bookmarked = this.fBookmarked;
    query.includedCategories = this.includedCats;
    query.excludedCategories = this.excludedCats;
    let items = await UpdatesRepo.filteredChapters(query, 300);
    // 关闭“显示 NSFW 源”时隐藏 NSFW 插件源的更新条目；
    // 源未注册（插件尚未加载完/已卸载）时无法确认非 NSFW，同样隐藏，避免冷启动闪现
    if (!this.showNsfw) {
      items = items.filter((it: UpdateItem): boolean => {
        const source = SourceRegistry.get(it.sourceKey);
        return source !== undefined && !source.nsfw;
      });
    }
    // 已下载筛选走内存过滤（下载状态在文件系统）
    if (query.downloaded === 'include' || query.downloaded === 'exclude') {
      const downloaded = DownloadService.downloadedChapterIdSet();
      const wantDownloaded = query.downloaded === 'include';
      items = items.filter((it: UpdateItem): boolean => {
        return wantDownloaded === downloaded.has(it.chapterId);
      });
    }
    // 筛选/数据刷新列表变化：包 animateTo，配合行 transition 播放增删转场
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, (): void => {
      this.items = items;
    });
    this.loading = false;
  }

  async refreshLibrary(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    // 批量更新网络/电源限制（仅 Wi-Fi / 仅充电）：不满足时提示并跳过
    const blockReason = UpdateService.checkUpdateRestrictions();
    if (blockReason !== '') {
      Util.toast(this.getUIContext(), blockReason);
      return;
    }
    this.refreshing = true;
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const newCount = await UpdateService.refreshLibrary(context);
      if (newCount > 0) {
        Util.toastRes(this.getUIContext(), $r('app.string.updates_found_new'), [newCount]);
      } else {
        Util.toastRes(this.getUIContext(), $r('app.string.updates_no_new'));
      }
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.updates_refresh_failed'));
    }
    this.refreshing = false;
    await this.loadData();
  }

  @Builder
  filterSheetBuilder() {
    UpdatesFilterSheet({
      initDownloaded: this.fDownloaded,
      initUnread: this.fUnread,
      initStarted: this.fStarted,
      initBookmarked: this.fBookmarked,
      initIncluded: this.includedCats,
      initExcluded: this.excludedCats,
      categories: this.categories,
      showFilterTab: true,
      onTriStateChanged: (key: string, v: string): void => {
        this.applyTriState(key, v);
      },
      onCategoriesChanged: (included: number[], excluded: number[]): void => {
        this.includedCats = included;
        this.excludedCats = excluded;
        this.publishFilterActive();
        Settings.setUpdatesIncludedCategories(included);
        Settings.setUpdatesExcludedCategories(excluded);
        this.loadData();
      }
    })
  }

  build() {
    this.bodyContent()
  }

  @Builder
  bodyContent() {
    Column() {
      // 顶栏（标题 + 筛选/日历/刷新）已抽取为 UpdatesHeader，由 Index 挂载到 Navigation 标题栏
      // 页内分段：「更新 | 时间表」
      this.tabBar()
      if (this.updTab === 'updates') {
        if (this.loading) {
          LoadingState()
        } else if (this.items.length === 0) {
          Column() {
            EmptyScreen({ message: $r('app.string.updates_empty') })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Column() {
            List({ space: 0 }) {
              ForEach(this.items, (item: UpdateItem) => {
                ListItem() {
                  Row({ space: 12 }) {
                    // 封面（无封面时 SmartImage 内部渲染默认封面占位）；
                    // UpdateItem 不含 sourceKey，传空串走网络/缓存通用路径
                    SmartImage({
                      url: item.coverUrl,
                      sourceKey: '',
                      fit: ImageFit.Cover,
                      placeholderIconSize: 20
                    })
                      .width(44)
                      .height(60)
                      .borderRadius(6)
                      .backgroundColor(this.pal.chip)
                      // HitTestMode.Block 阻断冒泡：避免同时触发整行 onClick（直接打开阅读器）
                      .hitTestBehavior(HitTestMode.Block)
                      .onClick(() => {
                        this.openDetail(item.mangaId);
                      })
                    Column() {
                      Text(item.mangaTitle)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.pal.text)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .opacity(item.read ? 0.38 : 1)
                      Row({ space: 4 }) {
                        if (!item.read) {
                          Column()
                            .width(8)
                            .height(8)
                            .borderRadius(4)
                            .backgroundColor(this.pal.primary)
                        }
                        if (item.bookmark) {
                          AppIcon({ name: 'bookmark_filled', iconSize: 12, tint: this.pal.primary })
                        }
                        Text(item.chapterName)
                          .fontSize(13)
                          .fontColor(this.pal.sub)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)
                          .opacity(item.read ? 0.38 : 1)
                      }
                      .margin({ top: 4 })
                      .alignItems(VerticalAlign.Center)

                      Text(Util.timeAgo(item.dateUpload))
                        .fontSize(11)
                        .fontColor(this.pal.sub)
                        .margin({ top: 4 })
                        .opacity(item.read ? 0.38 : 1)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding({
                    left: 16 + this.inset(),
                    right: 16 + this.inset(),
                    top: 10,
                    bottom: 10
                  })
                  // 筛选结果行增删转场：淡入淡出 + 轻微位移
                  .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
                    .animation({ duration: 200, curve: Curve.Friction }))
                  .onClick(() => {
                    ContentOpen.open(this.pathStack, item.mangaId, item.chapterId);
                  })
                }
              }, (item: UpdateItem) => `upd-${item.chapterId}-${item.coverUrl}-${item.read}-${item.bookmark}`)
            }
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .contentEndOffset(this.navBarH + this.tabPadH)
            .divider({
              strokeWidth: 1,
              color: this.pal.divider,
              startMargin: 72 + this.inset(),
              endMargin: 16 + this.inset(),
            })
          }
          .width('100%')
          .layoutWeight(1)
        }
      } else {
        this.scheduleContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
    // 筛选半模态：原锚点为顶栏筛选图标，顶栏外移后锚到页面根容器（选项保持不变）
    .bindSheet($$this.showFilterSheet, this.filterSheetBuilder(),
      SheetPreset.fit(this.windowW, {
        height: Bp.sheetHeight(this.windowW),
        detents: ['60%', SheetSize.LARGE],
        showClose: false,
        bg: this.pal.bg
      }))
  }

  // 页内分段控件：「更新 | 时间表」
  @Builder
  tabBar() {
    Row({ space: 4 }) {
      this.tabChip($r('app.string.updates_tab_updates'), 'updates')
      this.tabChip($r('app.string.updates_tab_schedule'), 'schedule')
    }
    .width('100%')
    .padding({
      left: 12 + this.inset(),
      right: 12 + this.inset(),
      top: 2,
      bottom: 6
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  tabChip(label: Resource, tab: string) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.updTab === tab ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.updTab === tab ? this.pal.text : this.pal.sub)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.updTab === tab ? this.pal.chip : Color.Transparent)
      .onClick(() => {
        this.switchTab(tab);
      })
  }

  // 新番时间表内容：星期 chips（周一起排、今日主色描边）+ 按选中星期过滤的封面网格
  // 网格与书架同构：Grid + columnsTemplate，列数同规则（书架手动列数/自动档），宽屏不限宽
  @Builder
  scheduleContent() {
    Column() {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(SCHEDULE_DAY_ORDER, (day: number) => {
            this.dayChip(day)
          }, (day: number) => `wd-${day}`)
        }
        .padding({
          left: 16,
          right: 16
        })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      if (this.scheduleLoading) {
        LoadingState()
      } else if (this.scheduleError !== '') {
        Column() {
          EmptyScreen({ message: $r('app.string.schedule_load_failed') })
          Text($r('app.string.common_retry'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal.primary)
            .padding({ top: 4, bottom: 12 })
            .onClick(() => {
              this.loadSchedule(true);
            })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.dayItems().length === 0) {
        Column() {
          EmptyScreen({ message: $r('app.string.schedule_empty') })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.dayItems(), (item: BgmCalendarItem) => {
            GridItem() {
              this.scheduleCard(item)
            }
          }, (item: BgmCalendarItem) => `bgm-${item.id}`)
        }
        .columnsTemplate(this.schedColumnsTemplate())
        .columnsGap(8)
        .rowsGap(12)
        .padding({ left: 8, right: 8, top: 8 })
        .contentEndOffset(this.navBarH + this.tabPadH)
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .onAreaChange((_old: Area, newArea: Area) => {
      const w = newArea.width;
      if (typeof w === 'number') {
        this.applySchedW(w);
      }
    })
  }

  // 星期 chip：选中实心、今日描边
  @Builder
  dayChip(day: number) {
    Text(this.weekdayLabel(day))
      .fontSize(13)
      .fontWeight(this.scheduleDay === day ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.scheduleDay === day ? this.pal.onPrimary :
        (this.todayJs === day ? this.pal.primary : this.pal.sub))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.scheduleDay === day ? this.pal.primary : Color.Transparent)
      .border({
        width: this.scheduleDay !== day && this.todayJs === day ? 1 : 0,
        color: this.pal.primary
      })
      .onClick(() => {
        this.scheduleDay = day;
      })
  }

  // 时间表卡片：封面（2:3）+ 评分角标 + 标题 + 放送日期，点击进条目详情
  @Builder
  scheduleCard(item: BgmCalendarItem) {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        SmartImage({
          url: item.cover,
          fit: ImageFit.Cover,
          placeholderIconSize: 24
        })
          .width('100%')
          .aspectRatio(2 / 3)
          .borderRadius(8)
          .clip(true)
          .backgroundColor(this.pal.chip)

        if (item.score > 0) {
          Text(`★ ${item.score.toFixed(1)}`)
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFD180')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor('#CC000000')
            .margin(5)
        }
      }
      .width('100%')

      // 标题固定 2 行、放送日期固定 1 行：文字长短/缺失不改变卡片高度，同行卡片底部对齐
      Text(item.nameCn !== '' ? item.nameCn : item.name)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal.text)
        .minLines(2)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })

      Text(item.airDate)
        .fontSize(11)
        .fontColor(this.pal.sub)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      const params: SubjectDetailParams = { subjectId: item.id };
      this.pathStack.pushPathByName('SubjectDetail', params);
    })
  }

  // 页面主体：滚动容器全宽（滚动条贴窗口边），内容列经 contentInset 限宽居中
  private inset(): number {
    return Bp.contentInset(this.windowW);
  }

  private filterActive(): boolean {
    return this.fDownloaded !== 'ignore' || this.fUnread !== 'ignore' ||
      this.fStarted !== 'ignore' || this.fBookmarked !== 'ignore' ||
      this.includedCats.length > 0 || this.excludedCats.length > 0;
  }

  // 发布筛选生效标记给头部（所有筛选状态变更点均须调用：aboutToAppear / applyTriState / onCategoriesChanged）
  private publishFilterActive(): void {
    this.filterActivePub = this.filterActive();
  }

  private applyTriState(key: string, v: string): void {
    if (key === 'downloaded') {
      this.fDownloaded = v;
    } else if (key === 'unread') {
      this.fUnread = v;
    } else if (key === 'started') {
      this.fStarted = v;
    } else {
      this.fBookmarked = v;
    }
    this.publishFilterActive();
    Settings.setUpdatesTriState(key, v);
    this.loadData();
  }

  private openDetail(mangaId: number): void {
    const params: DetailParams = { mangaId: mangaId };
    this.pathStack.pushPathByName('MangaDetail', params);
  }

  // ---- 新番时间表 ----

  // 分段切换：首次进入时间表时拉取 Bangumi 日历
  private switchTab(tab: string): void {
    if (this.updTab === tab) {
      return;
    }
    this.updTab = tab;
    if (tab === 'schedule' && this.scheduleAll.length === 0 && this.scheduleError === '') {
      this.loadSchedule(false);
    }
  }

  private async loadSchedule(force: boolean): Promise<void> {
    this.scheduleLoading = true;
    this.scheduleError = '';
    try {
      this.scheduleAll = await BangumiApi.getCalendar(force);
      this.scheduleLoading = false;
    } catch (e) {
      this.scheduleLoading = false;
      this.scheduleError = e instanceof Error ? e.message : 'load_failed';
    }
  }

  // 星期短标签（索引 = JS 星期 0=周日..6=周六）
  private buildWeekdayLabels(): void {
    const ctx = Util.hostAbilityContext(this.getUIContext());
    const labels: string[] = [];
    for (let day = 0; day < 7; day++) {
      labels.push(Util.weekdayShort(ctx, day));
    }
    this.weekdayLabels = labels;
  }

  private weekdayLabel(day: number): string {
    return this.weekdayLabels.length === 7 ? (this.weekdayLabels[day] ?? '') : `${day}`;
  }

  // 选中星期的条目
  private dayItems(): BgmCalendarItem[] {
    return this.scheduleAll.filter((it: BgmCalendarItem): boolean => it.jsDay === this.scheduleDay);
  }

  // 当前生效列数：与书架同规则——书架手动列数按可行区间收敛（0=自动），自动档约 128vp 一格
  private effectiveSchedCols(w: number): number {
    const manual: number = Settings.getLibraryGridCols();
    if (manual > 0) {
      return LibGrid.clampCols(manual, w);
    }
    return LibGrid.autoCols(w);
  }

  private schedColsCount(): number {
    return this.effectiveSchedCols(this.schedW > 0 ? this.schedW : 360);
  }

  // 网格宽变化：生效列数档位变化时包 animateTo，让网格重排带过渡动画
  private applySchedW(w: number): void {
    if (w === this.schedW) {
      return;
    }
    const reflow: boolean = this.effectiveSchedCols(w) !== this.schedColsCount();
    if (reflow) {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, (): void => {
        this.schedW = w;
      });
    } else {
      this.schedW = w;
    }
  }

  private schedColumnsTemplate(): string {
    let tpl = '';
    for (let i = 0; i < this.schedColsCount(); i++) {
      tpl += '1fr ';
    }
    return tpl.trim();
  }
}

// 更新页顶部标题栏：抽取供 Index 挂载到 Navigation 标题栏
// （高度 58，含 contentInset 横向留白，不含状态栏避让——由 Index 外部补齐）
// 筛选/刷新经 AppStorage 计数信号转发给内容区；筛选弹层仍由 UpdatesPage 持有
@Component
export struct UpdatesHeader {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  // 内容区发布：刷新中（spinner 显示）/ 筛选生效（筛选图标着色）
  @StorageProp('updatesRefreshing') refreshing: boolean = false;
  @StorageProp('updatesFilterActive') filterActive: boolean = false;

  build() {
    Row() {
      Text($r('app.string.updates_title'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .layoutWeight(1)
      if (this.refreshing) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(this.pal.primary)
          .margin({ left: 8 })
      }
      AppIcon({ name: 'filter_list', iconSize: 22, tint: this.filterActive ? this.pal.primary : this.pal.text })
        .padding({ left: 12 })
        .onClick(() => {
          AppStorage.setOrCreate(AppKeys.UPDATES_FILTER_SHEET_REQ,
            (AppStorage.get<number>(AppKeys.UPDATES_FILTER_SHEET_REQ) ?? 0) + 1);
        })
      AppIcon({ name: 'calendar_month', iconSize: 22, tint: this.pal.text })
        .padding({ left: 12 })
        .onClick(() => {
          this.pathStack.pushPathByName('Upcoming', null);
        })
      AppIcon({ name: 'refresh', iconSize: 22, tint: this.pal.text })
        .padding({ left: 12 })
        .onClick(() => {
          AppStorage.setOrCreate(AppKeys.UPDATES_REFRESH_REQ,
            (AppStorage.get<number>(AppKeys.UPDATES_REFRESH_REQ) ?? 0) + 1);
        })
    }
    .width('100%')
    .height(58)
    .padding({
      left: 16 + this.inset(),
      right: 16 + this.inset(),
      top: 12,
      bottom: 8
    })
  }

  private inset(): number {
    return Bp.contentInset(this.windowW);
  }
}
