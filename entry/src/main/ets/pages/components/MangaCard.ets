import { MangaRecord, CategoryRecord } from '../../model/Models';
import { Theme } from '../../common/Theme';

// 漫画封面卡片（书架/浏览通用）
@Component
export struct MangaCard {
  @Prop record: MangaRecord = new MangaRecord();
  @Prop badge: string = '';
  @StorageProp('isDark') isDark: boolean = false;
  onCardClick: (record: MangaRecord) => void = (_r: MangaRecord) => {};
  onCardLongPress: (record: MangaRecord) => void = (_r: MangaRecord) => {};

  build() {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.record.thumbnailUrl === '') {
          Column() {
            Text('📖').fontSize(28)
          }
          .width('100%')
          .aspectRatio(0.7)
          .backgroundColor(Theme.chip(this.isDark))
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
        } else {
          Image(this.record.thumbnailUrl)
            .width('100%')
            .aspectRatio(0.7)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .backgroundColor(Theme.chip(this.isDark))
        }
        if (this.badge !== '') {
          Text(this.badge)
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor('#E05252')
            .borderRadius(9)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .margin(4)
        }
      }

      Text(this.record.title)
        .fontSize(12)
        .fontColor(Theme.text(this.isDark))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onCardClick(this.record);
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.onCardLongPress(this.record);
        })
    )
  }
}

// 分类选择弹窗用条目
@Component
export struct CategoryChip {
  @Prop category: CategoryRecord = new CategoryRecord();
  @Prop selected: boolean = false;
  @StorageProp('isDark') isDark: boolean = false;
  onChipClick: (category: CategoryRecord) => void = (_c: CategoryRecord) => {};

  build() {
    Text(this.category.name)
      .fontSize(13)
      .fontColor(this.selected ? '#FFFFFF' : Theme.text(this.isDark))
      .backgroundColor(this.selected ? Theme.primary(this.isDark) : Theme.chip(this.isDark))
      .borderRadius(14)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .onClick(() => {
        this.onChipClick(this.category);
      })
  }
}
