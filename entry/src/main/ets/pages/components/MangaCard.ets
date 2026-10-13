import { MangaRecord, CategoryRecord } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';
import { SmartImage } from './SmartImage';
import { AppIcon } from './AppIcon';

// 漫画封面卡片（书架/浏览通用）
@Component
export struct MangaCard {
  @ObjectLink record: MangaRecord;
  @Prop badge: string = '';
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State hovered: boolean = false;
  onCardClick: (record: MangaRecord) => void = (_r: MangaRecord) => {};
  onCardLongPress: (record: MangaRecord) => void = (_r: MangaRecord) => {};

  build() {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        // 封面
        Stack() {
          if (this.record.thumbnailUrl === '') {
            Column() {
              AppIcon({ name: 'photo', iconSize: 28 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            SmartImage({ url: this.record.thumbnailUrl, sourceKey: this.record.sourceKey, fit: ImageFit.Cover, fill: true })
          }
        }
        .width('100%')
        .aspectRatio(0.7)
        .borderRadius(8)
        .clip(true)
        .backgroundColor(this.pal.chip)
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
        .fontColor(this.pal.text)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .scale({ x: this.hovered ? 1.02 : 1, y: this.hovered ? 1.02 : 1 })
    .onClick(() => {
      this.onCardClick(this.record);
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.onCardLongPress(this.record);
        })
    )
    .onHover((isHover: boolean) => {
      this.getUIContext().animateTo({ duration: 120, curve: Curve.Friction }, (): void => {
        this.hovered = isHover;
      });
    })
  }
}

// 分类选择弹窗用条目
@Component
export struct CategoryChip {
  @Prop category: CategoryRecord = new CategoryRecord();
  @Prop selected: boolean = false;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onChipClick: (category: CategoryRecord) => void = (_c: CategoryRecord) => {};

  build() {
    Text(this.category.name)
      .fontSize(13)
      .fontColor(this.selected ? '#FFFFFF' : this.pal.text)
      .backgroundColor(this.selected ? this.pal.primary : this.pal.chip)
      .borderRadius(14)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .onClick(() => {
        this.onChipClick(this.category);
      })
  }
}
