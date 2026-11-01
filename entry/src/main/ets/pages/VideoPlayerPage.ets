import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { SheetPreset } from './components/SheetPreset';
import { KeyCode } from '@kit.InputKit';
import { media } from '@kit.MediaKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { window, PiPWindow, uiMaterial, display, UIContext } from '@kit.ArkUI';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { AVCastPicker } from '@kit.AVSessionKit';
import { CacheListener } from '@ohos/video-cache';
import { AppDb } from '../data/AppDb';
import { ChapterRepo, HistoryRepo, MangaRepo } from '../data/Repos';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { DownloadService } from '../data/DownloadService';
import { BtFlow } from '../data/BtFlow';
import { BtModule } from '../data/BtModule';
import type { TorrentFileJson } from '@honyomi/torrent';
import { AppKeys } from '../common/AppKeys';
import { DanmakuItem, DanmakuService, DdpAccount } from '../data/DanmakuService';
import { CommentSegment, CommentBlock, EpisodeComment, EpisodeReaction, EpisodeCommentReply,
  EpisodeCommentService } from '../data/EpisodeCommentService';
import { TrackerManager } from '../data/track/TrackerManager';
import { SubCue, SubtitleParser } from '../common/SubtitleParser';
import { SourceRegistry } from '../source/Source';
import { Http } from '../net/Http';
import { ChapterRecord, ContentType, MangaRecord, SVideo } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';
import { ContinueSession } from '../common/ContinueSession';
import { Settings } from '../common/Settings';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { VideoCacheServer } from '../common/VideoCacheServer';
import { HlsDownloader } from '../common/HlsDownloader';
import { M3u8ProxyServer } from '../common/M3u8ProxyServer';
import { PipPageHooks, PipSessionInfo, VideoPipManager } from '../common/VideoPipManager';
import { VideoCastItem, VideoCastManager } from '../common/VideoCast';
import { ChapterNeighbors, ReaderChapterNav } from '../common/ReaderChapterNav';
import { Haptics } from '../common/Haptics';
import { AppIcon } from './components/AppIcon';
import { CoverViewer } from './components/CoverViewer';
import { DanmakuController, DanmakuView } from './components/DanmakuView';
import { OAuthSheet } from './components/OAuthSheet';

const SPEEDS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
const SCALE_MODES: number[] = [0, 1, 2];
// 长按快进档位（与画面顶部的速度胶囊一一对应）
const BOOST_SPEEDS: number[] = [1.0, 1.5, 2.0, 3.0];
const DM_FONT_VALUES: number[] = [12, 14, 16, 18, 20];
const DM_OPACITY_VALUES: number[] = [30, 50, 80, 100];
const DM_AREA_VALUES: number[] = [25, 50, 75, 100];
const DM_DUR_VALUES: number[] = [12, 10, 8, 6];
// 弹幕发送可选颜色（dandanplay 24bit）
const DM_SEND_COLORS: number[] = [0xFFFFFF, 0xFE0302, 0xFF7204, 0xFFFF00, 0x00CD00, 0x00BFFF, 0xFF00FF];
// 视频播控按钮液态玻璃材质（官方沉浸光感，Button.systemMaterial 生效）：
// 薄材质 THIN + 暗色赋色保证任意画面下白色图标可读，交互形变 + 点光源按压反馈
// 替代默认按压态。Button 必须显式设置 backgroundColor：材质生效时按该颜色渲染材质，
// 材质不生效的设备（PC/2in1 模拟器等）回退为该暗色底，任何路径都不会露出 Button 默认主题蓝
const VIDEO_GLASS: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
  style: uiMaterial.ImmersiveStyle.THIN,
  materialColor: '#66000000',
  interactive: true,
  lightEffect: { color: Color.White }
});
const VIDEO_BTN_BG: ResourceColor = '#66000000';
// 续播避开片尾：保存进度落在片尾数秒内（上次已基本看完）时重新从头播放，
// 防止续播到片尾立即触发 completed → 自动下一集，导致点选剧集被瞬间跳走
const VIDEO_RESUME_TAIL_MS: number = 5000;
// 发评人机验证（Cloudflare Turnstile）：next.bgm.tv 域 sitekey，
// 由隐藏 Web 加载 next.bgm.tv 页面后注入 invisible 组件获取 token（5 分钟有效、一次性）
const TS_SITEKEY: string = '0x4AAAAAAABkMYinukE8nzYS';
const TS_PAGE_URL: string = 'https://next.bgm.tv/';
const TS_TOKEN_VALID_MS: number = 240000;
let vpSeq: number = 0;

// 意图框架快进指令载荷（AppStorage videoSeek 键，VideoSeekIntent 写入）
interface VpSeekCommand {
  mode: string; // delta 相对位移 | absolute 绝对位置 | end 片尾
  ms: number;
  ts: number;
}

// BT 边下边播目标文件快照（字节）
interface BtHeadInfo {
  done: number; // 已下载字节
  size: number; // 文件总字节
  minHead: number; // 起播门槛 min(8MB, 5%)
}

// 代理缓存进度监听：把 OhosVideoCache 下载百分比同步到页面状态
class VpCacheListener implements CacheListener {
  private onPct: (pct: number) => void;

  constructor(onPct: (pct: number) => void) {
    this.onPct = onPct;
  }

  onCacheAvailable(_cacheFilePath: string, _url: string, percentsAvailable: number): void {
    this.onPct(percentsAvailable);
  }
}

// 视频播放器（参考 AnymeX 播放器布局）：沉浸式全屏 + 顶部/中部/底部悬浮控制条，
// 双击左右区域快退/快进 10s，控制条 4s 自动隐藏，支持锁定、倍速、画质、剧集列表与弹幕
@Component
export struct VideoPlayerPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  // 退出播放器时递增，驱动历史/书架等常驻页签重载数据（同 ReaderPage）
  @StorageLink('libDirty') libDirty: number = 0;
  // 意图框架快进/跳转指令（仅栈顶最新实例消费）
  @StorageLink('videoSeek') @Watch('onSeekCommand') seekCommand: string = '';
  @State manga: MangaRecord = new MangaRecord();
  @State chapter: ChapterRecord = new ChapterRecord();
  @State videos: SVideo[] = [];
  @State chapters: ChapterRecord[] = [];
  @State qualityIndex: number = 0;
  @State loading: boolean = true;
  @State playing: boolean = false;
  @State buffering: boolean = true;
  @State positionMs: number = 0;
  @State durationMs: number = 0;
  @State errorText: string = '';
  @State prevId: number = 0;
  @State nextId: number = 0;
  @State showControls: boolean = true;
  @State locked: boolean = false;
  @State speed: number = 1.0;
  @State autoNext: boolean = true;
  @State seekToast: number = 0;
  @State showSheet: boolean = false;
  @State sheetMode: number = 0;
  @State danmakuOn: boolean = true;
  @State dmFont: number = 16;
  @State dmOpacity: number = 80;
  @State dmArea: number = 50;
  @State dmDur: number = 10;
  @State fullscreen: boolean = false;
  @State boosting: boolean = false;
  @State boostSpeedIndex: number = 2;
  @State scaleMode: number = 0;
  @State cachePercent: number = 0;
  @State volume: number = 1.0;
  @State muted: boolean = false;
  @State volHudPct: number = -1;
  // 华为视频手势：亮度 HUD（左半屏上下滑）/ 快进 HUD（横滑）/ 续播提示
  @State brightHudPct: number = -1;
  @State seekHudMs: number = -1;
  @State showResumeTip: boolean = false;
  @State resumeTipMs: number = 0;
  @State casting: boolean = false;
  @State castDevice: string = '';
  private mangaId: number = -1;
  private chapterId: number = -1;
  private resumeMs: number = 0;
  private savedMs: number = 0;
  private surfaceId: string = '';
  private player: media.AVPlayer | undefined = undefined;
  private mediaFile: fs.File | undefined = undefined;
  private cacheListener: CacheListener | undefined = undefined;
  private cacheUrl: string = '';
  // 在线 m3u8 广告剔除改写：当前使用改写后的本地播放地址 / 对应视频 /
  // 已回退直连过的地址（同一地址仅自动回退一次，防循环）
  private hlsRewriteActive: boolean = false;
  private hlsRewriteVideo: SVideo | undefined = undefined;
  private hlsRewriteFailedUrl: string = '';
  private xCtrl: XComponentController = new XComponentController();
  // 画中画（华为视频对齐）：XComponent 内容迁移至系统小窗；退后台时按播放状态自动小窗
  @State pipEnabled: boolean = false;
  @State pipActive: boolean = false;
  // 手动小窗移交成功标记：aboutToDisappear 时跳过 PiP 清理（会话已归管理器接管）
  private pipHandedOff: boolean = false;
  private pipPageHooks: PipPageHooks | undefined = undefined;
  private ticker: number = -1;
  private dragging: boolean = false;
  private localPath: string = '';
  private playGen: number = 0;
  private loadGen: number = 0;
  private destroyed: boolean = false;
  private videoW: number = 0;
  private videoH: number = 0;
  private areaW: number = 0;
  private areaH: number = 0;
  private hideTimer: number = -1;
  private tapTimer: number = -1;
  private seekToastTimer: number = -1;
  private seekCmdTs: number = 0;
  private boostTimer: number = -1;
  private suppressTimer: number = -1;
  private boostDownX: number = 0;
  private boostAnchorX: number = 0;
  private suppressClick: boolean = false;
  // 键盘长按空格：延迟判定计时 + 按下状态（过滤系统按键重复）
  private spaceTimer: number = -1;
  private spaceDown: boolean = false;
  private volumeHudTimer: number = -1;
  // ---- 华为视频手势状态 ----
  // 手势类型：0 无 1 亮度（左半屏上下滑）2 音量（右半屏上下滑）3 快进（横滑）
  private panMode: number = 0;
  private panLeftHalf: boolean = false;
  private panBaseBright: number = 0.5;
  private panBaseVol: number = 1;
  private panSeekFrom: number = 0;
  private brightHudTimer: number = -1;
  private resumeTipTimer: number = -1;
  private resumeTipArmed: boolean = false;
  // 播放器亮度（0=跟随系统，(0,1]=固定亮度，随手势更新并持久化）
  private videoBright: number = 0;
  private win: window.Window | undefined = undefined;
  // PC/2in1：真全屏走窗口最大化沉浸式；进入前是悬浮窗则退出时 recover 还原尺寸位置
  private pcLike: boolean = deviceInfo.deviceType === 'pc' || deviceInfo.deviceType === '2in1';
  private pcWasFloating: boolean = true;
  private dmCtrl: DanmakuController = new DanmakuController();
  private dmLoading: boolean = false;
  private dmChapterId: number = -1;
  // ---- 剧集评论（Bangumi 吐槽箱）----
  @State comments: EpisodeComment[] = [];
  // 评论面板状态：0 加载中 1 已加载 2 失败 3 空闲（未开始/已重置）
  @State commentsState: number = 3;
  @State commentsErrNoEp: boolean = false;
  // 当前集 ep id（发评目标；0 未解析）
  @State commentsEpId: number = 0;
  // 发评/回复输入
  @State commentInput: string = '';
  @State commentSending: boolean = false;
  // 回复模式：0 = 顶层吐槽；> 0 = 楼中楼目标（主评论 id）
  @State replyToId: number = 0;
  @State replyToName: string = '';
  // Bangumi 登录态（发评/回应前置条件；OAuth token 复用为 /p1 Bearer）
  @State bgmLoggedIn: boolean = false;
  @State showBgmLogin: boolean = false;
  @State bgmLoginUrl: string = '';
  // 表情回应选择器（> 0 = 打开，值为目标评论 id）
  @State showReactPicker: boolean = false;
  @State reactPickerId: number = 0;
  @State reactPickerCurrent: number = 0;
  private commentsGen: number = 0;
  // ---- Turnstile token（隐藏 Web 注入获取）----
  private tsController: webview.WebviewController = new webview.WebviewController();
  private tsInjected: boolean = false;
  private tsToken: string = '';
  private tsTokenAt: number = 0;
  // 评论加载完成后才挂载隐藏 Web（避免每次进播放页都拉取 next.bgm.tv）
  @State tsWebMounted: boolean = false;
  // ---- 非全屏布局：窗口横竖（rootW > rootH，由根 onAreaChange 维护）----
  @State isWide: boolean = false;
  // @State：非横竖翻转的根区尺寸变化也需立即重排，普通成员不触发刷新会让视频区沿用旧尺寸
  @State rootW: number = 0;
  @State rootH: number = 0;
  // 根区是否已被 onAreaChange 精确测量（精确值优先，display/窗口推定值不覆盖）
  private rootMeasured: boolean = false;
  // 非全屏内容区避让（全局维护，随旋转经 avoidAreaChange 同步），用于首帧几何推定
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  // ---- 折叠屏悬停态：全屏时上半屏视频/下半屏常驻控制条；非全屏时视频与评论分界线避让折痕带 ----
  @State hoverActive: boolean = false;
  @State hoverBandH: boolean = true; // true 折痕横向（上下分界），false 折痕纵向（左右分界）
  @State hoverBandStart: number = 0; // 折痕带上沿 vp（相对窗口）
  @State hoverBandEnd: number = 0; // 折痕带下沿 vp（相对窗口）
  private foldCb: ((status: display.FoldStatus) => void) | undefined = undefined;
  // 上次布局生效的全屏悬停分屏态：用于捕捉分屏进入/退出（含横竖/全屏切换触发）
  private lastSplitApplied: boolean = false;
  // ---- 跳过 OP/ED（区间秒，-1 未设置）----
  @State skipOpS: number = -1;
  @State skipOpE: number = -1;
  @State skipEdS: number = -1;
  @State skipEdE: number = -1;
  @State skipOpText: string = '';
  @State skipOpEText: string = '';
  @State skipEdSText: string = '';
  @State skipEdEText: string = '';
  // 全局开关（持久化）+ 生效标记（开关且已配置区间）
  @State skipEnabled: boolean = false;
  @State skipActive: boolean = false;
  // 区间触发时短暂显示的浮动提示：0 无 1 跳片头 2 跳片尾
  @State skipChip: number = 0;
  private edSkipFired: boolean = false;
  // ---- 外挂字幕 ----
  @State subtitleOn: boolean = false;
  @State subFont: number = 18;
  @State subText: string = '';
  private subCues: SubCue[] = [];
  private subPath: string = '';
  // ---- 弹幕发送（dandanplay 账号）----
  @State dmAccount: DdpAccount | undefined = undefined;
  @State dmLoginName: string = '';
  @State dmLoginPass: string = '';
  @State dmLogging: boolean = false;
  @State dmSendText: string = '';
  @State dmSendMode: number = 1;
  @State dmSendColor: number = 0xFFFFFF;
  @State dmSending: boolean = false;
  // 弹幕输入框聚焦中：控制条不自动隐藏，避免输入被打断
  @State dmInputFocused: boolean = false;
  private dmItems: DanmakuItem[] = [];
  private instId: number = ++vpSeq;
  // 投屏：AVCastPicker 发现设备，连接/断开/远端播放态经 VideoCastManager 回调驱动页面
  private castMgr: VideoCastManager = new VideoCastManager({
    onConnected: (deviceName: string): void => {
      this.onCastConnected(deviceName);
    },
    onDisconnected: (positionMs: number): void => {
      this.onCastDisconnected(positionMs);
    },
    onPlayback: (playing: boolean, positionMs: number, durationMs: number): void => {
      this.onCastPlayback(playing, positionMs, durationMs);
    },
    onEnded: (): void => {
      this.onCastEnded();
    },
    onCommand: (command: string): void => {
      if (command === 'play') {
        if (!this.playing) {
          this.togglePlay();
        }
      } else if (command === 'pause') {
        if (this.playing) {
          this.togglePlay();
        }
      }
    }
  });
  // BT 边下边播：localPath 为预分配稀疏文件，fdSrc 须限制在已下载字节数内，
  // 到达边界（completed/error）后等待新数据重开播放器并续播
  private btPending: boolean = false;
  private btProgressive: boolean = false;
  private btStatSize: number = 0;
  private btSafeLen: number = 0;
  private btFileDone: number = 0;

  aboutToAppear(): void {
    this.log('aboutToAppear');
    this.speed = Settings.getVideoSpeed();
    this.volume = Settings.getVideoVolume();
    this.videoBright = Settings.getVideoBrightness();
    this.autoNext = Settings.getVideoAutoNext();
    this.scaleMode = Settings.getVideoScaleMode();
    this.danmakuOn = Settings.getDanmakuEnabled();
    this.dmFont = Settings.getDanmakuFont();
    this.dmOpacity = Settings.getDanmakuOpacityPct();
    this.dmArea = Settings.getDanmakuAreaPct();
    this.dmDur = Settings.getDanmakuDurationSec();
    // 底部弹幕输入条按登录态渲染：进入页面即恢复已保存的 dandanplay 账号
    this.dmAccount = DanmakuService.savedAccount();
    // 评论发评/回应按登录态渲染：Bangumi OAuth token 复用为 /p1 Bearer
    this.bgmLoggedIn = EpisodeCommentService.isLoggedIn();
    this.skipEnabled = Settings.getVideoSkipOpEd();
    this.subFont = Settings.getSubtitleFont();
    this.pipEnabled = PiPWindow.isPiPEnabled();
    // 横屏直进：首帧前同步推定根区横竖与尺寸，避免首个 onAreaChange 缺席/迟到时
    // 按竖屏默认布局把视频区撑高、进度条下方控件推出屏幕（旋转后 onAreaChange 到达才恢复）
    this.initRootGeometry();
    // 折叠屏悬停态监听：全屏时上半屏视频/下半屏常驻控制条；非全屏时视频与评论分界线避让折痕带
    this.setupFoldListener();
    // 沉浸式：隐藏状态栏与导航栏（页面已销毁则放弃，避免销毁后隐藏系统栏且无法还原）
    window.getLastWindow(Util.hostAbilityContext(this.getUIContext())).then((w: window.Window) => {
      if (this.destroyed) {
        return;
      }
      this.win = w;
      // 拿到窗口后按真实窗口矩形+避让区精化根区（display 推定对旋转时序/悬浮窗有偏差）
      this.refineRootGeometry();
      this.updateHoverLayout();
      if (canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
        if (this.pcLike) {
          w.setWindowSystemBarEnable([]).catch((): void => {
          });
        } else {
          // 非全屏：布局全屏关闭 + 显示状态栏，系统自动避让状态栏/摄像头挖孔区
          w.setWindowLayoutFullScreen(false).catch((): void => {
          });
          w.setWindowSystemBarEnable(['status']).catch((): void => {
          });
          // 窗口跟随设备旋转：竖屏视频上/评论下，横屏视频左/评论右；
          // 全屏仅由按钮/快捷键触发锁定横向，设备旋转不再自动进全屏
          w.setPreferredOrientation(window.Orientation.AUTO_ROTATION).catch((): void => {
          });
        }
      }
    }).catch((): void => {
    });
  }

  aboutToDisappear(): void {
    this.log('aboutToDisappear');
    this.destroyed = true;
    if (this.foldCb !== undefined) {
      try {
        display.off('foldStatusChange', this.foldCb);
      } catch (e) {
        this.log(`fold off catch: ${e}`);
      }
      this.foldCb = undefined;
    }
    this.loadGen += 1;
    this.persist(false);
    ReadingStatsRepo.flush();
    // 观看历史已随加载/进度落库：递增 libDirty 让历史页等常驻页签及时刷新
    this.libDirty += 1;
    this.stopTicker();
    this.clearUiTimers();
    this.releasePlayer();
    // 画中画：手动小窗已移交管理器（会话存活）则保留；否则解除退后台自动小窗并停止页面持有的 PiP
    if (this.pipHandedOff) {
      this.pipHandedOff = false;
    } else {
      VideoPipManager.getInstance().detachPage(this.pipPageHooks, true);
    }
    this.castMgr.destroy();
    if (this.win !== undefined) {
      // 还原系统栏与窗口方向；PC 全屏态先退出沉浸式，避免下一页残留无标题栏窗口
      if (this.pcLike && this.fullscreen) {
        this.exitPcFullscreen();
        this.fullscreen = false;
      }
      if (canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
        if (!this.pcLike) {
          // 还原应用级沉浸式全屏布局（EntryAbility 默认 true），其余页面手动避让依赖该模式
          this.win.setWindowLayoutFullScreen(true).catch((): void => {
          });
        }
        this.win.setPreferredOrientation(window.Orientation.UNSPECIFIED).catch((): void => {
        });
        this.win.setWindowSystemBarEnable(['status', 'navigation']).catch((): void => {
        });
        // 还原手势调节的窗口亮度（0=跟随系统）
        this.win.setWindowBrightness(0).catch((): void => {
        });
      }
      Settings.applySystemBar(Util.hostAbilityContext(this.getUIContext()));
    }
  }

  // ---- 折叠屏悬停态 ----
  // 注册折叠状态监听：非折叠设备直接跳过（isFoldable 返回 false）
  private setupFoldListener(): void {
    try {
      if (!display.isFoldable()) {
        return;
      }
      this.foldCb = (status: display.FoldStatus): void => {
        this.updateHoverLayout();
      };
      display.on('foldStatusChange', this.foldCb);
      this.updateHoverLayout();
    } catch (e) {
      this.log(`fold on catch: ${e}`);
    }
  }

  // 首帧根区几何推定：横屏直进时 onAreaChange 的首次精确回调存在缺席/迟到窗口，
  // 默认按竖屏（isWide=false）布局会把视频区按横屏宽度的 9/16 撑高，底部控件被推出屏幕；
  // 首帧前用 display（同步 API）按当前旋转直接落地横竖与近似尺寸，精确值仍由 onAreaChange 修正
  private initRootGeometry(): void {
    if (this.pcLike) {
      return;
    }
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const density: number = d.densityPixels > 0 ? d.densityPixels : 1;
      // 非全屏窗口内容区 = display 减去状态栏与手势指示条避让
      const wVp: number = d.width / density;
      const hVp: number = d.height / density - this.statusBarH - this.navBarH;
      if (wVp > 0 && hVp > 0) {
        this.rootW = wVp;
        this.rootH = hVp;
        this.isWide = wVp > hVp;
      }
    } catch (e) {
      this.log(`initRootGeometry catch: ${e}`);
    }
  }

  // 窗口级精化：按真实窗口矩形+避让区重估根区；已被 onAreaChange 精确测量时不覆盖
  private refineRootGeometry(): void {
    if (this.pcLike || this.rootMeasured || this.win === undefined) {
      return;
    }
    try {
      const rect: window.Rect = this.win.getWindowProperties().windowRect;
      const top: number = this.win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height;
      const bottom: number =
        this.win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height;
      const ui: UIContext = this.getUIContext();
      const wVp: number = ui.px2vp(rect.width);
      const hVp: number = ui.px2vp(rect.height - top - bottom);
      if (wVp > 0 && hVp > 0) {
        this.rootW = wVp;
        this.rootH = hVp;
        this.isWide = wVp > hVp;
      }
    } catch (e) {
      this.log(`refineRootGeometry catch: ${e}`);
    }
  }

  // 悬停态判定与折痕几何重算：半折叠时读取折痕区（设备物理空间像素，不随窗口旋转），
  // 先按 display 旋转角点映射到窗口空间，再减去窗口偏移后转 vp，
  // 得到折痕带在窗口内的上下/左右边界。
  private updateHoverLayout(): void {
    if (this.destroyed) {
      return;
    }
    let active: boolean = false;
    let bandH: boolean = true;
    let start: number = 0;
    let end: number = 0;
    try {
      if (this.win !== undefined && display.isFoldable() &&
        display.getFoldStatus() === display.FoldStatus.FOLD_STATUS_HALF_FOLDED) {
        const crease: display.FoldCreaseRegion = display.getCurrentFoldCreaseRegion();
        if (crease.creaseRects.length > 0) {
          const winRect: window.Rect = this.win.getWindowProperties().windowRect;
          const mapped: display.Rect = this.mapCreaseToWindow(crease.creaseRects[0]);
          // 折痕带方向：窗口空间矩形宽>高为横向折痕（上下分界），否则纵向折痕（左右分界）
          bandH = mapped.width > mapped.height;
          const axisLen: number = bandH ? winRect.height : winRect.width;
          // 非全屏时窗口矩形仍铺满屏幕，但系统把内容起点压到状态栏之下；
          // 折痕边界相对内容区须再减去状态栏避让高度，否则视频/评论整体偏下一个状态栏高度
          let contentOffsetPx: number = 0;
          if (!this.fullscreen) {
            const avoid: window.AvoidArea = this.win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
            const topInset: number = avoid.topRect.top + avoid.topRect.height;
            const leftInset: number = avoid.leftRect.left + avoid.leftRect.width;
            contentOffsetPx = bandH ? (topInset > 0 ? topInset : 0) : (leftInset > 0 ? leftInset : 0);
          }
          const bandStartPx: number =
            (bandH ? mapped.top : mapped.left) - (bandH ? winRect.top : winRect.left) - contentOffsetPx;
          const bandEndPx: number = bandStartPx + (bandH ? mapped.height : mapped.width);
          // 折痕带从窗口起侧开始且与主轴相交：视频完整落在折痕一侧，边界压折痕带上沿
          if (bandStartPx > 0 && bandEndPx > bandStartPx && bandStartPx < axisLen) {
            start = this.getUIContext().px2vp(bandStartPx);
            end = this.getUIContext().px2vp(bandEndPx < axisLen ? bandEndPx : axisLen);
            if (end > start) {
              active = true;
            }
          }
        }
      }
    } catch (e) {
      this.log(`updateHoverLayout catch: ${e}`);
    }
    const prevSplit: boolean = this.lastSplitApplied;
    if (!(active === this.hoverActive && bandH === this.hoverBandH &&
      start === this.hoverBandStart && end === this.hoverBandEnd)) {
      // 悬停进入/退出或折痕几何变化：元素位置/尺寸过渡动画
      this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, (): void => {
        this.hoverActive = active;
        this.hoverBandH = bandH;
        this.hoverBandStart = start;
        this.hoverBandEnd = end;
      });
      // 悬停进入/退出改变全屏方向策略（竖屏悬停分屏不锁横屏，悬停退出需补锁横向）
      this.syncFullscreenOrientation();
    }
    // 分屏进入/退出（悬停几何、横竖或全屏状态变化触发）：进入时常驻控制条并停用自动隐藏
    const split: boolean = this.hoverSplitOn();
    this.lastSplitApplied = split;
    if (split && !prevSplit) {
      if (this.hideTimer >= 0) {
        clearTimeout(this.hideTimer);
        this.hideTimer = -1;
      }
      this.showControls = true;
    } else if (!split && prevSplit) {
      this.pokeControls();
    }
  }

  // 折痕矩形从设备物理空间映射到窗口空间：creaseRects 不随窗口旋转，
  // 按 display 顺时针旋转角点变换后取包围盒；rotation 为 0 时原样返回
  private mapCreaseToWindow(rect: display.Rect): display.Rect {
    const d: display.Display = display.getDefaultDisplaySync();
    const rot: number = d.rotation;
    if (rot === 0) {
      return rect;
    }
    // 物理自然宽高（竖置基准）：90/270 横置时 display 宽高若已跟随旋转（宽>高）则对调还原
    let natW: number = d.width;
    let natH: number = d.height;
    if ((rot === 1 || rot === 3) && natW > natH) {
      const tmp: number = natW;
      natW = natH;
      natH = tmp;
    }
    // 角点变换：rotation 1（顺时针 90°）x_w=y_p、y_w=natW-x_p；
    // 2（180°）x_w=natW-x_p、y_w=natH-y_p；3（270°）x_w=natH-y_p、y_w=x_p
    const srcXs: number[] = [rect.left, rect.left + rect.width];
    const srcYs: number[] = [rect.top, rect.top + rect.height];
    const xs: number[] = [0, 0];
    const ys: number[] = [0, 0];
    for (let i: number = 0; i < 2; i++) {
      const x: number = srcXs[i];
      const y: number = srcYs[i];
      if (rot === 1) {
        xs[i] = y;
        ys[i] = natW - x;
      } else if (rot === 2) {
        xs[i] = natW - x;
        ys[i] = natH - y;
      } else {
        xs[i] = natH - y;
        ys[i] = x;
      }
    }
    const minX: number = xs[0] < xs[1] ? xs[0] : xs[1];
    const maxX: number = xs[0] > xs[1] ? xs[0] : xs[1];
    const minY: number = ys[0] < ys[1] ? ys[0] : ys[1];
    const maxY: number = ys[0] > ys[1] ? ys[0] : ys[1];
    const mapped: display.Rect = {
      left: minX,
      top: minY,
      width: maxX - minX,
      height: maxY - minY
    };
    return mapped;
  }

  // 全屏悬停分屏（仅竖屏）：上半屏（正对用户）视频 + 下半屏常驻控制条，严格避开折痕避让区；
  // 横屏悬停全屏为整屏视频（不避折痕）
  private hoverSplitOn(): boolean {
    return this.hoverActive && this.fullscreen && !this.isWide;
  }

  // 非全屏悬停折痕避让：保持正常上下/左右布局，仅视频与评论分界线避开折痕带
  private hoverAvoidBand(): boolean {
    return this.hoverActive && !this.fullscreen;
  }

  // 悬停态是否启用折痕避让布局（全屏分屏或非全屏分界线避让）
  private hoverApply(): boolean {
    return this.hoverSplitOn() || this.hoverAvoidBand();
  }

  // 悬停避让布局的主轴方向：避让激活时一律跟随折痕方向（横向折痕=上下布局），否则保持原横竖
  private hoverDirRow(): boolean {
    return this.hoverApply() ? !this.hoverBandH : this.isWide;
  }

  // 悬停态视频区主轴长度（vp）：视频填满折痕一侧，边界压折痕带上沿
  private hoverVideoLen(): number {
    return this.hoverBandStart;
  }

  // 折痕避让带厚度（vp）：折痕带本身（上沿到下沿）
  private hoverGapLen(): number {
    const len: number = this.hoverBandEnd - this.hoverBandStart;
    return len > 0 ? len : 0;
  }

  // 视频区宽：各状态统一数值尺寸，保证状态切换时宽度可插值动画；
  // 主轴（Row）时全屏=页宽/悬停避让=压折痕带上沿/横屏非全屏=页宽-评论面板宽，交叉轴铺满
  private videoAreaW(): Length {
    if (this.hoverDirRow()) {
      if (this.hoverApply()) {
        return this.hoverVideoLen();
      }
      if (this.fullscreen) {
        return this.rootW > 0 ? this.rootW : '100%';
      }
      return this.rootW > 0 ? this.rootW - this.commentsPanelW() : '100%';
    }
    return '100%';
  }

  // 视频区高：主轴（Column）时悬停避让=压折痕带上沿/全屏=页高/竖屏非全屏=16:9，交叉轴铺满
  private videoAreaH(): Length {
    if (!this.hoverDirRow()) {
      if (this.hoverApply()) {
        return this.hoverVideoLen();
      }
      if (this.fullscreen) {
        return this.rootH > 0 ? this.rootH : '100%';
      }
      return this.portraitVideoH();
    }
    return this.rootH > 0 ? this.rootH : '100%';
  }

  // ---- 悬浮控制条 ----
  @Builder
  topBar() {
    Row() {
      AppIcon({ name: 'arrow_back', iconSize: 24, tint: Color.White })
        .onClick(() => {
          this.pathStack.pop();
        })
      Column({ space: 2 }) {
        Text(this.manga.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.chapter.name)
          .fontSize(12)
          .fontColor('#DDDDDD')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })

      if (this.resLabel() !== '') {
        Text(this.resLabel())
          .fontSize(11)
          .fontColor(Color.White)
          .backgroundColor('rgba(255,255,255,0.2)')
          .borderRadius(8)
          .padding({
            left: 8,
            right: 8,
            top: 3,
            bottom: 3
          })
          .margin({ right: 8 })
      }
      if (this.pipEnabled) {
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          AppIcon({
            name: 'pip',
            iconSize: 22,
            tint: this.pipActive ? this.pal.primary : Color.White
          })
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .padding(0)
        .backgroundColor(VIDEO_BTN_BG)
        .systemMaterial(VIDEO_GLASS)
        .margin({ right: 8 })
        .onClick(() => {
          this.togglePiP();
        })
      }

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        AppIcon({
          name: 'cast',
          iconSize: 22,
          tint: this.casting ? this.pal.primary : Color.White
        })
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .padding(0)
      .backgroundColor(VIDEO_BTN_BG)
      .systemMaterial(VIDEO_GLASS)
      .margin({ right: 8 })
      .onClick(() => {
        this.openCastSheet();
      })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        AppIcon({ name: 'lock', iconSize: 22, tint: Color.White })
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .padding(0)
      .backgroundColor(VIDEO_BTN_BG)
      .systemMaterial(VIDEO_GLASS)
      .onClick(() => {
        this.locked = true;
        Util.toastRes(this.getUIContext(), $r('app.string.video_locked'));
        if (this.hideTimer >= 0) {
          clearTimeout(this.hideTimer);
          this.hideTimer = -1;
        }
        this.showControls = false;
      })
    }
    .width('100%')
    .padding({
      left: 12,
      right: 14,
      top: this.fullscreen ? 12 : 6,
      bottom: 14
    })
    .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0.65)', 0], [Color.Transparent, 1]] })
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  @Builder
  centerBar() {
    Row({ space: 30 }) {
      AppIcon({ name: 'skip_previous', iconSize: 32, tint: this.prevId > 0 ? Color.White : 'rgba(255,255,255,0.3)' })
        .onClick(() => {
          this.openChapter(this.prevId);
        })
      AppIcon({ name: 'replay_10', iconSize: 30, tint: Color.White })
        .onClick(() => {
          this.onDoubleTap(-1);
        })
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        if (this.loading || this.buffering) {
          LoadingProgress().width(44).height(44).color(Color.White)
        } else {
          AppIcon({ name: this.playing ? 'pause' : 'play_arrow', iconSize: 44, tint: Color.White })
        }
      }
      .width(76)
      .height(76)
      .borderRadius(38)
      .padding(0)
      .backgroundColor(VIDEO_BTN_BG)
      .systemMaterial(VIDEO_GLASS)
      .onClick(() => {
        this.togglePlay();
      })

      AppIcon({ name: 'forward_10', iconSize: 30, tint: Color.White })
        .onClick(() => {
          this.onDoubleTap(1);
        })
      AppIcon({ name: 'skip_next', iconSize: 32, tint: this.nextId > 0 ? Color.White : 'rgba(255,255,255,0.3)' })
        .onClick(() => {
          this.openChapter(this.nextId);
        })
    }
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  // 液态玻璃圆形按钮（华为视频对齐）：Button + systemMaterial 官方沉浸光感材质，
  // 毛玻璃/流光/按压点光源均由系统材质绘制，非手写模糊
  @Builder
  ctrlBtn(icon: string, onTap: () => void, tint: ResourceColor) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      AppIcon({ name: icon, iconSize: 22, tint: tint })
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .padding(0)
    .backgroundColor(VIDEO_BTN_BG)
    .systemMaterial(VIDEO_GLASS)
    .onClick(() => {
      onTap();
    })
  }

  // 弹幕输入条：占满控制条空余空间；未登录点击弹登录面板，已登录直接输入，
  // 有内容时出现小飞机发送按钮
  @Builder
  dmInputBar() {
    if (this.dmAccount === undefined) {
      Row() {
        Text($r('app.string.video_danmaku_input_hint'))
          .fontSize(13)
          .fontColor('rgba(255,255,255,0.55)')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 14 })
          .layoutWeight(1)
        AppIcon({ name: 'send', iconSize: 18, tint: 'rgba(255,255,255,0.4)' })
          .margin({ right: 11 })
      }
      .height(40)
      .borderRadius(20)
      .backgroundColor(VIDEO_BTN_BG)
      .systemMaterial(VIDEO_GLASS)
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openSheet(6);
      })
    } else {
      Row() {
        TextInput({ text: this.dmSendText, placeholder: $r('app.string.video_danmaku_input_hint') })
          .fontSize(13)
          .height(40)
          .fontColor('#FFFFFF')
          .placeholderColor('rgba(255,255,255,0.55)')
          .caretColor(this.pal.primary)
          .enterKeyType(EnterKeyType.Send)
          .backgroundColor(Color.Transparent)
          .padding({ left: 14, right: 4 })
          .layoutWeight(1)
          .onChange((v: string) => {
            this.dmSendText = v;
          })
          .onSubmit(() => {
            this.doDmSend();
          })
          .onFocus(() => {
            this.dmInputFocused = true;
            if (this.hideTimer >= 0) {
              clearTimeout(this.hideTimer);
              this.hideTimer = -1;
            }
          })
          .onBlur(() => {
            this.dmInputFocused = false;
            this.armAutoHide();
          })
        if (this.dmSendText.length > 0) {
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            AppIcon({ name: 'send', iconSize: 18, tint: Color.White })
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .padding(0)
          .margin({ right: 4 })
          .backgroundColor(this.pal.primary)
          .enabled(!this.dmSending)
          .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
          .onClick(() => {
            this.doDmSend();
          })
        }
      }
      .height(40)
      .borderRadius(20)
      .backgroundColor(VIDEO_BTN_BG)
      .systemMaterial(VIDEO_GLASS)
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  bottomBar() {
    Column() {
      Row() {
        Text(this.clock(this.positionMs))
          .fontSize(13)
          .fontColor('#FFFFFF')
          .width(58)
        Stack({ alignContent: Alignment.Center }) {
          // 缓存进度条：代理下载百分比（0-100），显示在播放进度条下方
          Progress({
            value: this.cachePercent,
            total: 100,
            type: ProgressType.Linear
          })
            .height(2)
            .width('100%')
            .color('rgba(255,255,255,0.45)')
            .backgroundColor(Color.Transparent)
            .offset({ y: 6 })
          Slider({
            value: this.positionMs,
            min: 0,
            max: this.durationMs > 0 ? this.durationMs : 1,
            step: 1000
          })
            .width('100%')
            .trackThickness(4)
            .blockSize({ width: 12, height: 12 })
            .selectedColor(this.pal.primary)
            .trackColor('rgba(255,255,255,0.3)')
            .blockColor(Color.White)
            .onChange((v: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                this.dragging = true;
                this.positionMs = v;
              } else {
                const interactive = this.dragging || mode === SliderChangeMode.Click;
                this.dragging = false;
                if (interactive && this.durationMs > 0) {
                  this.seekTo(v);
                }
              }
            })
        }
        .layoutWeight(1)

        Text(this.clock(this.durationMs))
          .fontSize(13)
          .fontColor('#E0E0E0')
          .width(58)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Row({ space: 10 }) {
        this.ctrlBtn('playlist_play', (): void => {
          this.openSheet(1);
        }, Color.White)
        if (this.videos.length > 1) {
          this.ctrlBtn('high_quality', (): void => {
            this.openSheet(2);
          }, Color.White)
        }
        this.ctrlBtn('forum', (): void => {
          this.toggleDanmaku();
        }, this.danmakuOn ? Color.White : 'rgba(255,255,255,0.35)')

        this.dmInputBar()

        this.ctrlBtn('tune', (): void => {
          this.openSheet(4);
        }, Color.White)
        this.ctrlBtn(this.fullscreen ? 'fullscreen_exit' : 'fullscreen', (): void => {
          this.toggleFullscreen();
        }, Color.White)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: this.fullscreen ? 16 : 12
    })
    .linearGradient({ angle: 180, colors: [[Color.Transparent, 0], ['rgba(0,0,0,0.65)', 1]] })
    .position({ x: 0, y: '100%' })
    .markAnchor({ x: 0, y: '100%' })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  @Builder
  unlockBtn() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      AppIcon({ name: 'lock_open', iconSize: 24, tint: Color.White })
    }
    .width(48)
    .height(48)
    .borderRadius(24)
    .padding(0)
    .backgroundColor(VIDEO_BTN_BG)
    .systemMaterial(VIDEO_GLASS)
    .position({ x: '86%', y: '44%' })
    .onClick(() => {
      this.locked = false;
      Util.toastRes(this.getUIContext(), $r('app.string.video_unlocked'));
      this.pokeControls();
    })
  }

  // ---- 底部弹层（剧集 / 画质 / 倍速 / 播放设置）----
  // 根节点不设固定高度：配合 FIT_CONTENT 半模态按内容收起，超出系统限高时在 Scroll 内滚动
  @Builder
  sheetBuilder() {
    Column() {
      Row() {
        Text(this.sheetTitle())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
        Blank()
        AppIcon({ name: 'close', iconSize: 22 })
          .onClick(() => {
            this.showSheet = false;
          })
      }
      .width('100%')
      .padding({
        left: 20,
        right: 16,
        top: 14,
        bottom: 8
      })

      Scroll() {
        Column() {
          if (this.sheetMode === 1) {
            this.episodesPane()
          } else if (this.sheetMode === 2) {
            this.qualityPane()
          } else if (this.sheetMode === 5) {
            this.castPane()
          } else if (this.sheetMode === 6) {
            this.dmSendPane()
          } else {
            this.settingsPane()
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 30 })
      }
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .backgroundColor(this.pal.bg)
    .borderRadius({ topLeft: 24, topRight: 24 })
  }

  @Builder
  episodesPane() {
    List() {
      ForEach(this.chapters, (c: ChapterRecord) => {
        ListItem() {
          Row() {
            Text(c.name)
              .fontSize(15)
              .fontColor(c.id === this.chapterId ? this.pal.primary : this.pal.text)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (c.read) {
              AppIcon({ name: 'done', iconSize: 18, tint: this.pal.primary })
            }
          }
          .width('100%')
          .height(48)
          .padding({ left: 8, right: 4 })
          .onClick(() => {
            this.showSheet = false;
            this.openChapter(c.id);
          })
        }
      }, (c: ChapterRecord) => `ep-${c.id}`)
    }
    .width('100%')
  }

  @Builder
  qualityPane() {
    Column() {
      ForEach(this.videos, (video: SVideo, index: number) => {
        Row() {
          Text(video.quality === 'local' ? $r('app.string.video_quality_local') : video.quality)
            .fontSize(15)
            .fontColor(index === this.qualityIndex ? this.pal.primary : this.pal.text)
            .layoutWeight(1)
          if (index === this.qualityIndex) {
            AppIcon({ name: 'done', iconSize: 18, tint: this.pal.primary })
          }
        }
        .width('100%')
        .height(48)
        .padding({ left: 8, right: 4 })
        .onClick(() => {
          this.showSheet = false;
          this.pickQuality(index);
        })
      }, (video: SVideo, index: number) => `q-${index}-${video.quality}`)
    }
    .width('100%')
  }

  // 投屏弹层：系统 AVCastPicker 发现连接设备；已连接时显示设备与断开入口
  @Builder
  castPane() {
    Column({ space: 16 }) {
      if (this.casting) {
        Row({ space: 10 }) {
          AppIcon({ name: 'cast', iconSize: 22, tint: this.pal.primary })
          Text(this.castDevice)
            .fontSize(16)
            .fontColor(this.pal.text)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button($r('app.string.video_cast_disconnect'))
            .fontSize(14)
            .height(36)
            .backgroundColor(this.pal.primary)
            .onClick(() => {
              this.showSheet = false;
              this.castMgr.stopCasting();
            })
        }
        .width('100%')
      } else {
        Text($r('app.string.video_cast_hint'))
          .fontSize(14)
          .fontColor(this.pal.sub)
        Row() {
          AVCastPicker({
            normalColor: '#666666'
          })
            .width(44)
            .height(44)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  settingsPane() {
    Column({ space: 10 }) {
      Text($r('app.string.video_speed'))
        .fontSize(13)
        .fontColor(this.pal.sub)
        .margin({ top: 4 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(SPEEDS, (s: number) => {
          Text(this.speedLabel(s))
            .fontSize(14)
            .fontColor(this.speed === s ? Color.White : this.pal.text)
            .backgroundColor(this.speed === s ? this.pal.primary : this.pal.chip)
            .borderRadius(16)
            .padding({
              left: 16,
              right: 16,
              top: 8,
              bottom: 8
            })
            .margin({ right: 8, top: 8 })
            .onClick(() => {
              this.applySpeed(s);
            })
        }, (s: number) => `set-spd-${s}`)
      }
      .width('100%')

      Row() {
        Text($r('app.string.player_set_auto_next'))
          .fontSize(15)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.autoNext })
          .selectedColor(this.pal.primary)
          .onChange((value: boolean) => {
            this.autoNext = value;
            Settings.setVideoAutoNext(value);
          })
      }
      .width('100%')
      .height(48)

      Text($r('app.string.video_scale_mode'))
        .fontSize(13)
        .fontColor(this.pal.sub)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(SCALE_MODES, (m: number) => {
          Text(this.scaleModeLabel(m))
            .fontSize(14)
            .fontColor(this.scaleMode === m ? Color.White : this.pal.text)
            .backgroundColor(this.scaleMode === m ? this.pal.primary : this.pal.chip)
            .borderRadius(16)
            .padding({
              left: 16,
              right: 16,
              top: 8,
              bottom: 8
            })
            .margin({ right: 8, top: 8 })
            .onClick(() => {
              this.scaleMode = m;
              Settings.setVideoScaleMode(m);
              this.adjustSurface();
            })
        }, (m: number) => `scale-${m}`)
      }
      .width('100%')

      Divider().color(this.pal.divider)

      // ---- 跳过片头/片尾 ----
      Row() {
        Text($r('app.string.player_set_skip_oped'))
          .fontSize(15)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.skipEnabled })
          .selectedColor(this.pal.primary)
          .onChange((value: boolean) => {
            this.skipEnabled = value;
            Settings.setVideoSkipOpEd(value);
            this.skipActive = value && this.hasSkipRanges();
          })
      }
      .width('100%')
      .height(48)

      Text($r('app.string.video_skip_section'))
        .fontSize(13)
        .fontColor(this.pal.sub)
      Row({ space: 8 }) {
        this.skipField($r('app.string.video_skip_op_start'), (): string => this.skipOpText,
          (v: string): void => {
            this.skipOpText = v;
          })
        this.skipField($r('app.string.video_skip_op_end'), (): string => this.skipOpEText,
          (v: string): void => {
            this.skipOpEText = v;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      Row({ space: 8 }) {
        this.skipField($r('app.string.video_skip_ed_start'), (): string => this.skipEdSText,
          (v: string): void => {
            this.skipEdSText = v;
          })
        this.skipField($r('app.string.video_skip_ed_end'), (): string => this.skipEdEText,
          (v: string): void => {
            this.skipEdEText = v;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      Row({ space: 12 }) {
        Button($r('app.string.video_skip_save'))
          .fontSize(14)
          .height(36)
          .backgroundColor(this.pal.primary)
          .onClick(() => {
            this.saveSkipRanges();
          })
        Button($r('app.string.video_skip_clear'))
          .fontSize(14)
          .height(36)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.clearSkipRanges();
          })
      }
      .width('100%')
      .margin({ top: 4 })

      Divider().color(this.pal.divider)

      // ---- 外挂字幕 ----
      Row() {
        Text($r('app.string.player_set_subtitle_enable'))
          .fontSize(15)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.subtitleOn })
          .selectedColor(this.pal.primary)
          .enabled(this.subCues.length > 0)
          .onChange((value: boolean) => {
            this.subtitleOn = value;
            Settings.setSubtitleEnabled(value);
          })
      }
      .width('100%')
      .height(48)
      Row() {
        Text(this.subPath !== '' ? this.subBaseName() : $r('app.string.video_subtitle_none'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text($r('app.string.video_subtitle_pick'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.primary)
          .padding({ left: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.pickSubtitle();
          })
        if (this.subCues.length > 0) {
          Text($r('app.string.video_subtitle_clear'))
            .fontSize(13)
            .fontColor(this.pal.sub)
            .padding({ left: 10, top: 6, bottom: 6 })
            .onClick(() => {
              this.clearSubtitle();
            })
        }
      }
      .width('100%')

      Divider().color(this.pal.divider)

      Row() {
        Text($r('app.string.player_set_danmaku_enable'))
          .fontSize(15)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.danmakuOn })
          .selectedColor(this.pal.primary)
          .onChange((value: boolean) => {
            this.danmakuOn = value;
            Settings.setDanmakuEnabled(value);
            if (value) {
              this.loadDanmaku();
            }
          })
      }
      .width('100%')
      .height(48)

      Text($r('app.string.player_set_danmaku_font'))
        .fontSize(13)
        .fontColor(this.pal.sub)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(DM_FONT_VALUES, (v: number) => {
          Text(`${v}`)
            .fontSize(14)
            .fontColor(this.dmFont === v ? Color.White : this.pal.text)
            .backgroundColor(this.dmFont === v ? this.pal.primary : this.pal.chip)
            .borderRadius(16)
            .padding({
              left: 16,
              right: 16,
              top: 8,
              bottom: 8
            })
            .margin({ right: 8, top: 8 })
            .onClick(() => {
              this.dmFont = v;
              Settings.setDanmakuFont(v);
            })
        }, (v: number) => `dm-font-${v}`)
      }
      .width('100%')

      Text($r('app.string.player_set_danmaku_opacity'))
        .fontSize(13)
        .fontColor(this.pal.sub)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(DM_OPACITY_VALUES, (v: number) => {
          Text(`${v}%`)
            .fontSize(14)
            .fontColor(this.dmOpacity === v ? Color.White : this.pal.text)
            .backgroundColor(this.dmOpacity === v ? this.pal.primary : this.pal.chip)
            .borderRadius(16)
            .padding({
              left: 16,
              right: 16,
              top: 8,
              bottom: 8
            })
            .margin({ right: 8, top: 8 })
            .onClick(() => {
              this.dmOpacity = v;
              Settings.setDanmakuOpacityPct(v);
            })
        }, (v: number) => `dm-op-${v}`)
      }
      .width('100%')

      Text($r('app.string.player_set_danmaku_area'))
        .fontSize(13)
        .fontColor(this.pal.sub)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(DM_AREA_VALUES, (v: number, i: number) => {
          Text(this.areaLabel(i))
            .fontSize(14)
            .fontColor(this.dmArea === v ? Color.White : this.pal.text)
            .backgroundColor(this.dmArea === v ? this.pal.primary : this.pal.chip)
            .borderRadius(16)
            .padding({
              left: 16,
              right: 16,
              top: 8,
              bottom: 8
            })
            .margin({ right: 8, top: 8 })
            .onClick(() => {
              this.dmArea = v;
              Settings.setDanmakuAreaPct(v);
            })
        }, (v: number) => `dm-area-${v}`)
      }
      .width('100%')

      Text($r('app.string.player_set_danmaku_speed'))
        .fontSize(13)
        .fontColor(this.pal.sub)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(DM_DUR_VALUES, (v: number, i: number) => {
          Text(this.durLabel(i))
            .fontSize(14)
            .fontColor(this.dmDur === v ? Color.White : this.pal.text)
            .backgroundColor(this.dmDur === v ? this.pal.primary : this.pal.chip)
            .borderRadius(16)
            .padding({
              left: 16,
              right: 16,
              top: 8,
              bottom: 8
            })
            .margin({ right: 8, top: 8 })
            .onClick(() => {
              this.dmDur = v;
              Settings.setDanmakuDurationSec(v);
            })
        }, (v: number) => `dm-dur-${v}`)
      }
      .width('100%')

      Text($r('app.string.player_set_danmaku_source'))
        .fontSize(12)
        .fontColor(this.pal.sub)
        .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 跳过区间输入字段：标签 + mm:ss 输入 + 「当前」快填
  @Builder
  skipField(label: Resource, getText: () => string, setValue: (v: string) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor(this.pal.sub)
      Row({ space: 4 }) {
        TextInput({ text: getText() })
          .fontSize(13)
          .height(36)
          .fontColor(this.pal.text)
          .caretColor(this.pal.primary)
          .backgroundColor(this.pal.chip)
          .borderRadius(8)
          .padding({ left: 8, right: 4 })
          .layoutWeight(1)
          .onChange((v: string) => {
            setValue(v);
          })
        Text($r('app.string.video_skip_set_current'))
          .fontSize(12)
          .fontColor(this.pal.primary)
          .padding({ left: 4, right: 2 })
          .onClick(() => {
            setValue(this.secToClock(Math.floor(this.positionMs / 1000)));
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
  }

  // 弹幕发送面板：未登录显示账号登录表单，已登录显示输入 + 模式/颜色 + 发送
  @Builder
  dmSendPane() {
    Column({ space: 14 }) {
      if (this.dmAccount === undefined) {
        Text($r('app.string.video_danmaku_login_hint'))
          .fontSize(13)
          .fontColor(this.pal.sub)
        TextInput({ text: this.dmLoginName, placeholder: $r('app.string.video_danmaku_username') })
          .fontSize(14)
          .height(44)
          .fontColor(this.pal.text)
          .caretColor(this.pal.primary)
          .backgroundColor(this.pal.chip)
          .borderRadius(10)
          .padding({ left: 12, right: 8 })
          .onChange((v: string) => {
            this.dmLoginName = v;
          })
        TextInput({ text: this.dmLoginPass, placeholder: $r('app.string.video_danmaku_password') })
          .type(InputType.Password)
          .fontSize(14)
          .height(44)
          .fontColor(this.pal.text)
          .caretColor(this.pal.primary)
          .backgroundColor(this.pal.chip)
          .borderRadius(10)
          .padding({ left: 12, right: 8 })
          .onChange((v: string) => {
            this.dmLoginPass = v;
          })
          .onSubmit(() => {
            this.doDmLogin();
          })
        Button(this.dmLogging ? $r('app.string.video_danmaku_logging') : $r('app.string.video_danmaku_login'))
          .fontSize(14)
          .height(40)
          .width('100%')
          .backgroundColor(this.pal.primary)
          .enabled(!this.dmLogging)
          .onClick(() => {
            this.doDmLogin();
          })
      } else {
        Row() {
          Text($r('app.string.video_danmaku_logged_in'))
            .fontSize(12)
            .fontColor(this.pal.sub)
          Text(this.dmAccount.userName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal.text)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 6 })
          Text($r('app.string.video_danmaku_logout'))
            .fontSize(13)
            .fontColor(this.pal.sub)
            .padding({ left: 8, top: 4, bottom: 4 })
            .onClick(() => {
              DanmakuService.logout();
              this.dmAccount = undefined;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        TextInput({ text: this.dmSendText, placeholder: $r('app.string.video_danmaku_input_hint') })
          .fontSize(14)
          .height(44)
          .fontColor(this.pal.text)
          .caretColor(this.pal.primary)
          .backgroundColor(this.pal.chip)
          .borderRadius(10)
          .padding({ left: 12, right: 8 })
          .onChange((v: string) => {
            this.dmSendText = v;
          })
          .onSubmit(() => {
            this.doDmSend();
          })

        // 弹幕模式：滚动 / 顶部 / 底部
        Row({ space: 8 }) {
          this.dmModeChip($r('app.string.video_danmaku_mode_scroll'), 1)
          this.dmModeChip($r('app.string.video_danmaku_mode_top'), 5)
          this.dmModeChip($r('app.string.video_danmaku_mode_bottom'), 4)
        }
        .width('100%')

        // 弹幕颜色
        Text($r('app.string.video_danmaku_color'))
          .fontSize(12)
          .fontColor(this.pal.sub)
        Row({ space: 10 }) {
          ForEach(DM_SEND_COLORS, (c: number) => {
            Column()
              .width(26)
              .height(26)
              .borderRadius(13)
              .backgroundColor(`#${this.hex6(c)}`)
              .border({
                width: this.dmSendColor === c ? 2 : 0,
                color: this.pal.text
              })
              .onClick(() => {
                this.dmSendColor = c;
              })
          }, (c: number) => `dmc-${c}`)
        }
        .width('100%')

        Row() {
          Text(this.clock(this.positionMs))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .layoutWeight(1)
          Button(this.dmSending ? $r('app.string.video_danmaku_sending') : $r('app.string.video_danmaku_send'))
            .fontSize(14)
            .height(40)
            .backgroundColor(this.pal.primary)
            .enabled(!this.dmSending)
            .onClick(() => {
              this.doDmSend();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 弹幕模式 chip
  @Builder
  dmModeChip(label: Resource, mode: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.dmSendMode === mode ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.dmSendMode === mode ? this.pal.onPrimary : this.pal.text)
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.dmSendMode === mode ? this.pal.primary : this.pal.chip)
      .onClick(() => {
        this.dmSendMode = mode;
      })
  }

  // 竖屏非全屏视频区高度：页面宽度的 9/16（宽度未知时兜底防塌陷）
  private portraitVideoH(): number {
    const base: number = this.rootW > 0 ? this.rootW : this.windowW;
    return base > 0 ? base * 9 / 16 : 220;
  }

  // 横屏评论面板宽：约 25% 页宽，clamp 340~460
  private commentsPanelW(): number {
    const base: number = this.rootW > 0 ? this.rootW : this.windowW;
    if (base <= 0) {
      return 360;
    }
    const w: number = base * 0.25;
    if (w < 340) {
      return 340;
    }
    if (w > 460) {
      return 460;
    }
    return w;
  }

  // 剧集评论面板（Bangumi 吐槽箱）：竖屏在视频下方，横屏在视频右侧
  @Builder
  commentsPanel() {
    Column() {
      Row({ space: 8 }) {
        Text($r('app.string.video_comments_title'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
        if (this.commentsState === 1 && this.comments.length > 0) {
          Text(`${this.comments.length}`)
            .fontSize(12)
            .fontColor(this.pal.sub)
        }
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      if (this.commentsState === 0) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.pal.primary)
          Text($r('app.string.video_comments_loading'))
            .fontSize(13)
            .fontColor(this.pal.sub)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.commentsState === 2) {
        Column({ space: 12 }) {
          Text(this.commentsErrNoEp ? $r('app.string.video_comments_no_episode') :
          $r('app.string.video_comments_failed'))
            .fontSize(13)
            .fontColor(this.pal.sub)
            .textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24 })
          if (!this.commentsErrNoEp) {
            Button($r('app.string.common_retry'))
              .fontSize(14)
              .height(36)
              .padding({ left: 20, right: 20 })
              .backgroundColor(this.pal.primary)
              .fontColor(this.pal.onPrimary)
              .onClick(() => {
                this.loadComments();
              })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.commentsState === 1) {
        if (this.comments.length === 0) {
          Column() {
            Text($r('app.string.video_comments_empty'))
              .fontSize(13)
              .fontColor(this.pal.sub)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.comments, (c: EpisodeComment) => {
              ListItem() {
                VpCommentItem({
                  comment: c,
                  onReply: (replyToId: number, nickname: string, isSubReply: boolean): void => {
                    this.startReply(replyToId, nickname, isSubReply);
                  },
                  onReact: (commentId: number, value: number, current: number): void => {
                    this.toggleReaction(commentId, value, current);
                  },
                  onReactAdd: (commentId: number, current: number): void => {
                    this.openReactPicker(commentId, current);
                  },
                })
              }
            }, (c: EpisodeComment) => `cmt-${c.id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .cachedCount(4)
          .padding({ bottom: 8 })
        }
      } else {
        Column()
          .width('100%')
          .layoutWeight(1)
      }

      // 底部输入区（发评/楼中楼回复）
      this.commentInputBar()

      // 隐藏 Web：next.bgm.tv 页面（Turnstile 域名校验载体），评论加载完成后挂载，
      // onPageEnd 注入 invisible 组件获取发评人机验证 token
      if (this.tsWebMounted) {
        Web({ src: TS_PAGE_URL, controller: this.tsController })
          .width(1)
          .height(1)
          .opacity(0)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(false)
          .onControllerAttached(() => {
            try {
              this.tsController.setCustomUserAgent(Http.USER_AGENT);
              this.tsController.onActive();
            } catch (_e) {
            }
          })
          .onPageEnd(() => {
            this.injectTurnstile();
          })
      }
    }
    // 竖屏占满视频下方剩余高度（layoutWeight）；横屏固定宽占满右侧；
    // 悬停折痕避让时改为 layoutWeight 填满折痕带一侧剩余空间
    .width(this.isWide && !this.hoverAvoidBand() ? this.commentsPanelW() : '100%')
    .height('100%')
    .layoutWeight(this.isWide && !this.hoverAvoidBand() ? 0 : 1)
    .backgroundColor(this.pal.bg)
    .transition(TransitionEffect.OPACITY)
    // 表情回应选择器（12 个合法反应值）
    .bindContentCover($$this.showReactPicker, this.reactPickerBuilder(), {
      modalTransition: ModalTransition.ALPHA,
      backgroundColor: '#00000000',
    })
    // Bangumi OAuth 登录（发评/回应前置）
    .bindSheet($$this.showBgmLogin, this.bgmLoginBuilder(), {
      height: '80%',
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      maskColor: 'rgba(0,0,0,0.45)'
    })
  }

  // 评论底部输入区：回复模式提示条 + 输入框/发送；未登录展示登录入口
  @Builder
  commentInputBar() {
    Column({ space: 6 }) {
      if (this.replyToId > 0) {
        Row({ space: 6 }) {
          Text(Util.resStr(this.getUIContext(), $r('app.string.video_comments_replying_to'),
            [this.replyToName]))
            .fontSize(12)
            .fontColor(this.pal.primary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          AppIcon({ name: 'close', iconSize: 16, tint: this.pal.sub })
            .onClick(() => {
              this.cancelReply();
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14 })
        .alignItems(VerticalAlign.Center)
      }
      if (this.bgmLoggedIn) {
        Row({ space: 8 }) {
          TextInput({ text: this.commentInput,
            placeholder: $r('app.string.video_comments_input_hint') })
            .onChange((v: string) => {
              this.commentInput = v;
            })
            .layoutWeight(1)
            .height(38)
            .fontSize(14)
            .fontColor(this.pal.text)
            .placeholderColor(this.pal.sub)
            .backgroundColor(this.pal.chip)
            .borderRadius(19)
            .padding({ left: 14, right: 14 })
            .caretColor(this.pal.primary)
          if (this.commentSending) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color(this.pal.primary)
          } else {
            Text($r('app.string.video_comments_send'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal.primary)
              .padding({ left: 4, right: 4 })
              .onClick(() => {
                this.sendComment();
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        Row({ space: 8 }) {
          Text($r('app.string.video_comments_login_required'))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .layoutWeight(1)
            .maxLines(1)
          Text($r('app.string.video_comments_login'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal.primary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(14)
            .backgroundColor(this.pal.chip)
            .onClick(() => {
              this.openBgmLogin();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 8 })
  }

  // 表情回应选择器弹层：12 个合法反应值网格，点击即选，点空白处关闭
  @Builder
  reactPickerBuilder() {
    Column() {
      Blank()
      Column() {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(EpisodeCommentService.REACTION_VALUES, (v: number) => {
            Image(EpisodeCommentService.reactionEmojiUrl(v))
              .width(32)
              .height(32)
              .margin(7)
              .objectFit(ImageFit.Contain)
              .onClick(() => {
                this.onReactPickerValue(v);
              })
          }, (v: number) => `rv-${v}`)
        }
      }
      .width('72%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .borderRadius(16)
      .backgroundColor(this.pal.bg)
      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#88000000')
    .onClick(() => {
      this.showReactPicker = false;
    })
  }

  build() {
    NavDestination() {
      // 非全屏自适应窗口方向：竖屏视频上/评论下，横屏视频左/评论右；
      // 用 Flex 方向切换而非 if/else 分支，方向切换不销毁 XComponent 子树。
      // 全屏悬停分屏时主轴跟随折痕方向（横向折痕=上下分屏）
      Flex({ direction: this.hoverDirRow() ? FlexDirection.Row : FlexDirection.Column }) {
        Stack() {
        XComponent({
          id: 'videoSurface',
          type: XComponentType.SURFACE,
          controller: this.xCtrl
        })
          .width('100%')
          .height('100%')
          .onLoad(() => {
            this.surfaceId = this.xCtrl.getXComponentSurfaceId();
            if (!this.loading && this.errorText === '' && this.player === undefined) {
              this.startCurrent();
            }
          })
          .onAreaChange((_old: Area, newArea: Area) => {
            const w = newArea.width;
            if (typeof w === 'number' && w > 0) {
              this.areaW = Math.floor(this.getUIContext().vp2px(w));
            }
            const h = newArea.height;
            if (typeof h === 'number' && h > 0) {
              this.areaH = Math.floor(this.getUIContext().vp2px(h));
            }
            this.adjustSurface();
          })

        DanmakuView({
          controller: this.dmCtrl,
          positionProvider: (): number => this.currentPlayPos(),
          dmEnabled: this.danmakuOn,
          fontVp: this.dmFont,
          opacityPct: this.dmOpacity,
          areaPct: this.dmArea,
          durSec: this.dmDur
        })
          .width('100%')
          .height('100%')

        // 手势分区：左右双击快退/快进，中间单击切换控制条
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .onTouch((event: TouchEvent) => {
              this.boostTouch(event);
            })
            .gesture(TapGesture({ count: 2 })
              .onAction(() => {
                this.onDoubleTap(-1);
              }))
            .onClick(() => {
              this.scheduleTap();
            })
          Column()
            .layoutWeight(1.2)
            .height('100%')
            .onTouch((event: TouchEvent) => {
              this.boostTouch(event);
            })
            .onClick(() => {
              if (this.boosting || this.suppressClick) {
                return;
              }
              if (this.locked) {
                this.pokeControls();
              } else {
                this.toggleControls();
              }
            })
          Column()
            .layoutWeight(1)
            .height('100%')
            .onTouch((event: TouchEvent) => {
              this.boostTouch(event);
            })
            .gesture(TapGesture({ count: 2 })
              .onAction(() => {
                this.onDoubleTap(1);
              }))
            .onClick(() => {
              this.scheduleTap();
            })
        }
        .width('100%')
        .height('100%')
        // 华为视频手势：上下滑调亮度/音量、横滑快进（与双击/长按共存，PanGesture 与 Tap 不冲突）
        .gesture(PanGesture({ fingers: 1, direction: PanDirection.All, distance: 10 })
          .onActionStart((event: GestureEvent) => {
            this.panStart(event);
          })
          .onActionUpdate((event: GestureEvent) => {
            this.panUpdate(event);
          })
          .onActionEnd(() => {
            this.panEnd();
          })
          .onActionCancel(() => {
            this.panEnd();
          }))

        if (this.boosting) {
          // 长按快进：页面顶部显示四个平行速度胶囊，当前档位轻微高亮
          Row({ space: 8 }) {
            ForEach(BOOST_SPEEDS, (s: number, i: number) => {
              Text(this.boostLabel(i))
                .fontSize(14)
                .fontWeight(this.boostSpeedIndex === i ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.boostSpeedIndex === i ? Color.White : '#B3FFFFFF')
                .backgroundColor(this.boostSpeedIndex === i ? 'rgba(255,255,255,0.32)' : 'rgba(255,255,255,0.08)')
                .borderRadius(16)
                .padding({
                  left: 18,
                  right: 18,
                  top: 6,
                  bottom: 6
                })
            }, (s: number, i: number) => `boost-${i}-${s}`)
          }
          .padding(6)
          .borderRadius(22)
          .backgroundColor('rgba(0,0,0,0.4)')
          .offset({ y: '-32%' })
        }

        if (this.seekToast !== 0) {
          Row({ space: 6 }) {
            AppIcon({ name: this.seekToast < 0 ? 'replay_10' : 'forward_10', iconSize: 24, tint: Color.White })
            Text(`${this.seekToast > 0 ? '+' : ''}${this.seekToast}s`)
              .fontSize(15)
              .fontColor(Color.White)
          }
          .padding({
            left: 16,
            right: 16,
            top: 8,
            bottom: 8
          })
          .borderRadius(20)
          .backgroundColor('rgba(0,0,0,0.6)')
          .offset({ x: this.seekToast < 0 ? '-22%' : '22%', y: '-10%' })
        }

        // 投屏中指示：顶部居中显示远端设备名
        if (this.casting) {
          Row({ space: 6 }) {
            AppIcon({ name: 'cast', iconSize: 16, tint: Color.White })
            Text(this.castDevice)
              .fontSize(12)
              .fontColor(Color.White)
              .maxLines(1)
          }
          .padding({
            left: 12,
            right: 12,
            top: 5,
            bottom: 5
          })
          .borderRadius(14)
          .backgroundColor('rgba(0,0,0,0.55)')
          .position({ x: '50%', y: this.fullscreen ? 56 : 64 })
          .markAnchor({ x: '50%' })
        }

        // 键盘音量 HUD：↑↓/M 调节时短暂显示音量条
        if (this.volHudPct >= 0) {
          Row({ space: 8 }) {
            AppIcon({ name: this.volHudPct <= 0 ? 'volume_off' : 'volume_up', iconSize: 22, tint: Color.White })
            Progress({
              value: this.volHudPct,
              total: 100,
              type: ProgressType.Linear
            })
              .width(110)
              .height(4)
              .color(Color.White)
              .backgroundColor('rgba(255,255,255,0.3)')
            Text(`${this.volHudPct}%`)
              .fontSize(13)
              .fontColor(Color.White)
          }
          .padding({
            left: 16,
            right: 16,
            top: 10,
            bottom: 10
          })
          .borderRadius(20)
          .backgroundColor('rgba(0,0,0,0.6)')
          .offset({ y: '-18%' })
        }

        // 手势亮度 HUD：左半屏上下滑调节窗口亮度（0=跟随系统不可低于 5%）
        if (this.brightHudPct >= 0) {
          Row({ space: 8 }) {
            Text($r('app.string.video_brightness'))
              .fontSize(13)
              .fontColor(Color.White)
            Progress({
              value: this.brightHudPct,
              total: 100,
              type: ProgressType.Linear
            })
              .width(110)
              .height(4)
              .color(Color.White)
              .backgroundColor('rgba(255,255,255,0.3)')
            Text(`${this.brightHudPct}%`)
              .fontSize(13)
              .fontColor(Color.White)
          }
          .padding({
            left: 16,
            right: 16,
            top: 10,
            bottom: 10
          })
          .borderRadius(20)
          .backgroundColor('rgba(0,0,0,0.6)')
          .offset({ y: '-18%' })
        }

        // 手势快进 HUD：横滑预览目标时间，松手跳转
        if (this.seekHudMs >= 0) {
          Row({ space: 8 }) {
            AppIcon({
              name: this.seekHudMs >= this.panSeekFrom ? 'forward_30' : 'replay_30',
              iconSize: 22,
              tint: Color.White
            })
            Text($r('app.string.video_seek_to'))
              .fontSize(13)
              .fontColor(Color.White)
            Text(this.clock(this.seekHudMs))
              .fontSize(15)
              .fontColor(Color.White)
          }
          .padding({
            left: 16,
            right: 16,
            top: 10,
            bottom: 10
          })
          .borderRadius(20)
          .backgroundColor('rgba(0,0,0,0.6)')
          .offset({ y: '-26%' })
        }

        // 续播提示（参考华为视频）：继续播放上次进度，可一键「从头播放」
        if (this.showResumeTip) {
          Row({ space: 10 }) {
            AppIcon({ name: 'play_arrow', iconSize: 18, tint: Color.White })
            Text($r('app.string.video_resume_tip'))
              .fontSize(13)
              .fontColor(Color.White)
            Text(this.clock(this.resumeTipMs))
              .fontSize(13)
              .fontColor('rgba(255,255,255,0.7)')
            Text($r('app.string.video_resume_restart'))
              .fontSize(13)
              .fontColor(this.pal.primary)
              .padding({ left: 6, right: 6 })
              .onClick(() => {
                this.showResumeTip = false;
                if (this.resumeTipTimer >= 0) {
                  clearTimeout(this.resumeTipTimer);
                  this.resumeTipTimer = -1;
                }
                Haptics.soft();
                this.seekTo(0);
                this.pokeControls();
              })
          }
          .padding({
            left: 16,
            right: 16,
            top: 10,
            bottom: 10
          })
          .borderRadius(20)
          .backgroundColor('rgba(0,0,0,0.6)')
          .position({ x: '50%', y: '80%' })
          .markAnchor({ x: '50%' })
        }

        // 跳过 OP/ED 触发提示：区间命中时短暂显示
        if (this.skipChip !== 0) {
          Row({ space: 6 }) {
            AppIcon({ name: 'forward_10', iconSize: 16, tint: Color.White })
            Text(this.skipChip === 1 ? $r('app.string.video_skip_op') : $r('app.string.video_skip_ed'))
              .fontSize(13)
              .fontColor(Color.White)
          }
          .padding({
            left: 14,
            right: 14,
            top: 8,
            bottom: 8
          })
          .borderRadius(18)
          .backgroundColor('rgba(0,0,0,0.6)')
          .position({ x: '50%', y: '30%' })
          .markAnchor({ x: '50%' })
        }

        // 外挂字幕：底部居中悬浮，不拦截手势
        if (this.subtitleOn && this.subText !== '') {
          Text(this.subText)
            .fontSize(this.subFont)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '80%' })
            .textShadow({
              radius: 3,
              color: 'rgba(0,0,0,0.9)',
              offsetX: 0,
              offsetY: 1
            })
            .hitTestBehavior(HitTestMode.None)
            .position({ x: '50%', y: '100%' })
            .markAnchor({ x: '50%', y: '100%' })
            .offset({ y: -64 })
        }

        if (this.errorText !== '') {
          Text(Util.errText(this.getUIContext(), this.errorText))
            .fontSize(13)
            .fontColor('#DDDDDD')
            .padding(16)
        } else if ((this.loading || this.buffering) && !(this.showControls && !this.locked)) {
          // 控制条可见时由中央播放按钮展示加载状态，避免双 loading
          LoadingProgress()
            .width(44)
            .height(44)
            .color(Color.White)
        }

        if (!this.hoverSplitOn() && this.showControls && !this.locked) {
          this.topBar()
        }
        if (!this.hoverSplitOn() && this.showControls && !this.locked) {
          this.centerBar()
        }
        if (!this.hoverSplitOn() && this.showControls && !this.locked) {
          this.bottomBar()
        }
        if (!this.hoverSplitOn() && this.locked && this.showControls) {
          this.unlockBtn()
        }
        }
        // 视频区：数值尺寸统一（见 videoAreaW/videoAreaH），全屏/横竖/悬停/全屏分屏切换均可动画
        .width(this.videoAreaW())
        .height(this.videoAreaH())
        .backgroundColor('#000000')

        // 折痕避让带：常驻元素、主轴尺寸动画（0 ↔ 折痕带厚度），
        // 悬停进出时视频与评论/控制区的分界平滑滑动而非跳变
        Column()
          .width(this.hoverDirRow() ? (this.hoverApply() ? this.hoverGapLen() : 0) : '100%')
          .height(this.hoverDirRow() ? '100%' : (this.hoverApply() ? this.hoverGapLen() : 0))
          .backgroundColor('#000000')

        if (!this.fullscreen) {
          this.commentsPanel()
        }

        if (this.hoverSplitOn()) {
          // 全屏悬停态下半屏（平放侧）：控制条常驻，不随 showControls 自动隐藏
          Stack() {
            if (!this.locked) {
              this.topBar()
              this.centerBar()
              this.bottomBar()
            } else {
              this.unlockBtn()
            }
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#000000')
          .transition(TransitionEffect.OPACITY)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      // 键盘控制宿主：默认获焦使 onKeyEvent 生效，触摸重聚焦避免焦点漂移后按键失灵
      .focusable(true)
      .defaultFocus(true)
      .focusOnTouch(true)
      .onKeyEvent((event: KeyEvent) => {
        this.handlePlayerKey(event);
      })
      // 根区尺寸跟踪（vp）：维护横竖方向与竖屏视频高度
      .onAreaChange((_old: Area, newArea: Area) => {
        const w = newArea.width;
        const h = newArea.height;
        if (typeof w === 'number' && typeof h === 'number' && w > 0 && h > 0) {
          // 已获精确测量值：后续 display/窗口推定不再覆盖
          this.rootMeasured = true;
          if (this.rootW <= 0) {
            // 首次测量：直接落地不动画
            this.rootW = w;
            this.rootH = h;
            this.isWide = w > h;
          } else if ((w > h) !== this.isWide) {
            // 横竖切换：布局方向过渡动画
            this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, (): void => {
              this.rootW = w;
              this.rootH = h;
              this.isWide = w > h;
            });
            // 横竖切换改变全屏方向策略（竖屏悬停分屏 ↔ 横屏悬停整屏）
            this.syncFullscreenOrientation();
          } else {
            this.rootW = w;
            this.rootH = h;
          }
        }
        // 折叠屏悬停判定依赖窗口横竖与窗口偏移，随根区变化重估
        this.updateHoverLayout();
      })
      .bindSheet($$this.showSheet, this.sheetBuilder(),
        // 高度自适应内容（SheetPreset 默认 FIT_CONTENT）：选项少时贴内容收起，多时内部滚动
        SheetPreset.fit(this.windowW, {
          showClose: false
        }))
    }
    .hideTitleBar(true)
    .backgroundColor('#000000')
    .onBackPressed((): boolean => {
      // 全屏时返回键先退出全屏，再次返回才退出播放页
      if (this.fullscreen) {
        this.toggleFullscreen();
        return true;
      }
      return false;
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as ReaderParams;
      if (params !== undefined && params !== null) {
        this.mangaId = params.mangaId;
        this.chapterId = params.chapterId;
      }
      this.log(`onReady manga=${this.mangaId} chapter=${this.chapterId}`);
      this.loadChapter();
    })
  }

  private log(msg: string): void {
    hilog.info(0xDEAD, 'VP', '[inst%{public}d] %{public}s', this.instId, msg);
  }

  // 全屏切换：PC/2in1 最大化进入沉浸式（隐藏标题栏/Dock，悬停热区呼出）；其余设备横竖屏切换
  private toggleFullscreen(): void {
    if (this.win === undefined) {
      return;
    }
    if (this.pcLike) {
      this.fullscreen = !this.fullscreen;
      if (this.fullscreen) {
        this.pcWasFloating = this.pcWindowFloating();
        this.win.maximize(window.MaximizePresentation.ENTER_IMMERSIVE).catch((): void => {
        });
      } else {
        this.exitPcFullscreen();
      }
      this.pokeControls();
      return;
    }
    // 横屏即全屏：PC/2in1 无方向概念走窗口最大化；其余设备进入=锁定横向沉浸式，
    // 退出=强制回竖屏（不存在"横屏非全屏"的中间态），竖屏态保持自由旋转可再次转屏进全屏
    this.applyFullscreen(!this.fullscreen);
  }

  // 全屏落地：进入=锁定横向+沉浸式铺满（隐藏系统栏）；退出=恢复自由旋转+非全屏布局（显示状态栏）
  private applyFullscreen(fs: boolean): void {
    // 全屏切换驱动评论面板增删与视频区尺寸：布局过渡动画
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, (): void => {
      this.fullscreen = fs;
    });
    if (this.win !== undefined && canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
      // 竖屏悬停进全屏保持自由旋转（上半屏视频+下半屏控制），其余全屏锁定横向
      this.syncFullscreenOrientation();
      // 布局全屏跟随：全屏窗口延伸至系统栏下铺满；非全屏系统自动避让状态栏/摄像头区
      this.win.setWindowLayoutFullScreen(fs).catch((): void => {
      });
      this.win.setWindowSystemBarEnable(fs ? [] : ['status']).catch((): void => {
      });
    }
    // 全屏切换改变悬停分屏/折痕避让的生效条件，立即重估
    this.updateHoverLayout();
    this.pokeControls();
  }

  // 全屏方向同步：竖屏悬停分屏保持自由旋转（不强制横屏），其余全屏锁定横向；非全屏自由旋转
  private syncFullscreenOrientation(): void {
    if (this.win === undefined || this.pcLike ||
      !canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
      return;
    }
    if (this.fullscreen && !(this.hoverActive && !this.isWide)) {
      this.win.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE).catch((): void => {
      });
    } else {
      this.win.setPreferredOrientation(window.Orientation.AUTO_ROTATION).catch((): void => {
      });
    }
  }

  // PC/2in1 退出沉浸式全屏：进入前是悬浮窗则还原悬浮窗，否则回最大化（带标题栏）
  private exitPcFullscreen(): void {
    if (this.win === undefined) {
      return;
    }
    if (this.pcWasFloating) {
      this.win.recover().catch((): void => {
      });
    } else {
      this.win.maximize(window.MaximizePresentation.EXIT_IMMERSIVE).catch((): void => {
      });
    }
  }

  private pcWindowFloating(): boolean {
    if (this.win === undefined) {
      return true;
    }
    try {
      const st: window.WindowStatusType = this.win.getWindowStatus();
      return st !== window.WindowStatusType.MAXIMIZE && st !== window.WindowStatusType.FULL_SCREEN;
    } catch (_e) {
      return true;
    }
  }

  private clearUiTimers(): void {
    if (this.hideTimer >= 0) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
    if (this.tapTimer >= 0) {
      clearTimeout(this.tapTimer);
      this.tapTimer = -1;
    }
    if (this.seekToastTimer >= 0) {
      clearTimeout(this.seekToastTimer);
      this.seekToastTimer = -1;
    }
    if (this.boostTimer >= 0) {
      clearTimeout(this.boostTimer);
      this.boostTimer = -1;
    }
    if (this.suppressTimer >= 0) {
      clearTimeout(this.suppressTimer);
      this.suppressTimer = -1;
    }
    if (this.spaceTimer >= 0) {
      clearTimeout(this.spaceTimer);
      this.spaceTimer = -1;
    }
    if (this.volumeHudTimer >= 0) {
      clearTimeout(this.volumeHudTimer);
      this.volumeHudTimer = -1;
    }
    if (this.brightHudTimer >= 0) {
      clearTimeout(this.brightHudTimer);
      this.brightHudTimer = -1;
    }
    if (this.resumeTipTimer >= 0) {
      clearTimeout(this.resumeTipTimer);
      this.resumeTipTimer = -1;
    }
    this.spaceDown = false;
  }

  private async loadChapter(): Promise<void> {
    const gen: number = ++this.loadGen;
    this.loading = true;
    this.buffering = true;
    this.errorText = '';
    this.videos = [];
    this.playing = false;
    ReadingStatsRepo.flush();
    // 换章会重建播放器并重置 surface：打断手动小窗会话（小窗随旧会话关闭，回页续播走重新加载）
    VideoPipManager.getInstance().interrupt();
    this.releasePlayer();
    this.dmChapterId = -1;
    this.dmCtrl.reset();
    this.dmItems = [];
    this.resetComments();
    this.edSkipFired = false;
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      if (gen !== this.loadGen) {
        return;
      }
      const chapter = await ChapterRepo.getById(this.chapterId);
      if (gen !== this.loadGen) {
        return;
      }
      if (chapter === undefined) {
        Util.toastRes(this.getUIContext(), $r('app.string.reader_chapter_not_found'));
        this.pathStack.pop();
        return;
      }
      this.chapter = chapter;
      this.mangaId = chapter.mangaId;
      this.resumeMs = chapter.lastPageRead > 0 ? chapter.lastPageRead : 0;
      this.positionMs = this.resumeMs;
      this.savedMs = this.resumeMs;
      // 续播提示（参考华为视频）：跳过 30s 以上才提示可「从头播放」
      this.resumeTipArmed = this.resumeMs > 30000;
      const manga = await MangaRepo.get(chapter.mangaId);
      if (gen !== this.loadGen) {
        return;
      }
      if (manga !== undefined) {
        this.manga = manga;
      }
      // 按漫画加载跳过 OP/ED 区间（需 mangaId 已就绪）
      this.loadSkipRanges();
      this.localPath = DownloadService.localVideo(chapter.mangaId, chapter.id);
      // BT 章节未完整下载：localVideo 可能命中下载中的预分配稀疏文件，标记后走边下边播等待流
      this.btPending = DownloadService.isBtUrl(chapter.url) && !DownloadService.isDownloaded(chapter.id);
      this.btProgressive = false;
      // 外挂字幕：缓存优先 → 本地视频同名 .srt（需 localPath 已就绪）
      this.loadSubtitle();
      if (this.localPath === '' && !this.btPending) {
        const source = SourceRegistry.get(this.manga.sourceKey);
        if (source === undefined) {
          throw new Error('source_unavailable');
        }
        this.videos = await source.getVideoList(chapter.url);
        if (gen !== this.loadGen) {
          return;
        }
        if (this.videos.length === 0) {
          throw new Error('video_no_streams');
        }
      }
      this.qualityIndex = 0;
      await this.loadNeighbors(gen);
      if (gen !== this.loadGen) {
        return;
      }
      await HistoryRepo.upsert(chapter.mangaId, chapter.id, this.resumeMs);
      // 跨设备接续/碰一碰会话快照：随章节加载刷新（进度语义=播放位置毫秒）
      ContinueSession.update(ContentType.VIDEO, this.manga, chapter, this.resumeMs);
      if (gen !== this.loadGen) {
        return;
      }
      ReadingStatsRepo.begin(chapter.mangaId, chapter.id);
      this.loading = false;
      this.startCurrent();
      if (this.danmakuOn) {
        this.loadDanmaku();
      }
      // 剧集评论与弹幕并行加载（面板内展示加载/失败态，不阻塞播放）
      this.loadComments();
    } catch (e) {
      if (gen !== this.loadGen) {
        return;
      }
      const em = (e as Error).message;
      this.log(`loadChapter catch: ${em}`);
      this.errorText = (e as Error).message;
      this.buffering = false;
      Util.toastRes(this.getUIContext(), $r('app.string.reader_load_failed'),
        [Util.errText(this.getUIContext(), this.errorText)]);
      this.loading = false;
    }
  }

  private async loadNeighbors(gen: number): Promise<void> {
    const n: ChapterNeighbors = await ReaderChapterNav.neighbors(this.mangaId, this.chapterId);
    if (gen !== this.loadGen) {
      return;
    }
    this.chapters = n.chapters;
    this.prevId = n.prevId;
    this.nextId = n.nextId;
  }

  // 弹幕加载（dandanplay 匹配失败静默提示，不阻塞播放）
  private loadDanmaku(): void {
    if (this.dmLoading || this.dmChapterId === this.chapterId || this.manga.title === '') {
      return;
    }
    this.dmLoading = true;
    this.dmChapterId = this.chapterId;
    Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_loading'));
    DanmakuService.loadForChapter(this.manga, this.chapter).then((items: DanmakuItem[]) => {
      this.dmLoading = false;
      this.dmItems = items;
      this.dmCtrl.setItems(items);
      if (items.length > 0) {
        Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_loaded'), [items.length]);
      } else {
        Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_none'));
      }
    }).catch((): void => {
      this.dmLoading = false;
      Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_failed'));
    });
  }

  // ---- 剧集评论（Bangumi 吐槽箱）----

  // 重置评论状态：换章/离开页面时取消在途请求并清空列表
  private resetComments(): void {
    this.commentsGen += 1;
    this.comments = [];
    this.commentsState = 3;
    this.commentsErrNoEp = false;
    this.commentsEpId = 0;
    this.replyToId = 0;
    this.replyToName = '';
    this.commentInput = '';
    this.showReactPicker = false;
  }

  // 加载当前章节对应的 Bangumi 单集评论（无匹配剧集/网络失败展示对应占位态）；
  // force = 跳过缓存刷新（发评/回应成功后回刷，失败时静默保留旧列表）
  private loadComments(force: boolean = false): void {
    const gen: number = ++this.commentsGen;
    if (!force) {
      this.comments = [];
      this.commentsState = 0;
      this.commentsErrNoEp = false;
    }
    // 解析当前集 ep id（发评目标；内存缓存，重复调用无额外网络开销）
    EpisodeCommentService.resolveEpisodeId(this.manga, this.chapter).then((epId: number): void => {
      if (gen === this.commentsGen && !this.destroyed) {
        this.commentsEpId = epId;
      }
    }).catch((): void => {
    });
    EpisodeCommentService.loadForChapter(this.manga, this.chapter, force)
      .then((items: EpisodeComment[]) => {
        if (gen !== this.commentsGen || this.destroyed) {
          return;
        }
        this.comments = items;
        this.commentsState = 1;
        // 评论加载成功后挂载隐藏 Turnstile Web（发评人机验证载体，延迟到实际需要时）
        if (this.bgmLoggedIn) {
          this.tsWebMounted = true;
        }
      }).catch((e: Error) => {
        if (gen !== this.commentsGen || this.destroyed) {
          return;
        }
        if (force && this.comments.length > 0) {
          // 刷新失败静默保留旧列表
          this.commentsState = 1;
        } else {
          this.commentsState = 2;
          this.commentsErrNoEp = e.message === 'comments_no_episode';
        }
        this.log(`loadComments failed: ${e.message}`);
      });
  }

  // 评论写操作统一错误提示（发评/回应共用）
  private commentWriteError(e: Error): void {
    const msg: string = e.message;
    if (msg === 'comments_unauthorized') {
      this.bgmLoggedIn = false;
      Util.toastRes(this.getUIContext(), $r('app.string.video_comments_relogin'));
    } else if (msg === 'comments_rate_limited') {
      Util.toastRes(this.getUIContext(), $r('app.string.video_comments_rate_limited'));
    } else if (msg === 'turnstile_failed') {
      Util.toastRes(this.getUIContext(), $r('app.string.video_comments_ts_failed'));
    } else {
      Util.toastRes(this.getUIContext(), $r('app.string.video_comments_send_failed'));
    }
    this.log(`comment write failed: ${msg}`);
  }

  // 进入回复模式（主评/楼中楼共用；isSubReply = 点击楼中楼内回复，输入框预填 @昵称）
  private startReply(replyToId: number, nickname: string, isSubReply: boolean): void {
    this.replyToId = replyToId;
    this.replyToName = nickname;
    if (isSubReply && this.commentInput.trim() === '') {
      this.commentInput = `@${nickname} `;
    }
  }

  private cancelReply(): void {
    this.replyToId = 0;
    this.replyToName = '';
  }

  // 发送评论/楼中楼回复：Turnstile token → POST → 成功清输入并强制刷新列表
  private sendComment(): void {
    const content: string = this.commentInput.trim();
    if (content === '' || this.commentSending) {
      return;
    }
    if (!this.bgmLoggedIn) {
      this.openBgmLogin();
      return;
    }
    if (this.commentsEpId <= 0) {
      Util.toastRes(this.getUIContext(), $r('app.string.video_comments_no_episode'));
      return;
    }
    this.commentSending = true;
    this.ensureTurnstileToken().then((token: string): Promise<number> => {
      this.tsToken = '';
      return EpisodeCommentService.postComment(this.commentsEpId, content, this.replyToId, token);
    }).then((): void => {
      this.commentSending = false;
      this.commentInput = '';
      this.replyToId = 0;
      this.replyToName = '';
      Util.toastRes(this.getUIContext(), $r('app.string.video_comments_sent'));
      this.loadComments(true);
    }).catch((e: Error) => {
      this.commentSending = false;
      this.commentWriteError(e);
    });
  }

  // 表情回应切换：current = 该评论当前已选值（0 未选）；选中值相同 = 取消
  private toggleReaction(commentId: number, value: number, current: number): void {
    if (!this.bgmLoggedIn) {
      this.openBgmLogin();
      return;
    }
    const call: Promise<void> = current === value ?
      EpisodeCommentService.unreact(commentId) :
      EpisodeCommentService.react(commentId, value);
    call.then((): void => {
      this.loadComments(true);
    }).catch((e: Error) => {
      this.commentWriteError(e);
    });
  }

  // 打开表情回应选择器（12 个合法反应值）
  private openReactPicker(commentId: number, current: number): void {
    this.reactPickerId = commentId;
    this.reactPickerCurrent = current;
    this.showReactPicker = true;
  }

  // 选择器选中值：与当前值相同 = 取消回应，否则切换
  private onReactPickerValue(value: number): void {
    this.showReactPicker = false;
    const id: number = this.reactPickerId;
    const current: number = this.reactPickerCurrent;
    this.reactPickerId = 0;
    if (id > 0) {
      this.toggleReaction(id, value, current);
    }
  }

  // ---- Bangumi 登录（评论发言/回应前置；OAuth token 复用为 /p1 Bearer）----

  private openBgmLogin(): void {
    if (this.showBgmLogin) {
      return;
    }
    TrackerManager.bangumi.getAuthUrl().then((url: string): void => {
      this.bgmLoginUrl = url;
      this.showBgmLogin = true;
    }).catch((): void => {
      Util.toastRes(this.getUIContext(), $r('app.string.track_login_failed'));
    });
  }

  @Builder
  bgmLoginBuilder() {
    OAuthSheet({
      authUrl: this.bgmLoginUrl,
      sheetTitle: 'Bangumi',
      onOAuthResult: (params: Record<string, string>): void => {
        this.onBgmAuthResult(params);
      },
      onClose: (): void => {
        this.showBgmLogin = false;
      },
    })
  }

  private onBgmAuthResult(params: Record<string, string>): void {
    this.showBgmLogin = false;
    const code: string = params['code'] ?? '';
    if (code === '') {
      return;
    }
    TrackerManager.bangumi.loginWithCode(code).then((): void => {
      this.bgmLoggedIn = true;
      EpisodeCommentService.resetMyUser();
      Util.toastRes(this.getUIContext(), $r('app.string.track_logged_in'), ['Bangumi']);
      this.loadComments(true);
    }).catch((): void => {
      TrackerManager.bangumi.logout();
      Util.toastRes(this.getUIContext(), $r('app.string.track_login_failed'));
    });
  }

  // ---- Turnstile token（发评人机验证）----

  // 隐藏 Web 加载 next.bgm.tv 完成后注入 invisible Turnstile 组件（幂等）
  private injectTurnstile(): void {
    if (this.tsInjected) {
      return;
    }
    this.tsInjected = true;
    const js: string = `(function(){` +
      `if(window.__hyTsLoaded){return;}` +
      `window.__hyTsLoaded=true;` +
      `var d=document.createElement('div');d.id='hy-ts';document.body.appendChild(d);` +
      `var s=document.createElement('script');` +
      `s.src='https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';` +
      `s.onload=function(){` +
      `turnstile.render('#hy-ts',{sitekey:'${TS_SITEKEY}',size:'invisible',` +
      `'error-callback':function(){window.__hyTsToken='';},` +
      `'expired-callback':function(){window.__hyTsToken='';},` +
      `'callback':function(t){window.__hyTsToken=t;}});};` +
      `document.head.appendChild(s);` +
      `})();`;
    this.tsController.runJavaScript(js).catch((): void => {
      this.tsInjected = false;
    });
  }

  // 获取有效 token：缓存未过期直接用，否则轮询注入组件产出的 token（约 15s 超时）
  private async ensureTurnstileToken(): Promise<string> {
    if (this.tsToken !== '' && Date.now() - this.tsTokenAt < TS_TOKEN_VALID_MS) {
      return this.tsToken;
    }
    this.tsToken = '';
    if (this.destroyed) {
      throw new Error('turnstile_failed');
    }
    for (let i = 0; i < 30; i++) {
      let raw: string = '';
      try {
        raw = await this.tsController.runJavaScript(
          'window.__hyTsToken ? window.__hyTsToken : ""');
      } catch (_e) {
        // Web 未就绪/已销毁：继续轮询
      }
      const token: string = this.parseRunJsString(raw);
      if (token !== '') {
        this.tsToken = token;
        this.tsTokenAt = Date.now();
        return token;
      }
      // 页面已加载但组件未注入时补注（onPageEnd 未触发的兜底）
      if (i === 5) {
        this.injectTurnstile();
      }
      await new Promise<void>((resolve: (v: void) => void) => {
        setTimeout(resolve, 500);
      });
      if (this.destroyed) {
        break;
      }
    }
    throw new Error('turnstile_failed');
  }

  // runJavaScript 返回值规整：结果为 JSON 字符串（带引号），剥壳取原文；
  // token 仅含 base64url 字符，无转义序列，手工剥引号即可
  private parseRunJsString(raw: string): string {
    if (raw === '' || raw === '""') {
      return '';
    }
    let s: string = raw;
    if (s.length >= 2 && s.charAt(0) === '"' && s.charAt(s.length - 1) === '"') {
      s = s.substring(1, s.length - 1);
    }
    return s.replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  }

  private startCurrent(): void {
    if (this.surfaceId === '') {
      return;
    }
    // 投屏中：本机不播放，改为向远端下发当前资源
    if (this.casting) {
      this.startCastPlayback();
      return;
    }
    // BT 章节未完整下载：进入等待流（引擎选择/入队/轮询头部就绪起播）
    if (this.btPending) {
      this.runBtFlow();
      return;
    }
    if (this.localPath !== '') {
      this.playFile(this.localPath);
      return;
    }
    if (this.qualityIndex < 0 || this.qualityIndex >= this.videos.length) {
      return;
    }
    const video = this.videos[this.qualityIndex];
    if (video.url.indexOf('file://') === 0) {
      this.playFile(video.url.substring('file://'.length));
      return;
    }
    // BT 流（magnet/.torrent）不支持在线播放：需先下载完成再播本地文件
    if (DownloadService.isBtUrl(video.url)) {
      this.errorText = 'bt_download_first';
      this.buffering = false;
      return;
    }
    this.playRemote(video);
  }

  // ===== BT 边下边播等待流 =====
  // 章节为 magnet/.torrent 且未完整下载：无任务时先走引擎选择/入队，
  // 之后轮询目标文件头部数据就绪即限长起播；到数据边界后等待扩展续播

  private runBtFlow(): void {
    const gen: number = this.loadGen;
    this.runBtFlowAsync(gen).catch((e: Error) => {
      if (gen !== this.loadGen || this.destroyed) {
        return;
      }
      this.log(`runBtFlow catch: ${e.message}`);
      this.errorText = 'bt_download_first';
      this.buffering = false;
    });
  }

  private async runBtFlowAsync(gen: number): Promise<void> {
    this.buffering = false;
    const st = DownloadService.taskStateOf(this.chapterId);
    if (st !== 0 && st !== 1) {
      // 无排队/下载中任务：询问引擎选择（已决直接短路）
      const choice = await BtFlow.acquireEngineChoice(this.getUIContext());
      if (gen !== this.loadGen || this.destroyed) {
        return;
      }
      if (choice === 'cancel') {
        this.pathStack.pop();
        return;
      }
      if (choice === 'system') {
        await BtFlow.handOffToSystem(this.getUIContext(), this.chapter.url);
        if (gen !== this.loadGen || this.destroyed) {
          return;
        }
        this.pathStack.pop();
        return;
      }
      // 用户明确选择内置引擎：解除安装引导抑制（此前"暂不"仅抑制自动弹窗）
      AppStorage.setOrCreate(AppKeys.BT_ASK_DISMISSED, false);
      DownloadService.enqueueRecord(this.manga, this.chapter);
      if (!Settings.getBtProgressive()) {
        this.errorText = 'bt_download_first';
        Util.toastRes(this.getUIContext(), $r('app.string.detail_download_queued'));
        return;
      }
    } else if (!Settings.getBtProgressive()) {
      // 任务已在下载但用户关闭边下边播：提示先下载完成
      this.errorText = 'bt_download_first';
      return;
    }
    await this.waitBtHeadAndPlay(gen);
  }

  // 轮询等待目标文件头部就绪（顺序下载下 done 即连续头部）：门槛 min(8MB, 5%)
  private async waitBtHeadAndPlay(gen: number): Promise<void> {
    this.errorText = 'bt_progressive_waiting';
    const deadline: number = Date.now() + 15 * 60 * 1000;
    while (Date.now() < deadline) {
      if (gen !== this.loadGen || this.destroyed) {
        return;
      }
      if (DownloadService.isDownloaded(this.chapterId)) {
        this.beginBtFullPlay();
        return;
      }
      const st = DownloadService.taskStateOf(this.chapterId);
      if (st === -1) {
        // 任务消失且未完成：被取消/删除
        this.errorText = 'bt_download_first';
        this.buffering = false;
        return;
      }
      if (st === 3) {
        const err = DownloadService.failedErrorOf(this.chapterId);
        if (err !== '' && err !== 'bt_component_required' && err !== 'download_cancelled') {
          this.errorText = err;
          this.buffering = false;
          return;
        }
        // 组件缺失：Index 安装引导 → retryBtComponentTasks 自动恢复，继续等待
      }
      const head: BtHeadInfo | undefined = await this.btHeadInfo();
      if (gen !== this.loadGen || this.destroyed) {
        return;
      }
      if (head !== undefined && head.done >= head.minHead) {
        this.localPath = DownloadService.localVideo(this.mangaId, this.chapterId);
        if (this.localPath !== '') {
          this.errorText = '';
          this.startBtPlay(head.done, head.size);
          return;
        }
      }
      await BtFlow.sleep(1000);
    }
    this.errorText = 'bt_download_first';
    this.buffering = false;
  }

  // 目标视频文件（种子内最大视频容器）下载快照；引擎未启动/无元数据返回 undefined
  private async btHeadInfo(): Promise<BtHeadInfo | undefined> {
    const key = DownloadService.btKeyOf(this.chapterId);
    if (key < 0) {
      return undefined;
    }
    try {
      const files: TorrentFileJson[] = await BtModule.files(key);
      let target: TorrentFileJson | undefined = undefined;
      for (const f of files) {
        if (DownloadService.isVideoName(f.path) && (target === undefined || f.size > target.size)) {
          target = f;
        }
      }
      if (target === undefined || target.size <= 0) {
        return undefined;
      }
      const info: BtHeadInfo = {
        done: target.done,
        size: target.size,
        minHead: Math.min(8 * 1024 * 1024, Math.floor(target.size * 0.05))
      };
      return info;
    } catch (_e) {
      return undefined;
    }
  }

  // 限长起播：fdSrc 截至已下载头部（顺序下载下数据连续）
  private startBtPlay(safeLen: number, realSize: number): void {
    this.log(`startBtPlay: safeLen=${safeLen}, size=${realSize}`);
    this.btProgressive = true;
    this.btStatSize = realSize;
    this.btSafeLen = Math.min(safeLen, realSize);
    this.btFileDone = this.btSafeLen;
    this.buffering = true;
    this.playFile(this.localPath, this.btSafeLen);
  }

  // 数据边界（completed/error 且 safeLen < 真实大小）：等待新增数据后重开续播
  private onBtBoundary(): void {
    const pos: number = this.positionMs;
    this.log(`bt boundary at ${pos}ms, safeLen=${this.btSafeLen}/${this.btStatSize}`);
    this.buffering = true;
    const gen: number = this.loadGen;
    this.extendBtWait(gen, pos).catch((): void => {
    });
  }

  private async extendBtWait(gen: number, pos: number): Promise<void> {
    const deadline: number = Date.now() + 15 * 60 * 1000;
    // 每次扩展至少等待 8MB 增量（约数秒视频），减少播放器重开次数
    const target: number = Math.min(this.btStatSize, this.btSafeLen + 8 * 1024 * 1024);
    while (Date.now() < deadline) {
      if (gen !== this.loadGen || this.destroyed || !this.btProgressive) {
        return;
      }
      if (DownloadService.isDownloaded(this.chapterId)) {
        this.btProgressive = false;
        this.resumeMs = pos;
        this.playFile(this.localPath);
        return;
      }
      const head: BtHeadInfo | undefined = await this.btHeadInfo();
      if (gen !== this.loadGen || this.destroyed || !this.btProgressive) {
        return;
      }
      if (head !== undefined && head.done >= target) {
        this.btFileDone = head.done;
        this.btSafeLen = Math.min(head.done, this.btStatSize);
        this.resumeMs = pos;
        this.playFile(this.localPath, this.btSafeLen);
        return;
      }
      await BtFlow.sleep(1000);
    }
    this.btProgressive = false;
    this.errorText = 'bt_download_first';
    this.buffering = false;
  }

  // 等待期间下载完成：转完整文件正常播放
  private beginBtFullPlay(): void {
    this.log('bt download completed during wait, full play');
    this.btPending = false;
    this.btProgressive = false;
    this.localPath = DownloadService.localVideo(this.mangaId, this.chapterId);
    this.errorText = '';
    this.startCurrent();
  }

  // limitLen >= 0 时 fdSrc 限制在已下载字节数（BT 边下边播：稀疏文件尾部为零洞，
  // 播放器读到未下载数据会产生解码错误），否则按文件实际大小
  private playFile(path: string, limitLen: number = -1): void {
    this.log(`playFile: ${path}, limitLen: ${limitLen}`);
    this.playGen += 1;
    const gen = this.playGen;
    this.releasePlayer();
    // @SuppressWarnings syscap
    media.createAVPlayer().then(async (player: media.AVPlayer): Promise<void> => {
      if (gen !== this.playGen) {
        player.release();
        return;
      }
      this.bindPlayer(player);
      const file: fs.File = await fs.open(path, fs.OpenMode.READ_ONLY);
      const stat: fs.Stat = await fs.stat(path);
      if (gen !== this.playGen) {
        try {
          fs.closeSync(file);
        } catch (_e) {
          // 已关闭
        }
        return;
      }
      this.mediaFile = file;
      const length: number = limitLen >= 0 ? Math.min(limitLen, stat.size) : stat.size;
      const fdSrc: media.AVFileDescriptor = { fd: file.fd, offset: 0, length: length };
      player.fdSrc = fdSrc;
    }).catch((e: Error) => {
      if (gen !== this.playGen) {
        return;
      }
      this.log(`playFile createAVPlayer catch: ${e.message}`);
      this.errorText = e.message;
      this.buffering = false;
    });
  }

  // m3u8 或代理失败时回退直连播放
  private async playRemote(video: SVideo): Promise<void> {
    this.log(`playRemote: ${video.url}`);
    this.playGen += 1;
    const gen = this.playGen;
    this.releasePlayer();
    let playUrl: string = video.url;
    let viaProxy: boolean = false;
    let hlsRewritten: boolean = false;
    // m3u8：拉取播放列表 → 过滤广告分片 → 本地服务改写播放；失败静默回退直连
    if (video.url.indexOf('.m3u8') >= 0 && this.hlsRewriteFailedUrl !== video.url) {
      const localUrl: string = await this.tryRewriteHls(video);
      if (gen !== this.playGen) {
        return;
      }
      if (localUrl !== '') {
        playUrl = localUrl;
        hlsRewritten = true;
        this.hlsRewriteActive = true;
        this.hlsRewriteVideo = video;
      }
    }
    if (!hlsRewritten && VideoCacheServer.isProxyEligible(video.url)) {
      try {
        playUrl = await VideoCacheServer.getProxyUrl(
          Util.hostAbilityContext(this.getUIContext()), video.url, video.headers);
        viaProxy = playUrl !== video.url;
      } catch (e) {
        this.log(`getProxyUrl catch: ${e}`);
      }
    }
    if (gen !== this.playGen) {
      return;
    }
    if (viaProxy && playUrl.indexOf('http') !== 0) {
      // 已完整缓存：直接按本地文件播放
      this.cachePercent = 100;
      this.playFile(playUrl);
      return;
    }
    if (viaProxy) {
      this.attachCacheListener(video.url);
    }
    // @SuppressWarnings syscap
    media.createAVPlayer().then((player: media.AVPlayer) => {
      if (gen !== this.playGen) {
        player.release();
        return;
      }
      this.bindPlayer(player);
      // 本地代理地址无需透传源站请求头（由 HeaderInjector 注入），直连时保留原逻辑
      const headers = viaProxy ? undefined : Http.headersFor(video.url, video.headers);
      // @SuppressWarnings syscap
      const source = media.createMediaSourceWithUrl(playUrl, headers);
      const strategy: media.PlaybackStrategy = { preferredWidth: 0, preferredHeight: 0 };
      player.setMediaSource(source, strategy);
    }).catch((e: Error) => {
      this.log(`playRemote createAVPlayer catch: ${e.message}`);
      this.errorText = e.message;
      this.buffering = false;
    });
  }

  // 拉取 m3u8 播放列表 → 过滤广告分片重组 → 注册本地服务，返回可播放的本地地址；
  // 任何一步失败（网络/解析/无可剔除内容/不支持加密形态）返回空串，调用方回退直连
  private async tryRewriteHls(video: SVideo): Promise<string> {
    try {
      const headers: Record<string, string> = Http.headersFor(video.url, video.headers);
      const text: string = await Http.get(video.url, headers);
      const rewritten: string = HlsDownloader.buildAdFreePlaylistText(text, video.url);
      if (rewritten === '') {
        this.log('hls rewrite: nothing removed or unsupported, direct play');
        return '';
      }
      const localUrl: string = await M3u8ProxyServer.serve(rewritten);
      this.log(`hls rewrite: serving ${localUrl} (${rewritten.length} chars)`);
      return localUrl;
    } catch (e) {
      this.log(`hls rewrite catch: ${e}`);
      return '';
    }
  }

  // 改写后的 m3u8 播放失败：自动回退原始地址直连一次（同一地址仅回退一次防循环）
  private fallbackFromRewrite(): boolean {
    const video: SVideo | undefined = this.hlsRewriteVideo;
    this.hlsRewriteActive = false;
    this.hlsRewriteVideo = undefined;
    if (video === undefined) {
      return false;
    }
    this.log(`rewritten hls playback failed, fallback to direct: ${video.url}`);
    this.hlsRewriteFailedUrl = video.url;
    this.errorText = '';
    this.buffering = true;
    this.playRemote(video);
    return true;
  }

  // 注册当前直链的缓存进度监听（进度的百分比用于进度条缓存区显示）
  private attachCacheListener(url: string): void {
    this.detachCacheListener();
    this.cachePercent = 0;
    this.cacheUrl = url;
    const listener = new VpCacheListener((pct: number): void => {
      this.cachePercent = pct;
    });
    this.cacheListener = listener;
    VideoCacheServer.registerCacheListener(listener, url);
  }

  private detachCacheListener(): void {
    const listener = this.cacheListener;
    if (listener !== undefined && this.cacheUrl !== '') {
      VideoCacheServer.unregisterCacheListener(listener, this.cacheUrl);
    }
    this.cacheListener = undefined;
    this.cacheUrl = '';
    this.cachePercent = 0;
  }

  private bindPlayer(player: media.AVPlayer): void {
    this.log(`bindPlayer`);
    this.player = player;
    this.buffering = true;
    player.on('stateChange', (state: media.AVPlayerState) => {
      this.log(`stateChange: ${state}`);
      if (state === 'initialized') {
        // surfaceId 仅支持在 initialized 状态设置，须在 prepare() 之前完成；
        // 自动小窗期间重建播放器时渲染目标须落在小窗 surface
        player.surfaceId = VideoPipManager.getInstance().resolveSurface(this.surfaceId);
        player.prepare();
      } else if (state === 'prepared') {
        this.hlsRewriteFailedUrl = '';
        this.durationMs = player.duration > 0 ? player.duration : 0;
        this.videoW = player.width > 0 ? player.width : 0;
        this.videoH = player.height > 0 ? player.height : 0;
        this.adjustSurface();
        this.preparePip();
        if (this.resumeMs > 0 && (this.durationMs === 0 ||
          this.resumeMs < this.durationMs - VIDEO_RESUME_TAIL_MS)) {
          // @SuppressWarnings syscap
          player.seek(this.resumeMs, media.SeekMode.SEEK_PREV_SYNC);
          if (this.resumeTipArmed) {
            this.resumeTipArmed = false;
            this.showResumeTipAt(this.resumeMs);
          }
        }
        // 恢复上次软件音量（prepared 状态起 setVolume 可用）
        try {
          player.setVolume(this.muted ? 0 : this.volume);
        } catch (e) {
          this.log(`prepared setVolume catch: ${e}`);
        }
        player.play();
        player.setSpeed(this.speedToEnum(this.speed));
        this.playing = true;
        this.startTicker();
      } else if (state === 'playing') {
        this.playing = true;
        this.buffering = false;
        this.armAutoHide();
        this.setPipAutoStart(true);
      } else if (state === 'paused' || state === 'stopped') {
        this.playing = false;
        this.buffering = false;
        this.setPipAutoStart(false);
      } else if (state === 'completed') {
        // BT 边下边播：completed 可能是 fdSrc 截断处的数据边界而非真实片尾
        if (this.btProgressive && this.btSafeLen < this.btStatSize) {
          this.onBtBoundary();
          return;
        }
        this.playing = false;
        this.buffering = false;
        this.setPipAutoStart(false);
        this.persist(true);
        if (this.autoNext && this.nextId > 0) {
          this.openChapter(this.nextId);
        } else {
          this.showControls = true;
        }
      } else if (state === 'error') {
        this.log(`stateChange error, native state: ${player.state}`);
        // BT 边下边播：截断容器的解码错误优先按数据边界处理
        if (this.btProgressive && this.btSafeLen < this.btStatSize) {
          this.onBtBoundary();
          return;
        }
        // 改写后的 m3u8 播放失败：优先自动回退原始地址直连
        if (this.fallbackFromRewrite()) {
          return;
        }
        this.playing = false;
        this.buffering = false;
        this.errorText = 'play_failed';
      }
    });
    player.on('seekDone', () => {
      this.buffering = false;
    });
    // 播放中途网络卡顿进入/退出缓冲：置位 buffering 驱动界面 loading（控制条可见时由中央按钮转圈展示）
    player.on('bufferingUpdate', (infoType: media.BufferingInfoType, _value: number) => {
      if (infoType === media.BufferingInfoType.BUFFERING_START) {
        this.buffering = true;
      } else if (infoType === media.BufferingInfoType.BUFFERING_END) {
        this.buffering = false;
      }
    });
    player.on('error', (_err: Error) => {
      this.log(`player error cb: ${_err.message}, native state: ${player.state}`);
      if (player.state !== 'error') {
        this.log('non-fatal error ignored');
        return;
      }
      // 改写后的 m3u8 播放失败：优先自动回退原始地址直连
      if (this.fallbackFromRewrite()) {
        return;
      }
      this.errorText = 'play_failed';
      this.playing = false;
      this.buffering = false;
    });
  }

  private startTicker(): void {
    this.stopTicker();
    this.ticker = setInterval(() => {
      const player = this.player;
      if (player === undefined || this.dragging) {
        return;
      }
      // 投屏中进度来自远端 playbackStateChange 回调，跳过本机轮询
      if (this.casting) {
        return;
      }
      if (player.currentTime >= 0) {
        this.positionMs = player.currentTime;
      }
      if (player.duration > 0) {
        this.durationMs = player.duration;
      }
      // 自动跳过 OP/ED（区间命中时秒跳）与字幕行刷新
      this.applyAutoSkip();
      this.updateSubtitle();
      if (Math.abs(this.positionMs - this.savedMs) >= 5000) {
        this.persist(false);
      }
      ReadingStatsRepo.tick();
    }, 500);
  }

  private stopTicker(): void {
    if (this.ticker >= 0) {
      clearInterval(this.ticker);
      this.ticker = -1;
    }
  }

  // Surface 显示区域按画面显示模式计算：0=适应（等比缩放居中）1=填充（等比放大裁剪铺满）2=拉伸（无视宽高比铺满）；SurfaceRect 单位为 px
  private adjustSurface(): void {
    if (this.videoW <= 0 || this.videoH <= 0 || this.areaW <= 0 || this.areaH <= 0) {
      return;
    }
    let w = 0;
    let h = 0;
    if (this.scaleMode === 2) {
      // 拉伸：忽略视频宽高比，直接铺满显示区域
      w = this.areaW;
      h = this.areaH;
    } else {
      const scale = this.scaleMode === 1
        ? Math.max(this.areaW / this.videoW, this.areaH / this.videoH)
        : Math.min(this.areaW / this.videoW, this.areaH / this.videoH);
      w = Math.floor(this.videoW * scale);
      h = Math.floor(this.videoH * scale);
    }
    if (w > 8192) {
      w = 8192;
    }
    if (h > 8192) {
      h = 8192;
    }
    if (w <= 0 || h <= 0) {
      return;
    }
    this.xCtrl.setXComponentSurfaceRect({ surfaceWidth: w, surfaceHeight: h });
  }

  private releasePlayer(): void {
    const player = this.player;
    this.log(`releasePlayer, hadPlayer=${player !== undefined}`);
    this.player = undefined;
    this.playing = false;
    this.hlsRewriteActive = false;
    this.hlsRewriteVideo = undefined;
    this.detachCacheListener();
    if (player !== undefined) {
      try {
        player.release();
      } catch (e) {
        this.log(`releasePlayer catch: ${e}`);
      }
    }
    if (this.mediaFile !== undefined) {
      try {
        fs.closeSync(this.mediaFile);
      } catch (e) {
        // 已关闭
      }
      this.mediaFile = undefined;
    }
  }

  // ---- 控制条显隐 ----
  private pokeControls(): void {
    this.showControls = true;
    this.armAutoHide();
  }

  private armAutoHide(): void {
    if (this.hideTimer >= 0) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
    // 弹幕输入框聚焦时控制条常驻，失焦后再恢复自动隐藏；全屏悬停分屏时下半屏控制条常驻
    if (this.playing && !this.dmInputFocused && !this.hoverSplitOn()) {
      this.hideTimer = setTimeout(() => {
        this.hideTimer = -1;
        this.showControls = false;
      }, 4000);
    }
  }

  private toggleControls(): void {
    if (this.showControls) {
      if (this.hideTimer >= 0) {
        clearTimeout(this.hideTimer);
        this.hideTimer = -1;
      }
      this.showControls = false;
    } else {
      this.pokeControls();
    }
  }

  // 侧区单击：延迟执行以等待可能的第二次点击（双击快进/快退）
  private scheduleTap(): void {
    if (this.boosting || this.suppressClick) {
      return;
    }
    if (this.locked) {
      this.pokeControls();
      return;
    }
    if (this.tapTimer >= 0) {
      return;
    }
    this.tapTimer = setTimeout(() => {
      this.tapTimer = -1;
      this.toggleControls();
    }, 260);
  }

  private onDoubleTap(side: number): void {
    if (this.boosting || this.suppressClick) {
      return;
    }
    if (this.tapTimer >= 0) {
      clearTimeout(this.tapTimer);
      this.tapTimer = -1;
    }
    if (this.locked) {
      this.pokeControls();
      return;
    }
    Haptics.soft();
    this.seekBy(side * 10000);
  }

  // 相对位移寻址：toast 显示实际位移秒数（方向键 ±10s，PgUp/PgDn ±60s）
  private seekBy(deltaMs: number): void {
    let target = this.positionMs + deltaMs;
    if (target < 0) {
      target = 0;
    }
    if (this.durationMs > 0 && target > this.durationMs) {
      target = this.durationMs;
    }
    this.seekTo(target);
    this.seekToast = deltaMs / 1000;
    if (this.seekToastTimer >= 0) {
      clearTimeout(this.seekToastTimer);
    }
    this.seekToastTimer = setTimeout(() => {
      this.seekToastTimer = -1;
      this.seekToast = 0;
    }, 600);
  }

  // 数字键 0-9：按总时长 0%-90% 跳转
  private seekToPercent(tenth: number): void {
    if (this.durationMs <= 0) {
      return;
    }
    this.seekTo(Math.floor(this.durationMs * tenth / 10));
    this.pokeControls();
  }

  // ---- 长按快进（按住 ~0.5s 进入倍速快进，可左右滑动换档，松开恢复原速） ----
  private boostTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      if (event.touches.length > 0) {
        // TouchObject.windowX 单位是 vp，转 px 后统一计算
        this.boostDownX = this.getUIContext().vp2px(event.touches[0].windowX);
      }
      this.armBoost();
    } else if (event.type === TouchType.Move) {
      if (this.boosting && event.touches.length > 0) {
        this.boostSlide(this.getUIContext().vp2px(event.touches[0].windowX));
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.disarmBoost();
    }
  }

  private armBoost(): void {
    if (this.boostTimer >= 0) {
      clearTimeout(this.boostTimer);
      this.boostTimer = -1;
    }
    if (this.locked || this.casting || !this.playing || this.speed >= 3.0) {
      return;
    }
    this.boostTimer = setTimeout(() => {
      this.boostTimer = -1;
      this.startBoost();
    }, 500);
  }

  private disarmBoost(): void {
    if (this.boostTimer >= 0) {
      clearTimeout(this.boostTimer);
      this.boostTimer = -1;
    }
    if (this.boosting) {
      this.endBoost();
      this.suppressClick = true;
      if (this.suppressTimer >= 0) {
        clearTimeout(this.suppressTimer);
      }
      this.suppressTimer = setTimeout(() => {
        this.suppressTimer = -1;
        this.suppressClick = false;
      }, 400);
    }
  }

  private startBoost(): void {
    const player = this.player;
    if (player === undefined) {
      return;
    }
    this.boostSpeedIndex = 2;
    this.boostAnchorX = this.boostDownX;
    this.log(`boost start ${BOOST_SPEEDS[this.boostSpeedIndex]}x pos=${this.positionMs}`);
    Haptics.medium();
    player.setSpeed(this.boostSpeedToEnum(this.boostSpeedIndex));
    this.boosting = true;
  }

  // 长按期间滑动换档：以按下点为基准，相对每滑过一个步长升降一档（右增左减）
  private boostSlide(x: number): void {
    if (this.areaW <= 0) {
      return;
    }
    const step = Math.max(this.areaW / 8, 80);
    let idx = this.boostSpeedIndex;
    if (x - this.boostAnchorX >= step && this.boostSpeedIndex < BOOST_SPEEDS.length - 1) {
      idx = this.boostSpeedIndex + 1;
    } else if (this.boostAnchorX - x >= step && this.boostSpeedIndex > 0) {
      idx = this.boostSpeedIndex - 1;
    }
    if (idx !== this.boostSpeedIndex) {
      this.boostAnchorX = x;
      this.boostSpeedIndex = idx;
      Haptics.soft();
      const player = this.player;
      if (player !== undefined) {
        this.log(`boost speed ${BOOST_SPEEDS[idx]}x`);
        player.setSpeed(this.boostSpeedToEnum(idx));
      }
    }
  }

  private boostSpeedToEnum(i: number): media.PlaybackSpeed {
    const s = BOOST_SPEEDS[i];
    if (s === 1.5) {
      // @SuppressWarnings syscap
      return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    }
    if (s === 2.0) {
      // @SuppressWarnings syscap
      return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
    }
    if (s === 3.0) {
      // @SuppressWarnings syscap
      return media.PlaybackSpeed.SPEED_FORWARD_3_00_X;
    }
    // @SuppressWarnings syscap
    return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
  }

  private boostLabel(i: number): string {
    const s = BOOST_SPEEDS[i];
    return s === 1.0 ? '1x' : `${s}x`;
  }

  private endBoost(): void {
    this.boosting = false;
    const player = this.player;
    if (player !== undefined) {
      this.log(`boost end pos=${this.positionMs}`);
      player.setSpeed(this.speedToEnum(this.speed));
    }
  }

  private togglePlay(): void {
    if (this.casting) {
      this.castMgr.sendPlay(!this.playing);
      return;
    }
    const player = this.player;
    if (player === undefined) {
      this.startCurrent();
      return;
    }
    if (this.playing) {
      try {
        player.pause();
      } catch (e) {
        this.log(`togglePlay pause catch: ${e}`);
        return;
      }
      this.persist(false);
    } else {
      try {
        player.play();
      } catch (e) {
        this.log(`togglePlay play catch: ${e}`);
        return;
      }
      this.armAutoHide();
    }
    this.armAutoHide();
  }

  // ---- 键盘控制（外接键盘/PC）----
  // 空格：短按播放/暂停，长按 ~0.5s 进入倍速快进（复用长按快进档位，松开恢复）
  // ↑↓：软件音量 ±10%；M：静音；←→：±10s；PgUp/PgDn：±60s
  // Home/End：跳首/跳尾；0-9：按总时长百分比跳转；F：全屏；D：弹幕
  // 回车：切换控制条；Escape：关闭弹层/退出全屏/退出页面
  private handlePlayerKey(event: KeyEvent): void {
    if (event.type === KeyType.Up) {
      if (event.keyCode === KeyCode.KEYCODE_SPACE) {
        this.onSpaceKeyRelease();
      }
      return;
    }
    if (event.type !== KeyType.Down) {
      return;
    }
    const code = event.keyCode;
    if (code === KeyCode.KEYCODE_ESCAPE) {
      if (this.showSheet) {
        this.showSheet = false;
      } else if (this.fullscreen) {
        this.toggleFullscreen();
      } else {
        this.pathStack.pop();
      }
      return;
    }
    // 弹层打开时交给弹层交互，锁定时仅唤起控制条
    if (this.showSheet) {
      return;
    }
    if (this.locked) {
      this.pokeControls();
      return;
    }
    if (code === KeyCode.KEYCODE_SPACE) {
      this.onSpaceKeyPress();
      return;
    }
    if (code === KeyCode.KEYCODE_ENTER) {
      this.toggleControls();
      return;
    }
    if (code === KeyCode.KEYCODE_DPAD_LEFT) {
      this.onDoubleTap(-1);
      return;
    }
    if (code === KeyCode.KEYCODE_DPAD_RIGHT) {
      this.onDoubleTap(1);
      return;
    }
    if (code === KeyCode.KEYCODE_DPAD_UP) {
      this.stepVolume(1);
      return;
    }
    if (code === KeyCode.KEYCODE_DPAD_DOWN) {
      this.stepVolume(-1);
      return;
    }
    if (code === KeyCode.KEYCODE_PAGE_UP) {
      this.seekBy(-60000);
      return;
    }
    if (code === KeyCode.KEYCODE_PAGE_DOWN) {
      this.seekBy(60000);
      return;
    }
    if (code === KeyCode.KEYCODE_MOVE_HOME) {
      this.seekTo(0);
      this.pokeControls();
      return;
    }
    if (code === KeyCode.KEYCODE_MOVE_END) {
      if (this.durationMs > 0) {
        this.seekTo(this.durationMs);
        this.pokeControls();
      }
      return;
    }
    if (code === KeyCode.KEYCODE_M) {
      this.toggleMute();
      return;
    }
    if (code === KeyCode.KEYCODE_F) {
      this.toggleFullscreen();
      return;
    }
    if (code === KeyCode.KEYCODE_D) {
      this.toggleDanmaku();
      return;
    }
    if (code >= KeyCode.KEYCODE_0 && code <= KeyCode.KEYCODE_9) {
      this.seekToPercent(code - KeyCode.KEYCODE_0);
      return;
    }
  }

  // 空格按下：可加速时延迟判定长按，否则保持原有即时播放/暂停
  private onSpaceKeyPress(): void {
    if (this.spaceDown) {
      return; // 过滤系统按键重复
    }
    this.spaceDown = true;
    if (this.loading || this.errorText !== '' || !this.playing || this.speed >= 3.0) {
      if (!this.loading && this.errorText === '') {
        this.togglePlay();
        this.pokeControls();
      }
      return;
    }
    if (this.spaceTimer >= 0) {
      clearTimeout(this.spaceTimer);
    }
    this.spaceTimer = setTimeout(() => {
      this.spaceTimer = -1;
      if (this.playing) {
        this.startBoost();
      }
    }, 500);
  }

  // 空格松开：未触发加速为短按（播放/暂停），加速中恢复原速
  private onSpaceKeyRelease(): void {
    if (!this.spaceDown) {
      return;
    }
    this.spaceDown = false;
    if (this.spaceTimer >= 0) {
      clearTimeout(this.spaceTimer);
      this.spaceTimer = -1;
      if (!this.loading && this.errorText === '') {
        this.togglePlay();
        this.pokeControls();
      }
      return;
    }
    if (this.boosting) {
      this.endBoost();
    }
  }

  // ---- 键盘软件音量（AVPlayer 0-1，↑↓ 步进 10%，M 静音，HUD 短暂显示） ----
  private stepVolume(dir: number): void {
    let next = this.volume + dir * 0.1;
    if (next < 0) {
      next = 0;
    }
    if (next > 1) {
      next = 1;
    }
    next = Math.round(next * 10) / 10;
    if (next !== this.volume) {
      this.volume = next;
      Settings.setVideoVolume(next);
    }
    this.muted = false;
    this.applyVolume();
    this.showVolumeHud();
  }

  private toggleMute(): void {
    this.muted = !this.muted;
    this.applyVolume();
    this.showVolumeHud();
  }

  private applyVolume(): void {
    const player = this.player;
    if (player === undefined) {
      return;
    }
    try {
      player.setVolume(this.muted || this.volume <= 0 ? 0 : this.volume);
    } catch (e) {
      this.log(`applyVolume catch: ${e}`);
    }
  }

  private showVolumeHud(): void {
    this.volHudPct = this.muted || this.volume <= 0 ? 0 : Math.round(this.volume * 100);
    if (this.volumeHudTimer >= 0) {
      clearTimeout(this.volumeHudTimer);
    }
    this.volumeHudTimer = setTimeout(() => {
      this.volumeHudTimer = -1;
      this.volHudPct = -1;
    }, 800);
  }

  // ---- 画中画（华为视频对齐）----

  // 页面钩子：小窗期间由管理器回调取渲染 surface / 播放器 / 通知小窗激活态
  private pipHooks(): PipPageHooks {
    if (this.pipPageHooks === undefined) {
      const hooks: PipPageHooks = new PipPageHooks();
      hooks.getSurfaceId = (): string => this.surfaceId;
      hooks.getPlayer = (): media.AVPlayer | undefined => this.player;
      hooks.onPipActive = (active: boolean): void => {
        if (!this.destroyed) {
          this.pipActive = active;
        }
      };
      this.pipPageHooks = hooks;
    }
    return this.pipPageHooks;
  }

  // prepared 时注册页面钩子并同步媒体尺寸；自动小窗开关跟随实际播放状态（manager 内部缓存），
  // 不再无条件开启，只有真正进入 playing 后才会允许退后台自动弹小窗
  private async preparePip(): Promise<void> {
    if (!this.pipEnabled) {
      return;
    }
    await VideoPipManager.getInstance().prepare(this.getUIContext(), this.pipHooks(),
      this.videoW, this.videoH);
  }

  // 跟随播放/暂停切换“退后台自动启动画中画”（华为视频行为）
  private setPipAutoStart(enable: boolean): void {
    VideoPipManager.getInstance().setAutoStart(enable);
  }

  // 手动开关画中画小窗：开启 = 移交播放器/媒体句柄给管理器并退出播放页；关闭 = 停止小窗
  private async togglePiP(): Promise<void> {
    if (!this.pipEnabled) {
      Util.toastRes(this.getUIContext(), $r('app.string.video_pip_unsupported'));
      return;
    }
    const mgr = VideoPipManager.getInstance();
    if (mgr.isPipActive()) {
      mgr.stopActive();
      return;
    }
    const player = this.player;
    if (player === undefined || this.casting || this.btPending || this.btProgressive) {
      Util.toastRes(this.getUIContext(), $r('app.string.video_pip_unsupported'));
      return;
    }
    // mediaFile 仅本地文件播放才有；网络/代理 URL 播放为 undefined，由管理器按需关闭
    const session: PipSessionInfo = {
      player: player,
      mediaFile: this.mediaFile,
      mangaId: this.mangaId,
      chapterId: this.chapterId,
      videoW: this.videoW,
      videoH: this.videoH,
      stack: this.pathStack
    };
    const ok = await mgr.startManual(session, this.getUIContext());
    if (!ok) {
      Util.toastRes(this.getUIContext(), $r('app.string.video_pip_unsupported'));
      return;
    }
    // 移交成功：页面立即让出播放器/媒体句柄并退出播放页（aboutToDisappear 借 pipHandedOff 跳过清理）
    this.pipHandedOff = true;
    this.player = undefined;
    this.mediaFile = undefined;
    this.detachCacheListener();
    this.stopTicker();
    this.persist(false);
    this.pathStack.pop();
  }

  // ---- 华为视频手势：左半屏上下滑亮度 / 右半屏上下滑音量 / 横滑快进 ----

  private panStart(event: GestureEvent): void {
    this.panMode = 0;
    this.panSeekFrom = this.positionMs;
    this.seekHudMs = -1;
    if (this.locked || this.showSheet) {
      return;
    }
    // 上下滑的方向（亮度/音量）按手势起点所在半屏决定
    const fingers: FingerInfo[] = event.fingerList;
    this.panLeftHalf = fingers.length > 0 ?
      this.getUIContext().vp2px(fingers[0].localX) < this.areaW / 2 : false;
    this.disarmBoost();
  }

  private panUpdate(event: GestureEvent): void {
    if (this.panMode === 0 && (this.locked || this.showSheet)) {
      return;
    }
    const density: number = this.getUIContext().vp2px(1);
    const dx: number = this.getUIContext().vp2px(event.offsetX);
    const dy: number = this.getUIContext().vp2px(event.offsetY);
    if (this.panMode === 0) {
      // 首个显著位移判型：横向=快进，纵向=亮度/音量
      if (Math.abs(dx) < 12 * density && Math.abs(dy) < 12 * density) {
        return;
      }
      if (Math.abs(dx) > Math.abs(dy)) {
        if (this.durationMs <= 0) {
          return;
        }
        this.panMode = 3;
        this.panSeekFrom = this.positionMs;
      } else if (this.panLeftHalf) {
        this.panMode = 1;
        this.panBaseBright = this.videoBright > 0 ? this.videoBright : 0.5;
      } else {
        this.panMode = 2;
        this.panBaseVol = this.volume;
      }
    }
    const h: number = this.areaH > 0 ? this.areaH : 1;
    if (this.panMode === 1) {
      // 亮度：整屏纵向滑动覆盖全量程，下限 5% 防止全黑
      let next = this.panBaseBright - dy / h;
      next = Math.min(1, Math.max(0.05, next));
      this.videoBright = next;
      this.applyVideoBrightness();
      this.showBrightHud();
    } else if (this.panMode === 2) {
      // 音量：软件音量 0-1，整屏纵向滑动覆盖全量程
      let next = this.panBaseVol - dy / h;
      next = Math.min(1, Math.max(0, next));
      if (next !== this.volume) {
        this.volume = next;
        this.muted = false;
        this.applyVolume();
      }
      this.showVolumeHud();
    } else if (this.panMode === 3) {
      // 快进：整屏横向滑动覆盖总时长，HUD 预览目标时间，松手才真正跳转
      const w: number = this.areaW > 0 ? this.areaW : 1;
      let target = this.panSeekFrom + dx / w * this.durationMs;
      target = Math.min(this.durationMs, Math.max(0, target));
      this.seekHudMs = target;
    }
  }

  private panEnd(): void {
    if (this.panMode === 1) {
      Settings.setVideoBrightness(this.videoBright);
    } else if (this.panMode === 2) {
      Settings.setVideoVolume(this.volume);
    } else if (this.panMode === 3 && this.seekHudMs >= 0) {
      if (Math.abs(this.seekHudMs - this.panSeekFrom) >= 1000) {
        Haptics.soft();
        this.seekTo(Math.floor(this.seekHudMs));
      }
      this.seekHudMs = -1;
    }
    this.panMode = 0;
  }

  private applyVideoBrightness(): void {
    if (this.win === undefined) {
      return;
    }
    this.win.setWindowBrightness(this.videoBright).catch((): void => {
    });
  }

  private showBrightHud(): void {
    this.brightHudPct = Math.round(this.videoBright * 100);
    if (this.brightHudTimer >= 0) {
      clearTimeout(this.brightHudTimer);
    }
    this.brightHudTimer = setTimeout(() => {
      this.brightHudTimer = -1;
      this.brightHudPct = -1;
    }, 800);
  }

  private showResumeTipAt(ms: number): void {
    this.resumeTipMs = ms;
    this.showResumeTip = true;
    if (this.resumeTipTimer >= 0) {
      clearTimeout(this.resumeTipTimer);
    }
    this.resumeTipTimer = setTimeout(() => {
      this.resumeTipTimer = -1;
      this.showResumeTip = false;
    }, 6000);
  }

  // 意图框架快进/跳转指令（VideoSeekIntent 写入）：仅栈顶最新实例、且时间戳递增时消费
  private onSeekCommand(): void {
    const raw: string = this.seekCommand;
    if (raw === '' || this.destroyed) {
      return;
    }
    let cmd: VpSeekCommand;
    try {
      cmd = JSON.parse(raw) as VpSeekCommand;
    } catch (e) {
      return;
    }
    if (cmd === undefined || cmd === null || cmd.ts <= this.seekCmdTs) {
      return;
    }
    this.seekCmdTs = cmd.ts;
    if (this.instId !== vpSeq) {
      return;
    }
    let target: number = this.positionMs;
    if (cmd.mode === 'delta') {
      target = this.positionMs + cmd.ms;
    } else if (cmd.mode === 'absolute') {
      target = cmd.ms;
    } else if (cmd.mode === 'end') {
      if (this.durationMs <= 0) {
        return;
      }
      target = this.durationMs - 1000;
    } else {
      return;
    }
    if (target < 0) {
      target = 0;
    }
    if (this.durationMs > 0 && target > this.durationMs) {
      target = this.durationMs;
    }
    this.log(`intent seek ${cmd.mode} ${cmd.ms} -> ${target}`);
    this.seekTo(target);
    this.pokeControls();
  }

  private seekTo(ms: number): void {
    if (this.casting) {
      this.positionMs = ms;
      this.castMgr.seek(ms);
      return;
    }
    const player = this.player;
    if (player === undefined) {
      return;
    }
    const st = player.state;
    if (st !== 'prepared' && st !== 'playing' && st !== 'paused' && st !== 'completed') {
      this.log(`seekTo skipped, state=${st}`);
      return;
    }
    this.positionMs = ms;
    this.buffering = true;
    // @SuppressWarnings syscap
    player.seek(ms, media.SeekMode.SEEK_PREV_SYNC);
    this.persist(false);
  }

  private persist(finished: boolean): void {
    if (this.chapterId <= 0) {
      return;
    }
    const pos = finished && this.durationMs > 0 ? this.durationMs : Math.floor(this.positionMs);
    this.savedMs = pos;
    ContinueSession.updateProgress(pos);
    ChapterRepo.setLastPageRead(this.chapterId, pos).catch((e: Error): void => {
      hilog.warn(0xDEAD, 'VP', 'persist setLastPageRead failed, chapter=%{public}d, err=%{public}s',
        this.chapterId, `${e}`);
    });
    HistoryRepo.upsert(this.mangaId, this.chapterId, pos).catch((e: Error): void => {
      hilog.warn(0xDEAD, 'VP', 'persist history upsert failed, chapter=%{public}d, err=%{public}s',
        this.chapterId, `${e}`);
    });
    if (finished || (this.durationMs > 0 && pos >= this.durationMs * 0.9)) {
      ChapterRepo.setRead(this.chapterId, true).catch((e: Error): void => {
        hilog.warn(0xDEAD, 'VP', 'persist setRead failed, chapter=%{public}d, err=%{public}s',
          this.chapterId, `${e}`);
      });
    }
  }

  private pickQuality(index: number): void {
    if (index === this.qualityIndex) {
      return;
    }
    this.resumeMs = Math.floor(this.positionMs);
    this.qualityIndex = index;
    this.startCurrent();
  }

  private openChapter(id: number): void {
    if (id <= 0) {
      return;
    }
    this.persist(false);
    this.stopTicker();
    this.chapterId = id;
    this.loadChapter();
  }

  // ---- 投屏（仅支持网络直链：BT 边下边播/纯本地文件无远端可拉流地址） ----

  // 当前画质是否可投屏，可投返回直链，否则返回空串
  private canCastUrl(): string {
    if (this.btPending || this.btProgressive) {
      return '';
    }
    if (this.qualityIndex < 0 || this.qualityIndex >= this.videos.length) {
      return '';
    }
    const video = this.videos[this.qualityIndex];
    return video.url.indexOf('http') === 0 ? video.url : '';
  }

  // 投屏入口：先确保 AVSession 与元数据就绪（否则 picker 设备列表为空），再打开投屏弹层
  private async openCastSheet(): Promise<void> {
    if (this.loading) {
      return;
    }
    if (this.casting) {
      this.openSheet(5);
      return;
    }
    if (this.canCastUrl() === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.video_cast_unsupported'));
      return;
    }
    const ok: boolean = await this.castMgr.ensureSession(Util.hostAbilityContext(this.getUIContext()), {
      assetId: `cast-${this.chapterId}-${this.qualityIndex}`,
      title: this.chapter.name,
      artist: this.manga.title
    });
    if (!ok) {
      return;
    }
    this.openSheet(5);
  }

  // 向远端下发当前资源（切集/切画质在投屏中复用本方法）
  private startCastPlayback(): void {
    const url = this.canCastUrl();
    if (url === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.video_cast_unsupported'));
      this.castMgr.stopCasting();
      return;
    }
    const item: VideoCastItem = {
      assetId: `cast-${this.chapterId}-${this.qualityIndex}`,
      title: this.chapter.name,
      artist: this.manga.title,
      mediaUri: url,
      startPosition: Math.floor(this.positionMs),
      duration: Math.floor(this.durationMs)
    };
    this.castMgr.startCast(item);
  }

  // 远端设备连接成功：暂停本机播放并从当前进度开始投屏
  private onCastConnected(deviceName: string): void {
    if (this.destroyed) {
      return;
    }
    this.log(`cast connected: ${deviceName}`);
    this.casting = true;
    this.castDevice = deviceName;
    Util.toastRes(this.getUIContext(), $r('app.string.video_cast_connected_toast'), [deviceName]);
    const player = this.player;
    if (player !== undefined) {
      try {
        player.pause();
      } catch (e) {
        this.log(`cast pause local catch: ${e}`);
      }
    }
    this.playing = false;
    this.persist(false);
    this.startCastPlayback();
  }

  // 投屏断开：按远端进度续播本机
  private onCastDisconnected(positionMs: number): void {
    if (this.destroyed) {
      return;
    }
    this.log(`cast disconnected at ${positionMs}`);
    this.casting = false;
    this.castDevice = '';
    Util.toastRes(this.getUIContext(), $r('app.string.video_cast_disconnected'));
    const resume: number = positionMs > 0 ? positionMs : Math.floor(this.positionMs);
    this.positionMs = resume;
    this.resumeMs = resume;
    const player = this.player;
    if (player !== undefined && this.errorText === '' && !this.loading) {
      try {
        // 带版本后缀的 syscap 查询运行时恒为 false：if 分支仅为抑制 media 命名空间版本化标签的编译告警
        if (canIUse('SystemCapability.Multimedia.Media.Core [since 12]')) {
          // 死分支
        } else {
          player.seek(resume, media.SeekMode.SEEK_PREV_SYNC);
        }
        player.play();
        this.playing = true;
        this.armAutoHide();
      } catch (e) {
        this.log(`cast resume local catch: ${e}`);
      }
    } else if (!this.loading && this.errorText === '') {
      // 投屏中切集后本机播放器已释放：重新起播续接远端进度
      this.startCurrent();
    }
  }

  // 远端播放状态同步（进度/时长/播放中）
  private onCastPlayback(playing: boolean, positionMs: number, durationMs: number): void {
    if (this.destroyed) {
      return;
    }
    this.positionMs = positionMs;
    if (durationMs > 0) {
      this.durationMs = durationMs;
    }
    this.playing = playing;
    if (Math.abs(positionMs - this.savedMs) >= 5000) {
      this.persist(false);
    }
  }

  // 远端播放完毕：自动下一集（下一集仍走投屏路径）
  private onCastEnded(): void {
    if (this.destroyed) {
      return;
    }
    this.persist(true);
    if (this.autoNext && this.nextId > 0) {
      this.openChapter(this.nextId);
    }
  }

  // ---- 跳过 OP/ED ----

  // ticker 每拍检查：进入 OP 区间秒跳到区间尾；进入 ED 区间直接结束本集
  private applyAutoSkip(): void {
    if (!this.skipActive || this.durationMs <= 0 || this.positionMs <= 0) {
      return;
    }
    const posSec: number = this.positionMs / 1000;
    // OP：区间 [opS, opE) 命中即跳到 opE
    if (this.skipOpS >= 0 && this.skipOpE > this.skipOpS &&
      posSec >= this.skipOpS && posSec < this.skipOpE) {
      this.showSkipChip(1);
      this.seekTo(this.skipOpE * 1000);
      return;
    }
    // ED：越过 edS 即视为片尾（自动下一集或跳至片尾停住）
    if (this.skipEdS >= 0 && posSec >= this.skipEdS && !this.edSkipFired) {
      this.edSkipFired = true;
      this.showSkipChip(2);
      if (this.autoNext && this.nextId > 0) {
        this.openChapter(this.nextId);
      } else {
        this.seekTo(Math.max(0, this.durationMs - 500));
      }
      return;
    }
    // 回退到 ED 之前：重新武装片尾跳过
    if (this.skipEdS < 0 || posSec < this.skipEdS) {
      this.edSkipFired = false;
    }
  }

  // 跳过触发提示：短暂显示浮动 chip
  private showSkipChip(kind: number): void {
    this.skipChip = kind;
    setTimeout(() => {
      this.skipChip = 0;
    }, 1200);
  }

  // 按漫画加载持久化的跳过区间（秒）
  private loadSkipRanges(): void {
    const r: number[] = Settings.getVideoSkipRanges(this.mangaId);
    this.skipOpS = r[0] ?? -1;
    this.skipOpE = r[1] ?? -1;
    this.skipEdS = r[2] ?? -1;
    this.skipEdE = r[3] ?? -1;
    this.skipOpText = this.skipOpS >= 0 ? this.secToClock(this.skipOpS) : '';
    this.skipOpEText = this.skipOpE >= 0 ? this.secToClock(this.skipOpE) : '';
    this.skipEdSText = this.skipEdS >= 0 ? this.secToClock(this.skipEdS) : '';
    this.skipEdEText = this.skipEdE >= 0 ? this.secToClock(this.skipEdE) : '';
    this.skipActive = this.skipEnabled && this.hasSkipRanges();
    this.edSkipFired = false;
  }

  // 是否配置了有效跳过区间（OP 成对或 ED 有起点）
  private hasSkipRanges(): boolean {
    return (this.skipOpS >= 0 && this.skipOpE > this.skipOpS) || this.skipEdS >= 0;
  }

  // 保存设置面板输入的跳过区间（mm:ss），带成对/顺序校验
  private saveSkipRanges(): void {
    const opS: number = this.parseClock(this.skipOpText);
    const opE: number = this.parseClock(this.skipOpEText);
    const edS: number = this.parseClock(this.skipEdSText);
    const edE: number = this.parseClock(this.skipEdEText);
    // 非空但解析失败：格式非法
    if ((this.skipOpText.trim() !== '' && opS < 0) || (this.skipOpEText.trim() !== '' && opE < 0) ||
      (this.skipEdSText.trim() !== '' && edS < 0) || (this.skipEdEText.trim() !== '' && edE < 0) ||
      (edS >= 0 && edE >= 0 && edE <= edS)) {
      Util.toastRes(this.getUIContext(), $r('app.string.video_skip_invalid'));
      return;
    }
    // OP 区间必须成对且 start < end
    if ((opS >= 0) !== (opE >= 0) || (opS >= 0 && opE <= opS)) {
      Util.toastRes(this.getUIContext(), $r('app.string.video_skip_invalid'));
      return;
    }
    this.skipOpS = opS;
    this.skipOpE = opE;
    this.skipEdS = edS;
    this.skipEdE = edE;
    if (opS < 0 && edS < 0) {
      Settings.clearVideoSkipRanges(this.mangaId);
    } else {
      Settings.setVideoSkipRanges(this.mangaId, opS, opE, edS, edE);
    }
    this.skipActive = this.skipEnabled && this.hasSkipRanges();
    this.edSkipFired = false;
    Util.toastRes(this.getUIContext(), $r('app.string.video_skip_saved'));
  }

  private clearSkipRanges(): void {
    this.skipOpS = -1;
    this.skipOpE = -1;
    this.skipEdS = -1;
    this.skipEdE = -1;
    this.skipOpText = '';
    this.skipOpEText = '';
    this.skipEdSText = '';
    this.skipEdEText = '';
    this.skipActive = false;
    this.edSkipFired = false;
    Settings.clearVideoSkipRanges(this.mangaId);
  }

  // 秒 → "m:ss"
  private secToClock(sec: number): string {
    const s: number = Math.max(0, Math.floor(sec));
    const m: number = Math.floor(s / 60);
    const r: number = s % 60;
    return `${m}:${r < 10 ? '0' : ''}${r}`;
  }

  // "ss" / "m:ss" / "h:mm:ss" → 秒；空串或非法返回 -1
  private parseClock(text: string): number {
    const t: string = text.trim();
    if (t === '') {
      return -1;
    }
    const segs: string[] = t.split(':');
    if (segs.length > 3) {
      return -1;
    }
    let sec: number = 0;
    for (let i = 0; i < segs.length; i++) {
      if (!/^\d{1,2}$/.test(segs[i])) {
        return -1;
      }
      sec = sec * 60 + parseInt(segs[i], 10);
    }
    return sec;
  }

  // ---- 外挂字幕 ----

  // 字幕缓存路径（用户手动选择后缓存，下次进本集自动加载）
  private subCachePath(): string {
    const context = Util.hostAbilityContext(this.getUIContext());
    return `${context.cacheDir}/subs/${this.mangaId}_${this.chapterId}.srt`;
  }

  // 字幕加载：手动缓存优先 → 本地视频同名 .srt 自动探测
  private loadSubtitle(): void {
    this.subCues = [];
    this.subText = '';
    this.subPath = '';
    this.subtitleOn = false;
    let text: string = '';
    // 1. 手动选择过的字幕缓存
    const cacheP: string = this.subCachePath();
    let cachedExists: boolean;
    try {
      cachedExists = fs.accessSync(cacheP);
    } catch (e) {
const err = e as Error;
      throw err;
    }
    if (cachedExists) {
      try {
        text = fs.readTextSync(cacheP);
        this.subPath = cacheP;
      } catch (_e) {
        text = '';
      }
    }
    // 2. 本地视频同名 .srt
    if (text === '' && this.localPath !== '') {
      const dot: number = this.localPath.lastIndexOf('.');
      if (dot > 0) {
        const cand: string = `${this.localPath.substring(0, dot)}.srt`;
        let candExists: boolean;
        try {
          candExists = fs.accessSync(cand);
        } catch (e) {
const err = e as Error;
          throw err;
        }
        if (candExists) {
          try {
            text = fs.readTextSync(cand);
            this.subPath = cand;
          } catch (_e) {
            text = '';
          }
        }
      }
    }
    if (text !== '') {
      this.subCues = SubtitleParser.parseSrt(text);
      this.subtitleOn = this.subCues.length > 0 && Settings.getSubtitleEnabled();
    }
  }

  // ticker 每拍刷新当前字幕行（命中变化才写状态，避免高频重绘）
  private updateSubtitle(): void {
    if (!this.subtitleOn || this.subCues.length === 0) {
      return;
    }
    const text: string = SubtitleParser.activeText(this.subCues, this.positionMs);
    if (text !== this.subText) {
      this.subText = text;
    }
  }

  // 手动选择字幕文件（DocumentViewPicker，.srt），成功后缓存并立即生效
  private async pickSubtitle(): Promise<void> {
    try {
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const uris: string[] = await docPicker.select({ fileSuffixFilters: ['.srt'] });
      if (uris.length === 0) {
        return;
      }
      const text: string = this.readTextFromUri(uris[0]);
      const cues: SubCue[] = SubtitleParser.parseSrt(text);
      if (cues.length === 0) {
        Util.toastRes(this.getUIContext(), $r('app.string.video_subtitle_invalid'));
        return;
      }
      this.subCues = cues;
      this.subPath = uris[0];
      this.cacheSubtitle(text);
      this.subtitleOn = true;
      Settings.setSubtitleEnabled(true);
      Util.toastRes(this.getUIContext(), $r('app.string.video_subtitle_loaded'), [cues.length]);
    } catch (e) {
      this.log(`pickSubtitle catch: ${e}`);
      Util.toastRes(this.getUIContext(), $r('app.string.video_subtitle_pick_failed'));
    }
  }

  // 读取用户选择的文件（URI）：一次性读入（字幕文件较小，上限 8MB）
  private readTextFromUri(uri: string): string {
    let file: fs.File;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    } catch (e) {
const err = e as Error;
      throw err;
    }
    try {
      const stat: fs.Stat = fs.statSync(file.fd);
      const size: number = Math.min(stat.size, 8 * 1024 * 1024);
      if (size <= 0) {
        return '';
      }
      const buf: ArrayBuffer = new ArrayBuffer(size);
      const read: number = fs.readSync(file.fd, buf);
      if (read <= 0) {
        return '';
      }
      return util.TextDecoder.create('utf-8', { fatal: false })
        .decodeToString(new Uint8Array(buf.slice(0, read)));
    } catch (e) {
const err = e as Error;
      throw err;
    } finally {
      try {
        fs.closeSync(file);
      } catch (_e) {
        // 已关闭
      }
    }
  }

  // 字幕文本写入缓存（下次进本集自动加载）
  private cacheSubtitle(text: string): void {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const dir: string = `${context.cacheDir}/subs`;
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const path: string = this.subCachePath();
      const file: fs.File = fs.openSync(path,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, text);
        this.subPath = path;
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      this.log(`cacheSubtitle catch: ${e}`);
    }
  }

  // 停用字幕：仅删除应用缓存内的副本，不碰用户选择的源文件
  private clearSubtitle(): void {
    const cacheP: string = this.subCachePath();
    let cacheExists: boolean;
    try {
      cacheExists = fs.accessSync(cacheP);
    } catch (e) {
const err = e as Error;
      throw err;
    }
    if (this.subPath === cacheP && cacheExists) {
      try {
        fs.unlinkSync(cacheP);
      } catch (_e) {
      }
    }
    this.subCues = [];
    this.subText = '';
    this.subPath = '';
    this.subtitleOn = false;
  }

  // 字幕文件显示名（截取最后一段路径）
  private subBaseName(): string {
    const p: string = this.subPath;
    const slash: number = Math.max(p.lastIndexOf('/'), p.lastIndexOf('\\'));
    return slash >= 0 ? p.substring(slash + 1) : p;
  }

  // ---- 弹幕发送（dandanplay 账号） ----

  private async doDmLogin(): Promise<void> {
    if (this.dmLogging) {
      return;
    }
    const name: string = this.dmLoginName.trim();
    if (name === '' || this.dmLoginPass === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_not_matched'));
      return;
    }
    this.dmLogging = true;
    try {
      const acct: DdpAccount = await DanmakuService.login(name, this.dmLoginPass);
      this.dmAccount = acct;
      this.dmLoginPass = '';
      Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_logged_in'), [acct.userName]);
    } catch (e) {
      this.log(`doDmLogin catch: ${e}`);
      Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_login_failed'));
    }
    this.dmLogging = false;
  }

  // 发送弹幕：成功后本地立即上屏（加入 dmItems 并整表重设）
  private async doDmSend(): Promise<void> {
    if (this.dmSending) {
      return;
    }
    const text: string = this.dmSendText.trim();
    if (text === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_not_matched'));
      return;
    }
    this.dmSending = true;
    try {
      const posMs: number = this.currentPlayPos();
      await DanmakuService.send(this.chapterId, text, posMs, this.dmSendMode, this.dmSendColor);
      const item: DanmakuItem = new DanmakuItem();
      item.timeMs = Math.floor(posMs);
      item.mode = this.dmSendMode;
      item.color = this.dmSendColor;
      item.text = text;
      this.dmItems.push(item);
      this.dmCtrl.setItems(this.dmItems);
      this.dmSendText = '';
      Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_sent'));
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : '';
      this.log(`doDmSend catch: ${msg}`);
      if (msg === 'ddp_no_episode') {
        Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_send_no_episode'));
      } else if (msg === 'ddp_login_required') {
        this.dmAccount = undefined;
        Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_login_required'));
      } else {
        Util.toastRes(this.getUIContext(), $r('app.string.video_danmaku_send_failed'));
      }
    }
    this.dmSending = false;
  }

  // 24bit 颜色 → 6 位十六进制（颜色 swatch 用）
  private hex6(n: number): string {
    return (n & 0xFFFFFF).toString(16).toUpperCase().padStart(6, '0');
  }

  // ---- 倍速 / 弹幕 ----
  private speedToEnum(v: number): media.PlaybackSpeed {
    if (v === 0.5) {
      // @SuppressWarnings syscap
      return media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
    }
    if (v === 0.75) {
      // @SuppressWarnings syscap
      return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    }
    if (v === 1.25) {
      // @SuppressWarnings syscap
      return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    }
    if (v === 1.5) {
      // @SuppressWarnings syscap
      return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    }
    if (v === 1.75) {
      // @SuppressWarnings syscap
      return media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
    }
    if (v === 2.0) {
      // @SuppressWarnings syscap
      return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
    }
    // @SuppressWarnings syscap
    return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
  }

  private applySpeed(v: number): void {
    this.speed = v;
    Settings.setVideoSpeed(v);
    const player = this.player;
    if (player !== undefined) {
      player.setSpeed(this.speedToEnum(v));
    }
  }

  private toggleDanmaku(): void {
    this.danmakuOn = !this.danmakuOn;
    Settings.setDanmakuEnabled(this.danmakuOn);
    Util.toastRes(this.getUIContext(),
      this.danmakuOn ? $r('app.string.video_danmaku_on') : $r('app.string.video_danmaku_off'));
    if (this.danmakuOn) {
      this.loadDanmaku();
    }
    this.armAutoHide();
  }

  private currentPlayPos(): number {
    const player = this.player;
    if (player !== undefined && player.currentTime >= 0) {
      return player.currentTime;
    }
    return this.positionMs;
  }

  private openSheet(mode: number): void {
    if (this.hideTimer >= 0) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
    this.sheetMode = mode;
    // 发送弹幕面板：进入时刷新已保存的 dandanplay 账号
    if (mode === 6) {
      this.dmAccount = DanmakuService.savedAccount();
    }
    this.showSheet = true;
  }

  private clock(ms: number): string {
    const total = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    const ss = s < 10 ? `0${s}` : `${s}`;
    if (h > 0) {
      return `${h}:${m < 10 ? '0' : ''}${m}:${ss}`;
    }
    return `${m}:${ss}`;
  }

  private resLabel(): string {
    const h = this.videoH;
    if (h >= 2160) {
      return '2160p';
    }
    if (h >= 1440) {
      return '1440p';
    }
    if (h >= 1080) {
      return '1080p';
    }
    if (h >= 720) {
      return '720p';
    }
    if (h >= 480) {
      return '480p';
    }
    if (h >= 360) {
      return '360p';
    }
    return '';
  }

  private speedLabel(s: number): string {
    return s === 1.0 ? '1.0x' : `${s}x`;
  }

  private scaleModeLabel(m: number): ResourceStr {
    if (m === 1) {
      return $r('app.string.video_scale_fill');
    }
    if (m === 2) {
      return $r('app.string.video_scale_stretch');
    }
    return $r('app.string.video_scale_fit');
  }

  private areaLabel(i: number): ResourceStr {
    const labels: ResourceStr[] = [
      $r('app.string.danmaku_area_quarter'),
      $r('app.string.danmaku_area_half'),
      $r('app.string.danmaku_area_three_quarters'),
      $r('app.string.danmaku_area_full')
    ];
    return i >= 0 && i < labels.length ? labels[i] : '';
  }

  private durLabel(i: number): ResourceStr {
    const labels: ResourceStr[] = [
      $r('app.string.danmaku_speed_slow'),
      $r('app.string.danmaku_speed_normal'),
      $r('app.string.danmaku_speed_fast'),
      $r('app.string.danmaku_speed_fastest')
    ];
    return i >= 0 && i < labels.length ? labels[i] : '';
  }

  private sheetTitle(): ResourceStr {
    if (this.sheetMode === 1) {
      return $r('app.string.video_episodes');
    }
    if (this.sheetMode === 2) {
      return $r('app.string.video_quality');
    }
    if (this.sheetMode === 5) {
      return $r('app.string.video_cast');
    }
    if (this.sheetMode === 6) {
      return $r('app.string.video_danmaku_send_title');
    }
    return $r('app.string.video_settings');
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function VideoPlayerBuilder() {
  VideoPlayerPage()
}

// 单条剧集评论：头像 + 昵称 + 时间 + 表情回应数 + 正文（片段序列渲染）+ 楼中楼回复；
// 正文内 [mask] 剧透段默认以占位遮罩呈现，点击正文切换揭示；
// 底部表情回应 chips（点击切换/取消自己的回应）与回复入口
@Component
struct VpCommentItem {
  @Prop comment: EpisodeComment = new EpisodeComment();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 剧透遮罩揭示状态（本条评论与其楼中楼共用）
  @State revealed: boolean = false;
  // 图片查看器（无链接的 [img] 内联图点击进入应用内查看）
  @State showViewer: boolean = false;
  @State viewerUrl: string = '';
  // 点已有回应 chip：同值取消、异值切换（commentId + 反应值 + 当前已选值）
  onReact: (commentId: number, value: number, current: number) => void =
    (_commentId: number, _value: number, _current: number) => {
    };
  // "+" 添加回应：打开 12 表情选择器
  onReactAdd: (commentId: number, current: number) => void =
    (_commentId: number, _current: number) => {
    };
  // 回复：主评 replyToId = 主评 id；楼中楼 replyToId 仍为主评 id（isSubReply 预填 @昵称）
  onReply: (replyToId: number, nickname: string, isSubReply: boolean) => void =
    (_replyToId: number, _nickname: string, _isSubReply: boolean) => {
    };

  // 片段文字颜色：链接用主题色，[color] 指定色优先，引用块内用次要色，否则正文色
  private segColor(seg: CommentSegment, quoted: boolean): ResourceColor {
    if (seg.linkUrl !== '') {
      return this.pal.primary;
    }
    if (seg.color !== '') {
      return seg.color;
    }
    return quoted ? this.pal.sub : this.pal.text;
  }

  // 片段装饰线：[u]/[s] → 下划线/删除线（两者同取时优先删除线）
  private segDecoration(seg: CommentSegment, quoted: boolean): DecorationStyleInterface {
    if (seg.underline || seg.strike) {
      return {
        type: seg.strike ? TextDecorationType.LineThrough : TextDecorationType.Underline,
        color: this.segColor(seg, quoted)
      };
    }
    return { type: TextDecorationType.None, color: Color.Black };
  }

  // 主评或任一楼中楼含 [mask]（点击正文任意处切换揭示）
  private hasAnyMask(): boolean {
    if (this.comment.hasMask) {
      return true;
    }
    for (let i = 0; i < this.comment.replies.length; i++) {
      if (this.comment.replies[i].hasMask) {
        return true;
      }
    }
    return false;
  }

  // 行内片段渲染：0 文本 1 表情 2 遮罩占位 3 图片；masked 需揭示后渲染
  @Builder
  private segmentBuilder(seg: CommentSegment, baseSize: number, emojiSize: number,
    imgW: number, imgH: number, quoted: boolean) {
    if (seg.kind === 2) {
      if (!this.revealed) {
        Span($r('app.string.video_comments_spoiler'))
          .fontSize(baseSize - 2)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.primary)
      }
    } else {
      if (!seg.masked || this.revealed) {
        if (seg.kind === 1) {
          ImageSpan(seg.emojiUrl)
            .size({ width: seg.emojiLarge ? 55 : emojiSize, height: seg.emojiLarge ? 55 : emojiSize })
            .verticalAlign(ImageSpanAlignment.BASELINE)
        } else {
          if (seg.kind === 3) {
            ImageSpan(seg.imageUrl)
              .size({ width: imgW, height: imgH })
              .objectFit(ImageFit.Contain)
              .borderRadius(6)
              .verticalAlign(ImageSpanAlignment.BASELINE)
              .onClick(() => {
                if (seg.linkUrl !== '') {
                  this.openLink(seg.linkUrl);
                } else {
                  this.openImage(seg.imageUrl);
                }
              })
          } else {
            Span(seg.text)
              .fontSize(seg.fontSize > 0 ? seg.fontSize : baseSize)
              .fontColor(this.segColor(seg, quoted))
              .fontWeight(seg.bold ? FontWeight.Bold : FontWeight.Normal)
              .fontStyle(seg.italic ? FontStyle.Italic : FontStyle.Normal)
              .decoration(this.segDecoration(seg, quoted))
              .onClick(() => {
                if (seg.linkUrl !== '') {
                  this.openLink(seg.linkUrl);
                }
              })
          }
        }
      }
    }
  }

  // 内容块渲染：块级 quote（左竖线 + 次要色）/code（等宽 + 底色）/align/indent，
  // 主评与楼中楼共用（baseSize/emojiSize/imgW/imgH/lineHeight 按容器区分）
  @Builder
  private blocksBuilder(blocks: CommentBlock[], baseSize: number, emojiSize: number,
    imgW: number, imgH: number, lineHeight: number) {
    Column({ space: 4 }) {
      ForEach(blocks, (block: CommentBlock, bi: number) => {
        if (block.code) {
          Text() {
            ForEach(block.segments, (seg: CommentSegment, si: number) => {
              Span(seg.text)
                .fontSize(12)
                .fontColor(this.pal.sub)
                .fontFamily('monospace')
            }, (seg: CommentSegment, si: number) => `${bi}-c${si}`)
          }
          .width('100%')
          .lineHeight(18)
          .fontSize(12)
          .fontColor(this.pal.sub)
          .fontFamily('monospace')
          .backgroundColor(this.pal.chip)
          .borderRadius(6)
          .padding(8)
          .textAlign(TextAlign.Start)
        } else if (block.quote) {
          Text() {
            ForEach(block.segments, (seg: CommentSegment, si: number) => {
              this.segmentBuilder(seg, baseSize, emojiSize, imgW, imgH, true)
            }, (seg: CommentSegment, si: number) => `${bi}-q${si}`)
          }
          .width('100%')
          .lineHeight(lineHeight)
          .textAlign(block.align === 1 ? TextAlign.Center :
            (block.align === 2 ? TextAlign.End : TextAlign.Start))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .border({ width: { left: 3 }, color: this.pal.primary })
          .borderRadius(4)
        } else {
          Text() {
            ForEach(block.segments, (seg: CommentSegment, si: number) => {
              this.segmentBuilder(seg, baseSize, emojiSize, imgW, imgH, false)
            }, (seg: CommentSegment, si: number) => `${bi}-s${si}`)
          }
          .width('100%')
          .lineHeight(lineHeight)
          .textAlign(block.align === 1 ? TextAlign.Center :
            (block.align === 2 ? TextAlign.End : TextAlign.Start))
          .padding({ left: block.indent > 0 ? block.indent * 14 : 0 })
        }
      }, (block: CommentBlock, bi: number) => `${bi}-${block.code}-${block.quote}-${block.align}-${block.indent}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      if (this.hasAnyMask()) {
        this.revealed = !this.revealed;
      }
    })
  }

  // 用系统浏览器打开链接
  private openLink(url: string): void {
    Util.openUrl(Util.hostAbilityContext(this.getUIContext()), url);
  }

  // 无链接图片：应用内全屏查看器打开（有链接则仍走浏览器）
  private openImage(url: string): void {
    this.viewerUrl = url;
    this.showViewer = true;
  }

  @Builder
  imageViewerBuilder() {
    CoverViewer({
      coverUrl: this.viewerUrl,
      title: '',
      allowEdit: false,
      onClose: (): void => {
        this.showViewer = false;
      }
    })
  }

  // 表情回应 chips + 添加回应 + 回复操作行（主评与楼中楼共用）：
  // reactionId = 回应目标评论 id；replyToId = 回复目标（楼中楼回复仍挂主评 id）；
  // myValue = 当前用户已选反应值（0 未选），compact = 楼中楼紧凑档
  @Builder
  reactionRow(reactionId: number, replyToId: number, reactions: EpisodeReaction[],
    myValue: number, nickname: string, isSubReply: boolean, compact: boolean) {
    Row({ space: 6 }) {
      ForEach(reactions, (re: EpisodeReaction) => {
        Row({ space: 3 }) {
          Image(EpisodeCommentService.reactionEmojiUrl(re.value))
            .width(compact ? 14 : 16)
            .height(compact ? 14 : 16)
            .objectFit(ImageFit.Contain)
          Text(`${re.count}`)
            .fontSize(11)
            .fontColor(re.mine ? this.pal.onPrimary : this.pal.sub)
        }
        .alignItems(VerticalAlign.Center)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .borderRadius(11)
        .backgroundColor(re.mine ? this.pal.primary : this.pal.chip)
        .onClick(() => {
          this.onReact(reactionId, re.value, myValue);
        })
      }, (re: EpisodeReaction) => `re-${reactionId}-${re.value}-${re.count}-${re.mine}`)
      // + 添加回应（打开 12 表情选择器）
      Row() {
        Text('+')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.sub)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width(26)
      .height(22)
      .borderRadius(11)
      .backgroundColor(this.pal.chip)
      .onClick(() => {
        this.onReactAdd(reactionId, myValue);
      })
      Blank()
      Text($r('app.string.video_comments_reply'))
        .fontSize(12)
        .fontColor(this.pal.sub)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .onClick(() => {
          this.onReply(replyToId, nickname, isSubReply);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        if (this.comment.avatar !== '') {
          Image(this.comment.avatar)
            .width(28)
            .height(28)
            .borderRadius(14)
            .objectFit(ImageFit.Cover)
            .backgroundColor(this.pal.chip)
        } else {
          Column()
            .width(28)
            .height(28)
            .borderRadius(14)
            .backgroundColor(this.pal.chip)
        }
        Column({ space: 1 }) {
          Text(this.comment.nickname !== '' ? this.comment.nickname : 'Bangumi')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.comment.createdAtMs > 0) {
            Text(Util.timeAgo(this.comment.createdAtMs))
              .fontSize(11)
              .fontColor(this.pal.sub)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.comment.reactionCount > 0) {
          Row({ space: 3 }) {
            AppIcon({ name: 'favorite', iconSize: 12, tint: this.pal.sub })
            Text(`${this.comment.reactionCount}`)
              .fontSize(11)
              .fontColor(this.pal.sub)
          }
          .alignItems(VerticalAlign.Center)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 正文：块级内容（引用/代码/对齐/缩进块 + 行内片段；masked 需揭示后渲染）
      this.blocksBuilder(this.comment.blocks, 14, 20, 180, 130, 22)

      // 表情回应 chips + 回复入口
      this.reactionRow(this.comment.id, this.comment.id, this.comment.reactions,
        this.comment.myReactionValue, this.comment.nickname, false, false)

      // 楼中楼回复
      if (this.comment.replies.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.comment.replies, (r: EpisodeCommentReply, ri: number) => {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                if (r.avatar !== '') {
                  Image(r.avatar)
                    .width(18)
                    .height(18)
                    .borderRadius(9)
                    .objectFit(ImageFit.Cover)
                    .backgroundColor(this.pal.chip)
                }
                Text(r.nickname !== '' ? r.nickname : 'Bangumi')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.pal.sub)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (r.createdAtMs > 0) {
                  Text(Util.timeAgo(r.createdAtMs))
                    .fontSize(11)
                    .fontColor(this.pal.sub)
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              this.blocksBuilder(r.blocks, 13, 18, 150, 110, 20)

              // 楼中楼紧凑回应 chips + 回复入口
              this.reactionRow(r.id, this.comment.id, r.reactions,
                r.myReactionValue, r.nickname, true, true)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(8)
            .borderRadius(8)
            .backgroundColor(this.pal.chip)
          }, (r: EpisodeCommentReply, ri: number) => `cmt-${this.comment.id}-r-${r.id}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 10, bottom: 12 })
    .bindContentCover($$this.showViewer, this.imageViewerBuilder(), {
      modalTransition: ModalTransition.ALPHA,
      backgroundColor: '#B3000000',
    })
  }
}
