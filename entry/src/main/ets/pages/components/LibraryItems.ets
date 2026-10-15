import { fileIo as fs } from '@kit.CoreFileKit';
import { MangaRecord } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';
import { SmartImage } from './SmartImage';
import { AppIcon } from './AppIcon';
import { CoverPlaceholder } from './CoverPlaceholder';

// Mihon 式徽标：文字或图标 + 背景色，矩形无圆角（外层 BadgeGroup 统一裁切）
@Component
export struct LibBadge {
  @Prop text: string = '';
  @Prop icon: string = '';
  @Prop bgColor: ResourceColor = '';
  // 前景色：默认白色（固定绿底徽标），primary 底徽标需传主题 onPrimary 保证对比度
  @Prop fgColor: ResourceColor = '#FFFFFF';

  build() {
    if (this.icon !== '') {
      Column() {
        AppIcon({ name: this.icon, iconSize: 12, tint: this.fgColor })
      }
      .backgroundColor(this.bgColor)
      .padding({
        left: 4,
        right: 4,
        top: 2,
        bottom: 2
      })
      .justifyContent(FlexAlign.Center)
    } else {
      Text(this.text)
        .fontSize(11)
        .fontColor(this.fgColor)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .backgroundColor(this.bgColor)
        .padding({
          left: 4,
          right: 4,
          top: 1,
          bottom: 1
        })
    }
  }
}

// 书架条目：紧凑/松散/封面网格 + 列表四种显示模式（对齐 Mihon CommonMangaItem）
// record 用 @ObjectLink 引用共享（MangaRecord 为 @Observed 类），避免 @Prop 深拷贝
@Component
export struct LibraryMangaItem {
  @ObjectLink record: MangaRecord;
  @Prop mode: string = 'compact'; // 'compact' | 'comfortable' | 'cover' | 'list'
  @Prop unreadCount: number = 0;
  @Prop downloadCount: number = 0;
  @Prop langLabel: string = '';
  @Prop isLocal: boolean = false;
  @Prop showUnreadBadge: boolean = true;
  @Prop showDownloadBadge: boolean = true;
  @Prop showLocalBadge: boolean = false;
  @Prop showLanguageBadge: boolean = false;
  @Prop isSelected: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onItemClick: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };
  onItemLongPress: (record: MangaRecord) => void = (_r: MangaRecord) => {
  };

  // 封面展示地址：自定义封面优先（origThumbnail 非空，thumbnailUrl 即 file:// 自定义路径），

  @Builder
  startBadges() {
    Row() {
      if (this.showDownloadBadge && this.downloadCount > 0) {
        LibBadge({ text: `${this.downloadCount}`, bgColor: '#4E9B5E' })
      }
      if (this.showUnreadBadge && this.unreadCount > 0) {
        LibBadge({ text: `${this.unreadCount}`, bgColor: this.pal.primary, fgColor: this.pal.onPrimary })
      }
    }
    .borderRadius(4)
    .clip(true)
  }

  @Builder
  endBadges() {
    Row() {
      if (this.isLocal) {
        if (this.showLocalBadge) {
          LibBadge({ icon: 'folder', bgColor: '#4E9B5E' })
        }
      } else if (this.showLanguageBadge && this.langLabel !== '') {
        LibBadge({ text: this.langLabel, bgColor: this.pal.primary, fgColor: this.pal.onPrimary })
      }
    }
    .borderRadius(4)
    .clip(true)
  }

  build() {
    if (this.mode === 'list') {
      Row({ space: 12 }) {
        this.coverSquare()
        Column() {
          Text(this.record.title)
            .fontSize(14)
            .fontColor(this.pal.text)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.startBadges()
      }
      .width('100%')
      .height(56)
      .padding({
        left: 16,
        right: 16,
        top: 4,
        bottom: 4
      })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.isSelected ? this.pal.primarySoft : Color.Transparent)
      .onClick(() => {
        this.onItemClick(this.record);
      })
      .gesture(
        LongPressGesture()
          .onAction(() => {
            this.onItemLongPress(this.record);
          })
      )
    } else {
      Column() {
        Stack({ alignContent: Alignment.TopEnd }) {
          Stack({ alignContent: Alignment.BottomEnd }) {
            Stack({ alignContent: Alignment.Bottom }) {
              Stack({ alignContent: Alignment.TopStart }) {
                this.coverGrid()
                Row() {
                  this.startBadges()
                }
                .margin(4)
              }
              .width('100%')
              .height('100%')
              .backgroundColor(this.isSelected ? this.pal.primary : Color.Transparent)
              .borderRadius(4)

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
            .height('100%')
          }
          .width('100%')
          .height('100%')

          Row() {
            this.endBadges()
          }
          .margin(4)
        }
        .width('100%')
        .aspectRatio(2 / 3)

        if (this.mode === 'comfortable') {
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
      .onClick(() => {
        this.onItemClick(this.record);
      })
      .gesture(
        LongPressGesture()
          .onAction(() => {
            this.onItemLongPress(this.record);
          })
      )
    }
  }

  // 网格封面：2:3，4vp 圆角
  @Builder
  coverGrid() {
    Stack() {
      if (this.coverDisplay() === '') {
        CoverPlaceholder({ iconSize: 32 })
      } else {
        SmartImage({
          url: this.coverDisplay(),
          sourceKey: this.record.sourceKey,
          fit: ImageFit.Cover,
          fill: true
        })
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(4)
    .clip(true)
    .backgroundColor(this.pal.chip)
    .opacity(this.isSelected ? 0.76 : 1)
  }

  // 列表封面：48x48 方形，4vp 圆角，比条目高度（56）略矮
  @Builder
  coverSquare() {
    Stack() {
      if (this.coverDisplay() === '') {
        CoverPlaceholder({ iconSize: 22 })
      } else {
        SmartImage({
          url: this.coverDisplay(),
          sourceKey: this.record.sourceKey,
          fit: ImageFit.Cover,
          fill: true
        })
      }
    }
    .width(48)
    .height(48)
    .borderRadius(4)
    .clip(true)
    .backgroundColor(this.pal.chip)
  }

  // 其次书架持久化封面（入库时落盘的 JPEG，文件存在才用），最后回退在线地址
  private coverDisplay(): string {
    if (this.record.origThumbnail === '' && this.record.localCover !== '') {
      try {
        if (fs.accessSync(this.record.localCover)) {
          return `file://${this.record.localCover}`;
        }
      } catch (e) {
      }
    }
    return this.record.thumbnailUrl;
  }
}
