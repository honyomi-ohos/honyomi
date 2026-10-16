/*
 * Copyright (c) 2026 honyomi
 *
 * AvifConverter — AVIF → JPEG 转码器主线程门面。
 *
 * 模拟器系统的 AVIF 解码器无法解码 Photos18 的封面/页面（62980116），
 * 且 createPixelMap 失败时 Promise 永不结算（挂死），因此任何依赖系统
 * 解码的路径（含系统转码兜底）都不可行。
 *
 * 实现：AvifWorker.ets 中调用 libjsvmengine.so 的 avifDecodeToJpeg
 * （libavif/aom 解码 + 系统 ImagePacker JPEG 编码，质量 88），请求在
 * worker 内串行排队，较早期 WASM 路径快约 4~5 倍。
 *
 * 失败语义：convert() 抛错（worker 不可用/超时/解码失败），调用方自行
 * 回退保留原始字节。worker 崩溃/超时后置 nativeBroken，后续请求立即
 * 失败且不再重建 worker（进程内自愈不可靠，避免反复挂死）。
 */

import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const NATIVE_CALL_TIMEOUT_MS: number = 15000; // 解码是纯 CPU 有界操作

interface NativePendingCall {
  resolve: (jpeg: ArrayBuffer | null) => void;
  timer: number;
}

export class AvifConverter {
  // 原生路径状态（libjsvmengine.so avifDecodeToJpeg，AvifWorker 串行执行）
  private static nativeWorker: worker.ThreadWorker | null = null;
  private static nativePending: NativePendingCall[] = [];
  private static nativeBroken: boolean = false;

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
   * AVIF → JPEG（原生 libavif + 系统 ImagePacker）。失败抛错，调用方自
   * 行回退保留原始字节。
   */
  static async convert(src: Uint8Array): Promise<ArrayBuffer> {
    const native = await AvifConverter.convertNative(src);
    if (native === null) {
      throw new Error('avif_convert_failed');
    }
    return native;
  }

  // ---------------- 原生路径（libjsvmengine.so avifDecodeToJpeg） ----------------

  /**
   * 原生 AVIF → JPEG。返回 null 表示路径不可用/失败/超时。请求按 FIFO
   * 在 AvifWorker 内串行处理；worker 退出后置 nativeBroken，后续请求直
   * 接失败，不再重建。
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
        hilog.warn(0x0000, 'AvifConverter', 'native convert timeout');
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
}
