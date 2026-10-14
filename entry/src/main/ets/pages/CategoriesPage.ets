import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { CategoryRepo } from '../data/Repos';
import { CategoryRecord } from '../model/Models';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { PageHeader } from './components/PageHeader';
import { AppIcon } from './components/AppIcon';
import { InputDialog } from './components/Dialogs';
import { PickerSheet } from './components/PickerSheet';

// 分类管理：列表 + 新建 + 长按重命名/删除
@Component
export struct CategoriesPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @State categories: CategoryRecord[] = [];
  @State showItemSheet: boolean = false;
  private menuCat: CategoryRecord | null = null;

  aboutToAppear(): void {
    const context = Util.hostAbilityContext(this.getUIContext());
    AppDb.ready(context).then(() => {
      return CategoryRepo.list();
    }).then((list: CategoryRecord[]) => {
      this.categories = list;
    });
  }

  private reload(): void {
    CategoryRepo.list().then((list: CategoryRecord[]) => {
      this.categories = list;
    });
    AppStorage.setOrCreate('libDirty', (AppStorage.get<number>('libDirty') ?? 0) + 1);
  }

  private showAdd(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: $r('app.string.categories_add'),
        placeholder: $r('app.string.categories_name_placeholder'),
        onConfirm: (text: string): void => {
          if (text.trim() !== '') {
            CategoryRepo.add(text.trim()).then(() => {
              this.reload();
            });
          }
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private showRename(cat: CategoryRecord): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: $r('app.string.categories_rename_category'),
        placeholder: cat.name,
        onConfirm: (text: string): void => {
          if (text.trim() !== '') {
            CategoryRepo.rename(cat.id, text.trim()).then(() => {
              this.reload();
            });
          }
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private showItemMenu(cat: CategoryRecord): void {
    if (cat.id === 1) {
      return;
    }
    this.menuCat = cat;
    this.showItemSheet = true;
  }

  @Builder
  itemSheetBuilder() {
    PickerSheet({
      options: [$r('app.string.categories_rename'), $r('app.string.common_delete')],
      selectedIndex: -1,
      onPick: (index: number): void => {
        this.showItemSheet = false;
        const cat: CategoryRecord | null = this.menuCat;
        if (cat === null) {
          return;
        }
        if (index === 0) {
          this.showRename(cat);
        } else if (index === 1) {
          CategoryRepo.remove(cat.id).then(() => {
            this.reload();
          });
        }
      }
    })
  }

  @Builder
  headerRight() {
    AppIcon({ name: 'add', iconSize: 24 })
      .padding(8)
      .onClick(() => {
        this.showAdd();
      })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.categories_title') }) {
          this.headerRight()
        }
        Column() {
          List({ space: 0 }) {
            ForEach(this.categories, (cat: CategoryRecord) => {
              ListItem() {
                Row() {
                  AppIcon({ name: 'label', iconSize: 20 })
                  Text(cat.name)
                    .fontSize(16)
                    .fontColor(this.pal.text)
                    .layoutWeight(1)
                    .margin({ left: 14 })
                    .maxLines(1)
                  if (cat.id === 1) {
                    Text($r('app.string.common_default'))
                      .fontSize(11)
                      .fontColor(this.pal.sub)
                      .backgroundColor(this.pal.chip)
                      .borderRadius(8)
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  } else {
                    AppIcon({ name: 'expand_more', iconSize: 20 })
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .onClick(() => {
                  this.showItemMenu(cat);
                })
                .gesture(
                  LongPressGesture({ repeat: false })
                    .onAction((event: GestureEvent) => {
                      this.showItemMenu(cat);
                    })
                )
              }
            }, (cat: CategoryRecord) => `cat-${cat.id}-${cat.name}`)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .divider({
            strokeWidth: 1,
            color: this.pal.divider,
            startMargin: 16,
            endMargin: 16,
          })
        }
        .width('100%')
        .layoutWeight(1)

        Text($r('app.string.categories_hint'))
          .fontSize(11)
          .fontColor(this.pal.sub)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ left: 12, right: 12, top: 12, bottom: this.navBarH + 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
      .bindSheet($$this.showItemSheet, this.itemSheetBuilder(), {
        preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
        width: Bp.isWide(this.windowW) ? 560 : '100%',
        height: SheetSize.FIT_CONTENT,
        title: { title: this.menuCat === null ? '' : this.menuCat.name },
        detents: [SheetSize.FIT_CONTENT],
        dragBar: true,
        showClose: false,
        blurStyle: BlurStyle.COMPONENT_ULTRA_THICK
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function CategoriesBuilder() {
  CategoriesPage()
}
