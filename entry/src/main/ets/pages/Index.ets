import { fileIo as fs } from '@kit.CoreFileKit';
import { SheetPreset } from './components/SheetPreset';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyCode } from '@kit.InputKit';
import { AnimatorOptions, AnimatorResult, curves } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { HdsTabsHost, HdsTabsHostController, HdsTabsHostMiniBar } from '../common/HdsTabsHost';
import { HOME_HEADER_H, NavGlassRoot } from '../common/HdsNavHost';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Settings } from '../common/Settings';
import { UpdateService } from '../data/UpdateService';
import { AppDb } from '../data/AppDb';
import { PluginService } from '../data/PluginService';
import { ChapterRepo, HistoryRepo, MangaRepo } from '../data/Repos';import { Util } from '../common/Util';
import { AppKeys } from '../common/AppKeys';
import { CookieJar } from '../net/CookieJar';
import { CoverStore } from '../common/CoverStore';
import { ImageCache } from '../common/ImageCache';
import { TtsPlaybackService, TtsServiceStateHandler } from '../common/TtsPlaybackService';
import { LibraryHeader, LibraryPage } from './LibraryPage';
import { UpdatesHeader, UpdatesPage } from './UpdatesPage';
import { HistoryHeader, HistoryPage } from './HistoryPage';
import { BrowseHeader, BrowsePage } from './BrowsePage';
import { MoreHeader, MorePage } from './MorePage';
import { ContentOpen } from './ContentOpen';
import { AppIcon } from './components/AppIcon';
import { CfVerifySheet } from './components/CfVerifySheet';
import { LockOverlay } from './components/LockOverlay';
import { BtComponentDialog } from './components/BtComponentDialog';
import { Http } from '../net/Http';
import { WebViewFetch } from '../net/WebViewFetch';
import { TtsMiniBar } from './components/novel/TtsMiniBar';
import { BROWSE_MORPH, LIBRARY_MORPH, PathMorph, UPDATES_MORPH } from './components/PathMorph';
import { BrowseSourceParams, DetailParams, GlobalSearchParams, OnboardingParams } from '../model/RouteParams';
import { MangaRecord } from '../model/Models';
import { KnockShare } from '../common/KnockShare';

// 桌面卡片 router 事件载荷（由 EntryAbility.handleCardWant 写入 AppStorage）；
// target='continue' 时为跨设备接续/碰一碰载荷（源身份字段，见 consumeCardAction）
interface CardActionPayload {
  target: string;
  mangaId: number;
  chapterId: number;
  contentType: string;
  query?: string;
  sourceKey?: string;
  mangaUrl?: string;
  chapterUrl?: string;
  page?: number;
  title?: string;
  chapterName?: string;
}

// 隐藏通道页的 JS 桥对象：页面内 fetch 的结果 JSON 经 postResult 回传宿主
// （注册进根 Stack 隐藏 Web 的 javaScriptProxy，结果按 callId 唤醒挂起请求）
class NetFetchProxy {
  postResult(json: string): void {
    WebViewFetch.onResult(json);
  }
}

// 底部导航图标：逐 Tab 复刻 Mihon 的 AnimatedImageVector 动画
// - library/updates/browse: 真 pathData 形变（PathMorph 逐帧插值 AVD valueFrom/valueTo，
//   300ms fast_out_slow_in，ohos.animator 逐帧驱动；中断时从当前进度续走）
// - library 另有静态 angle 层（AVD 中 angle 路径无 target 恒不变）
// - browse: 指针→圆盘形变 + 反向指针洞从圆心长出 + 整体随 morphT 旋转 180°
//   + 中心点 66ms 保持后 100ms 减速弹出（环为静态层）
// - history: 时针静止，环绕箭头绕 (13,12) 整圈旋转 360→0（500ms fast_out_slow_in）
// - more: 三点依次波浪弹跳（保持 83/150/217ms 后 100ms 上跳-133ms 下落-67ms 回正，贝塞尔 0.5,0,0.5,1）
// 形变 pathData 与 Mihon anim_*_enter.xml 逐字一致（PathMorph.ets 已脚本核对）
@Component
struct TabIcon {
  @Prop @Watch('onSelectedChanged') selected: boolean = false;
  @Prop kind: string = '';
  // 选中态落在 primarySoft 底上（侧边 RailItem 胶囊）时需用 onPrimarySoft 保证对比度
  @Prop onSoft: boolean = false;
  @State morphT: number = 0;
  @State histAngle: number = 0;
  @State browseDotScale: number = 0;
  @State moreY0: number = 0;
  @State moreY1: number = 0;
  @State moreY2: number = 0;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  private morphAnimator: AnimatorResult | undefined = undefined;
  private pxPerVp: number = 1;

  aboutToAppear(): void {
    this.pxPerVp = this.getUIContext().vp2px(1);
    if (this.selected) {
      this.morphT = 1;
      this.browseDotScale = 1;
    }
  }

  aboutToDisappear(): void {
    this.morphAnimator?.finish();
    this.morphAnimator = undefined;
  }

  build() {
    if (this.kind === 'more') {
      Row({ space: 2 }) {
        Column()
          .width(4)
          .height(4)
          .borderRadius(2)
          .backgroundColor(this.iconTint())
          .translate({ y: this.moreY0 })
        Column()
          .width(4)
          .height(4)
          .borderRadius(2)
          .backgroundColor(this.iconTint())
          .translate({ y: this.moreY1 })
        Column()
          .width(4)
          .height(4)
          .borderRadius(2)
          .backgroundColor(this.iconTint())
          .translate({ y: this.moreY2 })
      }
      .width(24)
      .height(24)
      .justifyContent(FlexAlign.Center)
    } else if (this.kind === 'history') {
      Stack() {
        AppIcon({ name: 'tab_history_hands', iconSize: 24, tint: this.iconTint() })
        AppIcon({ name: 'tab_history_arrow', iconSize: 24, tint: this.iconTint() })
          .rotate({ angle: this.histAngle, centerX: '54.2%', centerY: '50%' })
      }
      .width(24)
      .height(24)
    } else if (this.kind === 'browse') {
      Stack() {
        AppIcon({ name: 'tab_browse_ring', iconSize: 24, tint: this.iconTint() })
        Path()
          .width(24)
          .height(24)
          .commands(BROWSE_MORPH.valueAt(this.morphT, this.morphScale()))
          .fill(this.iconTint())
          .stroke(Color.Transparent)
          .strokeWidth(0)
        AppIcon({ name: 'tab_browse_dot', iconSize: 24, tint: this.iconTint() })
          .scale({ x: this.browseDotScale, y: this.browseDotScale })
      }
      .width(24)
      .height(24)
      .rotate({ angle: 180 * this.morphT })
    } else {
      Stack() {
        if (this.kind === 'library') {
          AppIcon({ name: 'tab_library_angle', iconSize: 24, tint: this.iconTint() })
        }
        Path()
          .width(24)
          .height(24)
          .commands(this.morphOf().valueAt(this.morphT, this.morphScale()))
          .fill(this.iconTint())
          .stroke(Color.Transparent)
          .strokeWidth(0)
      }
      .width(24)
      .height(24)
    }
  }

  private iconTint(): ResourceColor {
    if (!this.selected) {
      return this.pal.sub;
    }
    return this.onSoft ? this.pal.onPrimarySoft : this.pal.primary;
  }

  // 绘制 Path 的 commands 单位为 px：24 视口图标 24vp，library 为 1080 视口需再乘 24/1080
  private morphScale(): number {
    return this.kind === 'library' ? this.pxPerVp * 24 / 1080 : this.pxPerVp;
  }

  private morphOf(): PathMorph {
    if (this.kind === 'library') {
      return LIBRARY_MORPH;
    }
    return this.kind === 'browse' ? BROWSE_MORPH : UPDATES_MORPH;
  }

  private onSelectedChanged(): void {
    if (this.kind === 'history') {
      this.playHistory(this.selected);
    } else if (this.kind === 'browse') {
      this.playBrowse(this.selected);
    } else if (this.kind === 'more') {
      this.playMore(this.selected);
    } else {
      this.playMorph(this.selected ? 1 : 0);
    }
  }

  // 形变主驱动：begin 取当前 morphT，支持中途反向续走（等效 Mihon 倒放）
  private playMorph(target: number): void {
    if (this.morphAnimator === undefined) {
      this.morphAnimator = this.getUIContext().createAnimator({
        duration: 300,
        easing: 'fast-out-slow-in',
        delay: 0,
        fill: 'forwards',
        direction: 'normal',
        iterations: 1,
        begin: 0,
        end: 1
      });
    }
    const an: AnimatorResult = this.morphAnimator;
    an.onFrame = (): void => {
    };
    an.finish();
    const opts: AnimatorOptions = {
      duration: 300,
      easing: 'fast-out-slow-in',
      delay: 0,
      fill: 'forwards',
      direction: 'normal',
      iterations: 1,
      begin: this.morphT,
      end: target
    };
    try {
      an.reset(opts);
    } catch (e) {
      return;
    }
    an.onFrame = (value: number): void => {
      this.morphT = value;
    };
    an.play();
  }

  // 历史：选中 360→0 逆时针整圈，取消选中反向 0→360（360 与 0 视觉等价，中断时从当前角度续走）
  private playHistory(sel: boolean): void {
    if (sel) {
      if (this.histAngle % 360 === 0) {
        this.histAngle = 360;
      }
      this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, (): void => {
        this.histAngle = 0;
      });
    } else {
      if (this.histAngle % 360 === 0) {
        this.histAngle = 0;
      }
      this.getUIContext().animateTo({ duration: 500, curve: Curve.FastOutSlowIn }, (): void => {
        this.histAngle = 360;
      });
    }
  }

  // 浏览：形变+整体 180° 旋转由 morphT 同帧驱动；中心点 66ms 保持后 100ms 减速弹出
  private playBrowse(sel: boolean): void {
    this.playMorph(sel ? 1 : 0);
    if (sel) {
      this.browseDotScale = 0;
      this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
        {
          duration: 66,
          curve: Curve.FastOutSlowIn,
          event: (): void => {
            this.browseDotScale = 0;
          },
        },
        {
          duration: 100,
          curve: curves.cubicBezierCurve(0, 0, 0.2, 1),
          event: (): void => {
            this.browseDotScale = 1;
          },
        },
      ]);
    } else {
      this.getUIContext().animateTo({ duration: 100, curve: curves.cubicBezierCurve(0.8, 0, 1, 1) }, (): void => {
        this.browseDotScale = 0;
      });
    }
  }

  // 更多：三点依次弹跳；取消选中按原关键帧倒放
  private playMore(sel: boolean): void {
    const mid = sel ? -2.84 : 0.8;
    const end = sel ? 0.8 : -2.84;
    const cb = curves.cubicBezierCurve(0.5, 0, 0.5, 1);
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      {
        duration: 83, curve: cb, event: (): void => {
        this.moreY0 = 0;
      }
      },
      {
        duration: 100, curve: cb, event: (): void => {
        this.moreY0 = mid;
      }
      },
      {
        duration: 133, curve: cb, event: (): void => {
        this.moreY0 = end;
      }
      },
      {
        duration: 67, curve: cb, event: (): void => {
        this.moreY0 = 0;
      }
      },
    ]);
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      {
        duration: 150, curve: cb, event: (): void => {
        this.moreY1 = 0;
      }
      },
      {
        duration: 100, curve: cb, event: (): void => {
        this.moreY1 = mid;
      }
      },
      {
        duration: 133, curve: cb, event: (): void => {
        this.moreY1 = end;
      }
      },
      {
        duration: 67, curve: cb, event: (): void => {
        this.moreY1 = 0;
      }
      },
    ]);
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      {
        duration: 217, curve: cb, event: (): void => {
        this.moreY2 = 0;
      }
      },
      {
        duration: 100, curve: cb, event: (): void => {
        this.moreY2 = mid;
      }
      },
      {
        duration: 133, curve: cb, event: (): void => {
        this.moreY2 = end;
      }
      },
      {
        duration: 67, curve: cb, event: (): void => {
        this.moreY2 = 0;
      }
      },
    ]);
  }
}

// 宽屏 Rail 挂载/卸载转场：出现时自左侧滑入并淡入（越界方向由宽度参数决定），
// 消失时仅淡出——消失瞬间内容区（layoutWeight）同步展开补位，滑出会遮盖
// 正在展开的内容。仅在动画作用域内（animateTo 驱动的状态变化）生效。
function railTransition(w: number): TransitionEffect {
  return TransitionEffect.asymmetric(
    TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.Friction })
      .combine(TransitionEffect.translate({ x: -w })
        .animation({ duration: 250, curve: Curve.Friction })),
    TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Friction }));
}

// 宽屏（lg ≥840vp，平板横屏/PC）侧边导航项：图标在左、文本在右（横排）+ 选中胶囊底 + 鼠标悬停反馈；
// compact=true 时仅显示图标（推入路由页后外层导航收窄为图标栏，避免与设置页自身分类导航形成双栏）
@Component
struct RailItem {
  @Prop kind: string = '';
  @Prop selected: boolean = false;
  @Prop compact: boolean = false;
  title: ResourceStr = '';
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State hovered: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Row() {
      TabIcon({ kind: this.kind, selected: this.selected, onSoft: true })
      if (!this.compact) {
        Text(this.title)
          .fontSize(14)
          .fontColor(this.selected ? this.pal.onPrimarySoft : this.pal.sub)
          .margin({ left: 12 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding(this.compact ? { left: 0, right: 0 } : { left: 16, right: 12 })
    .borderRadius(24)
    .backgroundColor(this.selected ? this.pal.primarySoft : (this.hovered ? this.pal.chip : Color.Transparent))
    .onClick(() => {
      this.onTap();
    })
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
  }
}

@Entry
@Component
struct Index {
  @Provide('navStack') pathStack: NavPathStack = new NavPathStack();
  @State currentTab: number = 0;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageLink('cfChallengeUrl') @Watch('onCfUrlChanged') cfChallengeUrl: string = '';
  @State cfSheetShow: boolean = false;
  // 书架多选数：>0 时隐藏底部页签栏（HDS 官方多选交互：操作栏替换页签栏）
  @StorageLink('libSelectionCount') @Watch('onLibSelectionChanged') libSelectionCount: number = 0;
  @StorageLink('cardAction') @Watch('onCardActionChanged') cardActionJson: string = '';
  // 应用锁锁定态（隐私设置）：true 时全屏覆盖锁定层并拉起系统认证
  @StorageProp('appLocked') appLocked: boolean = false;
  // 插件源网络活动信号：插件成功完成 API 调用（可能刚注入 DNS 直连规则，
  // 如哔咔频道 pin）后去抖重试书架封面回填，把此前因网络不可达失败的封面落盘
  @StorageProp(AppKeys.PLUGIN_NET_TICK) @Watch('onPluginNetTick') pluginNetTick: number = 0;
  @StorageLink('btComponentAsk') btComponentAsk: boolean = false;
  // CF 盾域名请求通道：隐藏 ArkWeb 页控制器 + JS 桥对象
  // （受盾插件请求在隐藏页内同源 fetch，与过盾客户端同 TLS 指纹/Cookie 仓）
  private hiddenWebController: webview.WebviewController = new webview.WebviewController();
  private netFetchProxy: NetFetchProxy = new NetFetchProxy();
  // 详情页“搜索此处”回退主页时切到书架页签执行文本搜索（对齐 Mihon HomeScreen.search → LibraryTab）
  @StorageLink('libSearchReq') @Watch('onLibSearchReq') libSearchReq: number = 0;
  // 一多响应式：窗口宽度 + 已挂载页签位掩码（宽屏下按需挂载后驻留保状态）
  @State windowW: number = 0;
  @State mountedMask: number = 1;
  // 栈顶路由名：'' = 首页；仅设置页（自带左侧分类导航，避免双栏）时外层导航收窄为图标栏，其余路由页均显示完整导航
  @State topRouteName: string = '';
  // 听书进行中才挂载迷你条覆盖层（避免空覆盖层拦截整页触摸）
  @State ttsActive: boolean = false;
  // 首启引导只拉起一次（onPageShow 每次回前台都会触发，需防重复）
  private onboardingLaunched: boolean = false;
  // 返回首页兜底同步的 450ms 延迟定时器：销毁时清理，防对已销毁组件执行 animateTo
  private navSyncTimerId: number = -1;
  private tabsController: HdsTabsHostController = new HdsTabsHostController();

  aboutToAppear(): void {
    this.currentTab = Settings.getStartTab();
    this.mountedMask = 1 << this.currentTab;
    // 拦截路由切换：每次跳转完成后同步栈顶路由名（含路由页之间的跳转）
    this.pathStack.setInterception({
      didShow: (): void => {
        this.syncTopRoute();
      }
    });
    // 订阅听书状态：仅听书进行中才挂载迷你条覆盖层
    TtsPlaybackService.events.onState(this.onTtsState);
    this.ttsActive = TtsPlaybackService.isActive();
    // 插件直接运行于 JSVM 隔离引擎（无 Web 沙箱依赖），启动即加载
    this.loadInstalledPlugins();
    this.autoRefresh();
    this.consumeCardAction();
    // 碰一碰（华为分享链接 + 应用间推送）随主页生命周期注册/注销
    const winId = this.getUIContext().getWindowId();
    if (winId !== undefined) {
      KnockShare.register(winId);
    }
  }

  aboutToDisappear(): void {
    TtsPlaybackService.events.offState(this.onTtsState);
    KnockShare.unregister();
    if (this.navSyncTimerId >= 0) {
      clearTimeout(this.navSyncTimerId);
      this.navSyncTimerId = -1;
    }
  }

  // 首启未完成引导时拉起引导页（页面挂载完成后，对齐 Mihon ShowOnboarding）
  // 隐私同意走 AGC 隐私托管（系统标准弹窗），应用内不再自研同意流程，避免双弹窗
  onPageShow(): void {
    if (this.onboardingLaunched) {
      return;
    }
    this.onboardingLaunched = true;
    if (!Settings.getShownOnboarding()) {
      const params: OnboardingParams = { firstRun: true };
      this.pathStack.pushPathByName('Onboarding', params);
    }
  }

  // 听书迷你条：听书进行中挂入 HdsTabs 浮动条 miniBar（对齐 MusicHome 手机端）
  @Builder
  ttsMiniBar() {
    TtsMiniBar({
      onOpenPlayer: (): void => {
        this.pathStack.pushPathByName('TtsPlayer', null);
      }
    })
  }

  // 首页页签头部（置于 Navigation 标题栏，获得沉浸光感材质）：按当前页签切换；
  // 顶部补 statusBarH——全屏布局下标题栏内容自 y=0 起绘，需避开状态栏
  @Builder
  homeHeader() {
    Column() {
      if (this.currentTab === 0) {
        LibraryHeader()
      } else if (this.currentTab === 1) {
        UpdatesHeader()
      } else if (this.currentTab === 2) {
        HistoryHeader()
      } else if (this.currentTab === 3) {
        BrowseHeader()
      } else {
        MoreHeader()
      }
    }
    .width('100%')
    .padding({ top: this.statusBarH })
  }

  // 路由切换后同步栈顶路由名（驱动外层导航 完整栏 ↔ 图标栏）。
  // 仅在转场结束后（didShow）触发，且宽度变化放入动画：若在转场中途切换

  @Builder
  tabBuilder(kind: string, title: ResourceStr, index: number) {
    Column({ space: 2 }) {
      TabIcon({ kind: kind, selected: this.currentTab === index })
      Text(title)
        .fontSize(11)
        .fontColor(this.currentTab === index ? this.pal.primary : this.pal.sub)
    }
    .justifyContent(FlexAlign.Center)
    .height('100%')
    .onClick(() => {
      // 已选中时再次点击触发快捷操作；未选中时交由 HdsTabs 自行切换
      if (this.currentTab === index) {
        this.onTabReselect(index);
      }
    })
  }

  // 手机端五个页签内容（HdsTabs 与标准 Tabs 回退共用）
  @Builder
  phoneTabContents() {
    TabContent() {
      Column() {
        LibraryPage()
      }
      .height('100%')
      .padding({ top: this.statusBarH + HOME_HEADER_H })
    }
    .tabBar(this.tabBuilder('library', $r('app.string.tab_library'), 0))

    TabContent() {
      Column() {
        UpdatesPage()
      }
      .height('100%')
      .padding({ top: this.statusBarH + HOME_HEADER_H })
    }
    .tabBar(this.tabBuilder('updates', $r('app.string.tab_updates'), 1))

    TabContent() {
      Column() {
        HistoryPage()
      }
      .height('100%')
      .padding({ top: this.statusBarH + HOME_HEADER_H })
    }
    .tabBar(this.tabBuilder('history', $r('app.string.tab_history'), 2))

    TabContent() {
      Column() {
        BrowsePage()
      }
      .height('100%')
      .padding({ top: this.statusBarH + HOME_HEADER_H })
    }
    .tabBar(this.tabBuilder('browse', $r('app.string.tab_browse'), 3))

    TabContent() {
      Column() {
        MorePage()
      }
      .height('100%')
      .padding({ top: this.statusBarH + HOME_HEADER_H })
    }
    .tabBar(this.tabBuilder('more', $r('app.string.tab_more'), 4))
  }

  // 宽屏常驻左侧导航（置于 Navigation 之外）：推入任意路由页（分类/下载/设置等）均不遮挡，PC 上随时切页签
  @Builder
  wideRail() {
    Column({ space: 4 }) {
      RailItem({
        kind: 'library',
        title: $r('app.string.tab_library'),
        selected: this.currentTab === 0,
        onTap: (): void => {
          this.railTap(0);
        }
      })
      RailItem({
        kind: 'updates',
        title: $r('app.string.tab_updates'),
        selected: this.currentTab === 1,
        onTap: (): void => {
          this.railTap(1);
        }
      })
      RailItem({
        kind: 'history',
        title: $r('app.string.tab_history'),
        selected: this.currentTab === 2,
        onTap: (): void => {
          this.railTap(2);
        }
      })
      RailItem({
        kind: 'browse',
        title: $r('app.string.tab_browse'),
        selected: this.currentTab === 3,
        onTap: (): void => {
          this.railTap(3);
        }
      })
      RailItem({
        kind: 'more',
        title: $r('app.string.tab_more'),
        selected: this.currentTab === 4,
        onTap: (): void => {
          this.railTap(4);
        }
      })
    }
    .width(Bp.WIDE_RAIL_W)
    .height('100%')
    .padding({
      top: this.statusBarH + 8,
      left: 12,
      right: 12,
      bottom: 8
    })
    .backgroundColor(this.pal.bg)
    .border({ width: { right: 1 }, color: this.pal.divider })
    // 渲染在 Navigation（Row 中靠后的兄弟节点）之上：推入路由页时首页向左平移
    // 让位，Rail 不被平移中的首页内容盖住
    .zIndex(1)
    // 断点/路由切换时 Rail 挂载卸载的转场：出现从左侧滑入+淡入，
    // 消失仅淡出（内容区同时展开补位，滑出会盖住正在展开的内容）
    .transition(railTransition(Bp.WIDE_RAIL_W))
  }

  // 复刻 Mihon 底部导航快捷操作：再次点击已选中的页签触发 onReselect
  // （HomeScreen.NavigationSuiteItem：已选中时调用 tab.onReselect(navigator)）
  // - 书架: 打开筛选/显示设置弹层；更新: 下载队列；历史: 续读最近作品

  // 宽屏路由页（设置等）内的收窄图标栏：仅图标无文本，避免与设置页自身左侧分类导航形成双栏
  @Builder
  wideRailMini() {
    Column({ space: 4 }) {
      RailItem({
        kind: 'library',

        compact: true,
        selected: this.currentTab === 0,
        onTap: (): void => {
          this.railTap(0);
        }
      })
      RailItem({
        kind: 'updates',
        compact: true,
        selected: this.currentTab === 1,
        onTap: (): void => {
          this.railTap(1);
        }
      })
      RailItem({
        kind: 'history',
        compact: true,
        selected: this.currentTab === 2,
        onTap: (): void => {
          this.railTap(2);
        }
      })
      RailItem({
        kind: 'browse',
        compact: true,
        selected: this.currentTab === 3,
        onTap: (): void => {
          this.railTap(3);
        }
      })
      RailItem({
        kind: 'more',
        compact: true,
        selected: this.currentTab === 4,
        onTap: (): void => {
          this.railTap(4);
        }
      })
    }
    .width(72)
    .height('100%')
    .padding({
      top: this.statusBarH + 8,
      left: 8,
      right: 8,
      bottom: 8
    })
    .backgroundColor(this.pal.bg)
    .border({ width: { right: 1 }, color: this.pal.divider })
    .zIndex(1)
    .transition(railTransition(72))
  }

  // 宽屏内容区：页签首次访问时挂载、驻留保状态（无页签栏，导航由左侧 Rail 承担）
  @Builder
  wideContent() {
    Stack() {
      if (this.tabMounted(0)) {
        Column() {
          LibraryPage()
        }
        .height('100%')
        .padding({ top: this.statusBarH + HOME_HEADER_H })
        .visibility(this.currentTab === 0 ? Visibility.Visible : Visibility.None)
      }
      if (this.tabMounted(1)) {
        Column() {
          UpdatesPage()
        }
        .height('100%')
        .padding({ top: this.statusBarH + HOME_HEADER_H })
        .visibility(this.currentTab === 1 ? Visibility.Visible : Visibility.None)
      }
      if (this.tabMounted(2)) {
        Column() {
          HistoryPage()
        }
        .height('100%')
        .padding({ top: this.statusBarH + HOME_HEADER_H })
        .visibility(this.currentTab === 2 ? Visibility.Visible : Visibility.None)
      }
      if (this.tabMounted(3)) {
        Column() {
          BrowsePage()
        }
        .height('100%')
        .padding({ top: this.statusBarH + HOME_HEADER_H })
        .visibility(this.currentTab === 3 ? Visibility.Visible : Visibility.None)
      }
      if (this.tabMounted(4)) {
        Column() {
          MorePage()
        }
        .height('100%')
        .padding({ top: this.statusBarH + HOME_HEADER_H })
        .visibility(this.currentTab === 4 ? Visibility.Visible : Visibility.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }

  // CF 人机验证半模态内容：Mihon 风格工具栏 + 验证网页
  @Builder
  cfSheetBuilder() {
    CfVerifySheet({
      challengeUrl: this.cfChallengeUrl,
      onClose: (): void => {
        this.cfSheetShow = false;
      }
    })
  }

  // 首页内容（NavGlassRoot 的 content 经命名参数注入——宿主含多个 @BuilderParam，
  // 不能用尾随闭包初始化）
  @Builder
  homeContent() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.isWide()) {
        this.wideContent()
      } else {
        // 手机端 HDS 沉浸浮动页签栏（预览器由 src/mock 的标准 Tabs Mock 等效渲染）
        HdsTabsHost({
          index: this.currentTab,
          scrollable: true,
          barBottomMargin: Math.max(this.navBarH, 6),
          controller: this.tabsController,
          miniBar: this.ttsMiniBarOptions(),
          miniBarEnabled: this.ttsActive,
          onTabChange: (index: number): void => {
            this.currentTab = index;
          }
        }) {
          this.phoneTabContents()
        }
      }
      // 听书迷你条（PC/宽屏无底部页签条）：MusicHome 风格胶囊悬于右下角
      // （28 圆角 + 1px 描边 + 卡片底色，无阴影）
      if (this.isWide() && this.ttsActive) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Column() {
            TtsMiniBar({
              onOpenPlayer: (): void => {
                this.pathStack.pushPathByName('TtsPlayer', null);
              }
            })
          }
          .width(360)
          .height(56)
          .justifyContent(FlexAlign.Center)
          .borderRadius(28)
          .backgroundColor(this.pal.card)
          .border({ width: 1, color: this.pal.divider })
          .margin({ right: 24, bottom: 16 })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.cfSheetShow, this.cfSheetBuilder(),
      SheetPreset.fit(this.windowW, {
        height: SheetSize.LARGE,
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        showClose: false,
        maskColor: 'rgba(0,0,0,0.45)',
        onDisappear: (): void => {
          // 弹层关闭：回写 ArkWeb 会话 Cookie 到 CookieJar，并复位 challenge 标记
          const url = this.cfChallengeUrl;
          if (url !== '') {
            this.cfChallengeUrl = '';
            webview.WebCookieManager.fetchCookie(url).then((cookies: string) => {
              CookieJar.importCookieString(url, cookies);
            }).catch((_e: Error) => {
            });
          }
        }
      }))
  }

  build() {
    Stack() {
      Row() {
        // 宽屏常驻左侧导航：置于 Navigation 之外，推入任意路由页（分类/下载/设置等）均不遮挡；
        // 仅设置页（自带左侧分类导航，避免双栏）收窄为图标栏；沉浸式页（阅读器/播放器）全屏隐藏
        if (this.isWide() && !this.isImmersiveRoute(this.topRouteName)) {
          if (this.topRouteName === 'Settings') {
            this.wideRailMini()
          } else {
            this.wideRail()
          }
        }
        // HDS 液态玻璃导航根宿主（预览器由 src/mock 的标准 Navigation Mock 等效渲染）；
        // 外层 Column 承接 layoutWeight（自定义组件尾随闭包后不可链式调用属性）
        Column() {
          NavGlassRoot({
            header: (): void => {
              this.homeHeader();
            },
            content: (): void => {
              this.homeContent();
            },
            onNavBarStateChange: (isVisible: boolean): void => {
              if (isVisible) {
                if (this.navSyncTimerId >= 0) {
                  clearTimeout(this.navSyncTimerId);
                }
                this.navSyncTimerId = setTimeout((): void => {
                  this.navSyncTimerId = -1;
                  this.syncTopRoute();
                }, 450);
              }
            }
          })
        }
        .layoutWeight(1)
        .height('100%')
      }

      // 应用锁（隐私设置）：锁定时全屏覆盖，拦截一切交互直至系统认证通过
      if (this.appLocked) {
        LockOverlay()
      }
      // BT 组件安装引导：torrent HSP 按需分发缺失时 DownloadService 置位弹窗
      if (this.btComponentAsk) {
        BtComponentDialog()
      }

      // CF 盾域名请求通道：1x1 隐藏 ArkWeb 页（透明 + 触摸透传），受盾插件请求
      // 在其内同源 fetch 执行（详见 net/WebViewFetch.ets；常驻挂载，全局唯一）
      Web({ src: 'about:blank', controller: this.hiddenWebController })
        .javaScriptAccess(true)
        .domStorageAccess(false)
        .fileAccess(false)
        .onlineImageAccess(false)
        .onControllerAttached(() => {
          WebViewFetch.attach(this.hiddenWebController);
          try {
            // 与 CF 验证弹层同款 UA（cf_clearance 与 UA 绑定）
            this.hiddenWebController.setCustomUserAgent(Http.USER_AGENT);
            this.hiddenWebController.onActive();
          } catch (e) {
            hilog.error(0x0C0F, 'Index', 'hidden web attach failed: %{public}s', (e as Error).message);
          }
        })
        .onPageEnd(() => {
          WebViewFetch.onPageLoaded();
        })
        .javaScriptProxy({
          object: this.netFetchProxy,
          name: 'honyomiNet',
          methodList: ['postResult'],
          controller: this.hiddenWebController
        })
        .width(1)
        .height(1)
        .opacity(0)
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
    // 桌面键鼠交互：根节点持有焦点接收按键事件（键盘快捷键全局宿主）
    .focusable(true)
    .defaultFocus(true)
    // Ctrl+1..5 快速切换页签（与侧边 Rail 点击行为一致：路由页内先清栈回首页）
    .keyboardShortcut('1', [ModifierKey.CTRL], (): void => {
      this.railTap(0);
    })
    .keyboardShortcut('2', [ModifierKey.CTRL], (): void => {
      this.railTap(1);
    })
    .keyboardShortcut('3', [ModifierKey.CTRL], (): void => {
      this.railTap(2);
    })
    .keyboardShortcut('4', [ModifierKey.CTRL], (): void => {
      this.railTap(3);
    })
    .keyboardShortcut('5', [ModifierKey.CTRL], (): void => {
      this.railTap(4);
    })
    // Ctrl+F 全局搜索
    .keyboardShortcut('f', [ModifierKey.CTRL], (): void => {
      this.pathStack.pushPathByName('GlobalSearch', null);
    })
    // Esc：先关 CF 验证弹层，再广播关闭各页半模态弹层（阅读器/播放器等自行处理 Esc 的页面不受影响）
    .onKeyEvent((event: KeyEvent) => {
      this.onRootKeyEvent(event);
    })
    // 一多断点跟踪：外层 Row = 整窗宽度（含 Rail），避免 840vp 临界值来回抖动；
    // 同步发布到 AppStorage，供各页面按断点做限宽/边距适配
    .onAreaChange((_old: Area, newArea: Area) => {
      const w = newArea.width;
      if (typeof w === 'number') {
        // 跨越 lg 断点（横竖屏切换）时置于动画作用域内：Rail 挂载/卸载播放转场，
        // 由宽转窄淡出让位、由窄转宽滑入补位；未跨断点的普通缩放保持即时布局
        const apply = (): void => {
          this.windowW = w;
          AppStorage.setOrCreate(AppKeys.WINDOW_W, w);
          // 页签浮动条避让高度：宽屏无底部页签条时为 0，页签页不再预留大片底部空白
          AppStorage.setOrCreate(AppKeys.TAB_PAD_H, Bp.isWide(w) ? 0 : 76);
        };
        if (Bp.isWide(this.windowW) !== Bp.isWide(w)) {
          this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, apply);
        } else {
          apply();
        }
      }
    })
  }

  private readonly onTtsState: TtsServiceStateHandler =
    (_playing: boolean, _paused: boolean, _mangaId: number, _chapterId: number): void => {
      this.ttsActive = TtsPlaybackService.isActive();
    };

  // lg 断点（≥840vp）：底部页签切换为侧边导航栏（华为大屏导航规范）
  private isWide(): boolean {
    return Bp.isWide(this.windowW);
  }

  private tabMounted(index: number): boolean {
    return (this.mountedMask & (1 << index)) !== 0;
  }

  private switchTab(index: number): void {
    if (!this.tabMounted(index)) {
      this.mountedMask = this.mountedMask | (1 << index);
    }
    this.currentTab = index;
  }

  // CF 验证 URL 变化：弹出底部半模态验证弹层（液态玻璃）。弹层位于窗口 popup 层，

  // 导航宽度，内容区会跟着重排，出现首页透出到推入页下层、页面闪白等问题
  private syncTopRoute(): void {
    const names: string[] = this.pathStack.getAllPathName();
    const top: string = names.length > 0 ? names[names.length - 1] : '';
    if (top === this.topRouteName) {
      return;
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, (): void => {
      this.topRouteName = top;
    });
  }

  // 侧边导航点击：首页内切换页签/触发快捷操作；路由页内点击先清栈回首页再切换
  private railTap(index: number): void {
    if (this.topRouteName !== '') {
      this.pathStack.clear();
      this.switchTab(index);
      return;
    }
    if (this.currentTab === index) {
      this.onTabReselect(index);
    } else {
      this.switchTab(index);
    }
  }

  // 回填书架持久化封面：localCover 缺失、文件被清或源封面已变更时重新持久化；

  // 沉浸式路由（阅读器/听书/视频播放器/新手引导）：全屏体验，宽屏下不显示左侧导航
  private isImmersiveRoute(name: string): boolean {
    return name === 'Reader' || name === 'NovelReader'
      || name === 'TtsPlayer' || name === 'VideoPlayer'
      || name === 'Onboarding';
  }

  // - 浏览: 全局搜索；更多: 设置页
  private onTabReselect(index: number): void {
    if (index === 0) {
      AppStorage.setOrCreate(AppKeys.LIB_RESELECT, (AppStorage.get<number>(AppKeys.LIB_RESELECT) ?? 0) + 1);
    } else if (index === 1) {
      this.pathStack.pushPathByName('Downloads', null);
    } else if (index === 2) {
      AppStorage.setOrCreate(AppKeys.HISTORY_RESELECT, (AppStorage.get<number>(AppKeys.HISTORY_RESELECT) ?? 0) + 1);
    } else if (index === 3) {
      this.pathStack.pushPathByName('GlobalSearch', null);
    } else if (index === 4) {
      this.pathStack.pushPathByName('Settings', null);
    }
  }

  // 进入多选隐藏页签栏，退出多选恢复（官方隐藏/显示动效）；宽屏侧边栏常驻不参与
  private onLibSelectionChanged(): void {
    if (this.isWide()) {
      return;
    }
    if (this.libSelectionCount > 0) {
      this.tabsController.applyHideAnimation();
    } else {
      this.tabsController.applyShowAnimation();
    }
  }

  // 详情页回退主页的书架搜索请求：切到书架页签（搜索词由 LibraryPage 消费 libSearchQuery）
  private onLibSearchReq(): void {
    this.switchTab(0);
  }

  // 根节点按键：Esc 关闭 CF 验证弹层或广播关闭各页半模态弹层；
  // 书库页签下 Ctrl+A 全选、Delete 删除选中（信号由 LibraryPage 消费）
  // （路由页自行处理 Esc 的场景：焦点在路由页上时事件沿焦点链冒泡至此，
  //  广播仅递增计数，未打开弹层的页面 @Watch 为幂等空操作；
  //  焦点在文本框内时 Ctrl+A/Enter 等被输入框消费，不会冒泡至此）
  private onRootKeyEvent(event: KeyEvent): void {
    if (event.type !== KeyType.Down) {
      return;
    }
    const code = event.keyCode;
    if (code === KeyCode.KEYCODE_ESCAPE) {
      if (this.cfSheetShow) {
        this.cfSheetShow = false;
        return;
      }
      AppStorage.setOrCreate(AppKeys.SHEET_ESC, (AppStorage.get<number>(AppKeys.SHEET_ESC) ?? 0) + 1);
      return;
    }
    if (this.topRouteName !== '' || this.currentTab !== 0) {
      return;
    }
    if (this.ctrlPressed(event) && code === KeyCode.KEYCODE_A) {
      AppStorage.setOrCreate(AppKeys.LIB_SELECT_ALL_REQ,
        (AppStorage.get<number>(AppKeys.LIB_SELECT_ALL_REQ) ?? 0) + 1);
      return;
    }
    if (code === KeyCode.KEYCODE_FORWARD_DEL) {
      AppStorage.setOrCreate(AppKeys.LIB_DELETE_SEL_REQ,
        (AppStorage.get<number>(AppKeys.LIB_DELETE_SEL_REQ) ?? 0) + 1);
    }
  }

  private ctrlPressed(event: KeyEvent): boolean {
    return event.getModifierKeyState !== undefined && event.getModifierKeyState(['Ctrl']);
  }

  // 桌面卡片点击 / 意图框架（小艺）导航：切页签或跳阅读器/详情页
  private onCardActionChanged(): void {
    this.consumeCardAction();
  }

  private consumeCardAction(): void {
    if (this.cardActionJson === '') {
      return;
    }
    const json = this.cardActionJson;
    this.cardActionJson = '';
    let raw: CardActionPayload;
    try {
      raw = JSON.parse(json) as CardActionPayload;
    } catch (e) {
      return;
    }
    if (raw === undefined || raw === null || raw.target === undefined) {
      return;
    }
    if (raw.target === 'updates') {
      this.switchTab(1);
      return;
    }
    if (raw.target === 'upcoming') {
      this.switchTab(1);
      this.pathStack.pushPathByName('Upcoming', null);
      return;
    }
    if (raw.target === 'history') {
      this.switchTab(2);
      return;
    }
    if (raw.target === 'ttsplayer') {
      this.pathStack.pushPathByName('TtsPlayer', null);
      return;
    }
    // 意图框架（功能一步达）目标：直达功能页
    if (raw.target === 'library') {
      this.switchTab(0);
      return;
    }
    if (raw.target === 'browse') {
      this.switchTab(3);
      return;
    }
    if (raw.target === 'more') {
      this.switchTab(4);
      return;
    }
    if (raw.target === 'downloads') {
      this.switchTab(1);
      this.pathStack.pushPathByName('Downloads', null);
      return;
    }
    if (raw.target === 'globalsearch') {
      this.switchTab(3);
      const q: string = raw.query !== undefined ? raw.query.trim() : '';
      if (q !== '') {
        const searchParams: GlobalSearchParams = { query: q };
        this.pathStack.pushPathByName('GlobalSearch', searchParams);
      } else {
        this.pathStack.pushPathByName('GlobalSearch', null);
      }
      return;
    }
    // 外部"打开方式"导入书籍后：跳转指定源浏览页（携带搜索词定位导入书籍）
    if (raw.target === 'browsesource' && raw.sourceKey !== undefined && raw.sourceKey !== '') {
      this.switchTab(3);
      const bsParams: BrowseSourceParams = {
        sourceKey: raw.sourceKey,
        mode: 'popular',
        query: raw.query !== undefined ? raw.query : ''
      };
      this.pathStack.pushPathByName('BrowseSource', bsParams);
      return;
    }
    if (raw.target === 'settings') {
      this.switchTab(4);
      this.pathStack.pushPathByName('Settings', null);
      return;
    }
    if (raw.target === 'categories') {
      this.switchTab(0);
      this.pathStack.pushPathByName('Categories', null);
      return;
    }
    if (raw.target === 'stats') {
      this.switchTab(4);
      this.pathStack.pushPathByName('Stats', null);
      return;
    }
    if (raw.target === 'reader' && raw.mangaId > 0 && raw.chapterId > 0) {
      if (raw.contentType === 'novel' || raw.contentType === 'video' || raw.contentType === 'manga') {
        ContentOpen.push(this.pathStack, raw.contentType, raw.mangaId, raw.chapterId);
      } else {
        const context = Util.hostAbilityContext(this.getUIContext());
        AppDb.ready(context).then(() => {
          ContentOpen.open(this.pathStack, raw.mangaId, raw.chapterId);
        }).catch((e: Error) => {
          hilog.warn(0x0001, 'Index', 'card action db ready failed: %{public}s', `${e}`);
          Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
        });
      }
      return;
    }
    // 跨设备接续/碰一碰续读：以源身份（sourceKey+mangaUrl+chapterUrl）定位本机记录
    if (raw.target === 'continue') {
      this.resolveContinueTarget(raw);
      return;
    }
    if (raw.target === 'detail' && raw.mangaId > 0) {
      const params: DetailParams = { mangaId: raw.mangaId };
      this.pathStack.pushPathByName('MangaDetail', params);
    }
  }

  // 接续解析：找到作品+章节→恢复进度后打开对应阅读器；仅找到作品→详情页；
  // 本机无记录→按标题全局搜索兜底；进度语义随内容类型（漫画页码/小说千分比/视频毫秒），
  // 三类阅读器均以 chapter.lastPageRead 恢复进度
  private resolveContinueTarget(raw: CardActionPayload): void {
    const sourceKey = raw.sourceKey !== undefined ? raw.sourceKey : '';
    const mangaUrl = raw.mangaUrl !== undefined ? raw.mangaUrl : '';
    if (sourceKey === '' || mangaUrl === '') {
      return;
    }
    const context = Util.hostAbilityContext(this.getUIContext());
    AppDb.ready(context).then(async () => {
      const manga = await MangaRepo.getBySourceUrl(sourceKey, mangaUrl);
      if (manga === undefined) {
        this.continueFallback(raw.title);
        return;
      }
      const chapterUrl = raw.chapterUrl !== undefined ? raw.chapterUrl : '';
      if (chapterUrl === '') {
        const params: DetailParams = { mangaId: manga.id };
        this.pathStack.pushPathByName('MangaDetail', params);
        return;
      }
      const chapter = await ChapterRepo.getByMangaUrl(manga.id, chapterUrl);
      if (chapter === undefined) {
        const params: DetailParams = { mangaId: manga.id };
        this.pathStack.pushPathByName('MangaDetail', params);
        return;
      }
      const page = raw.page !== undefined && raw.page > 0 ? Math.floor(raw.page) : 0;
      if (page > 0) {
        ChapterRepo.setLastPageRead(chapter.id, page).catch((e: Object): void => {
          hilog.warn(0x0001, 'Index', 'continue set page failed: %{public}s', `${e}`);
        });
        HistoryRepo.upsert(manga.id, chapter.id, page).catch((e: Object): void => {
          hilog.warn(0x0001, 'Index', 'continue upsert history failed: %{public}s', `${e}`);
        });
      }
      ContentOpen.push(this.pathStack, manga.contentType, manga.id, chapter.id);
    }).catch((e: Error) => {
      hilog.warn(0x0001, 'Index', 'continue resolve failed: %{public}s', e.message);
      Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
    });
  }

  // 本机无对应作品时按标题全局搜索兜底（引导在已安装源中重新找到同书）
  private continueFallback(title: string | undefined): void {
    const q = title !== undefined ? title.trim() : '';
    if (q !== '') {
      this.switchTab(3);
      const searchParams: GlobalSearchParams = { query: q };
      this.pathStack.pushPathByName('GlobalSearch', searchParams);
    } else {
      Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
    }
  }

  // 压在任意 NavDestination（含插件浏览页）之上；弹层存活期间 URL 再变化由其内部热切换
  private onCfUrlChanged(): void {
    if (this.cfChallengeUrl === '') {
      return;
    }
    this.cfSheetShow = true;
  }

  // 加载已安装插件并广播刷新（每个插件在专属 Worker 的隔离 JSVM 引擎中执行）
  private async loadInstalledPlugins(): Promise<void> {
    try {
      await PluginService.loadAll();
    } catch (e) {
      // 加载失败不阻塞主界面
    }
    PluginService.markDirty();
    // 插件注册完成后回填书架持久化封面（旧条目/封面变更/文件缺失）
    this.backfillLibraryCovers();
  }

  // 插件源网络活动去抖定时器：连续 API 调用（如哔咔 V() 连续 pin 多个域名）
  // 合并为一次回填重试；销毁时清理，防对已销毁组件执行回填
  private pluginNetRetryTimer: number = -1;

  private onPluginNetTick(): void {
    // 清空封面下载失败记录：DNS 直连规则可能刚落地，后续解析立即重试网络
    ImageCache.resetFailed();
    hilog.info(0x0001, 'Index', 'plugin net tick, cover backfill retry in 5s');
    if (this.pluginNetRetryTimer >= 0) {
      clearTimeout(this.pluginNetRetryTimer);
    }
    this.pluginNetRetryTimer = setTimeout((): void => {
      this.pluginNetRetryTimer = -1;
      this.backfillLibraryCovers();
    }, 5000);
  }

  // 逐条串行落盘（下载+AVIF→JPEG 转码），完成后统一写 libDirty 刷新书架
  private async backfillLibraryCovers(): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const list: MangaRecord[] = await MangaRepo.getLibrary();
      let changed = 0;
      let failed = 0;
      for (const m of list) {
        const url = m.origThumbnail !== '' ? m.origThumbnail : m.thumbnailUrl;
        if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
          continue;
        }
        const stale = m.localCover === '' || !fs.accessSync(m.localCover) || m.localCoverUrl !== url;
        if (!stale) {
          continue;
        }
        const path = await CoverStore.persistFromUrl(context, m.id, url, m.sourceKey);
        if (path !== '') {
          await MangaRepo.setLocalCover(m.id, path, url);
          changed++;
          hilog.info(0x0001, 'Index', 'cover persisted mangaId=%{public}d', m.id);
        } else {
          failed++;
        }
      }
      if (changed > 0) {
        AppStorage.set(AppKeys.LIB_DIRTY, (AppStorage.get<number>(AppKeys.LIB_DIRTY) ?? 0) + 1);
      }
      if (changed > 0 || failed > 0) {
        hilog.info(0x0001, 'Index', 'backfill covers: %{public}d ok, %{public}d failed', changed, failed);
      }
    } catch (e) {
      hilog.warn(0x0001, 'Index', 'backfill covers failed: %{public}s', `${e}`);
    }
  }

  // 静默自动刷新：距上次刷新超过 12 小时才触发
  private async autoRefresh(): Promise<void> {
    const last = Settings.getLastRefreshAt();
    if (Date.now() - last < 12 * 60 * 60 * 1000) {
      return;
    }
    // 批量更新网络/电源限制不满足时不推进时间戳，下次启动仍会重试
    const blockReason = UpdateService.checkUpdateRestrictions();
    if (blockReason !== '') {
      hilog.info(0x0001, 'Index', 'skip autoRefresh: %{public}s', blockReason);
      return;
    }
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const newCount = await UpdateService.refreshLibrary(context);
      // 刷新成功才推进时间戳：失败时下次启动仍会重试
      Settings.setLastRefreshAt(Date.now());
      if (newCount > 0) {
        AppStorage.setOrCreate(AppKeys.LIB_DIRTY, (AppStorage.get<number>(AppKeys.LIB_DIRTY) ?? 0) + 1);
      }
    } catch (e) {
      // 静默失败：不更新时间戳，仅记录日志
      hilog.warn(0x0001, 'Index', 'autoRefresh failed: %{public}s', `${e}`);
    }
  }

  // 听书迷你条配置：builder 常驻配置；是否挂入 HDS 由 miniBarEnabled(ttsActive)
  // 控制（miniBar 为普通成员仅创建时赋值，动态显隐必须走 @Prop 开关重新应用样式）
  private ttsMiniBarOptions(): HdsTabsHostMiniBar | undefined {
    return {
      builder: (): void => {
        this.ttsMiniBar();
      }
    };
  }
}
