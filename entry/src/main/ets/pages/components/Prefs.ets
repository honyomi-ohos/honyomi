// 通用偏好设置行组件：PrefGroup / TextRow / SwitchRow / IconRow / PrefSelectRow / PrefSwitchRow
import { ThemePalette } from '../../common/Theme';
import { Bp } from '../../common/Breakpoint';
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
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  title: Resource | string = '';
  subtitle: Resource | string = '';
  @Prop icon: string = '';
  @Prop isOn: boolean = false;
  onChange: (value: boolean) => void = (value: boolean) => {};

  build() {
    Row() {
      if (this.icon !== '') {
        AppIcon({ name: this.icon, iconSize: 22 })
          .margin({ right: 12 })
      }
      Column() {
        Text(this.title)
          .fontSize(16)
          .fontColor(this.pal.text)
          .maxLines(1)
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(this.pal.sub)
            .maxLines(2)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.pal.primary)
        .onChange((value: boolean) => this.onChange(value))
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .padding({
      left: 16,
      right: 16,
      top: this.subtitle !== '' ? 10 : 0,
      bottom: this.subtitle !== '' ? 10 : 0
    })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct IconRow {
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

// 声明式偏好选择行：options 直接收 ResourceStr[]（含 $r 资源），按索引回调，
// 页面无需预解析资源字符串、维护 label 镜像状态或 indexOf 反查。
// 组件自持选中索引（@State currentIdx，初始化自 selectedIndex），
// 选中后行尾显示值即时刷新，页面只需在 onSelectIndex 中落库
@Component
export struct PrefSelectRow {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  @State hovered: boolean = false;
  @State showPicker: boolean = false;
  title: Resource | string = '';
  options: ResourceStr[] = [];
  selectedIndex: number = -1;
  @State currentIdx: number = -1;
  onSelectIndex: (index: number) => void = (index: number) => {};

  aboutToAppear(): void {
    this.currentIdx = this.selectedIndex;
  }

  @Builder
  pickerSheetBuilder() {
    PickerSheet({
      options: this.options,
      selectedIndex: this.currentIdx,
      onPick: (index: number): void => {
        this.showPicker = false;
        this.currentIdx = index;
        this.onSelectIndex(index);
      }
    })
  }

  private valueText(): ResourceStr {
    if (this.currentIdx >= 0 && this.currentIdx < this.options.length) {
      return this.options[this.currentIdx];
    }
    return '';
  }

  build() {
    Row() {
      Text(this.title)
        .fontSize(16)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
      Text(this.valueText())
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
      preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
      width: Bp.isWide(this.windowW) ? 560 : '100%',
      height: SheetSize.FIT_CONTENT,
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

// 声明式偏好开关行：组件自持开关状态，页面传入初始值与落库回调即可，
// 免去页面级 @State 镜像 + aboutToAppear 同步样板
@Component
export struct PrefSwitchRow {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  title: Resource | string = '';
  subtitle: Resource | string = '';
  icon: string = '';
  initValue: boolean = false;
  apply: (value: boolean) => void = (value: boolean) => {};
  @State isOn: boolean = false;
  private inited: boolean = false;

  build() {
    Row() {
      if (this.icon !== '') {
        AppIcon({ name: this.icon, iconSize: 22 })
          .margin({ right: 12 })
      }
      Column() {
        Text(this.title)
          .fontSize(16)
          .fontColor(this.pal.text)
          .maxLines(1)
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(this.pal.sub)
            .maxLines(2)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.pal.primary)
        .onChange((value: boolean) => {
          this.isOn = value;
          this.apply(value);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .padding({
      left: 16,
      right: 16,
      top: this.subtitle !== '' ? 10 : 0,
      bottom: this.subtitle !== '' ? 10 : 0
    })
    .alignItems(VerticalAlign.Center)
    .onAppear(() => {
      if (!this.inited) {
        this.inited = true;
        this.isOn = this.initValue;
      }
    })
  }
}
