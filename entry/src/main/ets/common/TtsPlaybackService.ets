import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChapterRepo, HistoryRepo, MangaRepo } from '../data/Repos';
import { ChapterRecord, MangaRecord } from '../model/Models';
import { SourceRegistry } from '../source/Source';
import { DownloadService } from '../data/DownloadService';
import { Util } from './Util';
import { Settings } from './Settings';
import { NovelTts } from './NovelTts';
import { TtsText } from './TtsText';
import { TtsAvSession, TtsSessionMeta } from './TtsAvSession';

const DOMAIN = 0x0001;
const TAG = 'TtsService';

// ---- 事件回调签名 ----
export type TtsServiceStateHandler =
  (playing: boolean, paused: boolean, mangaId: number, chapterId: number) => void;

export type TtsServiceParaHandler = (mangaId: number, chapterId: number, paraIdx: number) => void;

export type TtsServiceChapterHandler = (mangaId: number, chapterId: number) => void;

export type TtsServiceErrorHandler = (message: string) => void;

export type TtsServiceFinishHandler = () => void;

export type TtsServiceSleepHandler = (remainingMs: number) => void;

export type TtsServiceSleepChaptersHandler = (chaptersLeft: number) => void;

// 订阅列表模型：阅读器、播放器页、迷你条等多个实例可同时订阅、互不覆盖；
// 消费端 aboutToAppear 订阅、aboutToDisappear 退订自己的回调。
export class TtsServiceEvents {
  private stateHandlers: TtsServiceStateHandler[] = [];
  private paraHandlers: TtsServiceParaHandler[] = [];
  private chapterHandlers: TtsServiceChapterHandler[] = [];
  private errorHandlers: TtsServiceErrorHandler[] = [];
  private finishHandlers: TtsServiceFinishHandler[] = [];
  private sleepHandlers: TtsServiceSleepHandler[] = [];
  private sleepChaptersHandlers: TtsServiceSleepChaptersHandler[] = [];

  onState(handler: TtsServiceStateHandler): void {
    this.stateHandlers.push(handler);
  }

  offState(handler: TtsServiceStateHandler): void {
    this.stateHandlers = this.stateHandlers.filter((h: TtsServiceStateHandler): boolean => h !== handler);
  }

  onPara(handler: TtsServiceParaHandler): void {
    this.paraHandlers.push(handler);
  }

  offPara(handler: TtsServiceParaHandler): void {
    this.paraHandlers = this.paraHandlers.filter((h: TtsServiceParaHandler): boolean => h !== handler);
  }

  onChapter(handler: TtsServiceChapterHandler): void {
    this.chapterHandlers.push(handler);
  }

  offChapter(handler: TtsServiceChapterHandler): void {
    this.chapterHandlers = this.chapterHandlers.filter((h: TtsServiceChapterHandler): boolean => h !== handler);
  }

  onError(handler: TtsServiceErrorHandler): void {
    this.errorHandlers.push(handler);
  }

  offError(handler: TtsServiceErrorHandler): void {
    this.errorHandlers = this.errorHandlers.filter((h: TtsServiceErrorHandler): boolean => h !== handler);
  }

  onFinish(handler: TtsServiceFinishHandler): void {
    this.finishHandlers.push(handler);
  }

  offFinish(handler: TtsServiceFinishHandler): void {
    this.finishHandlers = this.finishHandlers.filter((h: TtsServiceFinishHandler): boolean => h !== handler);
  }

  onSleep(handler: TtsServiceSleepHandler): void {
    this.sleepHandlers.push(handler);
  }

  offSleep(handler: TtsServiceSleepHandler): void {
    this.sleepHandlers = this.sleepHandlers.filter((h: TtsServiceSleepHandler): boolean => h !== handler);
  }

  onSleepChapters(handler: TtsServiceSleepChaptersHandler): void {
    this.sleepChaptersHandlers.push(handler);
  }

  offSleepChapters(handler: TtsServiceSleepChaptersHandler): void {
    this.sleepChaptersHandlers =
      this.sleepChaptersHandlers.filter((h: TtsServiceSleepChaptersHandler): boolean => h !== handler);
  }

  // 通知遍历副本，允许回调内安全退订
  emitState(playing: boolean, paused: boolean, mangaId: number, chapterId: number): void {
    const handlers = this.stateHandlers.slice();
    for (let i = 0; i < handlers.length; i++) {
      handlers[i](playing, paused, mangaId, chapterId);
    }
  }

  emitPara(mangaId: number, chapterId: number, paraIdx: number): void {
    const handlers = this.paraHandlers.slice();
    for (let i = 0; i < handlers.length; i++) {
      handlers[i](mangaId, chapterId, paraIdx);
    }
  }

  emitChapter(mangaId: number, chapterId: number): void {
    const handlers = this.chapterHandlers.slice();
    for (let i = 0; i < handlers.length; i++) {
      handlers[i](mangaId, chapterId);
    }
  }

  emitError(message: string): void {
    const handlers = this.errorHandlers.slice();
    for (let i = 0; i < handlers.length; i++) {
      handlers[i](message);
    }
  }

  emitFinish(): void {
    const handlers = this.finishHandlers.slice();
    for (let i = 0; i < handlers.length; i++) {
      handlers[i]();
    }
  }

  emitSleep(remainingMs: number): void {
    const handlers = this.sleepHandlers.slice();
    for (let i = 0; i < handlers.length; i++) {
      handlers[i](remainingMs);
    }
  }

  emitSleepChapters(chaptersLeft: number): void {
    const handlers = this.sleepChaptersHandlers.slice();
    for (let i = 0; i < handlers.length; i++) {
      handlers[i](chaptersLeft);
    }
  }
}

// 小说听书播放编排服务（参考 AudioBook 示例 AudioControlCenter）：
// 在 NovelTts 引擎之上接管「章节级」播放——加载章节正文、拆分段落、驱动引擎，
// 提供播放/暂停/续播/上一章/下一章/语速/定时停止，播完自动进入下一章；
// 集成 AVSession（播控中心/锁屏媒体控制），朗读与阅读器页面生命周期解耦，
// 离开阅读器后可持续后台朗读。
export class TtsPlaybackService {
  static events: TtsServiceEvents = new TtsServiceEvents();
  private static ctx: common.UIAbilityContext | undefined = undefined;
  private static manga: MangaRecord | undefined = undefined;
  private static chapter: ChapterRecord | undefined = undefined;
  private static chapters: ChapterRecord[] = [];
  private static paras: string[] = [];
  private static lang: string = 'zh-CN';
  private static playingState: boolean = false;
  private static pausedState: boolean = false;
  private static pausePara: number = 0;
  private static paraIdx: number = -1;
  private static starting: boolean = false;
  // 章节加载代次号：连续切章时旧 start/续体据此丢弃
  private static loadGen: number = 0;
  // NovelTts 引擎事件只接管一次
  private static wired: boolean = false;
  // 定时停止
  private static sleepMinutes: number = 0;
  private static sleepTicker: number = -1;
  // 按章数定时：剩余待播章数（0 未启用）；到点后停在下一章开头（可续播）
  private static sleepChaptersLeft: number = 0;
  // 章数定时到点后待续播的下一章 id（0 无）
  private static resumeNextChapterId: number = 0;

  // ---- 状态查询 ----

  static isPlaying(): boolean {
    return TtsPlaybackService.playingState;
  }

  static isPaused(): boolean {
    return TtsPlaybackService.pausedState;
  }

  static isActive(): boolean {
    return TtsPlaybackService.playingState || TtsPlaybackService.pausedState;
  }

  static currentMangaId(): number {
    const m = TtsPlaybackService.manga;
    return m !== undefined ? m.id : -1;
  }

  static currentChapterId(): number {
    const ch = TtsPlaybackService.chapter;
    return ch !== undefined ? ch.id : -1;
  }

  static currentParaIdx(): number {
    return TtsPlaybackService.paraIdx;
  }

  static paraTotal(): number {
    return TtsPlaybackService.paras.length;
  }

  static getManga(): MangaRecord | undefined {
    return TtsPlaybackService.manga;
  }

  static getChapter(): ChapterRecord | undefined {
    return TtsPlaybackService.chapter;
  }

  static getChapters(): ChapterRecord[] {
    return TtsPlaybackService.chapters;
  }

  static sleepTimerMinutes(): number {
    return TtsPlaybackService.sleepMinutes;
  }

  static sleepChaptersLeftCount(): number {
    return TtsPlaybackService.sleepChaptersLeft;
  }

  // ---- 播放控制 ----

  // 从指定章节/段落开始朗读（加载正文并接管 AVSession）
  static async start(mangaId: number, chapterId: number, fromPara: number,
    context: common.UIAbilityContext): Promise<boolean> {
    if (TtsPlaybackService.starting) {
      return false;
    }
    TtsPlaybackService.starting = true;
    const gen = ++TtsPlaybackService.loadGen;
    try {
      TtsPlaybackService.ctx = context;
      const chapter = await ChapterRepo.getById(chapterId);
      if (chapter === undefined || chapter.mangaId !== mangaId || gen !== TtsPlaybackService.loadGen) {
        return false;
      }
      const manga = await MangaRepo.get(mangaId);
      if (manga === undefined || gen !== TtsPlaybackService.loadGen) {
        return false;
      }
      const chapters = await ChapterRepo.listByManga(mangaId);
      if (gen !== TtsPlaybackService.loadGen) {
        return false;
      }
      const text = await TtsPlaybackService.fetchText(manga, chapter);
      if (text === '' || gen !== TtsPlaybackService.loadGen) {
        return false;
      }
      const paras = TtsText.chapterParas(text);
      if (paras.length === 0 || gen !== TtsPlaybackService.loadGen) {
        return false;
      }
      // 提交状态：读取器（若在前台）经 onChapter 跟随加载
      TtsPlaybackService.manga = manga;
      TtsPlaybackService.chapter = chapter;
      TtsPlaybackService.chapters = chapters;
      TtsPlaybackService.paras = paras;
      TtsPlaybackService.lang = TtsText.detectLang(paras);
      TtsPlaybackService.paraIdx = -1;
      TtsPlaybackService.pausedState = false;
      TtsPlaybackService.pausePara = 0;
      TtsPlaybackService.resumeNextChapterId = 0;
      TtsPlaybackService.wireEngine();
      TtsPlaybackService.events.emitChapter(mangaId, chapterId);
      TtsPlaybackService.updateSession();
      const ok = await NovelTts.start(paras, fromPara, TtsPlaybackService.lang, context);
      if (gen !== TtsPlaybackService.loadGen) {
        return ok;
      }
      TtsPlaybackService.playingState = ok;
      if (!ok) {
        TtsPlaybackService.events.emitError('tts_unavailable');
      }
      TtsAvSession.setPlaying(ok);
      TtsPlaybackService.emitState();
      return ok;
    } finally {
      TtsPlaybackService.starting = false;
    }
  }

  // 暂停：记录当前朗读段，停止引擎（TTS 无原生暂停，续播从该段重读）
  static pause(): void {
    if (!TtsPlaybackService.playingState) {
      return;
    }
    TtsPlaybackService.pausePara =
      TtsPlaybackService.paraIdx >= 0 ? TtsPlaybackService.paraIdx : NovelTts.currentPara();
    TtsPlaybackService.loadGen += 1;
    TtsPlaybackService.starting = false;
    NovelTts.stop();
    TtsPlaybackService.playingState = false;
    TtsPlaybackService.pausedState = true;
    TtsAvSession.setPlaying(false);
    TtsPlaybackService.emitState();
  }

  // 续播：从暂停段落继续（复用已加载段落，不重新取正文）
  static resume(): void {
    if (!TtsPlaybackService.pausedState) {
      return;
    }
    // 章数定时到点后的续播：直接从下一章开头朗读
    if (TtsPlaybackService.resumeNextChapterId > 0) {
      const m = TtsPlaybackService.manga;
      const ctx = TtsPlaybackService.ctx;
      const nextId = TtsPlaybackService.resumeNextChapterId;
      TtsPlaybackService.resumeNextChapterId = 0;
      if (m !== undefined && ctx !== undefined) {
        TtsPlaybackService.pausedState = false;
        TtsPlaybackService.start(m.id, nextId, 0, ctx).catch((e: Object): void => {
          hilog.warn(DOMAIN, TAG, 'resume next chapter failed: %{public}s', `${e}`);
        });
        return;
      }
    }
    const ctx = TtsPlaybackService.ctx;
    const ch = TtsPlaybackService.chapter;
    if (ctx === undefined || ch === undefined || TtsPlaybackService.paras.length === 0) {
      return;
    }
    const from = TtsPlaybackService.pausePara;
    const lang = TtsPlaybackService.lang;
    const paras = TtsPlaybackService.paras;
    TtsPlaybackService.pausedState = false;
    TtsPlaybackService.playingState = true;
    TtsPlaybackService.emitState();
    TtsAvSession.setPlaying(true);
    NovelTts.start(paras, from, lang, ctx).then((ok: boolean) => {
      if (!TtsPlaybackService.pausedState && !ok) {
        // 非暂停/停止导致的失败：回落到停止态并报错
        TtsPlaybackService.playingState = false;
        TtsAvSession.setPlaying(false);
        TtsPlaybackService.events.emitError('tts_unavailable');
        TtsPlaybackService.emitState();
      }
    }).catch((e: Object): void => {
      // NovelTts.start 为 async：启动异常同样回落到停止态，避免悬挂的播放中状态
      hilog.warn(DOMAIN, TAG, 'resume start failed: %{public}s', `${e}`);
      if (!TtsPlaybackService.pausedState) {
        TtsPlaybackService.playingState = false;
        TtsAvSession.setPlaying(false);
        TtsPlaybackService.events.emitError('tts_unavailable');
        TtsPlaybackService.emitState();
      }
    });
  }

  // 播放/暂停切换（播控中心、迷你条、播放器页共用）
  static toggle(): void {
    if (TtsPlaybackService.playingState) {
      TtsPlaybackService.pause();
      return;
    }
    TtsPlaybackService.resume();
  }

  // 完全停止：清空播放状态并销毁播控会话
  static stop(): void {
    const wasActive = TtsPlaybackService.playingState || TtsPlaybackService.pausedState;
    TtsPlaybackService.loadGen += 1;
    TtsPlaybackService.starting = false;
    NovelTts.stop();
    TtsPlaybackService.playingState = false;
    TtsPlaybackService.pausedState = false;
    TtsPlaybackService.paras = [];
    TtsPlaybackService.paraIdx = -1;
    TtsPlaybackService.pausePara = 0;
    TtsPlaybackService.resumeNextChapterId = 0;
    TtsPlaybackService.manga = undefined;
    TtsPlaybackService.chapter = undefined;
    TtsPlaybackService.chapters = [];
    TtsPlaybackService.cancelSleepTimer();
    TtsAvSession.destroy();
    if (wasActive) {
      TtsPlaybackService.emitState();
    }
  }

  // 上一章/下一章（delta=-1/1）
  static step(delta: number): void {
    const ch = TtsPlaybackService.chapter;
    const m = TtsPlaybackService.manga;
    const ctx = TtsPlaybackService.ctx;
    if (ch === undefined || m === undefined || ctx === undefined) {
      return;
    }
    let idx = -1;
    for (let i = 0; i < TtsPlaybackService.chapters.length; i++) {
      if (TtsPlaybackService.chapters[i].id === ch.id) {
        idx = i;
        break;
      }
    }
    const target = idx + delta;
    if (idx < 0 || target < 0 || target >= TtsPlaybackService.chapters.length) {
      return;
    }
    TtsPlaybackService.start(m.id, TtsPlaybackService.chapters[target].id, 0, ctx)
      .catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, 'step failed: %{public}s', `${e}`);
      });
  }

  // 选择章节从头朗读
  static selectChapter(chapterId: number): void {
    const m = TtsPlaybackService.manga;
    const ctx = TtsPlaybackService.ctx;
    if (m === undefined || ctx === undefined) {
      return;
    }
    TtsPlaybackService.start(m.id, chapterId, 0, ctx).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'selectChapter failed: %{public}s', `${e}`);
    });
  }

  // 语速（0.5 - 2）：持久化；播放中从当前段以新语速续播
  static setSpeed(v: number): void {
    Settings.setNovelTtsSpeed(v);
    if (!TtsPlaybackService.playingState) {
      return;
    }
    const ctx = TtsPlaybackService.ctx;
    if (ctx === undefined || TtsPlaybackService.paras.length === 0) {
      return;
    }
    const from = TtsPlaybackService.paraIdx >= 0 ? TtsPlaybackService.paraIdx : NovelTts.currentPara();
    const paras = TtsPlaybackService.paras;
    const lang = TtsPlaybackService.lang;
    NovelTts.stop();
    NovelTts.start(paras, from, lang, ctx).then((ok: boolean) => {
      if (!TtsPlaybackService.playingState) {
        return;
      }
      if (!ok) {
        TtsPlaybackService.playingState = false;
        TtsAvSession.setPlaying(false);
        TtsPlaybackService.events.emitError('tts_unavailable');
        TtsPlaybackService.emitState();
      }
    }).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'restart after speed change failed: %{public}s', `${e}`);
      if (TtsPlaybackService.playingState) {
        TtsPlaybackService.playingState = false;
        TtsAvSession.setPlaying(false);
        TtsPlaybackService.events.emitError('tts_unavailable');
        TtsPlaybackService.emitState();
      }
    });
  }

  // ---- 相对快进/快退 ----

  // 秒级相对跳转（正为快进，负为快退）：TTS 无时间轨，
  // 按 1x 约 4.5 字/秒、乘以当前语速折算目标段的累计字数估算
  static seek(deltaSec: number): void {
    const total = TtsPlaybackService.paras.length;
    if (total === 0) {
      return;
    }
    let base = TtsPlaybackService.playingState ?
      (TtsPlaybackService.paraIdx >= 0 ? TtsPlaybackService.paraIdx : NovelTts.currentPara()) :
      TtsPlaybackService.pausePara;
    if (base < 0) {
      base = 0;
    }
    if (base >= total) {
      base = total - 1;
    }
    const speed = Settings.getNovelTtsSpeed();
    const budget = Math.max(1, Math.round(Math.abs(deltaSec) * 4.5 * (speed > 0 ? speed : 1)));
    let target = base;
    let acc = 0;
    if (deltaSec < 0) {
      for (let i = base - 1; i >= 0; i--) {
        acc += TtsPlaybackService.paraChars(i);
        target = i;
        if (acc >= budget) {
          break;
        }
      }
    } else if (deltaSec > 0) {
      for (let i = base + 1; i < total; i++) {
        acc += TtsPlaybackService.paraChars(i);
        target = i;
        if (acc >= budget) {
          break;
        }
      }
    }
    if (target === base) {
      return;
    }
    // 暂停态：仅移动续播点并同步 UI 进度
    if (!TtsPlaybackService.playingState) {
      if (!TtsPlaybackService.pausedState) {
        return;
      }
      TtsPlaybackService.resumeNextChapterId = 0;
      TtsPlaybackService.pausePara = target;
      TtsPlaybackService.paraIdx = target;
      TtsPlaybackService.events.emitPara(TtsPlaybackService.currentMangaId(),
        TtsPlaybackService.currentChapterId(), target);
      return;
    }
    // 播放中：从目标段重启引擎续播
    const ctx = TtsPlaybackService.ctx;
    if (ctx === undefined) {
      return;
    }
    const paras = TtsPlaybackService.paras;
    const lang = TtsPlaybackService.lang;
    TtsPlaybackService.paraIdx = target;
    NovelTts.stop();
    NovelTts.start(paras, target, lang, ctx).then((ok: boolean) => {
      if (!TtsPlaybackService.playingState) {
        return;
      }
      if (!ok) {
        TtsPlaybackService.playingState = false;
        TtsAvSession.setPlaying(false);
        TtsPlaybackService.events.emitError('tts_unavailable');
        TtsPlaybackService.emitState();
      }
    }).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'restart after seek failed: %{public}s', `${e}`);
      if (TtsPlaybackService.playingState) {
        TtsPlaybackService.playingState = false;
        TtsAvSession.setPlaying(false);
        TtsPlaybackService.events.emitError('tts_unavailable');
        TtsPlaybackService.emitState();
      }
    });
  }

  // minutes<=0 取消定时；到点暂停朗读（可续播）
  static setSleepTimer(minutes: number): void {
    TtsPlaybackService.cancelSleepTicker();
    // 切换为时长定时时取消章数定时
    if (TtsPlaybackService.sleepChaptersLeft !== 0) {
      TtsPlaybackService.sleepChaptersLeft = 0;
      TtsPlaybackService.events.emitSleepChapters(0);
    }
    TtsPlaybackService.sleepMinutes = minutes > 0 ? minutes : 0;
    if (minutes <= 0) {
      TtsPlaybackService.events.emitSleep(-1);
      return;
    }
    const endAt = Date.now() + minutes * 60000;
    TtsPlaybackService.sleepTicker = setInterval((): void => {
      const remain = endAt - Date.now();
      if (remain <= 0) {
        TtsPlaybackService.cancelSleepTicker();
        TtsPlaybackService.sleepMinutes = 0;
        TtsPlaybackService.events.emitSleep(-1);
        if (TtsPlaybackService.playingState) {
          TtsPlaybackService.pause();
        }
        return;
      }
      TtsPlaybackService.events.emitSleep(remain);
    }, 1000);
    TtsPlaybackService.events.emitSleep(minutes * 60000);
  }

  // ---- 定时停止 ----

  static cancelSleepTimer(): void {
    TtsPlaybackService.cancelSleepTicker();
    if (TtsPlaybackService.sleepMinutes !== 0) {
      TtsPlaybackService.sleepMinutes = 0;
    }
    if (TtsPlaybackService.sleepChaptersLeft !== 0) {
      TtsPlaybackService.sleepChaptersLeft = 0;
    }
    TtsPlaybackService.events.emitSleep(-1);
    TtsPlaybackService.events.emitSleepChapters(0);
  }

  // 按章数定时：播完 count 章后停在下一章开头（count>=1；count<=0 取消）
  static setSleepChapters(count: number): void {
    TtsPlaybackService.cancelSleepTicker();
    // 切换为章数定时时取消时长定时
    if (TtsPlaybackService.sleepMinutes !== 0) {
      TtsPlaybackService.sleepMinutes = 0;
    }
    TtsPlaybackService.sleepChaptersLeft = count > 0 ? count : 0;
    TtsPlaybackService.events.emitSleep(-1);
    TtsPlaybackService.events.emitSleepChapters(TtsPlaybackService.sleepChaptersLeft);
  }

  // 段落有效字符数（去空白，用于秒级跳转估算）
  private static paraChars(idx: number): number {
    const p = TtsPlaybackService.paras[idx];
    if (p === undefined) {
      return 0;
    }
    return p.replace(/\s/g, '').length;
  }

  private static cancelSleepTicker(): void {
    if (TtsPlaybackService.sleepTicker !== -1) {
      clearInterval(TtsPlaybackService.sleepTicker);
      TtsPlaybackService.sleepTicker = -1;
    }
  }

  // ---- 内部 ----

  // 接管引擎事件（仅一次）：段落推进、整章播完、引擎错误
  private static wireEngine(): void {
    if (TtsPlaybackService.wired) {
      return;
    }
    TtsPlaybackService.wired = true;
    NovelTts.events.onParaStart((idx: number): void => {
      TtsPlaybackService.paraIdx = idx;
      const m = TtsPlaybackService.manga;
      const ch = TtsPlaybackService.chapter;
      if (m !== undefined && ch !== undefined) {
        TtsPlaybackService.events.emitPara(m.id, ch.id, idx);
      }
    });
    NovelTts.events.onAllDone((): void => {
      TtsPlaybackService.onChapterDone();
    });
    NovelTts.events.onError((message: string): void => {
      TtsPlaybackService.playingState = false;
      TtsPlaybackService.pausedState = false;
      TtsPlaybackService.paras = [];
      TtsPlaybackService.paraIdx = -1;
      TtsPlaybackService.loadGen += 1;
      TtsPlaybackService.starting = false;
      NovelTts.stop();
      TtsPlaybackService.cancelSleepTimer();
      TtsAvSession.destroy();
      TtsPlaybackService.emitState();
      TtsPlaybackService.events.emitError(message);
    });
  }

  // 整章播完：标记已读并入历史，自动进入下一章；无下一章则结束
  private static onChapterDone(): void {
    const ch = TtsPlaybackService.chapter;
    const m = TtsPlaybackService.manga;
    if (ch === undefined || m === undefined) {
      return;
    }
    TtsPlaybackService.playingState = false;
    ChapterRepo.setLastPageRead(ch.id, 1000).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'setLastPageRead failed: %{public}s', `${e}`);
    });
    ChapterRepo.setRead(ch.id, true).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'setRead failed: %{public}s', `${e}`);
    });
    HistoryRepo.upsert(m.id, ch.id, 1000).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'history upsert failed: %{public}s', `${e}`);
    });
    let nextId = 0;
    for (let i = 0; i < TtsPlaybackService.chapters.length; i++) {
      if (TtsPlaybackService.chapters[i].id === ch.id && i < TtsPlaybackService.chapters.length - 1) {
        nextId = TtsPlaybackService.chapters[i + 1].id;
        break;
      }
    }
    // 章数定时递减：播完设定章数后不再自动续播，停在下一章开头（可续播）
    if (TtsPlaybackService.sleepChaptersLeft > 0) {
      TtsPlaybackService.sleepChaptersLeft -= 1;
      if (TtsPlaybackService.sleepChaptersLeft === 0) {
        TtsPlaybackService.playingState = false;
        if (nextId > 0) {
          TtsPlaybackService.pausedState = true;
          TtsPlaybackService.pausePara = 0;
          TtsPlaybackService.resumeNextChapterId = nextId;
          TtsAvSession.setPlaying(false);
          TtsPlaybackService.emitState();
          TtsPlaybackService.events.emitSleepChapters(0);
          return;
        }
        // 无下一章：走全书播完
      } else {
        TtsPlaybackService.events.emitSleepChapters(TtsPlaybackService.sleepChaptersLeft);
      }
    }
    if (nextId > 0 && TtsPlaybackService.ctx !== undefined) {
      const mangaId = m.id;
      const ctx = TtsPlaybackService.ctx;
      TtsPlaybackService.start(mangaId, nextId, 0, ctx).then((ok: boolean): void => {
        if (!ok) {
          TtsPlaybackService.emitState();
        }
      }).catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, 'auto next chapter failed: %{public}s', `${e}`);
      });
      return;
    }
    // 全书播完
    TtsPlaybackService.stop();
    TtsPlaybackService.events.emitFinish();
  }

  // 刷新播控中心/锁屏媒体卡片
  private static updateSession(): void {
    const ctx = TtsPlaybackService.ctx;
    const m = TtsPlaybackService.manga;
    const ch = TtsPlaybackService.chapter;
    if (ctx === undefined || m === undefined || ch === undefined) {
      return;
    }
    const meta: TtsSessionMeta = {
      assetId: `${m.id}-${ch.id}`,
      title: ch.name,
      artist: m.author,
      queueName: m.title,
      queueId: `${m.id}`,
      coverUri: m.thumbnailUrl.indexOf('file://') === 0 ? m.thumbnailUrl : ''
    };
    TtsAvSession.setup(ctx, meta, {
      onPlay: (): void => {
        TtsPlaybackService.resume();
      },
      onPause: (): void => {
        TtsPlaybackService.pause();
      },
      onNext: (): void => {
        TtsPlaybackService.step(1);
      },
      onPrev: (): void => {
        TtsPlaybackService.step(-1);
      }
    }).catch((e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'avsession setup failed: %{public}s', `${e}`);
    });
  }

  private static emitState(): void {
    TtsPlaybackService.events.emitState(TtsPlaybackService.playingState, TtsPlaybackService.pausedState,
      TtsPlaybackService.currentMangaId(), TtsPlaybackService.currentChapterId());
  }

  // 章节正文：离线（下载缓存）优先，其次经源在线获取
  private static async fetchText(manga: MangaRecord, chapter: ChapterRecord): Promise<string> {
    const local = DownloadService.localText(manga.id, chapter.id);
    if (local !== '') {
      return Util.readTextAuto(local);
    }
    const source = SourceRegistry.get(manga.sourceKey);
    if (source === undefined) {
      return '';
    }
    return await source.getChapterText(chapter.url);
  }
}
