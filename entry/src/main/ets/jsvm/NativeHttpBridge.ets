/*
 * Copyright (c) 2026 mihon-harmony
 *
 * NativeHttpBridge — ArkTS half of the JSVM <-> native HTTP bridge.
 *
 * The native engine (libjsvmengine.so) dispatches every extension HTTP call
 * (fetch() / tachiyomiHttpRequest) to the main thread through a
 * napi_threadsafe_function. This module executes the request with
 * @ohos.net.http — honoring extension headers (Referer / User-Agent / Cookie),
 * the shared CookieJar, and Cloudflare challenge detection — and resolves the
 * blocked worker thread via resolveHttp().
 */

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import jsvmEngine from 'libjsvmengine.so';
import { CookieJar } from '../net/CookieJar';
import { Http } from '../net/Http';

/** Bridge request as dispatched by the native engine (JSON-decoded). */
export interface JsvmBridgeRequest {
  callId: number;
  url: string;
  method: string;
  headersJson: string;
  body: string;
  wantBytes: boolean;
  /** True for zero-copy requests answered via resolveHttpBytes(). */
  shared?: boolean;
  /** Present only on release messages: '{"type":"release","callId":N}'. */
  type?: string;
}

/** KotlinHttpResult shape expected by the extension runtime. */
export interface JsvmHttpResult {
  status: number;
  statusText: string;
  headersJson: string;
  body: string;
  error: string | null;
  url: string;
}

/** Shared (zero-copy) result: meta envelope plus the pinned response body. */
export interface JsvmSharedResult extends JsvmHttpResult {
  bytes: ArrayBuffer | null;
}

interface NativeHttpFollowed {
  url: string;
  resp: http.HttpResponse;
}

/**
 * Thrown when a source answers with a Cloudflare bot challenge (401/403/503
 * challenge pages). The JSVM engine yields execution with this exception;
 * the ArkTS layer opens the single-instance verification webview, harvests
 * the token/cookie into the CookieJar and retries (cookies are re-injected
 * automatically on every subsequent bridge request).
 */
export class WebChallengeError extends Error {
  readonly challengeUrl: string;

  constructor(url: string) {
    super(`站点需要人机验证：${url}`);
    this.challengeUrl = url;
  }
}

/** Marker prefix used inside the bridge error field. */
const CHALLENGE_PREFIX = 'CF_CHALLENGE:';

export class NativeHttpBridge {
  private static installed: boolean = false;
  private static inflight: number = 0;

  /**
   * Installs the one-time dispatcher into the native engine. Must be called
   * on the main thread before any JSVM extension runs (see
   * JsvmExtensionManager.init()).
   */
  static install(): boolean {
    if (NativeHttpBridge.installed) {
      return true;
    }
    const ok = jsvmEngine.initHttpDispatcher((reqJson: string): void => {
      NativeHttpBridge.onRequest(reqJson);
    });
    NativeHttpBridge.installed = ok;
    return ok;
  }

  static isInstalled(): boolean {
    return NativeHttpBridge.installed;
  }

  static activeRequests(): number {
    return NativeHttpBridge.inflight;
  }

  /** True when an envelope error string is a challenge exception. */
  static isChallengeError(error: string): boolean {
    return error.indexOf(CHALLENGE_PREFIX) === 0;
  }

  /** Extracts the challenge URL from an envelope error string. */
  static challengeUrlOf(error: string): string {
    return error.substring(CHALLENGE_PREFIX.length);
  }

  /** Builds the marker error string reported through the bridge. */
  static challengeError(url: string): string {
    return `${CHALLENGE_PREFIX}${url}`;
  }

  // ------------------------------------------------------------------ private

  private static onRequest(reqJson: string): void {
    let msg: JsvmBridgeRequest;
    try {
      msg = JSON.parse(reqJson) as JsvmBridgeRequest;
    } catch (e) {
      return; // malformed dispatch: nothing to resolve
    }
    // Zero-copy body release: the JSVM side garbage-collected a shared
    // response buffer; drop its native pin.
    if (msg.type === 'release') {
      jsvmEngine.releaseHttpBuffer(msg.callId);
      return;
    }
    const req = msg;
    NativeHttpBridge.inflight += 1;
    if (req.shared === true) {
      NativeHttpBridge.executeShared(req).then((result: JsvmSharedResult) => {
        NativeHttpBridge.inflight -= 1;
        const meta: JsvmHttpResult = {
          status: result.status,
          statusText: result.statusText,
          headersJson: result.headersJson,
          body: '',
          error: result.error,
          url: result.url,
        };
        jsvmEngine.resolveHttpBytes(req.callId, JSON.stringify(meta), result.bytes);
      }).catch((e: Error) => {
        NativeHttpBridge.inflight -= 1;
        jsvmEngine.resolveHttpBytes(req.callId, JSON.stringify(NativeHttpBridge.error(0, e.message, '')), null);
      });
      return;
    }
    NativeHttpBridge.execute(req).then((result: JsvmHttpResult) => {
      NativeHttpBridge.inflight -= 1;
      jsvmEngine.resolveHttp(req.callId, JSON.stringify(result));
    }).catch((e: Error) => {
      NativeHttpBridge.inflight -= 1;
      jsvmEngine.resolveHttp(req.callId, JSON.stringify(NativeHttpBridge.error(0, e.message, '')));
    });
  }

  private static async execute(req: JsvmBridgeRequest): Promise<JsvmHttpResult> {
    const url = req.url;
    if (url.indexOf('https://') !== 0 && url.indexOf('http://') !== 0) {
      return NativeHttpBridge.error(0, `仅支持 http/https 请求: ${url}`, url);
    }
    let headers: Record<string, string> = {};
    try {
      headers = JSON.parse(req.headersJson) as Record<string, string>;
    } catch (e) {
      headers = {};
    }
    const followed = await NativeHttpBridge.follow(url, req.method, headers, req.body, req.wantBytes);
    const resp = followed.resp;
    const finalUrl = followed.url;
    const headersJson = JSON.stringify(NativeHttpBridge.flattenHeaders(resp.header));
    if (NativeHttpBridge.isChallenge(resp, finalUrl)) {
      return {
        status: resp.responseCode,
        statusText: NativeHttpBridge.statusTextOf(resp.responseCode),
        headersJson: headersJson,
        body: '',
        error: NativeHttpBridge.challengeError(finalUrl),
        url: finalUrl,
      };
    }
    let body = '';
    if (req.wantBytes) {
      body = NativeHttpBridge.toBase64(resp.result as ArrayBuffer);
    } else {
      body = resp.result as string;
    }
    return {
      status: resp.responseCode,
      statusText: NativeHttpBridge.statusTextOf(resp.responseCode),
      headersJson: headersJson,
      body: body,
      error: null,
      url: finalUrl,
    };
  }

  // Zero-copy variant: fetches with expectDataType ARRAY_BUFFER and hands the
  // raw buffer to the native engine (no base64 round-trip). Challenge
  // detection is header-based only here (cf-mitigated), since the body is not
  // decoded as text on this path.
  private static async executeShared(req: JsvmBridgeRequest): Promise<JsvmSharedResult> {
    const url = req.url;
    if (url.indexOf('https://') !== 0 && url.indexOf('http://') !== 0) {
      const e = NativeHttpBridge.error(0, `仅支持 http/https 请求: ${url}`, url);
      return {
        status: e.status, statusText: e.statusText, headersJson: e.headersJson,
        body: e.body, error: e.error, url: e.url, bytes: null,
      };
    }
    let headers: Record<string, string> = {};
    try {
      headers = JSON.parse(req.headersJson) as Record<string, string>;
    } catch (e) {
      headers = {};
    }
    const followed = await NativeHttpBridge.follow(url, req.method, headers, req.body, true);
    const resp = followed.resp;
    const finalUrl = followed.url;
    const headersJson = JSON.stringify(NativeHttpBridge.flattenHeaders(resp.header));
    if (NativeHttpBridge.isChallenge(resp, finalUrl)) {
      return {
        status: resp.responseCode,
        statusText: NativeHttpBridge.statusTextOf(resp.responseCode),
        headersJson: headersJson,
        body: '',
        error: NativeHttpBridge.challengeError(finalUrl),
        url: finalUrl,
        bytes: null,
      };
    }
    return {
      status: resp.responseCode,
      statusText: NativeHttpBridge.statusTextOf(resp.responseCode),
      headersJson: headersJson,
      body: '',
      error: null,
      url: finalUrl,
      bytes: resp.result as ArrayBuffer,
    };
  }

  private static async follow(
    startUrl: string,
    methodName: string,
    headers: Record<string, string>,
    body: string,
    wantBytes: boolean
  ): Promise<NativeHttpFollowed> {
    let url = startUrl;
    let method = NativeHttpBridge.methodOf(methodName);
    let extra = body;
    for (let hop = 0; hop < 8; hop++) {
      const resp = await NativeHttpBridge.requestOnce(url, method, headers, extra, wantBytes);
      CookieJar.storeFromResponse(url, resp.header);
      if (!NativeHttpBridge.isRedirect(resp.responseCode)) {
        const followed: NativeHttpFollowed = { url: url, resp: resp };
        return followed;
      }
      const loc = NativeHttpBridge.headerValue(resp.header, 'Location');
      const next = NativeHttpBridge.resolveLocation(url, loc);
      if (next === '') {
        const followed: NativeHttpFollowed = { url: url, resp: resp };
        return followed;
      }
      if (resp.responseCode === 303 ||
        ((resp.responseCode === 301 || resp.responseCode === 302) && method === http.RequestMethod.POST)) {
        method = http.RequestMethod.GET;
        extra = '';
      }
      url = next;
    }
    throw new Error(`too many redirects: ${startUrl}`);
  }

  private static async requestOnce(
    url: string,
    method: http.RequestMethod,
    headers: Record<string, string>,
    body: string,
    wantBytes: boolean
  ): Promise<http.HttpResponse> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: NativeHttpBridge.mergeHeaders(url, headers, method, body),
        expectDataType: wantBytes ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: wantBytes ? 60000 : 20000,
        usingProtocol: http.HttpProtocol.HTTP1_1,
      };
      if (body !== '' && method !== http.RequestMethod.GET && method !== http.RequestMethod.HEAD) {
        options.extraData = body;
      }
      return await client.request(url, options);
    } finally {
      client.destroy();
    }
  }

  private static error(status: number, message: string, url: string): JsvmHttpResult {
    return {
      status: status,
      statusText: '',
      headersJson: '{}',
      body: '',
      error: message,
      url: url,
    };
  }

  private static methodOf(name: string): http.RequestMethod {
    const upper = name.toUpperCase();
    if (upper === 'POST') {
      return http.RequestMethod.POST;
    }
    if (upper === 'HEAD') {
      return http.RequestMethod.HEAD;
    }
    if (upper === 'PUT') {
      return http.RequestMethod.PUT;
    }
    if (upper === 'DELETE') {
      return http.RequestMethod.DELETE;
    }
    if (upper === 'OPTIONS') {
      return http.RequestMethod.OPTIONS;
    }
    if (upper === 'TRACE') {
      return http.RequestMethod.TRACE;
    }
    return http.RequestMethod.GET;
  }

  // Same policy as net/Http.ets: unified UA (cf_clearance binds UA + client),
  // extension header overrides, then CookieJar auto-attach. Form POSTs get a
  // default Content-Type when the extension omitted one (Madara ajax).
  private static mergeHeaders(
    url: string,
    headers: Record<string, string>,
    method: http.RequestMethod,
    body: string
  ): Record<string, string> {
    const merged: Record<string, string> = { 'User-Agent': Http.USER_AGENT };
    const keys = Object.keys(headers);
    for (const key of keys) {
      merged[key] = headers[key];
    }
    if (!NativeHttpBridge.hasKey(merged, 'Cookie')) {
      const cookie = CookieJar.headerFor(url);
      if (cookie !== '') {
        merged['Cookie'] = cookie;
      }
    }
    if (body !== '' &&
      (method === http.RequestMethod.POST || method === http.RequestMethod.PUT) &&
      !NativeHttpBridge.hasKey(merged, 'Content-Type')) {
      merged['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    return merged;
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
    const origin = NativeHttpBridge.originOf(base);
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

  private static statusTextOf(code: number): string {
    if (code === 200) {
      return 'OK';
    }
    if (code === 201) {
      return 'Created';
    }
    if (code === 204) {
      return 'No Content';
    }
    if (code === 301) {
      return 'Moved Permanently';
    }
    if (code === 302) {
      return 'Found';
    }
    if (code === 303) {
      return 'See Other';
    }
    if (code === 304) {
      return 'Not Modified';
    }
    if (code === 400) {
      return 'Bad Request';
    }
    if (code === 401) {
      return 'Unauthorized';
    }
    if (code === 403) {
      return 'Forbidden';
    }
    if (code === 404) {
      return 'Not Found';
    }
    if (code === 500) {
      return 'Internal Server Error';
    }
    if (code === 503) {
      return 'Service Unavailable';
    }
    return '';
  }

  private static hasKey(record: Record<string, string>, key: string): boolean {
    const keys = Object.keys(record);
    for (const k of keys) {
      if (k.toLowerCase() === key.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  private static flattenHeaders(header: Object): Record<string, string> {
    const flat: Record<string, string> = {};
    const raw = header as Record<string, Object>;
    const keys = Object.keys(raw);
    for (const key of keys) {
      const value = raw[key];
      if (typeof value === 'string') {
        flat[key] = value;
      } else if (Array.isArray(value)) {
        flat[key] = (value as string[]).join(', ');
      }
    }
    return flat;
  }

  // Cloudflare bot challenge: 403/503 + cf-mitigated header or well-known
  // challenge page markers (mirrors net/Http.ets detection).
  private static isChallenge(resp: http.HttpResponse, url: string): boolean {
    if (resp.responseCode !== 401 && resp.responseCode !== 403 && resp.responseCode !== 503) {
      return false;
    }
    const headers = resp.header as Record<string, Object>;
    const keys = Object.keys(headers);
    for (const key of keys) {
      if (key.toLowerCase() === 'cf-mitigated') {
        const value = headers[key];
        if (typeof value === 'string' && value.toLowerCase() === 'challenge') {
          return true;
        }
      }
    }
    if (typeof resp.result === 'string') {
      const body = resp.result as string;
      if (body.indexOf('challenge-platform') >= 0 || body.indexOf('Just a moment') >= 0) {
        return true;
      }
    }
    return false;
  }

  private static toBase64(buffer: ArrayBuffer): string {
    const helper = new util.Base64Helper();
    return helper.encodeToStringSync(new Uint8Array(buffer));
  }
}
