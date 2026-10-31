import { http } from '@kit.NetworkKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { request } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { CookieJar } from './CookieJar';
import { CfChallenge } from './CfChallenge';
import { Util } from '../common/Util';
import { AppKeys } from '../common/AppKeys';
import { Settings } from '../common/Settings';
import { Doh } from './Doh';
import { Log } from '../common/Log';

// 原始响应：状态码 + 响应体（追踪器需要区分 404 等非 2xx 状态）
export interface RawResponse {
  code: number;
  body: string;
}

// 下载句柄：promise 必然 settle；cancel 中断；setProgressCb 接收字节进度
export interface DownloadHandle {
  promise: Promise<void>;
  cancel: () => void;
  setProgressCb: (cb: (received: number, total: number) => void) => void;
}

// CF 盾挑战错误：检测到盾页（需验证后重试），不参与网络错误重试
class HttpCfError extends Error {
}

// HTTP 非 2xx 状态错误：不属于网络类错误，不重试
class HttpStatusError extends Error {
}

// 重定向跟随结果：最终 URL + 最终响应
interface HttpFollowed {
  url: string;
  resp: http.HttpResponse;
}

// HTTP 客户端封装（对齐 Mihon NetworkHelper 的最小集）
// - 统一 UA：CF 盾 cf_clearance 与 UA 绑定，http 层与验证 Web 必须一致
// - CookieJar：自动附带请求 Cookie、回收响应 Set-Cookie
// - CF challenge：检测到盾页时置 AppStorage.cfChallengeUrl，由 Index 弹验证页
// - 手动重定向链（策略与 NativeHttpBridge 一致）：跨源跳转剥离敏感头
//   （Authorization/Referer/Referrer/Cookie），https 起始禁止降级 http
// - 幂等 GET：网络类错误（非 CF 挑战）退避 500ms 后重试一次
export class Http {
  // 兜底 UA：ArkWeb 真实默认 UA 结构（引擎不可用时使用，如预览器）。
  // 旧版伪装桌面 Chrome（Windows NT 10.0）是 Turnstile 判定伪造客户端的主因：
  // 移动端 ArkWeb 引擎声称 Windows 桌面 Chrome，UA 与实际指纹矛盾，质询必拒
  static readonly FALLBACK_USER_AGENT: string =
    'Mozilla/5.0 (Phone; OpenHarmony 5.0) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile';
  // 运行时生效 UA：优先 ArkWeb 真实默认 UA（getDefaultUserAgent），
  // 高级设置可自定义覆盖；各请求层与 CF 验证 WebView 均在请求时实时读取本字段
  static USER_AGENT: string = Http.FALLBACK_USER_AGENT;
  // initializeWebEngine 全生命周期仅一次（引擎预热的 DLL 加载与站点预连接）
  private static webEngineInited: boolean = false;

  // 解析 ArkWeb 真实默认 UA：cf_clearance 与 UA 绑定，统一 UA 必须与
  // 过盾 WebView 实际 UA 完全一致；自定义 UA 优先（用户显式覆盖）
  static defaultUserAgent(): string {
    try {
      if (!Http.webEngineInited) {
        webview.WebviewController.initializeWebEngine();
        Http.webEngineInited = true;
      }
      const ua = webview.WebviewController.getDefaultUserAgent().trim();
      if (ua !== '') {
        return ua;
      }
    } catch (e) {
      // 引擎不可用（预览器等）：保持兜底 UA
    }
    return Http.FALLBACK_USER_AGENT;
  }

  // 从持久化偏好同步自定义 UA（应用启动与用户修改后调用）
  static syncUserAgent(): void {
    const custom: string = Settings.getUserAgent();
    Http.USER_AGENT = custom !== '' ? custom : Http.defaultUserAgent();
  }

  static async get(url: string, headers: Record<string, string> | undefined): Promise<string> {
    try {
      return await Http.getOnce(url, headers);
    } catch (e) {
      if (e instanceof HttpCfError || e instanceof HttpStatusError) {
        throw e as Error;
      }
    }
    await Http.delay(500);
    return Http.getOnce(url, headers);
  }

  static async post(url: string, body: string, headers: Record<string, string> | undefined): Promise<string> {
    const caller: Record<string, string> = Http.copyHeaders(headers);
    caller['Content-Type'] = 'application/json';
    caller['Accept'] = 'application/json';
    const followed = await Http.follow(url, http.RequestMethod.POST, caller, body,
      http.HttpDataType.STRING, 20000);
    const resp = followed.resp;
    const respBody: string = Http.bodyText(resp.result);
    if (CfChallenge.isCfChallenge(resp.responseCode, respBody, resp.header)) {
      AppStorage.setOrCreate(AppKeys.CF_CHALLENGE_URL, followed.url);
      throw new HttpCfError('cf_required');
    }
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      throw new HttpStatusError(`HTTP ${resp.responseCode}: ${followed.url}`);
    }
    return respBody;
  }

  // 任意方法原始请求（追踪器用）：返回状态码 + 响应体，非 2xx 不抛错；
  // method 支持 GET/POST/PUT/PATCH/DELETE/HEAD；body 传空串表示无请求体；
  // Content-Type 由调用方通过 headers 指定（JSON / x-www-form-urlencoded）
  static async requestRaw(method: string, url: string, body: string,
    headers: Record<string, string> | undefined): Promise<RawResponse> {
    // RequestMethod.PATCH 枚举成员 API 26 才有：PATCH 走 customMethod（@since 23，优先级高于 method）
    const isPatch = method === 'PATCH';
    const followed = await Http.follow(url, isPatch ? http.RequestMethod.POST : Http.parseMethod(method),
      Http.copyHeaders(headers), body, http.HttpDataType.STRING, 20000, isPatch ? 'PATCH' : '');
    const resp = followed.resp;
    const respBody: string = Http.bodyText(resp.result);
    if (CfChallenge.isCfChallenge(resp.responseCode, respBody, resp.header)) {
      AppStorage.setOrCreate(AppKeys.CF_CHALLENGE_URL, followed.url);
      throw new HttpCfError('cf_required');
    }
    const raw: RawResponse = { code: resp.responseCode, body: respBody };
    return raw;
  }

  static async getBuffer(url: string, headers: Record<string, string> | undefined): Promise<ArrayBuffer> {
    try {
      return await Http.getBufferOnce(url, headers);
    } catch (e) {
      if (e instanceof HttpCfError || e instanceof HttpStatusError) {
        throw e as Error;
      }
    }
    await Http.delay(500);
    return Http.getBufferOnce(url, headers);
  }

  static defaultHeaders(): Record<string, string> {
    return { 'User-Agent': Http.USER_AGENT };
  }

  // 合并 UA、调用方头与 Cookie，供图片以外的下载和播放使用
  static headersFor(url: string, headers: Record<string, string> | undefined): Record<string, string> {
    return Http.buildHeaders(url, headers);
  }

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
          finish(new Error('download_timeout'));
        }, stallTimeoutMs);
      };
      // @SuppressWarnings syscap
      // DoH 规则注入完成（或关闭/失败回落）后再发起系统下载任务
      Doh.prepare(url).then((): void => {
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
            finish(new Error(`download_fail|${err}`));
          });
          task.on('remove', () => {
            finish(new Error('download_cancelled'));
          });
        }).catch((e: Error) => {
          finish(e);
        });
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

  // 流式下载到沙箱文件，避免把视频整段读进内存。
  // 返回句柄：promise 结束（成功/失败/取消/停顿超时都会 settle，绝不悬挂）；
  // cancel() 中断下载；setProgressCb 接收字节进度。

  private static parseMethod(method: string): http.RequestMethod {
    switch (method) {
      case 'POST':
        return http.RequestMethod.POST;
      case 'PUT':
        return http.RequestMethod.PUT;
      case 'DELETE':
        return http.RequestMethod.DELETE;
      case 'HEAD':
        return http.RequestMethod.HEAD;
      default:
        return http.RequestMethod.GET;
    }
  }

  // ---------------- 内部实现 ----------------

  private static async getOnce(url: string, headers: Record<string, string> | undefined): Promise<string> {
    const followed = await Http.follow(url, http.RequestMethod.GET, Http.copyHeaders(headers), '',
      http.HttpDataType.STRING, 20000);
    const resp = followed.resp;
    const respBody: string = Http.bodyText(resp.result);
    if (CfChallenge.isCfChallenge(resp.responseCode, respBody, resp.header)) {
      AppStorage.setOrCreate(AppKeys.CF_CHALLENGE_URL, followed.url);
      throw new HttpCfError('cf_required');
    }
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      throw new HttpStatusError(`HTTP ${resp.responseCode}: ${followed.url}`);
    }
    return respBody;
  }

  private static async getBufferOnce(url: string, headers: Record<string, string> | undefined): Promise<ArrayBuffer> {
    // 二进制抓取走 rcp 而非 @ohos.net.http：netstack 的 client.request 会
    // 自动跟随重定向且无法关闭，重定向段在 netstack 内部静默发起，绕过
    // 逐跳 DNS 准备，污染系统 DNS 下必死（哔咔 storage-b 301 → img 即此死法）。
    // rcp 关闭 autoRedirect 后由本方法手动逐跳跟随：每跳独立请求，先
    // Doh.prepare + pin 继承，再把 pin 以 StaticDnsRules 直接随请求带给
    // rcp，不依赖进程级规则是否对该网络栈生效。
    let current = url;
    let currentHeaders = Http.copyHeaders(headers);
    const httpsStart = url.indexOf('https://') === 0;
    for (let hop = 0; hop < 8; hop++) {
      await Doh.prepare(current);
      const req: rcp.Request = new rcp.Request(current, 'GET', Http.buildHeaders(current, currentHeaders));
      const ips: string[] | undefined = Doh.resolvedIpsOf(current);
      if (ips !== undefined) {
        const rule: rcp.StaticDnsRule = {
          host: Doh.hostOf(current),
          port: current.indexOf('https://') === 0 ? 443 : 80,
          ipAddresses: ips,
        };
        const rules: rcp.StaticDnsRules = [rule];
        req.configuration = { dns: { dnsRules: rules } };
      }
      let resp: rcp.Response;
      try {
        Log.debug('Http', `rcp GET ${current}`);
        resp = await Http.imageSession().fetch(req);
      } catch (e) {
        throw new Error(Util.rcpNetErrOf(e));
      }
      CookieJar.storeFromResponse(current, resp.headers);
      const code: number = resp.statusCode;
      if (!Http.isRedirect(code)) {
        return Http.bufferFrom(resp, code, current);
      }
      const loc = Http.headerValue(resp.headers, 'Location');
      const next = Http.resolveLocation(current, loc);
      if (next === '') {
        return Http.bufferFrom(resp, code, current);
      }
      // https 起始禁止降级：目标非 https（降级 http 或其他协议）即终止并报错
      if (httpsStart && next.indexOf('https://') !== 0) {
        throw new Error(`redirect_blocked|${next}`);
      }
      // 跨源跳转剥离敏感头，凭证明文不外送
      if (Http.originOf(next) !== Http.originOf(current)) {
        currentHeaders = Http.stripSensitiveHeaders(currentHeaders);
      }
      Log.info('Http', `redirect hop${hop} ${code} ${Http.originOf(current)} -> ${Http.originOf(next)}`);
      await Doh.inheritPin(current, next);
      current = next;
    }
    throw new Error(`too_many_redirects|${url}`);
  }

  // 终态响应 → ArrayBuffer：CF 盾检测、非 2xx/空响应体报错
  private static bufferFrom(resp: rcp.Response, code: number, url: string): ArrayBuffer {
    if (CfChallenge.isCfChallenge(code, '', resp.headers)) {
      AppStorage.setOrCreate(AppKeys.CF_CHALLENGE_URL, url);
      throw new HttpCfError('cf_required');
    }
    if (code < 200 || code >= 300) {
      throw new HttpStatusError(`HTTP ${code}: ${url}`);
    }
    const body = resp.body;
    if (body === undefined) {
      throw new HttpStatusError(`HTTP ${code}: empty body: ${url}`);
    }
    return body;
  }

  // rcp 会话（图片/二进制抓取专用）：关闭自动重定向，超时对齐旧路径
  // （connect 15s / transfer 60s）。会话全局复用，进程内常驻。
  private static rcpImageSession: rcp.Session | undefined = undefined;

  private static imageSession(): rcp.Session {
    if (Http.rcpImageSession === undefined) {
      const transfer: rcp.TransferConfiguration = {
        autoRedirect: false,
        timeout: { connectMs: 15000, transferMs: 60000 },
      };
      Http.rcpImageSession = rcp.createSession({ requestConfiguration: { transfer: transfer } });
    }
    return Http.rcpImageSession;
  }

  // 手动重定向链（策略对齐 NativeHttpBridge.follow）：
  // - 最多 8 跳，超出报错
  // - https 起始的请求禁止降级 http（或跳转其他协议）
  // - 跨源跳转剥离调用方自定义的敏感头（Authorization/Referer/Referrer/Cookie），
  //   CookieJar 会为新目标域自动附带其自身 cookie
  // - 303 或（301/302 且 POST）转 GET 并丢弃请求体
  // - 每跳回收 Set-Cookie
  private static async follow(
    startUrl: string,
    method: http.RequestMethod,
    headers: Record<string, string>,
    body: string,
    expectDataType: http.HttpDataType,
    readTimeout: number,
    customMethod: string = ''
  ): Promise<HttpFollowed> {
    let url = startUrl;
    let currentMethod = method;
    let currentHeaders = headers;
    let currentBody = body;
    let currentCustomMethod = customMethod;
    const httpsStart = startUrl.indexOf('https://') === 0;
    for (let hop = 0; hop < 8; hop++) {
      const resp = await Http.requestOnce(url, currentMethod, currentHeaders, currentBody, expectDataType,
        readTimeout, currentCustomMethod);
      CookieJar.storeFromResponse(url, resp.header);
      if (!Http.isRedirect(resp.responseCode)) {
        const followed: HttpFollowed = { url: url, resp: resp };
        return followed;
      }
      const loc = Http.headerValue(resp.header, 'Location');
      const next = Http.resolveLocation(url, loc);
      if (next === '') {
        const followed: HttpFollowed = { url: url, resp: resp };
        return followed;
      }
      // https 起始禁止降级：目标非 https（降级 http 或其他协议）即终止并报错
      if (httpsStart && next.indexOf('https://') !== 0) {
        throw new Error(`redirect_blocked|${next}`);
      }
      // 跨源跳转剥离敏感头，凭证明文不外送
      if (Http.originOf(next) !== Http.originOf(url)) {
        currentHeaders = Http.stripSensitiveHeaders(currentHeaders);
      }
      // 303 或（301/302 且真实 POST）转 GET 并丢弃请求体；customMethod 请求（如 PATCH）仅在 303 时转换
      if (resp.responseCode === 303 ||
        ((resp.responseCode === 301 || resp.responseCode === 302) &&
          currentMethod === http.RequestMethod.POST && currentCustomMethod === '')) {
        currentMethod = http.RequestMethod.GET;
        currentCustomMethod = '';
        currentBody = '';
      }
      url = next;
    }
    throw new Error(`too_many_redirects|${startUrl}`);
  }

  private static async requestOnce(
    url: string,
    method: http.RequestMethod,
    headers: Record<string, string>,
    body: string,
    expectDataType: http.HttpDataType,
    readTimeout: number,
    customMethod: string = ''
  ): Promise<http.HttpResponse> {
    // DoH 开启时先注入 host 解析规则（失败内部静默回落系统 DNS）
    await Doh.prepare(url);
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: Http.buildHeaders(url, headers),
        expectDataType: expectDataType,
        connectTimeout: 15000,
        readTimeout: readTimeout,
      };
      if (customMethod !== '') {
        options.customMethod = customMethod;
      }
      if (body !== '' && method !== http.RequestMethod.GET && method !== http.RequestMethod.HEAD) {
        options.extraData = body;
      }
      let resp: http.HttpResponse;
      try {
        Log.debug('Http', `request ${customMethod !== '' ? customMethod : method} ${url}`);
        resp = await client.request(url, options);
      } catch (e) {
        throw new Error(Util.netErrOf(e));
      }
      return resp;
    } finally {
      client.destroy();
    }
  }

  private static copyHeaders(headers: Record<string, string> | undefined): Record<string, string> {
    const out: Record<string, string> = {};
    if (headers !== undefined) {
      const keys = Object.keys(headers);
      for (const k of keys) {
        out[k] = headers[k];
      }
    }
    return out;
  }

  private static isRedirect(code: number): boolean {
    return code === 301 || code === 302 || code === 303 || code === 307 || code === 308;
  }

  private static headerValue(header: Object, name: string): string {
    const raw = header as Record<string, Object>;
    const keys = Object.keys(raw);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() !== name.toLowerCase()) {
        continue;
      }
      const value = raw[keys[i]];
      if (typeof value === 'string') {
        return value as string;
      }
      if (Array.isArray(value) && (value as Object[]).length > 0) {
        return String((value as Object[])[0]);
      }
    }
    return '';
  }

  private static originOf(u: string): string {
    let start = 0;
    if (u.indexOf('https://') === 0) {
      start = 8;
    } else if (u.indexOf('http://') === 0) {
      start = 7;
    } else {
      return u;
    }
    const slash = u.indexOf('/', start);
    return slash >= 0 ? u.substring(0, slash) : u;
  }

  private static resolveLocation(base: string, loc: string): string {
    const trimmed = loc.trim();
    if (trimmed === '') {
      return '';
    }
    if (trimmed.indexOf('https://') === 0 || trimmed.indexOf('http://') === 0) {
      return trimmed;
    }
    if (trimmed.indexOf('//') === 0) {
      if (base.indexOf('https://') === 0) {
        return `https:${trimmed}`;
      }
      return `http:${trimmed}`;
    }
    const origin = Http.originOf(base);
    if (trimmed.charAt(0) === '/') {
      return origin + trimmed;
    }
    let noHash = base;
    const hash = noHash.indexOf('#');
    if (hash >= 0) {
      noHash = noHash.substring(0, hash);
    }
    const query = noHash.indexOf('?');
    if (query >= 0) {
      noHash = noHash.substring(0, query);
    }
    const slash = noHash.lastIndexOf('/');
    const dir = slash >= 0 ? noHash.substring(0, slash + 1) : `${noHash}/`;
    return dir + trimmed;
  }

  // 跨源重定向时剥离调用方自定义的敏感头（大小写不敏感），返回净化后的新表
  private static stripSensitiveHeaders(headers: Record<string, string>): Record<string, string> {
    const kept: Record<string, string> = {};
    const keys = Object.keys(headers);
    for (const key of keys) {
      const lower = key.toLowerCase();
      if (lower === 'authorization' || lower === 'referer' || lower === 'referrer' || lower === 'cookie') {
        continue;
      }
      kept[key] = headers[key];
    }
    return kept;
  }

  // resp.result null/undefined 防护：非字符串一律按空串参与挑战检测
  private static bodyText(result: string | Object | ArrayBuffer | undefined): string {
    return typeof result === 'string' ? result : '';
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

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
}
