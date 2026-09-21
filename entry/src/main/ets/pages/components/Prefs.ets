// 閫氱敤鍋忓ソ/璁剧疆琛岀粍浠讹細PrefGroup / TextRow / SwitchRow / SelectRow / IconRow
import { ThemePalette } from '../../common/Theme';
import { AppIcon } from './AppIcon';

@Builder
function emptyContent() {
  Column() {
  }
  .width(0)
  .height(0)
}

@Component
export struct PrefGroup {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  groupTitle: Resource | string = '';
  @BuilderParam content: () => void = emptyContent;

  build() {
    Column() {
      if (this.groupTitle !== '') {
        Text(this.groupTitle)
          .fontSize(13)
          .fontColor(this.pal.sub)
          .margin({ left: 16, top: 12, bottom: 2 })
      }
      Column() {
        this.content()
      }
      .backgroundColor(this.pal.card)
      .borderRadius(16)
      .clip(true)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

@Component
export struct TextRow {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  title: Resource | string = '';
  value: Resource | string = '';
  onTap: () => void = () => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(16)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
      if (this.value !== '') {
        Text(this.value)
          .fontSize(14)
          .fontColor(this.pal.sub)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '50%' })
      }
      AppIcon({ name: 'keyboard_arrow_right', iconSize: 20 })
        .margin({ left: 4 })
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 12 })
    .onClick(() => this.onTap())
  }
}

@Component
export struct SwitchRow {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  title: Resource | string = '';
  @Prop icon: string = '';
  @Prop isOn: boolean = false;
  onChange: (value: boolean) => void = (value: boolean) => {};

  build() {
    Row() {
      if (this.icon !== '') {
        AppIcon({ name: this.icon, iconSize: 22 })
          .margin({ right: 12 })
      }
      Text(this.title)
        .fontSize(16)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.pal.primary)
        .onChange((value: boolean) => this.onChange(value))
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
  }
}

@Component
export struct SelectRow {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  title: Resource | string = '';
  value: Resource | string = '';
  @Prop options: string[] = [];
  onSelect: (value: string) => void = (value: string) => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(16)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
      Text(this.value)
        .fontSize(14)
        .fontColor(this.pal.sub)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '50%' })
      AppIcon({ name: 'keyboard_arrow_right', iconSize: 20 })
        .margin({ left: 4 })
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 12 })
    .onClick(() => {
      const sheets: SheetInfo[] = [];
      this.options.forEach((opt: string) => {
        sheets.push({
          title: opt,
          action: (): void => {
            this.onSelect(opt);
          }
        });
      });
      const opts: ActionSheetOptions = {
        title: this.title,
        message: '',
        sheets: sheets
      };
      this.getUIContext().showActionSheet(opts);
    })
  }
}

@Component
export struct IconRow {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  title: Resource | string = '';
  @Prop icon: string = '';
  onTap: () => void = () => {};

  build() {
    Row() {
      AppIcon({ name: this.icon, iconSize: 24 })
      Text(this.title)
        .fontSize(16)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .margin({ left: 16 })
        .maxLines(1)
      AppIcon({ name: 'keyboard_arrow_right', iconSize: 20 })
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 12 })
    .onClick(() => this.onTap())
  }
}
