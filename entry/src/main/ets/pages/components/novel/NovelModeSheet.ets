// 小说阅读器「阅读模式」Sheet：阅读模式选择 + 翻页动画
// （从 NovelReaderPage 拆出，Wave 3I；行为与原 modeSheetBuilder 一致）
import { ThemePalette } from '../../../common/Theme';
import { PickerSheet } from '../PickerSheet';

// 阅读模式的可选值（与模式选择 sheet 选项一一对应）
const NOVEL_MODES: string[] = ['scroll', 'paged', 'paged_rtl', 'double'];
const NOVEL_MODE_ICONS: string[] = ['reader_scroll', 'reader_ltr', 'reader_rtl', 'reader_double'];

@Component
export struct NovelModeSheet {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop mode: string = 'scroll';
  @Prop animMode: string = 'slide';
  onMode: (mode: string) => void = (mode: string): void => {};
  onAnim: (anim: string) => void = (anim: string): void => {};

  build() {
    Column({ space: 0 }) {
      PickerSheet({
        options: [$r('app.string.novel_mode_scroll'), $r('app.string.novel_mode_single_ltr'),
          $r('app.string.novel_mode_single_rtl'), $r('app.string.novel_mode_double')],
        icons: NOVEL_MODE_ICONS,
        selectedIndex: NOVEL_MODES.indexOf(this.mode),
        onPick: (index: number): void => {
          const v: string | undefined = NOVEL_MODES[index];
          if (v !== undefined) {
            this.onMode(v);
          }
        }
      })

      Divider().color(this.pal.divider)

      Column({ space: 8 }) {
        Text($r('app.string.novel_page_animation'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          this.animChip($r('app.string.novel_anim_curl'), 'curl')
          this.animChip($r('app.string.novel_anim_slide'), 'slide')
          this.animChip($r('app.string.novel_anim_cover'), 'cover')
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      Column().height(16)
    }
    .width('100%')
  }

  // 翻页动画 chip（仿真 / 滑动 / 覆盖）
  @Builder
  animChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.animMode === value ? this.pal.onPrimary : this.pal.text)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.animMode === value ? this.pal.primary : this.pal.chip)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.onAnim(value);
      })
  }
}
