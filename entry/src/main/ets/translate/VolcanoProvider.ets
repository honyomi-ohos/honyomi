// 火山引擎机器翻译（BYOK：AccessKeyID + SecretAccessKey）：
// TranslateText（Version 2020-06-01，open.volcengineapi.com），V4 风格 HMAC-SHA256 签名
// （X-Date + X-Content-Sha256 + CanonicalRequest → StringToSign → 派生密钥链 → Authorization）
// TextList 原生数组批量，天然对齐；ResponseMetadata.Error 透传错误码
// 文档：https://www.volcengine.com/docs/64487
// 注意：老版 API 无独立繁体语言码（zh-Hant 降级为 zh 简体输出）
import { Http } from '../net/Http';
import { Settings } from '../common/Settings';
import { TransHash } from './TransHash';
import { TranslationProvider } from './TranslationProvider';
import { Log } from '../common/Log';
import { util } from '@kit.ArkTS';

// TranslateText 请求体：SourceLanguage 省略时自动检测
interface VolcTranslateBodyBase {
  TargetLanguage: string;
  TextList: string[];
}

interface VolcTranslateBody extends VolcTranslateBodyBase {
  SourceLanguage: string;
}

// 响应体：TranslationList 与 TextList 对齐；错误在 ResponseMetadata.Error
interface VolcTranslationItem {
  Translation?: string;
  DetectedSourceLanguage?: string;
}

interface VolcError {
  Code?: string;
  Message?: string;
}

interface VolcResponseMeta {
  Error?: VolcError;
}

interface VolcTranslateResp {
  TranslationList?: VolcTranslationItem[];
  ResponseMetadata?: VolcResponseMeta;
}

export class VolcanoProvider implements TranslationProvider {
  id: string = 'volcano';
  // 单请求限制（保守）：条数 / 总字符
  private static readonly MAX_BATCH_ITEMS: number = 10;
  private static readonly MAX_BATCH_CHARS: number = 1500;
  private static readonly CHUNK_GAP_MS: number = 300;
  private static readonly HOST: string = 'open.volcengineapi.com';
  private static readonly ENDPOINT: string =
    `https://${VolcanoProvider.HOST}/?Action=TranslateText&Version=2020-06-01`;
  private static readonly SERVICE: string = 'translate';
  private static readonly REGION: string = 'cn-north-1';
  private static readonly VERSION: string = '2020-06-01';

  isConfigured(): boolean {
    return Settings.getTransVolcanoAccessKey() !== '' && Settings.getTransVolcanoSecretKey() !== '';
  }

  // 火山老版 TranslateText 支持全部候选目标语言（zh-Hant 降级 zh 由 mapLang 处理）
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
    // 按条数 + 字符总量分块
    const chunks: number[][] = [];
    let cur: number[] = [];
    let curLen: number = 0;
    for (const pos of positions) {
      const len: number = texts[pos].length;
      if (cur.length > 0 && (cur.length >= VolcanoProvider.MAX_BATCH_ITEMS
        || curLen + len > VolcanoProvider.MAX_BATCH_CHARS)) {
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
        await VolcanoProvider.delay(VolcanoProvider.CHUNK_GAP_MS);
      }
      const chunk: number[] = chunks[c];
      const batch: string[] = [];
      for (const pos of chunk) {
        batch.push(texts[pos]);
      }
      const translated: string[] = await VolcanoProvider.translateBatch(batch, from, to);
      for (let j = 0; j < chunk.length; j++) {
        out[chunk[j]] = translated[j];
      }
    }
    return out;
  }

  // 单块请求：TextList 原生数组，译文逐条对齐；条数失配时逐条重译兜底
  private static async translateBatch(batch: string[], from: string, to: string): Promise<string[]> {
    const accessKey: string = Settings.getTransVolcanoAccessKey();
    const secretKey: string = Settings.getTransVolcanoSecretKey();
    const now: Date = new Date();
    const xDate: string = VolcanoProvider.formatDateTime(now);
    const date: string = xDate.substring(0, 8);
    // SourceLanguage 省略时自动检测（对齐官方 omitempty 行为）
    let body: string;
    if (from === '' || from === 'auto') {
      const base: VolcTranslateBodyBase = {
        TargetLanguage: VolcanoProvider.mapTargetLang(to),
        TextList: batch
      };
      body = JSON.stringify(base);
    } else {
      const full: VolcTranslateBody = {
        SourceLanguage: VolcanoProvider.mapSourceLang(from),
        TargetLanguage: VolcanoProvider.mapTargetLang(to),
        TextList: batch
      };
      body = JSON.stringify(full);
    }
    const bodyHash: string = TransHash.sha256Hex(body);
    const canonicalRequest: string = 'POST\n' +
      '/\n' +
      `Action=TranslateText&Version=${VolcanoProvider.VERSION}\n` +
      'content-type:application/json\n' +
      `host:${VolcanoProvider.HOST}\n` +
      `x-content-sha256:${bodyHash}\n` +
      `x-date:${xDate}\n` +
      '\n' +
      'content-type;host;x-content-sha256;x-date\n' +
      bodyHash;
    const credentialScope: string = `${date}/${VolcanoProvider.REGION}/${VolcanoProvider.SERVICE}/request`;
    const stringToSign: string = 'HMAC-SHA256\n' +
      `${xDate}\n` +
      `${credentialScope}\n` +
      TransHash.sha256Hex(canonicalRequest);
    const encoder = new util.TextEncoder();
    const kDate: Uint8Array = VolcanoProvider.hmac(encoder.encodeInto(secretKey), date);
    const kRegion: Uint8Array = VolcanoProvider.hmac(kDate, VolcanoProvider.REGION);
    const kService: Uint8Array = VolcanoProvider.hmac(kRegion, VolcanoProvider.SERVICE);
    const kSigning: Uint8Array = VolcanoProvider.hmac(kService, 'request');
    const signature: string = TransHash.toHex(VolcanoProvider.hmac(kSigning, stringToSign));
    const authorization: string = 'HMAC-SHA256 ' +
      `Credential=${accessKey}/${credentialScope}, ` +
      'SignedHeaders=content-type;host;x-content-sha256;x-date, ' +
      `Signature=${signature}`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Host': VolcanoProvider.HOST,
      'X-Date': xDate,
      'X-Content-Sha256': bodyHash,
      'Authorization': authorization
    };
    const resp = await Http.requestRaw('POST', VolcanoProvider.ENDPOINT, body, headers);
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`volcano_http_${resp.code}`);
    }
    let parsed: VolcTranslateResp;
    try {
      parsed = JSON.parse(resp.body) as VolcTranslateResp;
    } catch (_e) {
      throw new Error('volcano_bad_response');
    }
    const meta: VolcResponseMeta | undefined = parsed.ResponseMetadata;
    if (meta !== undefined && meta.Error !== undefined) {
      const code: string = meta.Error.Code !== undefined ? meta.Error.Code : 'unknown';
      throw new Error(`volcano_${VolcanoProvider.sanitize(code)}`);
    }
    const items: VolcTranslationItem[] | undefined = parsed.TranslationList;
    if (items === undefined || items.length !== batch.length) {
      if (items !== undefined && items.length === 1 && batch.length > 1) {
        Log.warn('VolcanoProvider', `batch misaligned (${items.length}/${batch.length}), fallback to per-text`);
        return VolcanoProvider.translateOneByOne(batch, from, to);
      }
      throw new Error('volcano_result_mismatch');
    }
    const out: string[] = [];
    for (const item of items) {
      const text: string | undefined = item.Translation;
      out.push(typeof text === 'string' ? text : '');
    }
    return out;
  }

  // 条数失配时的逐条重译
  private static async translateOneByOne(texts: string[], from: string, to: string): Promise<string[]> {
    const out: string[] = [];
    for (const text of texts) {
      if (out.length > 0) {
        await VolcanoProvider.delay(VolcanoProvider.CHUNK_GAP_MS);
      }
      const single: string[] = await VolcanoProvider.translateBatch([text], from, to);
      out.push(single.length > 0 ? single[0] : '');
    }
    return out;
  }

  // 目标语言码：zh-Hant → zh（老版 API 无独立繁体码，降级简体），其余原样
  private static mapTargetLang(lang: string): string {
    if (lang === 'zh-Hant') {
      return 'zh';
    }
    return lang;
  }

  // 源语言码：zh-Hant → zh；其余原样
  private static mapSourceLang(lang: string): string {
    if (lang === 'zh-Hant') {
      return 'zh';
    }
    return lang;
  }

  // Date → UTC yyyyMMddTHHmmssZ（X-Date 格式）
  private static formatDateTime(d: Date): string {
    const p2 = (v: number): string => v < 10 ? `0${v}` : `${v}`;
    const y: string = `${d.getUTCFullYear()}`.padStart(4, '0');
    return `${y}${p2(d.getUTCMonth() + 1)}${p2(d.getUTCDate())}` +
      `T${p2(d.getUTCHours())}${p2(d.getUTCMinutes())}${p2(d.getUTCSeconds())}Z`;
  }

  private static hmac(key: Uint8Array, text: string): Uint8Array {
    const mac: Uint8Array = TransHash.hmacSha256(key, text);
    if (mac.length === 0) {
      throw new Error('volcano_sign_failed');
    }
    return mac;
  }

  // 错误码清洗：保留字母数字与下划线（避免服务端消息拼接进错误字符串）
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
