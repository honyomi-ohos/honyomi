// 视频画中画全局管理器（typeNode 方案，官方推荐）
// contentNode 为独立 typeNode.XComponent 自由节点，不随页面销毁；
// 播放器画面通过 surfaceId 在「页面 XComponent ↔ PiP 节点」间切换：
// 1. 手动小窗（右上角按钮）：页面把播放器/文件句柄移交本管理器后退出播放页，
//    小窗继续播放；关闭/删除时结算进度并释放资源；
//    「还原」时结算释放后重新 push 播放页，按落库进度续播。
// 2. 退后台自动小窗（华为视频对齐）：页面存活，仅切换渲染 surface，
//    还原/关闭时切回页面 surface，页面与播放器状态不受影响。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { PiPWindow, typeNode } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { ChapterRepo, HistoryRepo } from '../data/Repos';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { AppKeys } from './AppKeys';
import { ContinueSession } from './ContinueSession';
import { ReaderParams } from '../model/RouteParams';

// 页面侧钩子（页面存活期间由 VideoPlayerPage 注册）
export class PipPageHooks {
  // 页面 XComponent 当前 surfaceId（还原时回切画面）
  getSurfaceId: () => string = (): string => '';
  // 页面当前播放器实例（BT 边下边播数据边界会重建播放器，须实时获取）
  getPlayer: () => media.AVPlayer | undefined = (): media.AVPlayer | undefined => undefined;
  // 小窗激活状态变化（驱动页面按钮着色）
  onPipActive: (active: boolean) => void = (_active: boolean): void => {
  };
}

// 移交会话（页面退出、播放器归管理器接管）
export interface PipSessionInfo {
  player: media.AVPlayer;
  mediaFile: fs.File | undefined;
  mangaId: number;
  chapterId: number;
  videoW: number;
  videoH: number;
  stack: NavPathStack;
}

// PiP 节点 surface 生命周期回调：surface 创建/销毁时同步 surfaceId
class PipNodeController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void {
    VideoPipManager.getInstance().onPipSurfaceCreated(surfaceId);
  }

  onSurfaceDestroyed(_surfaceId: string): void {
    VideoPipManager.getInstance().onPipSurfaceDestroyed();
  }
}

export class VideoPipManager {
  private static instance: VideoPipManager | undefined = undefined;

  static getInstance(): VideoPipManager {
    if (VideoPipManager.instance === undefined) {
      VideoPipManager.instance = new VideoPipManager();
    }
    return VideoPipManager.instance;
  }

  // PiP 独立渲染节点（不挂布局）与控制器
  private nodeCtrl: PipNodeController = new PipNodeController();
  private node: typeNode.XComponent | undefined = undefined;
  private controller: PiPWindow.PiPController | undefined = undefined;
  private creating: Promise<PiPWindow.PiPController> | undefined = undefined;
  private uiContext: UIContext | undefined = undefined;
  private pipSurfaceId: string = '';
  // 小窗启动进行中（surface 可能晚于 startPiP 创建，创建后须补切渲染目标）
  private startPending: boolean = false;
  // 期望的退后台自动小窗：控制器异步创建期间先记录，创建完成后统一同步
  private autoStartWanted: boolean = false;
  private pipActive: boolean = false;
  // 页面钩子（页面存活的自动小窗场景）
  private page: PipPageHooks | undefined = undefined;
  // 移交会话（页面已退出的手动小窗场景）
  private session: PipSessionInfo | undefined = undefined;
  private sessionTicker: number = -1;
  private sessionPos: number = 0;
  private sessionDuration: number = 0;
  private sessionSavedMs: number = -1;

  private constructor() {
  }

  // prepared 时调用：确保控制器存在并同步媒体尺寸（系统要求应用前台创建）
  async prepare(uiContext: UIContext, page: PipPageHooks, w: number, h: number): Promise<void> {
    this.uiContext = uiContext;
    this.page = page;
    const ctrl = await this.ensureController();
    if (ctrl === undefined) {
      return;
    }
    if (w > 0 && h > 0) {
      ctrl.updateContentSize(w, h);
    }
    ctrl.setAutoStartEnabled(this.autoStartWanted);
  }

  // 跟随播放/暂停切换「退后台自动启动画中画」（华为视频行为）
  setAutoStart(enable: boolean): void {
    this.autoStartWanted = enable;
    if (this.controller !== undefined) {
      this.controller.setAutoStartEnabled(enable);
    }
  }

  // BT 边下边播等场景重建播放器时解析实际渲染目标：
  // 小窗激活期间新播放器直连 PiP 节点 surface，否则用页面 surface
  resolveSurface(pageSurfaceId: string): string {
    return this.pipActive && this.pipSurfaceId !== '' ? this.pipSurfaceId : pageSurfaceId;
  }

  // 手动小窗：移交播放器并启动 PiP；成功后由页面自行退出
  async startManual(info: PipSessionInfo, uiContext: UIContext): Promise<boolean> {
    this.uiContext = uiContext;
    // 已有移交会话（旧章节小窗中）：先结算关闭并等待窗口退出，避免重复操作冲突
    if (this.session !== undefined) {
      const oldCtrl = this.controller;
      this.endSession();
      if (oldCtrl !== undefined) {
        await oldCtrl.stopPiP().catch((): void => {
        });
      }
    }
    const ctrl = await this.ensureController();
    if (ctrl === undefined) {
      return false;
    }
    if (info.videoW > 0 && info.videoH > 0) {
      ctrl.updateContentSize(info.videoW, info.videoH);
    }
    this.session = info;
    this.sessionPos = 0;
    this.sessionDuration = 0;
    this.sessionSavedMs = -1;
    this.startPending = true;
    if (this.pipSurfaceId !== '') {
      this.applySurface(info.player, this.pipSurfaceId);
    }
    try {
      await ctrl.startPiP();
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0xDEAD, 'PiPMgr', 'startPiP failed, code=%{public}d', err.code);
      this.session = undefined;
      this.startPending = false;
      // 启动失败：画面切回页面 surface
      if (this.page !== undefined) {
        const back: string = this.page.getSurfaceId();
        if (back !== '') {
          this.applySurface(info.player, back);
        }
      }
      return false;
    }
    // 小窗已就位：会话归面板控制，页面即将退出
    this.page = undefined;
    this.setAutoStart(false);
    if (this.pipSurfaceId !== '') {
      this.applySurface(info.player, this.pipSurfaceId);
    }
    this.startSessionTicker();
    return true;
  }

  // 页面销毁时解除钩子与退后台自动小窗；移交会话不受影响
  detachPage(page: PipPageHooks | undefined, stopActivePip: boolean): void {
    if (this.page === page) {
      this.page = undefined;
    }
    this.setAutoStart(false);
    if (stopActivePip && this.pipActive && this.session === undefined && this.controller !== undefined) {
      this.controller.stopPiP().catch((): void => {
      });
    }
  }

  // 小窗激活时再次点击页面小窗按钮：关闭小窗回页面
  stopActive(): void {
    if (this.controller !== undefined) {
      this.controller.stopPiP().catch((): void => {
      });
    }
  }

  // 页面判断当前小窗是否激活（按钮态/手动开关入口）
  isPipActive(): boolean {
    return this.pipActive;
  }

  // 新视频加载前打断仍在小窗中播放的旧会话（结算进度、释放播放器、关闭小窗）
  interrupt(): void {
    if (this.session !== undefined) {
      const ctrl = this.controller;
      this.endSession();
      if (ctrl !== undefined) {
        ctrl.stopPiP().catch((): void => {
        });
      }
    }
  }

  // PiP 节点 surface 创建（自由节点 surface 随小窗窗口创建）：
  // 启动中/已激活时补切渲染目标，避免小窗黑屏
  onPipSurfaceCreated(surfaceId: string): void {
    hilog.info(0xDEAD, 'PiPMgr', 'pip surface created: %{public}s', surfaceId);
    this.pipSurfaceId = surfaceId;
    if (this.pipActive || this.startPending) {
      this.renderToPip();
    }
  }

  onPipSurfaceDestroyed(): void {
    hilog.info(0xDEAD, 'PiPMgr', 'pip surface destroyed');
    this.pipSurfaceId = '';
  }

  private async ensureController(): Promise<PiPWindow.PiPController | undefined> {
    if (this.controller !== undefined) {
      return this.controller;
    }
    if (this.uiContext === undefined || !PiPWindow.isPiPEnabled()) {
      return undefined;
    }
    const hostCtx = this.uiContext.getHostContext();
    if (hostCtx === undefined) {
      return undefined;
    }
    if (this.creating === undefined) {
      let node = this.node;
      if (node === undefined) {
        try {
          node = typeNode.createNode(this.uiContext, 'XComponent', {
            type: XComponentType.SURFACE,
            controller: this.nodeCtrl
          });
        } catch (e) {
          hilog.warn(0xDEAD, 'PiPMgr', 'create pip node failed: %{public}s', `${e}`);
          return undefined;
        }
        this.node = node;
        this.pipSurfaceId = this.nodeCtrl.getXComponentSurfaceId();
      }
      const config: PiPWindow.PiPConfiguration = {
        context: hostCtx,
        componentController: this.nodeCtrl,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY
      };
      this.creating = PiPWindow.create(config, node);
      // 首个创建者负责注册回调；并发调用者等待同一 Promise
      this.creating.then((ctrl: PiPWindow.PiPController): void => {
        this.creating = undefined;
        if (this.controller === undefined) {
          this.controller = ctrl;
          this.registerCallbacks(ctrl);
        }
      }).catch((): void => {
        this.creating = undefined;
      });
    }
    try {
      await this.creating;
      return this.controller;
    } catch (e) {
      hilog.warn(0xDEAD, 'PiPMgr', 'create pip controller failed: %{public}s', `${e}`);
      return undefined;
    }
  }

  private registerCallbacks(ctrl: PiPWindow.PiPController): void {
    ctrl.on('stateChange', (state: PiPWindow.PiPState, reason: string): void => {
      this.onStateChange(state, reason);
    });
    ctrl.on('controlEvent', (param: PiPWindow.ControlEventParam): void => {
      this.onControlEvent(param);
    });
  }

  private onStateChange(state: PiPWindow.PiPState, reason: string): void {
    hilog.info(0xDEAD, 'PiPMgr', 'state=%{public}s reason=%{public}s', `${state}`, reason);
    const wasActive: boolean = this.pipActive;
    this.pipActive = state === PiPWindow.PiPState.STARTED;
    if (this.pipActive !== wasActive && this.page !== undefined) {
      this.page.onPipActive(this.pipActive);
    }
    switch (state) {
      case PiPWindow.PiPState.ABOUT_TO_START:
        // typeNode 方案：渲染目标须自行切到 PiP 节点 surface
        this.startPending = true;
        this.renderToPip();
        break;
      case PiPWindow.PiPState.ABOUT_TO_RESTORE:
        if (this.session !== undefined) {
          // 移交会话还原：结算释放后重新进入播放页（按落库进度续播）
          this.restoreSession();
        } else {
          this.renderToPage();
        }
        break;
      case PiPWindow.PiPState.ABOUT_TO_STOP:
        if (this.session === undefined) {
          this.renderToPage();
        }
        break;
      case PiPWindow.PiPState.STOPPED:
        this.startPending = false;
        if (this.session !== undefined) {
          // 用户关闭/拖拽删除小窗：结算并释放移交会话
          this.endSession();
        } else {
          this.renderToPage();
        }
        break;
      default:
        break;
    }
  }

  // PiP 面板播放/暂停按钮
  private onControlEvent(param: PiPWindow.ControlEventParam): void {
    if (param.controlType !== PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE) {
      return;
    }
    const player = this.currentPlayer();
    if (player === undefined) {
      return;
    }
    const st = player.state;
    // 面板意图：PLAY=继续播放 PAUSE=暂停；状态缺失时按当前状态取反
    const wantPlay: boolean = param.status === undefined ? st !== 'playing'
      : param.status === PiPWindow.PiPControlStatus.PLAY;
    try {
      if (wantPlay) {
        if (st === 'paused' || st === 'prepared' || st === 'completed' || st === 'stopped') {
          player.play();
        }
      } else {
        if (st === 'playing') {
          player.pause();
        }
      }
    } catch (e) {
      hilog.warn(0xDEAD, 'PiPMgr', 'controlEvent failed: %{public}s', `${e}`);
    }
  }

  private applySurface(player: media.AVPlayer, surfaceId: string): void {
    try {
      player.surfaceId = surfaceId;
    } catch (e) {
      hilog.warn(0xDEAD, 'PiPMgr', 'applySurface failed: %{public}s', `${e}`);
    }
  }

  private currentPlayer(): media.AVPlayer | undefined {
    if (this.session !== undefined) {
      return this.session.player;
    }
    return this.page !== undefined ? this.page.getPlayer() : undefined;
  }

  private renderToPip(): void {
    const player = this.currentPlayer();
    if (player === undefined || this.pipSurfaceId === '') {
      return;
    }
    this.applySurface(player, this.pipSurfaceId);
  }

  private renderToPage(): void {
    if (this.page === undefined) {
      return;
    }
    const player = this.currentPlayer();
    if (player === undefined) {
      return;
    }
    const pageSurfaceId: string = this.page.getSurfaceId();
    if (pageSurfaceId === '') {
      return;
    }
    this.applySurface(player, pageSurfaceId);
  }

  private startSessionTicker(): void {
    this.stopSessionTicker();
    this.sessionTicker = setInterval((): void => {
      const s = this.session;
      if (s === undefined) {
        return;
      }
      const t: number = s.player.currentTime;
      if (t >= 0) {
        this.sessionPos = t;
      }
      if (s.player.duration > 0) {
        this.sessionDuration = s.player.duration;
      }
      if (Math.abs(this.sessionPos - this.sessionSavedMs) >= 5000) {
        this.persistSession(s, false);
      }
      ReadingStatsRepo.tick();
    }, 500);
  }

  private stopSessionTicker(): void {
    if (this.sessionTicker >= 0) {
      clearInterval(this.sessionTicker);
      this.sessionTicker = -1;
    }
  }

  // 移交会话进度落库（对齐页面 persist 逻辑）
  private persistSession(s: PipSessionInfo, finished: boolean): void {
    if (s.chapterId <= 0) {
      return;
    }
    const duration: number = this.sessionDuration > 0 ? this.sessionDuration
      : (s.player.duration > 0 ? s.player.duration : 0);
    const pos: number = finished && duration > 0 ? duration : Math.floor(this.sessionPos);
    this.sessionSavedMs = pos;
    ContinueSession.updateProgress(pos);
    ChapterRepo.setLastPageRead(s.chapterId, pos).catch((): void => {
      hilog.warn(0xDEAD, 'PiPMgr', 'persist setLastPageRead failed, chapter=%{public}d', s.chapterId);
    });
    HistoryRepo.upsert(s.mangaId, s.chapterId, pos).catch((): void => {
      hilog.warn(0xDEAD, 'PiPMgr', 'persist history failed, chapter=%{public}d', s.chapterId);
    });
    if (finished || (duration > 0 && pos >= duration * 0.9)) {
      ChapterRepo.setRead(s.chapterId, true).catch((): void => {
      });
    }
  }

  // 结算并释放移交会话（播放器/文件句柄/计时器），返回会话供还原跳转
  private releaseSession(): PipSessionInfo | undefined {
    const s = this.session;
    if (s === undefined) {
      return undefined;
    }
    this.session = undefined;
    this.stopSessionTicker();
    const t: number = s.player.currentTime;
    if (t >= 0) {
      this.sessionPos = t;
    }
    if (s.player.duration > 0) {
      this.sessionDuration = s.player.duration;
    }
    this.persistSession(s, false);
    try {
      s.player.release();
    } catch (e) {
      hilog.warn(0xDEAD, 'PiPMgr', 'session release failed: %{public}s', `${e}`);
    }
    if (s.mediaFile !== undefined) {
      try {
        fs.closeSync(s.mediaFile);
      } catch (_e) {
        // 已关闭
      }
    }
    ReadingStatsRepo.flush();
    // 观看历史已随进度落库：递增 libDirty 让历史页等常驻页签刷新
    AppStorage.setOrCreate(AppKeys.LIB_DIRTY, (AppStorage.get<number>(AppKeys.LIB_DIRTY) ?? 0) + 1);
    return s;
  }

  private endSession(): void {
    this.releaseSession();
  }

  // 还原：结算释放当前会话，重新 push 播放页（页内按 lastPageRead 续播）
  private restoreSession(): void {
    const s = this.releaseSession();
    if (s === undefined) {
      return;
    }
    const params: ReaderParams = { mangaId: s.mangaId, chapterId: s.chapterId };
    s.stack.pushPathByName('VideoPlayer', params);
  }
}
