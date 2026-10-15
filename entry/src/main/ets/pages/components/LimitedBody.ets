// 大屏可读性限宽容器（参考官方 ResponsiveLayout 示例缩进布局思想）：
// 窄屏（<maxWidth）100% 全宽铺满；md/lg/xl 大屏限宽居中，
// 避免长列表/设置面板在平板横屏、PC 宽窗口上全宽拉伸降低可读性
@Component
export struct LimitedBody {
  // 必传内容构建器（尾闭包语法传入页面根节点）
  @BuilderParam body: () => void = emptyBody;
  // 内容最大宽度（vp），超过该宽度的窗口中内容居中限宽
  @Prop maxWidth: number = 720;

  build() {
    Row() {
      Column() {
        this.body()
      }
      .constraintSize({ maxWidth: this.maxWidth })
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Builder
function emptyBody() {
}
