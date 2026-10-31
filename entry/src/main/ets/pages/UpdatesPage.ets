import { AppDb } from '../data/AppDb';
import { SheetPreset } from './components/SheetPreset';
import { CategoryRepo, UpdatesQuery, UpdatesRepo } from '../data/Repos';
import { DownloadService } from '../data/DownloadService';
import { UpdateService } from '../data/UpdateService';
import { CategoryRecord, UpdateItem } from '../model/Models';
import { DetailParams } from '../model/RouteParams';
import { ContentOpen } from './ContentOpen';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Settings } from '../common/Settings';
import { Util } from '../common/Util';
import { AppKeys } from '../common/AppKeys';
import { EmptyScreen } from './components/EmptyScreen';
import { LoadingState } from './components/LoadingState';
import { AppIcon } from './components/AppIcon';
import { SmartImage } from './components/SmartImage';
import { UpdatesFilterSheet } from './components/UpdatesFilterSheet';
import { SourceRegistry } from '../source/Source';

// 更新页：书架最新章节（对齐 Mihon UpdatesScreen）
// 顶栏四操作：筛选（FilterList）/ 即将推出（CalendarMonth）/ 新番时间表（Schedule）/ 更新书架（Refresh）
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
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;
  // 关闭“显示 NSFW 源”时隐藏 NSFW 插件源的更新；插件注册完成后（pluginsDirty）重算过滤
  @StorageProp('showNsfw') @Watch('onLibDirty') showNsfw: boolean = false;
  @StorageProp('pluginsDirty') @Watch('onLibDirty') pluginsDirty: number = 0;
  // 插件加载完成标志（见 AppKeys.PLUGINS_LOADED）：NSFW 过滤区分未加载完与未安装
  @StorageProp('pluginsLoaded') pluginsLoaded: boolean = false;
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

  aboutToAppear(): void {
    this.fDownloaded = Settings.getUpdatesTriState('downloaded');
    this.fUnread = Settings.getUpdatesTriState('unread');
    this.fStarted = Settings.getUpdatesTriState('started');
    this.fBookmarked = Settings.getUpdatesTriState('bookmarked');
    this.includedCats = Settings.getUpdatesIncludedCategories();
    this.excludedCats = Settings.getUpdatesExcludedCategories();
    this.publishFilterActive();
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

  // 头部刷新图标请求：刷新书架
  onRefreshReq(): void {
    this.refreshLibrary();
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
    // 插件加载完成前源未注册保持隐藏（防冷启动闪现）；
    // 完成后仍未注册 = 插件未安装（如备份恢复后待装），保留显示
    if (!this.showNsfw) {
      items = items.filter((it: UpdateItem): boolean => {
        const source = SourceRegistry.get(it.sourceKey);
        if (!this.pluginsLoaded) {
          return source !== undefined && !source.nsfw;
        }
        return source === undefined || !source.nsfw;
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
      Util.toast(this.getUIContext(),
        UpdateService.restrictionText(Util.hostAbilityContext(this.getUIContext()), blockReason));
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
      // 顶栏（标题 + 筛选/日历/时间表/刷新）已抽取为 UpdatesHeader，由 Index 挂载到 Navigation 标题栏
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
                  // 传入真实 sourceKey：缓存未命中时可用插件源请求头/并发去重下载
                  SmartImage({
                    url: item.coverUrl,
                    sourceKey: item.sourceKey,
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
    // 筛选半模态：原锚点为顶栏筛选图标，顶栏外移后锚到页面根容器（选项保持不变）
    // 高度自适应内容（SheetPreset 默认 FIT_CONTENT）：选项少时贴内容收起，多时内部滚动
    .bindSheet($$this.showFilterSheet, this.filterSheetBuilder(),
      SheetPreset.fit(this.windowW, {
        showClose: false,
        bg: this.pal.bg
      }))
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
      AppIcon({ name: 'schedule', iconSize: 22, tint: this.pal.text })
        .padding({ left: 12 })
        .onClick(() => {
          this.pathStack.pushPathByName('Schedule', null);
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
