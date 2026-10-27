// HdsTabsHost 预览 Mock（仅预览器构建生效，经 mock-config.json5 替换
// common/HdsTabsHost.ets；生产包不含本文件）：
// 预览器无 HDS 运行时，用标准 Tabs 等效实现——内容装 Tabs、页签栏落底部，
// 迷你条内容悬于页签栏上方；显隐动效无 HDS 官方实现，静默降级。
export interface HdsTabsHostMiniBar {
  builder: () => void;
  verticalLayout?: boolean;
}

export class HdsTabsHostController {
  readonly impl: TabsController = new TabsController();

  applyHideAnimation(): void {
  }

  applyShowAnimation(): void {
  }
}

@Component
export struct HdsTabsHost {
  @Prop index: number = 0;
  scrollable: boolean = true;
  barHeight: number = 56;
  barWidth: number = 0;
  @Prop barBottomMargin: number = 8;
  dividerFollowScroll: boolean = true;
  controller: HdsTabsHostController = new HdsTabsHostController();
  miniBar: HdsTabsHostMiniBar | undefined = undefined;
  @Prop miniBarEnabled: boolean = true;
  @BuilderParam content: () => void = this.emptyBuilder;
  onTabChange: (index: number) => void = (_i: number): void => {
  };

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({ barPosition: BarPosition.End, index: this.index, controller: this.controller.impl }) {
        this.content()
      }
      .scrollable(this.scrollable)
      .barHeight(this.barHeight)
      .onChange((index: number): void => {
        this.onTabChange(index);
      })
      .onSelected((index: number): void => {
        this.onTabChange(index);
      })
      .width('100%')
      .height('100%')

      // 迷你条：悬于页签栏上方（约等于 HDS 浮动条的预览占位）
      if (this.miniBarEnabled && this.miniBar !== undefined) {
        Column() {
          this.miniBar.builder()
        }
        .width(this.barWidth > 0 ? this.barWidth : '90%')
        .margin({ bottom: this.barHeight + this.barBottomMargin })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  emptyBuilder() {
  }
}
