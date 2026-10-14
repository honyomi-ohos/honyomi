import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { window } from '@kit.ArkUI';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, HistoryRepo } from '../data/Repos';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { DownloadService } from '../data/DownloadService';
import { DanmakuService, DanmakuItem } from '../data/DanmakuService';
import { SourceRegistry } from '../source/Source';
import { Http } from '../net/Http';
import { MangaRecord, ChapterRecord, SVideo } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';
import { Settings } from '../common/Settings';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { ReaderChapterNav, ChapterNeighbors } from '../common/ReaderChapterNav';
import { AppIcon } from './components/AppIcon';
import { DanmakuView, DanmakuController } from './components/DanmakuView';

const SPEEDS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
const SCALE_MODES: number[] = [0, 1, 2];
// 长按快进档位（与画面顶部的速度胶囊一一对应）
const BOOST_SPEEDS: number[] = [1.0, 1.5, 2.0, 3.0];
const DM_FONT_VALUES: number[] = [12, 14, 16, 18, 20];
const DM_OPACITY_VALUES: number[] = [30, 50, 80, 100];
const DM_AREA_VALUES: number[] = [25, 50, 75, 100];
const DM_DUR_VALUES: number[] = [12, 10, 8, 6];
let vpSeq: number = 0;

// 视频播放器（参考 AnymeX 播放器布局）：沉浸式全屏 + 顶部/中部/底部悬浮控制条，
// 双击左右区域快退/快进 10s，控制条 4s 自动隐藏，支持锁定、倍速、画质、剧集列表与弹幕
@Component
export struct VideoPlayerPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
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
  private mangaId: number = -1;
  private chapterId: number = -1;
  private resumeMs: number = 0;
  private savedMs: number = 0;
  private surfaceId: string = '';
  private player: media.AVPlayer | undefined = undefined;
  private mediaFile: fs.File | undefined = undefined;
  private xCtrl: XComponentController = new XComponentController();
  private ticker: number = -1;
  private dragging: boolean = false;
  private localPath: string = '';
  private playGen: number = 0;
  private videoW: number = 0;
  private videoH: number = 0;
  private areaW: number = 0;
  private areaH: number = 0;
  private hideTimer: number = -1;
  private tapTimer: number = -1;
  private seekToastTimer: number = -1;
  private boostTimer: number = -1;
  private boostDownX: number = 0;
  private boostAnchorX: number = 0;
  private suppressClick: boolean = false;
  private win: window.Window | undefined = undefined;
  private dmCtrl: DanmakuController = new DanmakuController();
  private dmLoading: boolean = false;
  private dmChapterId: number = -1;
  private instId: number = ++vpSeq;

  private log(msg: string): void {
    hilog.info(0xDEAD, 'VP', '[inst%{public}d] %{public}s', this.instId, msg);
  }

  aboutToAppear(): void {
    this.log('aboutToAppear');
    this.speed = Settings.getVideoSpeed();
    this.autoNext = Settings.getVideoAutoNext();
    this.scaleMode = Settings.getVideoScaleMode();
    this.danmakuOn = Settings.getDanmakuEnabled();
    this.dmFont = Settings.getDanmakuFont();
    this.dmOpacity = Settings.getDanmakuOpacityPct();
    this.dmArea = Settings.getDanmakuAreaPct();
    this.dmDur = Settings.getDanmakuDurationSec();
    // 沉浸式：隐藏状态栏与导航栏
    window.getLastWindow(Util.hostAbilityContext(this.getUIContext())).then((w: window.Window) => {
      this.win = w;
      if (canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
        w.setWindowSystemBarEnable([]).catch((): void => {
        });
      }
    }).catch((): void => {
    });
  }

  aboutToDisappear(): void {
    this.log('aboutToDisappear');
    this.persist(false);
    ReadingStatsRepo.flush();
    this.stopTicker();
    this.clearUiTimers();
    this.releasePlayer();
    if (this.win !== undefined) {
      // 还原系统栏与窗口方向
      if (canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
        this.win.setPreferredOrientation(window.Orientation.UNSPECIFIED).catch((): void => {
        });
        this.win.setWindowSystemBarEnable(['status', 'navigation']).catch((): void => {
        });
      }
      Settings.applySystemBar(Util.hostAbilityContext(this.getUIContext()));
    }
  }

  // 全屏横屏切换
  private toggleFullscreen(): void {
    this.fullscreen = !this.fullscreen;
    if (this.win !== undefined) {
      if (canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
        const target: window.Orientation = this.fullscreen ?
          window.Orientation.AUTO_ROTATION_LANDSCAPE : window.Orientation.AUTO_ROTATION_PORTRAIT;
        this.win.setPreferredOrientation(target).catch((): void => {
        });
      }
    }
    this.pokeControls();
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
  }

  private async loadChapter(): Promise<void> {
    this.loading = true;
    this.buffering = true;
    this.errorText = '';
    this.videos = [];
    this.playing = false;
    ReadingStatsRepo.flush();
    this.releasePlayer();
    this.dmChapterId = -1;
    this.dmCtrl.reset();
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const chapter = await ChapterRepo.getById(this.chapterId);
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
      const manga = await MangaRepo.get(chapter.mangaId);
      if (manga !== undefined) {
        this.manga = manga;
      }
      this.localPath = DownloadService.localVideo(chapter.mangaId, chapter.id);
      if (this.localPath === '') {
        const source = SourceRegistry.get(this.manga.sourceKey);
        if (source === undefined) {
          throw new Error('源不可用');
        }
        this.videos = await source.getVideoList(chapter.url);
        if (this.videos.length === 0) {
          throw new Error('没有可播放的视频');
        }
      }
      this.qualityIndex = 0;
      await this.loadNeighbors();
      await HistoryRepo.upsert(chapter.mangaId, chapter.id, this.resumeMs);
      ReadingStatsRepo.begin(chapter.mangaId, chapter.id);
      this.loading = false;
      this.startCurrent();
      if (this.danmakuOn) {
        this.loadDanmaku();
      }
    } catch (e) {
      const em = (e as Error).message;
      this.log(`loadChapter catch: ${em}`);
      this.errorText = (e as Error).message;
      this.buffering = false;
      Util.toastRes(this.getUIContext(), $r('app.string.reader_load_failed'), [this.errorText]);
      this.loading = false;
    }
  }

  private async loadNeighbors(): Promise<void> {
    const n: ChapterNeighbors = await ReaderChapterNav.neighbors(this.mangaId, this.chapterId);
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

  private startCurrent(): void {
    if (this.surfaceId === '') {
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
    this.playRemote(video);
  }

  private playFile(path: string): void {
    this.log(`playFile: ${path}`);
    this.playGen += 1;
    const gen = this.playGen;
    this.releasePlayer();
    // @SuppressWarnings syscap
    media.createAVPlayer().then((player: media.AVPlayer) => {
      if (gen !== this.playGen) {
        player.release();
        return;
      }
      this.bindPlayer(player);
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(path);
      this.mediaFile = file;
      const fdSrc: media.AVFileDescriptor = { fd: file.fd, offset: 0, length: stat.size };
      player.fdSrc = fdSrc;
    }).catch((e: Error) => {
      this.log(`playFile createAVPlayer catch: ${e.message}`);
      this.errorText = e.message;
      this.buffering = false;
    });
  }

  private playRemote(video: SVideo): void {
    this.log(`playRemote: ${video.url}`);
    this.playGen += 1;
    const gen = this.playGen;
    this.releasePlayer();
    // @SuppressWarnings syscap
    media.createAVPlayer().then((player: media.AVPlayer) => {
      if (gen !== this.playGen) {
        player.release();
        return;
      }
      this.bindPlayer(player);
      const headers = Http.headersFor(video.url, video.headers);
      // @SuppressWarnings syscap
      const source = media.createMediaSourceWithUrl(video.url, headers);
      const strategy: media.PlaybackStrategy = { preferredWidth: 0, preferredHeight: 0 };
      player.setMediaSource(source, strategy);
    }).catch((e: Error) => {
      this.log(`playRemote createAVPlayer catch: ${e.message}`);
      this.errorText = e.message;
      this.buffering = false;
    });
  }

  private bindPlayer(player: media.AVPlayer): void {
    this.log(`bindPlayer`);
    this.player = player;
    this.buffering = true;
    player.on('stateChange', (state: media.AVPlayerState) => {
      this.log(`stateChange: ${state}`);
      if (state === 'initialized') {
        // surfaceId 仅支持在 initialized 状态设置，须在 prepare() 之前完成
        player.surfaceId = this.surfaceId;
        player.prepare();
      } else if (state === 'prepared') {
        this.durationMs = player.duration > 0 ? player.duration : 0;
        this.videoW = player.width > 0 ? player.width : 0;
        this.videoH = player.height > 0 ? player.height : 0;
        this.adjustSurface();
        if (this.resumeMs > 0 && (this.durationMs === 0 || this.resumeMs < this.durationMs)) {
          // @SuppressWarnings syscap
          player.seek(this.resumeMs, media.SeekMode.SEEK_PREV_SYNC);
        }
        player.play();
        player.setSpeed(this.speedToEnum(this.speed));
        this.playing = true;
        this.startTicker();
      } else if (state === 'playing') {
        this.playing = true;
        this.buffering = false;
        this.armAutoHide();
      } else if (state === 'paused' || state === 'stopped') {
        this.playing = false;
        this.buffering = false;
      } else if (state === 'completed') {
        this.playing = false;
        this.buffering = false;
        this.persist(true);
        if (this.autoNext && this.nextId > 0) {
          this.openChapter(this.nextId);
        } else {
          this.showControls = true;
        }
      } else if (state === 'error') {
        this.log(`stateChange error, native state: ${player.state}`);
        this.playing = false;
        this.buffering = false;
        this.errorText = '播放失败';
      }
    });
    player.on('seekDone', () => {
      this.buffering = false;
    });
    player.on('error', (_err: Error) => {
      this.log(`player error cb: ${_err.message}, native state: ${player.state}`);
      if (player.state !== 'error') {
        this.log('non-fatal error ignored');
        return;
      }
      this.errorText = '播放失败';
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
      if (player.currentTime >= 0) {
        this.positionMs = player.currentTime;
      }
      if (player.duration > 0) {
        this.durationMs = player.duration;
      }
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
    if (player !== undefined) {
      player.release();
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
    if (this.playing) {
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
    const delta = side * 10000;
    let target = this.positionMs + delta;
    if (target < 0) {
      target = 0;
    }
    if (this.durationMs > 0 && target > this.durationMs) {
      target = this.durationMs;
    }
    this.seekTo(target);
    this.seekToast = side;
    if (this.seekToastTimer >= 0) {
      clearTimeout(this.seekToastTimer);
    }
    this.seekToastTimer = setTimeout(() => {
      this.seekToastTimer = -1;
      this.seekToast = 0;
    }, 600);
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
    if (this.locked || !this.playing || this.speed >= 3.0) {
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
      setTimeout(() => {
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
    const player = this.player;
    if (player === undefined) {
      this.startCurrent();
      return;
    }
    if (this.playing) {
      player.pause();
      this.persist(false);
    } else {
      player.play();
      this.armAutoHide();
    }
    this.armAutoHide();
  }

  private seekTo(ms: number): void {
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
    ChapterRepo.setLastPageRead(this.chapterId, pos).catch(() => {
    });
    HistoryRepo.upsert(this.mangaId, this.chapterId, pos).catch(() => {
    });
    if (finished || (this.durationMs > 0 && pos >= this.durationMs * 0.9)) {
      ChapterRepo.setRead(this.chapterId, true).catch(() => {
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
    if (this.sheetMode === 3) {
      return $r('app.string.video_speed');
    }
    return $r('app.string.video_settings');
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
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .margin({ right: 8 })
      }
      Column() {
        AppIcon({ name: 'lock', iconSize: 20, tint: Color.White })
      }
      .width(38)
      .height(38)
      .borderRadius(19)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(255,255,255,0.12)')
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
    .padding({ left: 10, right: 12, top: this.fullscreen ? 10 : this.statusBarH + 4, bottom: 12 })
    .linearGradient({ angle: 180, colors: [['rgba(0,0,0,0.65)', 0], [Color.Transparent, 1]] })
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  @Builder
  centerBar() {
    Row({ space: 26 }) {
      AppIcon({ name: 'skip_previous', iconSize: 32, tint: this.prevId > 0 ? Color.White : 'rgba(255,255,255,0.3)' })
        .onClick(() => {
          this.openChapter(this.prevId);
        })
      AppIcon({ name: 'replay_10', iconSize: 30, tint: Color.White })
        .onClick(() => {
          this.onDoubleTap(-1);
        })
      Column() {
        if (this.loading || this.buffering) {
          LoadingProgress().width(40).height(40).color(Color.White)
        } else {
          AppIcon({ name: this.playing ? 'pause' : 'play_arrow', iconSize: 40, tint: Color.White })
        }
      }
      .width(68)
      .height(68)
      .borderRadius(34)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(255,255,255,0.14)')
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
    .offset({ y: 20 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  @Builder
  ctrlBtn(icon: string, onTap: () => void) {
    Column() {
      AppIcon({ name: icon, iconSize: 20, tint: Color.White })
    }
    .width(38)
    .height(38)
    .borderRadius(19)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(255,255,255,0.12)')
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  bottomBar() {
    Column() {
      Row() {
        Text(this.clock(this.positionMs))
          .fontSize(13)
          .fontColor('#FFFFFF')
          .width(58)
        Slider({
          value: this.positionMs,
          min: 0,
          max: this.durationMs > 0 ? this.durationMs : 1,
          step: 1000
        })
          .layoutWeight(1)
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
        Text(this.clock(this.durationMs))
          .fontSize(13)
          .fontColor('#E0E0E0')
          .width(58)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.ctrlBtn('playlist_play', (): void => {
          this.openSheet(1);
        })
        if (this.videos.length > 1) {
          this.ctrlBtn('high_quality', (): void => {
            this.openSheet(2);
          })
        }
        this.ctrlBtn('speed', (): void => {
          this.openSheet(3);
        })
        Column() {
          AppIcon({ name: 'forum', iconSize: 20, tint: this.danmakuOn ? Color.White : 'rgba(255,255,255,0.35)' })
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(255,255,255,0.12)')
        .onClick(() => {
          this.toggleDanmaku();
        })
        this.ctrlBtn('tune', (): void => {
          this.openSheet(4);
        })
        this.ctrlBtn(this.fullscreen ? 'fullscreen_exit' : 'fullscreen', (): void => {
          this.toggleFullscreen();
        })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: this.fullscreen ? 14 : this.navBarH + 10 })
    .linearGradient({ angle: 180, colors: [[Color.Transparent, 0], ['rgba(0,0,0,0.65)', 1]] })
    .position({ x: 0, y: '100%' })
    .markAnchor({ x: 0, y: '100%' })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
  }

  @Builder
  unlockBtn() {
    Column() {
      AppIcon({ name: 'lock_open', iconSize: 22, tint: Color.White })
    }
    .width(46)
    .height(46)
    .borderRadius(23)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(0,0,0,0.55)')
    .border({ width: 1, color: 'rgba(255,255,255,0.4)' })
    .position({ x: '86%', y: '44%' })
    .onClick(() => {
      this.locked = false;
      Util.toastRes(this.getUIContext(), $r('app.string.video_unlocked'));
      this.pokeControls();
    })
  }

  // ---- 底部弹层（剧集 / 画质 / 倍速 / 播放设置）----
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
      .padding({ left: 20, right: 16, top: 14, bottom: 8 })
      Scroll() {
        Column() {
          if (this.sheetMode === 1) {
            this.episodesPane()
          } else if (this.sheetMode === 2) {
            this.qualityPane()
          } else if (this.sheetMode === 3) {
            this.speedPane()
          } else {
            this.settingsPane()
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 30 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
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
          Text(video.quality)
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

  @Builder
  speedPane() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(SPEEDS, (s: number) => {
          Text(this.speedLabel(s))
            .fontSize(14)
            .fontColor(this.speed === s ? Color.White : this.pal.text)
            .backgroundColor(this.speed === s ? this.pal.primary : this.pal.chip)
            .borderRadius(16)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .margin({ right: 8, top: 8 })
            .onClick(() => {
              this.applySpeed(s);
            })
        }, (s: number) => `spd-${s}`)
      }
      .width('100%')
    }
    .width('100%')
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
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
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
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
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
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
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
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
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
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
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
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
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

  build() {
    NavDestination() {
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
                .padding({ left: 18, right: 18, top: 6, bottom: 6 })
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
            Text(`${this.seekToast < 0 ? '-10s' : '+10s'}`)
              .fontSize(15)
              .fontColor(Color.White)
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(20)
          .backgroundColor('rgba(0,0,0,0.6)')
          .offset({ x: this.seekToast < 0 ? '-22%' : '22%', y: '-10%' })
        }

        if (this.errorText !== '') {
          Text(this.errorText)
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

        if (this.showControls && !this.locked) {
          this.topBar()
        }
        if (this.showControls && !this.locked) {
          this.centerBar()
        }
        if (this.showControls && !this.locked) {
          this.bottomBar()
        }
        if (this.locked && this.showControls) {
          this.unlockBtn()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .bindSheet($$this.showSheet, this.sheetBuilder(), {
        preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
        width: Bp.isWide(this.windowW) ? 560 : '100%',
        height: Bp.isWide(this.windowW) ? 560 : SheetSize.FIT_CONTENT,
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        showClose: false,
        blurStyle: BlurStyle.COMPONENT_ULTRA_THICK
      })
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
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function VideoPlayerBuilder() {
  VideoPlayerPage()
}
