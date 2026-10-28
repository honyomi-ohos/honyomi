// 阅读器共享 Chrome 组件（Wave 3I 从 ReaderPage / NovelReaderPage 抽出）：
// 菜单骨架（顶栏+占位）、HDS 沉浸宿主、章节导航行、页码胶囊、指示徽标、方向 Sheet、滤镜容器。
// 样式与两页原实现逐行一致，行为不变。
import { HdsTabsHost, HdsTabsHostController, HdsTabsHostMiniBar } from '../../common/HdsTabsHost';
import { AppKeys } from '../../common/AppKeys';
import { AppIcon, AppIconRes } from './AppIcon';
import { PickerSheet } from './PickerSheet';
import { WideSlider } from './WideSlider';

// HDS 沉浸宿主由 common/HdsTabsHost 统一承载（全项目唯一 @kit.UIDesignKit 导入点）；
// 预览器经 src/mock/HdsTabsHost.mock.ets 等效渲染（标准 Tabs），生产包不含 Mock。

// 屏幕方向的可选值（与方向选择 sheet 选项一一对应，两阅读器共用）
export const READER_ORIENTATIONS: string[] =
  ['free', 'portrait', 'landscape', 'lock_portrait', 'lock_landscape'];

export const READER_ORIENTATION_ICONS: string[] =
  ['screen_rotation', 'stay_current_portrait', 'stay_current_landscape', 'screen_lock_portrait',
    'screen_lock_landscape'];

// 阅读器菜单骨架：顶栏（返回 + 标题/章节名 + 右侧动作区）+ 点击关闭占位
// 顶栏从上方滑入（底栏由 ReaderHdsHost 浮动胶囊承载，不在此渲染）
@Component
export struct ReaderMenu {
  // 阅读页背景是否为深色（由宿主页面写入）：玻璃无任何底色，前景色据此取高对比色
  @StorageProp('readerBgDark') bgDark: boolean = false;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop statusBarH: number = 0;
  // 顶栏右侧动作区（宿主注入图标按钮；默认空）
  @BuilderParam actions: () => void = this.emptyBuilder;
  onBack: () => void = (): void => {
  };
  onBackdrop: () => void = (): void => {
  };

  build() {
    Column() {
      // 顶栏
      Row() {
        AppIcon({ name: 'arrow_back', iconSize: 24, tint: this.bgDark ? '#FFFFFF' : '#111111' })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.onBack();
          })
        Column() {
          Text(this.title)
            .fontSize(14)
            .fontColor(this.bgDark ? '#FFFFFF' : '#111111')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.subtitle)
            .fontSize(11)
            .fontColor(this.bgDark ? '#CCFFFFFF' : '#CC111111')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        this.actions()
      }
      .width('100%')
      .padding({
        left: 4,
        right: 16,
        top: this.statusBarH + 10,
        bottom: 10
      })
      // 液态玻璃顶栏：backgroundEffect 纯背景模糊，不叠任何背景颜色；
      // 前景色按阅读页背景明暗取高对比色
      .backgroundEffect({ radius: 32, saturation: 1.5 })
      .border({ width: { bottom: 0.5 }, color: { bottom: this.bgDark ? '#2EFFFFFF' : '#2E000000' } })
      // 对齐 Mihon ReaderAppBars：顶栏从屏幕上方滑入/滑出 + 渐隐（滑移 200ms、渐隐 150ms）
      .transition(
        TransitionEffect.translate({ y: -120 })
          .animation({ duration: 200, curve: Curve.Linear })
          .combine(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.Linear }))
      )

      // 占位（空 Column 宽度默认自适应内容为 0，必须显式撑满才能接收点击关闭菜单）
      Column()
        .layoutWeight(1)
        .width('100%')
        .onClick(() => {
          this.onBackdrop();
        })
    }
    .width('100%')
    .height('100%')
    // 整棵子树删除时根组件需有消失转场时间，保证子组件的退出动画完整播放
    .transition(
      TransitionEffect.asymmetric(
        TransitionEffect.IDENTITY,
        TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Linear })
      )
    )
  }

  @Builder
  emptyBuilder() {
  }
}

// 阅读器 HDS 沉浸宿主（对齐首页浮动页签栏实现）：
// HdsTabsHost 挂两块独立浮动玻璃胶囊，垂直上下堆叠——
// 迷你栏（miniBar）= 进度行（上排胶囊），页签栏（tabBar）= 设置行（下排胶囊）。
// VERTICAL 布局（6.1.1(24)+）不受窄屏(<440vp)“迷你栏展开联动折叠页签栏”规则约束
// （该规则仅适用左右布局场景）；两栏均以 EXPAND 常驻展开。
// 玻璃胶囊与沉浸材质由 HDS 绘制（systemMaterialEffect IMMERSIVE/ADAPTIVE，
// 系统按需 colorInvert 保证前景可读）。
// barsVisible 驱动官方显隐动效（对齐首页多选显隐用法）。
// 例外——HdsTabs 区域宽度不足以并排放下两块浮动胶囊时（< 2*barWidth+64vp）：
// 宽度 < 440vp：HDS 自动把页签栏切成手机样式全宽底栏
// （HdsTabsBarChangeMode.NORMAL 屏幕尺寸触发，无公开 API 禁止该切换），
// 页签栏内容从窗口左缘排起、与迷你栏胶囊同高重叠，VERTICAL 堆叠失效；
// 宽度 440-720vp：HDS 浮动样式对“两栏同时展开”无定义（440-600 仅定义一展开
// 一折叠的居中规则），实测页签栏贴左、迷你栏底部居中，横向重叠。
// 此阈值以下改为手动渲染两块 backgroundEffect 玻璃胶囊（对齐 ReaderMenu 顶栏），
// 前景色经 AppStorage 'readerNarrowBars' 信号由 ReaderChapterButton /
// ReaderMenuIconButton / ReaderPagePill 切换为 bgDark 高对比硬编码色
// （手动玻璃无 HDS 材质 colorInvert，sys 色跟随系统深浅色而非阅读页明暗）。
@Component
export struct ReaderHdsHost {
  // 菜单开合：true 显示浮动页签栏，false 隐藏（沉浸阅读）
  @Prop @Watch('onBarsVisibleChange') barsVisible: boolean = false;
  // 页签栏（设置胶囊）与窗口底边距离（避让系统导航条）
  @Prop barBottomMargin: number = 12;
  // 浮动胶囊宽度（页签栏/迷你栏宽度，显式设置可超过默认 328vp 上限）
  @Prop barWidth: number = 328;
  // 阅读页背景是否为深色（手动胶囊描边取高对比色）
  @StorageProp('readerBgDark') bgDark: boolean = false;
  // HdsTabs 区域宽度不足以并排两块胶囊：手动胶囊模式（见 struct 头注释与 manualThreshold）
  @State narrow: boolean = false;
  // HdsTabs 区域宽度（vp）：手动胶囊限宽用
  @State hostWidth: number = 0;
  @BuilderParam content: () => void = this.emptyBuilder;
  // 迷你栏胶囊内容（进度行，上排）
  @BuilderParam progressBar: () => void = this.emptyBuilder;
  // 页签栏胶囊内容（设置行，下排）
  @BuilderParam settingsBar: () => void = this.emptyBuilder;
  // 胶囊高度（barHeight 显式数值；进度行 44vp / 设置行 48vp + 胶囊内边距）
  private capsuleHeight: number = 56;
  private controller: HdsTabsHostController = new HdsTabsHostController();

  aboutToAppear(): void {
    // 会话起点复位窄屏信号（消除上次阅读残留），子组件挂载前写入
    AppStorage.setOrCreate(AppKeys.READER_NARROW_BARS, false);
    // 延迟到 HdsTabs 与控制器完成绑定后：菜单初始收起
    // （首帧布局后若已切窄屏手动模式，控制器随 HdsTabsHost 卸载，跳过避免未绑定调用）
    setTimeout(() => {
      if (!this.barsVisible && !this.narrow) {
        this.controller.applyHideAnimation();
      }
    }, 0);
  }

  aboutToDisappear(): void {
    // 离开阅读器时复位窄屏信号，避免残留影响下次会话初始取值
    AppStorage.setOrCreate(AppKeys.READER_NARROW_BARS, false);
  }

  // 菜单开合 → 官方显隐动效（迷你栏+页签栏同步）；
  // 窄屏手动胶囊由 barsVisible 条件渲染 + 转场承接，不经过控制器
  onBarsVisibleChange(): void {
    if (this.narrow) {
      return;
    }
    if (this.barsVisible) {
      this.controller.applyShowAnimation();
    } else {
      this.controller.applyHideAnimation();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.narrow) {
        // 窄屏：正文铺满 + 底部渐变遮罩 + 手动双胶囊底部居中
        this.content()
        this.manualBarsScrim()
        this.manualBars()
      } else {
        HdsTabsHost({
          scrollable: false,
          barHeight: this.capsuleHeight,
          barWidth: this.barWidth,
          barBottomMargin: this.barBottomMargin,
          // 阅读器无需页签栏上方跟手分割线
          dividerFollowScroll: false,
          controller: this.controller,
          miniBar: this.readerMiniBar(),
          content: (): void => {
            this.readerContent()
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    // 跟踪宿主区域宽度（vp）：跨过 manualThreshold 阈值时在 HDS 官方胶囊与手动胶囊间切换
    .onAreaChange((_old: Area, newArea: Area): void => {
      const w = newArea.width;
      if (typeof w === 'number') {
        this.hostWidth = w;
        const narrow: boolean = w > 0 && w < this.manualThreshold();
        if (narrow !== this.narrow) {
          this.narrow = narrow;
          AppStorage.setOrCreate(AppKeys.READER_NARROW_BARS, narrow);
        }
      }
    })
  }

  // 窄屏底部渐变遮罩：对齐 HDS 浮动栏背板蒙层（gradientMask 默认色，
  // 浅色 #CCF1F3F5 / 深色 #99000000，高度 = 内容高度 + 32vp），
  // 半透明渐变保证胶囊区域前景可读；触摸穿透不拦截菜单关闭点击
  @Builder
  manualBarsScrim() {
    if (this.barsVisible) {
      Column()
        .width('100%')
        .height(this.capsuleHeight * 2 + 8 + this.barBottomMargin + 32)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: this.scrimColors()
        })
        .hitTestBehavior(HitTestMode.None)
        .transition(
          TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.Linear })
        )
    }
  }

  // （无背景色，对齐 ReaderMenu 顶栏；开合对齐顶栏滑移+渐隐转场节奏）
  @Builder
  manualBars() {
    if (this.barsVisible) {
      Column({ space: 8 }) {
        Column() {
          this.progressBar()
        }
        .width(this.manualBarWidth())
        .height(this.capsuleHeight)
        .justifyContent(FlexAlign.Center)
        .backgroundEffect({ radius: 32, saturation: 1.5 })
        .borderRadius(28)
        .border({ width: 0.5, color: this.bgDark ? '#2EFFFFFF' : '#2E000000' })

        Column() {
          this.settingsBar()
        }
        .width(this.manualBarWidth())
        .height(this.capsuleHeight)
        .justifyContent(FlexAlign.Center)
        .backgroundEffect({ radius: 32, saturation: 1.5 })
        .borderRadius(28)
        .border({ width: 0.5, color: this.bgDark ? '#2EFFFFFF' : '#2E000000' })
      }
      .margin({ bottom: this.barBottomMargin })
      .transition(
        TransitionEffect.translate({ y: 80 })
          .animation({ duration: 200, curve: Curve.FastOutSlowIn })
          .combine(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.Linear }))
      )
    }
  }

  // 窄屏手动双胶囊：进度行（上）+ 设置行（下），纯 backgroundEffect 玻璃

  // （对齐首页 tabBuilder 用法；箭头函数形式在 HDS 浮动页签栏下内容不挂载）
  @Builder
  progressMiniBar() {
    this.progressBar()
  }

  // 页签栏内容（设置胶囊，VERTICAL 下排）
  @Builder
  settingsTabItem() {
    this.settingsBar()
  }

  // 唯一 TabContent：正文（设置行挂页签栏胶囊，进度行挂迷你栏胶囊）
  @Builder
  readerContent() {
    TabContent() {
      this.content()
    }
    .tabBar(this.settingsTabItem())
  }

  // 迷你栏内容（进度胶囊，VERTICAL 上排）：直接 @Builder 调用形式挂入

  @Builder
  emptyBuilder() {
  }

  // 遮罩渐变端点：顶部全透明 → 底部 HDS 背板蒙层默认色（按阅读页背景明暗取色）
  private scrimColors(): Array<[ResourceColor, number]> {
    const colors: Array<[ResourceColor, number]> = this.bgDark
      ? [['#00000000', 0], ['#99000000', 1]]
      : [['#00F1F3F5', 0], ['#CCF1F3F5', 1]];
    return colors;
  }

  // 手动胶囊模式宽度阈值（vp）：两块 barWidth 胶囊并排 + 左右边距(16/24/32vp) + 间隙
  private manualThreshold(): number {
    return this.barWidth * 2 + 64;
  }

  // 手动胶囊宽度：barWidth 上限内不超出宿主区域宽 - 24vp 左右留白
  private manualBarWidth(): number {
    const available: number = this.hostWidth > 0 ? this.hostWidth - 24 : this.barWidth;
    return Math.min(this.barWidth, available);
  }

  // 迷你条配置：垂直堆叠常驻展开（进度行常驻展开，VERTICAL 下不受窄屏联动约束）
  private readerMiniBar(): HdsTabsHostMiniBar {
    return {
      builder: (): void => {
        this.progressMiniBar();
      },
      verticalLayout: true
    };
  }
}

// 阅读器章节导航行：上一章圆钮 + 中间胶囊（BuilderParam 注入）+ 下一章圆钮
@Component
export struct ReaderNavRow {
  @Prop prevActive: boolean = true;
  @Prop nextActive: boolean = true;
  @BuilderParam pill: () => void = this.emptyBuilder;
  onPrev: () => void = (): void => {
  };
  onNext: () => void = (): void => {
  };

  build() {
    Row({ space: 8 }) {
      ReaderChapterButton({
        icon: 'skip_previous',
        isActive: this.prevActive,
        onTap: (): void => {
          this.onPrev();
        }
      })

      this.pill()

      ReaderChapterButton({
        icon: 'skip_next',
        isActive: this.nextActive,
        onTap: (): void => {
          this.onNext();
        }
      })
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
  }

  @Builder
  emptyBuilder() {
  }
}

// 章节跳转圆钮（44×44，禁用态 opacity 0.4；是否可点的 guard 由调用方回调内保留）
@Component
export struct ReaderChapterButton {
  @StorageProp('readerBgDark') bgDark: boolean = false;
  // 窄屏手动胶囊模式（ReaderHdsHost 写入）：无 HDS 材质 colorInvert，
  // sys 图标色跟随系统深浅色而非阅读页明暗，改取 bgDark 高对比硬编码色
  @StorageProp('readerNarrowBars') narrowBars: boolean = false;
  @Prop icon: string = 'skip_previous';
  @Prop isActive: boolean = true;
  onTap: () => void = (): void => {
  };

  build() {
    Column() {
      Image(AppIconRes.get(this.icon))
        .width(24)
        .height(24)
        // sys.color 资源配合材质 colorInvert 自动反色（硬编码颜色不触发反色）；
        // 窄屏手动玻璃下改按阅读页背景明暗取高对比色
        .fillColor(this.narrowBars ? (this.bgDark ? '#FFFFFF' : '#111111') : $r('sys.color.icon_primary'))
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .justifyContent(FlexAlign.Center)
    // 外层玻璃胶囊已有描边，内嵌按钮不再画边框
    .opacity(this.isActive ? 1 : 0.4)
    .onClick(() => {
      this.onTap();
    })
  }
}

// 设置行图标按钮（48×44，高对比色图标）
@Component
export struct ReaderMenuIconButton {
  @StorageProp('readerBgDark') bgDark: boolean = false;
  // 窄屏手动胶囊模式（ReaderHdsHost 写入）：同 ReaderChapterButton，
  // 无 HDS 材质 colorInvert，改按阅读页背景明暗取高对比硬编码色
  @StorageProp('readerNarrowBars') narrowBars: boolean = false;
  @Prop icon: string = 'settings';
  onTap: () => void = (): void => {
  };

  build() {
    Column() {
      Image(AppIconRes.get(this.icon))
        .width(24)
        .height(24)
        // sys.color 资源配合材质 colorInvert 自动反色（硬编码颜色不触发反色）；
        // 窄屏手动玻璃下改按阅读页背景明暗取高对比色
        .fillColor(this.narrowBars ? (this.bgDark ? '#FFFFFF' : '#111111') : $r('sys.color.icon_primary'))
    }
    .width(48)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onTap();
    })
  }
}

// 页码胶囊：当前页 + Slider + 总页数（Slider 松手才翻页）
@Component
export struct ReaderPagePill {
  @StorageProp('readerBgDark') bgDark: boolean = false;
  // 窄屏手动胶囊模式（ReaderHdsHost 写入）：页码文本同图标处理，
  // 无 HDS 材质 colorInvert，改按阅读页背景明暗取高对比硬编码色
  @StorageProp('readerNarrowBars') narrowBars: boolean = false;
  @Prop pos: number = 1;
  @Prop total: number = 1;
  onSeek: (value: number) => void = (value: number): void => {
  };

  build() {
    Row() {
      Text(`${this.pos}`)
        .fontSize(13)
        // sys.color 资源配合材质 colorInvert 自动反色（硬编码颜色不触发反色）；
        // 窄屏手动玻璃下改按阅读页背景明暗取高对比色
        .fontColor(this.narrowBars ? (this.bgDark ? '#FFFFFF' : '#111111') : $r('sys.color.font_primary'))
        .width(24)
        .textAlign(TextAlign.End)
      WideSlider({
        sliderValue: this.pos,
        min: 1,
        max: this.total > 1 ? this.total : 2,
        step: 1,
        dotsEnabled: false,
        // HDS 材质下取 sys.color（与同层文字/图标同源，跟随颜色模式/材质反色；
        // 硬编码 bgDark 键色在深色模式或深色内容下会与 sys 前景正好相反——
        // 文字/图标反色为白而滑条仍为黑）；窄屏手动玻璃无材质 colorInvert，
        // 保持按阅读页背景明暗取高对比硬编码色
        knobTint: this.narrowBars ? (this.bgDark ? '#FFFFFF' : '#111111') : $r('sys.color.icon_primary'),
        fillTint: this.narrowBars ? (this.bgDark ? '#99FFFFFF' : '#99000000') : $r('sys.color.icon_secondary'),
        trackTint: this.narrowBars ? (this.bgDark ? '#40FFFFFF' : '#40000000') : $r('sys.color.icon_tertiary'),
        knobBorderTint: Color.Transparent,
        onChange: (value: number, mode: SliderChangeMode): void => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.onSeek(Math.round(value));
          }
        }
      })
        .layoutWeight(1)
        .margin({ left: 4, right: 4 })
      Text(`${this.total}`)
        .fontSize(13)
        // sys.color 资源配合材质 colorInvert 自动反色（硬编码颜色不触发反色）；
        // 窄屏手动玻璃下改按阅读页背景明暗取高对比色
        .fontColor(this.narrowBars ? (this.bgDark ? '#FFFFFF' : '#111111') : $r('sys.color.font_primary'))
        .width(24)
    }
    .layoutWeight(1)
    .height(44)
  }
}

// 进度/页码指示徽标（菜单收起时右下角悬浮）
@Component
export struct ReaderIndicatorBadge {
  @StorageProp('readerBgDark') bgDark: boolean = false;
  @Prop text: string = '';
  @Prop navBarH: number = 0;

  build() {
    Text(this.text)
      .fontSize(11)
      .fontColor(this.bgDark ? '#FFFFFF' : '#111111')
      .padding({
        left: 8,
        right: 8,
        top: 3,
        bottom: 3
      })
      .borderRadius(10)
      // 液态玻璃悬浮徽标：纯背景模糊（无背景颜色），前景色按背景明暗取高对比色
      .backgroundEffect({ radius: 28, saturation: 1.4 })
      .border({ width: 0.5, color: this.bgDark ? '#2EFFFFFF' : '#2E000000' })
      .margin({
        left: 16,
        top: 16,
        right: 16,
        bottom: this.navBarH + 16
      })
  }
}

// 页眉章节名（常驻左上角小字；hitTest 不拦截点击，菜单打开时由宿主隐藏）
@Component
export struct ReaderHeaderText {
  @StorageProp('readerBgDark') bgDark: boolean = false;
  @Prop text: string = '';
  @Prop statusBarH: number = 0;

  build() {
    Text(this.text)
      .fontSize(11)
      .fontColor(this.bgDark ? '#99FFFFFF' : '#99111111')
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: '80%' })
      .position({ x: 16, y: this.statusBarH + 8 })
      .hitTestBehavior(HitTestMode.None)
  }
}

// 页脚页码（常驻左下角小字；hitTest 不拦截点击，菜单打开时由宿主隐藏）
@Component
export struct ReaderFooterText {
  @StorageProp('readerBgDark') bgDark: boolean = false;
  @Prop text: string = '';
  @Prop navBarH: number = 0;

  build() {
    Text(this.text)
      .fontSize(11)
      .fontColor(this.bgDark ? '#99FFFFFF' : '#99111111')
      .maxLines(1)
      .position({ x: 16, y: '100%' })
      .markAnchor({ y: '100%' })
      .translate({ y: -(this.navBarH + 8) })
      .hitTestBehavior(HitTestMode.None)
  }
}

// 屏幕方向选择 Sheet（两阅读器共用）
@Component
export struct ReaderOrientationSheet {
  @Prop selected: string = 'free';
  onPick: (value: string) => void = (value: string): void => {
  };

  build() {
    PickerSheet({
      options: [$r('app.string.reader_orientation_free'), $r('app.string.reader_orientation_portrait'),
        $r('app.string.reader_orientation_landscape'), $r('app.string.reader_orientation_lock_portrait'),
        $r('app.string.reader_orientation_lock_landscape')],
      icons: READER_ORIENTATION_ICONS,
      selectedIndex: READER_ORIENTATIONS.indexOf(this.selected),
      onPick: (index: number): void => {
        const v: string | undefined = READER_ORIENTATIONS[index];
        if (v !== undefined) {
          this.onPick(v);
        }
      }
    })
  }
}

// 滤镜容器：灰度/反色/亮度/对比度/饱和度滤镜链唯一出现处（对齐 Mihon 滤镜面板）
// 内容经 BuilderParam 注入；onAreaChange 等区域同步留在内容组件上，语义不变
@Component
export struct ReaderFilterArea {
  @Prop grayOn: boolean = false;
  @Prop invOn: boolean = false;
  @Prop brightOn: boolean = false;
  @Prop brightPct: number = 1;
  @Prop contrOn: boolean = false;
  @Prop contrPct: number = 1;
  @Prop satOn: boolean = false;
  @Prop satPct: number = 1;
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Stack() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .grayscale(this.grayOn ? 1 : 0)
    .invert(this.invOn ? 1 : 0)
    .brightness(this.brightOn ? this.brightPct : 1)
    .contrast(this.contrOn ? this.contrPct : 1)
    .saturate(this.satOn ? this.satPct : 1)
  }

  @Builder
  emptyBuilder() {
  }
}

// 章节过渡视图（对齐 Mihon ChapterTransition）：
// kind='next'：上方“已读完”当前章 + 下方“下一章”信息（无下一章时为提示卡片）
// kind='prev'：上方“上一章”信息（无上一章时为提示卡片）+ 下方“当前”章
// 组件自身不处理点击（点击由宿主容器/触摸热区接管），宿主负责全屏居中
@Component
export struct ReaderTransition {
  @Prop kind: string = 'next';
  @Prop currentName: string = '';
  // 相邻章节名；空串表示没有相邻章节（显示“没有下一章/上一章”卡片）
  @Prop targetName: string = '';
  @Prop textCol: string = '#ECEEF2';
  @Prop subCol: string = '#99ECEEF2';

  // 章节信息块：小号次要色标签 + 中号章节名（多行省略）
  @Builder
  chapterBlock(label: ResourceStr, name: string) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(13)
        .fontColor(this.subCol)
        .maxLines(1)
        .width('100%')
      Text(name)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .lineHeight(26)
        .fontColor(this.textCol)
        .maxLines(5)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  // 无相邻章节提示卡片（描边卡片 + info 图标）
  @Builder
  noChapterCard(label: ResourceStr) {
    Row({ space: 12 }) {
      AppIcon({ name: 'info', iconSize: 20, tint: this.textCol })
      Text(label)
        .fontSize(14)
        .lineHeight(20)
        .fontColor(this.textCol)
    }
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: 12
    })
    .borderRadius(12)
    .border({ width: 1, color: this.subCol })
  }

  build() {
    Column() {
      if (this.kind === 'next') {
        // 已读完：当前章节
        this.chapterBlock($r('app.string.transition_finished'), this.currentName)
        // 下一章信息 / 无下一章提示卡片
        if (this.targetName !== '') {
          Column() {
            this.chapterBlock($r('app.string.transition_next'), this.targetName)
          }
          .width('100%')
          .margin({ top: 32 })
        } else {
          Column() {
            this.noChapterCard($r('app.string.transition_no_next'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 32 })
        }
      } else {
        // 上一章信息 / 无上一章提示卡片
        if (this.targetName !== '') {
          Column() {
            this.chapterBlock($r('app.string.transition_previous'), this.targetName)
          }
          .width('100%')
        } else {
          Column() {
            this.noChapterCard($r('app.string.transition_no_previous'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        // 当前章节
        Column() {
          this.chapterBlock($r('app.string.transition_current'), this.currentName)
        }
        .width('100%')
        .margin({ top: 32 })
      }
    }
    .constraintSize({ maxWidth: 520 })
    .width('100%')
    .padding({
      left: 32,
      right: 32,
      top: 16,
      bottom: 16
    })
    .alignItems(HorizontalAlign.Center)
  }
}
