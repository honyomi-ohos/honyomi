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
}

/** Shared (zero-copy) result: meta envelope plus the pinned response body. */
export interface JsvmSharedResult extends JsvmHttpResult {
  bytes: ArrayBuffer | null;
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
        };
        jsvmEngine.resolveHttpBytes(req.callId, JSON.stringify(meta), result.bytes);
      }).catch((e: Error) => {
        NativeHttpBridge.inflight -= 1;
        jsvmEngine.resolveHttpBytes(req.callId, JSON.stringify(NativeHttpBridge.error(0, e.message)), null);
      });
      return;
    }
    NativeHttpBridge.execute(req).then((result: JsvmHttpResult) => {
      NativeHttpBridge.inflight -= 1;
      jsvmEngine.resolveHttp(req.callId, JSON.stringify(result));
    }).catch((e: Error) => {
      NativeHttpBridge.inflight -= 1;
      jsvmEngine.resolveHttp(req.callId, JSON.stringify(NativeHttpBridge.error(0, e.message)));
    });
  }

  private static async execute(req: JsvmBridgeRequest): Promise<JsvmHttpResult> {
    const url = req.url;
    if (url.indexOf('https://') !== 0 && url.indexOf('http://') !== 0) {
      return NativeHttpBridge.error(0, `仅支持 http/https 请求: ${url}`);
    }
    let headers: Record<string, string> = {};
    try {
      headers = JSON.parse(req.headersJson) as Record<string, string>;
    } catch (e) {
      headers = {};
    }
    const client: http.HttpRequest = http.createHttp();
    try {
      const method = NativeHttpBridge.methodOf(req.method);
      const options: http.HttpRequestOptions = {
        method: method,
        header: NativeHttpBridge.mergeHeaders(url, headers),
        expectDataType: req.wantBytes ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: req.wantBytes ? 60000 : 20000,
      };
      if (req.body !== '' && method !== http.RequestMethod.GET && method !== http.RequestMethod.HEAD) {
        options.extraData = req.body;
      }
      const resp: http.HttpResponse = await client.request(url, options);
      CookieJar.storeFromResponse(url, resp.header);
      const headersJson = JSON.stringify(NativeHttpBridge.flattenHeaders(resp.header));
      if (NativeHttpBridge.isChallenge(resp, url)) {
        return {
          status: resp.responseCode,
          statusText: '',
          headersJson: headersJson,
          body: '',
          error: NativeHttpBridge.challengeError(url),
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
        statusText: '',
        headersJson: headersJson,
        body: body,
        error: null,
      };
    } finally {
      client.destroy();
    }
  }

  // Zero-copy variant: fetches with expectDataType ARRAY_BUFFER and hands the
  // raw buffer to the native engine (no base64 round-trip). Challenge
  // detection is header-based only here (cf-mitigated), since the body is not
  // decoded as text on this path.
  private static async executeShared(req: JsvmBridgeRequest): Promise<JsvmSharedResult> {
    const url = req.url;
    if (url.indexOf('https://') !== 0 && url.indexOf('http://') !== 0) {
      const e = NativeHttpBridge.error(0, `仅支持 http/https 请求: ${url}`);
      return {
        status: e.status, statusText: e.statusText, headersJson: e.headersJson,
        body: e.body, error: e.error, bytes: null,
      };
    }
    let headers: Record<string, string> = {};
    try {
      headers = JSON.parse(req.headersJson) as Record<string, string>;
    } catch (e) {
      headers = {};
    }
    const client: http.HttpRequest = http.createHttp();
    try {
      const method = NativeHttpBridge.methodOf(req.method);
      const options: http.HttpRequestOptions = {
        method: method,
        header: NativeHttpBridge.mergeHeaders(url, headers),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000,
      };
      if (req.body !== '' && method !== http.RequestMethod.GET && method !== http.RequestMethod.HEAD) {
        options.extraData = req.body;
      }
      const resp: http.HttpResponse = await client.request(url, options);
      CookieJar.storeFromResponse(url, resp.header);
      const headersJson = JSON.stringify(NativeHttpBridge.flattenHeaders(resp.header));
      if (NativeHttpBridge.isChallenge(resp, url)) {
        return {
          status: resp.responseCode,
          statusText: '',
          headersJson: headersJson,
          body: '',
          error: NativeHttpBridge.challengeError(url),
          bytes: null,
        };
      }
      return {
        status: resp.responseCode,
        statusText: '',
        headersJson: headersJson,
        body: '',
        error: null,
        bytes: resp.result as ArrayBuffer,
      };
    } finally {
      client.destroy();
    }
  }

  private static error(status: number, message: string): JsvmHttpResult {
    return {
      status: status,
      statusText: '',
      headersJson: '{}',
      body: '',
      error: message,
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
  // extension header overrides, then CookieJar auto-attach.
  private static mergeHeaders(url: string, headers: Record<string, string>): Record<string, string> {
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
    return merged;
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
