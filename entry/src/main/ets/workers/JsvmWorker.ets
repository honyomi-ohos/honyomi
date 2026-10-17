/*
 * Copyright (c) 2026 honyomi
 *
 * JsvmWorker — dedicated Worker thread that owns one isolated JSVM engine.
 *
 * One instance of this worker is spawned per installed extension (lifecycle
 * isolation: each extension gets its own JSVM_VM + JSVM_Env, so extensions
 * can never contaminate each other's global scope). All engine calls are
 * executed on this background thread so parsing / searching / chapter
 * fetching never touch the UI thread; HTTP performed by extension code is
 * bridged to the main thread by the native engine (see NativeHttpBridge.ets).
 *
 * Message protocol (JSON strings, both directions):
 *   host -> worker: {"type":"init","code":"<extension js>"}
 *                   {"type":"call","seq":N,"name":"method","argsJson":"[...]","prefsDirty":bool}
 *                   {"type":"destroy"}
 *   worker -> host: {"type":"ready","ok":true,"kind":"simple"}
 *                   {"type":"result","seq":N,"ok":true,"json":"{...}","mem":N}
 *                   {"type":"destroyed"}
 */

import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import jsvmEngine from 'libjsvmengine.so';

const DOMAIN = 0x0000;
const TAG = 'JsvmWorker';
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

hilog.info(DOMAIN, TAG, 'module loaded');

let engineId: number = -1;
// 上一次 dump 的 prefs 快照：仅 prefsDirty 调用或无快照时才重新 dump
let prefsSnapshot: string = '';

interface WorkerRequest {
  type?: string;
  seq?: number;
  name?: string;
  argsJson?: string;
  code?: string;

  /** 宿主标记：该调用可能写入插件偏好（true 时才 dump prefs） */
  prefsDirty?: boolean;
}

interface CallEnvelope {
  ok?: boolean;
  data?: object;
  error?: string;
}

// 解析引擎返回的调用信封：畸形/非对象 JSON 回退为空信封，避免后续字段读取崩溃
function parseEnvelope(json: string): CallEnvelope {
  try {
    const parsed = JSON.parse(json) as CallEnvelope;
    if (parsed === undefined || parsed === null || typeof parsed !== 'object') {
      return {};
    }
    return parsed;
  } catch (_e) {
    return {};
  }
}

function post(json: string): void {
  try {
    workerPort.postMessage(json);
  } catch (e) {
  }
}

function ready(ok: boolean, kind: string, error: string): void {
  const prefs = dumpPrefs();
  if (prefs !== '') {
    prefsSnapshot = prefs;
  }
  const shape: Record<string, Object> = {
    'type': 'ready',
    'ok': ok,
    'kind': kind,
    'error': error,
    'prefs': prefs
  };
  post(JSON.stringify(shape));
}

function result(seq: number, ok: boolean, json: string, mem: number, prefs: string): void {
  const shape: Record<string, Object> = {
    'type': 'result',
    'seq': seq,
    'ok': ok,
    'json': json,
    'mem': mem,
    'prefs': prefs
  };
  post(JSON.stringify(shape));
}

function dumpPrefs(): string {
  if (engineId < 0) {
    return '';
  }
  try {
    const envelopeJson = jsvmEngine.callFunction(engineId, '__prefsDump', '[]');
    const envelope = parseEnvelope(envelopeJson);
    if (envelope.ok === true && envelope.data !== undefined) {
      return JSON.stringify(envelope.data);
    }
  } catch (e) {
    // prefs dump is best-effort
  }
  return '';
}

function handleInit(req: WorkerRequest): void {
  try {
    hilog.info(DOMAIN, TAG, 'init start');
    engineId = jsvmEngine.createEngine();
    if (engineId < 0) {
      ready(false, '', 'engine_create_failed');
      return;
    }
    const envelopeJson = jsvmEngine.runScript(engineId, req.code ?? '');
    const envelope = parseEnvelope(envelopeJson);
    if (envelope.ok !== true) {
      const error = envelope.error ?? 'script_failed';
      jsvmEngine.destroyEngine(engineId);
      engineId = -1;
      ready(false, '', error);
      return;
    }
    const kind = typeof envelope.data === 'string' ? envelope.data as string : '';
    ready(true, kind, '');
  } catch (e) {
    if (engineId >= 0) {
      jsvmEngine.destroyEngine(engineId);
      engineId = -1;
    }
    ready(false, '', (e as Error).message);
  }
}

function handleCall(req: WorkerRequest): void {
  const seq = req.seq ?? -1;
  if (engineId < 0) {
    result(seq, false, '{"ok":false,"error":"engine not initialized"}', -1, '');
    return;
  }
  try {
    const json = jsvmEngine.callFunction(engineId, req.name ?? '', req.argsJson ?? '[]');
    const mem = jsvmEngine.engineMemoryBytes(engineId);
    // 仅当调用可能写偏好（宿主 prefsDirty 标志）或尚无快照时才 dumpPrefs，
    // 否则沿用上次快照，消除每次调用的引擎往返
    if (req.prefsDirty === true || prefsSnapshot === '') {
      const fresh = dumpPrefs();
      if (fresh !== '') {
        prefsSnapshot = fresh;
      }
    }
    result(seq, true, json, mem, prefsSnapshot);
  } catch (e) {
    result(seq, false, JSON.stringify({ 'ok': false, 'error': (e as Error).message }), -1, '');
  }
}

function handleDestroy(): void {
  if (engineId >= 0) {
    jsvmEngine.destroyEngine(engineId);
    engineId = -1;
  }
  post('{"type":"destroyed"}');
  try {
    workerPort.close();
  } catch (e) {
  }
}

workerPort.onmessage = (e: MessageEvents): void => {
  let req: WorkerRequest;
  try {
    const parsed = (typeof e.data === 'string' ? JSON.parse(e.data as string) : e.data) as WorkerRequest;
    if (parsed === undefined || parsed === null || typeof parsed !== 'object') {
      return;
    }
    req = parsed;
  } catch (err) {
    return;
  }
  if (req === undefined || req === null) {
    return;
  }
  if (req.type === 'init') {
    handleInit(req);
  } else if (req.type === 'call') {
    handleCall(req);
  } else if (req.type === 'destroy') {
    handleDestroy();
  }
};

workerPort.onmessageerror = (): void => {
  // Unserialization failure: nothing sensible to recover; log and ignore.
  hilog.warn(DOMAIN, TAG, 'host message deserialization failed');
};
