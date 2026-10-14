/*
 * Copyright (c) 2026 honyomi
 *
 * AvifConverter — AVIF → JPEG 转码器（JSVM + WASM）主线程门面。
 *
 * 模拟器系统的 AVIF 解码器无法解码 Photos18 的封面/页面（62980116），
 * 且 createPixelMap 失败时 Promise 永不结算（挂死），因此任何依赖系统
 * 解码的路径（含系统转码兜底）都不可行。本模块在 JSVM worker 中运行
 * @jsquash（Squoosh）的 avif 解码 + mozjpeg 编码 WASM，把 AVIF 转成
 * JPEG 落盘后交由系统 Image 显示（JPEG 显示无任何问题）。
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

import { worker, MessageEvents, ErrorEvent, util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

const READY_TIMEOUT_MS: number = 30000;
const INIT_TIMEOUT_MS: number = 60000; // wasm 编译在模拟器上可能较慢
const CALL_TIMEOUT_MS: number = 60000; // 单图转码远低于此值（PC 实测 ~200ms）

/** init 握手保留的 seq（worker 以 {"type":"ready"} 回应）。 */
const READY_SEQ: number = -1;

interface PendingCall {
  resolve: (json: string) => void;
  reject: (err: Error) => void;
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

export class AvifConverter {
  private static context: common.Context | null = null;
  private static worker: worker.ThreadWorker | null = null;
  private static pending: Map<number, PendingCall> = new Map();
  private static seq: number = 0;
  private static ready: Promise<void> | null = null;
  private static broken: boolean = false;
  private static b64Helper: util.Base64Helper = new util.Base64Helper();

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
   * AVIF → JPEG。失败抛错（调用方自行回退保留原始字节）。
   */
  static async convert(src: Uint8Array): Promise<ArrayBuffer> {
    await AvifConverter.ensureReady();
    const srcB64 = AvifConverter.b64Helper.encodeToStringSync(src);
    const envelopeJson = await AvifConverter.call('__convertAvif', JSON.stringify([srcB64]), CALL_TIMEOUT_MS);
    const envelope = JSON.parse(envelopeJson) as CallEnvelope;
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

  // ---------------- 内部实现 ----------------

  private static ensureReady(): Promise<void> {
    if (AvifConverter.ready !== null) {
      return AvifConverter.ready;
    }
    if (AvifConverter.broken) {
      return Promise.reject(new Error('avif_converter_broken'));
    }
    AvifConverter.ready = AvifConverter.bootstrap();
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
    const scriptBytes = rm.getRawFileContentSync('avif/avif_converter.js');
    const script = util.TextDecoder.create('utf-8').decodeToString(scriptBytes);
    await AvifConverter.waitReady(script);
    // 2) wasm 字节 base64 注入（经 __initWasm 逃生舱调用）
    const avifWasm = rm.getRawFileContentSync('avif/avif_dec.wasm');
    const jpegWasm = rm.getRawFileContentSync('avif/mozjpeg_enc.wasm');
    const initArgs = JSON.stringify([
      AvifConverter.b64Helper.encodeToStringSync(avifWasm),
      AvifConverter.b64Helper.encodeToStringSync(jpegWasm)
    ]);
    const envelopeJson = await AvifConverter.call('__initWasm', initArgs, INIT_TIMEOUT_MS);
    const envelope = JSON.parse(envelopeJson) as CallEnvelope;
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
      event = (typeof data === 'string' ? JSON.parse(data as string) : data) as WorkerEvent;
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
