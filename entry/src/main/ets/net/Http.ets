import { http } from '@kit.NetworkKit';
import { CookieJar } from './CookieJar';

// HTTP 客户端封装（对齐 Mihon NetworkHelper 的最小集）
// - 统一 UA：CF 盾 cf_clearance 与 UA 绑定，http 层与验证 Web 必须一致
// - CookieJar：自动附带请求 Cookie、回收响应 Set-Cookie
// - CF challenge：检测到 403/503 盾页时置 AppStorage.cfChallengeUrl，由 Index 弹验证页
export class Http {
  static readonly USER_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static async get(url: string, headers: Record<string, string> | undefined): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: Http.buildHeaders(url, headers),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000,
      };
      const resp: http.HttpResponse = await client.request(url, options);
      CookieJar.storeFromResponse(url, resp.header);
      if (Http.isCfChallenge(resp, resp.result as string, url)) {
        throw new Error('站点需要人机验证，请在弹出的验证页完成后重试');
      }
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}: ${url}`);
      }
      return resp.result as string;
    } finally {
      client.destroy();
    }
  }

  static async post(url: string, body: string, headers: Record<string, string> | undefined): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const merged: Record<string, string> = Http.buildHeaders(url, headers);
      merged['Content-Type'] = 'application/json';
      merged['Accept'] = 'application/json';
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: merged,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000,
      };
      const resp: http.HttpResponse = await client.request(url, options);
      CookieJar.storeFromResponse(url, resp.header);
      if (Http.isCfChallenge(resp, resp.result as string, url)) {
        throw new Error('站点需要人机验证，请在弹出的验证页完成后重试');
      }
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}: ${url}`);
      }
      return resp.result as string;
    } finally {
      client.destroy();
    }
  }

  static async getBuffer(url: string, headers: Record<string, string> | undefined): Promise<ArrayBuffer> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: Http.buildHeaders(url, headers),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000,
      };
      const resp: http.HttpResponse = await client.request(url, options);
      CookieJar.storeFromResponse(url, resp.header);
      if (Http.isCfChallenge(resp, '', url)) {
        throw new Error('站点需要人机验证，请在弹出的验证页完成后重试');
      }
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}: ${url}`);
      }
      return resp.result as ArrayBuffer;
    } finally {
      client.destroy();
    }
  }

  static defaultHeaders(): Record<string, string> {
    return { 'User-Agent': Http.USER_AGENT };
  }

  // ---------------- 内部实现 ----------------

  // 合并请求头：统一 UA + 调用方覆盖 + CookieJar 自动附带
  private static buildHeaders(url: string, headers: Record<string, string> | undefined): Record<string, string> {
    const merged: Record<string, string> = { 'User-Agent': Http.USER_AGENT };
    if (headers !== undefined) {
      const keys = Object.keys(headers);
      for (const k of keys) {
        merged[k] = headers[k];
      }
    }
    if (!Http.hasKey(merged, 'Cookie')) {
      const cookie = CookieJar.headerFor(url);
      if (cookie !== '') {
        merged['Cookie'] = cookie;
      }
    }
    return merged;
  }

  private static hasKey(rec: Record<string, string>, key: string): boolean {
    const keys = Object.keys(rec);
    for (const k of keys) {
      if (k.toLowerCase() === key.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  // Cloudflare 盾页检测：403/503 + cf-mitigated 响应头或盾页特征文案
  private static isCfChallenge(resp: http.HttpResponse, body: string, url: string): boolean {
    if (resp.responseCode !== 403 && resp.responseCode !== 503) {
      return false;
    }
    const h = resp.header as Record<string, Object>;
    const keys = Object.keys(h);
    let challenged = false;
    for (const k of keys) {
      if (k.toLowerCase() === 'cf-mitigated') {
        const v = h[k];
        if (typeof v === 'string' && v.toLowerCase() === 'challenge') {
          challenged = true;
        }
      }
    }
    if (!challenged &&
      (body.indexOf('challenge-platform') >= 0 || body.indexOf('Just a moment') >= 0)) {
      challenged = true;
    }
    if (challenged) {
      AppStorage.setOrCreate('cfChallengeUrl', url);
    }
    return challenged;
  }
}
