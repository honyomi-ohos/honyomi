/*
 * WebViewFetch — CF 盾域名的隐藏 ArkWeb 请求通道。
 *
 * 原生栈（netstack/libcurl）与过盾的 ArkWeb（Chromium）TLS 指纹（ClientHello/JA3）
 * 与 HTTP/2 帧指纹不同：CF managed challenge 把 cf_clearance 绑定到过盾客户端
 * 指纹，原生栈携带有效 clearance 依旧会被重新质询，header 层无法弥补。
 * 本通道把受盾域名的插件请求改由 Index 挂载的隐藏 ArkWeb 页内同源 fetch 执行，
 * 与过盾客户端完全同栈（同 TLS/同 Cookie 仓/同 UA），弹层内验证过的会话直接
 * 复用，多数场景无感通过。
 *
 * 数据链路：runJavaScript 注入 fetch 脚本 → 页面内同源 fetch → 响应体分块
 * btoa 为 base64 → javaScriptProxy（window.honyomiNet.postResult）回传宿主。
 */

import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { CookieJar } from './CookieJar';
import { Log } from '../common/Log';

// 文本请求超时（页面内 AbortController）
const TEXT_TIMEOUT_MS = 30000;
// 字节请求超时
const BYTES_TIMEOUT_MS = 60000;
// 通道页加载超时
const PAGE_TIMEOUT_MS = 25000;
// 通道响应体上限（base64 编码前，与原生栈 MAX_WANT_BYTES 一致）
const MAX_CHANNEL_BYTES = 32 * 1024 * 1024;

// 通道结果：页面 fetch 回传（body 已 base64），由 NativeHttpBridge 解码组装
export interface WebViewFetchResult {
  status: number;
  statusText: string;
  headers: Record<string, string>;
  bodyBase64: string;
  error: string | null;
  url: string;
}

// 挂起的通道调用（onResult 按 callId 唤醒）
interface ChannelPending {
  resolve: (raw: ChannelResultRaw) => void;
  timer: number;
}

// 页面回传 JSON 的原始形态（字段全部可选，onResult 逐字段校验归一）
interface ChannelResultRaw {
  callId?: number;
  status?: number;
  statusText?: string;
  url?: string;
  headers?: Record<string, string>;
  bodyB64?: string;
  error?: string;
}

export class WebViewFetch {
  // 隐藏通道页控制器（Index 的 onControllerAttached 注入）
  private static controller: webview.WebviewController | null = null;
  // 已确认受 CF 盾的域名（内存态：重启后首次质询会重新标记）
  private static cfHosts: Set<string> = new Set<string>();
  private static nextCallId: number = 0;
  private static pending: Map<number, ChannelPending> = new Map();
  // 通道页加载状态
  private static loadedOrigin: string = '';
  private static pageReady: boolean = false;
  private static pageWaiter: (() => void) | null = null;
  private static pageTimer: number = -1;
  // ensurePageReady 串行链：并发请求共享同一次页面加载
  private static ensureChain: Promise<void> = Promise.resolve();

  /** Index 隐藏 Web 的 onControllerAttached 注入控制器（主线程）。 */
  static attach(controller: webview.WebviewController): void {
    WebViewFetch.controller = controller;
    Log.info('WebViewFetch', 'channel attached');
  }

  static isUsable(): boolean {
    return WebViewFetch.controller !== null;
  }

  /** 标记域名为 CF 盾域：后续插件请求优先走通道。 */
  static markCfHost(url: string): void {
    const host = CookieJar.hostOf(url);
    if (host !== '' && !WebViewFetch.cfHosts.has(host)) {
      WebViewFetch.cfHosts.add(host);
      Log.info('WebViewFetch', `cf host routed: ${host}`);
    }
  }

  /** 该 URL 是否应路由到通道（域名已被标记）。 */
  static shouldRoute(url: string): boolean {
    return WebViewFetch.cfHosts.has(CookieJar.hostOf(url));
  }

  /** Index 隐藏 Web 的 onPageEnd 回调：通道页加载完成信号。 */
  static onPageLoaded(): void {
    WebViewFetch.pageReady = true;
    if (WebViewFetch.pageTimer >= 0) {
      clearTimeout(WebViewFetch.pageTimer);
      WebViewFetch.pageTimer = -1;
    }
    const waiter = WebViewFetch.pageWaiter;
    WebViewFetch.pageWaiter = null;
    if (waiter !== null) {
      waiter();
    }
  }

  /** javaScriptProxy 回传入口（NetFetchProxy.postResult）：按 callId 唤醒挂起请求。 */
  static onResult(json: string): void {
    let parsed: ChannelResultRaw | null = null;
    try {
      parsed = JSON.parse(json) as ChannelResultRaw;
    } catch (e) {
      parsed = null;
    }
    if (parsed === null || parsed === undefined || typeof parsed.callId !== 'number') {
      return;
    }
    const pendingCall = WebViewFetch.pending.get(parsed.callId);
    if (pendingCall === undefined) {
      return;
    }
    WebViewFetch.pending.delete(parsed.callId);
    clearTimeout(pendingCall.timer);
    pendingCall.resolve(parsed);
  }

  /**
   * 经隐藏通道页执行请求（cf 盾域名专用）。
   * 技术性失败（未挂载/页面超时/注入失败/页面 fetch 报错）抛 Error，
   * 调用方回落原生栈；质询结果正常返回（由调用方检测并弹验证层）。
   */
  static async fetch(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    wantBytes: boolean
  ): Promise<WebViewFetchResult> {
    const controller = WebViewFetch.controller;
    if (controller === null) {
      throw new Error('webview_not_attached');
    }
    const origin = WebViewFetch.originOf(url);
    if (origin === '') {
      throw new Error('webview_invalid_url');
    }
    await WebViewFetch.ensurePageReady(origin);
    const upperMethod = method.toUpperCase();
    const safeHeaders = WebViewFetch.sanitizeHeaders(upperMethod, headers, body);
    const timeoutMs = wantBytes ? BYTES_TIMEOUT_MS : TEXT_TIMEOUT_MS;
    const callId = ++WebViewFetch.nextCallId;
    const raw = await WebViewFetch.injectFetch(controller, callId, url, upperMethod, safeHeaders, body, timeoutMs);
    if (typeof raw.error === 'string' && raw.error !== '') {
      throw new Error(raw.error);
    }
    const hs: Record<string, string> = {};
    const rawHeaders = raw.headers;
    if (rawHeaders !== undefined && rawHeaders !== null) {
      const keys = Object.keys(rawHeaders);
      for (const k of keys) {
        const v = rawHeaders[k];
        if (typeof v === 'string') {
          hs[k] = v;
        }
      }
    }
    const result: WebViewFetchResult = {
      status: typeof raw.status === 'number' ? raw.status : 0,
      statusText: typeof raw.statusText === 'string' ? raw.statusText : '',
      headers: hs,
      bodyBase64: typeof raw.bodyB64 === 'string' ? raw.bodyB64 : '',
      error: null,
      url: typeof raw.url === 'string' && raw.url !== '' ? raw.url : url,
    };
    return result;
  }

  // ---------------- 内部实现 ----------------

  // 确保通道页已加载到目标 origin（ensureChain 串行化：并发请求共享同一次加载）
  private static ensurePageReady(origin: string): Promise<void> {
    const run: Promise<void> = WebViewFetch.ensureChain.then((): Promise<void> => {
      if (WebViewFetch.controller === null) {
        return Promise.reject(new Error('webview_not_attached'));
      }
      if (WebViewFetch.pageReady && WebViewFetch.loadedOrigin === origin) {
        return Promise.resolve();
      }
      WebViewFetch.pageReady = false;
      return WebViewFetch.loadOrigin(origin).then((): void => {
        WebViewFetch.loadedOrigin = origin;
        WebViewFetch.pageReady = true;
        Log.info('WebViewFetch', `channel page ready: ${origin}`);
      });
    });
    // 失败也续链，后续请求可重新发起加载
    WebViewFetch.ensureChain = run.then((): void => {
    }, (): void => {
    });
    return run;
  }

  // 加载 origin 首页（站点根路径）：onPageLoaded 信号或 PAGE_TIMEOUT_MS 超时
  private static loadOrigin(origin: string): Promise<void> {
    const controller = WebViewFetch.controller;
    if (controller === null) {
      return Promise.reject(new Error('webview_not_attached'));
    }
    return new Promise<void>((resolve: () => void, reject: (e: Error) => void) => {
      WebViewFetch.pageWaiter = resolve;
      WebViewFetch.pageTimer = setTimeout(() => {
        WebViewFetch.pageWaiter = null;
        WebViewFetch.pageTimer = -1;
        reject(new Error('webview_page_timeout'));
      }, PAGE_TIMEOUT_MS);
      try {
        controller.loadUrl(`${origin}/`);
      } catch (e) {
        if (WebViewFetch.pageTimer >= 0) {
          clearTimeout(WebViewFetch.pageTimer);
          WebViewFetch.pageTimer = -1;
        }
        WebViewFetch.pageWaiter = null;
        reject(new Error('webview_load_failed'));
      }
    });
  }

  // 注入 fetch 脚本并挂起等待回传（宿主侧守护超时 = 页面超时 + 5s 余量）
  private static injectFetch(
    controller: webview.WebviewController,
    callId: number,
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    timeoutMs: number
  ): Promise<ChannelResultRaw> {
    return new Promise<ChannelResultRaw>((resolve: (raw: ChannelResultRaw) => void,
      reject: (e: Error) => void) => {
      const timer = setTimeout(() => {
        WebViewFetch.pending.delete(callId);
        reject(new Error('webview_channel_timeout'));
      }, timeoutMs + 5000);
      WebViewFetch.pending.set(callId, { resolve: resolve, timer: timer });
      const script = WebViewFetch.buildScript(callId, url, method, headers, body, timeoutMs);
      controller.runJavaScript(script).catch((_e: BusinessError) => {
        const pendingCall = WebViewFetch.pending.get(callId);
        if (pendingCall !== undefined) {
          clearTimeout(pendingCall.timer);
          WebViewFetch.pending.delete(callId);
          reject(new Error('webview_inject_failed'));
        }
      });
    });
  }

  // 页面内执行的 fetch 桥脚本（ES5 兼容）：
  // - 同源 fetch，credentials/UA/Cookie 由浏览器接管（与过盾客户端一致）
  // - AbortController 超时；响应体分块 btoa base64，超过 32MB 直接报错
  // - 结果经 window.honyomiNet.postResult 回传宿主
  private static buildScript(
    callId: number,
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    timeoutMs: number
  ): string {
    return '(function(){' +
      `var req={callId:${callId},url:${JSON.stringify(url)},method:${JSON.stringify(method)},` +
      `headers:${JSON.stringify(headers)},body:${JSON.stringify(body)},timeoutMs:${timeoutMs}};` +
      'var ctl=new AbortController();' +
      'var t=setTimeout(function(){ctl.abort();},req.timeoutMs);' +
      'fetch(req.url,{method:req.method,headers:req.headers,' +
      "body:(req.method==='GET'||req.method==='HEAD')?undefined:(req.body||'')," +
      "credentials:'same-origin',redirect:'follow',signal:ctl.signal})" +
      '.then(function(r){' +
      'return r.arrayBuffer().then(function(buf){' +
      'clearTimeout(t);' +
      'var b=new Uint8Array(buf);' +
      `if(b.length>${MAX_CHANNEL_BYTES}){` +
      'window.honyomiNet.postResult(JSON.stringify({callId:req.callId,error:"response_too_large"}));return;}' +
      'var s="";' +
      'for(var i=0;i<b.length;i+=32768){' +
      's+=String.fromCharCode.apply(null,b.subarray(i,Math.min(i+32768,b.length)));}' +
      'var hs={};r.headers.forEach(function(v,k){hs[k]=v;});' +
      'window.honyomiNet.postResult(JSON.stringify({callId:req.callId,status:r.status,' +
      'statusText:r.statusText,url:r.url,headers:hs,bodyB64:btoa(s)}));});})' +
      '.catch(function(e){clearTimeout(t);' +
      'window.honyomiNet.postResult(JSON.stringify({callId:req.callId,' +
      'error:String(e&&e.message?e.message:e)}));});' +
      '})();';
  }

  // 剥离浏览器禁改/自管的头（Cookie/UA/Referer/Sec-* 等）：
  // 通道请求的凭证与 UA 由 ArkWeb 引擎接管，与过盾客户端完全一致
  private static sanitizeHeaders(
    method: string,
    headers: Record<string, string>,
    body: string
  ): Record<string, string> {
    const out: Record<string, string> = {};
    let hasContentType = false;
    const keys = Object.keys(headers);
    for (const key of keys) {
      const lower = key.toLowerCase();
      if (lower === 'cookie' || lower === 'user-agent' || lower === 'referer' || lower === 'referrer' ||
        lower === 'host' || lower === 'origin' || lower === 'content-length' || lower === 'connection' ||
        lower === 'accept-encoding' || lower.indexOf('sec-') === 0 || lower.indexOf('proxy-') === 0) {
        continue;
      }
      if (lower === 'content-type') {
        hasContentType = true;
      }
      out[key] = headers[key];
    }
    // 与原生栈 mergeHeaders 同款默认值（Madara ajax 等不带 Content-Type 的表单 POST）
    if (!hasContentType && body !== '' && (method === 'POST' || method === 'PUT')) {
      out['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    return out;
  }

  private static originOf(u: string): string {
    let start = 0;
    if (u.indexOf('https://') === 0) {
      start = 8;
    } else if (u.indexOf('http://') === 0) {
      start = 7;
    } else {
      return '';
    }
    const slash = u.indexOf('/', start);
    return slash >= 0 ? u.substring(0, slash) : u;
  }
}
