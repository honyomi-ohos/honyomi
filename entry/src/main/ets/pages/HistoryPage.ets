import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { HistoryRepo, ChapterRepo } from '../data/Repos';
import { HistoryItem } from '../model/Models';
import { ContentOpen } from './ContentOpen';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { EmptyScreen } from './components/EmptyScreen';
import { AppIcon } from './components/AppIcon';

// 历史页：最近阅读记录
@Component
export struct HistoryPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;
  // 复刻 Mihon：再次点击历史页签续读最近作品的下一未读章节（HistoryTab.onReselect）
  @StorageLink('historyReselect') @Watch('onHistoryReselect') historyReselect: number = 0;
  @State items: HistoryItem[] = [];
  @State loading: boolean = true;
  @State confirmClear: boolean = false;

  aboutToAppear(): void {
    this.loadData();
  }

  onLibDirty(): void {
    this.loadData();
  }

  private onHistoryReselect(): void {
    this.resumeLastRead();
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

  async loadData(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await AppDb.ready(context);
    this.items = await HistoryRepo.recent(100);
    this.loading = false;
  }

  async clearHistory(): Promise<void> {
    if (!this.confirmClear) {
      this.confirmClear = true;
      setTimeout(() => {
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
    Column() {
      Row() {
        Text($r('app.string.history_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        Text(this.confirmClear ? $r('app.string.history_confirm_clear') : $r('app.string.history_clear'))
          .fontSize(14)
          .fontColor(this.confirmClear ? '#E05252' : this.pal.sub)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.clearHistory();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

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
        List({ space: 0 }) {
          ForEach(this.items, (item: HistoryItem) => {
            ListItem() {
              Row({ space: 12 }) {
                if (item.coverUrl === '') {
                  Column() {
                    AppIcon({ name: 'photo', iconSize: 20 })
                  }
                  .width(44)
                  .height(60)
                  .borderRadius(6)
                  .backgroundColor(this.pal.chip)
                  .justifyContent(FlexAlign.Center)
                } else {
                  Image(item.coverUrl)
                    .width(44)
                    .height(60)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(6)
                    .backgroundColor(this.pal.chip)
                }
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
                  Text($r('app.string.history_continue'))
                    .fontSize(12)
                  .fontColor(this.pal.primary)
                  .backgroundColor(this.pal.chip)
                  .borderRadius(12)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .onClick(() => {
                ContentOpen.open(this.pathStack, item.mangaId, item.chapterId);
              })
            }
          }, (item: HistoryItem) => `his-${item.chapterId}-${item.seenAt}-${item.coverUrl}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .contentEndOffset(this.navBarH + 76)
        .divider({
          strokeWidth: 1,
          color: this.pal.divider,
          startMargin: 72,
          endMargin: 16,
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }
}
