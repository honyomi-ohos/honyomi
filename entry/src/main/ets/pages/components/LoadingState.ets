import { ThemePalette } from '../../common/Theme';

// 加载态：收敛各页面重复的居中 LoadingProgress 布局
// - fill=true（默认）：页面级 loading，Column 占满父容器剩余空间并居中（默认 36vp 转圈）
// - fill=false：节内/行内紧凑态，按内容渲染转圈本体，尺寸经 size 指定，
//   宽度/高度/内边距等由调用方链式属性补充
@Component
export struct LoadingState {
  // 转圈尺寸（页面级 36-40，节内/行内 16-28）
  spinnerSize: number = 36;
  // true = 占满剩余空间居中（页面级）；false = 按内容自适应（紧凑态）
  fill: boolean = true;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    if (this.fill) {
      Column() {
        this.spinner()
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        this.spinner()
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  spinner() {
    LoadingProgress()
      .width(this.spinnerSize)
      .height(this.spinnerSize)
      .color(this.pal.primary)
  }
}
