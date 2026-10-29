// 腾讯云机器翻译 TMT（BYOK：SecretId + SecretKey）：
// TextTranslateBatch（Version 2018-03-21），TC3-HMAC-SHA256 请求签名
// （CanonicalRequest → StringToSign → 派生密钥链 kDate/kService/kSigning → Signature）
// 文档：https://cloud.tencent.com/document/product/551/15619
// 单请求限制：SourceText ≤2000 字符、≤25 行 → 按 1500 字符/20 行分块
import { Http } from '../net/Http';
import { Settings } from '../common/Settings';
import { TransHash } from './TransHash';
import { TranslationProvider } from './TranslationProvider';
import { Log } from '../common/Log';
import { util } from '@kit.ArkTS';

// TC3 响应体外壳：TargetText（\n 连接各行）或 Error
interface Tc3Error {
  Code?: string;
  Message?: string;
}

interface Tc3RespBody {
  TargetText?: string;
  Source?: string;
  Target?: string;
  RequestId?: string;
  Error?: Tc3Error;
}

interface Tc3Resp {
  Response?: Tc3RespBody;
}

export class TencentProvider implements TranslationProvider {
  id: string = 'tencent';
  // 单请求限制（保守）：SourceText 总字符 / 行数
  private static readonly MAX_BATCH_CHARS: number = 1500;
  private static readonly MAX_BATCH_LINES: number = 20;
  private static readonly CHUNK_GAP_MS: number = 300;
  private static readonly HOST: string = 'tmt.tencentcloudapi.com';
  private static readonly ENDPOINT: string = `https://${TencentProvider.HOST}/`;
  private static readonly SERVICE: string = 'tmt';
  private static readonly VERSION: string = '2018-03-21';
  private static readonly REGION: string = 'ap-guangzhou';

  isConfigured(): boolean {
    return Settings.getTransTencentSecretId() !== '' && Settings.getTransTencentSecretKey() !== '';
  }

  // 腾讯 TMT 支持全部候选目标语言（zh-Hant→zh-TW 由 mapLang 处理）
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
    // 按字符总量 + 行数分块（SourceText ≤2000 字符 / ≤25 行）
    const chunks: number[][] = [];
    let cur: number[] = [];
    let curLen: number = 0;
    for (const pos of positions) {
      const len: number = texts[pos].length;
      if (cur.length > 0 && (curLen + len > TencentProvider.MAX_BATCH_CHARS
        || cur.length >= TencentProvider.MAX_BATCH_LINES)) {
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
        await TencentProvider.delay(TencentProvider.CHUNK_GAP_MS);
      }
      const chunk: number[] = chunks[c];
      const batch: string[] = [];
      for (const pos of chunk) {
        batch.push(texts[pos]);
      }
      const translated: string[] = await TencentProvider.translateBatch(batch, from, to);
      for (let j = 0; j < chunk.length; j++) {
        out[chunk[j]] = translated[j];
      }
    }
    return out;
  }

  // 单块请求：合并 \n 请求；TargetText 按 \n 拆回对齐，失配逐条重译兜底
  private static async translateBatch(batch: string[], from: string, to: string): Promise<string[]> {
    const secretId: string = Settings.getTransTencentSecretId();
    const secretKey: string = Settings.getTransTencentSecretKey();
    const ts: number = Math.floor(Date.now() / 1000);
    const date: string = TencentProvider.utcDate(ts);
    const sourceText: string = batch.join('\n');
    const body: string = JSON.stringify({
      Source: TencentProvider.mapSourceLang(from),
      Target: TencentProvider.mapTargetLang(to),
      ProjectId: 0,
      SourceText: sourceText
    });
    const bodyHash: string = TransHash.sha256Hex(body);
    const canonicalRequest: string = 'POST\n' +
      '/\n' +
      '\n' +
      'content-type:application/json; charset=utf-8\n' +
      `host:${TencentProvider.HOST}\n` +
      'x-tc-action:texttranslatebatch\n' +
      '\n' +
      'content-type;host;x-tc-action\n' +
      bodyHash;
    const stringToSign: string = 'TC3-HMAC-SHA256\n' +
      `${ts}\n` +
      `${date}/${TencentProvider.SERVICE}/tc3_request\n` +
      TransHash.sha256Hex(canonicalRequest);
    const kDate: Uint8Array = TencentProvider.hmac(new util.TextEncoder().encodeInto(`TC3${secretKey}`), date);
    const kService: Uint8Array = TencentProvider.hmac(kDate, TencentProvider.SERVICE);
    const kSigning: Uint8Array = TencentProvider.hmac(kService, 'tc3_request');
    const signature: string = TransHash.toHex(TencentProvider.hmac(kSigning, stringToSign));
    const authorization: string = 'TC3-HMAC-SHA256 ' +
      `Credential=${secretId}/${date}/${TencentProvider.SERVICE}/tc3_request, ` +
      'SignedHeaders=content-type;host;x-tc-action, ' +
      `Signature=${signature}`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json; charset=utf-8',
      'Host': TencentProvider.HOST,
      'Authorization': authorization,
      'X-TC-Action': 'TextTranslateBatch',
      'X-TC-Timestamp': `${ts}`,
      'X-TC-Version': TencentProvider.VERSION,
      'X-TC-Region': TencentProvider.REGION
    };
    const resp = await Http.requestRaw('POST', TencentProvider.ENDPOINT, body, headers);
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`tencent_http_${resp.code}`);
    }
    let parsed: Tc3Resp;
    try {
      parsed = JSON.parse(resp.body) as Tc3Resp;
    } catch (_e) {
      throw new Error('tencent_bad_response');
    }
    const inner: Tc3RespBody | undefined = parsed.Response;
    if (inner === undefined) {
      throw new Error('tencent_bad_response');
    }
    const err: Tc3Error | undefined = inner.Error;
    if (err !== undefined) {
      const code: string = err.Code !== undefined ? err.Code : 'unknown';
      throw new Error(`tencent_${TencentProvider.sanitize(code)}`);
    }
    const targetText: string | undefined = inner.TargetText;
    if (typeof targetText !== 'string' || targetText === '') {
      throw new Error('tencent_empty_result');
    }
    // 单条输入直接返回
    if (batch.length === 1) {
      return [targetText];
    }
    const lines: string[] = targetText.split('\n');
    if (lines.length === batch.length) {
      return lines;
    }
    Log.warn('TencentProvider', `batch misaligned (${lines.length}/${batch.length}), fallback to per-text`);
    return TencentProvider.translateOneByOne(batch, from, to);
  }

  // 行对齐失败时的逐条重译
  private static async translateOneByOne(texts: string[], from: string, to: string): Promise<string[]> {
    const out: string[] = [];
    for (const text of texts) {
      if (out.length > 0) {
        await TencentProvider.delay(TencentProvider.CHUNK_GAP_MS);
      }
      const single: string[] = await TencentProvider.translateBatch([text], from, to);
      out.push(single.length > 0 ? single[0] : '');
    }
    return out;
  }

  // 通用语言码 → 腾讯 TMT 语言码（zh-Hant→zh-TW，其余原样）
  private static mapTargetLang(lang: string): string {
    if (lang === 'zh-Hant') {
      return 'zh-TW';
    }
    return lang;
  }

  // 源语言码：空/auto → auto（自动检测）
  private static mapSourceLang(lang: string): string {
    if (lang === '' || lang === 'auto') {
      return 'auto';
    }
    if (lang === 'zh-Hant') {
      return 'zh-TW';
    }
    return lang;
  }

  // 秒级时间戳 → UTC 日期 yyyyMMdd
  private static utcDate(ts: number): string {
    const d: Date = new Date(ts * 1000);
    const y: string = `${d.getUTCFullYear()}`.padStart(4, '0');
    const m: string = `${d.getUTCMonth() + 1}`.padStart(2, '0');
    const day: string = `${d.getUTCDate()}`.padStart(2, '0');
    return `${y}${m}${day}`;
  }

  private static hmac(key: Uint8Array, text: string): Uint8Array {
    const mac: Uint8Array = TransHash.hmacSha256(key, text);
    if (mac.length === 0) {
      throw new Error('tencent_sign_failed');
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
