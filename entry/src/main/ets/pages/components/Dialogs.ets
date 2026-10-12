import { CategoryRecord } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';

// 文本输入弹窗（新建分类 / 导入漫画命名）
@CustomDialog
export struct InputDialog {
  controller?: CustomDialogController;
  title: Resource | string = '';
  placeholder: Resource | string = '';
  initialText: string = '';
  @State inputText: string = '';
  onConfirm: (text: string) => void = (_t: string) => {};
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  aboutToAppear(): void {
    this.inputText = this.initialText;
  }

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
      TextInput({ placeholder: this.placeholder, text: this.inputText })
        .onChange((value: string) => {
          this.inputText = value;
        })
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
          })
        Button($r('app.string.common_ok'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onConfirm(this.inputText);
          })
      }
      .width('100%')
    }
    .padding(20)
    .backgroundColor(this.pal.card)
    .borderRadius(16)
    .width('86%')
  }
}

// 分类选择弹窗
@CustomDialog
export struct CategoryDialog {
  controller?: CustomDialogController;
  categories: CategoryRecord[] = [];
  onPick: (categoryId: number) => void = (_id: number) => {};
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    Column({ space: 8 }) {
      Text($r('app.string.dialog_pick_category'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .margin({ bottom: 8 })
      ForEach(this.categories, (cat: CategoryRecord) => {
        Text(cat.name)
          .fontSize(15)
          .fontColor(this.pal.text)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(12)
          .borderRadius(10)
          .backgroundColor(this.pal.chip)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onPick(cat.id);
          })
      }, (cat: CategoryRecord) => `cat-${cat.id}`)
    }
    .padding(20)
    .backgroundColor(this.pal.card)
    .borderRadius(16)
    .width('80%')
  }
}

// 导出列选择弹窗（书架列表 CSV 导出：标题/作者，对齐 Mihon ColumnSelectionDialog）
@CustomDialog
export struct ExportColumnsDialog {
  controller?: CustomDialogController;
  onConfirm: (includeTitle: boolean, includeAuthor: boolean) => void =
    (_t: boolean, _a: boolean) => {};
  @State titleSelected: boolean = true;
  @State authorSelected: boolean = true;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

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
            if (this.controller !== undefined) {
              this.controller.close();
            }
          })
        Button($r('app.string.common_save'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onConfirm(this.titleSelected, this.authorSelected);
          })
      }
      .width('100%')
    }
    .padding(20)
    .backgroundColor(this.pal.card)
    .borderRadius(16)
    .width('86%')
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
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

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
            if (this.controller !== undefined) {
              this.controller.close();
            }
          })
        Button(this.confirmText)
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onConfirm();
          })
      }
      .width('100%')
    }
    .padding(20)
    .backgroundColor(this.pal.card)
    .borderRadius(16)
    .width('86%')
  }
}
