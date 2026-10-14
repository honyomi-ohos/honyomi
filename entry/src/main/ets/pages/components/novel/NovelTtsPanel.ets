// 小说阅读器「听书」设置面板：播放/暂停/继续 + 语速 + 播放器入口
// （从 NovelReaderPage 拆出，Wave 3I；播放控制经 TtsPlaybackService）
import { ThemePalette } from '../../../common/Theme';
import { AppIcon } from '../AppIcon';

@Component
export struct NovelTtsPanel {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // playing / paused / idle
  @Prop mode: string = 'idle';
  @Prop ttsSpeed: number = 1;
  onToggle: () => void = (): void => {};
  onSpeed: (v: number) => void = (v: number): void => {};
  onOpenPlayer: () => void = (): void => {};

  private toggleLabel(): ResourceStr {
    if (this.mode === 'playing') {
      return $r('app.string.novel_tts_pause');
    }
    if (this.mode === 'paused') {
      return $r('app.string.novel_tts_resume');
    }
    return $r('app.string.novel_tts_start');
  }

  build() {
    Column({ space: 0 }) {
      Button(this.toggleLabel())
        .fontSize(14)
        .fontColor('#FFFFFF')
        .type(ButtonType.Capsule)
        .backgroundColor(this.mode === 'idle' ? this.pal.primary : '#8A343434')
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

      // 听书播放器入口（后台续播、播控中心、定时停止）
      Row({ space: 10 }) {
        AppIcon({ name: 'playlist_play', iconSize: 20, tint: this.pal.primary })
        Text($r('app.string.tts_open_player'))
          .fontSize(14)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.onOpenPlayer();
      })

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
