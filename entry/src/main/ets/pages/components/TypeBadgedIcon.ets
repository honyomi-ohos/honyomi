import { ThemePalette } from '../../common/Theme';
import { ContentType } from '../../model/Models';

// 图标 + 内容类型角标，尺寸与单类型圆标一致。
// 单类型：纯色圆标（漫 / 文 / 动）。
// 多类型：扫描渐变把圆均分成扇区（蓝漫 / 绿文 / 橙动），中间一个「多」。
// contentTypes 优先；未传时回退 contentType。两者都空时不显示角标。
@Component
export struct TypeBadgedIcon {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop iconPath: string = '';
  @Prop fallbackChar: string = '?';
  @Prop iconSize: number = 40;
  @Prop cornerRadius: number = 10;
  // manga | novel | video；空字符串不显示角标（contentTypes 为空时才使用）
  @Prop contentType: string = '';
  // 插件声明的全部内容类型。两项及以上时画成类型饼图。
  @Prop contentTypes: string[] = [];
  // 角标描边色：传所在行背景色使角标与背景自然衔接（默认 '' 无描边）
  @Prop badgeBorder: ResourceColor = '';

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
          .fontColor(this.pal.onPrimary)
          .textAlign(TextAlign.Center)
          .width(this.iconSize)
          .height(this.iconSize)
          .borderRadius(this.cornerRadius)
          .backgroundColor(this.pal.primary)
      }
      if (this.shownTypes().length === 1) {
        Text(this.badgeChar(this.shownTypes()[0]))
          .fontSize(this.badgeFontSize())
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .width(this.badgeSize())
          .height(this.badgeSize())
          .borderRadius(this.badgeSize() / 2)
          .backgroundColor(this.badgeColor(this.shownTypes()[0]))
          .border({
            width: this.badgeBorderWidth(),
            color: this.badgeBorder !== '' ? this.badgeBorder : Color.Transparent,
          })
      } else if (this.shownTypes().length > 1) {
        this.multiBadge()
      }
    }
    .width(this.iconSize)
    .height(this.iconSize)
  }

  // 扫描渐变绕圆心分扇区。径向渐变是从圆心向外变色，做不出饼图。
  // 色标写在组件上，并从 12 点起算；相邻色标错开一丁点，交界才是硬边。
  @Builder
  multiBadge() {
    if (this.shownTypes().length === 2) {
      Stack({ alignContent: Alignment.Center }) {
        Text($r('app.string.badge_type_multi'))
          .fontSize(this.badgeFontSize())
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .textShadow({
            radius: 2,
            color: 'rgba(0,0,0,0.85)',
            offsetX: 0,
            offsetY: 0,
          })
      }
      .width(this.badgeSize())
      .height(this.badgeSize())
      .sweepGradient({
        center: ['50%', '50%'],
        start: 0,
        end: 360,
        rotation: 270,
        colors: [
          [this.badgeColor(this.shownTypes()[0]), 0],
          [this.badgeColor(this.shownTypes()[0]), 0.499],
          [this.badgeColor(this.shownTypes()[1]), 0.501],
          [this.badgeColor(this.shownTypes()[1]), 1]
        ]
      })
      .borderRadius(this.badgeSize() / 2)
      .border({
        width: this.badgeBorderWidth(),
        color: this.badgeBorder !== '' ? this.badgeBorder : Color.Transparent,
      })
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Text($r('app.string.badge_type_multi'))
          .fontSize(this.badgeFontSize())
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .textShadow({
            radius: 2,
            color: 'rgba(0,0,0,0.85)',
            offsetX: 0,
            offsetY: 0,
          })
      }
      .width(this.badgeSize())
      .height(this.badgeSize())
      .sweepGradient({
        center: ['50%', '50%'],
        start: 0,
        end: 360,
        rotation: 270,
        colors: [
          [this.badgeColor(this.shownTypes()[0]), 0],
          [this.badgeColor(this.shownTypes()[0]), 0.332],
          [this.badgeColor(this.shownTypes()[1]), 0.334],
          [this.badgeColor(this.shownTypes()[1]), 0.665],
          [this.badgeColor(this.shownTypes()[2]), 0.667],
          [this.badgeColor(this.shownTypes()[2]), 1]
        ]
      })
      .borderRadius(this.badgeSize() / 2)
      .border({
        width: this.badgeBorderWidth(),
        color: this.badgeBorder !== '' ? this.badgeBorder : Color.Transparent,
      })
    }
  }

  // contentTypes 优先，保持声明顺序；否则回退单值 contentType。
  private shownTypes(): string[] {
    const raw: string[] = this.contentTypes.length > 0 ? this.contentTypes :
      (this.contentType !== '' ? [this.contentType] : []);
    const out: string[] = [];
    for (let i = 0; i < raw.length; i++) {
      const t = raw[i];
      if (t !== '' && out.indexOf(t) < 0) {
        out.push(t);
      }
    }
    return out;
  }

  private badgeChar(t: string): Resource {
    if (t === ContentType.NOVEL) {
      return $r('app.string.badge_type_text');
    }
    if (t === ContentType.VIDEO) {
      return $r('app.string.badge_type_video');
    }
    return $r('app.string.badge_type_manga');
  }

  private badgeColor(t: string): string {
    if (t === ContentType.NOVEL) {
      return '#2E7D32';
    }
    if (t === ContentType.VIDEO) {
      return '#E65100';
    }
    return '#3949AB';
  }

  private badgeSize(): number {
    return Math.max(14, Math.round(this.iconSize * 0.42));
  }

  private badgeFontSize(): number {
    const scaled = Math.round(this.badgeSize() * 0.6);
    if (scaled > 9) {
      return scaled;
    }
    return 9;
  }

  private badgeBorderWidth(): number {
    if (this.badgeBorder === '') {
      return 0;
    }
    return 1.5;
  }
}
