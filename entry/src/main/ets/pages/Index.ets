import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { ThemePalette } from '../common/Theme';
import { Settings } from '../common/Settings';
import { UpdateService } from '../data/UpdateService';
import { PluginHost } from '../data/PluginHost';
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
import { AppIcon } from './components/AppIcon';

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
  @State cfStatus: string = '';
  private hostController: webview.WebviewController = new webview.WebviewController();
  private cfController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.currentTab = Settings.getStartTab();
    PluginHost.getInstance().attachController(this.hostController);
    this.autoRefresh();
  }

  // CF 验证 URL 变化：打开验证页前把 CookieJar 已有会话注入 ArkWeb
  private onCfUrlChanged(): void {
    if (this.cfChallengeUrl === '') {
      return;
    }
    this.cfStatus = '等待验证完成…';
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
        Util.toast(this.getUIContext(), '验证完成');
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

  // 插件宿主沙箱就绪：加载已安装插件并广播刷新
  private async onHostReady(): Promise<void> {
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
  tabBuilder(title: string, icon: string, index: number) {
    Column({ space: 2 }) {
      AppIcon({
        name: icon,
        iconSize: 22,
        tint: this.currentTab === index ? this.pal.primary : this.pal.sub
      })
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
          .tabBar(this.tabBuilder('书架', 'collections_bookmark', 0))

          TabContent() {
            Column() {
              UpdatesPage()
            }
            .height('100%')
            .padding({ top: this.statusBarH })
          }
          .tabBar(this.tabBuilder('更新', 'new_releases', 1))

          TabContent() {
            Column() {
              HistoryPage()
            }
            .height('100%')
            .padding({ top: this.statusBarH })
          }
          .tabBar(this.tabBuilder('历史', 'schedule', 2))

          TabContent() {
            Column() {
              BrowsePage()
            }
            .height('100%')
            .padding({ top: this.statusBarH })
          }
          .tabBar(this.tabBuilder('浏览', 'explore', 3))

          TabContent() {
            Column() {
              MorePage()
            }
            .height('100%')
            .padding({ top: this.statusBarH })
          }
          .tabBar(this.tabBuilder('更多', 'more_vert', 4))
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

        // 插件宿主：隐藏 1x1 Web 沙箱（唯一 JS 执行引擎）
        Web({ src: $rawfile('plugin_host.html'), controller: this.hostController })
          .javaScriptAccess(true)
          .fileAccess(false)
          .onlineImageAccess(false)
          .domStorageAccess(false)
          .onPageEnd(() => {
            PluginHost.getInstance().markPageLoaded();
            this.onHostReady();
          })
          .onConsole((event: OnConsoleEvent): boolean => {
            hilog.info(0x0002, 'PluginConsole', '%{public}s',
              event.message.getMessage());
            return false;
          })
          .javaScriptProxy({
            object: PluginHost.getInstance().bridge,
            name: '__hostBridge',
            methodList: ['request', 'result', 'log'],
            controller: this.hostController,
          })
          .width(1)
          .height(1)
          .opacity(0)

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
              Text('人机验证')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
              Text('完成')
                .fontSize(15)
                .fontColor('#FFFFFF')
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .onClick(() => {
                  this.closeCf(true);
                  Util.toast(this.getUIContext(), '已保存验证结果');
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
