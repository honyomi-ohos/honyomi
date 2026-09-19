// 通用二级页头部：返回箭头 + 标题 + 右侧自定义区
import { ThemePalette } from '../../common/Theme';
import { AppIcon } from './AppIcon';

@Builder
function headerEmpty() {
  Column() {
  }
  .width(0)
  .height(0)
}

@Component
export struct PageHeader {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @Prop title: string = '';
  @BuilderParam right: () => void = headerEmpty;

  build() {
    Row() {
      AppIcon({ name: 'arrow_back', iconSize: 24 })
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .onClick(() => {
          this.pathStack.pop();
        })
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
      this.right()
    }
    .width('100%')
    .height(52 + this.statusBarH)
    .padding({ top: this.statusBarH, left: 4, right: 12 })
  }
}
