// 百度翻译开放平台·通用翻译 API（BYOK：用户在设置页填自己的 appid/密钥）：
// GET /api/trans/vip/translate，签名 MD5(appid+q+salt+密钥)，标准版 QPS=1
// 文档：https://fanyi-api.baidu.com/doc/21
import { Http } from '../net/Http';
import { Settings } from '../common/Settings';
import { TransHash } from './TransHash';
import { TranslationProvider } from './TranslationProvider';
import { Log } from '../common/Log';

// trans_result 单条：src 原文行 / dst 译文行
interface BaiduTransItem {
  src?: string;
  dst?: string;
}

interface BaiduRawResp {
  error_code?: string;
  error_msg?: string;
  trans_result?: BaiduTransItem[];
}

export class BaiduProvider implements TranslationProvider {
  id: string = 'baidu';

  isConfigured(): boolean {
    return Settings.getTransBaiduAppid() !== '' && Settings.getTransBaiduKey() !== '';
  }

  // 百度通用翻译支持全部候选目标语言
  supports(_from: string, _to: string): boolean {
    return true;
  }

  async translate(texts: string[], from: string, to: string): Promise<string[]> {
    const appid: string = Settings.getTransBaiduAppid();
    const key: string = Settings.getTransBaiduKey();
    const q: string = texts.join('\n');
    const salt: string = Math.floor(Math.random() * 10000000000).toString();
    const sign: string = TransHash.md5Hex(appid + q + salt + key);
    if (sign === '') {
      throw new Error('baidu_sign_failed');
    }
    const url: string = 'https://fanyi-api.baidu.com/api/trans/vip/translate' +
      `?q=${encodeURIComponent(q)}` +
      `&from=${BaiduProvider.mapLang(from)}&to=${BaiduProvider.mapLang(to)}` +
      `&appid=${encodeURIComponent(appid)}&salt=${salt}&sign=${sign}`;
    const resp = await Http.requestRaw('GET', url, '', undefined);
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`baidu_http_${resp.code}`);
    }
    let raw: BaiduRawResp;
    try {
      raw = JSON.parse(resp.body) as BaiduRawResp;
    } catch (_e) {
      throw new Error('baidu_bad_response');
    }
    if (typeof raw.error_code === 'string' && raw.error_code !== '') {
      throw new Error(`baidu_${raw.error_code}`);
    }
    const items: BaiduTransItem[] | undefined = raw.trans_result;
    if (items === undefined || items.length === 0) {
      throw new Error('baidu_empty_result');
    }
    const dsts: string[] = [];
    for (const item of items) {
      const dst: string | undefined = item.dst;
      dsts.push(typeof dst === 'string' ? dst : '');
    }
    // 单条输入直接合并返回（译文可能含换行，不参与对齐拆分）
    if (texts.length === 1) {
      return [dsts.join('\n')];
    }
    // 多行合并后按行拆回：与入参对齐则整批返回，否则逐条重译兜底
    const lines: string[] = dsts.join('\n').split('\n');
    if (lines.length === texts.length) {
      return lines;
    }
    Log.warn('BaiduProvider', `batch misaligned (${lines.length}/${texts.length}), fallback to per-text`);
    return this.translateOneByOne(texts, from, to);
  }

  // 行对齐失败时的逐条重译（QPS=1：请求间保持 1.1s 间隔）
  private async translateOneByOne(texts: string[], from: string, to: string): Promise<string[]> {
    const out: string[] = [];
    for (const text of texts) {
      if (out.length > 0) {
        await BaiduProvider.delay(1100);
      }
      const single: string[] = await this.translate([text], from, to);
      out.push(single.length > 0 ? single[0] : '');
    }
    return out;
  }

  // 通用语言码 → 百度语言码（日语 jp、韩语 kor、法语 fra、西语 spa、繁体 cht）
  private static mapLang(lang: string): string {
    if (lang === 'ja') {
      return 'jp';
    }
    if (lang === 'ko') {
      return 'kor';
    }
    if (lang === 'fr') {
      return 'fra';
    }
    if (lang === 'es') {
      return 'spa';
    }
    if (lang === 'zh-Hant') {
      return 'cht';
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
