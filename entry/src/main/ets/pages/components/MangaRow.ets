import { MangaRecord } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';
import { SmartImage } from './SmartImage';

// 漫画列表行：封面 + 标题（+ 副标题），可带尾部内容（迁移/全局搜索结果等）
@Component
export struct MangaRow {
  @ObjectLink record: MangaRecord;
  @Prop subtitle: string = '';
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State hovered: boolean = false;
  @BuilderParam trailing: () => void = this.emptyTrailing;
  onRowClick: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };
  // 长按快速入库（浏览源列表模式对齐 Mihon onMangaLongClick）
  onRowLongPress: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };

  @Builder
  emptyTrailing() {
  }

  build() {
    Row() {
      // 封面（无封面时 SmartImage 内部渲染默认封面占位）
      Stack() {
        SmartImage({
          url: this.record.thumbnailUrl,
          sourceKey: this.record.sourceKey,
          fit: ImageFit.Cover,
          fill: true,
          placeholderIconSize: 20
        })
      }
      .width(44)
      .height(62)
      .borderRadius(6)
      .clip(true)
      .backgroundColor(this.pal.chip)

      Column() {
        Text(this.record.title)
          .fontSize(14)
          .fontColor(this.pal.text)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(11)
            .fontColor(this.pal.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      this.trailing()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 6, bottom: 6 })
    .backgroundColor(this.hovered ? this.pal.chip : Color.Transparent)
    .onClick(() => {
      this.onRowClick(this.record);
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.onRowLongPress(this.record);
        })
    )
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
  }
}
