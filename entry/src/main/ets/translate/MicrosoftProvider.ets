// 微软必应翻译（免费逆向：Bing 网页版 ttranslatev3 接口，与项目 DeepL/Google 逆向策略一致）。
// 官方 Edge auth 免费端点已下线，改走网页会话流程：
// 1. GET cn.bing.com/translator 解析 IG / IID(translator.xxxx) / params_AbusePreventionHelper（key+token）
// 2. POST cn.bing.com/ttranslatev3?isVertical=1&&IG=<ig>&IID=<iid>.<n>
//    form：fromLang/to/text/tryFetchingGenderDebiasedTranslations/token/key
// 3. 响应 [{translations:[{text}], detectedLanguage}]；statusCode 205=会话过期需刷新重试
// 多行文本以 \n 合并请求，译文按行回传对齐；Bing 会话凭证有效期约 1 小时（页面内 token ttl）。
import { Http } from '../net/Http';
import { TranslationProvider } from './TranslationProvider';
import { Log } from '../common/Log';

// ttranslatev3 单条响应
interface BingTranslationItem {
  text?: string;
}

interface BingDetectedLanguage {
  language?: string;
}

interface BingResultItem {
  translations?: BingTranslationItem[];
  detectedLanguage?: BingDetectedLanguage;
}

// 会话内凭证（页面解析结果，进程级缓存）
interface BingSession {
  ig: string;
  iidBase: string;
  key: string;
  token: string;
  fetchedAt: number;
  reqCounter: number;
}

export class MicrosoftProvider implements TranslationProvider {
  id: string = 'microsoft';
  // 单请求文本总长上限（保守值，网页接口对超长文本易 400）
  private static readonly MAX_BATCH_CHARS: number = 900;
  // 分块请求间隔（毫秒）
  private static readonly CHUNK_GAP_MS: number = 400;
  // 会话有效期（毫秒）：token ttl 为 1 小时，提前 10 分钟刷新
  private static readonly SESSION_TTL_MS: number = 50 * 60 * 1000;
  private static readonly PAGE_URL: string = 'https://cn.bing.com/translator';
  private static readonly API_URL: string = 'https://cn.bing.com/ttranslatev3';
  // 进程级会话缓存（引擎单实例，串行队列保证无并发竞争）
  private static session: BingSession | undefined = undefined;

  isConfigured(): boolean {
    return true;
  }

  // Bing 支持全部候选目标语言（zh-Hant 原生支持）
  supports(_from: string, _to: string): boolean {
    return true;
  }

  async translate(texts: string[], from: string, to: string): Promise<string[]> {
    const out: string[] = texts.slice();
    const positions: number[] = [];
    for (let i = 0; i < texts.length; i++) {
      if (texts[i].trim() !== '') {
        positions.push(i);
      }
    }
    if (positions.length === 0) {
      return out;
    }
    // 按字符总量分块（网页接口对超长合并文本不稳定）
    const chunks: number[][] = [];
    let cur: number[] = [];
    let curLen: number = 0;
    for (const pos of positions) {
      const len: number = texts[pos].length;
      if (cur.length > 0 && curLen + len > MicrosoftProvider.MAX_BATCH_CHARS) {
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
    for (let c = 0; c < chunks.length; c++) {
      if (c > 0) {
        await MicrosoftProvider.delay(MicrosoftProvider.CHUNK_GAP_MS);
      }
      const chunk: number[] = chunks[c];
      const batch: string[] = [];
      for (const pos of chunk) {
        batch.push(texts[pos]);
      }
      const translated: string[] = await MicrosoftProvider.translateChunk(batch, from, to, false);
      for (let j = 0; j < chunk.length; j++) {
        out[chunk[j]] = translated[j];
      }
    }
    return out;
  }

  // 单块请求：合并 \n 请求；行对齐失败时逐条重译兜底；205 会话过期强制刷新重试一次
  private static async translateChunk(batch: string[], from: string, to: string, retried: boolean): Promise<string[]> {
    let session: BingSession = await MicrosoftProvider.ensureSession(false);
    const body: string = 'fromLang=' + encodeURIComponent(MicrosoftProvider.mapSourceLang(from)) +
      '&to=' + encodeURIComponent(MicrosoftProvider.mapTargetLang(to)) +
      '&text=' + encodeURIComponent(batch.join('\n')) +
      '&tryFetchingGenderDebiasedTranslations=true' +
      '&token=' + encodeURIComponent(session.token) +
      '&key=' + encodeURIComponent(session.key);
    const url: string = MicrosoftProvider.API_URL +
      `?isVertical=1&&IG=${session.ig}&IID=${session.iidBase}.${session.reqCounter++}`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
      'Referer': MicrosoftProvider.PAGE_URL,
      'Origin': 'https://cn.bing.com'
    };
    const resp = await Http.requestRaw('POST', url, body, headers);
    // 会话过期：刷新页面凭证后重试一次
    if (resp.body.indexOf('"statusCode":205') >= 0) {
      if (retried) {
        throw new Error('microsoft_session_expired');
      }
      await MicrosoftProvider.ensureSession(true);
      return MicrosoftProvider.translateChunk(batch, from, to, true);
    }
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`microsoft_http_${resp.code}`);
    }
    let parsed: BingResultItem[];
    try {
      parsed = JSON.parse(resp.body) as BingResultItem[];
    } catch (_e) {
      throw new Error('microsoft_bad_response');
    }
    if (!Array.isArray(parsed) || parsed.length === 0) {
      throw new Error('microsoft_bad_response');
    }
    const items: BingTranslationItem[] | undefined = parsed[0].translations;
    if (items === undefined || items.length === 0) {
      throw new Error('microsoft_empty_result');
    }
    const text: string | undefined = items[0].text;
    if (typeof text !== 'string' || text === '') {
      throw new Error('microsoft_empty_result');
    }
    // 单条输入直接返回（译文可能含换行，不参与对齐拆分）
    if (batch.length === 1) {
      return [text];
    }
    const lines: string[] = text.split('\n');
    if (lines.length === batch.length) {
      return lines;
    }
    Log.warn('MicrosoftProvider', `batch misaligned (${lines.length}/${batch.length}), fallback to per-text`);
    return MicrosoftProvider.translateOneByOne(batch, from, to);
  }

  // 行对齐失败时的逐条重译
  private static async translateOneByOne(texts: string[], from: string, to: string): Promise<string[]> {
    const out: string[] = [];
    for (const text of texts) {
      if (out.length > 0) {
        await MicrosoftProvider.delay(MicrosoftProvider.CHUNK_GAP_MS);
      }
      const single: string[] = await MicrosoftProvider.translateChunk([text], from, to, false);
      out.push(single.length > 0 ? single[0] : '');
    }
    return out;
  }

  // 会话凭证：无缓存/过期时拉取 translator 页面解析；force 时强制刷新
  private static async ensureSession(force: boolean): Promise<BingSession> {
    const held: BingSession | undefined = MicrosoftProvider.session;
    if (!force && held !== undefined && Date.now() - held.fetchedAt < MicrosoftProvider.SESSION_TTL_MS) {
      return held;
    }
    const headers: Record<string, string> = {
      'Referer': 'https://cn.bing.com/',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    };
    const resp = await Http.requestRaw('GET', MicrosoftProvider.PAGE_URL, '', headers);
    if (resp.code < 200 || resp.code >= 300) {
      // 旧会话仍可能可用：刷新失败且存在旧会话时降级沿用
      if (held !== undefined) {
        return held;
      }
      throw new Error(`microsoft_page_${resp.code}`);
    }
    const igExec: RegExpExecArray | null = /IG:"([^"]+)"/.exec(resp.body);
    const iidExec: RegExpExecArray | null = /data-iid="translator\.(\d+)"/.exec(resp.body);
    const abuseExec: RegExpExecArray | null =
      /params_AbusePreventionHelper\s*=\s*\[\s*(\d+)\s*,\s*"([^"]*)"\s*,\s*(\d+)\s*\]/.exec(resp.body);
    if (igExec === null || iidExec === null || abuseExec === null) {
      if (held !== undefined) {
        return held;
      }
      throw new Error('microsoft_parse_failed');
    }
    const fresh: BingSession = {
      ig: igExec[1],
      iidBase: `translator.${iidExec[1]}`,
      key: abuseExec[1],
      token: abuseExec[2],
      fetchedAt: Date.now(),
      reqCounter: 1
    };
    MicrosoftProvider.session = fresh;
    return fresh;
  }

  // 目标语言码（Bing：zh→zh-Hans，zh-Hant 原样，其余原样）
  private static mapTargetLang(lang: string): string {
    if (lang === 'zh') {
      return 'zh-Hans';
    }
    return lang;
  }

  // 源语言码：auto→auto-detect；zh→zh-Hans；zh-Hant 原样；其余原样
  private static mapSourceLang(lang: string): string {
    if (lang === '' || lang === 'auto') {
      return 'auto-detect';
    }
    if (lang === 'zh') {
      return 'zh-Hans';
    }
    return lang;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
