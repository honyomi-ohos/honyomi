/*
 * Copyright (c) 2026 mihon-harmony
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

/** Per-extension JSVM heap budget (bytes) — see architecture spec. */
export const JSVM_HEAP_BUDGET_BYTES: number = 2 * 1024 * 1024;

const WORKER_SCRIPT: string = 'entry/ets/workers/JsvmWorker.ets';
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
}

interface WorkerEvent {
  type?: string;
  ok?: boolean;
  kind?: string;
  error?: string;
  seq?: number;
  json?: string;
  mem?: number;
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
   */
  static async loadExtension(key: string, code: string): Promise<JsvmExtensionInfo> {
    JsvmExtensionManager.init();
    await JsvmExtensionManager.unloadExtension(key);
    const entry = JsvmExtensionManager.spawnWorker(key);
    try {
      const kind = await JsvmExtensionManager.waitReady(entry, code);
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
    setTimeout(() => {
      workerRef.terminate();
    }, 3000);
    // The worker self-terminates via workerPort.close(); the timer above is
    // only a safety net for wedged engines.
  }

  /**
   * Calls a normalized extension method. Returns the adapter envelope's
   * `data` payload. Throws WebChallengeError for Cloudflare challenges.
   */
  static async callData<T>(key: string, method: string, args: Array<string | number>): Promise<T> {
    const json = await JsvmExtensionManager.callMethod(key, method, args);
    return JsvmExtensionManager.unwrap<T>(json);
  }

  /** Calls a normalized extension method, returning the raw envelope JSON. */
  static async callMethod(key: string, method: string, args: Array<string | number>): Promise<string> {
    const entry = JsvmExtensionManager.extensions.get(key);
    if (entry === undefined) {
      throw new Error(`扩展未加载: ${key}`);
    }
    if (entry.broken) {
      throw new Error(`扩展已损坏，请重新加载: ${key}`);
    }
    return JsvmExtensionManager.callRaw(entry, method, JSON.stringify(args));
  }

  // ------------------------------------------------------------------ private

  private static spawnWorker(key: string): ExtensionEntry {
    const threadWorker = new worker.ThreadWorker(WORKER_SCRIPT);
    const entry: ExtensionEntry = {
      key: key,
      kind: '',
      worker: threadWorker,
      pending: new Map<number, PendingCall>(),
      lastMemoryBytes: -1,
      broken: false
    };
    threadWorker.onmessage = (e: MessageEvents): void => {
      JsvmExtensionManager.onWorkerMessage(entry, e.data);
    };
    threadWorker.onerror = (err: ErrorEvent): void => {
      entry.broken = true;
      JsvmExtensionManager.failAll(entry, new Error(err.message));
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
        pending.reject(new Error(event.error ?? 'JSVM 扩展初始化失败'));
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
      if (event.ok === true) {
        pending.resolve(event.json ?? '{"ok":false,"error":"empty result"}');
      } else {
        pending.reject(new Error(event.json ?? '调用失败'));
      }
    }
    // 'ready' / 'destroyed' are consumed via callRaw, nothing to do here.
  }

  private static waitReady(entry: ExtensionEntry, code: string): Promise<string> {
    const promise = new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => {
        entry.pending.delete(READY_SEQ);
        reject(new Error('JSVM 扩展初始化超时'));
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
    const initMessage: Record<string, Object> = { 'type': 'init', 'code': code };
    entry.worker.postMessage(JSON.stringify(initMessage));
    return promise;
  }

  private static callRaw(entry: ExtensionEntry, method: string, argsJson: string): Promise<string> {
    JsvmExtensionManager.seq += 1;
    const seq = JsvmExtensionManager.seq;
    const promise = new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (entry.pending.has(seq)) {
          entry.pending.delete(seq);
          reject(new Error(`扩展调用超时: ${method}`));
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
      'argsJson': argsJson
    };
    entry.worker.postMessage(JSON.stringify(message));
    return promise;
  }

  private static unwrap<T>(envelopeJson: string): T {
    let envelope: CallEnvelope;
    try {
      envelope = JSON.parse(envelopeJson) as CallEnvelope;
    } catch (e) {
      throw new Error('扩展返回无效 JSON');
    }
    if (envelope.ok !== true) {
      const error = envelope.error ?? '未知扩展错误';
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
