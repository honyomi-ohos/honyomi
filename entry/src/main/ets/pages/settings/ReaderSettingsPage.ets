import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, SelectRow, SwitchRow, TextRow } from '../components/Prefs';

const MODE_LABELS: string[] = ['左右翻页', '右到左', '竖向分页', '条漫'];
const MODE_VALUES: string[] = ['ltr', 'rtl', 'vertical', 'webtoon'];
const THEME_LABELS: string[] = ['跟随主题', '白色', '黑色', '灰色'];
const THEME_VALUES: number[] = [3, 0, 1, 2];

// 阅读器设置：默认模式/双页/页码/背景色/亮度
@Component
export struct ReaderSettingsPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State modeLabel: string = MODE_LABELS[0];
  @State dualPage: boolean = false;
  @State showPageNumber: boolean = true;
  @State themeLabel: string = THEME_LABELS[0];
  @State brightnessLabel: string = '跟随系统';

  aboutToAppear(): void {
    const mode = Settings.getReaderMode();
    const mi = MODE_VALUES.indexOf(mode);
    this.modeLabel = mi >= 0 ? MODE_LABELS[mi] : MODE_LABELS[0];
    this.dualPage = Settings.getReaderDualPage();
    this.showPageNumber = Settings.getReaderShowPageNumber();
    const theme = Settings.getReaderTheme();
    const ti = THEME_VALUES.indexOf(theme);
    this.themeLabel = ti >= 0 ? THEME_LABELS[ti] : THEME_LABELS[0];
    const b = Settings.getReaderBrightness();
    this.brightnessLabel = b === 0 ? '跟随系统' : `${b}`;
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '阅读器' })
        Scroll() {
          Column() {
            PrefGroup({ groupTitle: '阅读模式' }) {
              SelectRow({
                title: '默认模式',
                value: this.modeLabel,
                options: MODE_LABELS,
                onSelect: (value: string): void => {
                  const i = MODE_LABELS.indexOf(value);
                  if (i >= 0) {
                    Settings.setReaderMode(MODE_VALUES[i]);
                    this.modeLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: '双页显示（横向模式）',
                isOn: this.dualPage,
                onChange: (value: boolean): void => {
                  this.dualPage = value;
                  Settings.setReaderDualPage(value);
                }
              })
            }

            PrefGroup({ groupTitle: '显示' }) {
              SwitchRow({
                title: '显示页码',
                isOn: this.showPageNumber,
                onChange: (value: boolean): void => {
                  this.showPageNumber = value;
                  Settings.setReaderShowPageNumber(value);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SelectRow({
                title: '阅读器背景色',
                value: this.themeLabel,
                options: THEME_LABELS,
                onSelect: (value: string): void => {
                  const i = THEME_LABELS.indexOf(value);
                  if (i >= 0) {
                    Settings.setReaderTheme(THEME_VALUES[i]);
                    this.themeLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              TextRow({
                title: '重置阅读器亮度',
                value: this.brightnessLabel,
                onTap: (): void => {
                  Settings.setReaderBrightness(0);
                  this.brightnessLabel = '跟随系统';
                  Util.toast(this.getUIContext(), '已恢复跟随系统亮度');
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
