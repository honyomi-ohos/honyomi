/*
 * Copyright (c) 2026 honyomi
 *
 * AvifConverter — AVIF → JPEG 转码器主线程门面。
 *
 * 模拟器系统的 AVIF 解码器无法解码 Photos18 的封面/页面（62980116），
 * 且 createPixelMap 失败时 Promise 永不结算（挂死），因此任何依赖系统
 * 解码的路径（含系统转码兜底）都不可行。
 *
 * 快路径（原生）：AvifWorker.ets 中调用 libjsvmengine.so 的
 *   avifDecodeToJpeg（libavif/aom 解码 + turbojpeg 编码，质量 88/4:4:4），
 *   较 WASM 快约 4~5 倍，请求在 worker 内串行排队。
 *
 * 兜底路径（WASM）：本模块在 JSVM worker 中运行 @jsquash（Squoosh）的
 *   avif 解码 + mozjpeg 编码 WASM，把 AVIF 转成 JPEG 落盘后交由系统
 *   Image 显示（JPEG 显示无任何问题）。
 *
 * 组成：
 *   rawfile avif/avif_converter.js  自包含转换脚本（经典脚本，经 ADAPTER_JS
 *                                    的 "__" 逃生舱暴露 __initWasm/__convertAvif）
 *   rawfile avif/avif_dec.wasm      libavif+dav1d 解码器（1.17MB）
 *   rawfile avif/mozjpeg_enc.wasm   mozjpeg 编码器（251KB）
 *
 * worker 协议复用 JsvmWorker.ets（init/call/destroy）；wasm 字节以 base64
 * 经 callFunction 参数注入 JSVM（一次性，~1.9MB）。
 */

import { ErrorEvent, MessageEvents, util, worker } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const READY_TIMEOUT_MS: number = 30000;
const INIT_TIMEOUT_MS: number = 60000; // wasm 编译在模拟器上可能较慢
const CALL_TIMEOUT_MS: number = 60000; // 单图转码远低于此值（PC 实测 ~200ms）
const NATIVE_CALL_TIMEOUT_MS: number = 15000; // 原生路径安全绳：解码是纯 CPU 有界操作

/** init 握手保留的 seq（worker 以 {"type":"ready"} 回应）。 */
const READY_SEQ: number = -1;

interface PendingCall {
  resolve: (json: string) => void;
  reject: (err: Error) => void;
  timer: number;
}

interface NativePendingCall {
  resolve: (jpeg: ArrayBuffer | null) => void;
  timer: number;
}

interface WorkerEvent {
  type?: string;
  ok?: boolean;
  kind?: string;
  error?: string;
  seq?: number;
  json?: string;
}

interface CallEnvelope {
  ok?: boolean;
  data?: string;
  error?: string;
}

// 解析调用信封：畸形/非对象 JSON 一律回退为失败信封
function parseEnvelope(json: string): CallEnvelope {
  try {
    const parsed = JSON.parse(json) as CallEnvelope;
    if (parsed === undefined || parsed === null || typeof parsed !== 'object') {
      return { ok: false, error: 'invalid_envelope' };
    }
    return parsed;
  } catch (_e) {
    return { ok: false, error: 'invalid_envelope' };
  }
}

export class AvifConverter {
  private static context: common.Context | null = null;
  private static worker: worker.ThreadWorker | null = null;
  private static pending: Map<number, PendingCall> = new Map();
  private static seq: number = 0;
  private static ready: Promise<void> | null = null;
  private static broken: boolean = false;
  private static b64Helper: util.Base64Helper = new util.Base64Helper();
  // 原生快路径状态（libjsvmengine.so avifDecodeToJpeg，AvifWorker 串行执行）
  private static nativeWorker: worker.ThreadWorker | null = null;
  private static nativePending: NativePendingCall[] = [];
  private static nativeBroken: boolean = false;

  /** EntryAbility 启动时注入上下文（rawfile 读取用）。 */
  static init(context: common.Context): void {
    AvifConverter.context = context;
  }

  /** ftyp 盒嗅探：'ftyp' + 'avif'/'avis' 品牌。 */
  static isAvif(bytes: Uint8Array): boolean {
    if (bytes.length < 12) {
      return false;
    }
    if (bytes[4] !== 0x66 || bytes[5] !== 0x74 || bytes[6] !== 0x79 || bytes[7] !== 0x70) {
      return false; // 'ftyp'
    }
    const isAvifBrand: boolean = bytes[8] === 0x61 && bytes[9] === 0x76 &&
      bytes[10] === 0x69 && bytes[11] === 0x66; // 'avif'
    const isAvisBrand: boolean = bytes[8] === 0x61 && bytes[9] === 0x76 &&
      bytes[10] === 0x69 && bytes[11] === 0x73; // 'avis'
    return isAvifBrand || isAvisBrand;
  }

  /**
   * AVIF → JPEG。优先走原生 libavif/turbojpeg 快路径，失败静默回退 WASM
   * 转码器；两条路径都失败时抛错（调用方自行回退保留原始字节）。
   */
  static async convert(src: Uint8Array): Promise<ArrayBuffer> {
    const native = await AvifConverter.convertNative(src);
    if (native !== null) {
      return native;
    }
    await AvifConverter.ensureReady();
    const srcB64 = AvifConverter.b64Helper.encodeToStringSync(src);
    const envelopeJson = await AvifConverter.call('__convertAvif', JSON.stringify([srcB64]), CALL_TIMEOUT_MS);
    const envelope = parseEnvelope(envelopeJson);
    if (envelope.ok !== true || envelope.data === undefined) {
      throw new Error(envelope.error ?? 'avif_convert_failed');
    }
    const decoded = AvifConverter.b64Helper.decodeSync(envelope.data);
    // 拷贝出精确长度的 ArrayBuffer（落盘写接口不接受 TypedArray 视图）
    const out = new ArrayBuffer(decoded.byteLength);
    const view = new Uint8Array(out);
    view.set(decoded);
    return out;
  }

  // ---------------- 原生快路径（libjsvmengine.so avifDecodeToJpeg） ----------------

  /**
   * 原生 AVIF → JPEG。返回 null 表示原生路径不可用/失败/超时，调用方回退
   * WASM。请求按 FIFO 在 AvifWorker 内串行处理；worker 退出后置
   * nativeBroken，后续请求直接回退，不再重建。
   */
  private static convertNative(src: Uint8Array): Promise<ArrayBuffer | null> {
    if (AvifConverter.nativeBroken) {
      return Promise.resolve(null);
    }
    // 拷贝出独立 ArrayBuffer：postMessage 转移会 detach 原缓冲，且视图可能
    // 只是更大缓冲的一段（fs.readSync/Http.getBuffer 场景）
    const transfer = src.slice().buffer;
    return new Promise<ArrayBuffer | null>((resolve, _reject) => {
      const threadWorker = AvifConverter.ensureNativeWorker();
      if (threadWorker === null) {
        resolve(null);
        return;
      }
      const timer = setTimeout(() => {
        hilog.warn(0x0000, 'AvifConverter', 'native convert timeout, falling back to wasm');
        AvifConverter.nativeBroken = true;
        AvifConverter.failAllNative(null);
        AvifConverter.killNativeWorker();
      }, NATIVE_CALL_TIMEOUT_MS);
      AvifConverter.nativePending.push({ resolve: resolve, timer: timer });
      threadWorker.postMessage(transfer, [transfer]);
    });
  }

  private static ensureNativeWorker(): worker.ThreadWorker | null {
    if (AvifConverter.nativeWorker !== null) {
      return AvifConverter.nativeWorker;
    }
    try {
      const threadWorker = new worker.ThreadWorker('entry/ets/workers/AvifWorker.ets');
      threadWorker.onmessage = (e: MessageEvents): void => {
        AvifConverter.onNativeMessage(e.data);
      };
      threadWorker.onerror = (err: ErrorEvent): void => {
        hilog.warn(0x0000, 'AvifConverter', 'native worker error: %{public}s', err.message);
        AvifConverter.failAllNative(null);
      };
      threadWorker.onAllErrors = (err: ErrorEvent): void => {
        hilog.warn(0x0000, 'AvifConverter', 'native worker allErrors: %{public}s', err.message);
        AvifConverter.failAllNative(null);
      };
      threadWorker.onexit = (_code: number): void => {
        AvifConverter.nativeBroken = true;
        AvifConverter.nativeWorker = null;
        AvifConverter.failAllNative(null);
      };
      AvifConverter.nativeWorker = threadWorker;
      return threadWorker;
    } catch (e) {
      hilog.warn(0x0000, 'AvifConverter', 'native worker unavailable: %{public}s', `${e}`);
      AvifConverter.nativeBroken = true;
      return null;
    }
  }

  private static onNativeMessage(data: Object): void {
    const pending = AvifConverter.nativePending.shift();
    if (pending === undefined) {
      return;
    }
    clearTimeout(pending.timer);
    if (data instanceof ArrayBuffer) {
      pending.resolve(data);
    } else {
      hilog.warn(0x0000, 'AvifConverter', 'native convert failed: %{public}s', `${data}`);
      pending.resolve(null);
    }
  }

  private static failAllNative(result: ArrayBuffer | null): void {
    while (AvifConverter.nativePending.length > 0) {
      const pending = AvifConverter.nativePending.shift();
      if (pending === undefined) {
        break;
      }
      clearTimeout(pending.timer);
      pending.resolve(result);
    }
  }

  private static killNativeWorker(): void {
    const threadWorker = AvifConverter.nativeWorker;
    AvifConverter.nativeWorker = null;
    if (threadWorker !== null) {
      try {
        threadWorker.terminate();
      } catch (e) {
        // worker 可能已自行退出（BusinessError 1003）
      }
    }
  }

  // ---------------- 内部实现 ----------------

  private static ensureReady(): Promise<void> {
    if (AvifConverter.ready !== null) {
      return AvifConverter.ready;
    }
    if (AvifConverter.broken) {
      return Promise.reject(new Error('avif_converter_broken'));
    }
    AvifConverter.ready = AvifConverter.bootstrap().catch((e: Error): Promise<void> => {
      // bootstrap 失败不缓存 rejected promise：清掉 worker 并复位缓存，
      // 下次 convert() 用新 worker 重试（原实现会永久复用失败结果）
      AvifConverter.ready = null;
      AvifConverter.killWorker();
      throw new Error(`${e}`);
    });
    return AvifConverter.ready;
  }

  private static async bootstrap(): Promise<void> {
    const context = AvifConverter.context;
    if (context === null) {
      throw new Error('avif_converter_not_initialized');
    }
    const rm = context.resourceManager;
    const threadWorker = new worker.ThreadWorker('entry/ets/workers/JsvmWorker.ets');
    AvifConverter.worker = threadWorker;
    threadWorker.onmessage = (e: MessageEvents): void => {
      AvifConverter.onWorkerMessage(e.data);
    };
    threadWorker.onerror = (err: ErrorEvent): void => {
      AvifConverter.failWorker(err.message);
    };
    threadWorker.onAllErrors = (err: ErrorEvent): void => {
      AvifConverter.failWorker(err.message);
    };
    threadWorker.onexit = (code: number): void => {
      AvifConverter.broken = true;
      AvifConverter.failAll(new Error('avif_worker_exited'));
    };
    // 1) 转换脚本（rawfile，经典脚本）注入 worker 的 JSVM
    let scriptBytes: Uint8Array;
    try {
      scriptBytes = rm.getRawFileContentSync('avif/avif_converter.js');
    } catch (e) {
      throw new Error(`read avif converter script failed: ${e}`);
    }
    const script = util.TextDecoder.create('utf-8').decodeToString(scriptBytes);
    await AvifConverter.waitReady(script);
    // 2) wasm 字节 base64 注入（经 __initWasm 逃生舱调用）
    let avifWasm: Uint8Array;
    let jpegWasm: Uint8Array;
    try {
      avifWasm = rm.getRawFileContentSync('avif/avif_dec.wasm');
      jpegWasm = rm.getRawFileContentSync('avif/mozjpeg_enc.wasm');
    } catch (e) {
      throw new Error(`read avif wasm failed: ${e}`);
    }
    const initArgs = JSON.stringify([
      AvifConverter.b64Helper.encodeToStringSync(avifWasm),
      AvifConverter.b64Helper.encodeToStringSync(jpegWasm)
    ]);
    const envelopeJson = await AvifConverter.call('__initWasm', initArgs, INIT_TIMEOUT_MS);
    const envelope = parseEnvelope(envelopeJson);
    if (envelope.ok !== true) {
      throw new Error(envelope.error ?? 'avif_wasm_init_failed');
    }
  }

  private static waitReady(code: string): Promise<void> {
    const threadWorker = AvifConverter.worker;
    if (threadWorker === null) {
      return Promise.reject(new Error('avif_worker_not_running'));
    }
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        AvifConverter.pending.delete(READY_SEQ);
        reject(new Error('avif_init_timeout'));
      }, READY_TIMEOUT_MS);
      AvifConverter.pending.set(READY_SEQ, {
        resolve: (_json: string): void => {
          resolve();
        },
        reject: reject,
        timer: timer
      });
      const message: Record<string, Object> = { 'type': 'init', 'code': code };
      threadWorker.postMessage(JSON.stringify(message));
    });
  }

  private static call(name: string, argsJson: string, timeoutMs: number): Promise<string> {
    const threadWorker = AvifConverter.worker;
    if (threadWorker === null) {
      return Promise.reject(new Error('avif_worker_not_running'));
    }
    AvifConverter.seq += 1;
    const seq = AvifConverter.seq;
    return new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (AvifConverter.pending.has(seq)) {
          AvifConverter.pending.delete(seq);
          AvifConverter.broken = true;
          AvifConverter.failAll(new Error(`avif_call_timeout|${name}`));
          AvifConverter.killWorker();
        }
      }, timeoutMs);
      AvifConverter.pending.set(seq, {
        resolve: (json: string): void => {
          resolve(json);
        },
        reject: (err: Error): void => {
          reject(err);
        },
        timer: timer
      });
      const message: Record<string, Object> = {
        'type': 'call',
        'seq': seq,
        'name': name,
        'argsJson': argsJson
      };
      threadWorker.postMessage(JSON.stringify(message));
    });
  }

  private static onWorkerMessage(data: Object): void {
    let event: WorkerEvent;
    try {
      const parsed = (typeof data === 'string' ? JSON.parse(data as string) : data) as WorkerEvent;
      if (parsed === undefined || parsed === null || typeof parsed !== 'object') {
        return;
      }
      event = parsed;
    } catch (e) {
      return;
    }
    if (event.type === 'ready') {
      const pending = AvifConverter.pending.get(READY_SEQ);
      if (pending === undefined) {
        return;
      }
      AvifConverter.pending.delete(READY_SEQ);
      clearTimeout(pending.timer);
      if (event.ok === true) {
        pending.resolve(event.kind ?? '');
      } else {
        pending.reject(new Error(event.error ?? 'avif_init_failed'));
      }
      return;
    }
    if (event.type === 'result' && event.seq !== undefined) {
      const pending = AvifConverter.pending.get(event.seq);
      if (pending === undefined) {
        return;
      }
      AvifConverter.pending.delete(event.seq);
      clearTimeout(pending.timer);
      if (event.ok === true) {
        pending.resolve(event.json ?? '{"ok":false,"error":"empty result"}');
      } else {
        pending.reject(new Error(event.json ?? 'avif_call_failed'));
      }
    }
  }

  private static failWorker(message: string): void {
    AvifConverter.broken = true;
    AvifConverter.failAll(new Error(message));
  }

  private static failAll(err: Error): void {
    AvifConverter.pending.forEach((pending: PendingCall) => {
      clearTimeout(pending.timer);
      pending.reject(err);
    });
    AvifConverter.pending.clear();
  }

  private static killWorker(): void {
    const threadWorker = AvifConverter.worker;
    AvifConverter.worker = null;
    if (threadWorker !== null) {
      try {
        threadWorker.terminate();
      } catch (e) {
        // worker 可能已自行退出（BusinessError 1003）
      }
    }
  }
}
