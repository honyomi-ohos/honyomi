import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { curves } from '@kit.ArkUI';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { ThemePalette } from '../common/Theme';
import { Settings } from '../common/Settings';
import { UpdateService } from '../data/UpdateService';
import { PluginService } from '../data/PluginService';
import { Http } from '../net/Http';
import { CookieJar } from '../net/CookieJar';
import { Util } from '../common/Util';
import { LibraryPage } from './LibraryPage';
import { UpdatesPage } from './UpdatesPage';
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

// 底部导航图标：逐 Tab 复刻 Mihon 的 AnimatedImageVector 动画
// - library/updates: 描边→填充 pathData 形变（300ms fast_out_slow_in，两层图标交叉淡化近似）
// - history: 时针静止，环绕箭头绕 (13,12) 整圈旋转 360→0（500ms fast_out_slow_in）
// - browse: 指针菱形→罗盘形变 + 整体旋转 180°（300ms）+ 中心点延迟 66ms 后 100ms 减速弹出
// - more: 三点依次波浪弹跳（保持 83/150/217ms 后 100ms 上跳-133ms 下落-67ms 回正，贝塞尔 0.5,0,0.5,1）
// 图标 SVG 由 Mihon anim_*_enter.xml 的原始 pathData 生成（像素级一致）
@Component
struct TabIcon {
  @Prop @Watch('onSelectedChanged') selected: boolean = false;
  @Prop kind: string = '';
  @State fillOpacity: number = 0;
  @State histAngle: number = 0;
  @State browseAngle: number = 0;
  @State browseDotScale: number = 1;
  @State moreY0: number = 0;
  @State moreY1: number = 0;
  @State moreY2: number = 0;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  aboutToAppear(): void {
    if (this.selected) {
      this.fillOpacity = 1;
      this.browseAngle = 180;
      this.browseDotScale = 1;
    }
  }

  private iconTint(): ResourceColor {
    return this.selected ? this.pal.primary : this.pal.sub;
  }

  private onSelectedChanged(): void {
    if (this.kind === 'history') {
      this.playHistory(this.selected);
    } else if (this.kind === 'browse') {
      this.playBrowse(this.selected);
    } else if (this.kind === 'more') {
      this.playMore(this.selected);
    } else {
      this.getUIContext().animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, (): void => {
        this.fillOpacity = this.selected ? 1 : 0;
      });
    }
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

  // 浏览：形变+整体 180° 旋转同帧驱动；中心点 66ms 保持后 100ms 减速弹出
  private playBrowse(sel: boolean): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, (): void => {
      this.fillOpacity = sel ? 1 : 0;
      this.browseAngle = sel ? 180 : 0;
    });
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
      .width(16)
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
        AppIcon({ name: 'tab_browse', iconSize: 24, tint: this.iconTint() })
          .opacity(1 - this.fillOpacity)
        AppIcon({ name: 'tab_browse_on', iconSize: 24, tint: this.iconTint() })
          .opacity(this.fillOpacity)
        AppIcon({ name: 'tab_browse_dot', iconSize: 24, tint: this.iconTint() })
          .scale({ x: this.browseDotScale, y: this.browseDotScale })
      }
      .width(24)
      .height(24)
      .rotate({ angle: this.browseAngle })
    } else {
      Stack() {
        AppIcon({ name: this.kind === 'library' ? 'tab_library' : 'tab_updates', iconSize: 24, tint: this.iconTint() })
          .opacity(1 - this.fillOpacity)
        AppIcon({ name: this.kind === 'library' ? 'tab_library_on' : 'tab_updates_on', iconSize: 24, tint: this.iconTint() })
          .opacity(this.fillOpacity)
      }
      .width(24)
      .height(24)
    }
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
  @State cfStatus: ResourceStr = '';
  private cfController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.currentTab = Settings.getStartTab();
    // 插件直接运行于 JSVM 隔离引擎（无 Web 沙箱依赖），启动即加载
    this.loadInstalledPlugins();
    this.autoRefresh();
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

  build() {
    Navigation(this.pathStack) {
      Stack({ alignContent: Alignment.TopStart }) {
        HdsTabs({ barPosition: BarPosition.End, index: this.currentTab }) {
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
          barBottomMargin: this.navBarH + 8,
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
  }
}
