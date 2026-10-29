// 小牛翻译开放平台（BYOK：apikey）：
// GET api.niutrans.com/NiuTransServer/translationX?from=&to=&src_text=&apikey=
// 多行文本以 \n 合并请求，tgt_text 按行回传对齐；错误体 {error_code, error_msg}
// 文档：https://niutrans.com/documents/contents/trans_txt
// 注意：无独立繁体语言码时使用小牛「big」繁体中文码（zh-Hant→big）
import { Http } from '../net/Http';
import { Settings } from '../common/Settings';
import { TranslationProvider } from './TranslationProvider';
import { Log } from '../common/Log';

// translationX 响应：成功 {tgt_text}，失败 {error_code, error_msg}
interface NiuTransResp {
  tgt_text?: string;
  error_code?: string;
  error_msg?: string;
}

export class NiutransProvider implements TranslationProvider {
  id: string = 'niutrans';
  // 单请求合并文本字符上限（保守）
  private static readonly MAX_BATCH_CHARS: number = 1000;
  private static readonly CHUNK_GAP_MS: number = 300;
  private static readonly ENDPOINT: string = 'https://api.niutrans.com/NiuTransServer/translationX';

  isConfigured(): boolean {
    return Settings.getTransNiutransApikey() !== '';
  }

  // 小牛支持全部候选目标语言（zh-Hant→big 由 mapLang 处理）
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
    // 按字符总量分块
    const chunks: number[][] = [];
    let cur: number[] = [];
    let curLen: number = 0;
    for (const pos of positions) {
      const len: number = texts[pos].length;
      if (cur.length > 0 && curLen + len > NiutransProvider.MAX_BATCH_CHARS) {
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
        await NiutransProvider.delay(NiutransProvider.CHUNK_GAP_MS);
      }
      const chunk: number[] = chunks[c];
      const batch: string[] = [];
      for (const pos of chunk) {
        batch.push(texts[pos]);
      }
      const translated: string[] = await NiutransProvider.translateChunk(batch, from, to);
      for (let j = 0; j < chunk.length; j++) {
        out[chunk[j]] = translated[j];
      }
    }
    return out;
  }

  // 单块请求：合并 \n 请求；tgt_text 按 \n 拆回对齐，失配逐条重译兜底
  private static async translateChunk(batch: string[], from: string, to: string): Promise<string[]> {
    const apikey: string = Settings.getTransNiutransApikey();
    const url: string = NiutransProvider.ENDPOINT +
      `?from=${encodeURIComponent(NiutransProvider.mapSourceLang(from))}` +
      `&to=${encodeURIComponent(NiutransProvider.mapTargetLang(to))}` +
      `&src_text=${encodeURIComponent(batch.join('\n'))}` +
      `&apikey=${encodeURIComponent(apikey)}`;
    const resp = await Http.requestRaw('GET', url, '', undefined);
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`niutrans_http_${resp.code}`);
    }
    let parsed: NiuTransResp;
    try {
      parsed = JSON.parse(resp.body) as NiuTransResp;
    } catch (_e) {
      throw new Error('niutrans_bad_response');
    }
    if (typeof parsed.error_code === 'string' && parsed.error_code !== '') {
      throw new Error(`niutrans_${NiutransProvider.sanitize(parsed.error_code)}`);
    }
    const tgt: string | undefined = parsed.tgt_text;
    if (typeof tgt !== 'string' || tgt === '') {
      throw new Error('niutrans_empty_result');
    }
    // 单条输入直接返回
    if (batch.length === 1) {
      return [tgt];
    }
    const lines: string[] = tgt.split('\n');
    if (lines.length === batch.length) {
      return lines;
    }
    Log.warn('NiutransProvider', `batch misaligned (${lines.length}/${batch.length}), fallback to per-text`);
    return NiutransProvider.translateOneByOne(batch, from, to);
  }

  // 行对齐失败时的逐条重译
  private static async translateOneByOne(texts: string[], from: string, to: string): Promise<string[]> {
    const out: string[] = [];
    for (const text of texts) {
      if (out.length > 0) {
        await NiutransProvider.delay(NiutransProvider.CHUNK_GAP_MS);
      }
      const single: string[] = await NiutransProvider.translateChunk([text], from, to);
      out.push(single.length > 0 ? single[0] : '');
    }
    return out;
  }

  // 目标语言码：zh-Hant→big（小牛繁体中文码），其余原样
  private static mapTargetLang(lang: string): string {
    if (lang === 'zh-Hant') {
      return 'big';
    }
    return lang;
  }

  // 源语言码：空/auto → auto；zh-Hant→big；其余原样
  private static mapSourceLang(lang: string): string {
    if (lang === '' || lang === 'auto') {
      return 'auto';
    }
    if (lang === 'zh-Hant') {
      return 'big';
    }
    return lang;
  }

  // 错误码清洗：保留字母数字（避免服务端消息拼接进错误字符串）
  private static sanitize(code: string): string {
    return code.replace(/[^A-Za-z0-9_.-]/g, '');
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
