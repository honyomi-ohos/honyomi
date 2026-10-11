// 通用底部选择器 Sheet：替代系统 ActionSheet，主题化样式
// 解决系统 ActionSheet item 无间距、字号过小的问题：18fp 标题 + 16fp 选项 + item 间距 8
import { ThemePalette } from '../../common/Theme';
import { AppIcon } from './AppIcon';

@Component
export struct PickerSheet {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State pressedIdx: number = -1;
  @Prop options: ResourceStr[] = [];
  @Prop icons: string[] = [];
  @Prop selectedIndex: number = -1;
  onPick: (index: number) => void = (index: number) => {};

  build() {
    Column() {
      List({ space: 8 }) {
        ForEach(this.options, (opt: ResourceStr, index: number) => {
          ListItem() {
            Row() {
              if (index < this.icons.length && this.icons[index] !== '') {
                AppIcon({
                  name: this.icons[index],
                  iconSize: 22,
                  tint: index === this.selectedIndex ? this.pal.primary : this.pal.sub
                })
                  .margin({ right: 12 })
              }
              Text(opt)
                .fontSize(16)
                .fontColor(index === this.selectedIndex ? this.pal.primary : this.pal.text)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (index === this.selectedIndex) {
                AppIcon({ name: 'done', iconSize: 22, tint: this.pal.primary })
              }
            }
            .width('100%')
            .height(52)
            .padding({ left: 16, right: 16 })
            .borderRadius(14)
            .backgroundColor(this.pressedIdx === index ? this.pal.divider : this.pal.chip)
            .onClick(() => {
              this.pressedIdx = -1;
              this.onPick(index);
            })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.pressedIdx = index;
              } else {
                this.pressedIdx = -1;
              }
            })
          }
        }, (opt: ResourceStr, index: number): string => `opt-${index}`)
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 16 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
  }
}
