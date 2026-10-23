import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { NavGlassPage } from '../../common/HdsNavHost';
import { PrefGroup, PrefSelectRow, PrefSliderRow, PrefSwitchRow } from '../components/Prefs';

const SORT_VALUES: string[] = [
  'alpha', 'total', 'lastRead', 'lastUpdate', 'unread', 'latestChapter', 'fetchDate', 'dateAdded', 'random'
];
const VIEW_VALUES: string[] = ['compact', 'comfortable', 'cover', 'list'];

// 书架设置内容：默认排序/视图/列数/徽标（筛选与三态逻辑在书架过滤弹层中）
@Component
export struct LibrarySettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PrefGroup({ groupTitle: $r('app.string.lib_set_sort_group') }) {
          PrefSelectRow({
            title: $r('app.string.lib_set_sort_default'),
            options: [
              $r('app.string.lib_sort_alpha'), $r('app.string.lib_sort_total'),
              $r('app.string.lib_sort_last_read'), $r('app.string.lib_sort_last_update'),
              $r('app.string.lib_sort_unread'), $r('app.string.lib_sort_latest_chapter'),
              $r('app.string.lib_sort_fetch_date'), $r('app.string.lib_sort_date_added'),
              $r('app.string.lib_sort_random')
            ],
            selectedIndex: this.sortIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setLibrarySort(SORT_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_set_sort_asc'),
            initValue: Settings.getLibrarySortAsc(),
            apply: (value: boolean): void => {
              Settings.setLibrarySortAsc(value);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.lib_set_display_group') }) {
          PrefSelectRow({
            title: $r('app.string.lib_set_view_default'),
            options: [
              $r('app.string.lib_display_compact'), $r('app.string.lib_display_comfortable'),
              $r('app.string.lib_display_cover'), $r('app.string.lib_display_list')
            ],
            selectedIndex: this.viewIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setLibraryView(VIEW_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSliderRow({
            title: $r('app.string.lib_set_grid_cols'),
            initValue: Settings.getLibraryGridCols(),
            minValue: 0,
            maxValue: 10,
            stepValue: 1,
            valueText: (v: number): ResourceStr => v === 0 ? $r('app.string.lib_display_grid_auto') : `${v}`,
            apply: (v: number): void => {
              Settings.setLibraryGridCols(v);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_set_unread_badge'),
            initValue: Settings.getShowUnreadBadge(),
            apply: (value: boolean): void => {
              Settings.setShowUnreadBadge(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_set_download_badge'),
            initValue: Settings.getShowDownloadBadge(),
            apply: (value: boolean): void => {
              Settings.setShowDownloadBadge(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_badge_local'),
            initValue: Settings.getShowLocalBadge(),
            apply: (value: boolean): void => {
              Settings.setShowLocalBadge(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_badge_language'),
            initValue: Settings.getShowLanguageBadge(),
            apply: (value: boolean): void => {
              Settings.setShowLanguageBadge(value);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.lib_display_tabs_group') }) {
          PrefSwitchRow({
            title: $r('app.string.lib_show_category_tabs'),
            initValue: Settings.getShowCategoryTabs(),
            apply: (value: boolean): void => {
              Settings.setShowCategoryTabs(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_show_manga_count'),
            initValue: Settings.getShowMangaCount(),
            apply: (value: boolean): void => {
              Settings.setShowMangaCount(value);
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

  private sortIndex(): number {
    const i = SORT_VALUES.indexOf(Settings.getLibrarySort());
    return i >= 0 ? i : 0;
  }

  private viewIndex(): number {
    const i = VIEW_VALUES.indexOf(Settings.getLibraryView());
    return i >= 0 ? i : 0;
  }
}

// 书架设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct LibrarySettingsPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavGlassPage({ title: $r('app.string.lib_set_title') }) {
      Column() {
        LibrarySettingsContent()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function LibrarySettingsBuilder() {
  LibrarySettingsPage()
}
