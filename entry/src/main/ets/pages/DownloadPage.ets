import { DownloadService } from '../data/DownloadService';
import { DownloadedChapter, DownloadedManga, DownloadTask } from '../model/Models';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { EmptyScreen } from './components/EmptyScreen';
import { LoadingState } from './components/LoadingState';
import { AppIcon } from './components/AppIcon';
import { ConfirmDialog } from './components/Dialogs';

// 队列分组模型（对齐 Mihon DownloadHeaderItem：按作品分组，组内为章节任务）
class QueueGroup {
  mangaId: number = 0;
  mangaTitle: string = '';
  tasks: DownloadTask[] = [];
}

// 队列渲染项：分组头/任务行混合摊平进单个 ForEach，支撑 onMove 组内拖拽排序
class QueueRowItem {
  isHeader: boolean = false;
  group: QueueGroup = new QueueGroup();
  task: DownloadTask = new DownloadTask();

  key(): string {
    return this.isHeader ? `h-${this.group.mangaId}` : `q-${this.task.chapterId}`;
  }
}

// 已下载渲染项：分组头/章节行混合摊平（折叠时隐藏章节行）
class DownloadedRowItem {
  isHeader: boolean = false;
  group: DownloadedManga = new DownloadedManga();
  chapter: DownloadedChapter = new DownloadedChapter();

  key(): string {
    return this.isHeader ? `dh-${this.group.mangaId}` : `d-${this.chapter.chapterId}`;
  }
}

// 队列行子组件：ForEach key 固定为章节 id 后同 key 行会被复用而不重跑生成器，
// 进度/状态改由本组件自订阅 DownloadService 通知刷新（DownloadTask 非 @Observed）
// 行布局对齐 Mihon download_item.xml：拖拽把手 | 章节标题+页数文本 | 细进度条 | 溢出菜单
@Component
struct QueueTaskRow {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  task: DownloadTask = new DownloadTask();
  // 宽屏内容列缩进：自读 windowW 计算（经宿主传普通属性时，ForEach 缓存项在窗口尺寸变化后不会更新）
  @StorageProp('windowW') windowW: number = 0;
  @State state: number = 0;
  @State progress: number = 0;
  @State total: number = 0;
  @State error: string = '';

  aboutToAppear(): void {
    this.state = this.task.state;
    this.progress = this.task.progress;
    this.total = this.task.total;
    this.error = this.task.error;
    DownloadService.addListener(this.onQueueChanged);
  }

  aboutToDisappear(): void {
    DownloadService.removeListener(this.onQueueChanged);
  }

  // 行溢出菜单（对齐 Mihon download_single.xml：
  // 置顶/置顶本作品/移底/移底本作品/取消/取消本作品，失败态附加重试）
  @Builder
  rowMenuBuilder() {
    Menu() {
      if (this.state === 0) {
        MenuItem({ content: $r('app.string.download_move_top') })
          .onClick(() => {
            DownloadService.moveToTop(this.task.chapterId);
          })
        MenuItem({ content: $r('app.string.download_move_top_series') })
          .onClick(() => {
            DownloadService.moveSeriesToTop(this.task.mangaId);
          })
        MenuItem({ content: $r('app.string.download_move_bottom') })
          .onClick(() => {
            DownloadService.moveToBottom(this.task.chapterId);
          })
        MenuItem({ content: $r('app.string.download_move_bottom_series') })
          .onClick(() => {
            DownloadService.moveSeriesToBottom(this.task.mangaId);
          })
      } else if (this.state === 3) {
        MenuItem({ content: $r('app.string.common_retry') })
          .onClick(() => {
            DownloadService.retry(this.task.chapterId);
          })
      }
      MenuItem({ content: $r('app.string.common_cancel') })
        .contentFontColor(this.pal.badgeRed)
        .onClick(() => {
          DownloadService.cancel(this.task.chapterId);
        })
      MenuItem({ content: $r('app.string.download_cancel_series') })
        .contentFontColor(this.pal.badgeRed)
        .onClick(() => {
          DownloadService.cancelSeries(this.task.mangaId);
        })
    }
  }

  build() {
    Row() {
      AppIcon({ name: 'drag_handle', iconSize: 20, tint: this.pal.sub })
        .margin({ right: 8 })
      Column() {
        Row() {
          // 组头已展示作品标题，行内主文本为章节名（对齐 Mihon DownloadHolder）
          Text(this.task.chapterName)
            .fontSize(14)
            .fontColor(this.pal.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          // 页数进度文本（对齐 Mihon "downloaded/total"）；
          // 视频/音频任务 total 为字节数，超过页数上限时不展示数字只保留进度条
          if (this.total > 0 && this.total <= 500) {
            Text(`${this.progress}/${this.total}`)
              .fontSize(12)
              .fontColor(this.pal.sub)
              .margin({ left: 8 })
          }
        }
        .width('100%')

        if (this.total > 0) {
          Progress({ value: this.progress, total: this.total, type: ProgressType.Linear })
            .style({ strokeWidth: 3 })
            .color(this.state === 3 ? this.pal.badgeRed : this.pal.primary)
            .backgroundColor(this.pal.chip)
            .margin({ top: 6 })
        }
        if (this.state === 3 && this.error !== '') {
          Text(Util.errText(this.getUIContext(), this.error))
            .fontSize(11)
            .fontColor(this.pal.badgeRed)
            .maxLines(1)
            .margin({ top: 3 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      AppIcon({ name: 'more_vert', iconSize: 20, tint: this.pal.sub })
        .bindMenu(this.rowMenuBuilder)
        .padding({ left: 6, right: 2 })
    }
    .width('100%')
    .padding({
      left: 12 + Bp.contentInset(this.windowW),
      right: 12 + Bp.contentInset(this.windowW),
      top: 10,
      bottom: 10
    })
  }

  private onQueueChanged = (): void => {
    this.refreshState();
  }

  private refreshState(): void {
    const queue: DownloadTask[] = DownloadService.getQueue();
    for (const t of queue) {
      if (t.chapterId === this.task.chapterId) {
        this.state = t.state;
        this.progress = t.progress;
        this.total = t.total;
        this.error = t.error;
        return;
      }
    }
  }
}

// 下载管理页：双 Tab 分别管理"下载中"队列与"已下载"章节
// （交互对齐 Mihon DownloadQueueScreen：按作品分组可折叠、标题数量 Pill 徽标、
// 排序/溢出菜单、组内拖拽排序、行菜单整体调整优先级、右下角暂停/继续 FAB）
@Component
export struct DownloadPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @State currentTab: number = 0;
  @State queue: DownloadTask[] = [];
  @State queueRows: QueueRowItem[] = [];
  @State downloadedRows: DownloadedRowItem[] = [];
  @State downloadedCount: number = 0;
  @State loading: boolean = true;
  @State paused: boolean = false;
  @State fabExpanded: boolean = true;
  @State selecting: boolean = false;
  @State selectedIds: Set<number> = new Set<number>();
  private downloaded: DownloadedManga[] = [];
  private collapsedQueueIds: Set<number> = new Set<number>();
  private collapsedDownloadedIds: Set<number> = new Set<number>();
  private tabsController: TabsController = new TabsController();
  private lastQueueSignature: string = '';

  aboutToAppear(): void {
    DownloadService.addListener(this.onQueueChanged);
    this.queue = DownloadService.getQueue().slice();
    this.lastQueueSignature = this.queueSignature();
    this.paused = DownloadService.isPaused();
    this.rebuildQueueRows();
    this.loadDownloaded();
  }

  aboutToDisappear(): void {
    DownloadService.removeListener(this.onQueueChanged);
  }

  build() {
    NavDestination() {
      this.bodyContent()
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }

  // 页面主体：滚动容器全宽（滚动条贴窗口边），内容列经 contentInset 限宽居中（720 上限）
  private inset(): number {
    return Bp.contentInset(this.windowW);
  }

  // 排序菜单（对齐 Mihon 排序键：章节号升/降序 + 上传日期从新到旧/从旧到新）
  @Builder
  sortMenuBuilder() {
    Menu() {
      MenuItem({ content: $r('app.string.download_sort_asc') })
        .onClick(() => {
          DownloadService.sortQueue(true);
        })
      MenuItem({ content: $r('app.string.download_sort_desc') })
        .onClick(() => {
          DownloadService.sortQueue(false);
        })
      MenuItem({ content: $r('app.string.download_sort_newest') })
        .onClick(() => {
          DownloadService.sortQueueByDate(true);
        })
      MenuItem({ content: $r('app.string.download_sort_oldest') })
        .onClick(() => {
          DownloadService.sortQueueByDate(false);
        })
    }
  }

  // 头部溢出菜单（对齐 Mihon overflow："Clear finished" + "Cancel all"）
  @Builder
  overflowMenuBuilder() {
    Menu() {
      MenuItem({ content: $r('app.string.download_clear_finished') })
        .onClick(() => {
          DownloadService.clearFinished();
        })
      MenuItem({ content: $r('app.string.download_cancel_all') })
        .contentFontColor(this.pal.badgeRed)
        .onClick(() => {
          DownloadService.cancelAll();
        })
    }
  }

  // 页签标签：选中超粗+主色，附数量徽标（对齐 Mihon TabRow + Pill 计数）
  @Builder
  tabLabel(title: ResourceStr, count: number, index: number) {
    Column() {
      Row({ space: 5 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.currentTab === index ? this.pal.primary : this.pal.text)
        if (count > 0) {
          Text(`${count}`)
            .fontSize(11)
            .fontColor(this.currentTab === index ? this.pal.primary : this.pal.sub)
            .backgroundColor(this.isDark ? this.pal.text + '1F' : this.pal.text + '14')
            .borderRadius(9)
            .padding({
              left: 6,
              right: 6,
              top: 1,
              bottom: 1
            })
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(44)
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.tabsController.changeIndex(index);
    })
  }

  // 下载中分组头：折叠开关 + 作品标题 + 章节数（点击整行切换折叠）
  @Builder
  queueGroupHeader(group: QueueGroup) {
    Row({ space: 8 }) {
      AppIcon({
        name: this.isQueueGroupCollapsed(group.mangaId) ? 'expand_more' : 'expand_less',
        iconSize: 18,
        tint: this.pal.sub
      })
      Text(group.mangaTitle)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text($r('app.string.download_chapter_count', group.tasks.length))
        .fontSize(11)
        .fontColor(this.pal.sub)
    }
    .width('100%')
    .padding({
      left: 12 + this.inset(),
      right: 12 + this.inset(),
      top: 12,
      bottom: 6
    })
    .backgroundColor(this.pal.bg)
    .onClick(() => {
      this.toggleQueueGroup(group.mangaId);
    })
  }

  // 已下载分组头：普通态点击折叠/展开、长按进入多选并勾选整组、尾部图标整作品删除；
  // 多选态头部变勾选框，点击整组勾选/取消
  @Builder
  downloadedGroupHeader(group: DownloadedManga) {
    Row({ space: 8 }) {
      if (this.selecting) {
        AppIcon({
          name: this.isGroupFullySelected(group) ? 'check_circle' : 'check_box_outline_blank',
          iconSize: 20,
          tint: this.isGroupFullySelected(group) ? this.pal.primary : this.pal.sub
        })
      } else {
        AppIcon({
          name: this.isDownloadedGroupCollapsed(group.mangaId) ? 'expand_more' : 'expand_less',
          iconSize: 18,
          tint: this.pal.sub
        })
      }
      AppIcon({ name: 'photo', iconSize: 16 })
      Text(group.mangaTitle)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text($r('app.string.download_chapter_count', group.chapters.length))
        .fontSize(11)
        .fontColor(this.pal.sub)
      if (!this.selecting) {
        AppIcon({ name: 'delete_sweep', iconSize: 20, tint: this.pal.sub })
          .padding({ left: 6, right: 2 })
          .onClick(() => {
            this.confirmDeleteSeries(group);
          })
      }
    }
    .width('100%')
    .padding({
      left: 12 + this.inset(),
      right: 12 + this.inset(),
      top: 14,
      bottom: 8
    })
    .backgroundColor(this.pal.bg)
    .onClick((event?: ClickEvent) => {
      if (event !== undefined && Util.isCtrlHeld(event) && !this.selecting) {
        this.enterGroupSelection(group);
        return;
      }
      if (this.selecting) {
        this.toggleGroupSelection(group);
      } else {
        this.toggleDownloadedGroup(group.mangaId);
      }
    })
    .gesture(LongPressGesture()
      .onAction(() => {
        if (!this.selecting) {
          this.enterGroupSelection(group);
        }
      }))
    .bindContextMenu((): void => {
      this.downloadedGroupMenu(group);
    }, ResponseType.RightClick)
  }

  // 已下载章节行：普通态尾部单章删除、长按进入多选；
  // 多选态头部勾选框、点击行切换选中
  @Builder
  downloadedChapterRow(item: DownloadedChapter) {
    Row({ space: 8 }) {
      if (this.selecting) {
        AppIcon({
          name: this.selectedIds.has(item.chapterId) ? 'check_circle' : 'check_box_outline_blank',
          iconSize: 20,
          tint: this.selectedIds.has(item.chapterId) ? this.pal.primary : this.pal.sub
        })
          .margin({ left: 8 })
      }
      Text(item.chapterName)
        .fontSize(14)
        .fontColor(this.pal.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (!this.selecting) {
        AppIcon({ name: 'delete', iconSize: 20, tint: this.pal.sub })
          .padding(6)
          .onClick(() => {
            this.deleteChapter(item);
          })
      }
    }
    .width('100%')
    .padding({
      left: (this.selecting ? 12 : 42) + this.inset(),
      right: 6 + this.inset(),
      top: 6,
      bottom: 6
    })
    .onClick((event?: ClickEvent) => {
      if (event !== undefined && Util.isCtrlHeld(event) && !this.selecting) {
        this.enterSelection(item.chapterId);
        return;
      }
      if (this.selecting) {
        this.toggleSelected(item.chapterId);
      }
    })
    .gesture(LongPressGesture()
      .onAction(() => {
        if (!this.selecting) {
          this.enterSelection(item.chapterId);
        }
      }))
    .bindContextMenu((): void => {
      this.downloadedChapterMenu(item);
    }, ResponseType.RightClick)
  }

  // 下载中 Tab：分组队列列表 + 拖拽排序 + 暂停/继续 FAB
  @Builder
  queueTabContent() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      List({ space: 0 }) {
        if (this.queue.length === 0) {
          ListItem() {
            Column() {
              EmptyScreen({ message: $r('app.string.download_empty'), compact: true })
            }
            .width('100%')
            .padding({ top: 48, bottom: 48 })
          }
        } else {
          ForEach(this.queueRows, (item: QueueRowItem) => {
            ListItem() {
              if (item.isHeader) {
                this.queueGroupHeader(item.group)
              } else {
                QueueTaskRow({ task: item.task })
              }
            }
          }, (item: QueueRowItem) => this.queueRowKey(item))
            .onMove((from: number, to: number) => {
              this.onQueueMove(from, to);
            })
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .divider({
        strokeWidth: 1,
        color: this.pal.divider,
        startMargin: 16 + this.inset(),
        endMargin: 16 + this.inset(),
      })
      .onWillScroll((offset: number) => {
        // 对齐 Mihon FAB 手势行为：向列表底部滚动收起、回滚展开
        if (offset > 0) {
          this.fabExpanded = false;
        } else if (offset < 0) {
          this.fabExpanded = true;
        }
      })

      // 暂停/继续 FAB（对齐 Mihon SmallExtendedFloatingActionButton：队列空时隐藏）
      if (this.queue.length > 0) {
        Row({ space: 6 }) {
          AppIcon({ name: this.paused ? 'play_arrow' : 'pause', iconSize: 20, tint: this.pal.onPrimary })
          if (this.fabExpanded) {
            Text(this.paused ? $r('app.string.download_resume') : $r('app.string.download_pause'))
              .fontSize(14)
              .fontColor(this.pal.onPrimary)
          }
        }
        .padding({
          left: this.fabExpanded ? 16 : 11,
          right: this.fabExpanded ? 16 : 11,
          top: 11,
          bottom: 11,
        })
        .borderRadius(24)
        .backgroundColor(this.pal.primary)
        .shadow({ radius: 8, color: '#66000000', offsetY: 4 })
        .margin({ right: 20 + this.inset(), bottom: 28 })
        .animation({ duration: 150 })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
          .animation({ duration: 150 }))
        .onClick(() => {
          if (this.paused) {
            DownloadService.resumeAll();
          } else {
            DownloadService.pauseAll();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // 已下载 Tab：按作品分组的已完成章节列表 + 多选底部操作条
  @Builder
  downloadedTabContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      List({ space: 0 }) {
        if (this.loading) {
          ListItem() {
            LoadingState({ spinnerSize: 28, fill: false })
              .width('100%')
              .padding({ top: 40, bottom: 40 })
          }
        } else if (this.downloadedRows.length === 0) {
          ListItem() {
            Column() {
              EmptyScreen({ message: $r('app.string.download_empty'), compact: true })
            }
            .width('100%')
            .padding({ top: 48, bottom: 48 })
          }
        } else {
          ForEach(this.downloadedRows, (item: DownloadedRowItem) => {
            ListItem() {
              if (item.isHeader) {
                this.downloadedGroupHeader(item.group)
              } else {
                this.downloadedChapterRow(item.chapter)
              }
            }
          }, (item: DownloadedRowItem) => this.downloadedRowKey(item))
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .divider({
        strokeWidth: 1,
        color: this.pal.divider,
        startMargin: 16 + this.inset(),
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
            name: this.allDownloadedSelected() ? 'deselect' : 'select_all',
            iconSize: 20,
            tint: this.pal.text
          })
            .onClick(() => {
              this.toggleSelectAllDownloaded();
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
              this.confirmDeleteSelected();
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
    .height('100%')
  }

  @Builder
  bodyContent() {
    Column() {
      // 头部：返回 + 标题 + 队列数 Pill 徽标（对齐 Mihon AppBar + Pill 计数）
      Row() {
        AppIcon({ name: 'arrow_back', iconSize: 24 })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.pathStack.pop();
          })
        Row() {
          Text($r('app.string.download_title'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .maxLines(1)
          if (this.queue.length > 0) {
            Text(`${this.queue.length}`)
              .fontSize(12)
              .fontColor(this.pal.text)
              .backgroundColor(this.isDark ? this.pal.text + '1F' : this.pal.text + '14')
              .borderRadius(11)
              .padding({
                left: 7,
                right: 7,
                top: 2,
                bottom: 2
              })
              .margin({ left: 8 })
          }
        }
        .layoutWeight(1)

        if (this.currentTab === 0 && this.queue.length > 0) {
          AppIcon({ name: 'sort', iconSize: 22 })
            .bindMenu(this.sortMenuBuilder)
            .padding({ left: 10, right: 10 })
          AppIcon({ name: 'more_vert', iconSize: 22 })
            .bindMenu(this.overflowMenuBuilder)
            .padding({ left: 10, right: 6 })
        }
      }
      .width('100%')
      .padding({
        left: 4 + this.inset(),
        right: 8 + this.inset(),
        top: this.statusBarH + 8,
        bottom: 8
      })

      // 页签标签行：在限宽内容列内均分两份（对齐 Mihon TabRow），点击经控制器切换
      Row() {
        this.tabLabel($r('app.string.download_tab_queue'), this.queue.length, 0)
        this.tabLabel($r('app.string.download_tab_downloaded'), this.downloadedCount, 1)
      }
      .width('100%')
      .padding({
        left: 16 + this.inset(),
        right: 16 + this.inset()
      })

      // 双页签 + 可滑动内容（系统 tab 栏隐藏，标签由上方自定义行承载）
      Tabs({ barPosition: BarPosition.Start, index: this.currentTab, controller: this.tabsController }) {
        TabContent() {
          this.queueTabContent()
        }

        TabContent() {
          this.downloadedTabContent()
        }
      }
      .barHeight(0)
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }

  // ----- 队列分组折叠 -----

  private isQueueGroupCollapsed(mangaId: number): boolean {
    return this.collapsedQueueIds.has(mangaId);
  }

  private toggleQueueGroup(mangaId: number): void {
    if (this.collapsedQueueIds.has(mangaId)) {
      this.collapsedQueueIds.delete(mangaId);
    } else {
      this.collapsedQueueIds.add(mangaId);
    }
    this.rebuildQueueRows();
  }

  private isDownloadedGroupCollapsed(mangaId: number): boolean {
    return this.collapsedDownloadedIds.has(mangaId);
  }

  private toggleDownloadedGroup(mangaId: number): void {
    if (this.collapsedDownloadedIds.has(mangaId)) {
      this.collapsedDownloadedIds.delete(mangaId);
    } else {
      this.collapsedDownloadedIds.add(mangaId);
    }
    this.rebuildDownloadedRows();
  }

  // ----- 渲染模型重建 -----

  // 队列摊平：分组头 + （展开组的）任务行；分组按首次出现顺序
  private rebuildQueueRows(): void {
    const rows: QueueRowItem[] = [];
    const groups = new Map<number, QueueGroup>();
    for (const t of this.queue) {
      let g: QueueGroup | undefined = groups.get(t.mangaId);
      if (g === undefined) {
        g = new QueueGroup();
        g.mangaId = t.mangaId;
        g.mangaTitle = t.mangaTitle;
        groups.set(t.mangaId, g);
        const header = new QueueRowItem();
        header.isHeader = true;
        header.group = g;
        rows.push(header);
      }
      g.tasks.push(t);
      if (!this.collapsedQueueIds.has(t.mangaId)) {
        const row = new QueueRowItem();
        row.task = t;
        rows.push(row);
      }
    }
    this.queueRows = rows;
  }

  // 已下载摊平：分组头 + （展开组的）章节行
  private rebuildDownloadedRows(): void {
    const rows: DownloadedRowItem[] = [];
    let count = 0;
    for (const group of this.downloaded) {
      count += group.chapters.length;
      const header = new DownloadedRowItem();
      header.isHeader = true;
      header.group = group;
      rows.push(header);
      if (this.collapsedDownloadedIds.has(group.mangaId)) {
        continue;
      }
      for (const ch of group.chapters) {
        const row = new DownloadedRowItem();
        row.chapter = ch;
        rows.push(row);
      }
    }
    this.downloadedRows = rows;
    this.downloadedCount = count;
  }

  // ----- 组内拖拽排序（对齐 Mihon shouldMove：跨组拖拽禁止） -----

  private onQueueMove(from: number, to: number): void {
    if (from === to) {
      return;
    }
    const fromItem: QueueRowItem | undefined = this.queueRows[from];
    const toItem: QueueRowItem | undefined = this.queueRows[to];
    if (fromItem === undefined || toItem === undefined || fromItem.isHeader || toItem.isHeader) {
      return;
    }
    const movedTask: DownloadTask = fromItem.task;
    const targetTask: DownloadTask = toItem.task;
    if (movedTask.mangaId !== targetTask.mangaId) {
      return;
    }
    const removed: QueueRowItem[] = this.queueRows.splice(from, 1);
    const moved: QueueRowItem | undefined = removed[0];
    if (moved === undefined) {
      return;
    }
    this.queueRows.splice(to, 0, moved);
    this.queueRows = this.queueRows.slice();
    this.syncDraggedGroupOrder(movedTask.mangaId);
  }

  // 拖拽落位后把可见行顺序同步回 DownloadService：
  // 被拖组按行内新顺序、其余分组按原顺序，分组间保持原相对顺序
  private syncDraggedGroupOrder(mangaId: number): void {
    const visible: number[] = [];
    for (const item of this.queueRows) {
      if (!item.isHeader && item.task.mangaId === mangaId) {
        visible.push(item.task.chapterId);
      }
    }
    const ids: number[] = [];
    const seen: Set<number> = new Set<number>();
    for (const t of this.queue) {
      if (seen.has(t.mangaId)) {
        continue;
      }
      seen.add(t.mangaId);
      if (t.mangaId === mangaId) {
        for (const id of visible) {
          ids.push(id);
        }
        for (const tt of this.queue) {
          if (tt.mangaId === mangaId && visible.indexOf(tt.chapterId) < 0) {
            ids.push(tt.chapterId);
          }
        }
      } else {
        for (const tt of this.queue) {
          if (tt.mangaId === t.mangaId) {
            ids.push(tt.chapterId);
          }
        }
      }
    }
    DownloadService.reorderQueue(ids);
    this.queue = DownloadService.getQueue();
  }

  // ----- 数据加载 -----

  private onQueueChanged = (): void => {
    this.queue = DownloadService.getQueue().slice();
    this.paused = DownloadService.isPaused();
    this.rebuildQueueRows();
    // 队列成员变化（完成/新增/取消）时才重扫已下载目录，进度 tick 不触发
    const signature: string = this.queueSignature();
    if (signature !== this.lastQueueSignature) {
      this.lastQueueSignature = signature;
      this.loadDownloaded();
    }
  }

  private queueSignature(): string {
    const ids: string[] = [];
    for (const t of this.queue) {
      ids.push(`${t.chapterId}`);
    }
    return ids.join(',');
  }

  private async loadDownloaded(): Promise<void> {
    this.downloaded = await DownloadService.listDownloaded();
    this.rebuildDownloadedRows();
    this.loading = false;
  }

  private deleteChapter(item: DownloadedChapter): void {
    DownloadService.deleteChapter(item.mangaId, item.chapterId).then(() => {
      this.loadDownloaded();
    });
    Util.toastRes(this.getUIContext(), $r('app.string.download_deleted'));
  }

  // ----- 行 key：折叠态编入分组头 key -----
  // ForEach 对同 key 行复用组件而不重跑生成器，折叠集合又非状态成员，
  // 箭头图标无法驱动刷新；将折叠态编入 key 使头行在切换时销毁重建

  private queueRowKey(item: QueueRowItem): string {
    if (item.isHeader) {
      return `h-${item.group.mangaId}-${this.collapsedQueueIds.has(item.group.mangaId) ? 'c' : 'e'}`;
    }
    return item.key();
  }

  private downloadedRowKey(item: DownloadedRowItem): string {
    if (item.isHeader) {
      return `dh-${item.group.mangaId}-${this.collapsedDownloadedIds.has(item.group.mangaId) ? 'c' : 'e'}`;
    }
    return item.key();
  }

  // ----- 已下载多选 -----

  // PC 右键菜单「选择」：整组进入多选（与长按一致；移动端仍走长按手势）
  @Builder
  downloadedGroupMenu(group: DownloadedManga) {
    Menu() {
      MenuItem({ content: $r('app.string.common_select') })
        .onClick(() => {
          this.enterGroupSelection(group);
        })
    }
  }

  // PC 右键菜单「选择」：单章进入多选（与长按一致）
  @Builder
  downloadedChapterMenu(item: DownloadedChapter) {
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
    this.expandAllDownloadedGroups();
    this.selecting = true;
  }

  private enterGroupSelection(group: DownloadedManga): void {
    const ids: Set<number> = new Set<number>();
    for (const ch of group.chapters) {
      ids.add(ch.chapterId);
    }
    this.selectedIds = ids;
    this.expandAllDownloadedGroups();
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

  private isGroupFullySelected(group: DownloadedManga): boolean {
    if (group.chapters.length === 0) {
      return false;
    }
    for (const ch of group.chapters) {
      if (!this.selectedIds.has(ch.chapterId)) {
        return false;
      }
    }
    return true;
  }

  private toggleGroupSelection(group: DownloadedManga): void {
    const ids: Set<number> = new Set<number>(this.selectedIds);
    const fully: boolean = this.isGroupFullySelected(group);
    for (const ch of group.chapters) {
      if (fully) {
        ids.delete(ch.chapterId);
      } else {
        ids.add(ch.chapterId);
      }
    }
    this.selectedIds = ids;
  }

  private allDownloadedSelected(): boolean {
    return this.downloadedCount > 0 && this.selectedIds.size >= this.downloadedCount;
  }

  private toggleSelectAllDownloaded(): void {
    if (this.allDownloadedSelected()) {
      this.selectedIds = new Set<number>();
      return;
    }
    const ids: Set<number> = new Set<number>();
    for (const group of this.downloaded) {
      for (const ch of group.chapters) {
        ids.add(ch.chapterId);
      }
    }
    this.selectedIds = ids;
  }

  private expandAllDownloadedGroups(): void {
    if (this.collapsedDownloadedIds.size === 0) {
      return;
    }
    this.collapsedDownloadedIds = new Set<number>();
    this.rebuildDownloadedRows();
  }

  // ----- 删除（整作品 / 多选，均先确认） -----

  private confirmDeleteSeries(group: DownloadedManga): void {
    const dialog: CustomDialogController = new CustomDialogController({
      builder: ConfirmDialog({
        title: group.mangaTitle,
        message: $r('app.string.download_delete_series_confirm'),
        confirmText: $r('app.string.common_delete'),
        onConfirm: (): void => {
          dialog.close();
          this.deleteChapters(group.chapters);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private confirmDeleteSelected(): void {
    const chapters: DownloadedChapter[] = [];
    for (const group of this.downloaded) {
      for (const ch of group.chapters) {
        if (this.selectedIds.has(ch.chapterId)) {
          chapters.push(ch);
        }
      }
    }
    if (chapters.length === 0) {
      return;
    }
    const dialog: CustomDialogController = new CustomDialogController({
      builder: ConfirmDialog({
        title: $r('app.string.common_delete'),
        message: $r('app.string.download_delete_selected_confirm', chapters.length),
        confirmText: $r('app.string.common_delete'),
        onConfirm: (): void => {
          dialog.close();
          this.deleteChapters(chapters);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  // 批量删除：完成后退出多选、刷新列表并按数量提示
  private deleteChapters(chapters: DownloadedChapter[]): void {
    const n: number = chapters.length;
    this.deleteChaptersAsync(chapters).then(() => {
      this.exitSelection();
      this.loadDownloaded();
      Util.toastRes(this.getUIContext(), $r('app.string.detail_deleted_n', n));
    });
  }

  private async deleteChaptersAsync(chapters: DownloadedChapter[]): Promise<void> {
    for (const ch of chapters) {
      await DownloadService.deleteChapter(ch.mangaId, ch.chapterId);
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function DownloadsBuilder() {
  DownloadPage()
}
