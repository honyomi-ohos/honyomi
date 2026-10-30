import { AppDb } from '../data/AppDb';
import { CategoryRepo, ChapterRepo, HistoryRepo, MangaRepo } from '../data/Repos';
import { DuplicateManga, HistoryItem, MangaRecord } from '../model/Models';
import { DetailParams, MigrateSearchParams } from '../model/RouteParams';
import { ContentOpen } from './ContentOpen';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { AppKeys } from '../common/AppKeys';
import { Settings } from '../common/Settings';
import { LibraryAddFlow } from '../common/LibraryAddFlow';
import { EmptyScreen } from './components/EmptyScreen';
import { LoadingState } from './components/LoadingState';
import { SmartImage } from './components/SmartImage';
import { ChangeCategoryDialog, ConfirmDialog, DuplicateMangaDialog } from './components/Dialogs';
import { AppIcon } from './components/AppIcon';
import { SourceRegistry } from '../source/Source';

// 历史页头部：渲染于根 Navigation 标题栏（Index 挂载，组件随页签切换卸载），
// 与内容区的全部通信经 AppStorage 进行（键见 AppKeys）
@Component
export struct HistoryHeader {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  // 搜索框打开态（对齐 Mihon SearchToolbar：search 图标展开输入框，close 收起）；
  // AppStorage 持有，页签切换头部卸载不丢失
  @StorageLink('historySearchOpen') searchOpen: boolean = false;
  // 搜索词：头部 TextInput 写，内容区过滤读
  @StorageLink('historySearchQuery') searchQuery: string = '';
  // 确认清空态：内容区发布，delete_sweep 图标着色读
  @StorageProp('historyConfirmClear') confirmClear: boolean = false;

  build() {
    Row() {
      if (this.searchOpen) {
        TextInput({
          text: this.searchQuery,
          placeholder: $r('app.string.history_search_hint')
        })
          .id('historySearchInput')
          .layoutWeight(1)
          .height(38)
          .fontSize(15)
          .fontColor(this.pal.text)
          .placeholderColor(this.pal.sub)
          .caretColor(this.pal.primary)
          .backgroundColor(this.pal.chip)
          .borderRadius(19)
          .padding({ left: 16, right: 16 })
          .transition(TransitionEffect.OPACITY)
          .onChange((value: string) => {
            // 过滤列表变化包进 animateTo：列表行增删转场随输入逐键动画
            this.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, (): void => {
              this.searchQuery = value;
            });
          })
        AppIcon({ name: 'close', iconSize: 22, tint: this.pal.text })
          .padding({ left: 12 })
          .transition(TransitionEffect.OPACITY)
          .onClick(() => {
            this.closeSearch();
          })
      } else {
        Text($r('app.string.history_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
          .transition(TransitionEffect.OPACITY)
        // 清空历史：delete_sweep 图标（对齐 Mihon DeleteSweep），
        // 点击发清空请求信号，二次确认（武装/执行）逻辑在内容区 clearHistory
        AppIcon({
          name: 'delete_sweep',
          iconSize: 22,
          tint: this.confirmClear ? this.pal.badgeRed : this.pal.text
        })
          .padding({ left: 12 })
          .onClick(() => {
            this.requestClear();
          })
        AppIcon({ name: 'search', iconSize: 22, tint: this.pal.text })
          .padding({ left: 12 })
          .onClick(() => {
            this.openSearch();
          })
      }
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

  private openSearch(): void {
    // 展开动画结束后自动聚焦输入框
    this.getUIContext().animateTo({
      duration: 250,
      curve: Curve.Friction,
      onFinish: (): void => {
        this.getUIContext().getFocusController().requestFocus('historySearchInput');
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

  // 清空请求信号（计数器递增，内容区 @Watch 消费）
  private requestClear(): void {
    AppStorage.setOrCreate(AppKeys.HISTORY_CLEAR_REQ, (AppStorage.get<number>(AppKeys.HISTORY_CLEAR_REQ) ?? 0) + 1);
  }
}

// 历史页：最近阅读记录
@Component
export struct HistoryPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  // 页签浮动条避让高度：宽屏无页签条时为 0（Index 按断点发布）
  @StorageProp('tabPadH') tabPadH: number = 76;
  @StorageProp('windowW') windowW: number = 0;
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;
  // 复刻 Mihon：再次点击历史页签续读最近作品的下一未读章节（HistoryTab.onReselect）
  @StorageLink('historyReselect') @Watch('onHistoryReselect') historyReselect: number = 0;
  // 关闭“显示 NSFW 源”时隐藏 NSFW 插件源的历史；插件注册完成后（pluginsDirty）重算过滤
  @StorageProp('showNsfw') @Watch('onLibDirty') showNsfw: boolean = false;
  @StorageProp('pluginsDirty') @Watch('onLibDirty') pluginsDirty: number = 0;
  @State items: HistoryItem[] = [];
  @State loading: boolean = true;
  // 确认清空态经 AppStorage 发布（头部 HistoryHeader 的 delete_sweep 图标着色读）
  @StorageLink('historyConfirmClear') confirmClear: boolean = false;
  // 多选删除（对齐 Mihon HistoryScreen 长按进入选择模式）
  @State selecting: boolean = false;
  @State selectedIds: Set<number> = new Set<number>();
  // 搜索词与头部共享（头部 TextInput 写，此处过滤读）
  @StorageLink('historySearchQuery') searchQuery: string = '';
  // 头部清空请求信号（计数器递增触发 @Watch 走 clearHistory 二次确认逻辑）
  @StorageLink('historyClearReq') @Watch('onClearReq') historyClearReq: number = 0;
  // 清空确认 3 秒倒计时定时器：销毁时清理，防回调写已销毁组件状态
  private confirmTimerId: number = -1;

  aboutToAppear(): void {
    this.loadData();
  }

  aboutToDisappear(): void {
    if (this.confirmTimerId >= 0) {
      clearTimeout(this.confirmTimerId);
      this.confirmTimerId = -1;
    }
  }

  onLibDirty(): void {
    this.loadData();
  }

  async loadData(): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      let items = await HistoryRepo.recent(100);
      // 关闭“显示 NSFW 源”时隐藏 NSFW 插件源的历史条目；
      // 源未注册（插件尚未加载完/已卸载）时无法确认非 NSFW，同样隐藏，避免冷启动闪现
      if (!this.showNsfw) {
        items = items.filter((it: HistoryItem): boolean => {
          const source = SourceRegistry.get(it.sourceKey);
          return source !== undefined && !source.nsfw;
        });
      }
      this.items = items;
    } finally {
      this.loading = false;
    }
  }

  async clearHistory(): Promise<void> {
    if (!this.confirmClear) {
      this.confirmClear = true;
      this.confirmTimerId = setTimeout(() => {
        this.confirmTimerId = -1;
        this.confirmClear = false;
      }, 3000);
      return;
    }
    this.confirmClear = false;
    await HistoryRepo.clear();
    await this.loadData();
    Util.toastRes(this.getUIContext(), $r('app.string.history_cleared'));
  }

  // 未入库历史条目加入书架：查重 → 默认分类分流 → 入库（对齐 Mihon HistoryViewModel.addFavorite）
  private async addFavorite(item: HistoryItem): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    await AppDb.ready(context);
    const manga = await MangaRepo.get(item.mangaId);
    if (manga === undefined || manga.inLibrary) {
      return;
    }
    // 库内疑似重复（同名标题或相同追踪器绑定）
    const duplicates = await MangaRepo.getDuplicateLibraryManga(manga.id, manga.title);
    if (duplicates.length > 0) {
      this.showHistoryDuplicateDialog(manga, duplicates);
      return;
    }
    await this.pickCategoriesAndAdd(manga);
  }

  // 默认归入分类偏好分流；null 时弹分类多选（对齐 MangaViewModel.kt:366-387）
  private async pickCategoriesAndAdd(manga: MangaRecord): Promise<void> {
    const categories = await CategoryRepo.list();
    const preset = LibraryAddFlow.resolveDefaultCategoryIds(categories, Settings.getDefaultCategory());
    if (preset !== null) {
      await LibraryAddFlow.commit(this.getUIContext(), manga, preset);
      return;
    }
    const dialog = new CustomDialogController({
      builder: ChangeCategoryDialog({
        categories: categories,
        preselectedIds: [],
        title: $r('app.string.detail_add_to_library'),
        onConfirm: (categoryIds: number[]): void => {
          LibraryAddFlow.commit(this.getUIContext(), manga,
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

  // 历史条目查重弹窗：依然添加继续入库；点卡片迁移、长按打开详情
  private showHistoryDuplicateDialog(manga: MangaRecord, duplicates: DuplicateManga[]): void {
    const dialog = new CustomDialogController({
      builder: DuplicateMangaDialog({
        duplicates: duplicates,
        onAddAnyway: (): void => {
          this.pickCategoriesAndAdd(manga).catch((_e: Error): void => {
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

  build() {
    this.bodyContent()
  }

  @Builder
  bodyContent() {
    Column() {
      if (this.loading) {
        LoadingState()
      } else if (this.visibleItems().length === 0) {
        Column() {
          // 搜索无结果与无历史区分文案（对齐 Mihon HistoryScreen）
          EmptyScreen({
            message: this.searchQuery.trim() !== '' ?
              $r('app.string.no_results_found') : $r('app.string.history_empty')
          })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          List({ space: 0 }) {
            ForEach(this.visibleItems(), (item: HistoryItem) => {
              ListItem() {
                Row({ space: 12 }) {
                  // 多选态行首勾选框（对齐 Mihon 选择模式）
                  if (this.selecting) {
                    AppIcon({
                      name: this.selectedIds.has(item.chapterId) ? 'check_circle' : 'check_box_outline_blank',
                      iconSize: 20,
                      tint: this.selectedIds.has(item.chapterId) ? this.pal.primary : this.pal.sub
                    })
                  }
                  // 封面（无封面时 SmartImage 内部渲染默认封面占位）；
                  // HistoryItem 不含 sourceKey，传空串走网络/缓存通用路径
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
                  Column() {
                    Text(item.mangaTitle)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.pal.text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(item.chapterName)
                      .fontSize(13)
                      .fontColor(this.pal.sub)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 4 })
                    Text(Util.timeAgo(item.seenAt))
                      .fontSize(11)
                      .fontColor(this.pal.sub)
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (!this.selecting) {
                    // 未入库条目的心形按钮：点击加入书架（对齐 Mihon HistoryItem Favorite）
                    if (!item.inLibrary) {
                      AppIcon({
                        name: 'favorite',
                        iconSize: 20,
                        tint: this.pal.sub
                      })
                        .padding({ left: 4, right: 4 })
                        .onClick(() => {
                          this.addFavorite(item).catch((_e: Error): void => {
                            Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
                          });
                        })
                    }
                    Text($r('app.string.history_continue'))
                      .fontSize(12)
                      .fontColor(this.pal.primary)
                      .backgroundColor(this.pal.chip)
                      .borderRadius(12)
                      .padding({
                        left: 10,
                        right: 10,
                        top: 4,
                        bottom: 4
                      })
                  }
                }
                .width('100%')
                .padding({
                  left: (this.selecting ? 8 : 16) + this.inset(),
                  right: 16 + this.inset(),
                  top: 10,
                  bottom: 10
                })
                // 搜索过滤行增删转场：淡入淡出 + 轻微位移
                .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
                  .animation({ duration: 200, curve: Curve.Friction }))
                .onClick((event?: ClickEvent) => {
                  // PC Ctrl+点击直接进入多选（与右键菜单「选择」一致）
                  if (event !== undefined && Util.isCtrlHeld(event) && !this.selecting) {
                    this.enterSelection(item.chapterId);
                    return;
                  }
                  if (this.selecting) {
                    this.toggleSelected(item.chapterId);
                  } else {
                    ContentOpen.open(this.pathStack, item.mangaId, item.chapterId);
                  }
                })
                // 移动端长按进入多选（对齐 Mihon）
                .gesture(LongPressGesture()
                  .onAction(() => {
                    if (!this.selecting) {
                      this.enterSelection(item.chapterId);
                    }
                  }))
                // PC 右键菜单「选择」
                .bindContextMenu((): void => {
                  this.historyItemMenu(item);
                }, ResponseType.RightClick)
              }
            }, (item: HistoryItem) => `his-${item.chapterId}-${item.seenAt}-${item.coverUrl}-${item.inLibrary}`)
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

          // 多选底部操作条：退出 / 已选计数 / 全选切换 / 删除
          if (this.selecting) {
            Row({ space: 14 }) {
              AppIcon({ name: 'close', iconSize: 20, tint: this.pal.text })
                .onClick(() => {
                  this.exitSelection();
                })
              Text($r('app.string.detail_selected_count', this.selectedIds.size))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal.text)
                .layoutWeight(1)
              AppIcon({
                name: this.allSelected() ? 'deselect' : 'select_all',
                iconSize: 20,
                tint: this.pal.text
              })
                .onClick(() => {
                  this.toggleSelectAll();
                })
              Row({ space: 4 }) {
                AppIcon({ name: 'delete', iconSize: 18, tint: this.pal.badgeRed })
                Text($r('app.string.common_delete'))
                  .fontSize(14)
                  .fontColor(this.pal.badgeRed)
              }
              .opacity(this.selectedIds.size > 0 ? 1 : 0.4)
              .onClick(() => {
                if (this.selectedIds.size > 0) {
                  this.confirmRemoveSelected();
                }
              })
            }
            .width('100%')
            .padding({
              left: 16 + this.inset(),
              right: 16 + this.inset(),
              top: 10,
              bottom: 14
            })
            .backgroundColor(this.pal.bg)
            .shadow({ radius: 12, color: '#33000000', offsetY: -2 })
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }

  // PC 右键菜单「选择」：单条进入多选（与长按一致；移动端仍走长按手势）
  @Builder
  historyItemMenu(item: HistoryItem) {
    Menu() {
      MenuItem({ content: $r('app.string.common_select') })
        .onClick(() => {
          this.enterSelection(item.chapterId);
        })
    }
  }

  // 页面主体：滚动容器全宽（滚动条贴窗口边），内容列经 contentInset 限宽居中
  private inset(): number {
    return Bp.contentInset(this.windowW);
  }

  private onHistoryReselect(): void {
    this.resumeLastRead();
  }

  // 头部清空请求信号：走原 clearHistory 二次确认逻辑（首击武装，3 秒内再击执行）
  private onClearReq(): void {
    this.clearHistory();
  }

  // ----- 多选删除 -----

  // 按标题/章节名过滤（对齐 Mihon HistoryViewModel searchQuery 过滤）
  private visibleItems(): HistoryItem[] {
    const q: string = this.searchQuery.trim().toLowerCase();
    if (q === '') {
      return this.items;
    }
    return this.items.filter((it: HistoryItem): boolean =>
    it.mangaTitle.toLowerCase().indexOf(q) >= 0 || it.chapterName.toLowerCase().indexOf(q) >= 0);
  }

  private enterSelection(chapterId: number): void {
    const ids: Set<number> = new Set<number>();
    ids.add(chapterId);
    this.selectedIds = ids;
    this.selecting = true;
  }

  private exitSelection(): void {
    this.selectedIds = new Set<number>();
    this.selecting = false;
  }

  private toggleSelected(chapterId: number): void {
    const ids: Set<number> = new Set<number>(this.selectedIds);
    if (ids.has(chapterId)) {
      ids.delete(chapterId);
    } else {
      ids.add(chapterId);
    }
    this.selectedIds = ids;
  }

  private allSelected(): boolean {
    const visible: HistoryItem[] = this.visibleItems();
    return visible.length > 0 && this.selectedIds.size >= visible.length;
  }

  private toggleSelectAll(): void {
    if (this.allSelected()) {
      this.selectedIds = new Set<number>();
      return;
    }
    const ids: Set<number> = new Set<number>();
    for (const item of this.visibleItems()) {
      ids.add(item.chapterId);
    }
    this.selectedIds = ids;
  }

  private confirmRemoveSelected(): void {
    const dialog: CustomDialogController = new CustomDialogController({
      builder: ConfirmDialog({
        title: $r('app.string.common_delete'),
        message: $r('app.string.history_remove_selected_confirm', this.selectedIds.size),
        confirmText: $r('app.string.common_delete'),
        onConfirm: (): void => {
          dialog.close();
          this.removeSelected();
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private async removeSelected(): Promise<void> {
    try {
      const ids: number[] = Array.from(this.selectedIds);
      await HistoryRepo.removeByChapters(ids);
      this.exitSelection();
      await this.loadData();
      Util.toastRes(this.getUIContext(), $r('app.string.history_removed'));
    } catch (_e) {
      Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
    }
  }

  // 续读最近一部作品：取最近记录的漫画，打开其第一个未读章节；无可读时提示
  private async resumeLastRead(): Promise<void> {
    if (this.items.length === 0) {
      Util.toastRes(this.getUIContext(), $r('app.string.history_no_next_chapter'));
      return;
    }
    const last: HistoryItem = this.items[0];
    const nextId = await ChapterRepo.firstUnread(last.mangaId);
    if (nextId > 0) {
      ContentOpen.open(this.pathStack, last.mangaId, nextId);
    } else {
      Util.toastRes(this.getUIContext(), $r('app.string.history_no_next_chapter'));
    }
  }
}
