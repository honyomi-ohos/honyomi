import { ThemePalette } from '../../common/Theme';
import { AppIcon } from './AppIcon';

// 错误态：错误图标 + 描述文案（收敛各页面重复的错误布局）
// - fill=false（默认）：节内/行内错误态，占满宽度居中；内边距由调用方链式属性补充
// - fill=true：页面级错误态，占满父容器剩余空间并居中
@Component
export struct ErrorState {
  message: ResourceStr = '';
  // 图标尺寸（节内 24）
  iconSize: number = 24;
  // true = 占满父容器剩余空间并居中（页面级错误态）
  fill: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    if (this.fill) {
      Column() {
        this.body()
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        this.body()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  body() {
    AppIcon({ name: 'error', iconSize: this.iconSize, tint: this.pal.sub })
    Text(this.message)
      .fontSize(13)
      .fontColor(this.pal.sub)
      .textAlign(TextAlign.Center)
      .margin({ top: 4 })
  }
}
