// HdsNavHost 预览 Mock（仅预览器构建生效，经 mock-config.json5 替换
// common/HdsNavHost.ets；生产包不含本文件）：
// 预览器不渲染沉浸光感材质，用标准 Navigation/NavDestination 等效实现——
// 布局与生产宿主完全一致（STACK 堆叠 + 手动避让），仅无材质；
// API 与生产宿主完全一致（NavGlassRoot/NavGlassPage/NavGlassAction）。
import { ThemePalette } from '../main/ets/common/Theme';
import { AppIcon } from '../main/ets/pages/components/AppIcon';

// 二级页标题栏右侧动作项：图标 + 可选无障碍标签 + 点击回调
export interface NavGlassAction {
  icon: Resource;
  label?: Resource | string;
  action: () => void;
}

// 首页页签头部统一高度（vp）：与生产宿主一致
export const HOME_HEADER_H: number = 58;

// 二级页 MINI 标题栏高度（vp）：与生产宿主一致
export const NAV_BAR_H: number = 56;

// 根导航宿主 Mock：标准 Navigation + STACK 标题栏（承载首页页签头部）；
// 路由栈经 @Consume('navStack') 取 Index 的 @Provide 实例
@Component
export struct NavGlassRoot {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
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
    // 与生产宿主一致：NavigationCustomTitle 对象形式显式固定标题栏高度
    .title({
      builder: this.header,
      height: this.statusBarH + HOME_HEADER_H
    }, { barStyle: BarStyle.STACK })
    .mode(NavigationMode.Stack)
    .backgroundColor(this.pal.bg)
    .clip(true)
    .onNavBarStateChange((isVisible: boolean): void => {
      this.onNavBarStateChange(isVisible);
    })
  }

  @Builder
  emptyBuilder() {
  }
}

// 二级页宿主 Mock：NavDestination + 标准标题栏 + 右侧菜单图标；
// STACK 堆叠 + 内容手动避让，布局与生产宿主一致
@Component
export struct NavGlassPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  title: Resource | string = '';
  // false 时隐藏标题栏（页面自行管理头部/安全区）；宽窄屏动态切换，须 @Prop 同步
  @Prop showTitleBar: boolean = true;
  actions: NavGlassAction[] = [];
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
    // 与生产宿主一致：NavigationCustomTitle 对象形式 + 完全自绘标题行
    .title({
      builder: this.titleBar,
      height: this.statusBarH + NAV_BAR_H
    }, { barStyle: BarStyle.STACK })
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

  // 自绘标题行：与生产宿主一致
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
        // 外层容器承担 padding：与生产宿主一致，避免 padding 挤压定宽图标内容区
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
