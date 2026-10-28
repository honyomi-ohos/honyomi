import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { GripSupport } from '../../common/GripSupport';
import { NavGlassPage } from '../../common/HdsNavHost';
import { PrefGroup, PrefSelectRow, PrefSwitchRow, TextRow } from '../components/Prefs';

const THEME_VALUES: number[] = [3, 0, 1, 2, 4];
// 自动翻页间隔（秒，0=关闭；华为阅读对齐）
const AUTO_PAGE_VALUES: number[] = [0, 5, 10, 15, 20, 30, 60];

// 阅读器设置内容：默认模式/阅读体验/页面处理/显示/亮度
@Component
export struct ReaderSettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State brightnessLabel: string = '';
  private modeValues: string[] = [];
  private modeOptions: ResourceStr[] = [];
  private autoPageOptions: ResourceStr[] = [];
  private preloadOptions: ResourceStr[] = [];

  aboutToAppear(): void {
    this.modeValues = ['ltr', 'rtl', 'vertical', 'webtoon', 'continuous'];
    this.modeOptions = [
      $r('app.string.reader_set_mode_ltr'),
      $r('app.string.reader_set_mode_rtl'),
      $r('app.string.reader_set_mode_vertical'),
      $r('app.string.reader_set_mode_webtoon'),
      $r('app.string.reader_set_mode_continuous')
    ];
    // 智感握姿仅在支持的设备上提供
    if (GripSupport.isSupported()) {
      this.modeValues.push('smart_grip');
      this.modeOptions.push($r('app.string.reader_set_mode_smart_grip'));
    }
    const b = Settings.getReaderBrightness();
    this.brightnessLabel = b === 0 ?
      Util.resStr(this.getUIContext(), $r('app.string.lang_follow_system')) : `${b}`;
    // 自动翻页间隔选项：关闭 + 各档位（“N 秒”）
    const pageOpts: ResourceStr[] = [Util.resStr(this.getUIContext(), $r('app.string.reader_auto_off'))];
    for (let i = 1; i < AUTO_PAGE_VALUES.length; i++) {
      pageOpts.push(Util.resStr(this.getUIContext(),
        $r('app.string.reader_auto_sec_fmt'), [AUTO_PAGE_VALUES[i]]));
    }
    this.autoPageOptions = pageOpts;
    // 预加载后续页数选项：0-10 页
    for (let i = 0; i <= 10; i++) {
      this.preloadOptions.push(`${i}`);
    }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PrefGroup({ groupTitle: $r('app.string.reader_set_mode_group') }) {
          PrefSelectRow({
            title: $r('app.string.reader_set_mode_default'),
            options: this.modeOptions,
            selectedIndex: this.modeIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setReaderMode(this.modeValues[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.reader_set_auto_page'),
            options: this.autoPageOptions,
            selectedIndex: this.autoPageIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setReaderAutoPageSec(AUTO_PAGE_VALUES[index]);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.reader_set_experience_group') }) {
          PrefSwitchRow({
            title: $r('app.string.reader_volume_turn'),
            initValue: Settings.getReaderVolumeTurn(),
            apply: (value: boolean): void => {
              Settings.setReaderVolumeTurn(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.reader_keep_screen_on'),
            initValue: Settings.getReaderKeepScreenOn(),
            apply: (value: boolean): void => {
              Settings.setReaderKeepScreenOn(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.reader_show_header_footer'),
            initValue: Settings.getReaderShowHeaderFooter(),
            apply: (value: boolean): void => {
              Settings.setReaderShowHeaderFooter(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.reader_preload_pages'),
            options: this.preloadOptions,
            selectedIndex: Settings.getReaderPreloadPages(),
            onSelectIndex: (index: number): void => {
              Settings.setReaderPreloadPages(index);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.reader_set_page_process_group') }) {
          PrefSwitchRow({
            title: $r('app.string.reader_skip_duplicate_pages'),
            initValue: Settings.getReaderSkipDuplicatePages(),
            apply: (value: boolean): void => {
              Settings.setReaderSkipDuplicatePages(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.reader_clean_blank_pages'),
            initValue: Settings.getReaderCleanBlankPages(),
            apply: (value: boolean): void => {
              Settings.setReaderCleanBlankPages(value);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.reader_set_display_group') }) {
          PrefSwitchRow({
            title: $r('app.string.reader_set_show_page_number'),
            initValue: Settings.getReaderShowPageNumber(),
            apply: (value: boolean): void => {
              Settings.setReaderShowPageNumber(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.reader_set_bg_color'),
            options: [
              $r('app.string.reader_set_theme_follow'),
              $r('app.string.reader_set_theme_white'),
              $r('app.string.reader_set_theme_black'),
              $r('app.string.reader_set_theme_gray'),
              $r('app.string.reader_set_theme_paper')
            ],
            selectedIndex: this.themeIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setReaderTheme(THEME_VALUES[index]);
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
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  private modeIndex(): number {
    const i = this.modeValues.indexOf(Settings.getReaderMode());
    return i >= 0 ? i : 0;
  }

  private themeIndex(): number {
    const i = THEME_VALUES.indexOf(Settings.getReaderTheme());
    return i >= 0 ? i : 0;
  }

  private autoPageIndex(): number {
    const i = AUTO_PAGE_VALUES.indexOf(Settings.getReaderAutoPageSec());
    return i >= 0 ? i : 0;
  }
}

// 阅读器设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct ReaderSettingsPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavGlassPage({ title: $r('app.string.reader_set_title') }) {
      Column() {
        ReaderSettingsContent()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function ReaderSettingsBuilder() {
  ReaderSettingsPage()
}
