import { CategoryRecord, DuplicateManga } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { KeyCode } from '@kit.InputKit';
import { AppIcon } from './AppIcon';
import { SmartImage } from './SmartImage';
import { SourceRegistry } from '../../source/Source';
import { BackupOptions } from '../../data/BackupService';

// 文本输入弹窗（新建分类 / 导入漫画命名 / 敏感偏好输入）
@CustomDialog
export struct InputDialog {
  controller?: CustomDialogController;
  title: Resource | string = '';
  placeholder: Resource | string = '';
  initialText: string = '';
  // true 时使用系统密码输入框（自动掩码 + 明文切换图标）
  password: boolean = false;
  @State inputText: string = '';
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onConfirm: (text: string) => void = (_t: string) => {
  };
  onClose: () => void = () => {
  };

  aboutToAppear(): void {
    this.inputText = this.initialText;
  }

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
      TextInput({
        placeholder: this.placeholder,
        text: this.inputText,
      })
        .type(this.password ? InputType.Password : InputType.Normal)
        .defaultFocus(true)
        .onChange((value: string) => {
          this.inputText = value;
        })
        .enterKeyType(EnterKeyType.Done)
        .onSubmit(() => {
          this.dismiss();
          this.onConfirm(this.inputText);
        })
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.dismiss();
          })
        Button($r('app.string.common_ok'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .onClick(() => {
            this.dismiss();
            this.onConfirm(this.inputText);
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

// 账密登录弹窗（用户名 + 密码一次输入；密码框为系统密码输入框）
@CustomDialog
export struct CredentialsDialog {
  controller?: CustomDialogController;
  title: Resource | string = '';
  usernamePlaceholder: Resource | string = '';
  passwordPlaceholder: Resource | string = '';
  @State username: string = '';
  @State password: string = '';
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onConfirm: (username: string, password: string) => void = (_u: string, _p: string) => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
      TextInput({
        placeholder: this.usernamePlaceholder,
        text: this.username,
      })
        .defaultFocus(true)
        .enterKeyType(EnterKeyType.Next)
        .onChange((value: string) => {
          this.username = value;
        })
        .onSubmit(() => {
          // 用户名回车跳密码框（手动迁移焦点，失败时仍可 Tab 切换）
          try {
            this.getUIContext().getFocusController().requestFocus('credPasswordKey');
          } catch (e) {
          }
        })
      TextInput({
        placeholder: this.passwordPlaceholder,
        text: this.password,
      })
        .type(InputType.Password)
        .id('credPasswordKey')
        .enterKeyType(EnterKeyType.Done)
        .onChange((value: string) => {
          this.password = value;
        })
        .onSubmit(() => {
          this.dismiss();
          this.onConfirm(this.username.trim(), this.password);
        })
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.dismiss();
          })
        Button($r('app.string.common_ok'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .onClick(() => {
            this.dismiss();
            this.onConfirm(this.username.trim(), this.password);
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

// 双/三输入弹窗（Bangumi 镜像：API / 图片 / next 地址一次编辑，留空恢复默认）
@CustomDialog
export struct DualInputDialog {
  controller?: CustomDialogController;
  title: Resource | string = '';
  firstPlaceholder: Resource | string = '';
  secondPlaceholder: Resource | string = '';
  // 第三个输入（可选）：留空串不渲染该输入框
  thirdPlaceholder: Resource | string = '';
  initialFirst: string = '';
  initialSecond: string = '';
  initialThird: string = '';
  @State first: string = '';
  @State second: string = '';
  @State third: string = '';
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onConfirm: (first: string, second: string, third: string) => void =
    (_f: string, _s: string, _t: string) => {
    };
  onClose: () => void = () => {
  };

  aboutToAppear(): void {
    this.first = this.initialFirst;
    this.second = this.initialSecond;
    this.third = this.initialThird;
  }

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
      TextInput({
        placeholder: this.firstPlaceholder,
        text: this.first,
      })
        .defaultFocus(true)
        .enterKeyType(EnterKeyType.Next)
        .onChange((value: string) => {
          this.first = value;
        })
        .onSubmit(() => {
          // 首个输入框回车跳第二个（手动迁移焦点，失败时仍可 Tab 切换）
          try {
            this.getUIContext().getFocusController().requestFocus('dualSecondKey');
          } catch (e) {
          }
        })
      TextInput({
        placeholder: this.secondPlaceholder,
        text: this.second,
      })
        .id('dualSecondKey')
        .enterKeyType(this.thirdPlaceholder !== '' ? EnterKeyType.Next : EnterKeyType.Done)
        .onChange((value: string) => {
          this.second = value;
        })
        .onSubmit(() => {
          if (this.thirdPlaceholder !== '') {
            // 第二个输入框回车跳第三个
            try {
              this.getUIContext().getFocusController().requestFocus('dualThirdKey');
            } catch (e) {
            }
          } else {
            this.confirm();
          }
        })
      if (this.thirdPlaceholder !== '') {
        TextInput({
          placeholder: this.thirdPlaceholder,
          text: this.third,
        })
          .id('dualThirdKey')
          .enterKeyType(EnterKeyType.Done)
          .onChange((value: string) => {
            this.third = value;
          })
          .onSubmit(() => {
            this.confirm();
          })
      }
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.dismiss();
          })
        Button($r('app.string.common_ok'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .onClick(() => {
            this.confirm();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  private confirm(): void {
    this.dismiss();
    this.onConfirm(this.first.trim(), this.second.trim(), this.third.trim());
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

// 分类选择弹窗
@CustomDialog
export struct CategoryDialog {
  controller?: CustomDialogController;
  categories: CategoryRecord[] = [];
  // 当前分类 id（快速改分类/入库选分类时高亮，-1 表示不高亮）
  selectedId: number = -1;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onPick: (categoryId: number) => void = (_id: number) => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: 8 }) {
      Text($r('app.string.dialog_pick_category'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .margin({ bottom: 8 })
      ForEach(this.categories, (cat: CategoryRecord) => {
        Text(Util.categoryLabel(cat.name))
          .fontSize(15)
          .fontColor(cat.id === this.selectedId ? this.pal.onPrimary : this.pal.text)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(12)
          .borderRadius(10)
          .backgroundColor(cat.id === this.selectedId ? this.pal.primary : this.pal.chip)
          .onClick(() => {
            this.dismiss();
            this.onPick(cat.id);
          })
      }, (cat: CategoryRecord) => `cat-${cat.id}`)
    }
    .padding(20)
    .width('100%')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

// 多选分类弹窗（对齐 Mihon ChangeCategoryDialog）：
// 分类多选 + 编辑分类 / 取消 / 确定；预选 membership 高亮
@CustomDialog
export struct ChangeCategoryDialog {
  controller?: CustomDialogController;
  categories: CategoryRecord[] = [];
  // 预选分类 id（编辑已有作品分类时传当前 membership）
  preselectedIds: number[] = [];
  title: Resource | string = '';
  @State selected: Set<number> = new Set<number>();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onConfirm: (categoryIds: number[]) => void = (_ids: number[]) => {
  };
  onEditCategories: () => void = () => {
  };
  onClose: () => void = () => {
  };

  aboutToAppear(): void {
    const ids: Set<number> = new Set<number>();
    for (const id of this.preselectedIds) {
      ids.add(id);
    }
    this.selected = ids;
  }

  build() {
    Column({ space: 16 }) {
      Text(this.title !== '' ? this.title : $r('app.string.action_move_category'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
      if (this.categories.length === 0) {
        Text($r('app.string.information_empty_category_dialog'))
          .fontSize(14)
          .fontColor(this.pal.sub)
      } else {
        Scroll() {
          Column() {
            ForEach(this.categories, (cat: CategoryRecord) => {
              Row({ space: 12 }) {
                Checkbox()
                  .select(this.selected.has(cat.id))
                  .selectedColor(this.pal.primary)
                  .onChange((_checked: boolean) => {
                    this.toggle(cat.id);
                  })
                Text(Util.categoryLabel(cat.name))
                  .fontSize(15)
                  .fontColor(this.pal.text)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .constraintSize({ minHeight: 44 })
              .onClick(() => {
                this.toggle(cat.id);
              })
            }, (cat: CategoryRecord) => `ccat-${cat.id}`)
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: 320 })
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
        .width('100%')
      }
      Row({ space: 8 }) {
        Button($r('app.string.action_edit'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.dismiss();
            this.onEditCategories();
          })
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.dismiss();
          })
        Button($r('app.string.common_ok'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .enabled(this.categories.length > 0)
          .onClick(() => {
            const ids: number[] = [];
            this.selected.forEach((id: number): void => {
              ids.push(id);
            });
            this.dismiss();
            this.onConfirm(ids);
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  private toggle(id: number): void {
    const next: Set<number> = new Set<number>(this.selected);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    this.selected = next;
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

// 疑似重复作品弹窗（对齐 Mihon DuplicateMangaDialog）：
// 重复卡片横向列表（点击迁移/长按打开详情）+ 依然添加 + 取消
@CustomDialog
export struct DuplicateMangaDialog {
  controller?: CustomDialogController;
  duplicates: DuplicateManga[] = [];
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onAddAnyway: () => void = () => {
  };
  onOpenManga: (mangaId: number) => void = (_id: number) => {
  };
  onMigrate: (mangaId: number) => void = (_id: number) => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.possible_duplicates_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
      Text($r('app.string.possible_duplicates_summary'))
        .fontSize(13)
        .fontColor(this.pal.sub)
        .width('100%')
      Scroll() {
        Row({ space: 12 }) {
          ForEach(this.duplicates, (dup: DuplicateManga) => {
            Column({ space: 6 }) {
              Stack({ alignContent: Alignment.TopStart }) {
                SmartImage({
                  url: dup.coverUrl,
                  sourceKey: dup.sourceKey,
                  fit: ImageFit.Cover,
                  placeholderIconSize: 20
                })
                  .width('100%')
                  .height(140)
                  .borderRadius(8)
                  .backgroundColor(this.pal.chip)
                Text($r('app.string.manga_num_chapters', dup.chapterCount))
                  .fontSize(10)
                  .fontColor(this.pal.onPrimary)
                  .backgroundColor(this.pal.primary)
                  .borderRadius(8)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .margin(4)
              }
              .width('100%')
              Text(dup.title)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.pal.text)
                .maxLines(2)
                .minLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              if (dup.author !== '') {
                Text(dup.author)
                  .fontSize(11)
                  .fontColor(this.pal.sub)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              Text(Util.statusLabel(dup.status))
                .fontSize(11)
                .fontColor(this.pal.sub)
                .width('100%')
              Text(this.sourceName(dup))
                .fontSize(10)
                .fontColor(this.pal.sub)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .width(110)
            .alignItems(HorizontalAlign.Start)
            .padding(8)
            .borderRadius(12)
            .backgroundColor(this.pal.chip)
            .onClick(() => {
              this.dismiss();
              this.onMigrate(dup.id);
            })
            .gesture(LongPressGesture()
              .onAction(() => {
                this.dismiss();
                this.onOpenManga(dup.id);
              }))
          }, (dup: DuplicateManga) => `dup-${dup.id}`)
        }
        .padding({ top: 4, bottom: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .width('100%')
      Button($r('app.string.action_add_anyway'))
        .width('100%')
        .backgroundColor(this.pal.primary)
        .fontColor(this.pal.onPrimary)
        .onClick(() => {
          this.dismiss();
          this.onAddAnyway();
        })
      Button($r('app.string.common_cancel'))
        .width('100%')
        .backgroundColor(this.pal.chip)
        .fontColor(this.pal.primary)
        .onClick(() => {
          this.dismiss();
        })
    }
    .padding(20)
    .width('100%')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  // 源显示名：已注册源取名称，未注册（插件未加载/已卸载）回退 key
  private sourceName(dup: DuplicateManga): string {
    const source = SourceRegistry.get(dup.sourceKey);
    return source !== undefined ? source.name : dup.sourceKey;
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

// 导出列选择弹窗（书架列表 CSV 导出：标题/作者，对齐 Mihon ColumnSelectionDialog）
@CustomDialog
export struct ExportColumnsDialog {
  controller?: CustomDialogController;
  @State titleSelected: boolean = true;
  @State authorSelected: boolean = true;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onConfirm: (includeTitle: boolean, includeAuthor: boolean) => void =
    (_t: boolean, _a: boolean) => {
    };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.data_export_include'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)

      Row() {
        Checkbox()
          .select(this.titleSelected)
          .selectedColor(this.pal.primary)
          .onChange((checked: boolean) => {
            this.titleSelected = checked;
            if (!checked) {
              this.authorSelected = false;
            }
          })
        Text($r('app.string.data_column_title'))
          .fontSize(15)
          .fontColor(this.pal.text)
          .margin({ left: 8 })
      }
      .width('100%')

      Row() {
        Checkbox()
          .select(this.authorSelected)
          .selectedColor(this.pal.primary)
          .enabled(this.titleSelected)
          .onChange((checked: boolean) => {
            this.authorSelected = checked;
          })
        Text($r('app.string.data_column_author'))
          .fontSize(15)
          .fontColor(this.pal.text)
          .margin({ left: 8 })
      }
      .width('100%')

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.dismiss();
          })
        Button($r('app.string.common_save'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .onClick(() => {
            this.dismiss();
            this.onConfirm(this.titleSelected, this.authorSelected);
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

// 通用确认弹窗（迁移确认等）
@CustomDialog
export struct ConfirmDialog {
  controller?: CustomDialogController;
  title: Resource | string = '';
  message: Resource | string = '';
  confirmText: Resource | string = $r('app.string.common_ok');
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onConfirm: () => void = () => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
      Text(this.message)
        .fontSize(14)
        .fontColor(this.pal.sub)
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.dismiss();
          })
        Button(this.confirmText)
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .onClick(() => {
            this.dismiss();
            this.onConfirm();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

// 保存确认弹窗：系统保存对话框不可用时的回退方案，
// 通过 SaveButton 安全控件获取临时媒体库授权后创建资源
@CustomDialog
export struct SaveConfirmDialog {
  controller?: CustomDialogController;
  title: Resource | string = '';
  fileName: string = '';
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onConfirmed: () => void = () => {
  };
  onCancel: () => void = () => {
  };

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
      Text(this.fileName)
        .fontSize(13)
        .fontColor(this.pal.sub)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      // 两按钮等宽等高同圆角；SaveButton 不支持 layoutWeight，用等权容器包一层实现等分；
      // 授权失败也先收起弹窗再提示，避免弹窗滞留
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.dismiss();
          })
        Row() {
          SaveButton({ text: SaveDescription.SAVE_TO_GALLERY, buttonType: ButtonType.Capsule })
            .width('100%')
            .height(40)
            .backgroundColor(this.pal.primary)
            .fontColor(this.pal.onPrimary)
            .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
              this.dismiss();
              if (result === SaveButtonOnClickResult.SUCCESS) {
                this.onConfirmed();
              } else {
                Util.toastRes(this.getUIContext(), $r('app.string.reader_page_save_failed'));
              }
            })
        }
        .layoutWeight(1)
        // 安全组件忽略 borderRadius（实测渲染为方角），用容器裁剪出与取消一致的圆角
        .borderRadius(20)
        .clip(true)
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onCancel();
  }
}

// 备份导出选项弹窗（v3 双档位：完整备份 / 仅作品与插件仓库；
// 完整档可选包含敏感配置，包含时强制设置 ≥6 位密码用于加密）
@CustomDialog
export struct BackupOptionsDialog {
  controller?: CustomDialogController;
  // 档位：true 完整备份（默认）/ false 仅作品与插件仓库
  @State scopeFull: boolean = true;
  @State includeSecure: boolean = false;
  @State pwdInput: string = '';
  @State pwdConfirm: string = '';
  // 校验错误提示（空串 = 无错误）
  @State pwdError: Resource | string = '';
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onConfirm: (options: BackupOptions) => void = (_o: BackupOptions) => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.data_create_backup'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)

      // 档位单选（完整备份在后：勾选后展开的敏感配置选项紧随其下）
      Row() {
        Radio({ value: 'minimal', group: 'backupScope' })
          .checked(!this.scopeFull)
          .radioStyle({
            checkedBackgroundColor: this.pal.primary,
            uncheckedBorderColor: this.pal.sub
          })
          .width(20)
          .height(20)
          .onChange((isChecked: boolean) => {
            if (isChecked) {
              this.scopeFull = false;
            }
          })
        Text($r('app.string.backup_scope_minimal'))
          .fontSize(15)
          .fontColor(this.pal.text)
          .margin({ left: 8 })
      }
      .width('100%')
      .onClick(() => {
        this.scopeFull = false;
      })

      Row() {
        Radio({ value: 'full', group: 'backupScope' })
          .checked(this.scopeFull)
          .radioStyle({
            checkedBackgroundColor: this.pal.primary,
            uncheckedBorderColor: this.pal.sub
          })
          .width(20)
          .height(20)
          .onChange((isChecked: boolean) => {
            if (isChecked) {
              this.scopeFull = true;
            }
          })
        Text($r('app.string.backup_scope_full'))
          .fontSize(15)
          .fontColor(this.pal.text)
          .margin({ left: 8 })
      }
      .width('100%')
      .onClick(() => {
        this.scopeFull = true;
      })

      // 敏感配置开关（仅完整档可选）
      if (this.scopeFull) {
        Row() {
          Toggle({ type: ToggleType.Switch, isOn: this.includeSecure })
            .selectedColor(this.pal.primary)
            .height(24)
            .onChange((isOn: boolean) => {
              this.includeSecure = isOn;
              this.pwdError = '';
            })
          Text($r('app.string.backup_include_secure'))
            .fontSize(15)
            .fontColor(this.pal.text)
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')

        // 密码 + 确认密码（勾选敏感配置后出现）
        if (this.includeSecure) {
          TextInput({
            placeholder: $r('app.string.backup_password'),
            text: this.pwdInput,
          })
            .type(InputType.Password)
            .showPasswordIcon(true)
            .height(44)
            .fontSize(14)
            .fontColor(this.pal.text)
            .placeholderFont({ size: 14 })
            .onChange((value: string) => {
              this.pwdInput = value;
            })

          TextInput({
            placeholder: $r('app.string.backup_password_confirm'),
            text: this.pwdConfirm,
          })
            .type(InputType.Password)
            .showPasswordIcon(true)
            .height(44)
            .fontSize(14)
            .fontColor(this.pal.text)
            .placeholderFont({ size: 14 })
            .onChange((value: string) => {
              this.pwdConfirm = value;
            })

          Text($r('app.string.backup_password_hint'))
            .fontSize(12)
            .fontColor(this.pal.sub)
        }
      }

      // 校验错误提示
      if (this.pwdError !== '') {
        Text(this.pwdError)
          .fontSize(12)
          .fontColor('#D32F2F')
      }

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.dismiss();
          })
        Button($r('app.string.common_save'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .onClick(() => {
            this.confirm();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  // 校验并回调：包含敏感配置时要求密码 ≥6 位且两次一致
  private confirm(): void {
    if (this.scopeFull && this.includeSecure) {
      if (this.pwdInput === '') {
        this.pwdError = $r('app.string.backup_password_required');
        return;
      }
      if (this.pwdInput.length < 6) {
        this.pwdError = $r('app.string.backup_password_hint');
        return;
      }
      if (this.pwdInput !== this.pwdConfirm) {
        this.pwdError = $r('app.string.backup_password_mismatch');
        return;
      }
    }
    const options: BackupOptions = {
      full: this.scopeFull,
      includeSensitive: this.scopeFull && this.includeSecure,
      password: this.scopeFull && this.includeSecure ? this.pwdInput : '',
    };
    this.dismiss();
    this.onConfirm(options);
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

// 备份导入密码弹窗（v3 含加密敏感段时解密所需）
@CustomDialog
export struct BackupPasswordDialog {
  controller?: CustomDialogController;
  @State pwdInput: string = '';
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onConfirm: (password: string) => void = (_p: string) => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.backup_password'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)

      Text($r('app.string.backup_need_password_hint'))
        .fontSize(12)
        .fontColor(this.pal.sub)

      TextInput({
        placeholder: $r('app.string.backup_password'),
        text: this.pwdInput,
      })
        .type(InputType.Password)
        .showPasswordIcon(true)
        .height(44)
        .fontSize(14)
        .fontColor(this.pal.text)
        .placeholderFont({ size: 14 })
        .defaultFocus(true)
        .onChange((value: string) => {
          this.pwdInput = value;
        })

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.dismiss();
          })
        Button($r('app.string.common_ok'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .enabled(this.pwdInput.length >= 6)
          .onClick(() => {
            const password: string = this.pwdInput;
            this.dismiss();
            this.onConfirm(password);
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .focusable(true)
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}
