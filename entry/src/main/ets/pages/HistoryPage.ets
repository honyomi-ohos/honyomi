import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { HistoryRepo } from '../data/Repos';
import { HistoryItem } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { EmptyScreen } from './components/EmptyScreen';

// 历史页：最近阅读记录
@Component
export struct HistoryPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;
  @State items: HistoryItem[] = [];
  @State loading: boolean = true;
  @State confirmClear: boolean = false;

  aboutToAppear(): void {
    this.loadData();
  }

  onLibDirty(): void {
    this.loadData();
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
    Util.toast(this.getUIContext(), '已清空历史');
  }

  build() {
    Column() {
      Row() {
        Text('历史')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        Text(this.confirmClear ? '确认清空？' : '清空')
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
          EmptyScreen({ message: '最近没有阅读' })
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
                    Text('📖').fontSize(20)
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
                Text('继续')
                  .fontSize(12)
                  .fontColor(this.pal.primary)
                  .backgroundColor(this.pal.chip)
                  .borderRadius(12)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .onClick(() => {
                const params: ReaderParams = { mangaId: item.mangaId, chapterId: item.chapterId };
                this.pathStack.pushPathByName('Reader', params);
              })
            }
          }, (item: HistoryItem) => `his-${item.chapterId}-${item.seenAt}`)
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
