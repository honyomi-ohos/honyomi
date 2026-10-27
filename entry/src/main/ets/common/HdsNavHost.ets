// 沉浸光感玻璃导航宿主（生产实现）：
// 标准 Navigation/NavDestination + uiMaterial 沉浸光感材质（API26）。
// 标题栏统一 barStyle STACK（标题栏与内容堆叠，配合 systemMaterial 获得最佳
// 沉浸光感效果——官方沉浸光感 FAQ 示例组合）。业务页面只面向本模块纯类型
// API（NavGlassRoot/NavGlassPage/NavGlassAction/HOME_HEADER_H/NAV_BAR_H），
// 不感知材质细节；预览器由 src/mock/HdsNavHost.mock.ets 通过
// mock-config.json5 整体替换本模块（无材质的等效布局），生产包不含 Mock。
import { uiMaterial } from '@kit.ArkUI';
import { ThemePalette } from './Theme';
import { AppIcon } from '../pages/components/AppIcon';

// 二级页标题栏右侧动作项：图标 + 可选无障碍标签 + 点击回调
export interface NavGlassAction {
  icon: Resource;
  label?: Resource | string;
  action: () => void;
}

// 首页页签头部统一高度（vp）：各页签头部行等高，切换页签时标题栏高度不跳变
export const HOME_HEADER_H: number = 58;

// 二级页 MINI 标题栏高度（vp）：STACK 堆叠模式下内容手动避让用
export const NAV_BAR_H: number = 56;

// 沉浸光感材质（对齐官方沉浸光感 FAQ 示例参数）：
// REGULAR 常规 + lightEffect 光线感应 + colorInvert 色彩反转 + interactive 交互响应。
// materialColor 材质层提亮赋色：纯色平坦背景上模糊均色=均色且无内容从玻璃下
// 穿过，材质不可辨识，提亮色让标题栏呈现可辨识的磨砂层次。
function buildMaterial(isDark: boolean): uiMaterial.ImmersiveMaterial {
  const tint: ResourceColor = isDark ? '#1FFFFFFF' : '#4DFFFFFF';
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.REGULAR,
    materialColor: tint,
    colorInvert: true,
    interactive: true,
    lightEffect: {}
  });
}

// 标题栏背景兜底：半透明 card 色（比 bg 亮一档的"磨砂表面"观感）。
// 模拟器等环境下 systemMaterial 不实际渲染（API 报告支持但无输出），
// backgroundColor 兜底保证标题栏可见；真机材质生效时系统会将标题栏
// backgroundColor 置透明，不影响玻璃效果。
function barFallback(card: string): ResourceColor {
  return '#80' + card.substring(1);
}

// 根导航宿主：Index 首页用。首页页签头部经 header 构建器注入 Navigation
// 标题栏（获得沉浸光感材质），内容经尾随闭包注入；STACK 模式下标题栏
// 覆盖于内容之上（内容自行避让 HOME_HEADER_H）。
// 路由栈经 @Consume('navStack') 取 Index 的 @Provide 实例。
@Component
export struct NavGlassRoot {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('statusBarH') statusBarH: number = 0;
  // 首页页签头部（Index 按当前页签切换注入）
  @BuilderParam header: () => void = this.emptyBuilder;
  @BuilderParam content: () => void = this.emptyBuilder;

  onNavBarStateChange: (isVisible: boolean) => void = (_v: boolean): void => {
  };

  build() {
    Navigation(this.pathStack) {
      this.content()
    }
    .width('100%')
    .height('100%')
    // 官方沉浸光感示例形态：NavigationCustomTitle 对象形式显式固定标题栏高度，
    // 避免裸 CustomBuilder 与 systemMaterial 组合时内容被下移一个默认栏高
    .title({
      builder: this.header,
      height: this.statusBarH + HOME_HEADER_H
    }, {
      systemMaterial: buildMaterial(this.isDark),
      barStyle: BarStyle.STACK,
      backgroundColor: barFallback(this.pal.card)
    })
    .mode(NavigationMode.Stack)
    // 裁剪内容到自身边界：Stack 模式推入路由页时首页向左平移让位，
    // 不裁剪会溢出画到左侧 Rail 区域上（Rail 被"挤压"至不可见）
    .clip(true)
    .onNavBarStateChange((isVisible: boolean): void => {
      this.onNavBarStateChange(isVisible);
    })
  }

  @Builder
  emptyBuilder() {
  }
}

// 二级页液态玻璃宿主：标准 NavDestination + 沉浸光感标题栏 + 右侧动作图标。
// STACK 堆叠模式下内容从 y=0 起绘并从玻璃下穿过，外层包装列按
// statusBarH + NAV_BAR_H 手动避让（手机全屏布局下标题栏含状态区高度）。
@Component
export struct NavGlassPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  title: Resource | string = '';
  // false 时隐藏玻璃标题栏（页面自行管理头部/安全区，如设置页 lg 双栏布局）。
  // 宽窄屏切换会动态改变该值（Bp.isWide），必须 @Prop 同步否则栏显隐滞留旧布局
  @Prop showTitleBar: boolean = true;
  actions: NavGlassAction[] = [];
  // 兼容保留：标准 NavDestination 标题栏自动联动滚动容器，无需显式绑定
  scroller: Scroller | undefined = undefined;
  @BuilderParam content: () => void = this.emptyBuilder;

  onReady: (ctx: NavDestinationContext) => void = (_ctx: NavDestinationContext): void => {
  };

  onShown: () => void = (): void => {
  };

  onHidden: () => void = (): void => {
  };

  build() {
    NavDestination() {
      Column() {
        this.content()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.showTitleBar ? this.statusBarH + NAV_BAR_H : 0 })
    }
    .backgroundColor(this.pal.bg)
    // 与首页同形态：NavigationCustomTitle 对象形式显式固定标题栏总高（含状态区），
    // 标题行由 titleBar 完全自绘。字符串标题 + systemMaterial + STACK 在全屏沉浸
    // 布局下系统把栏高从屏幕顶端算起，状态栏挤占后内容区仅剩 NAV_BAR_H -
    // statusBarH（返回键/标题被压扁）；且系统 BackButton/menus 在 statusBarH>0
    // 时顶对齐错位——自绘行规避两者，返回/动作交互由自绘行承担。
    .title({
      builder: this.titleBar,
      height: this.statusBarH + NAV_BAR_H
    }, {
      systemMaterial: buildMaterial(this.isDark),
      barStyle: BarStyle.STACK,
      backgroundColor: barFallback(this.pal.card)
    })
    .hideBackButton(true)
    .hideTitleBar(!this.showTitleBar)
    .onReady((ctx: NavDestinationContext): void => {
      this.onReady(ctx);
    })
    .onShown((): void => {
      this.onShown();
    })
    .onHidden((): void => {
      this.onHidden();
    })
  }

  // 自绘标题行：返回键 + 标题 + 右侧动作（PageHeader 同款视觉），
  // 顶部按 statusBarH 下移，Row 内垂直居中，双端确定性对齐
  @Builder
  titleBar() {
    Row() {
      AppIcon({ name: 'arrow_back', iconSize: 24 })
        .padding({
          left: 8,
          right: 8,
          top: 8,
          bottom: 8
        })
        .onClick(() => {
          this.pathStack.pop();
        })
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      ForEach(this.actions, (act: NavGlassAction) => {
        // 外层容器承担 padding（点击区 40x40）：padding 直接叠加在定宽 Image 上
        // 会挤压图标内容区（24-16=8vp），图标实际渲染过小
        Column() {
          Image(act.icon)
            .width(24)
            .height(24)
            .fillColor(this.pal.text)
        }
        .padding({
          left: 8,
          right: 8,
          top: 8,
          bottom: 8
        })
        .onClick(() => {
          act.action();
        })
      }, (act: NavGlassAction, index: number) => index.toString())
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarH, left: 4, right: 12 })
  }

  @Builder
  emptyBuilder() {
  }
}
