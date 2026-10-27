// HdsTabs 沉浸光感宿主（生产实现）：
// 全项目唯一导入 @kit.UIDesignKit 的文件。业务页面只面向本模块的纯类型 API，
// 不感知 HDS 类型；预览器无 HDS 运行时，由 src/mock/HdsTabsHost.mock.ets
// 通过 mock-config.json5 整体替换本模块（标准 Tabs 等效实现），生产包不含 Mock。
import {
  DividerMode,
  HdsAnimationMode,
  HdsBarLayoutMode,
  HdsBarStyle,
  HdsBarWidthRangeOptions,
  hdsMaterial,
  HdsTabs,
  HdsTabsController,
  HdsTabsFloatingStyle,
  HdsTabsMiniBar
} from '@kit.UIDesignKit';

// 迷你条配置：builder 必填；verticalLayout=true 表示迷你栏与页签栏垂直堆叠且常驻展开
// （阅读器双浮动胶囊场景），false/不设置走 HDS 默认联动（首页听书迷你条）
export interface HdsTabsHostMiniBar {
  builder: () => void;
  verticalLayout?: boolean;
}

// 宿主控制器：封装 HDS 官方显隐动效（点击交互场景 CLICK_ANIMATION）
export class HdsTabsHostController {
  readonly impl: HdsTabsController = new HdsTabsController();

  applyHideAnimation(): void {
    this.impl.applyHideAnimation(HdsAnimationMode.CLICK_ANIMATION);
  }

  applyShowAnimation(): void {
    this.impl.applyShowAnimation(HdsAnimationMode.CLICK_ANIMATION);
  }
}

// HdsTabs 宿主：浮动页签栏 + 沉浸材质 + 可选迷你条，页签内容经尾随闭包注入。
// barWidth>0 时显式指定浮动条宽度（可超过默认 328vp 上限）；barHeight 显式数值
// （'auto' HDS 不识别，栏高会回落 56vp 且浮动胶囊不绘制）。
@Component
export struct HdsTabsHost {
  @Prop index: number = 0;
  scrollable: boolean = true;
  barHeight: number = 56;
  barWidth: number = 0;
  // 页签栏与窗口底边距离（调用点随导航条高度动态计算，@Prop 保证同步）
  @Prop barBottomMargin: number = 8;
  // 页签栏上方跟手分割线：true=HDS 默认 FOLLOW_SCROLL，false=关闭（阅读器场景）
  dividerFollowScroll: boolean = true;
  controller: HdsTabsHostController = new HdsTabsHostController();
  // miniBar 配置为普通成员（含 builder，仅创建时赋值）；是否挂入 HDS 由
  // miniBarEnabled 门控——父组件动态显隐（如首页听书 ttsActive）必须经由
  // @Prop 开关驱动 floatingStyle 重新应用，false 时不配置避免空胶囊
  miniBar: HdsTabsHostMiniBar | undefined = undefined;
  @Prop miniBarEnabled: boolean = true;
  @BuilderParam content: () => void = this.emptyBuilder;

  onTabChange: (index: number) => void = (_i: number): void => {
  };

  build() {
    HdsTabs({ barPosition: BarPosition.End, index: this.index, controller: this.controller.impl }) {
      this.content()
    }
    .scrollable(this.scrollable)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barHeight(this.barHeight)
    // 关闭页签栏上方跟手分割线时置 NONE，默认保持 FOLLOW_SCROLL（对齐 HDS 默认）
    .divider({ mode: this.dividerFollowScroll ? DividerMode.FOLLOW_SCROLL : DividerMode.NONE })
    .barFloatingStyle(this.floatingStyle())
    // onSelected 在切换动画开始时触发（onChange 在切换完成后），两者统一回调
    .onSelected((index: number): void => {
      this.onTabChange(index);
    })
    .onChange((index: number): void => {
      this.onTabChange(index);
    })
    .width('100%')
    .height('100%')
  }

  // 浮动样式：沉浸材质常驻 IMMERSIVE/ADAPTIVE；迷你条按需挂入（无迷你条不配置，

  @Builder
  emptyBuilder() {
  }

  // 避免空胶囊）；verticalLayout 追加垂直堆叠常驻展开配置
  private floatingStyle(): HdsTabsFloatingStyle {
    const style: HdsTabsFloatingStyle = {
      barBottomMargin: this.barBottomMargin,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    };
    if (this.barWidth > 0) {
      const width: HdsBarWidthRangeOptions = {
        smallWidth: this.barWidth,
        mediumWidth: this.barWidth,
        largeWidth: this.barWidth
      };
      style.barWidth = width;
    }
    const mini: HdsTabsHostMiniBar | undefined = this.miniBar;
    if (this.miniBarEnabled && mini !== undefined) {
      const config: HdsTabsMiniBar = {
        miniBarBuilder: (): void => {
          mini.builder();
        }
      };
      if (mini.verticalLayout === true) {
        config.miniBarWidth = {
          smallWidth: this.barWidth,
          mediumWidth: this.barWidth,
          largeWidth: this.barWidth
        };
        config.miniBarStyle = HdsBarStyle.EXPAND;
        config.barLayoutMode = HdsBarLayoutMode.VERTICAL;
      }
      style.miniBar = config;
    }
    return style;
  }
}
