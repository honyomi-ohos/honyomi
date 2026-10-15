import { DownloadService } from '../data/DownloadService';
import { DownloadedChapter, DownloadedManga, DownloadTask } from '../model/Models';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { EmptyScreen } from './components/EmptyScreen';
import { AppIcon } from './components/AppIcon';
import { LimitedBody } from './components/LimitedBody';

// 队列行子组件：ForEach key 固定为章节 id 后同 key 行会被复用而不重跑生成器，
// 进度/状态改由本组件自订阅 DownloadService 通知刷新（DownloadTask 非 @Observed）
// 行布局对齐 Mihon download_item.xml：拖拽把手 | 漫画标题+页数文本 | 章节标题 | 细进度条 | 溢出菜单
@Component
struct QueueTaskRow {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  task: DownloadTask = new DownloadTask();
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

  // 行溢出菜单（对齐 Mihon download_single.xml：置顶/移底/重试/取消）
  @Builder
  rowMenuBuilder() {
    Menu() {
      if (this.state === 0) {
        MenuItem({ content: $r('app.string.download_move_top') })
          .onClick(() => {
            DownloadService.moveToTop(this.task.chapterId);
          })
        MenuItem({ content: $r('app.string.download_move_bottom') })
          .onClick(() => {
            DownloadService.moveToBottom(this.task.chapterId);
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
    }
  }

  build() {
    Row() {
      AppIcon({ name: 'drag_handle', iconSize: 20, tint: this.pal.sub })
        .margin({ right: 8 })
      Column() {
        Row() {
          Text(this.task.mangaTitle)
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

        Text(this.task.chapterName)
          .fontSize(12)
          .fontColor(this.pal.sub)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 1 })
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
      left: 12,
      right: 12,
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

// 下载管理页：下载队列 + 已下载章节（交互对齐 Mihon DownloadQueueScreen：
// 标题数量 Pill 徽标、排序/溢出菜单、拖拽排序、右下角暂停/继续 FAB）
@Component
export struct DownloadPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @State queue: DownloadTask[] = [];
  @State downloaded: DownloadedManga[] = [];
  @State loading: boolean = true;
  @State paused: boolean = false;
  @State fabExpanded: boolean = true;

  aboutToAppear(): void {
    DownloadService.addListener(this.onQueueChanged);
    this.queue = DownloadService.getQueue().slice();
    this.paused = DownloadService.isPaused();
    this.loadDownloaded();
  }

  aboutToDisappear(): void {
    DownloadService.removeListener(this.onQueueChanged);
  }

  // 排序菜单（对齐 Mihon "Order by chapter number" 的升/降序）
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

  build() {
    NavDestination() {
      LimitedBody({ maxWidth: 960 }) {
        this.bodyContent()
      }
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }

  // 页面主体：LimitedBody 承载，大屏限宽居中，窄屏全宽
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

        if (this.queue.length > 0) {
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
        left: 4,
        right: 8,
        top: this.statusBarH + 8,
        bottom: 8
      })

      Stack({ alignContent: Alignment.BottomEnd }) {
        List({ space: 0 }) {
          // 下载队列
          if (this.queue.length > 0) {
            ListItem() {
              Text($r('app.string.download_queue'))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal.sub)
                .width('100%')
                .padding({
                  left: 16,
                  right: 16,
                  top: 10,
                  bottom: 6
                })
            }

            ForEach(this.queue, (task: DownloadTask) => {
              ListItem() {
                QueueTaskRow({ task: task })
              }
            }, (task: DownloadTask) => `q-${task.chapterId}`)
              .onMove((from: number, to: number) => {
                // 拖拽排序：同步页面数据源并落库到 DownloadService（对齐 Mihon 拖拽重排）
                const removed: DownloadTask[] = this.queue.splice(from, 1);
                const moved: DownloadTask | undefined = removed[0];
                if (moved !== undefined) {
                  this.queue.splice(to, 0, moved);
                  const ids: number[] = [];
                  for (const t of this.queue) {
                    ids.push(t.chapterId);
                  }
                  DownloadService.reorderQueue(ids);
                }
              })
          }

          // 已下载
          if (this.loading) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(this.pal.primary)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 40, bottom: 40 })
            }
          } else if (this.downloaded.length === 0 && this.queue.length === 0) {
            ListItem() {
              Column() {
                EmptyScreen({ message: $r('app.string.download_empty'), compact: true })
              }
              .width('100%')
              .padding({ top: 48, bottom: 48 })
            }
          } else {
            ForEach(this.downloaded, (group: DownloadedManga) => {
              ListItemGroup({ header: this.groupHeader(group) }) {
                ForEach(group.chapters, (item: DownloadedChapter) => {
                  ListItem() {
                    Row({ space: 8 }) {
                      Text(item.chapterName)
                        .fontSize(14)
                        .fontColor(this.pal.text)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      AppIcon({ name: 'delete', iconSize: 20, tint: this.pal.sub })
                        .padding(6)
                        .onClick(() => {
                          this.deleteChapter(item);
                        })
                    }
                    .width('100%')
                    .padding({
                      left: 16,
                      right: 6,
                      top: 6,
                      bottom: 6
                    })
                  }
                }, (item: DownloadedChapter) => `d-${item.chapterId}`)
              }
            }, (group: DownloadedManga) => `g-${group.mangaId}-${group.chapters.length}`)
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Auto)
        .divider({
          strokeWidth: 1,
          color: this.pal.divider,
          startMargin: 16,
          endMargin: 16,
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
          .margin({ right: 20, bottom: 28 })
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
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }

  @Builder
  groupHeader(group: DownloadedManga) {
    Row({ space: 8 }) {
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
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 14,
      bottom: 8
    })
    .backgroundColor(this.pal.bg)
  }

  private onQueueChanged = (): void => {
    this.queue = DownloadService.getQueue().slice();
    this.paused = DownloadService.isPaused();
    this.loadDownloaded();
  }

  private async loadDownloaded(): Promise<void> {
    this.downloaded = await DownloadService.listDownloaded();
    this.loading = false;
  }

  private deleteChapter(item: DownloadedChapter): void {
    DownloadService.deleteChapter(item.mangaId, item.chapterId);
    Util.toastRes(this.getUIContext(), $r('app.string.download_deleted'));
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function DownloadsBuilder() {
  DownloadPage()
}
