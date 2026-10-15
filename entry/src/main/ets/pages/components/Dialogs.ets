import { CategoryRecord } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';

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
  onConfirm: (text: string) => void = (_t: string) => {};
  onClose: () => void = () => {};
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  aboutToAppear(): void {
    this.inputText = this.initialText;
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
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
  onConfirm: (username: string, password: string) => void = (_u: string, _p: string) => {};
  onClose: () => void = () => {};
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }

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
        .onChange((value: string) => {
          this.username = value;
        })
      TextInput({
        placeholder: this.passwordPlaceholder,
        text: this.password,
      })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.password = value;
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
  }
}

// 分类选择弹窗
@CustomDialog
export struct CategoryDialog {
  controller?: CustomDialogController;
  categories: CategoryRecord[] = [];
  // 当前分类 id（快速改分类/入库选分类时高亮，-1 表示不高亮）
  selectedId: number = -1;
  onPick: (categoryId: number) => void = (_id: number) => {};
  onClose: () => void = () => {};
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }

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
          .fontColor(cat.id === this.selectedId ? '#FFFFFF' : this.pal.text)
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
  }
}

// 导出列选择弹窗（书架列表 CSV 导出：标题/作者，对齐 Mihon ColumnSelectionDialog）
@CustomDialog
export struct ExportColumnsDialog {
  controller?: CustomDialogController;
  onConfirm: (includeTitle: boolean, includeAuthor: boolean) => void =
    (_t: boolean, _a: boolean) => {};
  onClose: () => void = () => {};
  @State titleSelected: boolean = true;
  @State authorSelected: boolean = true;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }

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
  }
}

// 通用确认弹窗（迁移确认等）
@CustomDialog
export struct ConfirmDialog {
  controller?: CustomDialogController;
  title: Resource | string = '';
  message: Resource | string = '';
  confirmText: Resource | string = $r('app.string.common_ok');
  onConfirm: () => void = () => {};
  onClose: () => void = () => {};
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }

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
  }
}
