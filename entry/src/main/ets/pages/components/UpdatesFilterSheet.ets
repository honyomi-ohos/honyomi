import { ThemePalette } from '../../common/Theme';
import { CategoryRecord } from '../../model/Models';
import { AppIcon } from './AppIcon';

// 三态筛选键（对齐 Mihon UpdatesFilterDialog 顺序：已下载/未读/阅读过/已添加书签）
const UPD_FILTER_KEYS: string[] = ['downloaded', 'unread', 'started', 'bookmarked'];

// 更新页/即将推出页筛选弹层（对齐 Mihon UpdatesFilterDialog / UpcomingFilterDialog）
// - 更新页：筛选 + 分类 两个 Tab
// - 即将推出页：仅分类 Tab（showFilterTab = false）
// 状态变更通过回调上抛，由宿主页持久化并刷新列表
@Component
export struct UpdatesFilterSheet {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State sheetTab: number = 0;
  // 三态筛选初值（不显示筛选 Tab 时保持 ignore）
  initDownloaded: string = 'ignore';
  initUnread: string = 'ignore';
  initStarted: string = 'ignore';
  initBookmarked: string = 'ignore';
  // 分类筛选初值
  initIncluded: number[] = [];
  initExcluded: number[] = [];
  categories: CategoryRecord[] = [];
  showFilterTab: boolean = true;
  onTriStateChanged: (key: string, v: string) => void = (_key: string, _v: string) => {};
  onCategoriesChanged: (included: number[], excluded: number[]) => void =
    (_included: number[], _excluded: number[]) => {};
  // 内部可变副本
  @State fDownloaded: string = 'ignore';
  @State fUnread: string = 'ignore';
  @State fStarted: string = 'ignore';
  @State fBookmarked: string = 'ignore';
  @State includedCats: number[] = [];
  @State excludedCats: number[] = [];

  aboutToAppear(): void {
    this.fDownloaded = this.initDownloaded;
    this.fUnread = this.initUnread;
    this.fStarted = this.initStarted;
    this.fBookmarked = this.initBookmarked;
    this.includedCats = this.initIncluded.slice();
    this.excludedCats = this.initExcluded.slice();
  }

  private triValue(key: string): string {
    if (key === 'downloaded') {
      return this.fDownloaded;
    }
    if (key === 'unread') {
      return this.fUnread;
    }
    if (key === 'started') {
      return this.fStarted;
    }
    return this.fBookmarked;
  }

  // 三态循环：ignore → include → exclude → ignore
  private applyFilter(key: string): void {
    const cur: string = this.triValue(key);
    const next: string = cur === 'ignore' ? 'include' : (cur === 'include' ? 'exclude' : 'ignore');
    if (key === 'downloaded') {
      this.fDownloaded = next;
    } else if (key === 'unread') {
      this.fUnread = next;
    } else if (key === 'started') {
      this.fStarted = next;
    } else {
      this.fBookmarked = next;
    }
    this.onTriStateChanged(key, next);
  }

  private filterLabel(key: string): Resource {
    if (key === 'downloaded') {
      return $r('app.string.lib_filter_downloaded');
    }
    if (key === 'unread') {
      return $r('app.string.lib_filter_unread');
    }
    if (key === 'started') {
      return $r('app.string.lib_filter_started');
    }
    return $r('app.string.lib_filter_bookmarked');
  }

  // 分类三态：未选 → 包含 → 排除 → 未选（对齐 Mihon cycleCategory）
  private catState(id: number): string {
    if (this.includedCats.indexOf(id) >= 0) {
      return 'include';
    }
    if (this.excludedCats.indexOf(id) >= 0) {
      return 'exclude';
    }
    return 'ignore';
  }

  private cycleCategory(id: number): void {
    const inc: number[] = this.includedCats.slice();
    const exc: number[] = this.excludedCats.slice();
    const inInc: number = inc.indexOf(id);
    const inExc: number = exc.indexOf(id);
    if (inInc >= 0) {
      inc.splice(inInc, 1);
      exc.push(id);
    } else if (inExc >= 0) {
      exc.splice(inExc, 1);
    } else {
      inc.push(id);
    }
    this.includedCats = inc;
    this.excludedCats = exc;
    this.onCategoriesChanged(inc, exc);
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
  filterTabContent() {
    Scroll() {
      Column() {
        ForEach(UPD_FILTER_KEYS, (key: string) => {
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
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 10, bottom: 10 })
          .onClick(() => {
            this.applyFilter(key);
          })
        }, (key: string) => `updfilter-${key}`)
      }
      .width('100%')
      .padding({ top: 8, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  @Builder
  categoryTabContent() {
    Scroll() {
      Column() {
        Text($r('app.string.pref_filter_update_categories_details'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
          .padding({ left: 24, right: 24, top: 12, bottom: 8 })
        ForEach(this.categories, (cat: CategoryRecord) => {
          Row() {
            AppIcon({
              name: this.triIcon(this.catState(cat.id)),
              iconSize: 24,
              tint: this.triTint(this.catState(cat.id))
            })
              .margin({ right: 16 })
            Text(cat.name)
              .fontSize(15)
              .fontColor(this.pal.text)
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 10, bottom: 10 })
          .onClick(() => {
            this.cycleCategory(cat.id);
          })
        }, (cat: CategoryRecord) => `updcat-${cat.id}`)
      }
      .width('100%')
      .padding({ bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.Start, index: this.sheetTab }) {
        if (this.showFilterTab) {
          TabContent() {
            this.filterTabContent()
          }
          .tabBar(this.tabBarLabel(0, $r('app.string.lib_sheet_tab_filter')))
        }
        TabContent() {
          this.categoryTabContent()
        }
        .tabBar(this.tabBarLabel(this.showFilterTab ? 1 : 0, $r('app.string.categories_title')))
      }
      .layoutWeight(1)
      .barHeight(48)
      .barWidth('100%')
      .barMode(BarMode.Fixed)
      .scrollable(true)
      .vertical(false)
      .divider({ strokeWidth: 1, color: this.pal.divider })
      .onChange((index: number) => {
        this.sheetTab = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }
}
