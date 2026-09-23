import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, CategoryRepo } from '../data/Repos';
import { UpdateService } from '../data/UpdateService';
import { DownloadService } from '../data/DownloadService';
import { Settings } from '../common/Settings';
import { MangaRecord, CategoryRecord } from '../model/Models';
import { DetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { MangaCard, CategoryChip } from './components/MangaCard';
import { CategoryDialog } from './components/Dialogs';
import { EmptyScreen } from './components/EmptyScreen';
import { AppIcon } from './components/AppIcon';

// 书架页：分类 + 收藏网格 + 搜索/过滤/更多
@Component
export struct LibraryPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @State mangas: MangaRecord[] = [];
  @State categories: CategoryRecord[] = [];
  @State selectedCategory: number = 0;
  @State unreadMap: Record<string, number> = {};
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State searchOpen: boolean = false;
  @State searchQuery: string = '';
  @State filterValue: string = 'none';
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;

  aboutToAppear(): void {
    this.filterValue = Settings.getLibraryFilter();
    this.loadData();
  }

  onLibDirty(): void {
    this.loadData();
  }

  async loadData(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await AppDb.ready(context);
    this.categories = await CategoryRepo.list();
    this.mangas = await MangaRepo.getLibrary();
    const map: Record<string, number> = {};
    for (const manga of this.mangas) {
      map[`${manga.id}`] = await ChapterRepo.unreadCount(manga.id);
    }
    this.unreadMap = map;
    this.loading = false;
  }

  async refreshLibrary(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const newCount = await UpdateService.refreshLibrary(context);
      Util.toastRes(this.getUIContext(), newCount > 0 ? $r('app.string.updates_found_new', newCount) : $r('app.string.updates_no_new'));
      await this.loadData();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.updates_refresh_failed'));
    }
    this.refreshing = false;
  }

  shownMangas(): MangaRecord[] {
    let list = this.mangas;
    if (this.selectedCategory > 0) {
      list = list.filter((m: MangaRecord): boolean => m.categoryId === this.selectedCategory);
    }
    const q = this.searchQuery.trim().toLowerCase();
    if (q !== '') {
      list = list.filter((m: MangaRecord): boolean => m.title.toLowerCase().includes(q));
    }
    if (this.filterValue === 'unread') {
      list = list.filter((m: MangaRecord): boolean => (this.unreadMap[`${m.id}`] || 0) > 0);
    } else if (this.filterValue === 'downloaded') {
      const downloaded = new Set(DownloadService.downloadedMangaIds());
      list = list.filter((m: MangaRecord): boolean => downloaded.has(m.id));
    } else if (this.filterValue === 'uncompleted') {
      list = list.filter((m: MangaRecord): boolean => m.status !== 'completed');
    }
    return list;
  }

  // 溢出菜单：更新分类（仅刷新当前分类）
  async refreshCategoryNow(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const newCount = await UpdateService.refreshCategory(context, this.selectedCategory);
      Util.toastRes(this.getUIContext(), newCount > 0 ? $r('app.string.updates_found_new', newCount) : $r('app.string.updates_no_new'));
      await this.loadData();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.updates_refresh_failed'));
    }
    this.refreshing = false;
  }

  openRandomManga(): void {
    const list = this.shownMangas();
    if (list.length === 0) {
      return;
    }
    const idx = Math.floor(Math.random() * list.length);
    this.openDetail(list[idx]);
  }

  showFilterSheet(): void {
    const labels: string[] = [
      Util.resStr(this.getUIContext(), $r('app.string.common_all')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_filter_unread')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_filter_downloaded')),
      Util.resStr(this.getUIContext(), $r('app.string.lib_set_filter_uncompleted')),
    ];
    const values: string[] = ['none', 'unread', 'downloaded', 'uncompleted'];
    const sheets: SheetInfo[] = [];
    labels.forEach((label: string, i: number) => {
      sheets.push({
        title: label,
        action: (): void => {
          this.filterValue = values[i];
          Settings.setLibraryFilter(values[i]);
        }
      });
    });
    const opts: ActionSheetOptions = {
      title: $r('app.string.action_filter'),
      message: '',
      sheets: sheets
    };
    this.getUIContext().showActionSheet(opts);
  }

  openDetail(record: MangaRecord): void {
    const params: DetailParams = { mangaId: record.id };
    this.pathStack.pushPathByName('MangaDetail', params);
  }

  showCategoryMenu(record: MangaRecord): void {
    const dialog = new CustomDialogController({
      builder: CategoryDialog({
        categories: this.categories,
        onPick: (categoryId: number): void => {
          MangaRepo.setCategory(record.id, categoryId).then(() => {
            this.loadData();
          });
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  @Builder
  libMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.action_update_library') })
        .onClick(() => {
          this.refreshLibrary();
        })
      MenuItem({ content: $r('app.string.action_update_category') })
        .onClick(() => {
          this.refreshCategoryNow();
        })
      MenuItem({ content: $r('app.string.action_open_random_manga') })
        .onClick(() => {
          this.openRandomManga();
        })
    }
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        if (this.searchOpen) {
          TextInput({ text: this.searchQuery, placeholder: $r('app.string.library_search_hint') })
            .layoutWeight(1)
            .height(38)
            .fontSize(15)
            .fontColor(this.pal.text)
            .placeholderColor(this.pal.sub)
            .backgroundColor(this.pal.chip)
            .borderRadius(19)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.searchQuery = value;
            })
          AppIcon({ name: 'close', iconSize: 22, tint: this.pal.text })
            .padding({ left: 12 })
            .onClick(() => {
              this.searchOpen = false;
              this.searchQuery = '';
            })
        } else {
          Text($r('app.string.library_title'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
          Text(`${this.shownMangas().length}`)
            .fontSize(13)
            .fontColor(this.pal.sub)
            .backgroundColor(this.pal.chip)
            .borderRadius(10)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .margin({ left: 8 })
          if (this.refreshing) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(this.pal.primary)
              .margin({ left: 8 })
          }
          Blank()
            .layoutWeight(1)
          AppIcon({ name: 'search', iconSize: 22, tint: this.pal.text })
            .padding({ left: 12 })
            .onClick(() => {
              this.searchOpen = true;
            })
          AppIcon({ name: 'filter_list', iconSize: 22, tint: this.filterValue !== 'none' ? this.pal.primary : this.pal.text })
            .padding({ left: 12 })
            .onClick(() => {
              this.showFilterSheet();
            })
          AppIcon({ name: 'more_vert', iconSize: 22, tint: this.pal.text })
            .padding({ left: 12 })
            .bindMenu(this.libMenu)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 分类 chips
      Scroll() {
        Row({ space: 8 }) {
          Text($r('app.string.common_all'))
            .fontSize(13)
            .fontColor(this.selectedCategory === 0 ? '#FFFFFF' : this.pal.text)
            .backgroundColor(this.selectedCategory === 0 ? this.pal.primary : this.pal.chip)
            .borderRadius(14)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick(() => {
              this.selectedCategory = 0;
            })
          ForEach(this.categories, (cat: CategoryRecord) => {
            CategoryChip({
              category: cat,
              selected: this.selectedCategory === cat.id,
              onChipClick: (picked: CategoryRecord): void => {
                this.selectedCategory = picked.id;
              },
            })
          }, (cat: CategoryRecord) => `chip-${cat.id}-${cat.name}`)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .margin({ bottom: 4 })

      // 网格
      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.pal.primary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.shownMangas().length === 0) {
        Column() {
          EmptyScreen({
            message: this.searchQuery.trim() !== '' || this.filterValue !== 'none'
              ? $r('app.string.library_no_match') : $r('app.string.library_empty')
          })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.shownMangas(), (record: MangaRecord) => {
            GridItem() {
              MangaCard({
                record: record,
                badge: this.unreadMap[`${record.id}`] > 0 ? `${this.unreadMap[`${record.id}`]}` : '',
                onCardClick: (r: MangaRecord): void => {
                  this.openDetail(r);
                },
                onCardLongPress: (r: MangaRecord): void => {
                  this.showCategoryMenu(r);
                },
              })
            }
          }, (record: MangaRecord) => `lib-${record.id}-${record.inLibrary}`)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(16)
        .padding({ left: 16, right: 16, top: 8 })
        .contentEndOffset(this.navBarH + 76)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }
}
