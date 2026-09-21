import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, SelectRow, SwitchRow } from '../components/Prefs';

const SORT_VALUES: string[] = ['title', 'lastUpdate', 'added', 'unread'];
const FILTER_VALUES: string[] = ['none', 'unread', 'downloaded', 'uncompleted'];
const VIEW_VALUES: string[] = ['grid', 'cover', 'list'];
const COLS_VALUES: number[] = [0, 2, 3, 4];

// 书架设置：默认排序/筛选/视图/列数/徽标
@Component
export struct LibrarySettingsPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State sortLabel: string = '';
  @State sortAsc: boolean = true;
  @State filterLabel: string = '';
  @State viewLabel: string = '';
  @State colsLabel: string = '';
  @State showUnreadBadge: boolean = true;
  @State showDownloadBadge: boolean = true;
  private sortLabels: string[] = [];
  private filterLabels: string[] = [];
  private viewLabels: string[] = [];
  private colsLabels: string[] = [];

  aboutToAppear(): void {
    this.sortLabels = [
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_sort_title')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_sort_last_update')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_sort_added')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_sort_unread'))
    ];
    this.filterLabels = [
      Util.resStr(this.getUIContext(), $r('app.string.common_all')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_filter_unread')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_filter_downloaded')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_filter_uncompleted'))
    ];
    this.viewLabels = [
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_view_grid')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_view_cover')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_view_list'))
    ];
    this.colsLabels = [
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_cols_auto')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_cols_2')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_cols_3')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_cols_4'))
    ];
    const sort = Settings.getLibrarySort();
    const si = SORT_VALUES.indexOf(sort);
    this.sortLabel = si >= 0 ? this.sortLabels[si] : this.sortLabels[0];
    this.sortAsc = Settings.getLibrarySortAsc();
    const filter = Settings.getLibraryFilter();
    const fi = FILTER_VALUES.indexOf(filter);
    this.filterLabel = fi >= 0 ? this.filterLabels[fi] : this.filterLabels[0];
    const view = Settings.getLibraryView();
    const vi = VIEW_VALUES.indexOf(view);
    this.viewLabel = vi >= 0 ? this.viewLabels[vi] : this.viewLabels[0];
    const cols = Settings.getLibraryGridCols();
    const ci = COLS_VALUES.indexOf(cols);
    this.colsLabel = ci >= 0 ? this.colsLabels[ci] : this.colsLabels[0];
    this.showUnreadBadge = Settings.getShowUnreadBadge();
    this.showDownloadBadge = Settings.getShowDownloadBadge();
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
              Divider().color(this.pal.divider).margin({ left: 16 })
              SelectRow({
                title: $r('app.string.lib_set_filter_default'),
                value: this.filterLabel,
                options: this.filterLabels,
                onSelect: (value: string): void => {
                  const i = this.filterLabels.indexOf(value);
                  if (i >= 0) {
                    Settings.setLibraryFilter(FILTER_VALUES[i]);
                    this.filterLabel = value;
                  }
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
