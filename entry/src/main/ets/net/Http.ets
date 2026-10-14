import { http } from '@kit.NetworkKit';
import { request } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { CookieJar } from './CookieJar';

// 下载句柄：promise 必然 settle；cancel 中断；setProgressCb 接收字节进度
export interface DownloadHandle {
  promise: Promise<void>;
  cancel: () => void;
  setProgressCb: (cb: (received: number, total: number) => void) => void;
}

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

  // 合并 UA、调用方头与 Cookie，供图片以外的下载和播放使用
  static headersFor(url: string, headers: Record<string, string> | undefined): Record<string, string> {
    return Http.buildHeaders(url, headers);
  }

  // 流式下载到沙箱文件，避免把视频整段读进内存。
  // 返回句柄：promise 结束（成功/失败/取消/停顿超时都会 settle，绝不悬挂）；
  // cancel() 中断下载；setProgressCb 接收字节进度。
  // stall 超时看门狗：连续 STALL_TIMEOUT_MS 无字节进展即失败并清理系统任务。
  static downloadToFile(context: common.Context, url: string, headers: Record<string, string> | undefined,
    filePath: string, stallTimeoutMs: number = 60000): DownloadHandle {
    const config: request.DownloadConfig = {
      url: url,
      header: Http.buildHeaders(url, headers),
      filePath: filePath,
    };
    let taskRef: request.DownloadTask | undefined = undefined;
    let settled = false;
    let watchdog: number = -1;
    let progressCb: ((received: number, total: number) => void) | undefined = undefined;
    const promise = new Promise<void>((resolve: () => void, reject: (err: Error) => void) => {
      const finish = (err: Error | undefined): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (watchdog >= 0) {
          clearTimeout(watchdog);
          watchdog = -1;
        }
        const task = taskRef;
        taskRef = undefined;
        if (task !== undefined) {
          // 清理系统下载任务记录（幂等，失败可忽略）
          task.delete().catch((_e: Error) => {
          });
        }
        if (err !== undefined) {
          reject(err);
        } else {
          resolve();
        }
      };
      const armWatchdog = (): void => {
        if (watchdog >= 0) {
          clearTimeout(watchdog);
        }
        watchdog = setTimeout(() => {
          finish(new Error('下载超时（服务器长时间无响应）'));
        }, stallTimeoutMs);
      };
      // @SuppressWarnings syscap
      request.downloadFile(context, config).then((task: request.DownloadTask) => {
        if (settled) {
          task.delete().catch((_e: Error) => {
          });
          return;
        }
        taskRef = task;
        task.on('progress', (received: number, total: number) => {
          armWatchdog();
          if (progressCb !== undefined) {
            progressCb(received, total);
          }
        });
        task.on('complete', () => {
          finish(undefined);
        });
        task.on('fail', (err: number) => {
          finish(new Error(`下载失败 (${err})`));
        });
        task.on('remove', () => {
          finish(new Error('下载已取消'));
        });
      }).catch((e: Error) => {
        finish(e);
      });
      armWatchdog();
    });
    const handle: DownloadHandle = {
      promise: promise,
      cancel: (): void => {
        const task = taskRef;
        if (task !== undefined && !settled) {
          task.delete().catch((_e: Error) => {
          });
        }
      },
      setProgressCb: (cb: (received: number, total: number) => void): void => {
        progressCb = cb;
      },
    };
    return handle;
  }

  // ---------------- 内部实现 ----------------

  // 合并请求头：统一 UA + 调用方覆盖 + CookieJar 自动附带
  // 域名已有 cf_clearance 会话时忽略调用方 UA：cf_clearance 与验证
  // WebView 的 UA（Http.USER_AGENT）绑定，混用其他 UA 会被 CF 拒绝
  private static buildHeaders(url: string, headers: Record<string, string> | undefined): Record<string, string> {
    const cfBound = CookieJar.hasCookie(url, 'cf_clearance');
    const merged: Record<string, string> = {};
    if (headers !== undefined) {
      const keys = Object.keys(headers);
      for (const k of keys) {
        if (cfBound && k.toLowerCase() === 'user-agent') {
          continue;
        }
        merged[k] = headers[k];
      }
    }
    if (!Http.hasKey(merged, 'User-Agent')) {
      merged['User-Agent'] = Http.USER_AGENT;
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
