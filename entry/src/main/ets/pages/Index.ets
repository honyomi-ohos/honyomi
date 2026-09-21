import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
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
import { PluginManagePage } from './PluginManagePage';
import { CategoriesPage } from './CategoriesPage';
import { SettingsPage } from './settings/SettingsPage';
import { AppearancePage } from './settings/AppearancePage';
import { LibrarySettingsPage } from './settings/LibrarySettingsPage';
import { ReaderSettingsPage } from './settings/ReaderSettingsPage';
import { DownloadsSettingsPage } from './settings/DownloadsSettingsPage';
import { BrowseSettingsPage } from './settings/BrowseSettingsPage';
import { AdvancedPage } from './settings/AdvancedPage';
import { AboutPage } from './settings/AboutPage';
import { AppIconRes } from './components/AppIcon';

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
    } else if (name === 'Plugins') {
      PluginManagePage()
    } else if (name === 'Categories') {
      CategoriesPage()
    } else if (name === 'Settings') {
      SettingsPage()
    } else if (name === 'Appearance') {
      AppearancePage()
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
  tabBuilder(title: ResourceStr, icon: string, index: number) {
    Column({ space: 2 }) {
      Image(AppIconRes.get(icon))
        .width(22)
        .height(22)
        .fillColor(this.currentTab === index ? this.pal.primary : this.pal.sub)
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
          .tabBar(this.tabBuilder($r('app.string.tab_library'), 'collections_bookmark', 0))

          TabContent() {
            Column() {
              UpdatesPage()
            }
            .height('100%')
            .padding({ top: this.statusBarH })
          }
          .tabBar(this.tabBuilder($r('app.string.tab_updates'), 'new_releases', 1))

          TabContent() {
            Column() {
              HistoryPage()
            }
            .height('100%')
            .padding({ top: this.statusBarH })
          }
          .tabBar(this.tabBuilder($r('app.string.tab_history'), 'schedule', 2))

          TabContent() {
            Column() {
              BrowsePage()
            }
            .height('100%')
            .padding({ top: this.statusBarH })
          }
          .tabBar(this.tabBuilder($r('app.string.tab_browse'), 'explore', 3))

          TabContent() {
            Column() {
              MorePage()
            }
            .height('100%')
            .padding({ top: this.statusBarH })
          }
          .tabBar(this.tabBuilder($r('app.string.tab_more'), 'more_vert', 4))
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
        .onChange((index: number) => {
          this.currentTab = index;
        })
        .width('100%')
        .height('100%')

        // Cloudflare 盾验证页：Http 层检测到 challenge 时弹出
        if (this.cfChallengeUrl !== '') {
          Column() {
            Row() {
              Text('✕')
                .fontSize(16)
                .fontColor('#FFFFFF')
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
