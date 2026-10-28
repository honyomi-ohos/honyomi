// 彩云小译·开放 API（BYOK：用户在设置页填自己的令牌）：
// POST api.interpreter.caiyunai.com/v1/translator，原生数组批量，X-Authorization: token
// 文档：https://docs.caiyunapp.com/blog/2019/06/04/old-api-docs/
import { Http } from '../net/Http';
import { Settings } from '../common/Settings';
import { TranslationProvider } from './TranslationProvider';

// 请求体：source 为原文数组（原生批量，无需行对齐）
interface CaiyunRequestBody {
  source: string[];
  trans_type: string;
  request_id: string;
  detect: boolean;
}

interface CaiyunRawResp {
  rc?: number;
  target?: string[];
}

export class CaiyunProvider implements TranslationProvider {
  id: string = 'caiyun';

  isConfigured(): boolean {
    return Settings.getTransCaiyunToken() !== '';
  }

  // 彩云仅支持「中文 ↔ 英/日/韩/西/法/俄」双向（auto 仅可译入中文），
  // 其余方向整链跳过该引擎
  supports(from: string, to: string): boolean {
    const pairs: string[] = ['en', 'ja', 'ko', 'es', 'fr', 'ru'];
    if (to === 'zh') {
      return from === 'auto' || pairs.indexOf(from) >= 0;
    }
    if (from === 'zh') {
      return pairs.indexOf(to) >= 0;
    }
    return false;
  }

  async translate(texts: string[], from: string, to: string): Promise<string[]> {
    const token: string = Settings.getTransCaiyunToken();
    const reqBody: CaiyunRequestBody = {
      source: texts,
      trans_type: `${from}2${to}`,
      request_id: Math.floor(Math.random() * 10000000000).toString(),
      detect: true
    };
    const headers: Record<string, string> = { 'X-Authorization': `token ${token}` };
    // Http.post 自动带 Content-Type: application/json
    const respBody: string = await Http.post('https://api.interpreter.caiyunai.com/v1/translator',
      JSON.stringify(reqBody), headers);
    let raw: CaiyunRawResp;
    try {
      raw = JSON.parse(respBody) as CaiyunRawResp;
    } catch (_e) {
      throw new Error('caiyun_bad_response');
    }
    if (typeof raw.rc === 'number' && raw.rc !== 0) {
      throw new Error(`caiyun_rc_${raw.rc}`);
    }
    const target: string[] | undefined = raw.target;
    if (target === undefined || target.length !== texts.length) {
      throw new Error('caiyun_bad_result');
    }
    return target;
  }
}
