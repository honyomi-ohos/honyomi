import { CategoryRecord } from '../model/Models';
import { Theme } from '../common/Theme';

// 文本输入弹窗（新建分类 / 导入漫画命名）
@CustomDialog
export struct InputDialog {
  controller?: CustomDialogController;
  title: string = '';
  placeholder: string = '';
  @State inputText: string = '';
  onConfirm: (text: string) => void = (_t: string) => {};
  @StorageProp('isDark') isDark: boolean = false;

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.text(this.isDark))
      TextInput({ placeholder: this.placeholder, text: this.inputText })
        .onChange((value: string) => {
          this.inputText = value;
        })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor(Theme.chip(this.isDark))
          .fontColor(Theme.text(this.isDark))
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
          })
        Button('确定')
          .layoutWeight(1)
          .backgroundColor(Theme.primary(this.isDark))
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
    .backgroundColor(Theme.card(this.isDark))
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

  build() {
    Column({ space: 8 }) {
      Text('选择分类')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.text(this.isDark))
        .margin({ bottom: 8 })
      ForEach(this.categories, (cat: CategoryRecord) => {
        Text(cat.name)
          .fontSize(15)
          .fontColor(Theme.text(this.isDark))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(12)
          .borderRadius(10)
          .backgroundColor(Theme.chip(this.isDark))
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onPick(cat.id);
          })
      }, (cat: CategoryRecord) => `cat-${cat.id}`)
    }
    .padding(20)
    .backgroundColor(Theme.card(this.isDark))
    .borderRadius(16)
    .width('80%')
  }
}
