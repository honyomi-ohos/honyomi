// 小说阅读位置书签面板：顶部「添加当前进度」+ 书签列表（章名 / 进度百分比 / 时间），点击跳转，可删除
import { ThemePalette } from '../../../common/Theme';
import { NovelBookmark } from '../../../common/NovelBookmarks';
import { Util } from '../../../common/Util';
import { AppIcon } from '../AppIcon';

@Component
export struct NovelBookmarkSheet {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop bookmarks: NovelBookmark[] = [];
  // 当前章节 id（用于列表中标记当前章的书签）
  @Prop currentChapterId: number = -1;
  onAdd: () => void = (): void => {
  };
  onJump: (bm: NovelBookmark) => void = (bm: NovelBookmark): void => {
  };
  onDelete: (bm: NovelBookmark) => void = (bm: NovelBookmark): void => {
  };

  build() {
    Column() {
      // 添加当前进度
      Row({ space: 8 }) {
        AppIcon({ name: 'add', iconSize: 20, tint: this.pal.primary })
        Text($r('app.string.novel_bookmark_add'))
          .fontSize(14)
          .fontColor(this.pal.primary)
          .layoutWeight(1)
      }
      .width('100%')
      .height(44)
      .padding({ left: 14, right: 14 })
      .borderRadius(22)
      .backgroundColor(this.pal.chip)
      .onClick(() => {
        this.onAdd();
      })

      if (this.bookmarks.length === 0) {
        Column() {
          Text($r('app.string.novel_bookmark_empty'))
            .fontSize(13)
            .fontColor(this.pal.sub)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ initialIndex: 0 }) {
          ForEach(this.bookmarks, (bm: NovelBookmark) => {
            ListItem() {
              Row() {
                Row({ space: 10 }) {
                  AppIcon({
                    name: bm.chapterId === this.currentChapterId ? 'bookmark_filled' : 'bookmark',
                    iconSize: 18,
                    tint: bm.chapterId === this.currentChapterId ? this.pal.primary : this.pal.sub
                  })
                  Column({ space: 2 }) {
                    Text(bm.chapterName)
                      .fontSize(13)
                      .fontColor(this.pal.text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${Math.round(bm.permille / 10)}% · ${Util.timeAgo(bm.time)}`)
                      .fontSize(11)
                      .fontColor(this.pal.sub)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .layoutWeight(1)
                .onClick(() => {
                  this.onJump(bm);
                })

                AppIcon({ name: 'delete', iconSize: 18, tint: this.pal.sub })
                  .padding({ left: 8, top: 8, bottom: 8, right: 2 })
                  .onClick(() => {
                    this.onDelete(bm);
                  })
              }
              .width('100%')
            }
          }, (bm: NovelBookmark) => `${bm.time}#${bm.chapterId}#${bm.permille}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .divider({ strokeWidth: 0.5, color: this.pal.divider, startMargin: 4, endMargin: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }
}
