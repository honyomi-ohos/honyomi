import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { LibGrid } from '../../common/Util';
import { ContentType } from '../../model/Models';
import { AppIcon } from './AppIcon';
import { WideSlider } from './WideSlider';

// 排序键（对齐 Mihon LibrarySort）
const SORT_KEYS: string[] = [
  'alpha', 'total', 'lastRead', 'lastUpdate', 'unread', 'latestChapter', 'fetchDate', 'dateAdded', 'random'
];
// 三态筛选键
const FILTER_KEYS: string[] = ['downloaded', 'unread', 'started', 'bookmarked', 'completed', 'tracked'];
// 显示模式
const VIEW_MODES: string[] = ['compact', 'comfortable', 'cover', 'list'];

// 书架过滤弹层（对齐 Mihon LibrarySettingsDialog）：筛选 / 排序 / 显示 三 Tab
@Component
export struct LibrarySettingsSheet {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Link sortKey: string;
  @Link sortAsc: boolean;
  @Link filterDownloaded: string;
  @Link filterUnread: string;
  @Link filterStarted: string;
  @Link filterBookmarked: string;
  @Link filterCompleted: string;
  @Link filterTracked: string;
  @Link contentFilter: string;
  @Link viewMode: string;
  @Link gridCols: number;
  // 书架内容区宽度：列数滑条按其限制最小/最大列
  @Prop contentW: number = 0;
  @Link showUnreadBadge: boolean;
  @Link showDownloadBadge: boolean;
  @Link showLocalBadge: boolean;
  @Link showLanguageBadge: boolean;
  @Link showCategoryTabs: boolean;
  @Link showMangaCount: boolean;
  @State sheetTab: number = 0;
  onReshuffle: () => void = () => {
  };

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
  checkboxRow(label: Resource, checked: boolean, onToggle: (v: boolean) => void) {
    Row() {
      Checkbox()
        .select(checked)
        .selectedColor(this.pal.primary)
        .width(24)
        .height(24)
        .margin({ right: 16 })
        .onChange((v: boolean) => {
          onToggle(v);
        })
      Text(label)
        .fontSize(15)
        .fontColor(this.pal.text)
    }
    .width('100%')
    .padding({
      left: 24,
      right: 24,
      top: 6,
      bottom: 6
    })
  }

  @Builder
  typeChip(type: string, label: Resource) {
    Text(label)
      .fontSize(13)
      .fontColor(this.contentFilter === type ? this.pal.onPrimary : this.pal.text)
      .backgroundColor(this.contentFilter === type ? this.pal.primary : this.pal.chip)
      .borderRadius(14)
      .padding({
        left: 12,
        right: 12,
        top: 6,
        bottom: 6
      })
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.contentFilter = type;
        Settings.setLibraryContentFilter(type);
      })
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.Start, index: this.sheetTab }) {
        TabContent() {
          Scroll() {
            Column() {
              Text($r('app.string.lib_filter_content'))
                .fontSize(13)
                .fontColor(this.pal.sub)
                .width('100%')
                .padding({
                  left: 24,
                  right: 24,
                  top: 8,
                  bottom: 8
                })
              Flex({ wrap: FlexWrap.Wrap }) {
                this.typeChip('all', $r('app.string.lib_filter_type_all'))
                this.typeChip(ContentType.MANGA, $r('app.string.browse_type_manga'))
                this.typeChip(ContentType.NOVEL, $r('app.string.browse_type_novel'))
                this.typeChip(ContentType.VIDEO, $r('app.string.browse_type_video'))
              }
              .width('100%')
              .padding({ left: 24, right: 24, bottom: 8 })

              ForEach(FILTER_KEYS, (key: string) => {
                Row() {
                  AppIcon({
                    name: this.triIcon(this.filterValue(key)),
                    iconSize: 24,
                    tint: this.triTint(this.filterValue(key))
                  })
                    .margin({ right: 16 })
                  Text(this.filterLabel(key))
                    .fontSize(15)
                    .fontColor(this.pal.text)
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
              }, (key: string) => `filter-${key}`)
            }
            .width('100%')
            .padding({ top: 8, bottom: 16 })
            .alignItems(HorizontalAlign.Start)
          }
          .height('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.TopStart)
        }
        .tabBar(this.tabBarLabel(0, $r('app.string.lib_sheet_tab_filter')))

        TabContent() {
          Scroll() {
            Column() {
              ForEach(SORT_KEYS, (key: string) => {
                Row() {
                  Text(this.sortLabel(key))
                    .fontSize(15)
                    .fontColor(this.pal.text)
                  Blank()
                  if (this.sortKey === key) {
                    if (key === 'random') {
                      AppIcon({ name: 'refresh', iconSize: 24, tint: this.pal.primary })
                        .onClick(() => {
                          this.onReshuffle();
                        })
                    } else {
                      AppIcon({
                        name: this.sortAsc ? 'arrow_upward' : 'arrow_downward',
                        iconSize: 24,
                        tint: this.pal.primary
                      })
                    }
                  }
                }
                .width('100%')
                .padding({
                  left: 24,
                  right: 24,
                  top: 10,
                  bottom: 10
                })
                .onClick(() => {
                  this.applySort(key);
                })
              }, (key: string) => `sort-${key}`)
            }
            .width('100%')
            .padding({ top: 8, bottom: 16 })
            .alignItems(HorizontalAlign.Start)
          }
          .height('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.TopStart)
        }
        .tabBar(this.tabBarLabel(1, $r('app.string.lib_sheet_tab_sort')))

        TabContent() {
          Scroll() {
            Column() {
              // 显示模式 chips
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(VIEW_MODES, (mode: string) => {
                  Text(this.viewLabel(mode))
                    .fontSize(13)
                    .fontColor(this.viewMode === mode ? this.pal.onPrimary : this.pal.text)
                    .backgroundColor(this.viewMode === mode ? this.pal.primary : this.pal.chip)
                    .borderRadius(14)
                    .padding({
                      left: 14,
                      right: 14,
                      top: 8,
                      bottom: 8
                    })
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      this.applyView(mode);
                    })
                }, (mode: string) => `view-${mode}`)
              }
              .width('100%')
              .padding({ left: 24, right: 24, top: 8 })

              // 每行数目滑条（列表模式隐藏，0=自动）
              if (this.viewMode !== 'list') {
                Column() {
                  Row() {
                    Text($r('app.string.lib_display_grid_size'))
                      .fontSize(15)
                      .fontColor(this.pal.text)
                    Blank()
                    Text(this.gridCols === 0
                      ? $r('app.string.lib_display_grid_auto')
                      : `${LibGrid.clampCols(this.gridCols, this.gridW())}`)
                      .fontSize(13)
                      .fontColor(this.pal.text)
                      .backgroundColor(this.pal.chip)
                      .borderRadius(999)
                      .padding({
                        left: 10,
                        right: 10,
                        top: 3,
                        bottom: 3
                      })
                      .margin({ left: 8 })
                  }
                  .width('100%')

                  WideSlider({
                    sliderValue: LibGrid.posOfCols(this.gridCols, this.gridW()),
                    min: 0,
                    max: LibGrid.maxPos(this.gridW()),
                    step: 1,
                    onChange: (v: number, mode: SliderChangeMode): void => {
                      const n: number = LibGrid.colsOfPos(Math.floor(v), this.gridW());
                      if (n !== this.gridCols) {
                        // 列数变化：包 animateTo 让书架网格重排带过渡动画
                        this.getUIContext().animateTo({ duration: 200, curve: Curve.Friction }, (): void => {
                          this.gridCols = n;
                        });
                        // 拖动中仅更新 UI（@Link 联动书架实时预览），
                        // 松手/点击时才落库，避免逐 tick 写 preferences
                        if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                          Settings.setLibraryGridCols(n);
                        }
                      }
                    }
                  })
                    .width('100%')
                    .margin({ top: 4 })
                }
                .width('100%')
                .padding({
                  left: 24,
                  right: 24,
                  top: 6,
                  bottom: 6
                })
                .alignItems(HorizontalAlign.Start)
              }

              // 标记和按钮
              Text($r('app.string.lib_display_badges_group'))
                .fontSize(13)
                .fontColor(this.pal.sub)
                .width('100%')
                .padding({
                  left: 24,
                  right: 24,
                  top: 18,
                  bottom: 6
                })
              this.checkboxRow($r('app.string.lib_badge_downloaded'), this.showDownloadBadge, (v: boolean): void => {
                this.showDownloadBadge = v;
                Settings.setShowDownloadBadge(v);
              })
              this.checkboxRow($r('app.string.lib_badge_unread'), this.showUnreadBadge, (v: boolean): void => {
                this.showUnreadBadge = v;
                Settings.setShowUnreadBadge(v);
              })
              this.checkboxRow($r('app.string.lib_badge_local'), this.showLocalBadge, (v: boolean): void => {
                this.showLocalBadge = v;
                Settings.setShowLocalBadge(v);
              })
              this.checkboxRow($r('app.string.lib_badge_language'), this.showLanguageBadge, (v: boolean): void => {
                this.showLanguageBadge = v;
                Settings.setShowLanguageBadge(v);
              })

              // 标签
              Text($r('app.string.lib_display_tabs_group'))
                .fontSize(13)
                .fontColor(this.pal.sub)
                .width('100%')
                .padding({
                  left: 24,
                  right: 24,
                  top: 18,
                  bottom: 6
                })
              this.checkboxRow($r('app.string.lib_show_category_tabs'), this.showCategoryTabs, (v: boolean): void => {
                this.showCategoryTabs = v;
                Settings.setShowCategoryTabs(v);
              })
              this.checkboxRow($r('app.string.lib_show_manga_count'), this.showMangaCount, (v: boolean): void => {
                this.showMangaCount = v;
                Settings.setShowMangaCount(v);
              })
            }
            .width('100%')
            .padding({ bottom: 24 })
            .alignItems(HorizontalAlign.Start)
          }
          .height('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.TopStart)
        }
        .tabBar(this.tabBarLabel(2, $r('app.string.lib_sheet_tab_display')))
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

  // 书架内容区宽度（未测得时按手机宽度兜底）
  private gridW(): number {
    return this.contentW > 0 ? this.contentW : 360;
  }

  private filterValue(key: string): string {
    if (key === 'downloaded') {
      return this.filterDownloaded;
    }
    if (key === 'unread') {
      return this.filterUnread;
    }
    if (key === 'started') {
      return this.filterStarted;
    }
    if (key === 'bookmarked') {
      return this.filterBookmarked;
    }
    if (key === 'completed') {
      return this.filterCompleted;
    }
    if (key === 'tracked') {
      return this.filterTracked;
    }
    return 'ignore';
  }

  // 三态循环：ignore → include → exclude → ignore
  private applyFilter(key: string): void {
    const cur: string = this.filterValue(key);
    const next: string = cur === 'ignore' ? 'include' : (cur === 'include' ? 'exclude' : 'ignore');
    if (key === 'downloaded') {
      this.filterDownloaded = next;
    } else if (key === 'unread') {
      this.filterUnread = next;
    } else if (key === 'started') {
      this.filterStarted = next;
    } else if (key === 'bookmarked') {
      this.filterBookmarked = next;
    } else if (key === 'completed') {
      this.filterCompleted = next;
    } else if (key === 'tracked') {
      this.filterTracked = next;
    }
    Settings.setLibraryTriState(key, next);
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
    if (key === 'bookmarked') {
      return $r('app.string.lib_filter_bookmarked');
    }
    if (key === 'completed') {
      return $r('app.string.lib_filter_completed');
    }
    return $r('app.string.lib_filter_tracked');
  }

  private sortLabel(key: string): Resource {
    if (key === 'total') {
      return $r('app.string.lib_sort_total');
    }
    if (key === 'lastRead') {
      return $r('app.string.lib_sort_last_read');
    }
    if (key === 'lastUpdate') {
      return $r('app.string.lib_sort_last_update');
    }
    if (key === 'unread') {
      return $r('app.string.lib_sort_unread');
    }
    if (key === 'latestChapter') {
      return $r('app.string.lib_sort_latest_chapter');
    }
    if (key === 'fetchDate') {
      return $r('app.string.lib_sort_fetch_date');
    }
    if (key === 'dateAdded') {
      return $r('app.string.lib_sort_date_added');
    }
    if (key === 'random') {
      return $r('app.string.lib_sort_random');
    }
    return $r('app.string.lib_sort_alpha');
  }

  private viewLabel(mode: string): Resource {
    if (mode === 'comfortable') {
      return $r('app.string.lib_display_comfortable');
    }
    if (mode === 'cover') {
      return $r('app.string.lib_display_cover');
    }
    if (mode === 'list') {
      return $r('app.string.lib_display_list');
    }
    return $r('app.string.lib_display_compact');
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

  // 同项点击翻转方向（随机则重洗），异项切换保持当前方向
  private applySort(key: string): void {
    if (this.sortKey === key) {
      if (key === 'random') {
        this.onReshuffle();
        return;
      }
      this.sortAsc = !this.sortAsc;
      Settings.setLibrarySortAsc(this.sortAsc);
      return;
    }
    this.sortKey = key;
    Settings.setLibrarySort(key);
    if (key === 'random') {
      this.onReshuffle();
    }
  }

  private applyView(mode: string): void {
    if (this.viewMode === mode) {
      return;
    }
    // 显示模式切换：包 animateTo，配合书架 list/grid 分支的 transition 产生切换过渡
    this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, (): void => {
      this.viewMode = mode;
    });
    Settings.setLibraryView(mode);
  }
}
