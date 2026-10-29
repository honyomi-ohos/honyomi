import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { GripSupport } from '../../common/GripSupport';
import { NavGlassPage } from '../../common/HdsNavHost';
import { PrefGroup, PrefSelectRow, PrefSwitchRow, TextRow } from '../components/Prefs';

const THEME_VALUES: number[] = [3, 0, 1, 2, 4];
// 自动翻页间隔（秒，0=关闭；华为阅读对齐）
const AUTO_PAGE_VALUES: number[] = [0, 5, 10, 15, 20, 30, 60];
// 墨水屏闪烁时长档位（毫秒）
const FLASH_DURATION_VALUES: number[] = [40, 80, 100, 150, 200, 300, 500];
// 滤镜混合模式
const BLEND_VALUES: string[] = ['none', 'multiply', 'screen', 'overlay', 'darken', 'lighten'];
// 缩放起始位置
const ZOOM_START_VALUES: string[] = ['automatic', 'left', 'right', 'center'];
// 墨水屏闪烁颜色
const FLASH_COLOR_VALUES: string[] = ['white', 'black', 'both'];

// 阅读器设置内容：模式/常规/外观/导航/阅读体验/页面处理/墨水屏
@Component
export struct ReaderSettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State brightnessLabel: string = '';
  private modeValues: string[] = [];
  private modeOptions: ResourceStr[] = [];
  private autoPageOptions: ResourceStr[] = [];
  private preloadOptions: ResourceStr[] = [];
  private flashDurationOptions: ResourceStr[] = [];
  private flashEveryOptions: ResourceStr[] = [];

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
    // 墨水屏闪烁时长选项（“N ms”）
    for (let i = 0; i < FLASH_DURATION_VALUES.length; i++) {
      this.flashDurationOptions.push(`${FLASH_DURATION_VALUES[i]} ms`);
    }
    // 闪烁间隔选项：每 N 页闪一次
    for (let i = 1; i <= 10; i++) {
      this.flashEveryOptions.push(`${i}`);
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

        PrefGroup({ groupTitle: $r('app.string.reader_set_general_group') }) {
          PrefSwitchRow({
            title: $r('app.string.reader_set_skip_read'),
            initValue: Settings.getReaderSkipRead(),
            apply: (value: boolean): void => {
              Settings.setReaderSkipRead(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.reader_set_skip_filtered'),
            initValue: Settings.getReaderSkipFiltered(),
            apply: (value: boolean): void => {
              Settings.setReaderSkipFiltered(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.reader_set_skip_duplicate'),
            initValue: Settings.getReaderSkipDuplicate(),
            apply: (value: boolean): void => {
              Settings.setReaderSkipDuplicate(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.reader_set_chapter_transition'),
            initValue: Settings.getReaderShowChapterTransition(),
            apply: (value: boolean): void => {
              Settings.setReaderShowChapterTransition(value);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.reader_set_appearance_group') }) {
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
          PrefSwitchRow({
            title: $r('app.string.reader_set_crop_paged'),
            initValue: Settings.getReaderCropBordersPaged(),
            apply: (value: boolean): void => {
              Settings.setReaderCropBordersPaged(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.reader_set_crop_webtoon'),
            initValue: Settings.getReaderCropBordersWebtoon(),
            apply: (value: boolean): void => {
              Settings.setReaderCropBordersWebtoon(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.reader_set_color_blend'),
            options: [
              $r('app.string.reader_blend_none'),
              $r('app.string.reader_blend_multiply'),
              $r('app.string.reader_blend_screen'),
              $r('app.string.reader_blend_overlay'),
              $r('app.string.reader_blend_darken'),
              $r('app.string.reader_blend_lighten')
            ],
            selectedIndex: this.blendIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setReaderColorFilterBlend(BLEND_VALUES[index]);
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

        PrefGroup({ groupTitle: $r('app.string.reader_set_nav_group') }) {
          PrefSelectRow({
            title: $r('app.string.reader_set_zoom_start'),
            options: [
              $r('app.string.reader_zoom_automatic'),
              $r('app.string.reader_zoom_left'),
              $r('app.string.reader_zoom_right'),
              $r('app.string.reader_zoom_center')
            ],
            selectedIndex: this.zoomStartIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setReaderZoomStart(ZOOM_START_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.reader_set_webtoon_no_zoom_out'),
            initValue: Settings.getReaderWebtoonDisableZoomOut(),
            apply: (value: boolean): void => {
              Settings.setReaderWebtoonDisableZoomOut(value);
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

        PrefGroup({ groupTitle: $r('app.string.reader_set_eink_group') }) {
          PrefSwitchRow({
            title: $r('app.string.reader_set_flash_enable'),
            initValue: Settings.getReaderFlashEnabled(),
            apply: (value: boolean): void => {
              Settings.setReaderFlashEnabled(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.reader_set_flash_color'),
            options: [
              $r('app.string.reader_flash_color_white'),
              $r('app.string.reader_flash_color_black'),
              $r('app.string.reader_flash_color_both')
            ],
            selectedIndex: this.flashColorIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setReaderFlashColor(FLASH_COLOR_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.reader_set_flash_duration'),
            options: this.flashDurationOptions,
            selectedIndex: this.flashDurationIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setReaderFlashDurationMs(FLASH_DURATION_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.reader_set_flash_every'),
            options: this.flashEveryOptions,
            selectedIndex: Settings.getReaderFlashEveryPages() - 1,
            onSelectIndex: (index: number): void => {
              Settings.setReaderFlashEveryPages(index + 1);
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

  private blendIndex(): number {
    const i = BLEND_VALUES.indexOf(Settings.getReaderColorFilterBlend());
    return i >= 0 ? i : 0;
  }

  private zoomStartIndex(): number {
    const i = ZOOM_START_VALUES.indexOf(Settings.getReaderZoomStart());
    return i >= 0 ? i : 0;
  }

  private flashColorIndex(): number {
    const i = FLASH_COLOR_VALUES.indexOf(Settings.getReaderFlashColor());
    return i >= 0 ? i : 0;
  }

  private flashDurationIndex(): number {
    const i = FLASH_DURATION_VALUES.indexOf(Settings.getReaderFlashDurationMs());
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
