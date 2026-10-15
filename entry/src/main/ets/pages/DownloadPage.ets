import { DownloadService } from '../data/DownloadService';
import { DownloadTask, DownloadedManga, DownloadedChapter } from '../model/Models';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { EmptyScreen } from './components/EmptyScreen';
import { AppIcon } from './components/AppIcon';
import { LimitedBody } from './components/LimitedBody';

// 队列行子组件：ForEach key 固定为章节 id 后同 key 行会被复用而不重跑生成器，
// 进度/状态改由本组件自订阅 DownloadService 通知刷新（DownloadTask 非 @Observed）
@Component
struct QueueTaskRow {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  task: DownloadTask = new DownloadTask();
  @State state: number = 0;
  @State progress: number = 0;
  @State total: number = 0;
  @State error: string = '';

  private onQueueChanged = (): void => {
    this.refreshState();
  }

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

  private stateLabel(state: number): Resource {
    switch (state) {
      case 0:
        return $r('app.string.download_state_queued');
      case 1:
        return $r('app.string.download_state_downloading');
      case 2:
        return $r('app.string.download_state_done');
      default:
        return $r('app.string.download_state_failed');
    }
  }

  build() {
    Row({ space: 12 }) {
      Column() {
        Text(this.task.chapterName)
          .fontSize(14)
          .fontColor(this.pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.task.mangaTitle)
          .fontSize(11)
          .fontColor(this.pal.sub)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
        if (this.total > 0) {
          Progress({ value: this.progress, total: this.total, type: ProgressType.Linear })
            .color(this.pal.primary)
            .margin({ top: 6 })
        }
        if (this.state === 3 && this.error !== '') {
          Text(Util.errText(this.getUIContext(), this.error))
            .fontSize(11)
            .fontColor('#E05252')
            .maxLines(1)
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.stateLabel(this.state))
        .fontSize(11)
        .fontColor(this.state === 2 ? this.pal.primary :
          (this.state === 3 ? '#E05252' : this.pal.sub))
      if (this.state === 0) {
        Row({ space: 2 }) {
          Text($r('app.string.download_move_top'))
            .fontSize(12)
            .fontColor(this.pal.primary)
            .padding({ left: 6 })
            .onClick(() => {
              DownloadService.moveToTop(this.task.chapterId);
            })
          Text($r('app.string.download_move_bottom'))
            .fontSize(12)
            .fontColor(this.pal.primary)
            .padding({ left: 6 })
            .onClick(() => {
              DownloadService.moveToBottom(this.task.chapterId);
            })
          Text($r('app.string.common_cancel'))
            .fontSize(12)
            .fontColor('#E05252')
            .padding({ left: 6 })
            .onClick(() => {
              DownloadService.cancel(this.task.chapterId);
            })
        }
      } else if (this.state === 3) {
        Row({ space: 2 }) {
          Text($r('app.string.common_retry'))
            .fontSize(12)
            .fontColor(this.pal.primary)
            .padding({ left: 6 })
            .onClick(() => {
              DownloadService.retry(this.task.chapterId);
            })
          Text($r('app.string.common_cancel'))
            .fontSize(12)
            .fontColor('#E05252')
            .padding({ left: 6 })
            .onClick(() => {
              DownloadService.cancel(this.task.chapterId);
            })
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }
}

// 下载管理页：下载队列 + 已下载章节
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

  private onQueueChanged = (): void => {
    this.queue = DownloadService.getQueue().slice();
    this.paused = DownloadService.isPaused();
    this.loadDownloaded();
  }

  aboutToAppear(): void {
    DownloadService.addListener(this.onQueueChanged);
    this.queue = DownloadService.getQueue().slice();
    this.paused = DownloadService.isPaused();
    this.loadDownloaded();
  }

  aboutToDisappear(): void {
    DownloadService.removeListener(this.onQueueChanged);
  }

  private async loadDownloaded(): Promise<void> {
    this.downloaded = await DownloadService.listDownloaded();
    this.loading = false;
  }

  private deleteChapter(item: DownloadedChapter): void {
    DownloadService.deleteChapter(item.mangaId, item.chapterId);
    Util.toastRes(this.getUIContext(), $r('app.string.download_deleted'));
  }

  build() {
    NavDestination() {
      LimitedBody() {
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
        // 头部
        Row() {
          AppIcon({ name: 'arrow_back', iconSize: 24 })
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.pathStack.pop();
            })
          Text($r('app.string.download_title'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .layoutWeight(1)
          if (this.queue.length > 0) {
            Text(this.paused ? $r('app.string.download_resume') : $r('app.string.download_pause'))
              .fontSize(13)
              .fontColor(this.pal.primary)
              .padding(6)
              .onClick(() => {
                if (this.paused) {
                  DownloadService.resumeAll();
                } else {
                  DownloadService.pauseAll();
                }
              })
            Text($r('app.string.download_clear_finished'))
              .fontSize(13)
              .fontColor(this.pal.primary)
              .padding(6)
              .margin({ left: 4 })
              .onClick(() => {
                DownloadService.clearFinished();
              })
          }
        }
        .width('100%')
        .padding({ left: 4, right: 16, top: this.statusBarH + 8, bottom: 8 })

        Column() {
          List({ space: 0 }) {
          // 下载队列
          if (this.queue.length > 0) {
            ListItem() {
              Text($r('app.string.download_queue'))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal.sub)
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 6 })
            }
            ForEach(this.queue, (task: DownloadTask) => {
              ListItem() {
                QueueTaskRow({ task: task })
              }
            }, (task: DownloadTask) => `q-${task.chapterId}`)
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
                    Row() {
                      Text(item.chapterName)
                        .fontSize(14)
                        .fontColor(this.pal.text)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      Text($r('app.string.download_status_downloaded'))
                        .fontSize(11)
                        .fontColor(this.pal.primary)
                        .margin({ right: 8 })
                      Text($r('app.string.common_delete'))
                        .fontSize(12)
                        .fontColor('#E05252')
                        .onClick(() => {
                          this.deleteChapter(item);
                        })
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                  }
                }, (item: DownloadedChapter) => `d-${item.chapterId}`)
              }
            }, (group: DownloadedManga) => `g-${group.mangaId}-${group.chapters.length}`)
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .divider({
          strokeWidth: 1,
          color: this.pal.divider,
          startMargin: 16,
          endMargin: 16,
        })
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
    .padding({ left: 16, right: 16, top: 14, bottom: 8 })
    .backgroundColor(this.pal.bg)
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function DownloadsBuilder() {
  DownloadPage()
}
