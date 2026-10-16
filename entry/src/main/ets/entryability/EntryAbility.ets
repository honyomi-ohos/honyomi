import { AbilityConstant, common, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Settings } from '../common/Settings';
import { AppDb } from '../data/AppDb';
import { SourceRegistry } from '../source/Source';
import { LocalSource } from '../source/LocalSource';
import { LocalNovelSource } from '../source/LocalNovelSource';
import { LocalVideoSource } from '../source/LocalVideoSource';
import { DownloadService } from '../data/DownloadService';
import { PluginService } from '../data/PluginService';
import { BackupService } from '../data/BackupService';
import { EngineGateway } from '../jsvm/EngineGateway';
import { JsvmEngineBackend } from '../jsvm/JsvmEngineBackend';
import { CookieJar } from '../net/CookieJar';
import { ImageCache } from '../common/ImageCache';

import { WidgetUpdater } from '../form/WidgetUpdater';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { TtsPlaybackService } from '../common/TtsPlaybackService';
import { AppKeys } from '../common/AppKeys';
import { PluginPrefs } from '../jsvm/PluginPrefs';

const DOMAIN = 0x0001;

export default class EntryAbility extends UIAbility {
  // 供意图执行器等非组件环境获取应用 context（onCreate 即赋值，先于任意意图执行）
  static appContext: common.UIAbilityContext | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onCreate');
    EntryAbility.appContext = this.context;
    // ── 第0级（同步关键路径）：首帧渲染必需的全局状态、主题与插件宿主桥 ──
    AppStorage.setOrCreate(AppKeys.IS_DARK, false);
    AppStorage.setOrCreate(AppKeys.IS_DARK_SYSTEM, false);
    AppStorage.setOrCreate(AppKeys.LIB_DIRTY, 0);
    AppStorage.setOrCreate(AppKeys.PLUGINS_DIRTY, 0);
    AppStorage.setOrCreate(AppKeys.CF_CHALLENGE_URL, '');
    Settings.init(this.context);
    // 全局功能开关从持久化偏好恢复（NSFW 源显示等）
    Settings.pushGlobalFlags();
    // 应用语言偏好（跟随系统时由系统资源机制自动匹配）
    Settings.applyAppLanguage();
    // 主题
    const systemDark = this.context.config !== undefined &&
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.set(AppKeys.IS_DARK_SYSTEM, systemDark);
    Settings.applyTheme(systemDark);
    Settings.applyColorMode(this.context);
    // 注册内置源（本地漫画 / 小说 / 视频；在线源全部通过插件动态安装）
    SourceRegistry.register(new LocalSource(this.context.filesDir, this.context.cacheDir));
    SourceRegistry.register(new LocalNovelSource(this.context.filesDir));
    SourceRegistry.register(new LocalVideoSource(this.context.filesDir));
    // 插件宿主（JSVM 隔离引擎）：注册引擎后端（native 实现仅在此处接入，
    // UI/服务层经 EngineGateway 访问，页面导入链保持 native-free 以支持预览器）；
    // HTTP 桥必须在首个插件网络请求前就绪，保持同步
    PluginService.init(this.context);
    const engineBackend = new JsvmEngineBackend();
    EngineGateway.setBackend(engineBackend);
    engineBackend.init();
    this.handleCardWant(want);
    // ── 第1级（主线程空闲即执行，先于首帧内容挂载）：非首帧必需的服务初始化 ──
    // 契约：此处初始化的服务允许在回调执行前被访问——各服务必须容忍“未 init 先使用”
    // （内部空安全/延迟就绪），不得假设构造期已完成初始化；首帧路径严禁依赖本级服务。
    setTimeout((): void => {
      DownloadService.init(this.context);
      CookieJar.init(this.context);
      ImageCache.init(this.context);
      // 启动时清除章节缓存（数据与存储设置）
      if (Settings.getAutoClearChapterCache()) {
        ImageCache.clearAll();
      }
    }, 0);
    // ── 第2级（异步，数据库就绪后）：后台维护任务 ──
    AppDb.ready(this.context).then(() => {
      // 数据库就绪后检查自动备份是否到期（数据与存储设置）
      BackupService.runAutoBackupIfDue(this.context).catch((e: Error) => {
        hilog.warn(DOMAIN, 'Mihon', 'auto backup failed: %{public}s', e.message);
      });
    }).catch((e: Error) => {
      hilog.error(DOMAIN, 'Mihon', 'db init failed: %{public}s', e.message);
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const systemDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.set(AppKeys.IS_DARK_SYSTEM, systemDark);
    Settings.applyTheme(systemDark);
    Settings.applySystemBar(this.context);
    Settings.initAvoidAreas(this.context);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onDestroy');
    // 退出前清理：停止听书播放（销毁 AVSession）、结算阅读统计、偏好设置落盘
    TtsPlaybackService.stop();
    ReadingStatsRepo.flush();
    Settings.flushNow();
    // 防抖窗口内的插件偏好与 Cookie 立即落盘，防退出丢失最后一次写入
    PluginPrefs.flushAll().catch((e: Error): void => {
      hilog.warn(DOMAIN, 'Mihon', 'plugin prefs flush failed: %{public}s', `${e}`);
    });
    CookieJar.flushNow();
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
    // 退后台先结算进行中的阅读会话，偏好设置落盘，再刷新桌面卡片
    ReadingStatsRepo.flush();
    Settings.flushNow();
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
    const mangaIdRaw = typeof mangaIdVal === 'number' ? mangaIdVal :
      (typeof mangaIdVal === 'string' ? Number(mangaIdVal) : 0);
    const chapterIdRaw = typeof chapterIdVal === 'number' ? chapterIdVal :
      (typeof chapterIdVal === 'string' ? Number(chapterIdVal) : 0);
    // 非数字/NaN 统一置 0，避免 JSON 序列化出 null 污染下游
    const mangaId = Number.isFinite(mangaIdRaw) ? Math.floor(mangaIdRaw) : 0;
    const chapterId = Number.isFinite(chapterIdRaw) ? Math.floor(chapterIdRaw) : 0;
    const typeVal = params['contentType'];
    const contentType = typeof typeVal === 'string' ? typeVal : '';
    const payload: Record<string, string | number> = {
      'target': target,
      'mangaId': mangaId,
      'chapterId': chapterId,
      'contentType': contentType
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
  }
}
