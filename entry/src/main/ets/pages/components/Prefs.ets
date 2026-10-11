// 閫氱敤鍋忓ソ/璁剧疆琛岀粍浠讹細PrefGroup / TextRow / SwitchRow / SelectRow / IconRow
import { ThemePalette } from '../../common/Theme';
import { AppIcon } from './AppIcon';
import { PickerSheet } from './PickerSheet';

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
    // 一多大屏适配：宽屏下限制内容最大宽度并居中，避免列表被拉伸过宽
    .constraintSize({ maxWidth: 720 })
  }
}

@Component
export struct TextRow {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State hovered: boolean = false;
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
    .backgroundColor(this.hovered ? this.pal.chip : Color.Transparent)
    .onClick(() => this.onTap())
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
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
  @State hovered: boolean = false;
  title: Resource | string = '';
  value: Resource | string = '';
  @Prop options: string[] = [];
  onSelect: (value: string) => void = (value: string) => {};
  @State showPicker: boolean = false;

  @Builder
  pickerSheetBuilder() {
    PickerSheet({
      options: this.options,
      selectedIndex: this.currentValueIndex(),
      onPick: (index: number): void => {
        this.showPicker = false;
        const opt: string | undefined = this.options[index];
        if (opt !== undefined) {
          this.onSelect(opt);
        }
      }
    })
  }

  private currentValueIndex(): number {
    for (let i = 0; i < this.options.length; i++) {
      if (this.options[i] === this.value) {
        return i;
      }
    }
    return -1;
  }

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
    .backgroundColor(this.hovered ? this.pal.chip : Color.Transparent)
    .bindSheet($$this.showPicker, this.pickerSheetBuilder(), {
      title: { title: this.title },
      detents: [SheetSize.FIT_CONTENT],
      dragBar: true,
      showClose: false,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK
    })
    .onClick(() => {
      this.showPicker = true;
    })
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
  }
}

@Component
export struct IconRow {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State hovered: boolean = false;
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
    .backgroundColor(this.hovered ? this.pal.chip : Color.Transparent)
    .onClick(() => this.onTap())
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
  }
}
