import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, SelectRow, SwitchRow } from '../components/Prefs';

const SORT_VALUES: string[] = [
  'alpha', 'total', 'lastRead', 'lastUpdate', 'unread', 'latestChapter', 'fetchDate', 'dateAdded', 'random'
];
const VIEW_VALUES: string[] = ['compact', 'comfortable', 'cover', 'list'];
const COLS_VALUES: number[] = [0, 2, 3, 4, 5, 6, 7, 8, 9, 10];

// 书架设置：默认排序/视图/列数/徽标（筛选与三态逻辑在书架过滤弹层中）
@Component
export struct LibrarySettingsPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State sortLabel: string = '';
  @State sortAsc: boolean = true;
  @State viewLabel: string = '';
  @State colsLabel: string = '';
  @State showUnreadBadge: boolean = true;
  @State showDownloadBadge: boolean = true;
  @State showLocalBadge: boolean = false;
  @State showLanguageBadge: boolean = false;
  @State showCategoryTabs: boolean = true;
  @State showMangaCount: boolean = false;
  private sortLabels: string[] = [];
  private viewLabels: string[] = [];
  private colsLabels: string[] = [];

  aboutToAppear(): void {
    this.sortLabels = [
      Util.resStr(this.getUIContext(), $r('app.string.lib_sort_alpha')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_sort_total')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_sort_last_read')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_sort_last_update')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_sort_unread')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_sort_latest_chapter')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_sort_fetch_date')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_sort_date_added')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_sort_random'))
    ];
    this.viewLabels = [
      Util.resStr(this.getUIContext(), $r('app.string.lib_display_compact')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_display_comfortable')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_display_cover')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_display_list'))
    ];
    this.colsLabels = [
      Util.resStr(this.getUIContext(), $r('app.string.lib_display_grid_auto')),
      '2', '3', '4', '5', '6', '7', '8', '9', '10'
    ];
    const sort = Settings.getLibrarySort();
    const si = SORT_VALUES.indexOf(sort);
    this.sortLabel = si >= 0 ? this.sortLabels[si] : this.sortLabels[0];
    this.sortAsc = Settings.getLibrarySortAsc();
    const view = Settings.getLibraryView();
    const vi = VIEW_VALUES.indexOf(view);
    this.viewLabel = vi >= 0 ? this.viewLabels[vi] : this.viewLabels[0];
    const cols = Settings.getLibraryGridCols();
    const ci = COLS_VALUES.indexOf(cols);
    this.colsLabel = ci >= 0 ? this.colsLabels[ci] : this.colsLabels[0];
    this.showUnreadBadge = Settings.getShowUnreadBadge();
    this.showDownloadBadge = Settings.getShowDownloadBadge();
    this.showLocalBadge = Settings.getShowLocalBadge();
    this.showLanguageBadge = Settings.getShowLanguageBadge();
    this.showCategoryTabs = Settings.getShowCategoryTabs();
    this.showMangaCount = Settings.getShowMangaCount();
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.lib_set_title') })
        Scroll() {
          Column() {
            PrefGroup({ groupTitle: $r('app.string.lib_set_sort_group') }) {
              SelectRow({
                title: $r('app.string.lib_set_sort_default'),
                value: this.sortLabel,
                options: this.sortLabels,
                onSelect: (value: string): void => {
                  const i = this.sortLabels.indexOf(value);
                  if (i >= 0) {
                    Settings.setLibrarySort(SORT_VALUES[i]);
                    this.sortLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: $r('app.string.lib_set_sort_asc'),
                isOn: this.sortAsc,
                onChange: (value: boolean): void => {
                  this.sortAsc = value;
                  Settings.setLibrarySortAsc(value);
                }
              })
            }

            PrefGroup({ groupTitle: $r('app.string.lib_set_display_group') }) {
              SelectRow({
                title: $r('app.string.lib_set_view_default'),
                value: this.viewLabel,
                options: this.viewLabels,
                onSelect: (value: string): void => {
                  const i = this.viewLabels.indexOf(value);
                  if (i >= 0) {
                    Settings.setLibraryView(VIEW_VALUES[i]);
                    this.viewLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SelectRow({
                title: $r('app.string.lib_set_grid_cols'),
                value: this.colsLabel,
                options: this.colsLabels,
                onSelect: (value: string): void => {
                  const i = this.colsLabels.indexOf(value);
                  if (i >= 0) {
                    Settings.setLibraryGridCols(COLS_VALUES[i]);
                    this.colsLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: $r('app.string.lib_set_unread_badge'),
                isOn: this.showUnreadBadge,
                onChange: (value: boolean): void => {
                  this.showUnreadBadge = value;
                  Settings.setShowUnreadBadge(value);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: $r('app.string.lib_set_download_badge'),
                isOn: this.showDownloadBadge,
                onChange: (value: boolean): void => {
                  this.showDownloadBadge = value;
                  Settings.setShowDownloadBadge(value);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: $r('app.string.lib_badge_local'),
                isOn: this.showLocalBadge,
                onChange: (value: boolean): void => {
                  this.showLocalBadge = value;
                  Settings.setShowLocalBadge(value);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: $r('app.string.lib_badge_language'),
                isOn: this.showLanguageBadge,
                onChange: (value: boolean): void => {
                  this.showLanguageBadge = value;
                  Settings.setShowLanguageBadge(value);
                }
              })
            }

            PrefGroup({ groupTitle: $r('app.string.lib_display_tabs_group') }) {
              SwitchRow({
                title: $r('app.string.lib_show_category_tabs'),
                isOn: this.showCategoryTabs,
                onChange: (value: boolean): void => {
                  this.showCategoryTabs = value;
                  Settings.setShowCategoryTabs(value);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: $r('app.string.lib_show_manga_count'),
                isOn: this.showMangaCount,
                onChange: (value: boolean): void => {
                  this.showMangaCount = value;
                  Settings.setShowMangaCount(value);
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
