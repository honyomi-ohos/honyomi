import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { UpdatesRepo } from '../data/Repos';
import { UpdateService } from '../data/UpdateService';
import { UpdateItem } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { EmptyScreen } from './components/EmptyScreen';

// 更新页：书架未读章节
@Component
export struct UpdatesPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;
  @State items: UpdateItem[] = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;

  aboutToAppear(): void {
    this.loadData();
  }

  onLibDirty(): void {
    this.loadData();
  }

  async loadData(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await AppDb.ready(context);
    this.items = await UpdatesRepo.unreadChapters(300);
    this.loading = false;
  }

  async refreshLibrary(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const newCount = await UpdateService.refreshLibrary(context);
      Util.toastRes(this.getUIContext(), newCount > 0 ? $r('app.string.updates_found_new', newCount) : $r('app.string.updates_no_new'));
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.updates_refresh_failed'));
    }
    this.refreshing = false;
    await this.loadData();
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.updates_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        Text(this.refreshing ? $r('app.string.updates_refreshing') : '⟳')
          .fontSize(this.refreshing ? 14 : 24)
          .fontColor(this.pal.primary)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.refreshLibrary();
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
          EmptyScreen({ message: $r('app.string.updates_empty') })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.items, (item: UpdateItem) => {
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
                  Text(Util.timeAgo(item.dateUpload))
                    .fontSize(11)
                    .fontColor(this.pal.sub)
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .onClick(() => {
                const params: ReaderParams = { mangaId: item.mangaId, chapterId: item.chapterId };
                this.pathStack.pushPathByName('Reader', params);
              })
            }
          }, (item: UpdateItem) => `upd-${item.chapterId}`)
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
