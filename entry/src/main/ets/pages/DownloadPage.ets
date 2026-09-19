import { DownloadService } from '../data/DownloadService';
import { DownloadTask, DownloadedManga, DownloadedChapter } from '../model/Models';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';

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

  private stateLabel(state: number): string {
    switch (state) {
      case 0:
        return '队列中';
      case 1:
        return '下载中';
      case 2:
        return '已完成';
      default:
        return '失败';
    }
  }

  private deleteChapter(item: DownloadedChapter): void {
    DownloadService.deleteChapter(item.mangaId, item.chapterId);
    Util.toast(this.getUIContext(), '已删除下载');
  }

  build() {
    NavDestination() {
      Column() {
        // 头部
        Row() {
          Text('‹')
            .fontSize(30)
            .fontColor(this.pal.text)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.pathStack.pop();
            })
          Text('下载管理')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .layoutWeight(1)
          if (this.queue.length > 0) {
            Text(this.paused ? '继续' : '暂停')
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
            Text('清除记录')
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

        List({ space: 0 }) {
          // 下载队列
          if (this.queue.length > 0) {
            ListItem() {
              Text('下载队列')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal.sub)
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 6 })
            }
            ForEach(this.queue, (task: DownloadTask) => {
              ListItem() {
                Row({ space: 12 }) {
                  Column() {
                    Text(task.chapterName)
                      .fontSize(14)
                      .fontColor(this.pal.text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(task.mangaTitle)
                      .fontSize(11)
                      .fontColor(this.pal.sub)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                    if (task.total > 0) {
                      Progress({ value: task.progress, total: task.total, type: ProgressType.Linear })
                        .color(this.pal.primary)
                        .margin({ top: 6 })
                    }
                    if (task.state === 3 && task.error !== '') {
                      Text(task.error)
                        .fontSize(11)
                        .fontColor('#E05252')
                        .maxLines(1)
                        .margin({ top: 2 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text(this.stateLabel(task.state))
                    .fontSize(11)
                    .fontColor(task.state === 2 ? this.pal.primary :
                      (task.state === 3 ? '#E05252' : this.pal.sub))
                  if (task.state === 0) {
                    Row({ space: 2 }) {
                      Text('置顶')
                        .fontSize(12)
                        .fontColor(this.pal.primary)
                        .padding({ left: 6 })
                        .onClick(() => {
                          DownloadService.moveToTop(task.chapterId);
                        })
                      Text('移底')
                        .fontSize(12)
                        .fontColor(this.pal.primary)
                        .padding({ left: 6 })
                        .onClick(() => {
                          DownloadService.moveToBottom(task.chapterId);
                        })
                      Text('取消')
                        .fontSize(12)
                        .fontColor('#E05252')
                        .padding({ left: 6 })
                        .onClick(() => {
                          DownloadService.cancel(task.chapterId);
                        })
                    }
                  } else if (task.state === 3) {
                    Row({ space: 2 }) {
                      Text('重试')
                        .fontSize(12)
                        .fontColor(this.pal.primary)
                        .padding({ left: 6 })
                        .onClick(() => {
                          DownloadService.retry(task.chapterId);
                        })
                      Text('取消')
                        .fontSize(12)
                        .fontColor('#E05252')
                        .padding({ left: 6 })
                        .onClick(() => {
                          DownloadService.cancel(task.chapterId);
                        })
                    }
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              }
            }, (task: DownloadTask) => `q-${task.chapterId}-${task.state}-${task.progress}`)
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
                Text('⬇️').fontSize(28)
                Text('暂无下载内容')
                  .fontSize(13)
                  .fontColor(this.pal.sub)
                  .margin({ top: 8 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 80, bottom: 80 })
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
                      Text('已下载')
                        .fontSize(11)
                        .fontColor(this.pal.primary)
                        .margin({ right: 8 })
                      Text('删除')
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
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }

  @Builder
  groupHeader(group: DownloadedManga) {
    Row({ space: 8 }) {
      Text('📖').fontSize(14)
      Text(group.mangaTitle)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(`${group.chapters.length} 话`)
        .fontSize(11)
        .fontColor(this.pal.sub)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 8 })
    .backgroundColor(this.pal.bg)
  }
}
