import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { CategoryRepo } from '../data/Repos';
import { CategoryRecord } from '../model/Models';
import { ThemePalette } from '../common/Theme';
import { PageHeader } from './components/PageHeader';
import { AppIcon } from './components/AppIcon';
import { InputDialog } from './components/Dialogs';

// 分类管理：列表 + 新建 + 长按重命名/删除
@Component
export struct CategoriesPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State categories: CategoryRecord[] = [];

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
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
        title: '新建分类',
        placeholder: '分类名称',
        onConfirm: (text: string): void => {
          if (text.trim() !== '') {
            CategoryRepo.add(text.trim()).then(() => {
              this.reload();
            });
          }
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private showRename(cat: CategoryRecord): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: '重命名分类',
        placeholder: cat.name,
        onConfirm: (text: string): void => {
          if (text.trim() !== '') {
            CategoryRepo.rename(cat.id, text.trim()).then(() => {
              this.reload();
            });
          }
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
    const sheets: SheetInfo[] = [];
    sheets.push({
      title: '重命名',
      action: (): void => {
        this.showRename(cat);
      }
    });
    sheets.push({
      title: '删除',
      action: (): void => {
        CategoryRepo.remove(cat.id).then(() => {
          this.reload();
        });
      }
    });
    const opts: ActionSheetOptions = {
      title: cat.name,
      message: '',
      sheets: sheets
    };
    this.getUIContext().showActionSheet(opts);
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
        PageHeader({ title: '分类' }) {
          this.headerRight()
        }
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
                  Text('默认')
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
        .scrollBar(BarState.Off)
        .divider({
          strokeWidth: 1,
          color: this.pal.divider,
          startMargin: 16,
          endMargin: 16,
        })

        Text('长按分类可重命名或删除；删除后其中的漫画会移回「默认」分类')
          .fontSize(11)
          .fontColor(this.pal.sub)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(12)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
  }
}
