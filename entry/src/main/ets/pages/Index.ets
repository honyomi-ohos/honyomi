import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { curves, AnimatorResult, AnimatorOptions } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { HdsTabs, hdsMaterial, HdsTabsController, HdsAnimationMode, HdsTabsMiniBar } from '@kit.UIDesignKit';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Settings } from '../common/Settings';
import { UpdateService } from '../data/UpdateService';
import { AppDb } from '../data/AppDb';
import { PluginService } from '../data/PluginService';
import { MangaRepo } from '../data/Repos';
import { Util } from '../common/Util';
import { CookieJar } from '../net/CookieJar';
import { CoverStore } from '../common/CoverStore';
import { TtsPlaybackService, TtsServiceStateHandler } from '../common/TtsPlaybackService';
import { LibraryPage } from './LibraryPage';
import { UpdatesPage } from './UpdatesPage';
import { HistoryPage } from './HistoryPage';
import { BrowsePage } from './BrowsePage';
import { MorePage } from './MorePage';
import { ContentOpen } from './ContentOpen';
import { AppIcon } from './components/AppIcon';
import { CfVerifySheet } from './components/CfVerifySheet';
import { TtsMiniBar } from './components/novel/TtsMiniBar';
import { UPDATES_MORPH, LIBRARY_MORPH, BROWSE_MORPH, PathMorph } from './components/PathMorph';
import { DetailParams, GlobalSearchParams, OnboardingParams } from '../model/RouteParams';
import { MangaRecord } from '../model/Models';

// 桌面卡片 router 事件载荷（由 EntryAbility.handleCardWant 写入 AppStorage）
interface CardActionPayload {
  target: string;
  mangaId: number;
  chapterId: number;
  contentType: string;
  query?: string;
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
      { duration: 83, curve: cb, event: (): void => { this.moreY0 = 0; } },
      { duration: 100, curve: cb, event: (): void => { this.moreY0 = mid; } },
      { duration: 133, curve: cb, event: (): void => { this.moreY0 = end; } },
      { duration: 67, curve: cb, event: (): void => { this.moreY0 = 0; } },
    ]);
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      { duration: 150, curve: cb, event: (): void => { this.moreY1 = 0; } },
      { duration: 100, curve: cb, event: (): void => { this.moreY1 = mid; } },
      { duration: 133, curve: cb, event: (): void => { this.moreY1 = end; } },
      { duration: 67, curve: cb, event: (): void => { this.moreY1 = 0; } },
    ]);
    this.getUIContext().keyframeAnimateTo({ iterations: 1 }, [
      { duration: 217, curve: cb, event: (): void => { this.moreY2 = 0; } },
      { duration: 100, curve: cb, event: (): void => { this.moreY2 = mid; } },
      { duration: 133, curve: cb, event: (): void => { this.moreY2 = end; } },
      { duration: 67, curve: cb, event: (): void => { this.moreY2 = 0; } },
    ]);
  }

  build() {
    if (this.kind === 'more') {
      Row({ space: 2 }) {
        Circle().width(4).height(4).fill(this.iconTint()).translate({ y: this.moreY0 })
        Circle().width(4).height(4).fill(this.iconTint()).translate({ y: this.moreY1 })
        Circle().width(4).height(4).fill(this.iconTint()).translate({ y: this.moreY2 })
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
}

// 宽屏（lg ≥840vp，平板横屏/PC）侧边导航项：图标在左、文本在右（横排）+ 选中胶囊底 + 鼠标悬停反馈
@Component
struct RailItem {
  @Prop kind: string = '';
  @Prop selected: boolean = false;
  title: ResourceStr = '';
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State hovered: boolean = false;
  onTap: () => void = () => {};

  build() {
    Row() {
      TabIcon({ kind: this.kind, selected: this.selected, onSoft: true })
      Text(this.title)
        .fontSize(14)
        .fontColor(this.selected ? this.pal.onPrimarySoft : this.pal.sub)
        .margin({ left: 12 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(48)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 12 })
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
  // 详情页“搜索此处”回退主页时切到书架页签执行文本搜索（对齐 Mihon HomeScreen.search → LibraryTab）
  @StorageLink('libSearchReq') @Watch('onLibSearchReq') libSearchReq: number = 0;
  // 一多响应式：窗口宽度 + 已挂载页签位掩码（宽屏下按需挂载后驻留保状态）
  @State windowW: number = 0;
  @State mountedMask: number = 1;
  // 首启引导只拉起一次（onPageShow 每次回前台都会触发，需防重复）
  private onboardingLaunched: boolean = false;
  private tabsController: HdsTabsController = new HdsTabsController();
  // 无 HDS 运行时环境（预览器）的标准 Tabs 回退控制器
  private fallbackTabsController: TabsController = new TabsController();
  // HDS 组件（@kit.UIDesignKit）由系统 HDS 运行时注册，预览器环境 HdsTabs 为
  // null；探测失败时回退标准 Tabs，保证预览器可正常渲染（真机走 HdsTabs 不变）
  private hdsAvailable: boolean = HdsTabs !== null && HdsTabs !== undefined;
  // 听书进行中才挂载迷你条覆盖层（避免空覆盖层拦截整页触摸）
  @State ttsActive: boolean = false;
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

  // 复刻 Mihon 底部导航快捷操作：再次点击已选中的页签触发 onReselect
  // （HomeScreen.NavigationSuiteItem：已选中时调用 tab.onReselect(navigator)）
  // - 书架: 打开筛选/显示设置弹层；更新: 下载队列；历史: 续读最近作品
  // - 浏览: 全局搜索；更多: 设置页
  private onTabReselect(index: number): void {
    if (index === 0) {
      AppStorage.setOrCreate('libReselect', (AppStorage.get<number>('libReselect') ?? 0) + 1);
    } else if (index === 1) {
      this.pathStack.pushPathByName('Downloads', null);
    } else if (index === 2) {
      AppStorage.setOrCreate('historyReselect', (AppStorage.get<number>('historyReselect') ?? 0) + 1);
    } else if (index === 3) {
      this.pathStack.pushPathByName('GlobalSearch', null);
    } else if (index === 4) {
      this.pathStack.pushPathByName('Settings', null);
    }
  }

  // 进入多选隐藏页签栏，退出多选恢复（HdsTabsController 官方隐藏/显示动效）；宽屏侧边栏常驻不参与
  private onLibSelectionChanged(): void {
    if (this.isWide() || !this.hdsAvailable) {
      return;
    }
    if (this.libSelectionCount > 0) {
      this.tabsController.applyHideAnimation(HdsAnimationMode.CLICK_ANIMATION);
    } else {
      this.tabsController.applyShowAnimation(HdsAnimationMode.CLICK_ANIMATION);
    }
  }

  aboutToAppear(): void {
    this.currentTab = Settings.getStartTab();
    this.mountedMask = 1 << this.currentTab;
    // 订阅听书状态：仅听书进行中才挂载迷你条覆盖层
    TtsPlaybackService.events.onState(this.onTtsState);
    this.ttsActive = TtsPlaybackService.isActive();
    // 插件直接运行于 JSVM 隔离引擎（无 Web 沙箱依赖），启动即加载
    this.loadInstalledPlugins();
    this.autoRefresh();
    this.consumeCardAction();
  }

  aboutToDisappear(): void {
    TtsPlaybackService.events.offState(this.onTtsState);
  }

  // 首启未完成引导时拉起引导页（页面挂载完成后，对齐 Mihon ShowOnboarding）
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

  // 详情页回退主页的书架搜索请求：切到书架页签（搜索词由 LibraryPage 消费 libSearchQuery）
  private onLibSearchReq(): void {
    this.switchTab(0);
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
    if (raw.target === 'detail' && raw.mangaId > 0) {
      const params: DetailParams = { mangaId: raw.mangaId };
      this.pathStack.pushPathByName('MangaDetail', params);
    }
  }

  // CF 验证 URL 变化：弹出底部半模态验证弹层（液态玻璃）。弹层位于窗口 popup 层，
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

  // 回填书架持久化封面：localCover 缺失、文件被清或源封面已变更时重新持久化；
  // 逐条串行落盘（下载+AVIF→JPEG 转码），完成后统一写 libDirty 刷新书架
  private async backfillLibraryCovers(): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const list: MangaRecord[] = await MangaRepo.getLibrary();
      let changed = 0;
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
        }
      }
      if (changed > 0) {
        AppStorage.set('libDirty', (AppStorage.get<number>('libDirty') ?? 0) + 1);
        hilog.info(0x0001, 'Index', 'backfill covers done: %{public}d', changed);
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
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const newCount = await UpdateService.refreshLibrary(context);
      // 刷新成功才推进时间戳：失败时下次启动仍会重试
      Settings.setLastRefreshAt(Date.now());
      if (newCount > 0) {
        AppStorage.setOrCreate('libDirty', (AppStorage.get<number>('libDirty') ?? 0) + 1);
      }
    } catch (e) {
      // 静默失败：不更新时间戳，仅记录日志
      hilog.warn(0x0001, 'Index', 'autoRefresh failed: %{public}s', `${e}`);
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

  // 听书未进行时不配置 miniBar，避免空胶囊
  private ttsMiniBarOptions(): HdsTabsMiniBar | undefined {
    if (!this.ttsActive) {
      return undefined;
    }
    return {
      miniBarBuilder: (): void => {
        this.ttsMiniBar();
      }
    };
  }

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
      .padding({ top: this.statusBarH })
    }
    .tabBar(this.tabBuilder('library', $r('app.string.tab_library'), 0))

    TabContent() {
      Column() {
        UpdatesPage()
      }
      .height('100%')
      .padding({ top: this.statusBarH })
    }
    .tabBar(this.tabBuilder('updates', $r('app.string.tab_updates'), 1))

    TabContent() {
      Column() {
        HistoryPage()
      }
      .height('100%')
      .padding({ top: this.statusBarH })
    }
    .tabBar(this.tabBuilder('history', $r('app.string.tab_history'), 2))

    TabContent() {
      Column() {
        BrowsePage()
      }
      .height('100%')
      .padding({ top: this.statusBarH })
    }
    .tabBar(this.tabBuilder('browse', $r('app.string.tab_browse'), 3))

    TabContent() {
      Column() {
        MorePage()
      }
      .height('100%')
      .padding({ top: this.statusBarH })
    }
    .tabBar(this.tabBuilder('more', $r('app.string.tab_more'), 4))
  }

  // 宽屏主界面：左侧固定导航栏 + 右侧内容区（页签首次访问时挂载、驻留保状态）
  @Builder
  wideHome() {
    Row() {
      Column({ space: 4 }) {
        RailItem({
          kind: 'library', title: $r('app.string.tab_library'),
          selected: this.currentTab === 0,
          onTap: (): void => { this.currentTab === 0 ? this.onTabReselect(0) : this.switchTab(0); }
        })
        RailItem({
          kind: 'updates', title: $r('app.string.tab_updates'),
          selected: this.currentTab === 1,
          onTap: (): void => { this.currentTab === 1 ? this.onTabReselect(1) : this.switchTab(1); }
        })
        RailItem({
          kind: 'history', title: $r('app.string.tab_history'),
          selected: this.currentTab === 2,
          onTap: (): void => { this.currentTab === 2 ? this.onTabReselect(2) : this.switchTab(2); }
        })
        RailItem({
          kind: 'browse', title: $r('app.string.tab_browse'),
          selected: this.currentTab === 3,
          onTap: (): void => { this.currentTab === 3 ? this.onTabReselect(3) : this.switchTab(3); }
        })
        RailItem({
          kind: 'more', title: $r('app.string.tab_more'),
          selected: this.currentTab === 4,
          onTap: (): void => { this.currentTab === 4 ? this.onTabReselect(4) : this.switchTab(4); }
        })
      }
      .width(200)
      .height('100%')
      .padding({ top: this.statusBarH + 8, left: 12, right: 12, bottom: 8 })
      .backgroundColor(this.pal.bg)
      .border({ width: { right: 1 }, color: this.pal.divider })

      Stack() {
        if (this.tabMounted(0)) {
          Column() {
            LibraryPage()
          }
          .height('100%')
          .padding({ top: this.statusBarH })
          .visibility(this.currentTab === 0 ? Visibility.Visible : Visibility.None)
        }
        if (this.tabMounted(1)) {
          Column() {
            UpdatesPage()
          }
          .height('100%')
          .padding({ top: this.statusBarH })
          .visibility(this.currentTab === 1 ? Visibility.Visible : Visibility.None)
        }
        if (this.tabMounted(2)) {
          Column() {
            HistoryPage()
          }
          .height('100%')
          .padding({ top: this.statusBarH })
          .visibility(this.currentTab === 2 ? Visibility.Visible : Visibility.None)
        }
        if (this.tabMounted(3)) {
          Column() {
            BrowsePage()
          }
          .height('100%')
          .padding({ top: this.statusBarH })
          .visibility(this.currentTab === 3 ? Visibility.Visible : Visibility.None)
        }
        if (this.tabMounted(4)) {
          Column() {
            MorePage()
          }
          .height('100%')
          .padding({ top: this.statusBarH })
          .visibility(this.currentTab === 4 ? Visibility.Visible : Visibility.None)
        }
      }
      .layoutWeight(1)
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .width('100%')
    .height('100%')
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

  build() {
    Navigation(this.pathStack) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.isWide()) {
          this.wideHome()
        } else if (this.hdsAvailable) {
        HdsTabs({ barPosition: BarPosition.End, index: this.currentTab, controller: this.tabsController }) {
          this.phoneTabContents()
        }
        .scrollable(true)
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .vertical(false)
        .barFloatingStyle({
          barBottomMargin: this.navBarH + 2,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
          // 听书迷你条（对齐 MusicHome）：听书进行中由 HDS 绘制胶囊背景，
          // 与浮动页签条堆叠悬浮于导航条上方（barBottomMargin 控制）
          miniBar: this.ttsMiniBarOptions()
        })
        // onSelected 在切换动画开始时触发，让图标动画与 Mihon 一样即刻起播（onChange 在切换完成后才触发）
        .onSelected((index: number) => {
          this.currentTab = index;
        })
        .onChange((index: number) => {
          this.currentTab = index;
        })
        .width('100%')
        .height('100%')
        } else {
        // 无 HDS 运行时（预览器等）：回退标准 Tabs，保证页面可渲染
        Tabs({ barPosition: BarPosition.End, index: this.currentTab, controller: this.fallbackTabsController }) {
          this.phoneTabContents()
        }
        .scrollable(true)
        .vertical(false)
        .onChange((index: number) => {
          this.currentTab = index;
        })
        .width('100%')
        .height('100%')
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
      .bindSheet($$this.cfSheetShow, this.cfSheetBuilder(), {
        height: SheetSize.LARGE,
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        showClose: false,
        preferType: this.isWide() ? SheetType.CENTER : SheetType.BOTTOM,
        width: this.isWide() ? 560 : '100%',
        blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
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
      })
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor(this.pal.bg)
    // 一多断点跟踪：窗口宽度变化驱动 底部页签/侧边导航 切换；
    // 同步发布到 AppStorage，供各页面按断点做限宽/边距适配
    .onAreaChange((_old: Area, newArea: Area) => {
      const w = newArea.width;
      if (typeof w === 'number') {
        this.windowW = w;
        AppStorage.setOrCreate('windowW', w);
      }
    })
  }
}
