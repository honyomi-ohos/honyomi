import { textToSpeech } from '@kit.CoreSpeechKit';
import { common, wantAgent } from '@kit.AbilityKit';
import type { WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Settings } from './Settings';

// 听书事件回调集合（页面在 aboutToAppear 中接管，aboutToDisappear 中复位）
export class TtsEvents {
  onParaStart: (paraIdx: number) => void = (_paraIdx: number): void => {
  };
  onAllDone: () => void = (): void => {
  };
  onError: (message: string) => void = (_message: string): void => {
  };
}

// 引擎回调（转交 NovelTts 静态方法处理）
class TtsListener implements textToSpeech.SpeakListener {
  onStart(requestId: string, response: textToSpeech.StartResponse): void {
    NovelTts.onSpeakStart(requestId);
  }

  onComplete(requestId: string, response: textToSpeech.CompleteResponse): void {
    // type=0 合成结束（先于播报结束到达）：播报仍在进行，仅标记请求存活，不能据此推进，
    // 否则段落刚开口就被切走；type=1 播报结束才推进下一块
    if (response.type === 0) {
      NovelTts.onChunkSynthDone(requestId);
      return;
    }
    NovelTts.onChunkDone(requestId);
  }

  onStop(requestId: string, response: textToSpeech.StopResponse): void {
  }

  onData(requestId: string, audio: ArrayBuffer, response: textToSpeech.SynthesisResponse): void {
  }

  onError(requestId: string, errorCode: number, errorMessage: string): void {
    NovelTts.onSpeakError(requestId, `(${errorCode}) ${errorMessage}`);
  }
}

// 系统文本转语音（Core Speech Kit）封装：小说听书
// 引擎懒创建并按语种（zh-CN / en-US 自动识别）复用；正文按段落切分为 ≤900 字的小块逐块播报，
// 单块播完自动续播下一块，全部播完回调 onAllDone（页面据此自动进入下一章）。
// 播报期间申请 AUDIO_PLAYBACK 长时任务避免应用退后台被挂起（否则播报十几分钟后会被系统中断）；
// 另有看门狗：迟迟未开始播报则重建引擎重发；播完但未收到结束回调则按 isBusy 兜底推进。
export class NovelTts {
  private static engine: textToSpeech.TextToSpeechEngine | undefined = undefined;
  private static engineLang: string = '';
  private static chunks: string[] = [];
  private static chunkPara: number[] = [];
  private static pos: number = 0;
  private static stopped: boolean = true;
  private static reqSeq: number = 0;
  private static activeReq: string = '';
  private static retries: number = 0;
  private static lang: string = 'zh-CN';
  private static starting: boolean = false;
  // 看门狗（2s 一查）
  private static keepAlive: number = -1;
  private static startReceived: boolean = false;
  private static issueAt: number = 0;
  private static busyFalseStreak: number = 0;
  private static engineRetries: number = 0;
  // 后台长任务
  private static ctx: common.UIAbilityContext | undefined = undefined;
  private static taskRequested: boolean = false;
  private static taskRunning: boolean = false;
  static events: TtsEvents = new TtsEvents();

  static isPlaying(): boolean {
    return !NovelTts.stopped;
  }

  // 页面销毁时复位回调，避免向已卸载页面派发事件
  static resetEvents(): void {
    NovelTts.events = new TtsEvents();
  }

  // 从 startPara 段开始顺序播报 paras（空段自动跳过）
  static async start(paras: string[], startPara: number, lang: string,
    context: common.UIAbilityContext): Promise<boolean> {
    if (NovelTts.starting) {
      return false;
    }
    NovelTts.starting = true;
    try {
      NovelTts.lang = lang;
      NovelTts.ctx = context;
      NovelTts.buildChunks(paras);
      if (NovelTts.chunks.length === 0) {
        return false;
      }
      NovelTts.pos = 0;
      for (let i = 0; i < NovelTts.chunkPara.length; i++) {
        if (NovelTts.chunkPara[i] >= startPara) {
          NovelTts.pos = i;
          break;
        }
      }
      const ready = await NovelTts.ensureEngine();
      if (!ready) {
        return false;
      }
      NovelTts.stopped = false;
      NovelTts.startTtsTask();
      NovelTts.speakCurrent();
      return true;
    } finally {
      NovelTts.starting = false;
    }
  }

  static stop(): void {
    NovelTts.stopped = true;
    NovelTts.activeReq = '';
    NovelTts.clearKeepAlive();
    NovelTts.stopTtsTask();
    const eng = NovelTts.engine;
    if (eng !== undefined) {
      try {
        eng.stop();
      } catch (_e) {
      }
    }
  }

  // 当前正在朗读（或待播）的段落，用于语速切换后从当前位置续播
  static currentPara(): number {
    if (NovelTts.pos >= 0 && NovelTts.pos < NovelTts.chunkPara.length) {
      return NovelTts.chunkPara[NovelTts.pos];
    }
    return 0;
  }

  private static async ensureEngine(): Promise<boolean> {
    if (NovelTts.engine !== undefined && NovelTts.engineLang === NovelTts.lang) {
      return true;
    }
    NovelTts.killEngine();
    // 官方文档推荐音色优先，不可用时回退默认音色
    const persons: number[] = NovelTts.lang === 'en-US' ? [8, 0] : [3, 0];
    for (let p = 0; p < persons.length; p++) {
      try {
        const extra: Record<string, Object> = {
          'style': 'interaction-broadcast',
          'locate': 'CN',
          'name': 'novel-tts',
          'isBackStage': true
        };
        const params: textToSpeech.CreateEngineParams = {
          language: NovelTts.lang,
          person: persons[p],
          online: 1,
          extraParams: extra
        };
        const eng = await textToSpeech.createEngine(params);
        eng.setListener(new TtsListener());
        NovelTts.engine = eng;
        NovelTts.engineLang = NovelTts.lang;
        return true;
      } catch (_e) {
        // 换下一个音色重试
      }
    }
    return false;
  }

  // 丢弃当前引擎实例（引擎失效/出错时调用，下次 ensureEngine 重建全新实例）
  private static killEngine(): void {
    if (NovelTts.engine !== undefined) {
      try {
        NovelTts.engine.shutdown();
      } catch (_e) {
      }
      NovelTts.engine = undefined;
      NovelTts.engineLang = '';
    }
  }

  // 段落 → 播报块（≤900 字；超长段按句末标点切分）；chunkPara 记录块所属段落
  private static buildChunks(paras: string[]): void {
    const chunks: string[] = [];
    const chunkPara: number[] = [];
    const maxLen = 900;
    for (let i = 0; i < paras.length; i++) {
      let para = paras[i].trim();
      if (para === '') {
        continue;
      }
      while (para.length > 0) {
        if (para.length <= maxLen) {
          chunks.push(para);
          chunkPara.push(i);
          break;
        }
        let cut = -1;
        const enders: string[] = ['。', '！', '？', '；', '…', '.', '!', '?', ';'];
        for (let e = 0; e < enders.length; e++) {
          const idx = para.lastIndexOf(enders[e], maxLen);
          if (idx > 200) {
            cut = idx + 1;
            break;
          }
        }
        if (cut <= 0) {
          cut = maxLen;
        }
        chunks.push(para.substring(0, cut));
        chunkPara.push(i);
        para = para.substring(cut).trim();
      }
    }
    NovelTts.chunks = chunks;
    NovelTts.chunkPara = chunkPara;
  }

  private static speakCurrent(): void {
    const eng = NovelTts.engine;
    if (NovelTts.stopped || eng === undefined) {
      return;
    }
    if (NovelTts.pos >= NovelTts.chunks.length) {
      NovelTts.stopped = true;
      NovelTts.clearKeepAlive();
      NovelTts.stopTtsTask();
      NovelTts.events.onAllDone();
      return;
    }
    const text = NovelTts.chunks[NovelTts.pos];
    if (text === '') {
      NovelTts.pos += 1;
      NovelTts.speakCurrent();
      return;
    }
    NovelTts.events.onParaStart(NovelTts.chunkPara[NovelTts.pos]);
    const reqId = `novelTts-${++NovelTts.reqSeq}`;
    NovelTts.activeReq = reqId;
    NovelTts.startReceived = false;
    NovelTts.issueAt = Date.now();
    NovelTts.busyFalseStreak = 0;
    const extra: Record<string, Object> = {
      'speed': Settings.getNovelTtsSpeed(),
      'volume': 2,
      'pitch': 1,
      'languageContext': NovelTts.lang,
      'audioType': 'pcm',
      'queueMode': 1,
      'playType': 1
    };
    const params: textToSpeech.SpeakParams = {
      requestId: reqId,
      extraParams: extra
    };
    try {
      eng.speak(text, params);
      NovelTts.retries = 0;
    } catch (_e) {
      // 引擎忙（刚 stop 完等）时稍后重试，最多 3 次
      if (NovelTts.retries < 3) {
        NovelTts.retries += 1;
        setTimeout(() => {
          NovelTts.retrySpeak(reqId);
        }, 250);
      } else {
        NovelTts.stopped = true;
        NovelTts.activeReq = '';
        NovelTts.clearKeepAlive();
        NovelTts.stopTtsTask();
        // 引擎可能已失效，丢弃以便下次重建
        NovelTts.killEngine();
        NovelTts.events.onError('engine busy');
      }
      return;
    }
    NovelTts.scheduleKeepAlive();
  }

  private static retrySpeak(oldReq: string): void {
    if (NovelTts.stopped || NovelTts.activeReq !== oldReq) {
      return;
    }
    NovelTts.speakCurrent();
  }

  // 引擎回调入口（TtsListener 转交，包内可见）
  // 播报真正开始：看门狗据此区分"尚未开始"与"播报中"
  static onSpeakStart(requestId: string): void {
    if (requestId === NovelTts.activeReq) {
      NovelTts.startReceived = true;
      NovelTts.engineRetries = 0;
    }
  }

  // 播报结束（type=1）：推进下一块
  static onChunkDone(requestId: string): void {
    NovelTts.clearKeepAlive();
    if (NovelTts.stopped || requestId !== NovelTts.activeReq) {
      return;
    }
    NovelTts.activeReq = '';
    NovelTts.pos += 1;
    NovelTts.speakCurrent();
  }

  // 合成结束（type=0）：播报仍在进行，仅标记请求存活（允许看门狗按 isBusy 判定完成）
  static onChunkSynthDone(requestId: string): void {
    if (NovelTts.stopped || requestId !== NovelTts.activeReq) {
      return;
    }
    NovelTts.startReceived = true;
  }

  static onSpeakError(requestId: string, message: string): void {
    if (NovelTts.stopped) {
      return;
    }
    NovelTts.stopped = true;
    NovelTts.activeReq = '';
    NovelTts.clearKeepAlive();
    NovelTts.stopTtsTask();
    // 出错后引擎状态不可信，丢弃以便下次重建
    NovelTts.killEngine();
    NovelTts.events.onError(message);
  }

  // 看门狗：每 2s 检查一次当前块是否仍在正常播报
  private static scheduleKeepAlive(): void {
    NovelTts.clearKeepAlive();
    NovelTts.keepAlive = setInterval(() => {
      NovelTts.checkAlive();
    }, 2000);
  }

  private static clearKeepAlive(): void {
    if (NovelTts.keepAlive !== -1) {
      clearInterval(NovelTts.keepAlive);
      NovelTts.keepAlive = -1;
    }
  }

  private static checkAlive(): void {
    if (NovelTts.stopped || NovelTts.activeReq === '' || NovelTts.keepAlive === -1) {
      NovelTts.clearKeepAlive();
      return;
    }
    const eng = NovelTts.engine;
    if (eng === undefined) {
      NovelTts.clearKeepAlive();
      return;
    }
    if (!NovelTts.startReceived) {
      // 迟迟未开始播报：引擎大概率已失效（如后台被系统回收），重建后重发当前块
      if (Date.now() - NovelTts.issueAt > 15000) {
        NovelTts.recoverEngine();
      }
      return;
    }
    let busy = false;
    try {
      busy = eng.isBusy();
    } catch (_e) {
      busy = false;
    }
    if (busy) {
      NovelTts.busyFalseStreak = 0;
      return;
    }
    NovelTts.busyFalseStreak += 1;
    // 连续两次空闲仍未收到播报结束回调：视为本块已播完，推进（兜底回调丢失）
    if (NovelTts.busyFalseStreak >= 2) {
      NovelTts.onChunkDone(NovelTts.activeReq);
    }
  }

  // 引擎失效自愈：销毁后重建，并从当前块重发（不改变 pos）
  private static recoverEngine(): void {
    if (NovelTts.engineRetries >= 2) {
      NovelTts.stopped = true;
      NovelTts.activeReq = '';
      NovelTts.clearKeepAlive();
      NovelTts.stopTtsTask();
      NovelTts.killEngine();
      NovelTts.events.onError('engine stalled');
      return;
    }
    NovelTts.engineRetries += 1;
    NovelTts.clearKeepAlive();
    NovelTts.killEngine();
    NovelTts.ensureEngine().then((ok: boolean) => {
      if (NovelTts.stopped) {
        return;
      }
      if (ok) {
        NovelTts.speakCurrent();
      } else {
        NovelTts.stopped = true;
        NovelTts.activeReq = '';
        NovelTts.stopTtsTask();
        NovelTts.events.onError('engine unavailable');
      }
    });
  }

  // 后台长任务（AUDIO_PLAYBACK）：听书期间避免应用退后台/锁屏后被挂起导致播报被系统中断
  private static startTtsTask(): void {
    const ctx = NovelTts.ctx;
    if (NovelTts.taskRequested || ctx === undefined) {
      return;
    }
    NovelTts.taskRequested = true;
    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: ctx.abilityInfo.bundleName,
          abilityName: ctx.abilityInfo.name
        }
      ],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0
    };
    wantAgent.getWantAgent(info).then((agent: WantAgent): Promise<void> => {
      return backgroundTaskManager.startBackgroundRunning(ctx, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
    }).then((): void => {
      if (NovelTts.stopped) {
        // 申请期间用户已停止：立即撤销，避免残留长任务
        backgroundTaskManager.stopBackgroundRunning(ctx).catch((_e: BusinessError): void => {
        });
        return;
      }
      NovelTts.taskRunning = true;
    }).catch((_e: BusinessError): void => {
      // 长任务申请失败不阻断前台听书
      NovelTts.taskRequested = false;
    });
  }

  private static stopTtsTask(): void {
    const ctx = NovelTts.ctx;
    if (!NovelTts.taskRequested || ctx === undefined) {
      return;
    }
    NovelTts.taskRequested = false;
    if (!NovelTts.taskRunning) {
      return;
    }
    NovelTts.taskRunning = false;
    backgroundTaskManager.stopBackgroundRunning(ctx).then((): void => {
    }).catch((_e: BusinessError): void => {
    });
  }
}
