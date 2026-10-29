import { ThemePalette } from '../../common/Theme';
import { ChapterFlags } from '../../common/ChapterFlags';
import { AppIcon } from './AppIcon';

// 排序模式列表（对齐 Mihon ChapterSettingsDialog SortPage 顺序）
const SORT_MODES: number[] = [
  ChapterFlags.SORTING_SOURCE,
  ChapterFlags.SORTING_NUMBER,
  ChapterFlags.SORTING_UPLOAD_DATE,
  ChapterFlags.SORTING_ALPHABET,
];

// 章节排序/筛选设置弹层（对齐 Mihon ChapterSettingsDialog）：
// 排序页：四模式行，点击已选模式翻转方向，切换模式重置为正序；
// 筛选页：已下载/未读/已书签三态循环 + 重置。
// 状态变更即时回调，由宿主页持久化 chapterFlags 并刷新章节列表。
@Component
export struct ChapterSettingsSheet {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State sheetTab: number = 0;
  // 初值（宿主页当前 chapterFlags 解码结果）
  initSortMode: number = ChapterFlags.SORTING_SOURCE;
  initAscending: boolean = false;
  initUnread: string = 'ignore';
  initDownloaded: string = 'ignore';
  initBookmarked: string = 'ignore';
  // 内部可变副本
  @State sortMode: number = ChapterFlags.SORTING_SOURCE;
  @State ascending: boolean = false;
  @State fUnread: string = 'ignore';
  @State fDownloaded: string = 'ignore';
  @State fBookmarked: string = 'ignore';
  onSortChanged: (mode: number, ascending: boolean) => void = (_mode: number, _ascending: boolean) => {
  };
  onFilterChanged: (unread: string, downloaded: string, bookmarked: string) => void =
    (_unread: string, _downloaded: string, _bookmarked: string) => {
    };

  aboutToAppear(): void {
    this.sortMode = this.initSortMode;
    this.ascending = this.initAscending;
    this.fUnread = this.initUnread;
    this.fDownloaded = this.initDownloaded;
    this.fBookmarked = this.initBookmarked;
  }

  @Builder
  tabBarLabel(index: number, label: Resource) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontWeight(this.sheetTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.sheetTab === index ? this.pal.primary : this.pal.text)
        .maxLines(1)
    }
    .height(48)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  sortTabContent() {
    Column() {
      ForEach(SORT_MODES, (mode: number) => {
        Row() {
          Text(this.sortLabel(mode))
            .fontSize(15)
            .fontColor(this.sortMode === mode ? this.pal.primary : this.pal.text)
            .layoutWeight(1)
          if (this.sortMode === mode) {
            AppIcon({
              name: this.ascending ? 'arrow_upward' : 'arrow_downward',
              iconSize: 20,
              tint: this.pal.primary
            })
          }
        }
        .width('100%')
        .padding({
          left: 24,
          right: 24,
          top: 12,
          bottom: 12
        })
        .onClick(() => {
          this.pickSortMode(mode);
        })
      }, (mode: number) => `sortmode-${mode}`)
    }
    .width('100%')
    .padding({ top: 8, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  filterTabContent() {
    Column() {
      ForEach(['downloaded', 'unread', 'bookmarked'], (key: string) => {
        Row() {
          AppIcon({
            name: this.triIcon(this.triValue(key)),
            iconSize: 24,
            tint: this.triTint(this.triValue(key))
          })
            .margin({ right: 16 })
          Text(this.filterLabel(key))
            .fontSize(15)
            .fontColor(this.pal.text)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({
          left: 24,
          right: 24,
          top: 10,
          bottom: 10
        })
        .onClick(() => {
          this.applyFilter(key);
        })
      }, (key: string) => `chfilter-${key}`)
      Text($r('app.string.detail_filter_reset'))
        .fontSize(14)
        .fontColor(this.pal.primary)
        .width('100%')
        .textAlign(TextAlign.End)
        .padding({
          left: 24,
          right: 24,
          top: 12,
          bottom: 8
        })
        .onClick(() => {
          this.resetFilters();
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.Start, index: this.sheetTab }) {
        TabContent() {
          this.sortTabContent()
        }
        .tabBar(this.tabBarLabel(0, $r('app.string.detail_sort_tab')))

        TabContent() {
          this.filterTabContent()
        }
        .tabBar(this.tabBarLabel(1, $r('app.string.detail_filter_tab')))
      }
      .barHeight(48)
      .barWidth('100%')
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .vertical(false)
      .divider({ strokeWidth: 1, color: this.pal.divider })
      .onChange((index: number) => {
        this.sheetTab = index;
      })
    }
    .width('100%')
    .backgroundColor(this.pal.bg)
  }

  private sortLabel(mode: number): Resource {
    if (mode === ChapterFlags.SORTING_NUMBER) {
      return $r('app.string.detail_sort_by_number');
    }
    if (mode === ChapterFlags.SORTING_UPLOAD_DATE) {
      return $r('app.string.detail_sort_by_date');
    }
    if (mode === ChapterFlags.SORTING_ALPHABET) {
      return $r('app.string.detail_sort_by_name');
    }
    return $r('app.string.detail_sort_by_source');
  }

  // 对齐 Mihon awaitSetSortingModeOrFlipOrder：同模式翻转方向，切模式重置为正序
  private pickSortMode(mode: number): void {
    if (this.sortMode === mode) {
      this.ascending = !this.ascending;
    } else {
      this.sortMode = mode;
      this.ascending = true;
    }
    this.onSortChanged(this.sortMode, this.ascending);
  }

  private applyFilter(key: string): void {
    const cur: string = this.triValue(key);
    const next: string = cur === 'ignore' ? 'include' : (cur === 'include' ? 'exclude' : 'ignore');
    this.setTriValue(key, next);
    this.onFilterChanged(this.fUnread, this.fDownloaded, this.fBookmarked);
  }

  private resetFilters(): void {
    this.fUnread = 'ignore';
    this.fDownloaded = 'ignore';
    this.fBookmarked = 'ignore';
    this.onFilterChanged(this.fUnread, this.fDownloaded, this.fBookmarked);
  }

  private triValue(key: string): string {
    if (key === 'downloaded') {
      return this.fDownloaded;
    }
    if (key === 'unread') {
      return this.fUnread;
    }
    return this.fBookmarked;
  }

  private setTriValue(key: string, v: string): void {
    if (key === 'downloaded') {
      this.fDownloaded = v;
    } else if (key === 'unread') {
      this.fUnread = v;
    } else {
      this.fBookmarked = v;
    }
  }

  private filterLabel(key: string): Resource {
    if (key === 'downloaded') {
      return $r('app.string.detail_filter_downloaded');
    }
    if (key === 'unread') {
      return $r('app.string.detail_filter_unread');
    }
    return $r('app.string.detail_filter_bookmarked');
  }

  // 三态图标：ignore=空心(灰) include=选中(主色) exclude=禁用(主色)
  private triIcon(v: string): string {
    if (v === 'include') {
      return 'check_box';
    }
    if (v === 'exclude') {
      return 'disabled_by_default';
    }
    return 'check_box_outline_blank';
  }

  private triTint(v: string): ResourceColor {
    return v === 'ignore' ? this.pal.sub : this.pal.primary;
  }
}
