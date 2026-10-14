// 加载态兜底返回：左上角浮动返回圆钮 + ESC 快捷键
// PC/平板等无返回手势设备在章节加载中可随时退出，无需等待网络超时
import { AppIcon } from './AppIcon';

@Component
export struct LoadingBackButton {
  @StorageProp('statusBarH') statusBarH: number = 0;
  onBack: () => void = (): void => {};

  build() {
    Row({ space: 8 }) {
      Row() {
        AppIcon({ name: 'arrow_back', iconSize: 24, tint: '#FFFFFF' })
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#66000000')
      .onClick((): void => {
        this.onBack();
      })
      // 单个 FunctionKey（无修饰键）可绑定为快捷键：组件未获焦也响应，窗口获焦即触发
      .keyboardShortcut(FunctionKey.ESC, [], (): void => {
        this.onBack();
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, top: this.statusBarH + 12 })
    .alignItems(VerticalAlign.Top)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
