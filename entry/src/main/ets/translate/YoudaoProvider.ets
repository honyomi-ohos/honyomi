// 网易有道智云·文本翻译 API（BYOK：用户在设置页填自己的应用ID/应用密钥）：
// POST openapi.youdao.com/api，v3 签名 SHA-256(appKey+input+salt+curtime+appSecret)
// 文档：https://ai.youdao.com/DOCSIRMA/html/自然语言处理/API文本翻译服务/JSON/API文档.html
import { Http } from '../net/Http';
import { Settings } from '../common/Settings';
import { TransHash } from './TransHash';
import { TranslationProvider } from './TranslationProvider';
import { Log } from '../common/Log';

interface YoudaoRawResp {
  errorCode?: string;
  translation?: string[];
}

export class YoudaoProvider implements TranslationProvider {
  id: string = 'youdao';

  isConfigured(): boolean {
    return Settings.getTransYoudaoKey() !== '' && Settings.getTransYoudaoSecret() !== '';
  }

  // 有道文本翻译支持全部候选目标语言
  supports(_from: string, _to: string): boolean {
    return true;
  }

  async translate(texts: string[], from: string, to: string): Promise<string[]> {
    const appKey: string = Settings.getTransYoudaoKey();
    const secret: string = Settings.getTransYoudaoSecret();
    const q: string = texts.join('\n');
    const salt: string = Math.floor(Math.random() * 10000000000).toString();
    const curtime: string = Math.floor(Date.now() / 1000).toString();
    // 签名摘要 input：q 不超过 20 字符取原文，否则 前10 + 长度 + 后10
    const input: string = q.length <= 20 ? q : q.substring(0, 10) + q.length.toString() + q.substring(q.length - 10);
    const sign: string = TransHash.sha256Hex(appKey + input + salt + curtime + secret);
    if (sign === '') {
      throw new Error('youdao_sign_failed');
    }
    const body: string = `q=${encodeURIComponent(q)}` +
      `&from=${YoudaoProvider.mapLang(from)}&to=${YoudaoProvider.mapLang(to)}` +
      `&appKey=${encodeURIComponent(appKey)}&salt=${salt}` +
      `&sign=${sign}&signType=v3&curtime=${curtime}`;
    const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    const resp = await Http.requestRaw('POST', 'https://openapi.youdao.com/api', body, headers);
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`youdao_http_${resp.code}`);
    }
    let raw: YoudaoRawResp;
    try {
      raw = JSON.parse(resp.body) as YoudaoRawResp;
    } catch (_e) {
      throw new Error('youdao_bad_response');
    }
    if (typeof raw.errorCode === 'string' && raw.errorCode !== '0') {
      throw new Error(`youdao_${raw.errorCode}`);
    }
    const translation: string[] | undefined = raw.translation;
    if (translation === undefined || translation.length === 0) {
      throw new Error('youdao_empty_result');
    }
    // 单条输入直接合并返回（译文可能含换行，不参与对齐拆分）
    if (texts.length === 1) {
      return [translation.join('\n')];
    }
    const lines: string[] = translation.join('\n').split('\n');
    if (lines.length === texts.length) {
      return lines;
    }
    Log.warn('YoudaoProvider', `batch misaligned (${lines.length}/${texts.length}), fallback to per-text`);
    return this.translateOneByOne(texts, from, to);
  }

  // 行对齐失败时的逐条重译（实例级 QPS 保守限速 1.1s）
  private async translateOneByOne(texts: string[], from: string, to: string): Promise<string[]> {
    const out: string[] = [];
    for (const text of texts) {
      if (out.length > 0) {
        await YoudaoProvider.delay(1100);
      }
      const single: string[] = await this.translate([text], from, to);
      out.push(single.length > 0 ? single[0] : '');
    }
    return out;
  }

  // 通用语言码 → 有道语言码（简体 zh-CHS、繁体 zh-CHT）
  private static mapLang(lang: string): string {
    if (lang === 'zh') {
      return 'zh-CHS';
    }
    if (lang === 'zh-Hant') {
      return 'zh-CHT';
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
