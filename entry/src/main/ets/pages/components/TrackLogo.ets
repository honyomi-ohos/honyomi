// 追踪器品牌徽标：无官方 logo 资源，以品牌色圆角底 + 名称首字母占位
import { ThemePalette } from '../../common/Theme';

@Component
export struct TrackLogo {
  @Prop logoName: string = '';
  @Prop color: string = '#888888';
  @Prop logoSize: number = 28;

  private initials(): string {
    const parts = this.logoName.split(' ');
    if (parts.length >= 2) {
      const a = parts[0].charAt(0);
      const b = parts[1].charAt(0);
      return `${a}${b}`.toUpperCase();
    }
    return this.logoName.substring(0, 2).toUpperCase();
  }

  build() {
    Text(this.initials())
      .fontSize(Math.max(9, Math.round(this.logoSize * 0.36)))
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .textAlign(TextAlign.Center)
      .width(this.logoSize)
      .height(this.logoSize)
      .borderRadius(Math.round(this.logoSize * 0.28))
      .backgroundColor(this.color)
  }
}
