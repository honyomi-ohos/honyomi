import { curves } from '@kit.ArkUI';
import { AppDb } from '../data/AppDb';
import { SheetPreset } from './components/SheetPreset';
import { CategoryRepo } from '../data/Repos';
import { CategoryRecord, ContentType } from '../model/Models';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { AppKeys } from '../common/AppKeys';
import { NavGlassPage, NavGlassAction } from '../common/HdsNavHost';
import { AppIcon } from './components/AppIcon';
import { InputDialog } from './components/Dialogs';
import { PickerSheet } from './components/PickerSheet';

// 分类管理：列表 + 新建 + 点击重命名/删除 + 长按拖拽排序
// 拖拽参考官方 grid-drag-sort 示例的"直接拖拽"模式：
// 长按浮起（translate/zIndex/scale）→ 跟手位移 → 越过半行高时弹簧动画换位 → 松手持久化
@Component
export struct CategoriesPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @State categories: CategoryRecord[] = [];
  @State showItemSheet: boolean = false;
  // Index 根节点 Esc 广播：关闭条目操作弹层（计数器递增触发）
  @StorageLink('sheetEsc') @Watch('onSheetEsc') sheetEsc: number = 0;
  @State dragId: number = -1;
  @State offsetY: number = 0;
  @State rowH: number = 0;
  private menuCat: CategoryRecord | null = null;
  private dragRefOffsetY: number = 0;
  private panning: boolean = false;
  private orderDirty: boolean = false;
  // 标题栏滚动联动：绑定分类列表
  private listScroller: Scroller = new Scroller();

  // Esc 广播：关闭条目操作半模态弹层
  onSheetEsc(): void {
    if (this.showItemSheet) {
      this.showItemSheet = false;
    }
  }

  aboutToAppear(): void {
    const context = Util.hostAbilityContext(this.getUIContext());
    AppDb.ready(context).then(() => {
      return CategoryRepo.list();
    }).then((list: CategoryRecord[]) => {
      this.categories = list;
    }).catch((_e: Error): void => {
      Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
    });
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
          }).catch((_e: Error): void => {
            Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
          });
        }
      }
    })
  }

  build() {
    NavGlassPage({
      title: $r('app.string.categories_title'),
      actions: [{
        icon: $r('app.media.ic_add'),
        action: (): void => {
          this.showAdd();
        }
      }],
      scroller: this.listScroller
    }) {
      this.bodyContent()
    }
  }

  // 页面主体：滚动容器全宽（滚动条贴窗口边），内容列经 contentInset 限宽居中（720 上限）
  private inset(): number {
    return Bp.contentInset(this.windowW);
  }

  @Builder
  bodyContent() {
    Column() {
      Column() {
        List({ space: 0, scroller: this.listScroller }) {
          ForEach(this.categories, (cat: CategoryRecord) => {
            ListItem() {
              Row() {
                AppIcon({ name: 'drag_handle', iconSize: 20 })
                Text(Util.categoryLabel(cat.name))
                  .fontSize(16)
                  .fontColor(this.pal.text)
                  .layoutWeight(1)
                  .margin({ left: 14 })
                  .maxLines(1)
                if (this.isDefaultCat(cat)) {
                  Text($r('app.string.common_default'))
                    .fontSize(11)
                    .fontColor(this.pal.sub)
                    .backgroundColor(this.pal.chip)
                    .borderRadius(8)
                    .padding({
                      left: 8,
                      right: 8,
                      top: 3,
                      bottom: 3
                    })
                } else {
                  AppIcon({ name: 'expand_more', iconSize: 20 })
                }
              }
              .width('100%')
              .padding({
                left: 16 + this.inset(),
                right: 16 + this.inset(),
                top: 14,
                bottom: 14
              })
              .backgroundColor(this.dragId === cat.id ? this.pal.card : Color.Transparent)
              .borderRadius(this.dragId === cat.id ? 12 : 0)
              .shadow(this.dragId === cat.id
                ? {
                  radius: 20,
                  offsetX: 0,
                  offsetY: 6,
                  color: this.isDark ? '#99000000' : '#2E000000'
                }
                : { radius: 0 })
              .onClick(() => {
                this.showItemMenu(cat);
              })
            }
            .zIndex(this.dragId === cat.id ? 1 : 0)
            .scale(this.dragId === cat.id ? { x: 1.02, y: 1.02 } : { x: 1, y: 1 })
            .translate({ y: this.dragId === cat.id ? this.offsetY : 0 })
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              // 行高仅在首行测量一次（各行等高，作为换位阈值）
              if (this.rowH <= 0 && typeof newArea.height === 'number') {
                this.rowH = newArea.height;
              }
            })
            .gesture(
              GestureGroup(GestureMode.Sequence,
                LongPressGesture({ repeat: false, duration: 300 })
                  .onAction(() => {
                    // 长按浮起待拖拽
                    this.getUIContext().animateTo({ duration: 120, curve: Curve.Friction }, (): void => {
                      this.dragId = cat.id;
                      this.offsetY = 0;
                    });
                  })
                  .onActionEnd(() => {
                    // 长按后未拖动直接松手：取消浮起
                    if (!this.panning) {
                      this.endDrag();
                    }
                  }),
                PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 0 })
                  .onActionStart(() => {
                    this.panning = true;
                    this.dragRefOffsetY = 0;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.offsetY = event.offsetY - this.dragRefOffsetY;
                    const index: number =
                      this.categories.findIndex((c: CategoryRecord): boolean => c.id === this.dragId);
                    if (this.rowH <= 0 || index < 0) {
                      return;
                    }
                    // 越过半行高时弹簧动画换位（其余行滑动让位）
                    this.getUIContext().animateTo(
                      { curve: curves.interpolatingSpring(0, 1, 400, 38) }, (): void => {
                      if (this.offsetY >= this.rowH / 2 && index < this.categories.length - 1) {
                        this.offsetY -= this.rowH;
                        this.dragRefOffsetY += this.rowH;
                        this.itemMove(index, index + 1);
                      } else if (this.offsetY <= -this.rowH / 2 && index > 0) {
                        this.offsetY += this.rowH;
                        this.dragRefOffsetY -= this.rowH;
                        this.itemMove(index, index - 1);
                      }
                    });
                  })
                  .onActionEnd(() => {
                    this.panning = false;
                    this.endDrag();
                  })
                  .onActionCancel(() => {
                    this.panning = false;
                    this.endDrag();
                  })
              )
            )
          }, (cat: CategoryRecord) => `cat-${cat.id}-${cat.name}`)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .divider({
          strokeWidth: 1,
          color: this.pal.divider,
          startMargin: 16 + this.inset(),
          endMargin: 16 + this.inset(),
        })
      }
      .width('100%')
      .layoutWeight(1)

      Text($r('app.string.categories_hint'))
        .fontSize(11)
        .fontColor(this.pal.sub)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({
          left: 12,
          right: 12,
          top: 12,
          bottom: this.navBarH + 12
        })
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showItemSheet, this.itemSheetBuilder(),
      SheetPreset.fit(this.windowW, {
        title: this.menuCat === null ? '' : Util.categoryLabel(this.menuCat.name),
        showClose: false
      }))
  }

  private reload(): void {
    CategoryRepo.list().then((list: CategoryRecord[]) => {
      this.categories = list;
    }).catch((_e: Error): void => {
      Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
    });
    AppStorage.setOrCreate(AppKeys.LIB_DIRTY, (AppStorage.get<number>(AppKeys.LIB_DIRTY) ?? 0) + 1);
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
            }).catch((_e: Error): void => {
              Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
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
        placeholder: Util.categoryLabel(cat.name),
        onConfirm: (text: string): void => {
          if (text.trim() !== '') {
            CategoryRepo.rename(cat.id, text.trim()).then(() => {
              this.reload();
            }).catch((_e: Error): void => {
              Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
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

  // 默认分类：id = 1 回退分类 + 内置三分类（漫画/小说/动画），均不可编辑
  private isDefaultCat(cat: CategoryRecord): boolean {
    return cat.id === 1 || ContentType.isBuiltinCategory(cat.name);
  }

  private showItemMenu(cat: CategoryRecord): void {
    if (this.isDefaultCat(cat)) {
      return;
    }
    this.menuCat = cat;
    this.showItemSheet = true;
  }

  // 数组内移动分类（换位），标记顺序已变更
  private itemMove(index: number, newIndex: number): void {
    if (newIndex < 0 || newIndex >= this.categories.length || index === newIndex || index < 0) {
      return;
    }
    const moved: CategoryRecord = this.categories.splice(index, 1)[0];
    this.categories.splice(newIndex, 0, moved);
    this.orderDirty = true;
  }

  // 松手：浮起复位 + 持久化（顺序有变化时）
  private endDrag(): void {
    const dragged: number = this.dragId;
    this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 400, 38) }, (): void => {
      this.dragId = -1;
      this.offsetY = 0;
    });
    if (dragged >= 0 && this.orderDirty) {
      this.orderDirty = false;
      this.persistOrder();
    }
  }

  // 持久化当前顺序到数据库并刷新书架分类 tab
  private persistOrder(): void {
    const ids: number[] = [];
    for (const cat of this.categories) {
      ids.push(cat.id);
    }
    CategoryRepo.reorder(ids).then(() => {
      AppStorage.setOrCreate(AppKeys.LIB_DIRTY, (AppStorage.get<number>(AppKeys.LIB_DIRTY) ?? 0) + 1);
    }).catch((_e: Error): void => {
      this.reload();
      Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
    });
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function CategoriesBuilder() {
  CategoriesPage()
}
