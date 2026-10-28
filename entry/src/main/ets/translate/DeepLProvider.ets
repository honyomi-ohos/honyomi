// DeepL 翻译引擎（参考 DLX 项目逆向的 oneshot 接口）：
// POST oneshot-free.www.deepl.com/v1/translate，text 为原生数组，天然批量对齐。
// 匿名调用限制：单请求文本总长（UTF-16）≤1500，超限按块拆分多次请求；
// 429=请求过频（IP 被临时限制），403=客户端指纹被拒。
// 需伪装 DeepL iOS 客户端指纹（Authorization: None + x-app-* + URLSession UA），
// 各字段须保持同一代际的 iOS 配置，否则易被临时封禁。
import { Http } from '../net/Http';
import { TranslationProvider } from './TranslationProvider';
import { util } from '@kit.ArkTS';

// 请求体（对齐 DeepL iOS 客户端 OneShotTranslationRequestDto + AppInformation）
interface DeeplAppInformation {
  os: string;
  os_version: string;
  app_version: string;
  app_build: string;
  instance_id: string;
}

// source_lang 为空（自动检测）时不携带该字段，与 iOS 客户端 omitempty 行为一致
interface DeeplOneshotBodyBase {
  text: string[];
  target_lang: string;
  usage_type: string;
  app_information: DeeplAppInformation;
}

interface DeeplOneshotBody extends DeeplOneshotBodyBase {
  source_lang: string;
}

// 响应体：translations 与请求 text 一一对应
interface DeeplTranslationItem {
  text?: string;
}

interface DeeplOneshotResp {
  translations?: DeeplTranslationItem[];
}

export class DeeplProvider implements TranslationProvider {
  id: string = 'deepl';
  // 匿名单请求总长上限（UTF-16 码元，含代理对）：超限按块拆分多次请求
  private static readonly MAX_BATCH_CHARS: number = 1500;
  // 分块请求间隔（毫秒）：降低 429 概率
  private static readonly CHUNK_GAP_MS: number = 600;
  private static readonly ENDPOINT: string = 'https://oneshot-free.www.deepl.com/v1/translate';
  // 进程级稳定 UUID：实例 ID / 会话 ID（逐请求轮换是更强的机器人特征）
  private static readonly INSTANCE_ID: string = util.generateRandomUUID(true);
  private static readonly SESSION_ID: string = util.generateRandomUUID(true);

  isConfigured(): boolean {
    return true;
  }

  // DeepL 支持全部候选目标语言
  supports(_from: string, _to: string): boolean {
    return true;
  }

  async translate(texts: string[], from: string, to: string): Promise<string[]> {
    const out: string[] = texts.slice();
    // 空白文本不发送（接口对空串原样回显，按位置校验会误判为失败）：位置对齐原样返回
    const positions: number[] = [];
    for (let i = 0; i < texts.length; i++) {
      if (texts[i].trim() !== '') {
        positions.push(i);
      }
    }
    if (positions.length === 0) {
      return out;
    }
    // 按 UTF-16 总长分块（匿名上限 1500）
    const chunks: number[][] = [];
    let cur: number[] = [];
    let curLen: number = 0;
    for (const pos of positions) {
      const len: number = texts[pos].length;
      if (cur.length > 0 && curLen + len > DeeplProvider.MAX_BATCH_CHARS) {
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
        await DeeplProvider.delay(DeeplProvider.CHUNK_GAP_MS);
      }
      const chunk: number[] = chunks[c];
      const batch: string[] = [];
      for (const pos of chunk) {
        batch.push(texts[pos]);
      }
      const translated: string[] = await DeeplProvider.translateBatch(batch, from, to);
      for (let j = 0; j < chunk.length; j++) {
        out[chunk[j]] = translated[j];
      }
    }
    return out;
  }

  // 单块请求：全部成功或整体抛错（上层回退其它引擎）
  private static async translateBatch(batch: string[], from: string, to: string): Promise<string[]> {
    const appInfo: DeeplAppInformation = {
      os: 'iOS',
      os_version: '26.0',
      app_version: '26.52',
      app_build: '5443737',
      instance_id: DeeplProvider.INSTANCE_ID
    };
    const target: string = DeeplProvider.mapTargetLang(to);
    const source: string = DeeplProvider.mapSourceLang(from);
    // source_lang 为空串时省略该字段（自动检测）
    let bodyJson: string;
    if (source === '') {
      const base: DeeplOneshotBodyBase = {
        text: batch,
        target_lang: target,
        usage_type: 'translate',
        app_information: appInfo
      };
      bodyJson = JSON.stringify(base);
    } else {
      const full: DeeplOneshotBody = {
        text: batch,
        target_lang: target,
        source_lang: source,
        usage_type: 'translate',
        app_information: appInfo
      };
      bodyJson = JSON.stringify(full);
    }
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'None',
      'User-Agent': 'DeepL/26.52 CFNetwork/3826.600.41 Darwin/25.0.0',
      'x-app-os-version': '26.0',
      'x-app-instance-id': DeeplProvider.INSTANCE_ID,
      'x-app-session-id': DeeplProvider.SESSION_ID
    };
    const resp = await Http.requestRaw('POST', DeeplProvider.ENDPOINT, bodyJson, headers);
    if (resp.code === 429) {
      throw new Error('deepl_rate_limited');
    }
    if (resp.code === 403) {
      throw new Error('deepl_forbidden');
    }
    if (resp.code < 200 || resp.code >= 300) {
      throw new Error(`deepl_http_${resp.code}`);
    }
    let parsed: DeeplOneshotResp;
    try {
      parsed = JSON.parse(resp.body) as DeeplOneshotResp;
    } catch (_e) {
      throw new Error('deepl_bad_response');
    }
    const items: DeeplTranslationItem[] | undefined = parsed.translations;
    if (items === undefined || items.length !== batch.length) {
      throw new Error('deepl_result_mismatch');
    }
    const out: string[] = [];
    for (const item of items) {
      const text: string | undefined = item.text;
      if (typeof text !== 'string' || text === '') {
        throw new Error('deepl_empty_result');
      }
      out.push(text);
    }
    return out;
  }

  // 目标语言码（对齐 iOS 客户端：ZH→zh-Hans、EN→en-US；JA 等原样）
  private static mapTargetLang(lang: string): string {
    if (lang === 'zh') {
      return 'zh-Hans';
    }
    if (lang === 'zh-Hant') {
      return 'zh-Hant';
    }
    if (lang === 'en') {
      return 'en-US';
    }
    if (lang === 'pt') {
      return 'pt-BR';
    }
    return lang;
  }

  // 源语言码：用泛化形式（ZH→zh，EN→en；空/auto 返回空串省略字段走自动检测）
  private static mapSourceLang(lang: string): string {
    if (lang === 'en') {
      return 'en';
    }
    if (lang === '' || lang === 'auto') {
      return '';
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
