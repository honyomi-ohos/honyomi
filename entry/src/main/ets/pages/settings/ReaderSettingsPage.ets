import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, SelectRow, SwitchRow, TextRow } from '../components/Prefs';

const MODE_VALUES: string[] = ['ltr', 'rtl', 'vertical', 'webtoon'];
const THEME_VALUES: number[] = [3, 0, 1, 2];

// 阅读器设置：默认模式/双页/页码/背景色/亮度
@Component
export struct ReaderSettingsPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State modeLabel: string = '';
  @State dualPage: boolean = false;
  @State showPageNumber: boolean = true;
  @State themeLabel: string = '';
  @State brightnessLabel: string = '';
  private modeLabels: string[] = [];
  private themeLabels: string[] = [];

  aboutToAppear(): void {
    this.modeLabels = [
      Util.resStr(this.getUIContext(), $r('app.string.reader_set_mode_ltr')),
      Util.resStr(this.getUIContext(), $r('app.string.reader_set_mode_rtl')),
      Util.resStr(this.getUIContext(), $r('app.string.reader_set_mode_vertical')),
      Util.resStr(this.getUIContext(), $r('app.string.reader_set_mode_webtoon'))
    ];
    this.themeLabels = [
      Util.resStr(this.getUIContext(), $r('app.string.reader_set_theme_follow')),
      Util.resStr(this.getUIContext(), $r('app.string.reader_set_theme_white')),
      Util.resStr(this.getUIContext(), $r('app.string.reader_set_theme_black')),
      Util.resStr(this.getUIContext(), $r('app.string.reader_set_theme_gray'))
    ];
    const mode = Settings.getReaderMode();
    const mi = MODE_VALUES.indexOf(mode);
    this.modeLabel = mi >= 0 ? this.modeLabels[mi] : this.modeLabels[0];
    this.dualPage = Settings.getReaderDualPage();
    this.showPageNumber = Settings.getReaderShowPageNumber();
    const theme = Settings.getReaderTheme();
    const ti = THEME_VALUES.indexOf(theme);
    this.themeLabel = ti >= 0 ? this.themeLabels[ti] : this.themeLabels[0];
    const b = Settings.getReaderBrightness();
    this.brightnessLabel = b === 0 ?
      Util.resStr(this.getUIContext(), $r('app.string.lang_follow_system')) : `${b}`;
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.reader_set_title') })
        Scroll() {
          Column() {
            PrefGroup({ groupTitle: $r('app.string.reader_set_mode_group') }) {
              SelectRow({
                title: $r('app.string.reader_set_mode_default'),
                value: this.modeLabel,
                options: this.modeLabels,
                onSelect: (value: string): void => {
                  const i = this.modeLabels.indexOf(value);
                  if (i >= 0) {
                    Settings.setReaderMode(MODE_VALUES[i]);
                    this.modeLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: $r('app.string.reader_set_dual_page'),
                isOn: this.dualPage,
                onChange: (value: boolean): void => {
                  this.dualPage = value;
                  Settings.setReaderDualPage(value);
                }
              })
            }

            PrefGroup({ groupTitle: $r('app.string.reader_set_display_group') }) {
              SwitchRow({
                title: $r('app.string.reader_set_show_page_number'),
                isOn: this.showPageNumber,
                onChange: (value: boolean): void => {
                  this.showPageNumber = value;
                  Settings.setReaderShowPageNumber(value);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SelectRow({
                title: $r('app.string.reader_set_bg_color'),
                value: this.themeLabel,
                options: this.themeLabels,
                onSelect: (value: string): void => {
                  const i = this.themeLabels.indexOf(value);
                  if (i >= 0) {
                    Settings.setReaderTheme(THEME_VALUES[i]);
                    this.themeLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              TextRow({
                title: $r('app.string.reader_set_reset_brightness'),
                value: this.brightnessLabel,
                onTap: (): void => {
                  Settings.setReaderBrightness(0);
                  this.brightnessLabel = Util.resStr(this.getUIContext(), $r('app.string.lang_follow_system'));
                  Util.toastRes(this.getUIContext(), $r('app.string.reader_set_brightness_reset'));
                }
              })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
  }
}
