import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Http } from '../net/Http';

const DOMAIN = 0x0002;
const TAG = 'PluginHost';

// 注入到沙箱页 window.__hostBridge 的桥对象（javaScriptProxy 注册）
export class HostBridge {
  request(callId: string, method: string, payloadJson: string): void {
    PluginHost.getInstance().onRequest(callId, method, payloadJson);
  }

  result(callId: string, ok: boolean, json: string): void {
    PluginHost.getInstance().onResult(callId, ok, json);
  }

  log(level: string, message: string): void {
    hilog.info(DOMAIN, TAG, '[%{public}s] %{public}s', level, message);
  }
}

interface PendingCall {
  resolve: (json: string) => void;
  reject: (err: Error) => void;
  timer: number;
}

interface BridgeHttpPayload {
  url?: string;
  body?: string;
  headers?: Record<string, string>;
}

interface BridgePrefsPayload {
  plugin?: string;
  name?: string;
  def?: string;
  value?: string;
}

// 插件 Web 桥单例：管理隐藏 Web 引擎、双向异步调用与超时
export class PluginHost {
  private static instance: PluginHost = new PluginHost();

  static getInstance(): PluginHost {
    return PluginHost.instance;
  }

  readonly bridge: HostBridge = new HostBridge();
  private controller: webview.WebviewController | undefined = undefined;
  private prefs: preferences.Preferences | undefined = undefined;
  private pending: Map<string, PendingCall> = new Map();
  private seq: number = 0;
  private hostReady: boolean = false;
  private handshakeRetries: number = 0;
  private readyWaiters: Array<() => void> = [];

  init(context: common.UIAbilityContext): void {
    if (this.prefs === undefined) {
      const options: preferences.Options = { name: 'plugin_prefs' };
      this.prefs = preferences.getPreferencesSync(context, options);
    }
  }

  attachController(controller: webview.WebviewController): void {
    this.controller = controller;
  }

  markPageLoaded(): void {
    this.handshake();
  }

  isReady(): boolean {
    return this.hostReady;
  }

  async waitReady(): Promise<void> {
    if (this.hostReady) {
      return;
    }
    return new Promise<void>((resolve) => {
      this.readyWaiters.push(() => {
        resolve();
      });
    });
  }

  // 加载/替换沙箱内插件脚本
  async loadPlugin(key: string, manifestJson: string, scriptText: string): Promise<void> {
    await this.waitReady();
    const id = this.newCallId();
    const promise = this.makePending(id, 30000);
    const code = `__loadPlugin(${id}, ${JSON.stringify(key)}, ${JSON.stringify(manifestJson)}, ` +
      `${JSON.stringify(scriptText)})`;
    this.runJs(code);
    await promise;
  }

  // 卸载沙箱内插件（尽力而为）
  async unloadPlugin(key: string): Promise<void> {
    if (!this.hostReady) {
      return;
    }
    const id = this.newCallId();
    const promise = this.makePending(id, 8000);
    this.runJs(`__unloadPlugin(${id}, ${JSON.stringify(key)})`);
    await promise.catch((_e: Error) => {
    });
  }

  // 调用插件方法，返回其返回值的 JSON 文本
  async callPlugin(pluginKey: string, method: string, args: Array<string | number>): Promise<string> {
    await this.waitReady();
    const id = this.newCallId();
    const promise = this.makePending(id, 60000);
    const argsJson = JSON.stringify(args);
    const code = `__callPlugin(${id}, ${JSON.stringify(pluginKey)}, ${JSON.stringify(method)}, ` +
      `${JSON.stringify(argsJson)})`;
    this.runJs(code);
    return promise;
  }

  isPluginEnabled(key: string): boolean {
    if (this.prefs === undefined) {
      return true;
    }
    return !(this.prefs.getSync(`__disabled:${key}`, false) as boolean);
  }

  setPluginEnabled(key: string, enabled: boolean): void {
    if (this.prefs === undefined) {
      return;
    }
    this.prefs.putSync(`__disabled:${key}`, !enabled);
    this.prefs.flush();
  }

  // ---------------- 桥回调（来自 window.__hostBridge） ----------------

  onRequest(callId: string, method: string, payloadJson: string): void {
    this.handleRequest(callId, method, payloadJson);
  }

  onResult(callId: string, ok: boolean, json: string): void {
    const p = this.pending.get(callId);
    if (p === undefined) {
      return;
    }
    this.pending.delete(callId);
    clearTimeout(p.timer);
    if (ok) {
      p.resolve(json);
    } else {
      let msg = json;
      if (msg.length >= 2 && msg.charAt(0) === '"') {
        try {
          msg = JSON.parse(msg) as string;
        } catch (_e) {
          // 保留原文
        }
      }
      p.reject(new Error(msg));
    }
  }

  // ---------------- 内部实现 ----------------

  private async handshake(): Promise<void> {
    try {
      const t1 = await this.probeSync('typeof __hostBridge');
      const t2 = await this.probeSync('typeof __ping');
      const probeJs = `(function(){try{__hostBridge.result('0', false, JSON.stringify('probe-unused-id'));` +
        ` return 'call-ok'}catch(e){return 'call-fail: '+e.message}}())`;
      const t3 = await this.probeSync(probeJs);
      hilog.info(DOMAIN, TAG, 'probe: __hostBridge=%{public}s __ping=%{public}s call=%{public}s', t1, t2, t3);
      const id = this.newCallId();
      const promise = this.makePending(id, 8000);
      this.runJs(`__ping(${id})`);
      await promise;
      this.hostReady = true;
      const waiters = this.readyWaiters;
      this.readyWaiters = [];
      for (const w of waiters) {
        w();
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'plugin host ready');
    } catch (e) {
      this.handshakeRetries += 1;
      if (this.handshakeRetries < 10) {
        setTimeout(() => {
          this.handshake();
        }, 500);
      } else {
        hilog.error(DOMAIN, TAG, 'handshake failed after retries: %{public}s', (e as Error).message);
      }
    }
  }

  // 同步表达式探针（runJavaScript 可返回同步表达式结果）
  private async probeSync(expr: string): Promise<string> {
    if (this.controller === undefined) {
      return 'no-controller';
    }
    try {
      const r = await this.controller.runJavaScript(expr);
      return r;
    } catch (e) {
      return `probe-error: ${(e as Error).message}`;
    }
  }

  private newCallId(): string {
    this.seq += 1;
    return String(this.seq);
  }

  private makePending(id: string, timeoutMs: number): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const timer: number = setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error('插件调用超时'));
        }
      }, timeoutMs);
      const p: PendingCall = {
        resolve: resolve,
        reject: reject,
        timer: timer,
      };
      this.pending.set(id, p);
    });
  }

  private runJs(code: string): void {
    if (this.controller === undefined) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'controller not attached');
      return;
    }
    this.controller.runJavaScript(code).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'runJavaScript failed: %{public}s', e.message);
    });
  }

  private async handleRequest(callId: string, method: string, payloadJson: string): Promise<void> {
    let ok = true;
    let value: string | boolean = '';
    try {
      if (method === 'http.get') {
        const p = JSON.parse(payloadJson) as BridgeHttpPayload;
        value = await Http.get(this.checkUrl(p.url), p.headers);
      } else if (method === 'http.post') {
        const p = JSON.parse(payloadJson) as BridgeHttpPayload;
        value = await Http.post(this.checkUrl(p.url), p.body ?? '', p.headers);
      } else if (method === 'prefs.get') {
        const p = JSON.parse(payloadJson) as BridgePrefsPayload;
        const def = p.def ?? '';
        if (this.prefs === undefined) {
          value = def;
        } else {
          value = this.prefs.getSync(this.prefKey(p.plugin, p.name), def) as string;
        }
      } else if (method === 'prefs.set') {
        const p = JSON.parse(payloadJson) as BridgePrefsPayload;
        if (this.prefs !== undefined) {
          this.prefs.putSync(this.prefKey(p.plugin, p.name), p.value ?? '');
          this.prefs.flush();
        }
        value = true;
      } else {
        throw new Error(`未知桥方法: ${method}`);
      }
    } catch (e) {
      ok = false;
      value = (e as Error).message;
    }
    this.runJs(`__bridgeResolve(${callId}, ${ok}, ${JSON.stringify(JSON.stringify(value))})`);
  }

  private checkUrl(url: string | undefined): string {
    const u = url ?? '';
    if (u.indexOf('https://') !== 0 && u.indexOf('http://') !== 0) {
      throw new Error('仅支持 http/https 请求');
    }
    return u;
  }

  private prefKey(plugin: string | undefined, name: string | undefined): string {
    return `${plugin ?? ''}:${name ?? ''}`;
  }
}
