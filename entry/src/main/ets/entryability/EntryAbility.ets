import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Settings } from '../common/Settings';
import { AppDb } from '../data/AppDb';
import { SourceRegistry } from '../source/Source';
import { LocalSource } from '../source/LocalSource';
import { DownloadService } from '../data/DownloadService';
import { PluginService } from '../data/PluginService';
import { JsvmExtensionManager } from '../jsvm/JsvmExtensionManager';
import { CookieJar } from '../net/CookieJar';
import { ImageCache } from '../common/ImageCache';
import { WidgetUpdater } from '../form/WidgetUpdater';

const DOMAIN = 0x0001;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onCreate');
    // 初始化全局状态
    AppStorage.setOrCreate('isDark', false);
    AppStorage.setOrCreate('isDarkSystem', false);
    AppStorage.setOrCreate('libDirty', 0);
    AppStorage.setOrCreate('pluginsDirty', 0);
    Settings.init(this.context);
    // 应用语言偏好（跟随系统时由系统资源机制自动匹配）
    Settings.applyAppLanguage();
    // 注册内置源（LocalSource；在线源全部通过插件动态安装）
    SourceRegistry.register(new LocalSource(this.context.filesDir, this.context.cacheDir));
    // 插件宿主（JSVM 隔离引擎：安装主线程 HTTP 桥）
    PluginService.init(this.context);
    JsvmExtensionManager.init();
    // 主题
    const systemDark = this.context.config !== undefined &&
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.set('isDarkSystem', systemDark);
    Settings.applyTheme(systemDark);
    Settings.applyColorMode(this.context);
    // 数据库
    AppDb.ready(this.context).catch((e: Error) => {
      hilog.error(DOMAIN, 'Mihon', 'db init failed: %{public}s', e.message);
    });
    // 下载服务
    DownloadService.init(this.context);
    // Cookie 存储与图片缓存
    CookieJar.init(this.context);
    ImageCache.init(this.context);
    AppStorage.setOrCreate('cfChallengeUrl', '');
    this.handleCardWant(want);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const systemDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.set('isDarkSystem', systemDark);
    Settings.applyTheme(systemDark);
    Settings.applySystemBar(this.context);
    Settings.initAvoidAreas(this.context);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onWindowStageCreate');
    // PC/2in1：保留系统窗口标题栏（含最小化/关闭按钮），不做全屏沉浸布局，
    // 避免内容延伸至标题栏三键区造成遮挡；其余设备维持沉浸式全屏
    const isPcLike: boolean = deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'pc';
    windowStage.getMainWindow().then((win: window.Window) => {
      if (isPcLike) {
        Settings.applySystemBar(this.context);
        Settings.initAvoidAreas(this.context);
        return;
      }
      win.setWindowLayoutFullScreen(true).then(() => {
        Settings.applySystemBar(this.context);
        Settings.initAvoidAreas(this.context);
      }).catch((e: Error) => {
        hilog.error(DOMAIN, 'Mihon', 'Failed to set full screen. Cause: %{public}s', e.message);
      });
    }).catch((e: Error) => {
      hilog.error(DOMAIN, 'Mihon', 'Failed to get main window. Cause: %{public}s', e.message);
    });
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'Mihon', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'Mihon', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onBackground');
    WidgetUpdater.refreshAll(this.context).catch((e: Error) => {
      hilog.warn(DOMAIN, 'Mihon', 'onBackground refreshAll failed: %{public}s', e.message);
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onNewWant');
    this.handleCardWant(want);
  }

  // 解析桌面卡片 router 事件参数，写入 AppStorage 供 Index 导航
  private handleCardWant(want: Want): void {
    const params = want.parameters;
    if (params === undefined) {
      return;
    }
    const target = params['cardTarget'];
    if (typeof target !== 'string' || target === '') {
      return;
    }
    const mangaIdVal = params['mangaId'];
    const chapterIdVal = params['chapterId'];
    const mangaId = typeof mangaIdVal === 'number' ? mangaIdVal :
      (typeof mangaIdVal === 'string' ? Number(mangaIdVal) : 0);
    const chapterId = typeof chapterIdVal === 'number' ? chapterIdVal :
      (typeof chapterIdVal === 'string' ? Number(chapterIdVal) : 0);
    const payload: Record<string, string | number> = {
      'target': target,
      'mangaId': mangaId,
      'chapterId': chapterId
    };
    AppStorage.setOrCreate('cardAction', JSON.stringify(payload));
  }
}
