import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { Settings } from '../common/Settings';
import { AppDb } from '../data/AppDb';
import { SourceRegistry } from '../source/Source';
import { LocalSource } from '../source/LocalSource';
import { LocalNovelSource } from '../source/LocalNovelSource';
import { LocalVideoSource } from '../source/LocalVideoSource';
import { DownloadService } from '../data/DownloadService';
import { PluginService } from '../data/PluginService';
import { BackupService } from '../data/BackupService';
import { JsvmExtensionManager } from '../jsvm/JsvmExtensionManager';
import { CookieJar } from '../net/CookieJar';
import { ImageCache } from '../common/ImageCache';
import { WidgetUpdater } from '../form/WidgetUpdater';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { AppKeys } from '../common/AppKeys';

const DOMAIN = 0x0001;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'Mihon', '%{public}s', 'Ability onCreate');
    // ── 第0级（同步关键路径）：首帧渲染必需的全局状态、主题与插件宿主桥 ──
    AppStorage.setOrCreate(AppKeys.IS_DARK, false);
    AppStorage.setOrCreate(AppKeys.IS_DARK_SYSTEM, false);
    AppStorage.setOrCreate(AppKeys.LIB_DIRTY, 0);
    AppStorage.setOrCreate(AppKeys.PLUGINS_DIRTY, 0);
    AppStorage.setOrCreate(AppKeys.CF_CHALLENGE_URL, '');
    Settings.init(this.context);
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
    // 插件宿主（JSVM 隔离引擎）：HTTP 桥必须在首个插件网络请求前就绪，保持同步
    PluginService.init(this.context);
    JsvmExtensionManager.init();
    this.handleCardWant(want);
    // ── 第1级（主线程空闲即执行，先于首帧内容挂载）：非首帧必需的服务初始化 ──
    setTimeout((): void => {
      hilog.info(DOMAIN, 'Mihon', 'AVIF PROBE: callback entered');
      DownloadService.init(this.context);
      CookieJar.init(this.context);
      ImageCache.init(this.context);
      hilog.info(DOMAIN, 'Mihon', 'AVIF PROBE: pre probe');
      // TEMP PROBE: AVIF 解码能力实测（诊断 photos18 图片问题，验证后移除）
      this.probeAvifDecode();
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

  // TEMP PROBE: 读取缓存中的 .avif 文件实测系统解码能力（验证后移除）
  private probeAvifDecode(): void {
    try {
      const dir = `${this.context.cacheDir}/image_file_cache`;
      const names = fs.listFileSync(dir);
      let avif = '';
      for (let i = 0; i < names.length; i++) {
        if (names[i].endsWith('.avif')) {
          avif = names[i];
          break;
        }
      }
      if (avif === '') {
        hilog.warn(DOMAIN, 'Mihon', 'AVIF PROBE: no cached avif file');
        return;
      }
      const file = fs.openSync(`${dir}/${avif}`, fs.OpenMode.READ_ONLY);
      const imgSrc = image.createImageSource(file.fd);
      imgSrc.createPixelMap({ desiredSize: { width: 64, height: 64 } }).then((pm: image.PixelMap) => {
        pm.getImageInfo().then((info: image.ImageInfo) => {
          hilog.info(DOMAIN, 'Mihon', 'AVIF PROBE OK: %{public}dx%{public}d %{public}s',
            info.size.width, info.size.height, avif);
          pm.release();
          imgSrc.release();
          fs.closeSync(file);
        }).catch((e: BusinessError) => {
          hilog.error(DOMAIN, 'Mihon', 'AVIF PROBE getImageInfo fail: %{public}s', e.message);
        });
      }).catch((e: BusinessError) => {
        hilog.error(DOMAIN, 'Mihon', 'AVIF PROBE DECODE FAIL: %{public}s %{public}s', e.code.toString(), e.message);
        imgSrc.release();
        fs.closeSync(file);
      });
    } catch (e) {
      hilog.error(DOMAIN, 'Mihon', 'AVIF PROBE throw: %{public}s', (e as Error).message);
    }
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
    // 退后台先结算进行中的阅读会话，再刷新桌面卡片
    ReadingStatsRepo.flush();
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
