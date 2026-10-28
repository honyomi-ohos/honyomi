// 小说阅读器「文本」设置面板：字号 / 边距 / 段间距 / 合并空行 / 段落缩进 / 行间距 / 字体 / 两端对齐 / 整章翻译
// （从 NovelReaderPage 拆出，Wave 3I；行为与原 textSheetBuilder 一致）
import { ThemePalette } from '../../../common/Theme';
import { WideSlider } from '../WideSlider';

@Component
export struct NovelTextPanel {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Link fontSize: number;
  @Link pageMargin: number;
  @Link paraSpacing: number;
  @Link mergeBlank: boolean;
  @Link indentChars: number;
  @Link lineHeight: number;
  @Link justify: boolean;
  @Link transOn: boolean;
  @Prop fontFamily: string = 'default';
  onFontSizeDone: (v: number) => void = (v: number): void => {
  };
  onMarginDone: (v: number) => void = (v: number): void => {
  };
  onParaSpacingDone: (v: number) => void = (v: number): void => {
  };
  onMergeBlank: (v: boolean) => void = (v: boolean): void => {
  };
  onIndentDone: (v: number) => void = (v: number): void => {
  };
  onLineHeightDone: (v: number) => void = (v: number): void => {
  };
  onJustify: (v: boolean) => void = (v: boolean): void => {
  };
  onTransChange: (v: boolean) => void = (v: boolean): void => {
  };
  onFontFamily: (v: string) => void = (v: string): void => {
  };

  build() {
    Column({ space: 0 }) {
      this.novelSliderRow($r('app.string.novel_font_size'), this.fontSize, 14, 32,
        (value: number, done: boolean): void => {
          this.fontSize = value;
          if (done) {
            this.onFontSizeDone(value);
          }
        })

      Divider().color(this.pal.divider)

      this.novelSliderRow($r('app.string.novel_margin'), this.pageMargin, 8, 48,
        (value: number, done: boolean): void => {
          this.pageMargin = value;
          if (done) {
            this.onMarginDone(value);
          }
        })

      Divider().color(this.pal.divider)

      this.novelSliderRow($r('app.string.novel_paragraph_spacing'), this.paraSpacing, 0, 28,
        (value: number, done: boolean): void => {
          this.paraSpacing = value;
          if (done) {
            this.onParaSpacingDone(value);
          }
        })

      Divider().color(this.pal.divider)

      this.mergeBlankRow()

      Divider().color(this.pal.divider)

      this.novelSliderRow($r('app.string.novel_paragraph_indent'), this.indentChars, 0, 4,
        (value: number, done: boolean): void => {
          this.indentChars = value;
          if (done) {
            this.onIndentDone(value);
          }
        })

      Divider().color(this.pal.divider)

      this.novelSliderRow($r('app.string.novel_line_height'), this.lineHeight, 20, 56,
        (value: number, done: boolean): void => {
          this.lineHeight = value;
          if (done) {
            this.onLineHeightDone(value);
          }
        })

      Divider().color(this.pal.divider)

      this.justifyRow()

      Divider().color(this.pal.divider)

      // 整章翻译开关（开启后自动翻译本章，译文替换原文）
      this.transRow()

      Divider().color(this.pal.divider)

      Column({ space: 8 }) {
        Text($r('app.string.novel_font_family'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          this.fontChip($r('app.string.novel_font_default'), 'default')
          this.fontChip($r('app.string.novel_font_serif'), 'serif')
          this.fontChip($r('app.string.novel_font_sans'), 'sans')
          this.fontChip($r('app.string.novel_font_mono'), 'mono')
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

      Column().height(16)
    }
    .width('100%')
  }

  // 两端对齐开关行：正文段落（末行除外）左右两端对齐排版
  @Builder
  justifyRow() {
    Row() {
      Text($r('app.string.novel_justify'))
        .fontSize(13)
        .fontColor(this.pal.sub)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.justify })
        .selectedColor(this.pal.primary)
        .switchPointColor(this.pal.onPrimary)
        .onChange((isOn: boolean) => {
          this.justify = isOn;
          this.onJustify(isOn);
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

  // 合并空行开关行：部分站点段落间大量空行，开启后折叠为单个换行
  @Builder
  mergeBlankRow() {
    Row() {
      Text($r('app.string.novel_merge_blank_lines'))
        .fontSize(13)
        .fontColor(this.pal.sub)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.mergeBlank })
        .selectedColor(this.pal.primary)
        .switchPointColor(this.pal.onPrimary)
        .onChange((isOn: boolean) => {
          this.mergeBlank = isOn;
          this.onMergeBlank(isOn);
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

  // 整章翻译开关行：开启后自动翻译本章并展示译文，关闭还原原文
  @Builder
  transRow() {
    Row() {
      Column() {
        Text($r('app.string.novel_trans_chapter'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Text($r('app.string.novel_trans_chapter_sub'))
          .fontSize(11)
          .fontColor(this.pal.sub)
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.transOn })
        .selectedColor(this.pal.primary)
        .switchPointColor(this.pal.onPrimary)
        .onChange((isOn: boolean) => {
          this.transOn = isOn;
          this.onTransChange(isOn);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 16,
      right: 16,
      top: 10,
      bottom: 6
    })
  }

  // 字体 chip（默认 / 宋体 / 黑体 / 等宽）
  @Builder
  fontChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.fontFamily === value ? this.pal.onPrimary : this.pal.text)
      .padding({
        left: 14,
        right: 14,
        top: 6,
        bottom: 6
      })
      .borderRadius(16)
      .backgroundColor(this.fontFamily === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.onFontFamily(value);
      })
  }

  // 设置面板滑杆行：label 在上、Slider + 数值在下（对齐面板内其他分组的排版）
  @Builder
  novelSliderRow(label: ResourceStr, value: number, min: number, max: number,
    onChange: (value: number, done: boolean) => void) {
    Column({ space: 8 }) {
      Text(label)
        .fontSize(13)
        .fontColor(this.pal.sub)
        .width('100%')
      Row() {
        WideSlider({
          sliderValue: value,
          min: min,
          max: max,
          step: 1,
          onChange: (sliderValue: number, mode: SliderChangeMode): void => {
            onChange(Math.round(sliderValue),
              mode === SliderChangeMode.End || mode === SliderChangeMode.Click);
          }
        })
          .layoutWeight(1)
        Text(`${value}`)
          .fontSize(13)
          .fontColor(this.pal.text)
          .width(44)
          .textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 10,
      bottom: 6
    })
  }
}
