import { AppDb } from '../data/AppDb';
import { ChapterRepo, HistoryRepo } from '../data/Repos';
import { HistoryItem } from '../model/Models';
import { ContentOpen } from './ContentOpen';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { EmptyScreen } from './components/EmptyScreen';
import { SmartImage } from './components/SmartImage';
import { ConfirmDialog } from './components/Dialogs';
import { AppIcon } from './components/AppIcon';
import { SourceRegistry } from '../source/Source';

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
  @State confirmClear: boolean = false;
  // 多选删除（对齐 Mihon HistoryScreen 长按进入选择模式）
  @State selecting: boolean = false;
  @State selectedIds: Set<number> = new Set<number>();
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

  build() {
    this.bodyContent()
  }

  // 页面主体：滚动容器全宽（滚动条贴窗口边），内容列经 contentInset 限宽居中
  private inset(): number {
    return Bp.contentInset(this.windowW);
  }

  @Builder
  bodyContent() {
    Column() {
      Row() {
        Text($r('app.string.history_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        if (!this.selecting) {
          Text(this.confirmClear ? $r('app.string.history_confirm_clear') : $r('app.string.history_clear'))
            .fontSize(14)
            .fontColor(this.confirmClear ? '#E05252' : this.pal.sub)
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              this.clearHistory();
            })
        }
      }
      .width('100%')
      .padding({
        left: 16 + this.inset(),
        right: 16 + this.inset(),
        top: 12,
        bottom: 8
      })

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.pal.primary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.items.length === 0) {
        Column() {
          EmptyScreen({ message: $r('app.string.history_empty') })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          List({ space: 0 }) {
            ForEach(this.items, (item: HistoryItem) => {
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
            }, (item: HistoryItem) => `his-${item.chapterId}-${item.seenAt}-${item.coverUrl}`)
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

  private onHistoryReselect(): void {
    this.resumeLastRead();
  }

  // ----- 多选删除 -----

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
    return this.items.length > 0 && this.selectedIds.size >= this.items.length;
  }

  private toggleSelectAll(): void {
    if (this.allSelected()) {
      this.selectedIds = new Set<number>();
      return;
    }
    const ids: Set<number> = new Set<number>();
    for (const item of this.items) {
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
