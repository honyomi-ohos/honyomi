/*
 * Copyright (c) 2026 honyomi
 *
 * AvifWorker — dedicated Worker thread for native AVIF → JPEG conversion.
 *
 * Runs avifDecodeToJpeg() from libjsvmengine.so off the UI thread
 * (libavif/aom decode + system ImagePacker encode, ~4-5x faster than the WASM path).
 * The call is synchronous and blocking; each message is processed serially,
 * so concurrent convert() requests queue naturally in the worker's loop.
 *
 * Message protocol:
 *   host -> worker: ArrayBuffer (raw AVIF bytes, transferred)
 *   worker -> host: ArrayBuffer (JPEG bytes, transferred) on success, or
 *                   { "error": "<message>" } on failure
 */

import { ErrorEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import jsvmEngine from 'libjsvmengine.so';

/** 原生转码失败的回包结构（成功时直接回传 ArrayBuffer）。 */
interface AvifWorkerError {
  error: string;
}

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

function postError(message: string): void {
  try {
    const failure: AvifWorkerError = { error: message };
    workerPort.postMessage(failure);
  } catch (e) {
  }
}

workerPort.onmessage = (e: MessageEvents): void => {
  const src: Object = e.data;
  if (!(src instanceof ArrayBuffer)) {
    postError('avif_worker_invalid_input');
    return;
  }
  try {
    const jpeg = jsvmEngine.avifDecodeToJpeg(src);
    workerPort.postMessage(jpeg, [jpeg]);
  } catch (err) {
    postError(`${err}`);
  }
};

workerPort.onerror = (err: ErrorEvent): void => {
  postError(err.message);
};
