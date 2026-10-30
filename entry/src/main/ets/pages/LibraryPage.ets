import { AppDb } from '../data/AppDb';
import { SheetPreset } from './components/SheetPreset';
import { CategoryRepo, ChapterRepo, MangaRepo, TrackRepo } from '../data/Repos';
import { UpdateService } from '../data/UpdateService';
import { DownloadService } from '../data/DownloadService';
import { DownloadRules } from '../data/DownloadRules';
import { Settings } from '../common/Settings';
import { CategoryRecord, ChapterRecord, ContentType, DownloadTask, MangaRecord, MangaStats } from '../model/Models';
import { DetailParams, MigrateSearchParams } from '../model/RouteParams';
import { Source, SourceRegistry } from '../source/Source';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { LibGrid, Util } from '../common/Util';
import { AppKeys } from '../common/AppKeys';
import { ChangeCategoryDialog, ConfirmDialog } from './components/Dialogs';
import { EmptyScreen } from './components/EmptyScreen';
import { LoadingState } from './components/LoadingState';
import { AppIcon } from './components/AppIcon';
import { SwipeActionItem } from './components/SwipeActionItem';
import { LibrarySettingsSheet } from './components/LibrarySettingsSheet';
import { LibraryAddFlow } from '../common/LibraryAddFlow';
import { HOME_HEADER_H } from '../common/HdsNavHost';

// LazyForEach 数据源：shownList 变化时 onDataReloaded 通知
class LibMangaSource implements IDataSource {
  private items: MangaRecord[] = [];
  private listeners: DataChangeListener[] = [];

  setItems(items: MangaRecord[]): void {
    this.items = items;
    this.notifyReload();
  }

  // diff 替换：搜索/筛选/分类切换时按 id 逐行增删通知（公共行相对顺序不变，
  // 双指针定位插入点；结果与新序列长度不一致时回退整体重载），
  // 配合行 transition 播放行增删动效
  setItemsDiff(items: MangaRecord[]): void {
    const kept = new Set<number>();
    for (const it of items) {
      kept.add(it.id);
    }
    for (let i = this.items.length - 1; i >= 0; i--) {
      if (!kept.has(this.items[i].id)) {
        this.items.splice(i, 1);
        this.notifyDelete(i);
      }
    }
    let oldIdx = 0;
    for (let i = 0; i < items.length; i++) {
      if (oldIdx < this.items.length && this.items[oldIdx].id === items[i].id) {
        oldIdx++;
      } else {
        this.items.splice(i, 0, items[i]);
        oldIdx = i + 1;
        this.notifyAdd(i);
      }
    }
    if (this.items.length !== items.length) {
      this.items = items;
      this.notifyReload();
    }
  }

  private notifyAdd(index: number): void {
    for (const listener of this.listeners) {
      listener.onDataAdd(index);
    }
  }

  private notifyDelete(index: number): void {
    for (const listener of this.listeners) {
      listener.onDataDelete(index);
    }
  }

  // 选中集合变化时通知 LazyForEach 重跑行生成器（刷新 isSelected 勾选态）
  notifyReload(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): MangaRecord {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }
}

// 书库页签头部（置于 Index 的 Navigation 标题栏，获得沉浸光感材质）：
// 选择模式下切换为多选工具栏。与内容区经 AppStorage 桥接——
// 头部随页签切换卸载，持久状态走全局存储，动作走计数信号。
@Component
export struct LibraryHeader {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 多选数（内容区 onSelectionChanged 发布）：>0 显示选择工具栏
  @StorageProp('libSelectionCount') selectionCount: number = 0;
  // 刷新中（内容区发布）与筛选生效态（内容区 refreshView 发布）
  @StorageProp('libRefreshing') refreshing: boolean = false;
  @StorageProp('libFilterActive') filterActive: boolean = false;
  // 搜索框打开态与搜索词：详情页回退搜索时内容区也会写入
  @StorageLink('libSearchOpen') searchOpen: boolean = false;
  @StorageLink('libSearchQuery') searchQuery: string = '';

  build() {
    if (this.selectionCount > 0) {
      this.selectionToolbar()
    } else {
      this.titleRow()
    }
  }

  // 选择模式工具栏（对齐 Mihon LibrarySelectionToolbar）
  @Builder
  selectionToolbar() {
    Row() {
      AppIcon({ name: 'close', iconSize: 22, tint: this.pal.text })
        .onClick(() => {
          this.sendSignal(AppKeys.LIB_SEL_CLEAR_REQ);
        })
      Text(`${this.selectionCount}`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .margin({ left: 16 })
      Blank()
        .layoutWeight(1)
      AppIcon({ name: 'select_all', iconSize: 22, tint: this.pal.text })
        .padding({ left: 12 })
        .onClick(() => {
          this.sendSignal(AppKeys.LIB_SELECT_ALL_REQ);
        })
      AppIcon({ name: 'autorenew', iconSize: 22, tint: this.pal.text })
        .padding({ left: 12 })
        .onClick(() => {
          this.sendSignal(AppKeys.LIB_SEL_INVERT_REQ);
        })
    }
    .width('100%')
    .height(HOME_HEADER_H)
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: 8
    })
  }

  // 常规顶栏：标题(+刷新指示)/搜索框 + 搜索/筛选/更多
  @Builder
  titleRow() {
    Row() {
      if (this.searchOpen) {
        TextInput({
          text: this.searchQuery,
          placeholder: $r('app.string.library_search_hint')
        })
          .id('libSearchInput')
          .layoutWeight(1)
          .height(38)
          .fontSize(15)
          .fontColor(this.pal.text)
          .placeholderColor(this.pal.sub)
          .caretColor(this.pal.primary)
          .backgroundColor(this.pal.chip)
          .borderRadius(19)
          .padding({ left: 16, right: 16 })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ x: -24 })))
          .onChange((value: string) => {
            this.searchQuery = value;
          })
        AppIcon({ name: 'close', iconSize: 22, tint: this.pal.text })
          .padding({ left: 12 })
          .onClick(() => {
            this.closeSearch();
          })
      } else {
        Text($r('app.string.library_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
        if (this.refreshing) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(this.pal.primary)
            .margin({ left: 8 })
        }
        Blank()
          .layoutWeight(1)
        AppIcon({ name: 'search', iconSize: 22, tint: this.pal.text })
          .padding({ left: 12 })
          .onClick(() => {
            this.openSearch();
          })
        AppIcon({ name: 'filter_list', iconSize: 22, tint: this.filterActive ? this.pal.primary : this.pal.text })
          .padding({ left: 12 })
          .onClick(() => {
            this.sendSignal(AppKeys.LIB_FILTER_SHEET_REQ);
          })
        AppIcon({ name: 'more_vert', iconSize: 22, tint: this.pal.text })
          .padding({ left: 12 })
          .bindMenu(this.libMenu)
      }
    }
    .width('100%')
    .height(HOME_HEADER_H)
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: 8
    })
  }

  @Builder
  libMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.action_update_library') })
        .onClick(() => {
          this.sendSignal(AppKeys.LIB_REFRESH_REQ);
        })
      MenuItem({ content: $r('app.string.action_update_category') })
        .onClick(() => {
          this.sendSignal(AppKeys.LIB_REFRESH_CATEGORY_REQ);
        })
      MenuItem({ content: $r('app.string.action_open_random_manga') })
        .onClick(() => {
          this.sendSignal(AppKeys.LIB_RANDOM_REQ);
        })
    }
  }

  private openSearch(): void {
    // 展开动画结束后自动聚焦输入框
    this.getUIContext().animateTo({
      duration: 250,
      curve: Curve.Friction,
      onFinish: (): void => {
        this.getUIContext().getFocusController().requestFocus('libSearchInput');
      }
    }, (): void => {
      this.searchOpen = true;
    });
  }

  private closeSearch(): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, (): void => {
      this.searchOpen = false;
      this.searchQuery = '';
    });
  }

  private sendSignal(key: string): void {
    AppStorage.setOrCreate(key, (AppStorage.get<number>(key) ?? 0) + 1);
  }
}

// 书架页：分类 + 搜索/过滤弹层（筛选/排序/显示）/四种显示模式
@Component
export struct LibraryPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  // 页签浮动条避让高度：宽屏无页签条时为 0（Index 按断点发布）
  @StorageProp('tabPadH') tabPadH: number = 76;
  @StorageProp('windowW') windowW: number = 0;
  @State mangas: MangaRecord[] = [];
  @State categories: CategoryRecord[] = [];
  @State loading: boolean = true;
  // 刷新中/搜索框打开态：经 AppStorage 与头部（Navigation 标题栏）共享
  @StorageLink('libRefreshing') refreshing: boolean = false;
  @StorageLink('libSearchOpen') searchOpen: boolean = false;
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;
  // 复刻 Mihon：再次点击书架页签打开筛选/显示设置弹层（LibraryTab.onReselect）
  @StorageLink('libReselect') @Watch('onLibReselect') libReselect: number = 0;
  // 设置-书架配置变更（计数器递增）：书架页常驻挂载，设置页只写 Preferences，
  // 经此信号触发重读配置（applySettings），否则改动需重启应用才生效
  @StorageLink('libSettingsDirty') @Watch('onLibSettingsDirty') libSettingsDirty: number = 0;
  // 详情页回退书架的文本搜索请求（对齐 Mihon LibraryTab.search）：计数触发，查询词经 libSearchQuery 传递
  @StorageLink('libSearchReq') @Watch('onLibSearchReq') libSearchReq: number = 0;
  // NSFW 源显示开关：关闭时隐藏 NSFW 插件源的作品；插件注册完成后（pluginsDirty）重算过滤
  @StorageProp('showNsfw') @Watch('onDataInput') showNsfw: boolean = false;
  @StorageProp('pluginsDirty') @Watch('onDataInput') pluginsDirty: number = 0;
  // 弹层状态（与 Settings 同步）；筛选/排序输入变化时重算缓存列表
  @State @Watch('onViewInput') sortKey: string = 'alpha';
  @State @Watch('onViewInput') sortAsc: boolean = true;
  @State @Watch('onViewInput') fDownloaded: string = 'ignore';
  @State @Watch('onViewInput') fUnread: string = 'ignore';
  @State @Watch('onViewInput') fStarted: string = 'ignore';
  @State @Watch('onViewInput') fBookmarked: string = 'ignore';
  @State @Watch('onViewInput') fCompleted: string = 'ignore';
  @State @Watch('onViewInput') fTracked: string = 'ignore';
  @State @Watch('onViewInput') selectedCategory: number = 0;
  // 搜索词（头部 TextInput 写入）：200ms 防抖刷新，避免逐键全量重算
  @StorageLink('libSearchQuery') @Watch('onSearchQuery') searchQuery: string = '';
  @State viewMode: string = 'compact';
  @State gridCols: number = 0;
  // 卡片滑动动作（起始/末端，'read' | 'none'）：条目滑动包装组件消费
  @State swipeStartAction: string = 'read';
  @State swipeEndAction: string = 'none';
  @State showUnreadBadge: boolean = true;
  @State showDownloadBadge: boolean = true;
  @State showLocalBadge: boolean = false;
  @State showLanguageBadge: boolean = false;
  @State @Watch('onViewInput') showCategoryTabs: boolean = true;
  @State showMangaCount: boolean = false;
  @State showFilterSheet: boolean = false; // 聚合数据
  // Index 根节点 Esc 广播：关闭筛选弹层 / 退出多选（计数器递增触发）
  @StorageLink('sheetEsc') @Watch('onSheetEsc') sheetEsc: number = 0;
  // Index 根节点键盘广播：Ctrl+A 全选、Delete 删除选中
  @StorageLink('libSelectAllReq') @Watch('onSelectAllReq') libSelectAllReq: number = 0;
  @StorageLink('libDeleteSelReq') @Watch('onDeleteSelReq') libDeleteSelReq: number = 0;
  // 头部（Navigation 标题栏）信号：筛选弹层 / 菜单动作 / 多选工具栏（计数器递增触发）
  @StorageLink('libFilterSheetReq') @Watch('onFilterSheetReq') libFilterSheetReq: number = 0;
  @StorageLink('libRefreshReq') @Watch('onRefreshReq') libRefreshReq: number = 0;
  @StorageLink('libRefreshCategoryReq') @Watch('onRefreshCategoryReq') libRefreshCategoryReq: number = 0;
  @StorageLink('libRandomReq') @Watch('onRandomReq') libRandomReq: number = 0;
  @StorageLink('libSelClearReq') @Watch('onSelClearReq') libSelClearReq: number = 0;
  @StorageLink('libSelInvertReq') @Watch('onSelInvertReq') libSelInvertReq: number = 0;
  @State statsMap: Record<string, MangaStats> = {};
  @State downloadCounts: Record<string, number> = {};
  @State trackedIds: Set<number> = new Set<number>();
  @State langMap: Record<string, string> = {};
  @State randomOrder: Record<string, number> = {};
  @State contentW: number = 0;
  // 多选（长按触发，对齐 Mihon 书架选择模式）；变化同步全局计数，
  // Index 侧据此隐藏/恢复底部悬浮页签栏（HDS 多选交互规范）
  @State @Watch('onSelectionChanged') selection: Set<number> = new Set<number>();
  // 视图缓存：shownList = 搜索/筛选/排序(+分类)后的列表，categoryCounts = 分类 chip 计数，
  // 输入变化经 @Watch('refreshView') 一次性重算，build 内不做逐帧过滤排序
  @State shownList: MangaRecord[] = [];
  @State categoryCounts: Record<string, number> = {};
  // manga_category membership 真源（mangaId → 分类 id 列表，仅 inLibrary）：
  // 分类计数/选中分类过滤/批量分类预选均以 membership 为准，categoryId 仅回退
  private categoryIdsMap: Map<number, number[]> = new Map<number, number[]>();
  private libSource: LibMangaSource = new LibMangaSource();
  private searchTimer: number = -1;

  aboutToAppear(): void {
    this.applySettings();
    this.takePendingLibSearch();
    this.loadData();
  }

  aboutToDisappear(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
  }

  onLibDirty(): void {
    this.loadData();
  }

  // 设置-书架任意配置改动：重读排序/显示/徽标等配置即时生效
  onLibSettingsDirty(): void {
    this.applySettings();
  }

  // Esc 广播：优先关筛选弹层，其次退出多选
  onSheetEsc(): void {
    if (this.showFilterSheet) {
      this.showFilterSheet = false;
      return;
    }
    if (this.selection.size > 0) {
      this.clearSelection();
    }
  }

  // Ctrl+A：全选当前筛选视图（未进入选择态时顺带进入）
  onSelectAllReq(): void {
    this.selectAllShown();
  }

  // Delete：选择态下弹出删除确认（非选择态空操作）
  onDeleteSelReq(): void {
    if (this.selectionMode()) {
      this.showDeleteConfirm();
    }
  }

  async loadData(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    await AppDb.ready(context);
    this.categories = await CategoryRepo.list();
    this.mangas = await MangaRepo.getLibrary();
    this.categoryIdsMap = await MangaRepo.libraryCategoryIds();
    this.statsMap = await MangaRepo.stats();
    this.downloadCounts = DownloadService.downloadedChapterCounts();
    this.trackedIds = await TrackRepo.trackedMangaIds();
    const langs: Record<string, string> = {};
    for (const manga of this.mangas) {
      if (langs[manga.sourceKey] === undefined) {
        const source = SourceRegistry.get(manga.sourceKey);
        langs[manga.sourceKey] = source !== undefined ? source.lang.toUpperCase() : '';
      }
    }
    this.langMap = langs;
    this.reshuffle();
    this.loading = false;
  }

  async refreshLibrary(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    // 网络限制（仅 Wi-Fi / 仅充电）不满足时跳过本次批量更新并提示
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
      await this.loadData();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.updates_refresh_failed'));
    }
    this.refreshing = false;
  }

  // 溢出菜单：更新分类（仅刷新当前分类）
  async refreshCategoryNow(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    // 网络限制（仅 Wi-Fi / 仅充电）不满足时跳过本次批量更新并提示
    const blockReason = UpdateService.checkUpdateRestrictions();
    if (blockReason !== '') {
      Util.toast(this.getUIContext(), blockReason);
      return;
    }
    this.refreshing = true;
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const newCount = await UpdateService.refreshCategory(context, this.selectedCategory);
      if (newCount > 0) {
        Util.toastRes(this.getUIContext(), $r('app.string.updates_found_new'), [newCount]);
      } else {
        Util.toastRes(this.getUIContext(), $r('app.string.updates_no_new'));
      }
      await this.loadData();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.updates_refresh_failed'));
    }
    this.refreshing = false;
  }

  openRandomManga(): void {
    const list = this.shownList;
    if (list.length === 0) {
      return;
    }
    const idx = Math.floor(Math.random() * list.length);
    this.openDetail(list[idx]);
  }

  shownMangas(): MangaRecord[] {
    return this.shownList;
  }

  openDetail(record: MangaRecord): void {
    const params: DetailParams = { mangaId: record.id };
    this.pathStack.pushPathByName('MangaDetail', params);
  }

  @Builder
  selectionActionBtn(icon: string, label: Resource, onTap: () => void) {
    Column({ space: 4 }) {
      AppIcon({ name: icon, iconSize: 22, tint: this.pal.text })
      Text(label)
        .fontSize(10)
        .fontColor(this.pal.sub)
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  selectionActionBar() {
    Row() {
      this.selectionActionBtn('label', $r('app.string.action_move_category'), (): void => {
        this.showMultiCategoryMenu();
      })
      this.selectionActionBtn('done_all', $r('app.string.action_mark_as_read'), (): void => {
        this.markSelectionRead(true);
      })
      this.selectionActionBtn('cancel', $r('app.string.action_mark_as_unread'), (): void => {
        this.markSelectionRead(false);
      })
      this.selectionActionBtn('download', $r('app.string.action_download'), (): void => {
        this.downloadSelection();
      })
      this.selectionActionBtn('delete', $r('app.string.action_delete'), (): void => {
        this.showDeleteConfirm();
      })
      this.selectionActionBtn('open_in_new', $r('app.string.action_migrate'), (): void => {
        this.migrateSelection();
      })
    }
    .width('100%')
    .padding({
      left: 8,
      right: 8,
      top: 4,
      bottom: this.navBarH + 8
    })
    .backgroundColor(this.pal.card)
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  @Builder
  filterSheetBuilder() {
    LibrarySettingsSheet({
      sortKey: this.sortKey,
      sortAsc: this.sortAsc,
      filterDownloaded: this.fDownloaded,
      filterUnread: this.fUnread,
      filterStarted: this.fStarted,
      filterBookmarked: this.fBookmarked,
      filterCompleted: this.fCompleted,
      filterTracked: this.fTracked,
      viewMode: this.viewMode,
      gridCols: this.gridCols,
      contentW: this.contentW,
      showUnreadBadge: this.showUnreadBadge,
      showDownloadBadge: this.showDownloadBadge,
      showLocalBadge: this.showLocalBadge,
      showLanguageBadge: this.showLanguageBadge,
      showCategoryTabs: this.showCategoryTabs,
      showMangaCount: this.showMangaCount,
      onReshuffle: () => {
        this.reshuffle();
      }
    })
  }

  build() {
    Column() {
      // 顶栏已移至 Index 的 Navigation 标题栏（LibraryHeader，沉浸光感材质）

      // 分类 chips
      if (this.showCategoryTabs) {
        Scroll() {
          Row({ space: 8 }) {
            Text(this.showMangaCount ?
              `${Util.resStr(this.getUIContext(), $r('app.string.common_all'))} ${this.categoryCount(0)}` :
              Util.resStr(this.getUIContext(), $r('app.string.common_all')))
              .fontSize(13)
              .fontColor(this.selectedCategory === 0 ? this.pal.onPrimary : this.pal.text)
              .backgroundColor(this.selectedCategory === 0 ? this.pal.primary : this.pal.chip)
              .borderRadius(14)
              .padding({
                left: 14,
                right: 14,
                top: 6,
                bottom: 6
              })
              .onClick(() => {
                this.selectedCategory = 0;
              })
            ForEach(this.categories, (cat: CategoryRecord) => {
              Text(this.showMangaCount ?
                `${Util.categoryLabelStr(this.getUIContext(), cat.name)} ${this.categoryCount(cat.id)}` :
                Util.categoryLabel(cat.name))
                .fontSize(13)
                .fontColor(this.selectedCategory === cat.id ? this.pal.onPrimary : this.pal.text)
                .backgroundColor(this.selectedCategory === cat.id ? this.pal.primary : this.pal.chip)
                .borderRadius(14)
                .padding({
                  left: 14,
                  right: 14,
                  top: 6,
                  bottom: 6
                })
                .onClick(() => {
                  this.selectedCategory = cat.id;
                })
            }, (cat: CategoryRecord) => `chip-${cat.id}-${cat.name}`)
          }
          .padding({ left: 16, right: 16, top: 8 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        // 分类不足一屏时内容靠左排布（Scroll 默认居中）
        .align(Alignment.Start)
        .width('100%')
        .margin({ bottom: 4 })
      }

      // 内容
      Column() {
        if (this.loading) {
          LoadingState()
        } else if (this.shownList.length === 0) {
          Column() {
            EmptyScreen({
              message: this.searchQuery.trim() !== '' || this.filterActive()
                ? $r('app.string.library_no_match') : $r('app.string.library_empty')
            })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.viewMode === 'list') {
          Column() {
            List({ space: 0 }) {
              LazyForEach(this.libSource, (record: MangaRecord) => {
                ListItem() {
                  SwipeActionItem({
                    record: record,
                    mode: 'list',
                    startAction: this.itemSwipeStart(),
                    endAction: this.itemSwipeEnd(),
                    unreadCount: this.unreadOf(record.id),
                    downloadCount: this.downloadCounts[`${record.id}`] || 0,
                    langLabel: ContentType.isLocal(record.sourceKey) ? '' : this.langMap[record.sourceKey] || '',
                    isLocal: ContentType.isLocal(record.sourceKey),
                    showUnreadBadge: this.showUnreadBadge,
                    showDownloadBadge: this.showDownloadBadge,
                    showLocalBadge: this.showLocalBadge,
                    showLanguageBadge: this.showLanguageBadge,
                    isSelected: this.selection.has(record.id),
                    onItemClick: (r: MangaRecord): void => {
                      this.onItemTap(r);
                    },
                    onItemLongPress: (r: MangaRecord): void => {
                      this.onItemLongPress(r);
                    },
                    onItemMenuSelect: (r: MangaRecord): void => {
                      this.menuSelectItem(r);
                    },
                    onItemMenuCategory: (r: MangaRecord): void => {
                      this.showQuickCategoryMenu(r);
                    },
                    onSwipe: (action: string): void => {
                      this.onItemSwipe(record, action);
                    }
                  })
                }
                // 搜索/筛选/分类切换行增删转场：淡入淡出 + 轻微位移
                .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
                  .animation({ duration: 200, curve: Curve.Friction }))
              }, (record: MangaRecord) => `lib-${record.id}`)
            }
            .scrollBar(BarState.Off)
            .contentEndOffset(this.navBarH + this.tabPadH)
            .layoutWeight(1)
          }
          .width('100%')
          .layoutWeight(1)
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.Friction }))
        } else {
          Grid() {
            LazyForEach(this.libSource, (record: MangaRecord) => {
              GridItem() {
                SwipeActionItem({
                  record: record,
                  mode: this.viewMode,
                  startAction: this.itemSwipeStart(),
                  endAction: this.itemSwipeEnd(),
                  unreadCount: this.unreadOf(record.id),
                  downloadCount: this.downloadCounts[`${record.id}`] || 0,
                  langLabel: ContentType.isLocal(record.sourceKey) ? '' : this.langMap[record.sourceKey] || '',
                  isLocal: ContentType.isLocal(record.sourceKey),
                  showUnreadBadge: this.showUnreadBadge,
                  showDownloadBadge: this.showDownloadBadge,
                  showLocalBadge: this.showLocalBadge,
                  showLanguageBadge: this.showLanguageBadge,
                  isSelected: this.selection.has(record.id),
                  onItemClick: (r: MangaRecord): void => {
                    this.onItemTap(r);
                  },
                  onItemLongPress: (r: MangaRecord): void => {
                    this.onItemLongPress(r);
                  },
                  onItemMenuSelect: (r: MangaRecord): void => {
                    this.menuSelectItem(r);
                  },
                  onItemMenuCategory: (r: MangaRecord): void => {
                    this.showQuickCategoryMenu(r);
                  },
                    onSwipe: (action: string): void => {
                      this.onItemSwipe(record, action);
                    }
                  })
                }
                // 搜索/筛选/分类切换行增删转场：淡入淡出 + 轻微位移
                .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
                  .animation({ duration: 200, curve: Curve.Friction }))
              }, (record: MangaRecord) => `lib-${record.id}`)
            }
            .columnsTemplate(this.columnsTemplate())
          .columnsGap(8)
          .rowsGap(12)
          .padding({ left: 8, right: 8, top: 4 })
          .contentEndOffset(this.navBarH + this.tabPadH)
          .layoutWeight(1)
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.Friction }))
        }
      }
      .layoutWeight(1)
      .width('100%')
      .onAreaChange((_old: Area, newArea: Area) => {
        const w = newArea.width;
        if (typeof w === 'number') {
          this.applyContentW(w);
        }
      })

      // 选择模式底部操作栏（对齐 Mihon LibraryBottomActionMenu）
      if (this.selectionMode()) {
        this.selectionActionBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
    // 筛选弹层（头部筛选图标经 libFilterSheetReq 信号触发）
    .bindSheet($$this.showFilterSheet, this.filterSheetBuilder(),
      SheetPreset.fit(this.windowW, {
        height: Bp.sheetHeight(this.windowW),
        detents: ['70%', SheetSize.LARGE],
        showClose: false,
        bg: this.pal.bg
      }))
  }

  private onSelectionChanged(): void {
    AppStorage.setOrCreate(AppKeys.LIB_SELECTION_COUNT, this.selection.size);
    this.libSource.notifyReload();
  }

  private onLibReselect(): void {
    this.showFilterSheet = true;
  }

  // 头部（Navigation 标题栏）信号处理：筛选弹层 / 更新书库 / 更新分类 /
  // 随机打开 / 取消多选 / 反选（计数器递增触发）
  private onFilterSheetReq(): void {
    this.showFilterSheet = true;
  }

  private onRefreshReq(): void {
    this.refreshLibrary();
  }

  private onRefreshCategoryReq(): void {
    this.refreshCategoryNow();
  }

  private onRandomReq(): void {
    this.openRandomManga();
  }

  private onSelClearReq(): void {
    this.clearSelection();
  }

  private onSelInvertReq(): void {
    this.invertSelection();
  }

  // 消费详情页回退书架的搜索请求（已挂载时由 @Watch 触发；未挂载时由 aboutToAppear 兜底）
  private takePendingLibSearch(): void {
    const q = AppStorage.get<string>(AppKeys.LIB_SEARCH_QUERY) ?? '';
    if (q === '') {
      return;
    }
    AppStorage.setOrCreate(AppKeys.LIB_SEARCH_QUERY, '');
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    this.searchOpen = true;
    this.searchQuery = q;
  }

  private onLibSearchReq(): void {
    this.takePendingLibSearch();
    this.onViewInput();
  }

  // 搜索词变化（头部 TextInput / 详情页回退搜索写入）：200ms 防抖后全量重算视图缓存
  private onSearchQuery(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      this.onViewInput();
    }, 200);
  }

  private applySettings(): void {
    this.sortKey = Settings.getLibrarySort();
    this.sortAsc = Settings.getLibrarySortAsc();
    this.fDownloaded = Settings.getLibraryTriState('downloaded');
    this.fUnread = Settings.getLibraryTriState('unread');
    this.fStarted = Settings.getLibraryTriState('started');
    this.fBookmarked = Settings.getLibraryTriState('bookmarked');
    this.fCompleted = Settings.getLibraryTriState('completed');
    this.fTracked = Settings.getLibraryTriState('tracked');
    this.viewMode = Settings.getLibraryView();
    this.gridCols = Settings.getLibraryGridCols();
    this.showUnreadBadge = Settings.getShowUnreadBadge();
    this.showDownloadBadge = Settings.getShowDownloadBadge();
    this.showLocalBadge = Settings.getShowLocalBadge();
    this.showLanguageBadge = Settings.getShowLanguageBadge();
    this.showCategoryTabs = Settings.getShowCategoryTabs();
    this.showMangaCount = Settings.getShowMangaCount();
    this.swipeStartAction = Settings.getLibrarySwipeStartAction();
    this.swipeEndAction = Settings.getLibrarySwipeEndAction();
  }

  // 输入（搜索词/筛选/排序/分类/洗牌/数据刷新）变化后重算视图缓存（O(M log M) 单次）；
  // animate = true 时走 diff 通知以触发行增删转场（由 onViewInput 包 animateTo 调用）
  private refreshView(animate: boolean): void {
    const filtered = this.filteredAll();
    // 分类计数按 membership：一部作品可同时计入多个分类；'0' 为全部分类总数
    const counts: Record<string, number> = {};
    for (const m of filtered) {
      const ids: number[] = this.categoryIdsOf(m);
      for (const cid of ids) {
        const key = `${cid}`;
        counts[key] = (counts[key] || 0) + 1;
      }
    }
    counts['0'] = filtered.length;
    this.categoryCounts = counts;
    const sorted = filtered.slice().sort((a: MangaRecord, b: MangaRecord): number => this.compareMangas(a, b));
    this.shownList = this.selectedCategory > 0 && this.showCategoryTabs ?
      sorted.filter((m: MangaRecord): boolean => this.categoryIdsOf(m).includes(this.selectedCategory)) : sorted;
    if (animate) {
      this.libSource.setItemsDiff(this.shownList);
    } else {
      this.libSource.setItems(this.shownList);
    }
    // 发布筛选生效态给头部（Navigation 标题栏筛选图标着色）
    AppStorage.setOrCreate(AppKeys.LIB_FILTER_ACTIVE, this.filterActive());
  }

  // 用户搜索/筛选/排序/分类切换：包 animateTo + diff 通知，行增删与补位滑动入动画
  private onViewInput(): void {
    // 首次装载（loading 中）不动画，避免启动期批量初始化触发转场
    if (this.loading) {
      this.refreshView(false);
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, (): void => {
      this.refreshView(true);
    });
  }

  // 数据层变化（NSFW 开关/插件重载）：直接重算视图，不走行转场
  private onDataInput(): void {
    this.refreshView(false);
  }

  // 作品的 membership 分类列表（membership 为空时回退主分类 categoryId）
  private categoryIdsOf(m: MangaRecord): number[] {
    const ids: number[] | undefined = this.categoryIdsMap.get(m.id);
    if (ids !== undefined && ids.length > 0) {
      return ids;
    }
    return [m.categoryId];
  }

  // 随机排序洗牌（sortKey === 'random' 时生效）；洗牌后需重算视图
  private reshuffle(): void {
    const ids: number[] = this.mangas.map((m: MangaRecord): number => m.id);
    for (let i = ids.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const t = ids[i];
      ids[i] = ids[j];
      ids[j] = t;
    }
    const order: Record<string, number> = {};
    ids.forEach((id: number, i: number) => {
      order[`${id}`] = i;
    });
    this.randomOrder = order;
    this.refreshView(false);
  }

  private passesTriState(value: string, cond: boolean): boolean {
    if (value === 'include') {
      return cond;
    }
    if (value === 'exclude') {
      return !cond;
    }
    return true;
  }

  private filterActive(): boolean {
    return this.fDownloaded !== 'ignore' || this.fUnread !== 'ignore' ||
      this.fStarted !== 'ignore' || this.fBookmarked !== 'ignore' || this.fCompleted !== 'ignore' ||
      this.fTracked !== 'ignore';
  }

  // 应用搜索 + 三态筛选（不含分类），供列表与分类计数共用
  private filteredAll(): MangaRecord[] {
    let list = this.mangas;
    // 关闭“显示 NSFW 源”时隐藏来自 NSFW 插件源的作品；
    // 源未注册（插件尚未加载完/已卸载）时无法确认非 NSFW，同样隐藏，避免冷启动闪现
    if (!this.showNsfw) {
      list = list.filter((m: MangaRecord): boolean => {
        const source: Source | undefined = SourceRegistry.get(m.sourceKey);
        return source !== undefined && !source.nsfw;
      });
    }
    const q = this.searchQuery.trim().toLowerCase();
    if (q !== '') {
      list = list.filter((m: MangaRecord): boolean => m.title.toLowerCase().includes(q));
    }
    return list.filter((m: MangaRecord): boolean => {
      const s: MangaStats | undefined = this.statsMap[`${m.id}`];
      if (!this.passesTriState(this.fDownloaded, (this.downloadCounts[`${m.id}`] || 0) > 0)) {
        return false;
      }
      if (!this.passesTriState(this.fUnread, s !== undefined && s.unread > 0)) {
        return false;
      }
      if (!this.passesTriState(this.fStarted, s !== undefined && s.readCount > 0)) {
        return false;
      }
      if (!this.passesTriState(this.fBookmarked, s !== undefined && s.bookmarkCount > 0)) {
        return false;
      }
      if (!this.passesTriState(this.fCompleted, m.status === 'completed')) {
        return false;
      }
      if (!this.passesTriState(this.fTracked, this.trackedIds.has(m.id))) {
        return false;
      }
      return true;
    });
  }

  private statsOf(id: number): MangaStats | undefined {
    return this.statsMap[`${id}`];
  }

  // ---- 多选逻辑（对齐 Mihon LibraryViewModel selection）----

  private unreadOf(id: number): number {
    const s: MangaStats | undefined = this.statsMap[`${id}`];
    return s !== undefined ? s.unread : 0;
  }

  private compareMangas(a: MangaRecord, b: MangaRecord): number {
    let cmp = 0;
    if (this.sortKey === 'alpha') {
      const ta = a.title.toLowerCase();
      const tb = b.title.toLowerCase();
      cmp = ta < tb ? -1 : (ta > tb ? 1 : 0);
    } else if (this.sortKey === 'random') {
      const oa = this.randomOrder[`${a.id}`] || 0;
      const ob = this.randomOrder[`${b.id}`] || 0;
      cmp = oa - ob;
    } else {
      const sa = this.statsOf(a.id);
      const sb = this.statsOf(b.id);
      if (this.sortKey === 'total') {
        cmp = (sa !== undefined ? sa.total : 0) - (sb !== undefined ? sb.total : 0);
      } else if (this.sortKey === 'lastRead') {
        cmp = (sa !== undefined ? sa.lastRead : 0) - (sb !== undefined ? sb.lastRead : 0);
      } else if (this.sortKey === 'lastUpdate') {
        cmp = a.lastUpdateAt - b.lastUpdateAt;
      } else if (this.sortKey === 'unread') {
        cmp = (sa !== undefined ? sa.unread : 0) - (sb !== undefined ? sb.unread : 0);
      } else if (this.sortKey === 'latestChapter') {
        cmp = (sa !== undefined ? sa.latest : 0) - (sb !== undefined ? sb.latest : 0);
      } else if (this.sortKey === 'fetchDate') {
        cmp = a.fetchedAt - b.fetchedAt;
      } else if (this.sortKey === 'rating') {
        // 平台评分（源站点评分）：0 = 未提供
        cmp = a.rating - b.rating;
      } else {
        cmp = a.addedAt - b.addedAt;
      }
    }
    return this.sortAsc ? cmp : -cmp;
  }

  // 分类 chip 数量（显示作品数开启时），读缓存
  private categoryCount(categoryId: number): number {
    return this.categoryCounts[`${categoryId}`] || 0;
  }

  private colsForWidth(w: number): number {
    return LibGrid.autoCols(w);
  }

  // 当前生效列数：手动值按书架宽度可行区间收敛（PC 下限、手机上限），0=自动
  private effectiveCols(w: number): number {
    if (this.gridCols > 0) {
      return LibGrid.clampCols(this.gridCols, w);
    }
    return this.colsForWidth(w);
  }

  private gridColsCount(): number {
    return this.effectiveCols(this.contentW > 0 ? this.contentW : 360);
  }

  // 网格宽变化：生效列数档位变化时包 animateTo，让网格重排带过渡动画
  private applyContentW(w: number): void {
    if (w === this.contentW) {
      return;
    }
    const reflow: boolean = this.effectiveCols(w) !== this.gridColsCount();
    if (reflow) {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, (): void => {
        this.contentW = w;
      });
    } else {
      this.contentW = w;
    }
  }

  private columnsTemplate(): string {
    let tpl = '';
    for (let i = 0; i < this.gridColsCount(); i++) {
      tpl += '1fr ';
    }
    return tpl.trim();
  }

  private selectionMode(): boolean {
    return this.selection.size > 0;
  }

  private toggleSelection(id: number): void {
    const next: Set<number> = new Set<number>(this.selection);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    this.selection = next;
  }

  private clearSelection(): void {
    this.selection = new Set<number>();
  }

  private selectAllShown(): void {
    const next: Set<number> = new Set<number>();
    this.shownMangas().forEach((m: MangaRecord): void => {
      next.add(m.id);
    });
    this.selection = next;
  }

  private invertSelection(): void {
    const next: Set<number> = new Set<number>(this.selection);
    this.shownMangas().forEach((m: MangaRecord): void => {
      if (next.has(m.id)) {
        next.delete(m.id);
      } else {
        next.add(m.id);
      }
    });
    this.selection = next;
  }

  // 条目点击：选择模式下切换选中，否则打开详情
  private onItemTap(record: MangaRecord): void {
    if (this.selectionMode()) {
      this.toggleSelection(record.id);
    } else {
      this.openDetail(record);
    }
  }

  // 卡片滑动动作：多选模式下禁用；起始/末端动作由设置决定
  private itemSwipeStart(): string {
    return this.selectionMode() ? 'none' : this.swipeStartAction;
  }

  private itemSwipeEnd(): string {
    return this.selectionMode() ? 'none' : this.swipeEndAction;
  }

  // 滑动动作执行：'read' = 切换已读/未读（有未读标已读，无未读标未读，对齐 Mihon swipe 切换）
  private async onItemSwipe(record: MangaRecord, action: string): Promise<void> {
    if (action !== 'read') {
      return;
    }
    const markRead: boolean = this.unreadOf(record.id) > 0;
    await ChapterRepo.markAllRead(record.id, markRead);
    // 标记已读：按下载设置删除已读章节的下载
    if (markRead) {
      DownloadRules.onDeleteAllRead(record.id);
    }
    Util.toastRes(this.getUIContext(),
      markRead ? $r('app.string.action_mark_as_read') : $r('app.string.action_mark_as_unread'));
    await this.loadData();
  }

  // 长按：仅进入/切换多选（对齐 Mihon 书架选择模式，不弹改分类弹窗；
  // 改分类走详情页长按「已在书架」或多选操作条「移动分类」）
  private onItemLongPress(record: MangaRecord): void {
    this.toggleSelection(record.id);
  }

  // PC 右键菜单「选择」/ Ctrl+点击：切换多选（与长按一致）
  private menuSelectItem(record: MangaRecord): void {
    this.toggleSelection(record.id);
  }

  // PC 右键菜单「移动分类」：单条改分类弹窗（预选当前 membership），确认后覆盖落库刷新
  private showQuickCategoryMenu(record: MangaRecord): void {
    const preselected: number[] = this.categoryIdsOf(record);
    const dialog = new CustomDialogController({
      builder: ChangeCategoryDialog({
        categories: this.categories,
        preselectedIds: preselected,
        title: $r('app.string.action_move_category'),
        onConfirm: (categoryIds: number[]): void => {
          MangaRepo.setCategories(record.id, LibraryAddFlow.normalizeCategoryIds(categoryIds))
            .then((): Promise<void> => {
              this.clearSelection();
              return this.loadData();
            })
            .catch((_e: Error): void => {
              Util.toastRes(this.getUIContext(), $r('app.string.library_move_failed'));
              this.loadData();
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

  // 批量移动分类：预选全部选中作品的共有分类，确认后逐个覆盖 membership
  private showMultiCategoryMenu(): void {
    const ids: number[] = Array.from(this.selection);
    if (ids.length === 0) {
      return;
    }
    // 共有分类：所有选中作品 membership 均包含的分类才预选
    const first: number[] = this.categoryIdsOf(this.mangas.find((m: MangaRecord): boolean => m.id === ids[0]) ??
      new MangaRecord());
    const common: number[] = first.filter((cid: number): boolean =>
      ids.every((id: number): boolean => {
        const manga: MangaRecord | undefined = this.mangas.find((m: MangaRecord): boolean => m.id === id);
        return manga !== undefined && this.categoryIdsOf(manga).includes(cid);
      }));
    const dialog = new CustomDialogController({
      builder: ChangeCategoryDialog({
        categories: this.categories,
        preselectedIds: common,
        title: $r('app.string.action_move_category'),
        onConfirm: (categoryIds: number[]): void => {
          const target: number[] = LibraryAddFlow.normalizeCategoryIds(categoryIds);
          this.clearSelection();
          Promise.all(ids.map((id: number): Promise<void> => MangaRepo.setCategories(id, target)))
            .then((): Promise<void> => this.loadData())
            .catch((_e: Error): void => {
              Util.toastRes(this.getUIContext(), $r('app.string.library_move_failed'));
              this.loadData();
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

  private async markSelectionRead(read: boolean): Promise<void> {
    const ids: number[] = Array.from(this.selection);
    this.clearSelection();
    await Promise.all(ids.map((id: number): Promise<void> => ChapterRepo.markAllRead(id, read)));
    // 手动全部标记已读：按下载设置删除已读章节的下载
    if (read) {
      for (const id of ids) {
        DownloadRules.onDeleteAllRead(id);
      }
    }
    await this.loadData();
  }

  // 下载选中漫画的全部未读章节（本地图源跳过）；章节列表并行加载，入队顺序保持
  private async downloadSelection(): Promise<void> {
    const ids: number[] = Array.from(this.selection);
    this.clearSelection();
    const targets: MangaRecord[] = [];
    for (const id of ids) {
      const manga: MangaRecord | undefined = this.mangas.find((m: MangaRecord): boolean => m.id === id);
      if (manga !== undefined && !ContentType.isLocal(manga.sourceKey)) {
        targets.push(manga);
      }
    }
    const chapterLists: ChapterRecord[][] =
      await Promise.all(
        targets.map((manga: MangaRecord): Promise<ChapterRecord[]> => ChapterRepo.listByManga(manga.id)));
    let queued: number = 0;
    for (let i = 0; i < targets.length; i++) {
      const manga: MangaRecord = targets[i];
      for (const ch of chapterLists[i]) {
        if (!ch.read && !DownloadService.isQueued(ch.id)) {
          const task: DownloadTask = new DownloadTask();
          task.mangaId = manga.id;
          task.mangaTitle = manga.title;
          task.chapterId = ch.id;
          task.chapterName = ch.name;
          task.chapterNumber = ch.chapterNumber;
          task.dateUpload = ch.dateUpload;
          task.sourceKey = manga.sourceKey;
          task.mangaUrl = manga.url;
          task.chapterUrl = ch.url;
          DownloadService.enqueue(task);
          queued += 1;
        }
      }
    }
    Util.toastRes(this.getUIContext(), $r('app.string.action_download_queued'), [queued]);
  }

  private showDeleteConfirm(): void {
    const dialog = new CustomDialogController({
      builder: ConfirmDialog({
        title: $r('app.string.action_remove_from_library'),
        message: Util.resStr(this.getUIContext(), $r('app.string.action_remove_from_library_msg'),
          [this.selection.size]),
        confirmText: $r('app.string.action_delete'),
        onConfirm: (): void => {
          this.removeSelection();
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private async removeSelection(): Promise<void> {
    const ids: number[] = Array.from(this.selection);
    this.clearSelection();
    await Promise.all(ids.map((id: number): Promise<void> => MangaRepo.setInLibrary(id, false)));
    // libDirty 的 @Watch(onLibDirty) 会统一触发 loadData，无需手动重复加载
    AppStorage.set(AppKeys.LIB_DIRTY, this.libDirty + 1);
  }

  // 迁移选中漫画（复用迁移搜索页）
  private migrateSelection(): void {
    const ids: number[] = Array.from(this.selection);
    this.clearSelection();
    const params: MigrateSearchParams = { mangaIds: ids };
    this.pathStack.pushPathByName('MigrateSearch', params);
  }
}
