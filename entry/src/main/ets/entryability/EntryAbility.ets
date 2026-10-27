import { AbilityConstant, common, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { Settings } from '../common/Settings';
import { Log } from '../common/Log';
import { AppDb } from '../data/AppDb';
import { SourceRegistry } from '../source/Source';
import { LocalSource } from '../source/LocalSource';
import { LocalNovelSource } from '../source/LocalNovelSource';
import { LocalVideoSource } from '../source/LocalVideoSource';
import { LocalFolderManager } from '../source/LocalFolderManager';
import { BookParser } from '../common/bookparser/BookParser';
import { DownloadService } from '../data/DownloadService';
import { BtFlow } from '../data/BtFlow';
import { PluginService } from '../data/PluginService';
import { BackupService } from '../data/BackupService';
import { EngineGateway } from '../jsvm/EngineGateway';
import { JsvmEngineBackend } from '../jsvm/JsvmEngineBackend';
import { CookieJar } from '../net/CookieJar';
import { Http } from '../net/Http';
import { ImageCache } from '../common/ImageCache';
import { NetworkMonitor } from '../common/NetworkMonitor';

import { WidgetUpdater } from '../form/WidgetUpdater';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { TtsPlaybackService } from '../common/TtsPlaybackService';
import { AppKeys } from '../common/AppKeys';
import { PluginPrefs } from '../jsvm/PluginPrefs';
import { AppLock } from '../common/AppLock';

const DOMAIN = 0x0001;

export default class EntryAbility extends UIAbility {
  // 供意图执行器等非组件环境获取应用 context（onCreate 即赋值，先于任意意图执行）
  static appContext: common.UIAbilityContext | undefined = undefined;

  // 已配置本地源文件夹时尽力向用户文件夹同步落一份，防止整树重新同步覆盖 local_root 后导入丢失
  private static async importBookToNovelSource(context: common.UIAbilityContext,
    srcUri: string, name: string): Promise<void> {
    const novelDir = `${LocalFolderManager.syncedRootPath(context.filesDir)}/${LocalFolderManager.NOVEL_SUBDIR}`;
    try {
      if (!fs.accessSync(novelDir)) {
        fs.mkdirSync(novelDir, true);
      }
    } catch (e) {
      throw new Error('mkdir_failed');
    }
    const destPath = `${novelDir}/${name}`;
    try {
      fs.unlinkSync(destPath);
    } catch (e) {
      // 目标不存在，继续拷贝
    }
    await fs.copy(srcUri, fileUri.getUriFromPath(destPath));
    const folderUri = Settings.getLocalFolderUri();
    if (folderUri !== '') {
      try {
        const userDestUri = `${folderUri}/${LocalFolderManager.NOVEL_SUBDIR}/${name}`;
        try {
          fs.unlinkSync(userDestUri);
        } catch (e) {
          // 目标不存在，继续拷贝
        }
        await fs.copy(srcUri, userDestUri);
      } catch (e) {
        // 用户文件夹写入失败不影响本次导入（沙箱副本已就位）
      }
    }
    const dotIdx = name.lastIndexOf('.');
    const baseName = dotIdx > 0 ? name.substring(0, dotIdx) : name;
    const payload: Record<string, string | number> = {
      'target': 'browsesource',
      'mangaId': 0,
      'chapterId': 0,
      'contentType': '',
      'sourceKey': 'local_novel',
      'query': baseName
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
  }

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
    // 「详细日志」开关接入 hilog 全局最低级别（关闭时全进程 debug 零输出）
    Log.applyVerboseLogging();
    // 自定义 User-Agent 同步到网络层（Settings.init 之后，先于任意网络请求）
    Http.syncUserAgent();
    // 全局功能开关从持久化偏好恢复（NSFW 源显示等）
    Settings.pushGlobalFlags();
    // 应用锁（隐私设置）：启用且设备有解锁凭据时冷启动即锁定（对齐 Mihon useAuthenticator）
    AppStorage.setOrCreate(AppKeys.APP_LOCKED, Settings.getAppLock() && AppLock.isAuthSupported());
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
    this.handleFileOpenWant(want);
    // ── 第1级（主线程空闲即执行，先于首帧内容挂载）：非首帧必需的服务初始化 ──
    // 契约：此处初始化的服务允许在回调执行前被访问——各服务必须容忍“未 init 先使用”
    // （内部空安全/延迟就绪），不得假设构造期已完成初始化；首帧路径严禁依赖本级服务。
    setTimeout((): void => {
      // 网络监听先行启动：下载"仅 Wi-Fi"门禁依赖其判定（判定失败 fail-open 放行）；
      // 判定变化同时联动 BT 计费网络限上传（蜂窝时压至 10KB/s）
      NetworkMonitor.start((): void => {
        DownloadService.refreshNetworkGate();
        BtFlow.applyLimitsLive();
      });
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
    // 隐私界面（防截屏）：窗口就绪后按设置应用到主窗口
    Settings.applySecureScreen(this.context);
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
    // 应用锁：切后台超过时限后回前台需重新解锁（0=切后台立即锁；>0=分钟；-1=从不自动锁）
    if (Settings.getAppLock() && AppLock.isAuthSupported()) {
      const after: number = Settings.getLockAfterMinutes();
      if (after !== -1) {
        const elapsed: number = Date.now() - Settings.getLastAppClosedAt();
        if (after === 0 || elapsed >= after * 60 * 1000) {
          AppStorage.setOrCreate(AppKeys.APP_LOCKED, true);
        }
      }
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onBackground');
    // 记录切后台时间戳：应用锁空闲判定（进程存活内存判定 + 被杀重启持久化兜底）
    Settings.setLastAppClosedAt(Date.now());
    // 退后台先结算进行中的阅读会话，偏好设置落盘，再刷新桌面卡片
    ReadingStatsRepo.flush();
    Settings.flushNow();
    WidgetUpdater.refreshAll(this.context).catch((e: Error) => {
      hilog.warn(DOMAIN, 'Mihon', 'onBackground refreshAll failed: %{public}s', e.message);
    });
  }

  // 系统"打开方式"拉起（文件管理器等选择本应用打开书籍文件）：

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onNewWant');
    this.handleCardWant(want);
    this.handleFileOpenWant(want);
  }

  // 书籍导入：拷入沙箱本地小说源目录（立即出现在本地小说源列表）；

  // 识别 epub/mobi/azw/azw3/prc 后导入本地小说源，经 cardAction 通道由 Index 导航定位
  private handleFileOpenWant(want: Want): void {
    const uri = want.uri;
    if (typeof uri !== 'string' || uri === '') {
      return;
    }
    const name = LocalFolderManager.uriName(uri);
    if (!BookParser.isBookFile(name)) {
      return;
    }
    EntryAbility.importBookToNovelSource(this.context, uri, name).catch((e: Error): void => {
      hilog.warn(DOMAIN, 'Mihon', 'import opened book failed: %{public}s', e.message);
    });
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
