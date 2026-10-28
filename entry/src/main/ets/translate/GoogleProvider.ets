// 谷歌翻译引擎（参考 free-google-translate 的接入方式）：
// GET translate.googleapis.com/translate_a/single?client=gtx&dt=t
// 无需密钥；非官方接口，无 SLA；频繁调用可能被限流（429）。
import { Http } from '../net/Http';
import { TranslationProvider } from './TranslationProvider';
import { Log } from '../common/Log';

export class GoogleProvider implements TranslationProvider {
  id: string = 'google';

  isConfigured(): boolean {
    return true;
  }

  // gtx 接口支持全部候选目标语言
  supports(_from: string, _to: string): boolean {
    return true;
  }

  async translate(texts: string[], from: string, to: string): Promise<string[]> {
    const q: string = texts.join('\n');
    const url: string = 'https://translate.googleapis.com/translate_a/single' +
      `?client=gtx&sl=${GoogleProvider.mapLang(from)}&tl=${GoogleProvider.mapLang(to)}` +
      `&dt=t&q=${encodeURIComponent(q)}`;
    const resp = await Http.requestRaw('GET', url, '', undefined);
    if (resp.code === 429) {
      throw new Error('google_rate_limited');
    }
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`google_http_${resp.code}`);
    }
    const merged: string = GoogleProvider.mergeSegments(resp.body);
    if (merged === '') {
      throw new Error('google_empty_result');
    }
    // 单条输入直接返回（译文可能含换行，不参与对齐拆分）
    if (texts.length === 1) {
      return [merged];
    }
    const lines: string[] = merged.split('\n');
    if (lines.length === texts.length) {
      return lines;
    }
    Log.warn('GoogleProvider', `batch misaligned (${lines.length}/${texts.length}), fallback to per-text`);
    return this.translateOneByOne(texts, from, to);
  }

  // 响应为嵌套数组 [[["译文","原文",null,null,置信度],...],null,"ja",...]：
  // 拼接所有句段译文（句段粒度按源句切分，非按输入行）
  private static mergeSegments(body: string): string {
    let outer: Object[];
    try {
      outer = JSON.parse(body) as Object[];
    } catch (_e) {
      return '';
    }
    if (outer.length === 0 || !Array.isArray(outer[0])) {
      return '';
    }
    const segments: Object[] = outer[0] as Object[];
    let merged = '';
    for (const seg of segments) {
      if (!Array.isArray(seg)) {
        continue;
      }
      const parts: Object[] = seg as Object[];
      if (parts.length > 0 && typeof parts[0] === 'string') {
        merged += parts[0];
      }
    }
    return merged;
  }

  // 通用语言码 → 谷歌语言码（简体 zh-CN、繁体 zh-TW）
  private static mapLang(lang: string): string {
    if (lang === 'zh') {
      return 'zh-CN';
    }
    if (lang === 'zh-Hant') {
      return 'zh-TW';
    }
    return lang;
  }

  // 行对齐失败时的逐条重译（非官方接口保守限速 400ms）
  private async translateOneByOne(texts: string[], from: string, to: string): Promise<string[]> {
    const out: string[] = [];
    for (const text of texts) {
      if (out.length > 0) {
        await GoogleProvider.delay(400);
      }
      const single: string[] = await this.translate([text], from, to);
      out.push(single.length > 0 ? single[0] : '');
    }
    return out;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
