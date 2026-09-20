/*
 * Copyright (c) 2026 mihon-harmony
 *
 * JsvmWorker — dedicated Worker thread that owns one isolated JSVM engine.
 *
 * One instance of this worker is spawned per installed extension (lifecycle
 * isolation: each extension gets its own JSVM_VM + JSVM_Env, so extensions
 * can never contaminate each other's global scope). All engine calls are
 * executed on this background thread so parsing / searching / chapter
 * fetching never touch the UI thread; HTTP performed by extension code is
 * bridged to the main thread by the native engine (see NativeHttpBridge.ts).
 *
 * Message protocol (JSON strings, both directions):
 *   host -> worker: {"type":"init","code":"<extension js>"}
 *                   {"type":"call","seq":N,"name":"method","argsJson":"[...]"}
 *                   {"type":"destroy"}
 *   worker -> host: {"type":"ready","ok":true,"kind":"tachiyomi|simple"}
 *                   {"type":"result","seq":N,"ok":true,"json":"{...}","mem":N}
 *                   {"type":"destroyed"}
 */

import { worker, MessageEvents } from '@kit.ArkTS';
import jsvmEngine from 'libjsvmengine.so';

const workerPort: worker.ThreadWorkerGlobalScope = worker.workerPort;

let engineId: number = -1;

interface WorkerRequest {
  type?: string;
  seq?: number;
  name?: string;
  argsJson?: string;
  code?: string;
}

interface CallEnvelope {
  ok?: boolean;
  data?: object;
  error?: string;
}

function post(json: string): void {
  workerPort.postMessage(json);
}

function ready(ok: boolean, kind: string, error: string): void {
  const shape: Record<string, Object> = {
    'type': 'ready',
    'ok': ok,
    'kind': kind,
    'error': error
  };
  post(JSON.stringify(shape));
}

function result(seq: number, ok: boolean, json: string, mem: number): void {
  const shape: Record<string, Object> = {
    'type': 'result',
    'seq': seq,
    'ok': ok,
    'json': json,
    'mem': mem
  };
  post(JSON.stringify(shape));
}

function handleInit(req: WorkerRequest): void {
  try {
    engineId = jsvmEngine.createEngine();
    if (engineId < 0) {
      ready(false, '', 'JSVM 引擎创建失败');
      return;
    }
    const envelopeJson = jsvmEngine.runScript(engineId, req.code ?? '');
    const envelope = JSON.parse(envelopeJson) as CallEnvelope;
    if (envelope.ok !== true) {
      const error = envelope.error ?? '插件脚本执行失败';
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
    result(seq, false, '{"ok":false,"error":"engine not initialized"}', -1);
    return;
  }
  try {
    const json = jsvmEngine.callFunction(engineId, req.name ?? '', req.argsJson ?? '[]');
    const mem = jsvmEngine.engineMemoryBytes(engineId);
    result(seq, true, json, mem);
  } catch (e) {
    result(seq, false, JSON.stringify({ 'ok': false, 'error': (e as Error).message }), -1);
  }
}

function handleDestroy(): void {
  if (engineId >= 0) {
    jsvmEngine.destroyEngine(engineId);
    engineId = -1;
  }
  post('{"type":"destroyed"}');
  workerPort.close();
}

workerPort.onmessage = (e: MessageEvents): void => {
  let req: WorkerRequest;
  try {
    req = e.data as WorkerRequest;
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
  // Unserialization failure: nothing sensible to recover; ignore.
};
