import { ChapterRecord } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';
import { AppIcon } from './AppIcon';

// 阅读器章节目录抽屉（参考华为阅读）：bindSheet 内容，
// 当前章节高亮 + 已读打勾 + 打开时自动滚动定位到当前章节。
// 漫画 / 小说阅读器共用；视频播放器沿用其剧集面板。
@Component
export struct ReaderChapterSheet {
  @Prop chapters: ChapterRecord[] = [];
  @Prop currentId: number = -1;
  @Prop pal: ThemePalette = new ThemePalette();
  private listScroller: Scroller = new Scroller();

  onPick: (id: number) => void = (id: number): void => {
  };

  build() {
    List({ scroller: this.listScroller }) {
      ForEach(this.chapters, (c: ChapterRecord) => {
        ListItem() {
          Row() {
            Text(c.name)
              .fontSize(15)
              .fontColor(c.id === this.currentId ? this.pal.primary :
                (c.read ? this.pal.sub : this.pal.text))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (c.id === this.currentId) {
              AppIcon({ name: 'play_arrow', iconSize: 18, tint: this.pal.primary })
            } else if (c.read) {
              AppIcon({ name: 'done', iconSize: 18, tint: this.pal.sub })
            }
          }
          .width('100%')
          .height(48)
          .padding({ left: 8, right: 4 })
          .onClick(() => {
            this.onPick(c.id);
          })
        }
      }, (c: ChapterRecord) => `toc-${c.id}-${c.read ? 'r' : 'u'}`)
    }
    .width('100%')
    .height('100%')
    .onAppear(() => {
      const idx = this.currentIndex();
      if (idx > 2) {
        this.listScroller.scrollToIndex(idx - 2, false, ScrollAlign.START);
      }
    })
  }

  private currentIndex(): number {
    for (let i = 0; i < this.chapters.length; i++) {
      if (this.chapters[i].id === this.currentId) {
        return i;
      }
    }
    return -1;
  }
}
