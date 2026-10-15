import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { UpdatesRepo, UpdatesQuery, CategoryRepo } from '../data/Repos';
import { DownloadService } from '../data/DownloadService';
import { UpdateService } from '../data/UpdateService';
import { UpdateItem, CategoryRecord } from '../model/Models';
import { DetailParams } from '../model/RouteParams';
import { ContentOpen } from './ContentOpen';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { LimitedBody } from './components/LimitedBody';
import { Settings } from '../common/Settings';
import { Util } from '../common/Util';
import { EmptyScreen } from './components/EmptyScreen';
import { AppIcon } from './components/AppIcon';
import { SmartImage } from './components/SmartImage';
import { UpdatesFilterSheet } from './components/UpdatesFilterSheet';

// 更新页：书架最新章节（对齐 Mihon UpdatesScreen）
// 顶栏三操作：筛选（FilterList）/ 查看即将推出（CalendarMonth）/ 更新书架（Refresh）
@Component
export struct UpdatesPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;
  @State items: UpdateItem[] = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State showFilterSheet: boolean = false;
  // 筛选状态（对齐 Mihon UpdatesPreferences）
  @State fDownloaded: string = 'ignore';
  @State fUnread: string = 'ignore';
  @State fStarted: string = 'ignore';
  @State fBookmarked: string = 'ignore';
  @State includedCats: number[] = [];
  @State excludedCats: number[] = [];
  @State categories: CategoryRecord[] = [];

  aboutToAppear(): void {
    this.fDownloaded = Settings.getUpdatesTriState('downloaded');
    this.fUnread = Settings.getUpdatesTriState('unread');
    this.fStarted = Settings.getUpdatesTriState('started');
    this.fBookmarked = Settings.getUpdatesTriState('bookmarked');
    this.includedCats = Settings.getUpdatesIncludedCategories();
    this.excludedCats = Settings.getUpdatesExcludedCategories();
    this.loadData();
    this.loadCategories();
  }

  onLibDirty(): void {
    this.loadData();
  }

  async loadCategories(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    await AppDb.ready(context);
    this.categories = await CategoryRepo.list();
  }

  private filterActive(): boolean {
    return this.fDownloaded !== 'ignore' || this.fUnread !== 'ignore' ||
      this.fStarted !== 'ignore' || this.fBookmarked !== 'ignore' ||
      this.includedCats.length > 0 || this.excludedCats.length > 0;
  }

  private applyTriState(key: string, v: string): void {
    if (key === 'downloaded') {
      this.fDownloaded = v;
    } else if (key === 'unread') {
      this.fUnread = v;
    } else if (key === 'started') {
      this.fStarted = v;
    } else {
      this.fBookmarked = v;
    }
    Settings.setUpdatesTriState(key, v);
    this.loadData();
  }

  async loadData(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    await AppDb.ready(context);
    const query = new UpdatesQuery();
    query.downloaded = this.fDownloaded;
    query.unread = this.fUnread;
    query.started = this.fStarted;
    query.bookmarked = this.fBookmarked;
    query.includedCategories = this.includedCats;
    query.excludedCategories = this.excludedCats;
    let items = await UpdatesRepo.filteredChapters(query, 300);
    // 已下载筛选走内存过滤（下载状态在文件系统）
    if (query.downloaded === 'include' || query.downloaded === 'exclude') {
      const downloaded = DownloadService.downloadedChapterIdSet();
      const wantDownloaded = query.downloaded === 'include';
      items = items.filter((it: UpdateItem): boolean => {
        return wantDownloaded === downloaded.has(it.chapterId);
      });
    }
    this.items = items;
    this.loading = false;
  }

  async refreshLibrary(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const newCount = await UpdateService.refreshLibrary(context);
      if (newCount > 0) {
        Util.toastRes(this.getUIContext(), $r('app.string.updates_found_new'), [newCount]);
      } else {
        Util.toastRes(this.getUIContext(), $r('app.string.updates_no_new'));
      }
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.updates_refresh_failed'));
    }
    this.refreshing = false;
    await this.loadData();
  }

  private openDetail(mangaId: number): void {
    const params: DetailParams = { mangaId: mangaId };
    this.pathStack.pushPathByName('MangaDetail', params);
  }

  @Builder
  filterSheetBuilder() {
    UpdatesFilterSheet({
      initDownloaded: this.fDownloaded,
      initUnread: this.fUnread,
      initStarted: this.fStarted,
      initBookmarked: this.fBookmarked,
      initIncluded: this.includedCats,
      initExcluded: this.excludedCats,
      categories: this.categories,
      showFilterTab: true,
      onTriStateChanged: (key: string, v: string): void => {
        this.applyTriState(key, v);
      },
      onCategoriesChanged: (included: number[], excluded: number[]): void => {
        this.includedCats = included;
        this.excludedCats = excluded;
        Settings.setUpdatesIncludedCategories(included);
        Settings.setUpdatesExcludedCategories(excluded);
        this.loadData();
      }
    })
  }

  build() {
    LimitedBody() {
      this.bodyContent()
    }
  }

  // 页面主体：LimitedBody 承载，大屏限宽居中，窄屏全宽
  @Builder
  bodyContent() {
    Column() {
      // 顶栏：标题 + 筛选/日历/刷新（对齐 Mihon UpdatesAppBar）
      Row() {
        Text($r('app.string.updates_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        if (this.refreshing) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(this.pal.primary)
            .margin({ left: 8 })
        }
        AppIcon({ name: 'filter_list', iconSize: 22, tint: this.filterActive() ? this.pal.primary : this.pal.text })
          .padding({ left: 12 })
          .onClick(() => {
            this.showFilterSheet = true;
          })
          .bindSheet($$this.showFilterSheet, this.filterSheetBuilder(), {
            preferType: Bp.sheetType(this.windowW),
            width: Bp.sheetWidth(this.windowW),
            height: Bp.sheetHeight(this.windowW),
            detents: ['60%', SheetSize.LARGE],
            showClose: false,
            dragBar: true,
            backgroundColor: this.pal.bg
          })
        AppIcon({ name: 'calendar_month', iconSize: 22, tint: this.pal.text })
          .padding({ left: 12 })
          .onClick(() => {
            this.pathStack.pushPathByName('Upcoming', null);
          })
        AppIcon({ name: 'refresh', iconSize: 22, tint: this.pal.text })
          .padding({ left: 12 })
          .onClick(() => {
            this.refreshLibrary();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.pal.primary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.items.length === 0) {
        Column() {
          EmptyScreen({ message: $r('app.string.updates_empty') })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          List({ space: 0 }) {
            ForEach(this.items, (item: UpdateItem) => {
              ListItem() {
                Row({ space: 12 }) {
                  // 封面（无封面时 SmartImage 内部渲染默认封面占位）；
                  // UpdateItem 不含 sourceKey，传空串走网络/缓存通用路径
                  SmartImage({
                    url: item.coverUrl,
                    sourceKey: '',
                    fit: ImageFit.Cover,
                    placeholderIconSize: 20
                  })
                    .width(44)
                    .height(60)
                    .borderRadius(6)
                    .backgroundColor(this.pal.chip)
                    // HitTestMode.Block 阻断冒泡：避免同时触发整行 onClick（直接打开阅读器）
                    .hitTestBehavior(HitTestMode.Block)
                    .onClick(() => {
                      this.openDetail(item.mangaId);
                    })
                  Column() {
                    Text(item.mangaTitle)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.pal.text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .opacity(item.read ? 0.38 : 1)
                    Row({ space: 4 }) {
                      if (!item.read) {
                        Circle()
                          .width(8)
                          .height(8)
                          .fill(this.pal.primary)
                      }
                      if (item.bookmark) {
                        AppIcon({ name: 'bookmark_filled', iconSize: 12, tint: this.pal.primary })
                      }
                      Text(item.chapterName)
                        .fontSize(13)
                        .fontColor(this.pal.sub)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                        .opacity(item.read ? 0.38 : 1)
                    }
                    .margin({ top: 4 })
                    .alignItems(VerticalAlign.Center)
                    Text(Util.timeAgo(item.dateUpload))
                      .fontSize(11)
                      .fontColor(this.pal.sub)
                      .margin({ top: 4 })
                      .opacity(item.read ? 0.38 : 1)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .onClick(() => {
                  ContentOpen.open(this.pathStack, item.mangaId, item.chapterId);
                })
              }
            }, (item: UpdateItem) => `upd-${item.chapterId}-${item.coverUrl}-${item.read}-${item.bookmark}`)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .contentEndOffset(this.navBarH + 76)
          .divider({
            strokeWidth: 1,
            color: this.pal.divider,
            startMargin: 72,
            endMargin: 16,
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }
}
