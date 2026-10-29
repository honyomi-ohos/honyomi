// 翻译服务：缓存（引擎无关）→ 按优先级逐引擎尝试 → 失败回退下一家。
// - 缓存与「原文+方向」绑定：同一句原文无论走哪家只翻一次，超限整体清空
// - 每引擎独立串行队列 + 最小请求间隔（百度/有道标准版 QPS=1 保护）
// - 引擎优先级持久化为 CSV（Settings.transEngineOrder），设置页可调序
import { TranslationProvider } from './TranslationProvider';
import { BaiduProvider } from './BaiduProvider';
import { YoudaoProvider } from './YoudaoProvider';
import { CaiyunProvider } from './CaiyunProvider';
import { GoogleProvider } from './GoogleProvider';
import { DeeplProvider } from './DeepLProvider';
import { MicrosoftProvider } from './MicrosoftProvider';
import { TencentProvider } from './TencentProvider';
import { VolcanoProvider } from './VolcanoProvider';
import { NiutransProvider } from './NiuTransProvider';
import { Settings } from '../common/Settings';
import { Log } from '../common/Log';

// 设置页展示用：引擎 id + 配置状态
export interface TransEngineInfo {
  id: string;
  configured: boolean;
}

// 单引擎串行队列：排队执行 + 请求间保持最小间隔
class EngineGate {
  private queue: Promise<void> = Promise.resolve();
  private lastAt: number = 0;
  private minGapMs: number = 0;

  constructor(minGapMs: number) {
    this.minGapMs = minGapMs;
  }

  run<T>(task: () => Promise<T>): Promise<T> {
    const result: Promise<T> = this.queue.then(async (): Promise<T> => {
      const waitMs: number = this.lastAt + this.minGapMs - Date.now();
      if (waitMs > 0) {
        await EngineGate.delay(waitMs);
      }
      this.lastAt = Date.now();
      return task();
    });
    // 队列只关心时序：吞掉任务结果/错误，错误由调用方持有的 result 接收
    this.queue = result.then((): void => {
    }, (): void => {
    });
    return result;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}

export class TranslationService {
  // 全部引擎 id（默认优先级顺序；需密钥引擎在前，免密钥引擎殿后）
  static readonly ENGINE_IDS: string[] =
    ['baidu', 'caiyun', 'youdao', 'tencent', 'volcano', 'niutrans', 'deepl', 'microsoft', 'google'];
  // 免密钥引擎 id（其余均需密钥）：顺序调整/新引擎补位一律遵守「需密钥在前、免密钥殿后」
  private static readonly KEYLESS_IDS: string[] = ['deepl', 'microsoft', 'google'];
  // 各引擎请求最小间隔（毫秒，QPS 保护）
  private static readonly ENGINE_GAP_MS: Record<string, number> = {
    'baidu': 1100,
    'youdao': 1100,
    'caiyun': 600,
    'deepl': 1200,
    'google': 400,
    'tencent': 600,
    'volcano': 600,
    'niutrans': 600,
    'microsoft': 800
  };
  private static readonly CACHE_LIMIT: number = 2000;
  // 长文分块上限：单块段落数 / 单块字符总量（引擎单请求长度受限：百度/有道 q 上限、DeepL 匿名 1500）
  private static readonly PARAGRAPH_CHUNK_COUNT: number = 20;
  private static readonly PARAGRAPH_CHUNK_CHARS: number = 1200;

  private static readonly BAIDU: BaiduProvider = new BaiduProvider();
  private static readonly YOUDAO: YoudaoProvider = new YoudaoProvider();
  private static readonly CAIYUN: CaiyunProvider = new CaiyunProvider();
  private static readonly GOOGLE: GoogleProvider = new GoogleProvider();
  private static readonly DEEPL: DeeplProvider = new DeeplProvider();
  private static readonly MICROSOFT: MicrosoftProvider = new MicrosoftProvider();
  private static readonly TENCENT: TencentProvider = new TencentProvider();
  private static readonly VOLCANO: VolcanoProvider = new VolcanoProvider();
  private static readonly NIUTRANS: NiutransProvider = new NiutransProvider();

  // 引擎无关结果缓存：from>to|原文 → 译文
  private static cache: Map<string, string> = new Map<string, string>();
  // 各引擎串行队列
  private static gates: Map<string, EngineGate> = new Map<string, EngineGate>();

  // 生效引擎顺序：持久化 CSV 校验过滤 + 去重，未列出的新引擎按分类补位
  // （需密钥引擎插到首个免密钥引擎之前，免密钥引擎一律补到末尾，
  // 保证任何迁移路径下顺序都满足「需密钥在前、免密钥殿后」）
  static effectiveOrder(): string[] {
    const saved: string[] = Settings.getTransEngineOrder().split(',');
    const order: string[] = [];
    for (const id of saved) {
      if (TranslationService.ENGINE_IDS.indexOf(id) >= 0 && order.indexOf(id) < 0) {
        order.push(id);
      }
    }
    for (const id of TranslationService.ENGINE_IDS) {
      if (order.indexOf(id) >= 0) {
        continue;
      }
      if (TranslationService.KEYLESS_IDS.indexOf(id) >= 0) {
        order.push(id);
      } else {
        TranslationService.insertBeforeKeyless(order, id);
      }
    }
    return order;
  }

  // 需密钥引擎插入位置：现有顺序中首个免密钥引擎之前；无免密钥引擎则追加末尾
  private static insertBeforeKeyless(order: string[], id: string): void {
    let at: number = order.length;
    for (let i = 0; i < order.length; i++) {
      if (TranslationService.KEYLESS_IDS.indexOf(order[i]) >= 0) {
        at = i;
        break;
      }
    }
    order.splice(at, 0, id);
  }

  // 引擎配置状态列表（设置页展示，按生效优先级排序）
  static engineInfos(): TransEngineInfo[] {
    const infos: TransEngineInfo[] = [];
    for (const id of TranslationService.effectiveOrder()) {
      const info: TransEngineInfo = { id: id, configured: TranslationService.providerOf(id).isConfigured() };
      infos.push(info);
    }
    return infos;
  }

  static isEngineConfigured(id: string): boolean {
    return TranslationService.providerOf(id).isConfigured();
  }

  // 单条翻译（设置页连通性测试等轻量场景）
  static async translateText(text: string, from: string, to: string): Promise<string> {
    const out: string[] = await TranslationService.translatePage([text], from, to);
    return out.length > 0 ? out[0] : '';
  }

  // 长文段落翻译：内部按「段落数 + 字符总量」分块逐块调用 translatePage（复用其缓存与引擎回退）；
  // 空白段落按位原样保留；onProgress 汇报进度；shouldStop 返回 true 时中止剩余块（reject trans_cancelled）
  static async translateParagraphs(paras: string[], from: string, to: string,
    onProgress: (done: number, total: number) => void,
    shouldStop: () => boolean): Promise<string[]> {
    const out: string[] = paras.slice();
    const positions: number[] = [];
    for (let i = 0; i < paras.length; i++) {
      if (paras[i].trim() !== '') {
        positions.push(i);
      }
    }
    const total: number = positions.length;
    if (total === 0) {
      return out;
    }
    const chunks: number[][] = [];
    let cur: number[] = [];
    let curLen: number = 0;
    for (const pos of positions) {
      const len: number = paras[pos].length;
      if (cur.length > 0 && (cur.length >= TranslationService.PARAGRAPH_CHUNK_COUNT
        || curLen + len > TranslationService.PARAGRAPH_CHUNK_CHARS)) {
        chunks.push(cur);
        cur = [];
        curLen = 0;
      }
      cur.push(pos);
      curLen += len;
    }
    if (cur.length > 0) {
      chunks.push(cur);
    }
    let done: number = 0;
    for (const chunk of chunks) {
      if (shouldStop()) {
        throw new Error('trans_cancelled');
      }
      const batch: string[] = [];
      for (const pos of chunk) {
        batch.push(paras[pos]);
      }
      const translated: string[] = await TranslationService.translatePage(batch, from, to);
      for (let j = 0; j < chunk.length; j++) {
        out[chunk[j]] = translated[j];
      }
      done += chunk.length;
      onProgress(done, total);
    }
    return out;
  }

  // 页面文本批量翻译：texts 与返回数组一一对应；
  // 全部引擎失败时 reject 最后一个错误（调用方决定降级展示原文）
  static async translatePage(texts: string[], from: string, to: string): Promise<string[]> {
    const out: string[] = [];
    const pending: number[] = [];
    for (let i = 0; i < texts.length; i++) {
      const text: string = texts[i];
      if (text === '') {
        out.push('');
        continue;
      }
      const hit: string | undefined = TranslationService.cache.get(TranslationService.cacheKey(text, from, to));
      if (hit !== undefined) {
        out.push(hit);
      } else {
        out.push('');
        pending.push(i);
      }
    }
    if (pending.length === 0) {
      return out;
    }
    let lastErr: Error = new Error('trans_no_engine');
    for (const id of TranslationService.effectiveOrder()) {
      if (pending.length === 0) {
        break;
      }
      const provider: TranslationProvider = TranslationService.providerOf(id);
      if (!provider.isConfigured()) {
        continue;
      }
      // 不支持该翻译方向的引擎整链跳过（如彩云仅中文↔少数语种）
      if (!provider.supports(from, to)) {
        Log.warn('TransService', `engine ${id} skipped: unsupported direction ${from}>${to}`);
        continue;
      }
      const batch: string[] = [];
      for (const idx of pending) {
        batch.push(texts[idx]);
      }
      try {
        const gate: EngineGate = TranslationService.gateOf(id);
        const translated: string[] = await gate.run<string[]>((): Promise<string[]> => provider.translate(batch, from, to));
        if (translated.length !== batch.length) {
          throw new Error(`trans_result_mismatch|${id}`);
        }
        for (let j = 0; j < translated.length; j++) {
          const idx: number = pending[j];
          out[idx] = translated[j];
          TranslationService.cachePut(texts[idx], from, to, translated[j]);
        }
        pending.length = 0;
      } catch (e) {
        const err: Error = e as Error;
        Log.warn('TransService', `engine ${id} failed: ${err.message}`);
        lastErr = err;
      }
    }
    if (pending.length > 0) {
      throw lastErr;
    }
    return out;
  }

  private static providerOf(id: string): TranslationProvider {
    if (id === 'baidu') {
      return TranslationService.BAIDU;
    }
    if (id === 'youdao') {
      return TranslationService.YOUDAO;
    }
    if (id === 'caiyun') {
      return TranslationService.CAIYUN;
    }
    if (id === 'deepl') {
      return TranslationService.DEEPL;
    }
    if (id === 'microsoft') {
      return TranslationService.MICROSOFT;
    }
    if (id === 'tencent') {
      return TranslationService.TENCENT;
    }
    if (id === 'volcano') {
      return TranslationService.VOLCANO;
    }
    if (id === 'niutrans') {
      return TranslationService.NIUTRANS;
    }
    return TranslationService.GOOGLE;
  }

  private static gateOf(id: string): EngineGate {
    let gate: EngineGate | undefined = TranslationService.gates.get(id);
    if (gate === undefined) {
      const gap: number = TranslationService.ENGINE_GAP_MS[id];
      gate = new EngineGate(gap !== undefined ? gap : 500);
      TranslationService.gates.set(id, gate);
    }
    return gate;
  }

  private static cacheKey(text: string, from: string, to: string): string {
    return `${from}>${to}|${text}`;
  }

  private static cachePut(text: string, from: string, to: string, translated: string): void {
    if (TranslationService.cache.size >= TranslationService.CACHE_LIMIT) {
      TranslationService.cache.clear();
    }
    TranslationService.cache.set(TranslationService.cacheKey(text, from, to), translated);
  }
}
