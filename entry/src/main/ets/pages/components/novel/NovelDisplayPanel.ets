// 小说阅读器「画面」设置面板：亮度 / 配色 / 背景 / 屏幕常亮 / 音量键翻页
// （从 NovelReaderPage 拆出，Wave 3I；行为与原 displaySheetBuilder 一致）
import { ThemePalette } from '../../../common/Theme';
import { WideSlider } from '../WideSlider';

@Component
export struct NovelDisplayPanel {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop brightLv: number = 0;
  @Prop colorScheme: string = 'auto';
  @Prop readerTheme: number = 3;
  @Prop keepScreenOn: boolean = true;
  @Prop volumeTurn: boolean = false;
  onBrightness: (v: number) => void = (v: number): void => {
  };
  onColorScheme: (v: string) => void = (v: string): void => {
  };
  onTheme: (v: number) => void = (v: number): void => {
  };
  onKeepScreenOn: (v: boolean) => void = (v: boolean): void => {
  };
  onVolumeTurn: (v: boolean) => void = (v: boolean): void => {
  };

  build() {
    Column({ space: 0 }) {
      Column({ space: 8 }) {
        Text($r('app.string.reader_brightness'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Row() {
          WideSlider({
            sliderValue: this.brightLv,
            min: 0,
            max: 1,
            step: 0.05,
            onChange: (value: number, mode: SliderChangeMode): void => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.onBrightness(Math.round(value * 20) / 20);
              }
            }
          })
            .layoutWeight(1)
          Text(this.brightLv === 0 ? $r('app.string.reader_auto') : `${Math.round(this.brightLv * 100)}%`)
            .fontSize(13)
            .fontColor(this.pal.text)
            .width(52)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 4
      })

      Divider().color(this.pal.divider)

      Column({ space: 8 }) {
        Text($r('app.string.novel_color_scheme'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          this.schemeChip($r('app.string.reader_auto'), 'auto')
          this.schemeChip($r('app.string.novel_color_light'), 'light')
          this.schemeChip($r('app.string.novel_color_dark'), 'dark')
        }
        .width('100%')
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 4
      })

      Divider().color(this.pal.divider)

      Column({ space: 8 }) {
        Text($r('app.string.reader_background'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          this.themeChip($r('app.string.reader_theme_auto'), 3)
          this.themeChip($r('app.string.reader_theme_white'), 0)
          this.themeChip($r('app.string.reader_theme_paper'), 4)
          this.themeChip($r('app.string.reader_theme_gray'), 2)
          this.themeChip($r('app.string.reader_theme_black'), 1)
        }
        .width('100%')
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 4
      })

      Divider().color(this.pal.divider)

      this.toggleRow($r('app.string.novel_keep_screen_on'), this.keepScreenOn,
        (isOn: boolean): void => {
          this.onKeepScreenOn(isOn);
        })

      Divider().color(this.pal.divider)

      this.toggleRow($r('app.string.novel_volume_turn'), this.volumeTurn,
        (isOn: boolean): void => {
          this.onVolumeTurn(isOn);
        })

      Column().height(16)
    }
    .width('100%')
  }

  // 布尔开关行（屏幕常亮 / 音量键翻页）
  @Builder
  toggleRow(label: ResourceStr, isOn: boolean, onChange: (isOn: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(this.pal.sub)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(this.pal.primary)
        .switchPointColor(this.pal.onPrimary)
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 10,
      bottom: 6
    })
  }

  // 配色 chip（自动 / 浅色 / 深色）
  @Builder
  schemeChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.colorScheme === value ? this.pal.onPrimary : this.pal.text)
      .padding({
        left: 14,
        right: 14,
        top: 6,
        bottom: 6
      })
      .borderRadius(16)
      .backgroundColor(this.colorScheme === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.onColorScheme(value);
      })
  }

  // 背景 chip（与漫画阅读器共用 readerTheme：自动/白/纸张/灰/黑）
  @Builder
  themeChip(label: ResourceStr, value: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.readerTheme === value ? this.pal.onPrimary : this.pal.text)
      .padding({
        left: 14,
        right: 14,
        top: 6,
        bottom: 6
      })
      .borderRadius(16)
      .backgroundColor(this.readerTheme === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.onTheme(value);
      })
  }
}
