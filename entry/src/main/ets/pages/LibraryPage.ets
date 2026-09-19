import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, CategoryRepo } from '../data/Repos';
import { UpdateService } from '../data/UpdateService';
import { MangaRecord, CategoryRecord } from '../model/Models';
import { DetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { MangaCard, CategoryChip } from './components/MangaCard';
import { InputDialog, CategoryDialog } from './components/Dialogs';

// 书架页：分类 + 收藏网格 + 刷新
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
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;

  aboutToAppear(): void {
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
      Util.toast(this.getUIContext(), newCount > 0 ? `发现 ${newCount} 个新章节` : '没有新章节');
      await this.loadData();
    } catch (e) {
      Util.toast(this.getUIContext(), '刷新失败，请检查网络');
    }
    this.refreshing = false;
  }

  shownMangas(): MangaRecord[] {
    if (this.selectedCategory === 0) {
      return this.mangas;
    }
    return this.mangas.filter((m: MangaRecord): boolean => m.categoryId === this.selectedCategory);
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

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('书架')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        Text(this.refreshing ? '刷新中…' : '⟳')
          .fontSize(this.refreshing ? 14 : 24)
          .fontColor(this.pal.primary)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.refreshLibrary();
          })
        Text('＋')
          .fontSize(22)
          .fontColor(this.pal.primary)
          .padding({ left: 8 })
          .onClick(() => {
            this.showAddCategoryDialog();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 分类 chips
      Scroll() {
        Row({ space: 8 }) {
          Text('全部')
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
          Text('书架空空如也')
            .fontSize(15)
            .fontColor(this.pal.sub)
          Text('去「浏览」页发现并收藏漫画吧')
            .fontSize(13)
            .fontColor(this.pal.sub)
            .margin({ top: 8 })
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

  private showAddCategoryDialog(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: '新建分类',
        placeholder: '分类名称',
        onConfirm: (text: string): void => {
          if (text.trim() !== '') {
            CategoryRepo.add(text.trim()).then(() => {
              this.loadData();
            });
          }
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }
}
