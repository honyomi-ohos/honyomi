// 小说阅读器「听书」设置面板：播放/停止 + 语速
// （从 NovelReaderPage 拆出，Wave 3I；行为与原 ttsSheetBuilder 一致）
import { ThemePalette } from '../../../common/Theme';

@Component
export struct NovelTtsPanel {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop ttsPlaying: boolean = false;
  @Prop ttsSpeed: number = 1;
  onToggle: () => void = (): void => {};
  onSpeed: (v: number) => void = (v: number): void => {};

  build() {
    Column({ space: 0 }) {
      Button(this.ttsPlaying ? $r('app.string.novel_tts_stop') : $r('app.string.novel_tts_start'))
        .fontSize(14)
        .fontColor('#FFFFFF')
        .type(ButtonType.Capsule)
        .backgroundColor(this.ttsPlaying ? '#8A343434' : this.pal.primary)
        .height(40)
        .padding({ left: 28, right: 28 })
        .margin({ top: 16 })
        .onClick(() => {
          this.onToggle();
        })

      Divider()
        .color(this.pal.divider)
        .margin({ top: 16 })

      Column({ space: 8 }) {
        Text($r('app.string.novel_tts_speed'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          this.ttsSpeedChip('0.5x', 0.5)
          this.ttsSpeedChip('0.75x', 0.75)
          this.ttsSpeedChip('1x', 1)
          this.ttsSpeedChip('1.25x', 1.25)
          this.ttsSpeedChip('1.5x', 1.5)
          this.ttsSpeedChip('2x', 2)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      Column().height(16)
    }
    .width('100%')
  }

  // 语速 chip（0.5x - 2x，播放中切换立即生效）
  @Builder
  ttsSpeedChip(label: string, value: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.ttsSpeed === value ? '#FFFFFF' : this.pal.text)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.ttsSpeed === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.onSpeed(value);
      })
  }
}
