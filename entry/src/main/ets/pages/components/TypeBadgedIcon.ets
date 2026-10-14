import { ThemePalette } from '../../common/Theme';
import { ContentType } from '../../model/Models';

// 图标 + 内容类型角标：图标右下角叠加小圆标，标识源/插件为漫画（漫）/小说（文）/动漫（动）
// contentType 为空字符串时不显示角标（如仓库索引未声明 contentType 的条目）
@Component
export struct TypeBadgedIcon {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop iconPath: string = '';
  @Prop fallbackChar: string = '?';
  @Prop iconSize: number = 40;
  @Prop cornerRadius: number = 10;
  // manga | novel | video；空字符串不显示角标
  @Prop contentType: string = '';
  // 角标描边色：传所在行背景色使角标与背景自然衔接（默认 '' 无描边）
  @Prop badgeBorder: ResourceColor = '';

  private badgeChar(): string {
    if (this.contentType === ContentType.NOVEL) {
      return '文';
    }
    if (this.contentType === ContentType.VIDEO) {
      return '动';
    }
    return '漫';
  }

  private badgeColor(): string {
    if (this.contentType === ContentType.NOVEL) {
      return '#2E7D32';
    }
    if (this.contentType === ContentType.VIDEO) {
      return '#E65100';
    }
    return '#3949AB';
  }

  private badgeSize(): number {
    return Math.max(14, Math.round(this.iconSize * 0.42));
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (this.iconPath !== '') {
        Image(this.iconPath)
          .width(this.iconSize)
          .height(this.iconSize)
          .borderRadius(this.cornerRadius)
          .objectFit(ImageFit.Cover)
          .clip(true)
      } else {
        Text(this.fallbackChar)
          .fontSize(Math.max(12, Math.round(this.iconSize * 0.42)))
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .width(this.iconSize)
          .height(this.iconSize)
          .borderRadius(this.cornerRadius)
          .backgroundColor(this.pal.primary)
      }
      if (this.contentType !== '') {
        Text(this.badgeChar())
          .fontSize(Math.max(9, Math.round(this.badgeSize() * 0.6)))
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .width(this.badgeSize())
          .height(this.badgeSize())
          .borderRadius(this.badgeSize() / 2)
          .backgroundColor(this.badgeColor())
          .border({
            width: this.badgeBorder !== '' ? 1.5 : 0,
            color: this.badgeBorder !== '' ? this.badgeBorder : Color.Transparent,
          })
      }
    }
    .width(this.iconSize)
    .height(this.iconSize)
  }
}
