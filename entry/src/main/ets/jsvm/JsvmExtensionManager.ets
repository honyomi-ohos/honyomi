/*
 * Copyright (c) 2026 honyomi
 *
 * JsvmExtensionManager — main-thread facade of the JSVM extension engine.
 *
 * Responsibilities:
 *   - Installs the native HTTP bridge once (NativeHttpBridge.install()).
 *   - Spawns one dedicated JsvmWorker per installed extension: every
 *     extension executes in its own isolated JSVM_Context on a background
 *     worker thread (zero ArkWeb dependency, zero UI-thread work).
 *   - Bridges typed callMethod() requests to the worker and unwraps the
 *     adapter envelope, re-throwing challenge exceptions (WebChallengeError)
 *     so the ArkTS layer can open the verification webview and retry with
 *     the harvested token re-injected through the CookieJar.
 *   - Tracks per-extension JS heap usage (2MB budget watchdog).
 */

import { worker, MessageEvents, ErrorEvent } from '@kit.ArkTS';
import { NativeHttpBridge, WebChallengeError } from './NativeHttpBridge';
import { PluginPrefs } from './PluginPrefs';

/** Per-extension JSVM heap budget (bytes) — see architecture spec. */
export const JSVM_HEAP_BUDGET_BYTES: number = 2 * 1024 * 1024;


const READY_TIMEOUT_MS: number = 30000;
const CALL_TIMEOUT_MS: number = 190000; // > native 180s pump deadline

export interface JsvmExtensionInfo {
  key: string;
  kind: string; // 'tachiyomi' | 'simple'
  methods: string[];
}

interface PendingCall {
  resolve: (json: string) => void;
  reject: (err: Error) => void;
  timer: number;
}

interface ExtensionEntry {
  key: string;
  kind: string;
  worker: worker.ThreadWorker;
  pending: Map<number, PendingCall>;
  lastMemoryBytes: number;
  broken: boolean;
  /** unload 后的 terminate 安全网定时器 id（-1 表示未挂） */
  terminateTimer: number;
  /** 最近一次持久化的 prefs JSON，内容未变化时跳过 persist */
  lastPrefsJson: string;
}

interface WorkerEvent {
  type?: string;
  ok?: boolean;
  kind?: string;
  error?: string;
  seq?: number;
  json?: string;
  mem?: number;
  prefs?: string;
}

interface CallEnvelope {
  ok?: boolean;
  data?: object;
  error?: string;
}

export class JsvmExtensionManager {
  private static extensions: Map<string, ExtensionEntry> = new Map();
  private static initialized: boolean = false;
  private static seq: number = 0;

  /** Installs the HTTP bridge; call once on the main thread at startup. */
  static init(): void {
    if (JsvmExtensionManager.initialized) {
      return;
    }
    JsvmExtensionManager.initialized = true;
    NativeHttpBridge.install();
  }

  static isLoaded(key: string): boolean {
    const entry = JsvmExtensionManager.extensions.get(key);
    return entry !== undefined && !entry.broken;
  }

  static loadedKeys(): string[] {
    const keys: string[] = [];
    JsvmExtensionManager.extensions.forEach((entry: ExtensionEntry) => {
      if (!entry.broken) {
        keys.push(entry.key);
      }
    });
    return keys;
  }

  /** Last reported JS heap usage of an extension's engine (-1 unknown). */
  static memoryBytes(key: string): number {
    const entry = JsvmExtensionManager.extensions.get(key);
    return entry === undefined ? -1 : entry.lastMemoryBytes;
  }

  /**
   * Loads an extension: spawns its dedicated worker, creates the isolated
   * JSVM_Context, executes the script and probes the adapter capabilities.
   * `seed` is an optional JS prologue executed before the extension script
   * (used to rehydrate the persisted plugin preferences store).
   */
  static async loadExtension(key: string, code: string, seed: string = ''): Promise<JsvmExtensionInfo> {
    JsvmExtensionManager.init();
    await JsvmExtensionManager.unloadExtension(key);
    const entry = JsvmExtensionManager.spawnWorker(key);
    try {
      const kind = await JsvmExtensionManager.waitReady(entry, code, seed);
      entry.kind = kind;
      const methodsJson = await JsvmExtensionManager.callRaw(entry, '__methods', '[]');
      const methods = JsvmExtensionManager.unwrap<string[]>(methodsJson);
      const info: JsvmExtensionInfo = { key: key, kind: kind, methods: methods };
      return info;
    } catch (e) {
      await JsvmExtensionManager.unloadExtension(key);
      throw e as Error;
    }
  }

  /** Unloads an extension and releases its worker + JSVM engine. */
  static async unloadExtension(key: string): Promise<void> {
    const entry = JsvmExtensionManager.extensions.get(key);
    if (entry === undefined) {
      return;
    }
    JsvmExtensionManager.extensions.delete(key);
    JsvmExtensionManager.failAll(entry, new Error('extension unloaded'));
    try {
      entry.worker.postMessage('{"type":"destroy"}');
    } catch (e) {
      // worker already gone
    }
    const workerRef = entry.worker;
    entry.terminateTimer = setTimeout(() => {
      entry.terminateTimer = -1;
      try {
        workerRef.terminate();
      } catch (e) {
        // terminate() throws BusinessError 1003 "worker is not running"
        // when the worker has already self-terminated via workerPort.close();
        // an uncaught throw here crashes the whole app (jscrash).
      }
    }, 3000);
    // The worker self-terminates via workerPort.close(); the timer above is
    // only a safety net for wedged engines.
  }

  /**
   * Calls a normalized extension method. Returns the adapter envelope's
   * `data` payload. Throws WebChallengeError for Cloudflare challenges.
   */
  static async callData<T>(key: string, method: string, args: Array<string | number | boolean | object>): Promise<T> {
    const json = await JsvmExtensionManager.callMethod(key, method, args);
    return JsvmExtensionManager.unwrap<T>(json);
  }

  /** Calls a normalized extension method, returning the raw envelope JSON. */
  static async callMethod(key: string, method: string, args: Array<string | number | boolean | object>): Promise<string> {
    const entry = JsvmExtensionManager.extensions.get(key);
    if (entry === undefined) {
      throw new Error('ext_not_loaded');
    }
    if (entry.broken) {
      throw new Error('ext_broken');
    }
    return JsvmExtensionManager.callRaw(entry, method, JSON.stringify(args));
  }

  // ------------------------------------------------------------------ private

  private static spawnWorker(key: string): ExtensionEntry {
    console.info(`[JsvmExt] spawning worker for ${key}`);
    const threadWorker = new worker.ThreadWorker('entry/ets/workers/JsvmWorker.ets');
    const entry: ExtensionEntry = {
      key: key,
      kind: '',
      worker: threadWorker,
      pending: new Map<number, PendingCall>(),
      lastMemoryBytes: -1,
      broken: false,
      terminateTimer: -1,
      lastPrefsJson: ''
    };
    threadWorker.onmessage = (e: MessageEvents): void => {
      JsvmExtensionManager.onWorkerMessage(entry, e.data);
    };
    threadWorker.onerror = (err: ErrorEvent): void => {
      console.error(`[JsvmExt] worker error for ${key}: ${err.message}`);
      entry.broken = true;
      JsvmExtensionManager.failAll(entry, new Error(err.message));
    };
    threadWorker.onAllErrors = (err: ErrorEvent): void => {
      console.error(`[JsvmExt] worker allErrors for ${key}: ${err.message}`);
      entry.broken = true;
      JsvmExtensionManager.failAll(entry, new Error(err.message));
    };
    threadWorker.onexit = (code: number): void => {
      console.info(`[JsvmExt] worker exit for ${key}: code=${code}`);
      // worker 已退出：清除 terminate 安全网定时器
      if (entry.terminateTimer >= 0) {
        clearTimeout(entry.terminateTimer);
        entry.terminateTimer = -1;
      }
      // Worker gone without an error event: fail any still-pending calls so
      // callers do not hang until CALL_TIMEOUT_MS.
      entry.broken = true;
      JsvmExtensionManager.failAll(entry, new Error('worker exited unexpectedly'));
    };
    JsvmExtensionManager.extensions.set(key, entry);
    return entry;
  }

  private static onWorkerMessage(entry: ExtensionEntry, data: Object): void {
    let event: WorkerEvent;
    try {
      event = (typeof data === 'string' ? JSON.parse(data as string) : data) as WorkerEvent;
    } catch (e) {
      return;
    }
    if (event.type === 'destroyed') {
      // worker 即将自行退出：清除 terminate 安全网定时器
      if (entry.terminateTimer >= 0) {
        clearTimeout(entry.terminateTimer);
        entry.terminateTimer = -1;
      }
      return;
    }
    if (event.type === 'ready') {
      const pending = entry.pending.get(READY_SEQ);
      if (pending === undefined) {
        return;
      }
      entry.pending.delete(READY_SEQ);
      clearTimeout(pending.timer);
      if (event.ok === true) {
        pending.resolve(event.kind ?? '');
      } else {
        pending.reject(new Error(event.error ?? 'ext_init_failed'));
      }
      if (event.prefs !== undefined && event.prefs !== '' && event.prefs !== entry.lastPrefsJson) {
        entry.lastPrefsJson = event.prefs;
        PluginPrefs.persist(entry.key, event.prefs);
      }
      return;
    }
    if (event.type === 'result' && event.seq !== undefined) {
      const pending = entry.pending.get(event.seq);
      if (pending === undefined) {
        return;
      }
      entry.pending.delete(event.seq);
      clearTimeout(pending.timer);
      if (event.mem !== undefined && event.mem >= 0) {
        entry.lastMemoryBytes = event.mem;
      }
      if (event.prefs !== undefined && event.prefs !== '' && event.prefs !== entry.lastPrefsJson) {
        entry.lastPrefsJson = event.prefs;
        PluginPrefs.persist(entry.key, event.prefs);
      }
      if (event.ok === true) {
        pending.resolve(event.json ?? '{"ok":false,"error":"empty result"}');
      } else {
        pending.reject(new Error(event.json ?? 'ext_call_failed'));
      }
    }
    // 'ready' / 'destroyed' are consumed via callRaw, nothing else to do here.
  }

  private static waitReady(entry: ExtensionEntry, code: string, seed: string): Promise<string> {
    const promise = new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => {
        entry.pending.delete(READY_SEQ);
        reject(new Error('ext_init_timeout'));
      }, READY_TIMEOUT_MS);
      entry.pending.set(READY_SEQ, {
        resolve: (json: string): void => {
          resolve(json);
        },
        reject: (err: Error): void => {
          reject(err);
        },
        timer: timer
      });
    });
    const initMessage: Record<string, Object> = { 'type': 'init', 'code': seed + code };
    try {
      entry.worker.postMessage(JSON.stringify(initMessage));
    } catch (e) {
      throw new Error(`post init message failed: ${e}`);
    }
    return promise;
  }

  private static callRaw(entry: ExtensionEntry, method: string, argsJson: string): Promise<string> {
    JsvmExtensionManager.seq += 1;
    const seq = JsvmExtensionManager.seq;
    const promise = new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (entry.pending.has(seq)) {
          entry.pending.delete(seq);
          // 调用超时：标记 broken 并强杀 worker，避免后续调用继续挂在死 worker 上
          entry.broken = true;
          JsvmExtensionManager.failAll(entry, new Error(`ext_call_timeout|${method}`));
          try {
            entry.worker.terminate();
          } catch (e) {
            // worker 可能已自行退出（BusinessError 1003）
          }
        }
      }, CALL_TIMEOUT_MS);
      entry.pending.set(seq, {
        resolve: (json: string): void => {
          resolve(json);
        },
        reject: (err: Error): void => {
          reject(err);
        },
        timer: timer
      });
    });
    const message: Record<string, Object> = {
      'type': 'call',
      'seq': seq,
      'name': method,
      'argsJson': argsJson,
      // 可能写插件偏好的调用才要求 worker dump prefs，其余沿用上次快照
      'prefsDirty': JsvmExtensionManager.prefsWritingMethod(method)
    };
    try {
      entry.worker.postMessage(JSON.stringify(message));
    } catch (e) {
      throw new Error(`post call message failed: ${e}`);
    }
    return promise;
  }

  // 可能写入插件偏好的方法（设置/过滤类）：仅这些调用标记 prefsDirty
  private static prefsWritingMethod(method: string): boolean {
    const lower = method.toLowerCase();
    return lower.indexOf('pref') >= 0 || lower.indexOf('filter') >= 0;
  }

  private static unwrap<T>(envelopeJson: string): T {
    let envelope: CallEnvelope;
    try {
      envelope = JSON.parse(envelopeJson) as CallEnvelope;
    } catch (e) {
      throw new Error('ext_invalid_json');
    }
    if (envelope.ok !== true) {
      const error = envelope.error ?? 'ext_unknown';
      if (NativeHttpBridge.isChallengeError(error)) {
        throw new WebChallengeError(NativeHttpBridge.challengeUrlOf(error));
      }
      throw new Error(error);
    }
    return envelope.data as T;
  }

  private static failAll(entry: ExtensionEntry, err: Error): void {
    entry.pending.forEach((pending: PendingCall) => {
      clearTimeout(pending.timer);
      pending.reject(err);
    });
    entry.pending.clear();
  }
}

/**
 * Special sequence reserved for the init handshake (the worker replies with
 * {"type":"ready",...} which the manager funnels through the same pending map).
 */
const READY_SEQ: number = -1;
