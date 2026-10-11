import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { curves, AnimatorResult, AnimatorOptions } from '@kit.ArkUI';
import { HdsTabs, hdsMaterial, HdsTabsController, HdsAnimationMode } from '@kit.UIDesignKit';
import { ThemePalette } from '../common/Theme';
import { Settings } from '../common/Settings';
import { UpdateService } from '../data/UpdateService';
import { PluginService } from '../data/PluginService';
import { Http } from '../net/Http';
import { CookieJar } from '../net/CookieJar';
import { Util } from '../common/Util';
import { LibraryPage } from './LibraryPage';
import { UpdatesPage } from './UpdatesPage';
import { UpcomingPage } from './UpcomingPage';
import { HistoryPage } from './HistoryPage';
import { BrowsePage } from './BrowsePage';
import { MorePage } from './MorePage';
import { MangaDetailPage } from './MangaDetailPage';
import { ReaderPage } from './ReaderPage';
import { DownloadPage } from './DownloadPage';
import { BrowseSourcePage } from './BrowseSourcePage';
import { GlobalSearchPage } from './GlobalSearchPage';
import { MigrateMangaPage } from './MigrateMangaPage';
import { MigrateSearchPage } from './MigrateSearchPage';
import { ExtensionDetailPage } from './ExtensionDetailPage';
import { CategoriesPage } from './CategoriesPage';
import { StatsPage } from './StatsPage';
import { SettingsPage } from './settings/SettingsPage';
import { AppearancePage } from './settings/AppearancePage';
import { LanguagePage } from './settings/LanguagePage';
import { LibrarySettingsPage } from './settings/LibrarySettingsPage';
import { ReaderSettingsPage } from './settings/ReaderSettingsPage';
import { DownloadsSettingsPage } from './settings/DownloadsSettingsPage';
import { BrowseSettingsPage } from './settings/BrowseSettingsPage';
import { AdvancedPage } from './settings/AdvancedPage';
import { AboutPage } from './settings/AboutPage';
import { AppIcon } from './components/AppIcon';
import { UPDATES_MORPH, LIBRARY_MORPH, BROWSE_MORPH, PathMorph } from './components/PathMorph';
import { ReaderParams, DetailParams } from '../model/RouteParams';

// 桌面卡片 router 事件载荷（由 EntryAbility.handleCardWant 写入 AppStorage）
interface CardActionPayload {
  target: string;
  mangaId: number;
  chapterId: number;
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
    return this.selected ? this.pal.primary : this.pal.sub;
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
    an.reset(opts);
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
      TabIcon({ kind: this.kind, selected: this.selected })
      Text(this.title)
        .fontSize(14)
        .fontColor(this.selected ? this.pal.primary : this.pal.sub)
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
  // 书架多选数：>0 时隐藏底部页签栏（HDS 官方多选交互：操作栏替换页签栏）
  @StorageLink('libSelectionCount') @Watch('onLibSelectionChanged') libSelectionCount: number = 0;
  @StorageLink('cardAction') @Watch('onCardActionChanged') cardActionJson: string = '';
  @State cfStatus: ResourceStr = '';
  // 一多响应式：窗口宽度 + 已挂载页签位掩码（宽屏下按需挂载后驻留保状态）
  @State windowW: number = 0;
  @State mountedMask: number = 1;
  private cfController: webview.WebviewController = new webview.WebviewController();
  private tabsController: HdsTabsController = new HdsTabsController();

  // lg 断点（≥840vp）：底部页签切换为侧边导航栏（华为大屏导航规范）
  private isWide(): boolean {
    return this.windowW >= 840;
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

  // 进入多选隐藏页签栏，退出多选恢复（HdsTabsController 官方隐藏/显示动效）；宽屏侧边栏常驻不参与
  private onLibSelectionChanged(): void {
    if (this.isWide()) {
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
    // 插件直接运行于 JSVM 隔离引擎（无 Web 沙箱依赖），启动即加载
    this.loadInstalledPlugins();
    this.autoRefresh();
    this.consumeCardAction();
  }

  // 桌面卡片点击导航：切页签或跳阅读器/详情页
  private onCardActionChanged(): void {
    this.consumeCardAction();
  }

  private consumeCardAction(): void {
    if (this.cardActionJson === '') {
      return;
    }
    const raw = JSON.parse(this.cardActionJson) as CardActionPayload;
    this.cardActionJson = '';
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
    if (raw.target === 'stats') {
      this.switchTab(4);
      this.pathStack.pushPathByName('Stats', null);
      return;
    }
    if (raw.target === 'reader' && raw.mangaId > 0 && raw.chapterId > 0) {
      const params: ReaderParams = { mangaId: raw.mangaId, chapterId: raw.chapterId };
      this.pathStack.pushPathByName('Reader', params);
      return;
    }
    if (raw.target === 'detail' && raw.mangaId > 0) {
      const params: DetailParams = { mangaId: raw.mangaId };
      this.pathStack.pushPathByName('MangaDetail', params);
    }
  }

  // CF 验证 URL 变化：打开验证页前把 CookieJar 已有会话注入 ArkWeb
  private onCfUrlChanged(): void {
    if (this.cfChallengeUrl === '') {
      return;
    }
    this.cfStatus = $r('app.string.tab_cf_waiting');
    const jar = CookieJar.headerFor(this.cfChallengeUrl);
    if (jar !== '') {
      webview.WebCookieManager.configCookie(this.cfChallengeUrl, jar).catch((_e: Error) => {
        // 忽略注入失败
      });
    }
  }

  // 每次页面加载完成后检查盾是否通过
  private checkCfSolved(): void {
    webview.WebCookieManager.fetchCookie(this.cfChallengeUrl).then((cookies: string) => {
      if (cookies.indexOf('cf_clearance') >= 0) {
        this.closeCf(true);
        Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_verified'));
      }
    }).catch((_e: Error) => {
      // 忽略
    });
  }

  private closeCf(importCookies: boolean): void {
    if (importCookies) {
      webview.WebCookieManager.fetchCookie(this.cfChallengeUrl).then((cookies: string) => {
        CookieJar.importCookieString(this.cfChallengeUrl, cookies);
      }).catch((_e: Error) => {
        // 忽略
      });
    }
    this.cfStatus = '';
    this.cfChallengeUrl = '';
  }

  // 加载已安装插件并广播刷新（每个插件在专属 Worker 的隔离 JSVM 引擎中执行）
  private async loadInstalledPlugins(): Promise<void> {
    try {
      await PluginService.loadAll();
    } catch (e) {
      // 加载失败不阻塞主界面
    }
    PluginService.markDirty();
  }

  // 静默自动刷新：距上次刷新超过 12 小时才触发
  private async autoRefresh(): Promise<void> {
    const last = Settings.getLastRefreshAt();
    if (Date.now() - last < 12 * 60 * 60 * 1000) {
      return;
    }
    Settings.setLastRefreshAt(Date.now());
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const newCount = await UpdateService.refreshLibrary(context);
      if (newCount > 0) {
        AppStorage.setOrCreate('libDirty', (AppStorage.get<number>('libDirty') ?? 0) + 1);
      }
    } catch (e) {
      // 静默失败
    }
  }

  @Builder
  pageMap(name: string) {
    if (name === 'MangaDetail') {
      MangaDetailPage()
    } else if (name === 'Reader') {
      ReaderPage()
    } else if (name === 'Downloads') {
      DownloadPage()
    } else if (name === 'BrowseSource') {
      BrowseSourcePage()
    } else if (name === 'GlobalSearch') {
      GlobalSearchPage()
    } else if (name === 'MigrateManga') {
      MigrateMangaPage()
    } else if (name === 'MigrateSearch') {
      MigrateSearchPage()
    } else if (name === 'ExtensionDetail') {
      ExtensionDetailPage()
    } else if (name === 'Categories') {
      CategoriesPage()
    } else if (name === 'Stats') {
      StatsPage()
    } else if (name === 'Upcoming') {
      UpcomingPage()
    } else if (name === 'Settings') {
      SettingsPage()
    } else if (name === 'Appearance') {
      AppearancePage()
    } else if (name === 'Language') {
      LanguagePage()
    } else if (name === 'LibrarySettings') {
      LibrarySettingsPage()
    } else if (name === 'ReaderSettings') {
      ReaderSettingsPage()
    } else if (name === 'DownloadsSettings') {
      DownloadsSettingsPage()
    } else if (name === 'BrowseSettings') {
      BrowseSettingsPage()
    } else if (name === 'Advanced') {
      AdvancedPage()
    } else if (name === 'About') {
      AboutPage()
    }
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
  }

  // 宽屏主界面：左侧固定导航栏 + 右侧内容区（页签首次访问时挂载、驻留保状态）
  @Builder
  wideHome() {
    Row() {
      Column({ space: 4 }) {
        RailItem({
          kind: 'library', title: $r('app.string.tab_library'),
          selected: this.currentTab === 0,
          onTap: (): void => { this.switchTab(0); }
        })
        RailItem({
          kind: 'updates', title: $r('app.string.tab_updates'),
          selected: this.currentTab === 1,
          onTap: (): void => { this.switchTab(1); }
        })
        RailItem({
          kind: 'history', title: $r('app.string.tab_history'),
          selected: this.currentTab === 2,
          onTap: (): void => { this.switchTab(2); }
        })
        RailItem({
          kind: 'browse', title: $r('app.string.tab_browse'),
          selected: this.currentTab === 3,
          onTap: (): void => { this.switchTab(3); }
        })
        RailItem({
          kind: 'more', title: $r('app.string.tab_more'),
          selected: this.currentTab === 4,
          onTap: (): void => { this.switchTab(4); }
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

  build() {
    Navigation(this.pathStack) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.isWide()) {
          this.wideHome()
        } else {
        HdsTabs({ barPosition: BarPosition.End, index: this.currentTab, controller: this.tabsController }) {
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
        .scrollable(true)
        .barOverlap(true)
        .barPosition(BarPosition.End)
        .vertical(false)
        .barFloatingStyle({
          barBottomMargin: this.navBarH + 2,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
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
        }

        // Cloudflare 盾验证页：Http 层检测到 challenge 时弹出
        if (this.cfChallengeUrl !== '') {
          Column() {
            Row() {
              AppIcon({ name: 'close', iconSize: 20, tint: '#FFFFFF' })
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .onClick(() => {
                  this.closeCf(false);
                })
              Text($r('app.string.tab_cf_title'))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
              Text($r('app.string.tab_cf_done'))
                .fontSize(15)
                .fontColor('#FFFFFF')
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .onClick(() => {
                  this.closeCf(true);
                  Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_saved'));
                })
            }
            .width('100%')
            .backgroundColor('#CC000000')

            Web({ src: 'about:blank', controller: this.cfController })
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .fileAccess(true)
              .onlineImageAccess(true)
              .onControllerAttached(() => {
                // UA 必须在首次加载前设置（cf_clearance 与 UA 绑定）
                this.cfController.setCustomUserAgent(Http.USER_AGENT);
                this.cfController.loadUrl(this.cfChallengeUrl);
              })
              .onPageEnd(() => {
                this.checkCfSolved();
              })
              .layoutWeight(1)

            Text(this.cfStatus)
              .fontSize(12)
              .fontColor(this.pal.sub)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding(8)
          }
          .width('100%')
          .height('100%')
          .padding({ top: this.statusBarH })
          .backgroundColor(this.pal.bg)
        }
      }
      .width('100%')
      .height('100%')
    }
    .navDestination(this.pageMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor(this.pal.bg)
    // 一多断点跟踪：窗口宽度变化驱动 底部页签/侧边导航 切换
    .onAreaChange((_old: Area, newArea: Area) => {
      const w = newArea.width;
      if (typeof w === 'number') {
        this.windowW = w;
      }
    })
  }
}
