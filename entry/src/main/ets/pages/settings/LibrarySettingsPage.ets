import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, SelectRow, SwitchRow } from '../components/Prefs';

const SORT_LABELS: string[] = ['标题', '最新章节', '添加时间', '未读数'];
const SORT_VALUES: string[] = ['title', 'lastUpdate', 'added', 'unread'];
const FILTER_LABELS: string[] = ['全部', '未读', '已下载', '未完结'];
const FILTER_VALUES: string[] = ['none', 'unread', 'downloaded', 'uncompleted'];
const VIEW_LABELS: string[] = ['网格', '封面网格', '列表'];
const VIEW_VALUES: string[] = ['grid', 'cover', 'list'];
const COLS_LABELS: string[] = ['自适应', '2 列', '3 列', '4 列'];
const COLS_VALUES: number[] = [0, 2, 3, 4];

// 书架设置：默认排序/筛选/视图/列数/徽标
@Component
export struct LibrarySettingsPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State sortLabel: string = SORT_LABELS[0];
  @State sortAsc: boolean = true;
  @State filterLabel: string = FILTER_LABELS[0];
  @State viewLabel: string = VIEW_LABELS[0];
  @State colsLabel: string = COLS_LABELS[0];
  @State showUnreadBadge: boolean = true;
  @State showDownloadBadge: boolean = true;

  aboutToAppear(): void {
    const sort = Settings.getLibrarySort();
    const si = SORT_VALUES.indexOf(sort);
    this.sortLabel = si >= 0 ? SORT_LABELS[si] : SORT_LABELS[0];
    this.sortAsc = Settings.getLibrarySortAsc();
    const filter = Settings.getLibraryFilter();
    const fi = FILTER_VALUES.indexOf(filter);
    this.filterLabel = fi >= 0 ? FILTER_LABELS[fi] : FILTER_LABELS[0];
    const view = Settings.getLibraryView();
    const vi = VIEW_VALUES.indexOf(view);
    this.viewLabel = vi >= 0 ? VIEW_LABELS[vi] : VIEW_LABELS[0];
    const cols = Settings.getLibraryGridCols();
    const ci = COLS_VALUES.indexOf(cols);
    this.colsLabel = ci >= 0 ? COLS_LABELS[ci] : COLS_LABELS[0];
    this.showUnreadBadge = Settings.getShowUnreadBadge();
    this.showDownloadBadge = Settings.getShowDownloadBadge();
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '书架' })
        Scroll() {
          Column() {
            PrefGroup({ groupTitle: '分类与排序' }) {
              SelectRow({
                title: '默认排序',
                value: this.sortLabel,
                options: SORT_LABELS,
                onSelect: (value: string): void => {
                  const i = SORT_LABELS.indexOf(value);
                  if (i >= 0) {
                    Settings.setLibrarySort(SORT_VALUES[i]);
                    this.sortLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: '按标题正序排列',
                isOn: this.sortAsc,
                onChange: (value: boolean): void => {
                  this.sortAsc = value;
                  Settings.setLibrarySortAsc(value);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SelectRow({
                title: '默认筛选',
                value: this.filterLabel,
                options: FILTER_LABELS,
                onSelect: (value: string): void => {
                  const i = FILTER_LABELS.indexOf(value);
                  if (i >= 0) {
                    Settings.setLibraryFilter(FILTER_VALUES[i]);
                    this.filterLabel = value;
                  }
                }
              })
            }

            PrefGroup({ groupTitle: '显示' }) {
              SelectRow({
                title: '默认视图',
                value: this.viewLabel,
                options: VIEW_LABELS,
                onSelect: (value: string): void => {
                  const i = VIEW_LABELS.indexOf(value);
                  if (i >= 0) {
                    Settings.setLibraryView(VIEW_VALUES[i]);
                    this.viewLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SelectRow({
                title: '网格列数',
                value: this.colsLabel,
                options: COLS_LABELS,
                onSelect: (value: string): void => {
                  const i = COLS_LABELS.indexOf(value);
                  if (i >= 0) {
                    Settings.setLibraryGridCols(COLS_VALUES[i]);
                    this.colsLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: '未读数徽标',
                isOn: this.showUnreadBadge,
                onChange: (value: boolean): void => {
                  this.showUnreadBadge = value;
                  Settings.setShowUnreadBadge(value);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: '下载数徽标',
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
