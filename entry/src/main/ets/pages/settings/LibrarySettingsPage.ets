import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { AppKeys } from '../../common/AppKeys';
import { LibGrid, Util } from '../../common/Util';
import { AppDb } from '../../data/AppDb';
import { CategoryRepo } from '../../data/Repos';
import { CategoryRecord } from '../../model/Models';
import { NavGlassPage } from '../../common/HdsNavHost';
import { PrefGroup, PrefSelectRow, PrefSliderRow, PrefSwitchRow } from '../components/Prefs';

const SORT_VALUES: string[] = [
  'alpha', 'total', 'lastRead', 'lastUpdate', 'unread', 'latestChapter', 'fetchDate', 'dateAdded', 'random'
];
const VIEW_VALUES: string[] = ['compact', 'comfortable', 'cover', 'list'];

// 书架设置内容：默认归入分类/默认排序/视图/列数/徽标（筛选与三态逻辑在书架过滤弹层中）
@Component
export struct LibrarySettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 分类列表（默认归入分类选项）：挂载后异步加载，加载完成前不渲染该行
  @State categories: CategoryRecord[] = [];
  // 页面内容区宽度：列数滑条按其限制最小/最大列（与书架网格宽度一致）
  @State contentW: number = 0;

  aboutToAppear(): void {
    this.loadCategories();
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PrefGroup({ groupTitle: $r('app.string.categories_title') }) {
          if (this.categories.length > 0) {
            PrefSelectRow({
              title: $r('app.string.default_category'),
              options: this.defaultCategoryOptions(),
              selectedIndex: this.defaultCategoryIndex(),
              onSelectIndex: (index: number): void => {
                if (index === 0) {
                  Settings.setDefaultCategory(0);
                } else if (index === 1) {
                  Settings.setDefaultCategory(-1);
                } else {
                  Settings.setDefaultCategory(this.categories[index - 2].id);
                }
              }
            })
          }
        }

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
              this.bumpLibSettings();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_set_sort_asc'),
            initValue: Settings.getLibrarySortAsc(),
            apply: (value: boolean): void => {
              Settings.setLibrarySortAsc(value);
              this.bumpLibSettings();
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.lib_set_update_group') }) {
          PrefSwitchRow({
            title: $r('app.string.lib_set_update_wifi_only'),
            subtitle: $r('app.string.lib_set_update_wifi_only_sub'),
            initValue: Settings.getLibraryUpdateWifiOnly(),
            apply: (value: boolean): void => {
              Settings.setLibraryUpdateWifiOnly(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_set_update_charging_only'),
            subtitle: $r('app.string.lib_set_update_charging_only_sub'),
            initValue: Settings.getLibraryUpdateChargingOnly(),
            apply: (value: boolean): void => {
              Settings.setLibraryUpdateChargingOnly(value);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.lib_set_swipe_group') }) {
          PrefSelectRow({
            title: $r('app.string.lib_set_swipe_start'),
            options: [$r('app.string.action_mark_as_read'), $r('app.string.action_none')],
            selectedIndex: this.swipeStartIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setLibrarySwipeStartAction(index === 1 ? 'none' : 'read');
              this.bumpLibSettings();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.lib_set_swipe_end'),
            options: [$r('app.string.action_mark_as_read'), $r('app.string.action_none')],
            selectedIndex: this.swipeEndIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setLibrarySwipeEndAction(index === 1 ? 'none' : 'read');
              this.bumpLibSettings();
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
              this.bumpLibSettings();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSliderRow({
            title: $r('app.string.lib_set_grid_cols'),
            initValue: LibGrid.posOfCols(Settings.getLibraryGridCols(), this.gridW()),
            minValue: 0,
            maxValue: LibGrid.maxPos(this.gridW()),
            stepValue: 1,
            valueText: (pos: number): ResourceStr => pos === 0
              ? $r('app.string.lib_display_grid_auto')
              : `${LibGrid.colsOfPos(pos, this.gridW())}`,
            apply: (pos: number): void => {
              Settings.setLibraryGridCols(LibGrid.colsOfPos(pos, this.gridW()));
              this.bumpLibSettings();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_set_unread_badge'),
            initValue: Settings.getShowUnreadBadge(),
            apply: (value: boolean): void => {
              Settings.setShowUnreadBadge(value);
              this.bumpLibSettings();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_set_download_badge'),
            initValue: Settings.getShowDownloadBadge(),
            apply: (value: boolean): void => {
              Settings.setShowDownloadBadge(value);
              this.bumpLibSettings();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_badge_local'),
            initValue: Settings.getShowLocalBadge(),
            apply: (value: boolean): void => {
              Settings.setShowLocalBadge(value);
              this.bumpLibSettings();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_badge_language'),
            initValue: Settings.getShowLanguageBadge(),
            apply: (value: boolean): void => {
              Settings.setShowLanguageBadge(value);
              this.bumpLibSettings();
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.lib_display_tabs_group') }) {
          PrefSwitchRow({
            title: $r('app.string.lib_show_category_tabs'),
            initValue: Settings.getShowCategoryTabs(),
            apply: (value: boolean): void => {
              Settings.setShowCategoryTabs(value);
              this.bumpLibSettings();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.lib_show_manga_count'),
            initValue: Settings.getShowMangaCount(),
            apply: (value: boolean): void => {
              Settings.setShowMangaCount(value);
              this.bumpLibSettings();
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
    .onAreaChange((_old: Area, newArea: Area) => {
      const w = newArea.width;
      if (typeof w === 'number') {
        this.contentW = w;
      }
    })
  }

  // 书架内容区宽度近似（未测得时按手机宽度兜底）：
  // 本页与书架网格同为 Navigation 内容区全宽，量本级 Scroll 即可
  private gridW(): number {
    return this.contentW > 0 ? this.contentW : 360;
  }

  // 配置变更信号：书架页常驻挂载不会重建，需主动通知其重读配置（applySettings）
  private bumpLibSettings(): void {
    AppStorage.setOrCreate(AppKeys.LIB_SETTINGS_DIRTY,
      (AppStorage.get<number>(AppKeys.LIB_SETTINGS_DIRTY) ?? 0) + 1);
  }

  private async loadCategories(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    await AppDb.ready(context);
    this.categories = await CategoryRepo.list();
  }

  // 选项：自动（按内容类型）+ 每次都询问 + 各分类名
  private defaultCategoryOptions(): ResourceStr[] {
    const options: ResourceStr[] =
      [$r('app.string.default_category_auto'), $r('app.string.default_category_summary')];
    for (const cat of this.categories) {
      options.push(Util.categoryLabel(cat.name));
    }
    return options;
  }

  private defaultCategoryIndex(): number {
    const value: number = Settings.getDefaultCategory();
    if (value === 0) {
      return 0;
    }
    if (value < 0) {
      return 1;
    }
    const index: number = this.categories.findIndex((c: CategoryRecord): boolean => c.id === value);
    return index >= 0 ? index + 2 : 0;
  }

  private sortIndex(): number {
    const i = SORT_VALUES.indexOf(Settings.getLibrarySort());
    return i >= 0 ? i : 0;
  }

  private viewIndex(): number {
    const i = VIEW_VALUES.indexOf(Settings.getLibraryView());
    return i >= 0 ? i : 0;
  }

  // 滑动动作选项索引：0 = 标记已读（'read'），1 = 无（'none'）
  private swipeStartIndex(): number {
    return Settings.getLibrarySwipeStartAction() === 'none' ? 1 : 0;
  }

  private swipeEndIndex(): number {
    return Settings.getLibrarySwipeEndAction() === 'none' ? 1 : 0;
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
