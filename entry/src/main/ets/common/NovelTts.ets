import { textToSpeech } from '@kit.CoreSpeechKit';
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
  }

  onComplete(requestId: string, response: textToSpeech.CompleteResponse): void {
    // type=0 合成结束（先于播报结束到达）：不能据此推进，否则段落刚开口就被切走；
    // 仅启动 isBusy 轮询兜底（防个别引擎只回调合成结束不回调播报结束）
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
  // 播报结束兜底轮询定时器（合成结束回调后启动，播报结束回调到达时取消）
  private static pollTimer: number = -1;
  private static lang: string = 'zh-CN';
  private static starting: boolean = false;
  static events: TtsEvents = new TtsEvents();

  static isPlaying(): boolean {
    return !NovelTts.stopped;
  }

  // 页面销毁时复位回调，避免向已卸载页面派发事件
  static resetEvents(): void {
    NovelTts.events = new TtsEvents();
  }

  // 从 startPara 段开始顺序播报 paras（空段自动跳过）
  static async start(paras: string[], startPara: number, lang: string): Promise<boolean> {
    if (NovelTts.starting) {
      return false;
    }
    NovelTts.starting = true;
    try {
      NovelTts.lang = lang;
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
      NovelTts.speakCurrent();
      return true;
    } finally {
      NovelTts.starting = false;
    }
  }

  static stop(): void {
    NovelTts.stopped = true;
    NovelTts.activeReq = '';
    NovelTts.clearDonePoll();
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
    if (NovelTts.engine !== undefined) {
      try {
        NovelTts.engine.shutdown();
      } catch (_e) {
      }
      NovelTts.engine = undefined;
      NovelTts.engineLang = '';
    }
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
        NovelTts.events.onError('engine busy');
      }
    }
  }

  private static retrySpeak(oldReq: string): void {
    if (NovelTts.stopped || NovelTts.activeReq !== oldReq) {
      return;
    }
    NovelTts.speakCurrent();
  }

  // 引擎回调入口（TtsListener 转交，包内可见）
  static onChunkDone(requestId: string): void {
    // 播报结束已确认，取消兜底轮询
    NovelTts.clearDonePoll();
    if (NovelTts.stopped || requestId !== NovelTts.activeReq) {
      return;
    }
    NovelTts.activeReq = '';
    NovelTts.pos += 1;
    NovelTts.speakCurrent();
  }

  // 合成结束回调（type=0）：播报仍在进行，启动轮询等待引擎空闲（兜底个别引擎不再回调播报结束）
  static onChunkSynthDone(requestId: string): void {
    if (NovelTts.stopped || requestId !== NovelTts.activeReq) {
      return;
    }
    NovelTts.scheduleDonePoll(requestId);
  }

  private static scheduleDonePoll(requestId: string): void {
    NovelTts.clearDonePoll();
    NovelTts.pollTimer = setTimeout(() => {
      NovelTts.pollTimer = -1;
      if (NovelTts.stopped || requestId !== NovelTts.activeReq) {
        return;
      }
      const eng = NovelTts.engine;
      let busy = false;
      if (eng !== undefined) {
        try {
          busy = eng.isBusy();
        } catch (_e) {
          busy = false;
        }
      }
      if (busy) {
        NovelTts.scheduleDonePoll(requestId);
      } else {
        NovelTts.onChunkDone(requestId);
      }
    }, 400);
  }

  private static clearDonePoll(): void {
    if (NovelTts.pollTimer !== -1) {
      clearTimeout(NovelTts.pollTimer);
      NovelTts.pollTimer = -1;
    }
  }

  static onSpeakError(requestId: string, message: string): void {
    if (NovelTts.stopped) {
      return;
    }
    NovelTts.stopped = true;
    NovelTts.activeReq = '';
    NovelTts.events.onError(message);
  }
}
