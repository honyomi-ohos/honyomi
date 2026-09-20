/*
 * Copyright (c) 2026 mihon-harmony
 *
 * Typed surface of libjsvmengine.so — the native JSVM extension engine.
 * All functions except initHttpDispatcher/resolveHttp are meant to be called
 * from the dedicated JsvmWorker thread; the two bridge functions run on the
 * main ArkTS thread (see NativeHttpBridge.ts).
 */

/** KotlinHttpResult shape returned to extension JS by the http bridge. */
export interface JsvmHttpResult {
  status: number;
  statusText: string;
  headersJson: string;
  body: string;
  error: string | null;
}

/** Adapter envelope returned by runScript / callFunction. */
export interface JsvmCallEnvelope {
  ok: boolean;
  data?: object;
  error?: string;
}

/** Bridge request dispatched to the main thread (JSON-decoded form). */
export interface JsvmBridgeRequest {
  callId: number;
  url: string;
  method: string;
  headersJson: string;
  body: string;
  wantBytes: boolean;
}

/**
 * Creates an isolated JSVM_VM + JSVM_Env with the native bridge globals
 * (fetch/tachiyomiHttpRequest/nativeSelector/console) pre-installed.
 * @returns engine id (>= 1), or -1 on failure.
 */
export function createEngine(): number;

/** Destroys the engine and frees its VM. Safe to call from its worker thread. */
export function destroyEngine(engineId: number): boolean;

/**
 * Executes an extension script inside the engine and appends the export
 * adapter that binds __mihonCall(). Returns a JsvmCallEnvelope JSON string.
 */
export function runScript(engineId: number, code: string): string;

/**
 * Calls a normalized extension method (see __mihonApi in the native adapter).
 * Async methods are awaited via the native microtask pump.
 * Returns a JsvmCallEnvelope JSON string.
 */
export function callFunction(engineId: number, name: string, argsJson: string): string;

/**
 * Installs the one-time http dispatcher callback (main thread). The callback
 * receives a JSON-encoded JsvmBridgeRequest and MUST eventually answer with
 * resolveHttp(callId, resultJson).
 */
export function initHttpDispatcher(onRequest: (reqJson: string) => void): boolean;

/**
 * Resolves a pending bridge request; wakes the blocked worker thread.
 * resultJson is a JSON-encoded JsvmHttpResult.
 */
export function resolveHttp(callId: number, resultJson: string): boolean;

/** Current JS heap usage of the engine in bytes (-1 when unknown). */
export function engineMemoryBytes(engineId: number): number;
