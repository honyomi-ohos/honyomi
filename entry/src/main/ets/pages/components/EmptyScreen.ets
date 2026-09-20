import { ThemePalette } from '../../common/Theme';

// 空状态：随机字符表情 + 描述（参考 Mihon EmptyScreen）
const ERROR_FACES: string[] = [
  '(･o･;)',
  'Σ(ಠ_ಠ)',
  'ಥ_ಥ',
  '(˘･_･˘)',
  '(；￣Д￣)',
  '(･Д･。',
  '(╬ಠ益ಠ)',
  '(╥﹏╥)',
  '(⋟﹏⋞)',
  'Ò︵Ó',
  ' ˙ᯅ˙)',
  '(¬_¬)',
];

@Component
export struct EmptyScreen {
  @Prop message: string = '';
  @Prop compact: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State face: string = ERROR_FACES[0];

  aboutToAppear(): void {
    this.face = ERROR_FACES[Math.floor(Math.random() * ERROR_FACES.length)];
  }

  build() {
    Column() {
      Text(this.face)
        .fontSize(this.compact ? 22 : 40)
        .fontColor(this.pal.sub)
        .opacity(0.8)
      Text(this.message)
        .fontSize(this.compact ? 12 : 14)
        .fontColor(this.pal.sub)
        .textAlign(TextAlign.Center)
        .lineHeight(this.compact ? 18 : 22)
        .margin({ top: this.compact ? 6 : 16 })
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: this.compact ? 16 : 0, bottom: this.compact ? 16 : 0 })
  }
}
