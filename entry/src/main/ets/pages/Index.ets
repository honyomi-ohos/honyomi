import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme } from '../common/Theme';
import { Settings } from '../common/Settings';
import { UpdateService } from '../data/UpdateService';
import { PluginHost } from '../data/PluginHost';
import { PluginService } from '../data/PluginService';
import { LibraryPage } from './LibraryPage';
import { UpdatesPage } from './UpdatesPage';
import { HistoryPage } from './HistoryPage';
import { BrowsePage } from './BrowsePage';
import { MorePage } from './MorePage';
import { MangaDetailPage } from './MangaDetailPage';
import { ReaderPage } from './ReaderPage';
import { DownloadPage } from './DownloadPage';
import { PluginManagePage } from './PluginManagePage';

@Entry
@Component
struct Index {
  @Provide('navStack') pathStack: NavPathStack = new NavPathStack();
  @State currentTab: number = 0;
  @StorageProp('isDark') isDark: boolean = false;
  private hostController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    PluginHost.getInstance().attachController(this.hostController);
    this.autoRefresh();
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
    }
  }

  @Builder
  tabBuilder(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === index ? Theme.primary(this.isDark) : Theme.sub(this.isDark))
    }
    .justifyContent(FlexAlign.Center)
    .height('100%')
  }

  build() {
    Navigation(this.pathStack) {
      Stack({ alignContent: Alignment.TopStart }) {
        Tabs({ barPosition: BarPosition.End }) {
          TabContent() {
            LibraryPage()
          }
          .tabBar(this.tabBuilder('书架', 0))

          TabContent() {
            UpdatesPage()
          }
          .tabBar(this.tabBuilder('更新', 1))

          TabContent() {
            HistoryPage()
          }
          .tabBar(this.tabBuilder('历史', 2))

          TabContent() {
            BrowsePage()
          }
          .tabBar(this.tabBuilder('浏览', 3))

          TabContent() {
            MorePage()
          }
          .tabBar(this.tabBuilder('更多', 4))
        }
        .scrollable(true)
        .barMode(BarMode.Fixed)
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
      }
      .width('100%')
      .height('100%')
    }
    .navDestination(this.pageMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor(Theme.bg(this.isDark))
  }
}
