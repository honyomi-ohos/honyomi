import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Settings } from '../common/Settings';
import { AppDb } from '../data/AppDb';
import { SourceRegistry } from '../source/Source';
import { LocalSource } from '../source/LocalSource';
import { DownloadService } from '../data/DownloadService';
import { PluginService } from '../data/PluginService';
import { JsvmExtensionManager } from '../jsvm/JsvmExtensionManager';
import { CookieJar } from '../net/CookieJar';
import { ImageCache } from '../common/ImageCache';

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
    // 窗口沉浸式：全屏布局 + 透明系统栏（内容延伸到状态栏/导航栏下方）
    windowStage.getMainWindow().then((win: window.Window) => {
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
  }
}
