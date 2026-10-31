import { CategoryRecord, MangaRecord } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { SmartImage } from './SmartImage';

// 漫画封面卡片（书架/浏览通用）
// mode：'comfortable' 标题在封面下方（默认）| 'compact' 渐变标题覆盖封面（对齐 Mihon MangaCompactGridItem）
@Component
export struct MangaCard {
  @ObjectLink record: MangaRecord;
  @Prop badge: string = '';
  @Prop mode: string = 'comfortable';
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State hovered: boolean = false;
  onCardClick: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };
  onCardLongPress: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };
  // PC 右键菜单「加入书架」：与长按快速入库同一逻辑
  onCardMenuAddToLibrary: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };

  // PC 鼠标右键菜单（移动端仍走长按手势，右键不响应触摸）
  @Builder
  cardContextMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.detail_add_to_library') })
        .onClick(() => {
          this.onCardMenuAddToLibrary(this.record);
        })
    }
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Stack({ alignContent: Alignment.BottomStart }) {
          // 封面（无封面时 SmartImage 内部渲染默认封面占位）
          Stack() {
            SmartImage({
              url: this.record.thumbnailUrl,
              sourceKey: this.record.sourceKey,
              fit: ImageFit.Cover,
              fill: true
            })
          }
          .width('100%')
          .aspectRatio(0.7)
          .borderRadius(8)
          .clip(true)
          .backgroundColor(this.pal.chip)

          // 紧凑模式：渐变遮罩 + 白色标题压在封面底部（无下方标题）
          if (this.mode === 'compact') {
            Column() {
              Blank()
              Text(this.record.title)
                .fontSize(12)
                .fontColor('#FFFFFF')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({
                  left: 8,
                  right: 8,
                  top: 20,
                  bottom: 8
                })
            }
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 180,
              colors: [['rgba(0,0,0,0)', 0.55], ['rgba(0,0,0,0.6)', 1]]
            })
          }
        }
        .width('100%')
        .aspectRatio(0.7)
        .borderRadius(8)
        .clip(true)

        if (this.badge !== '') {
          Text(this.badge)
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor('#E05252')
            .borderRadius(9)
            .padding({
              left: 6,
              right: 6,
              top: 2,
              bottom: 2
            })
            .margin(4)
        }
      }

      if (this.mode !== 'compact') {
        Text(this.record.title)
          .fontSize(12)
          .fontColor(this.pal.text)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
      }
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
    .bindContextMenu(this.cardContextMenu, ResponseType.RightClick)
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
  onChipClick: (category: CategoryRecord) => void = (_c: CategoryRecord) => {
  };

  build() {
    Text(Util.categoryLabel(this.category.name))
      .fontSize(13)
      .fontColor(this.selected ? this.pal.onPrimary : this.pal.text)
      .backgroundColor(this.selected ? this.pal.primary : this.pal.chip)
      .borderRadius(14)
      .padding({
        left: 14,
        right: 14,
        top: 6,
        bottom: 6
      })
      .onClick(() => {
        this.onChipClick(this.category);
      })
  }
}
