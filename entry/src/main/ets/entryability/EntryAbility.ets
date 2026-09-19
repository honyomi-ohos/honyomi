import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Settings } from '../common/Settings';
import { AppDb } from '../data/AppDb';
import { SourceRegistry } from '../source/Source';
import { MangaDexSource } from '../source/MangaDexSource';
import { LocalSource } from '../source/LocalSource';

const DOMAIN = 0x0001;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onCreate');
    // 初始化全局状态
    AppStorage.setOrCreate('isDark', false);
    AppStorage.setOrCreate('isDarkSystem', false);
    AppStorage.setOrCreate('libDirty', 0);
    Settings.init(this.context);
    // 注册内置源
    SourceRegistry.register(new MangaDexSource());
    SourceRegistry.register(new LocalSource(this.context.filesDir, this.context.cacheDir));
    // 主题
    const systemDark = this.context.config !== undefined &&
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.set('isDarkSystem', systemDark);
    Settings.applyTheme(systemDark);
    // 数据库
    AppDb.ready(this.context).catch((e: Error) => {
      hilog.error(DOMAIN, 'Mihon', 'db init failed: %{public}s', e.message);
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const systemDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.set('isDarkSystem', systemDark);
    Settings.applyTheme(systemDark);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onWindowStageCreate');
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
