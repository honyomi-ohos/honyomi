import { CategoryRecord } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';

// 文本输入弹窗（新建分类 / 导入漫画命名）
@CustomDialog
export struct InputDialog {
  controller?: CustomDialogController;
  title: Resource | string = '';
  placeholder: Resource | string = '';
  @State inputText: string = '';
  onConfirm: (text: string) => void = (_t: string) => {};
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

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
