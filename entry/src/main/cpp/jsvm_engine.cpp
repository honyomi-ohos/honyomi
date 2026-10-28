/*
 * Copyright (c) 2026 honyomi
 *
 * JSVM Extension Engine — pure ECMAScript execution context for comic source
 * extensions, fully decoupled from ArkWeb.
 *
 * Architecture:
 *   - Each extension runs in an isolated JSVM_VM + JSVM_Env pair (lifecycle
 *     isolation, no shared global scope between extensions).
 *   - The engine is created / driven / destroyed from a dedicated worker
 *     thread (see ets/workers/JsvmWorker.ets); it never touches the UI thread.
 *   - JSVM has no network or DOM capabilities, so this module injects:
 *       * __nativeHttpRequest(url, method, headersJson, body, wantBytes)
 *         A SYNCHRONOUS bridge: the calling worker thread blocks on a
 *         condition variable while the request is dispatched through a
 *         napi_threadsafe_function to the main ArkTS thread, executed via
 *         @ohos.net.http (with CookieJar / Referer support) and resolved back
 *         through resolveHttp().
 *       * nativeSelector(html, cssQuery)
 *         Lexbor HTML parser + CSS selectors (html_selector.cpp).
 *       * __nativeLog(level, message) — hilog bridge.
 *       * __nativeRandomBytes(n) — libohcrypto (CryptoArchitectureKit C API)
 *         hardware-entropy CSPRNG; backs crypto.getRandomValues in the shim.
 *         Installed as an ordinary configurable global (not a JSVM_DEFAULT
 *         CreateEnv binding) and captured/deleted by plugin_runtime_jsvm.js
 *         (host.ts natives closure), never visible to plugin code.
 *   - A JS bootstrap (BOOTSTRAP_JS) builds fetch()/Response-like objects and
 *     console on top of the raw natives. createEngine(pluginKey) stamps that
 *     key into console, so plugin code logs with console.* and never names
 *     itself. plugin_runtime_jsvm.js (prepended by
 *     PluginService) adds the $ DSL, CommonJS, URL/atob/crypto.subtle, prefs.
 *     An adapter (ADAPTER_JS) is appended after each extension script to
 *     bind host-DSL plugins (module.exports with getPopularWorks) and
 *     simple-contract extensions (globalThis.extension) into one uniform
 *     __honyomiCall() entry, with a promise trampoline
 *     (__PENDING__ / __honyomiPoll) driven by the native microtask pump.
 */

#include "html_selector.h"

// Enables OH_JSVM_CreateArrayBufferFromExternalMemory (zero-copy ArrayBuffer).
#define JSVM_EXPERIMENTAL
#include "ark_runtime/jsvm.h"
#include "CryptoArchitectureKit/crypto_architecture_kit.h"
#include "hilog/log.h"
#include "napi/native_api.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#define JSVM_LOG_DOMAIN 0x0002
#define JSVM_LOG_TAG "JsvmEngine"
#define ENGINE_CALL_TIMEOUT_S 180
#define HTTP_BRIDGE_TIMEOUT_S 180

// ============================================================================
// Engine registry
// ============================================================================

struct Engine {
    uint32_t id;
    JSVM_VM vm;
    JSVM_Env env;
};

static std::mutex g_enginesLock;
static std::unordered_map<uint32_t, Engine *> g_engines;
static std::atomic<uint32_t> g_nextEngineId{1};
static std::atomic<bool> g_jsvmInited{false};
// Serializes JSVM init + VM creation across worker threads: a second engine
// created while OH_JSVM_Init is still running crashes in v8::Isolate::New
// (observed deterministically on x86_64 when two workers start concurrently).
static std::mutex g_createEngineLock;

// ============================================================================
// HTTP bridge state (worker blocks here while main thread performs the request)
// ============================================================================

struct HttpTask {
    uint64_t callId;
    std::string reqJson;
};

struct SharedBody; // defined below (shared-body registry)

struct PendingHttp {
    std::mutex mtx;
    std::condition_variable cv;
    bool done = false;
    std::string resultJson;
    SharedBody *sharedBody = nullptr; // pinned by g_sharedBodies until released
};

static std::mutex g_pendingLock;
static std::unordered_map<uint64_t, std::shared_ptr<PendingHttp>> g_pending;
static std::atomic<uint64_t> g_nextCallId{1};

static napi_threadsafe_function g_httpTsf = nullptr;
static std::mutex g_tsfLock;

// ============================================================================
// Shared-body registry (zero-copy HTTP pipeline)
//
// The main thread pins the ArkTS response ArrayBuffer with a napi_ref
// (ResolveHttpBytes); the worker wraps the SAME memory in a JSVM external
// ArrayBuffer (OH_JSVM_CreateArrayBufferFromExternalMemory). When the JS side
// garbage-collects that buffer, the finalize callback posts a release task
// back through the TSF; ReleaseHttpBuffer (main thread) then drops the
// napi_ref. Release tasks reuse the HttpTask channel with
// reqJson == {"type":"release"}.
// ============================================================================

struct SharedBody {
    uint64_t callId;
    napi_env nenv; // main-thread napi env that owns the ref
    napi_ref ref;
    void *data;
    size_t length;
};

static std::mutex g_bodiesLock;
static std::unordered_map<uint64_t, SharedBody *> g_sharedBodies;

// ============================================================================
// Small helpers
// ============================================================================

static std::string ToStdString(JSVM_Env env, JSVM_Value value)
{
    if (value == nullptr) {
        return "";
    }
    JSVM_ValueType type;
    if (OH_JSVM_Typeof(env, value, &type) != JSVM_OK || type != JSVM_STRING) {
        return "";
    }
    size_t size = 0;
    if (OH_JSVM_GetValueStringUtf8(env, value, nullptr, 0, &size) != JSVM_OK || size == 0) {
        return "";
    }
    std::vector<char> buf(size + 1, '\0');
    size_t written = 0;
    if (OH_JSVM_GetValueStringUtf8(env, value, buf.data(), buf.size(), &written) != JSVM_OK) {
        return "";
    }
    return std::string(buf.data(), written);
}

static JSVM_Value ToJsString(JSVM_Env env, const std::string &text)
{
    JSVM_Value value = nullptr;
    OH_JSVM_CreateStringUtf8(env, text.c_str(), text.size(), &value);
    return value;
}

static std::string ErrEnvelope(const std::string &message)
{
    return std::string("{\"ok\":false,\"error\":\"") + JsonEscape(message) + "\"}";
}

static std::string HttpErrResult(const std::string &message)
{
    return std::string("{\"status\":0,\"statusText\":\"\",\"headersJson\":\"{}\",\"body\":\"\",\"url\":\"\",\"error\":\"") +
        JsonEscape(message) + "\"}";
}

// Converts an arbitrary JS result into a string: strings pass through raw,
// everything else is JSON-stringified ("null" for unstringifiable values).
static std::string ValueToString(JSVM_Env env, JSVM_Value value)
{
    if (value == nullptr) {
        return "null";
    }
    JSVM_ValueType type;
    if (OH_JSVM_Typeof(env, value, &type) != JSVM_OK) {
        return "null";
    }
    if (type == JSVM_STRING) {
        return ToStdString(env, value);
    }
    if (type == JSVM_UNDEFINED || type == JSVM_NULL) {
        return "null";
    }
    JSVM_Value json = nullptr;
    if (OH_JSVM_JsonStringify(env, value, &json) == JSVM_OK && json != nullptr) {
        JSVM_ValueType jsonType;
        if (OH_JSVM_Typeof(env, json, &jsonType) == JSVM_OK && jsonType == JSVM_STRING) {
            return ToStdString(env, json);
        }
    }
    return "null";
}

static std::string PendingExceptionMessage(JSVM_Env env)
{
    JSVM_Value exc = nullptr;
    if (OH_JSVM_GetAndClearLastException(env, &exc) != JSVM_OK || exc == nullptr) {
        return "script execution failed";
    }
    JSVM_Value msg = nullptr;
    if (OH_JSVM_GetNamedProperty(env, exc, "message", &msg) == JSVM_OK && msg != nullptr) {
        JSVM_ValueType type;
        if (OH_JSVM_Typeof(env, msg, &type) == JSVM_OK && type == JSVM_STRING) {
            std::string text = ToStdString(env, msg);
            if (!text.empty()) {
                return text;
            }
        }
    }
    JSVM_Value json = nullptr;
    if (OH_JSVM_JsonStringify(env, exc, &json) == JSVM_OK && json != nullptr) {
        JSVM_ValueType jsonType;
        if (OH_JSVM_Typeof(env, json, &jsonType) == JSVM_OK && jsonType == JSVM_STRING) {
            return ToStdString(env, json);
        }
    }
    return "script execution failed";
}

static void PumpVm(JSVM_VM vm)
{
    bool hasMore = false;
    OH_JSVM_PumpMessageLoop(vm, &hasMore);
    OH_JSVM_PerformMicrotaskCheckpoint(vm);
}

// ----------------------------------------------------------------------------
// Shared-body helpers (see registry comment above)
// ----------------------------------------------------------------------------

// Worker/main thread: asks the main thread to drop the napi_ref pinning a
// shared HTTP body. Safe to call multiple times for one callId (idempotent
// through the registry erase).
static void PostRelease(uint64_t callId)
{
    std::lock_guard<std::mutex> lock(g_tsfLock);
    if (g_httpTsf == nullptr) {
        return; // bridge torn down: bounded leak of the pinned ref
    }
    HttpTask *task = new HttpTask{callId, "{\"type\":\"release\"}"};
    if (napi_call_threadsafe_function(g_httpTsf, task, napi_tsfn_nonblocking) != napi_ok) {
        delete task;
    }
}

// JSVM finalize callback for external ArrayBuffers over shared HTTP bodies.
static void SharedBodyFinalize(JSVM_Env env, void *finalizeData, void *finalizeHint, bool copied)
{
    (void)env;
    (void)finalizeData;
    (void)copied;
    auto *body = static_cast<SharedBody *>(finalizeHint);
    if (body != nullptr) {
        PostRelease(body->callId);
    }
}

// Main thread only: unregisters a shared body, drops its napi_ref and frees it.
static void ReleaseSharedBodyMain(napi_env env, uint64_t callId)
{
    (void)env;
    SharedBody *body = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_bodiesLock);
        auto it = g_sharedBodies.find(callId);
        if (it == g_sharedBodies.end()) {
            return;
        }
        body = it->second;
        g_sharedBodies.erase(it);
    }
    napi_delete_reference(body->nenv, body->ref);
    delete body;
}

static size_t TypedarrayElementSize(JSVM_TypedarrayType type)
{
    switch (type) {
        case JSVM_INT8_ARRAY:
        case JSVM_UINT8_ARRAY:
        case JSVM_UINT8_CLAMPED_ARRAY:
            return 1;
        case JSVM_INT16_ARRAY:
        case JSVM_UINT16_ARRAY:
            return 2;
        case JSVM_INT32_ARRAY:
        case JSVM_UINT32_ARRAY:
        case JSVM_FLOAT32_ARRAY:
            return 4;
        case JSVM_FLOAT64_ARRAY:
        case JSVM_BIGINT64_ARRAY:
        case JSVM_BIGUINT64_ARRAY:
            return 8;
        default:
            return 0;
    }
}

// Runs one raw script inside a fresh handle scope; returns the captured result
// as a string, or an error envelope when a JS exception escapes.
static std::string RunRawScript(Engine *engine, const std::string &source)
{
    JSVM_Env env = engine->env;
    JSVM_HandleScope scope = nullptr;
    if (OH_JSVM_OpenHandleScope(env, &scope) != JSVM_OK) {
        return ErrEnvelope("open handle scope failed");
    }
    std::string out;
    JSVM_Value jsSource = ToJsString(env, source);
    JSVM_Script script = nullptr;
    if (jsSource == nullptr ||
        OH_JSVM_CompileScript(env, jsSource, nullptr, 0, true, nullptr, &script) != JSVM_OK) {
        out = ErrEnvelope("script compile failed: " + PendingExceptionMessage(env));
    } else {
        JSVM_Value result = nullptr;
        if (OH_JSVM_RunScript(env, script, &result) != JSVM_OK) {
            out = ErrEnvelope(PendingExceptionMessage(env));
        } else {
            PumpVm(engine->vm);
            out = ValueToString(env, result);
        }
    }
    OH_JSVM_CloseHandleScope(env, scope);
    return out;
}

// ============================================================================
// JSVM-exposed natives
// ============================================================================

static JSVM_Value NativeHttpRequest(JSVM_Env env, JSVM_CallbackInfo info)
{
    size_t argc = 5;
    JSVM_Value args[5] = {nullptr, nullptr, nullptr, nullptr, nullptr};
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, nullptr);
    std::string url = argc > 0 ? ToStdString(env, args[0]) : "";
    std::string method = argc > 1 ? ToStdString(env, args[1]) : "GET";
    std::string headersJson = argc > 2 ? ToStdString(env, args[2]) : "{}";
    std::string body = argc > 3 ? ToStdString(env, args[3]) : "";
    bool wantBytes = false;
    if (argc > 4) {
        OH_JSVM_GetValueBool(env, args[4], &wantBytes);
    }

    const uint64_t callId = g_nextCallId.fetch_add(1);
    auto pending = std::make_shared<PendingHttp>();
    {
        std::lock_guard<std::mutex> lock(g_pendingLock);
        g_pending[callId] = pending;
    }

    std::string reqJson = std::string("{\"callId\":") + std::to_string(callId) +
        ",\"url\":\"" + JsonEscape(url) +
        "\",\"method\":\"" + JsonEscape(method) +
        "\",\"headersJson\":\"" + JsonEscape(headersJson) +
        "\",\"body\":\"" + JsonEscape(body) +
        "\",\"wantBytes\":" + (wantBytes ? "true" : "false") + "}";

    bool dispatched = false;
    {
        std::lock_guard<std::mutex> lock(g_tsfLock);
        if (g_httpTsf != nullptr) {
            HttpTask *task = new HttpTask{callId, reqJson};
            if (napi_call_threadsafe_function(g_httpTsf, task, napi_tsfn_nonblocking) == napi_ok) {
                dispatched = true;
            } else {
                delete task;
            }
        }
    }

    std::string resultJson;
    if (!dispatched) {
        resultJson = HttpErrResult("http bridge not initialized");
        std::lock_guard<std::mutex> lock(g_pendingLock);
        g_pending.erase(callId);
    } else {
        std::unique_lock<std::mutex> lock(pending->mtx);
        bool woke = pending->cv.wait_for(lock, std::chrono::seconds(HTTP_BRIDGE_TIMEOUT_S),
                                         [&pending]() { return pending->done; });
        if (!woke) {
            resultJson = HttpErrResult("http bridge timeout");
            std::lock_guard<std::mutex> plock(g_pendingLock);
            g_pending.erase(callId);
        } else {
            resultJson = pending->resultJson;
        }
    }
    return ToJsString(env, resultJson);
}

// Blocking bridge to the ArkTS side: URL-encodes text as GBK bytes via the
// system TextEncoder (NativeHttpBridge.encodeGbkUrl). Reuses the HTTP task
// channel with reqJson == {"type":"encodeGbk","callId":N,"text":"..."}; the
// answer arrives as a JsvmHttpResult envelope with the encoded string in
// `body` (resolved through resolveHttp).
static JSVM_Value NativeUrlEncodeGbk(JSVM_Env env, JSVM_CallbackInfo info)
{
    size_t argc = 1;
    JSVM_Value args[1] = {nullptr};
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, nullptr);
    std::string text = argc > 0 ? ToStdString(env, args[0]) : "";

    const uint64_t callId = g_nextCallId.fetch_add(1);
    auto pending = std::make_shared<PendingHttp>();
    {
        std::lock_guard<std::mutex> lock(g_pendingLock);
        g_pending[callId] = pending;
    }

    std::string reqJson = std::string("{\"callId\":") + std::to_string(callId) +
        ",\"type\":\"encodeGbk\",\"text\":\"" + JsonEscape(text) + "\"}";

    bool dispatched = false;
    {
        std::lock_guard<std::mutex> lock(g_tsfLock);
        if (g_httpTsf != nullptr) {
            HttpTask *task = new HttpTask{callId, reqJson};
            if (napi_call_threadsafe_function(g_httpTsf, task, napi_tsfn_nonblocking) == napi_ok) {
                dispatched = true;
            } else {
                delete task;
            }
        }
    }

    std::string resultJson;
    if (!dispatched) {
        resultJson = HttpErrResult("http bridge not initialized");
        std::lock_guard<std::mutex> lock(g_pendingLock);
        g_pending.erase(callId);
    } else {
        std::unique_lock<std::mutex> lock(pending->mtx);
        bool woke = pending->cv.wait_for(lock, std::chrono::seconds(HTTP_BRIDGE_TIMEOUT_S),
                                         [&pending]() { return pending->done; });
        if (!woke) {
            resultJson = HttpErrResult("http bridge timeout");
            std::lock_guard<std::mutex> plock(g_pendingLock);
            g_pending.erase(callId);
        } else {
            resultJson = pending->resultJson;
        }
    }
    return ToJsString(env, resultJson);
}

// Blocking bridge to the ArkTS side: registers a pinned DNS rule
// (host -> IPv4 list) into this app's netstack (Doh.pin ->
// connection.addCustomDnsRule + long-lived Doh cache pin). Reuses the HTTP
// task channel with reqJson == {"type":"dnsSet","callId":N,"host":"...",
// "ipsJson":"[\"1.2.3.4\",...]"}; the answer arrives as a JsvmHttpResult
// envelope (resolved through resolveHttp) whose `error` field marks
// rejection. Lets a plugin bypass poisoned system DNS for a specific host
// (ChannelDns-style direct addressing).
static JSVM_Value NativeDnsSet(JSVM_Env env, JSVM_CallbackInfo info)
{
    size_t argc = 2;
    JSVM_Value args[2] = {nullptr, nullptr};
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, nullptr);
    std::string host = argc > 0 ? ToStdString(env, args[0]) : "";
    std::string ipsJson = argc > 1 ? ToStdString(env, args[1]) : "[]";

    const uint64_t callId = g_nextCallId.fetch_add(1);
    auto pending = std::make_shared<PendingHttp>();
    {
        std::lock_guard<std::mutex> lock(g_pendingLock);
        g_pending[callId] = pending;
    }

    std::string reqJson = std::string("{\"callId\":") + std::to_string(callId) +
        ",\"type\":\"dnsSet\",\"host\":\"" + JsonEscape(host) +
        "\",\"ipsJson\":\"" + JsonEscape(ipsJson) + "\"}";

    bool dispatched = false;
    {
        std::lock_guard<std::mutex> lock(g_tsfLock);
        if (g_httpTsf != nullptr) {
            HttpTask *task = new HttpTask{callId, reqJson};
            if (napi_call_threadsafe_function(g_httpTsf, task, napi_tsfn_nonblocking) == napi_ok) {
                dispatched = true;
            } else {
                delete task;
            }
        }
    }

    std::string resultJson;
    if (!dispatched) {
        resultJson = HttpErrResult("http bridge not initialized");
        std::lock_guard<std::mutex> lock(g_pendingLock);
        g_pending.erase(callId);
    } else {
        std::unique_lock<std::mutex> lock(pending->mtx);
        bool woke = pending->cv.wait_for(lock, std::chrono::seconds(HTTP_BRIDGE_TIMEOUT_S),
                                         [&pending]() { return pending->done; });
        if (!woke) {
            resultJson = HttpErrResult("http bridge timeout");
            std::lock_guard<std::mutex> plock(g_pendingLock);
            g_pending.erase(callId);
        } else {
            resultJson = pending->resultJson;
        }
    }
    return ToJsString(env, resultJson);
}

// Blocking generic host-call bridge: routes an arbitrary (kind, payloadJson)
// request to the ArkTS side for capabilities that live above the JSVM layer
// (cookie store access, image pixel decode/re-encode, ...). Reuses the HTTP
// task channel with reqJson == {"type":"hostCall","callId":N,"kind":"...",
// "payload":"..."}; the answer arrives as a JsvmHttpResult envelope (resolved
// through resolveHttp) whose `body` carries the result JSON and whose `error`
// field marks rejection. New capabilities only need a kind handler on the
// ArkTS side plus a $-DSL shim; this C++ side stays untouched.
static JSVM_Value NativeHostCall(JSVM_Env env, JSVM_CallbackInfo info)
{
    size_t argc = 2;
    JSVM_Value args[2] = {nullptr, nullptr};
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, nullptr);
    std::string kind = argc > 0 ? ToStdString(env, args[0]) : "";
    std::string payloadJson = argc > 1 ? ToStdString(env, args[1]) : "{}";

    const uint64_t callId = g_nextCallId.fetch_add(1);
    auto pending = std::make_shared<PendingHttp>();
    {
        std::lock_guard<std::mutex> lock(g_pendingLock);
        g_pending[callId] = pending;
    }

    std::string reqJson = std::string("{\"callId\":") + std::to_string(callId) +
        ",\"type\":\"hostCall\",\"kind\":\"" + JsonEscape(kind) +
        "\",\"payload\":\"" + JsonEscape(payloadJson) + "\"}";

    bool dispatched = false;
    {
        std::lock_guard<std::mutex> lock(g_tsfLock);
        if (g_httpTsf != nullptr) {
            HttpTask *task = new HttpTask{callId, reqJson};
            if (napi_call_threadsafe_function(g_httpTsf, task, napi_tsfn_nonblocking) == napi_ok) {
                dispatched = true;
            } else {
                delete task;
            }
        }
    }

    std::string resultJson;
    if (!dispatched) {
        resultJson = HttpErrResult("host call bridge not initialized");
        std::lock_guard<std::mutex> lock(g_pendingLock);
        g_pending.erase(callId);
    } else {
        std::unique_lock<std::mutex> lock(pending->mtx);
        bool woke = pending->cv.wait_for(lock, std::chrono::seconds(HTTP_BRIDGE_TIMEOUT_S),
                                         [&pending]() { return pending->done; });
        if (!woke) {
            resultJson = HttpErrResult("host call bridge timeout");
            std::lock_guard<std::mutex> plock(g_pendingLock);
            g_pending.erase(callId);
        } else {
            resultJson = pending->resultJson;
        }
    }
    return ToJsString(env, resultJson);
}

static JSVM_Value NativeSelector(JSVM_Env env, JSVM_CallbackInfo info)
{
    size_t argc = 2;
    JSVM_Value args[2] = {nullptr, nullptr};
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, nullptr);
    std::string html = argc > 0 ? ToStdString(env, args[0]) : "";
    std::string query = argc > 1 ? ToStdString(env, args[1]) : "";
    return ToJsString(env, NativeSelectHtml(html, query));
}

// querySelectorAll over an ArrayBuffer / TypedArray: lexbor parses the bytes
// in place — the buffer is never copied.
static JSVM_Value NativeSelectorBuffer(JSVM_Env env, JSVM_CallbackInfo info)
{
    size_t argc = 2;
    JSVM_Value args[2] = {nullptr, nullptr};
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1 || args[0] == nullptr) {
        return ToJsString(env, "[]");
    }
    void *data = nullptr;
    size_t length = 0;
    bool isAb = false;
    bool isTa = false;
    if (OH_JSVM_IsArraybuffer(env, args[0], &isAb) == JSVM_OK && isAb) {
        if (OH_JSVM_GetArraybufferInfo(env, args[0], &data, &length) != JSVM_OK) {
            return ToJsString(env, "[]");
        }
    } else if (OH_JSVM_IsTypedarray(env, args[0], &isTa) == JSVM_OK && isTa) {
        JSVM_TypedarrayType type = JSVM_INT8_ARRAY;
        size_t elementCount = 0;
        JSVM_Value arraybuffer = nullptr;
        size_t byteOffset = 0;
        if (OH_JSVM_GetTypedarrayInfo(env, args[0], &type, &elementCount, &data, &arraybuffer,
                                      &byteOffset) != JSVM_OK) {
            return ToJsString(env, "[]");
        }
        const size_t elementSize = TypedarrayElementSize(type);
        if (elementSize == 0) {
            return ToJsString(env, "[]");
        }
        length = elementCount * elementSize;
    } else {
        return ToJsString(env, "[]");
    }
    std::string query = argc > 1 ? ToStdString(env, args[1]) : "";
    return ToJsString(env, NativeSelectHtmlBytes(static_cast<const uint8_t *>(data), length, query));
}

// Synchronous zero-copy HTTP fetch: the main thread answers via
// ResolveHttpBytes with the response ArrayBuffer pinned by a napi_ref; the
// same memory is then wrapped as a JSVM external ArrayBuffer. Returns a JS
// object {status, statusText, headersJson, body:"", bytes, error} where
// `bytes` is an ArrayBuffer (or null after errors).
static JSVM_Value NativeHttpRequestShared(JSVM_Env env, JSVM_CallbackInfo info)
{
    size_t argc = 4;
    JSVM_Value args[4] = {nullptr, nullptr, nullptr, nullptr};
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, nullptr);
    std::string url = argc > 0 ? ToStdString(env, args[0]) : "";
    std::string method = argc > 1 ? ToStdString(env, args[1]) : "GET";
    std::string headersJson = argc > 2 ? ToStdString(env, args[2]) : "{}";
    std::string body = argc > 3 ? ToStdString(env, args[3]) : "";

    const uint64_t callId = g_nextCallId.fetch_add(1);
    auto pending = std::make_shared<PendingHttp>();
    {
        std::lock_guard<std::mutex> lock(g_pendingLock);
        g_pending[callId] = pending;
    }

    std::string reqJson = std::string("{\"callId\":") + std::to_string(callId) +
        ",\"url\":\"" + JsonEscape(url) +
        "\",\"method\":\"" + JsonEscape(method) +
        "\",\"headersJson\":\"" + JsonEscape(headersJson) +
        "\",\"body\":\"" + JsonEscape(body) + "\",\"shared\":true}";

    bool dispatched = false;
    {
        std::lock_guard<std::mutex> lock(g_tsfLock);
        if (g_httpTsf != nullptr) {
            HttpTask *task = new HttpTask{callId, reqJson};
            if (napi_call_threadsafe_function(g_httpTsf, task, napi_tsfn_nonblocking) == napi_ok) {
                dispatched = true;
            } else {
                delete task;
            }
        }
    }

    std::string resultJson;
    SharedBody *bodyShared = nullptr;
    if (!dispatched) {
        resultJson = HttpErrResult("http bridge not initialized");
        std::lock_guard<std::mutex> lock(g_pendingLock);
        g_pending.erase(callId);
    } else {
        std::unique_lock<std::mutex> lock(pending->mtx);
        bool woke = pending->cv.wait_for(lock, std::chrono::seconds(HTTP_BRIDGE_TIMEOUT_S),
                                         [&pending]() { return pending->done; });
        if (!woke) {
            resultJson = HttpErrResult("http bridge timeout");
            std::lock_guard<std::mutex> plock(g_pendingLock);
            g_pending.erase(callId);
        } else {
            resultJson = pending->resultJson;
            bodyShared = pending->sharedBody;
        }
    }

    JSVM_Value obj = nullptr;
    JSVM_Value meta = ToJsString(env, resultJson);
    if (meta == nullptr || OH_JSVM_JsonParse(env, meta, &obj) != JSVM_OK || obj == nullptr) {
        OH_JSVM_CreateObject(env, &obj);
        JSVM_Value zero = nullptr;
        OH_JSVM_CreateInt32(env, 0, &zero);
        OH_JSVM_SetNamedProperty(env, obj, "status", zero);
        JSVM_Value empty = ToJsString(env, "");
        OH_JSVM_SetNamedProperty(env, obj, "statusText", empty);
        OH_JSVM_SetNamedProperty(env, obj, "headersJson", ToJsString(env, "{}"));
        OH_JSVM_SetNamedProperty(env, obj, "body", ToJsString(env, ""));
        OH_JSVM_SetNamedProperty(env, obj, "url", ToJsString(env, ""));
        OH_JSVM_SetNamedProperty(env, obj, "error", ToJsString(env, "bridge result parse failed"));
    }

    JSVM_Value bytes = nullptr;
    OH_JSVM_GetNull(env, &bytes);
    if (bodyShared != nullptr) {
        bool copied = false;
        JSVM_Value external = nullptr;
        if (OH_JSVM_CreateArrayBufferFromExternalMemory(env, bodyShared->data, bodyShared->length,
                SharedBodyFinalize, bodyShared, &copied, &external) == JSVM_OK &&
            external != nullptr) {
            bytes = external;
        } else {
            // Fallback (e.g. unaligned backing store): copy once, then unpin.
            JSVM_Value copy = nullptr;
            void *copyData = nullptr;
            if (OH_JSVM_CreateArraybuffer(env, bodyShared->length, &copyData, &copy) == JSVM_OK &&
                copy != nullptr && copyData != nullptr) {
                if (bodyShared->length > 0) {
                    std::memcpy(copyData, bodyShared->data, bodyShared->length);
                }
                bytes = copy;
            }
            PostRelease(bodyShared->callId);
        }
    }
    OH_JSVM_SetNamedProperty(env, obj, "bytes", bytes);
    return obj;
}

// __nativeRandomBytes(n): n 字节硬件熵随机数 → Uint8Array。
// 任何失败（参数非法/libohcrypto 错误）返回 undefined，由 shim 侧
// crypto.getRandomValues 落到 Math.random 兜底——决不静默返回全零或
// 截断缓冲（随机数退化为全零是密钥安全灾难）。
static JSVM_Value NativeRandomBytes(JSVM_Env env, JSVM_CallbackInfo info)
{
    size_t argc = 1;
    JSVM_Value args[1] = {nullptr};
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, nullptr);
    int32_t requested = 0;
    if (argc > 0 && args[0] != nullptr &&
        OH_JSVM_GetValueInt32(env, args[0], &requested) != JSVM_OK) {
        requested = 0;
    }
    // 防御式上限：getRandomValues 不会请求超过 64KiB
    if (requested > 65536) {
        requested = 65536;
    }
    if (requested <= 0) {
        JSVM_Value undefined = nullptr;
        OH_JSVM_GetUndefined(env, &undefined);
        return undefined;
    }

    OH_CryptoRand *rand = nullptr;
    Crypto_DataBlob blob = {nullptr, 0};
    bool ok = OH_CryptoRand_Create(&rand) == CRYPTO_SUCCESS && rand != nullptr;
    if (ok) {
        // API 21+，尽力而为：无硬件熵时回落默认熵源（仍为 CSPRNG）
        OH_CryptoRand_EnableHardwareEntropy(rand);
        ok = OH_CryptoRand_GenerateRandom(rand, requested, &blob) == CRYPTO_SUCCESS &&
             blob.data != nullptr && blob.len == static_cast<size_t>(requested);
    }

    JSVM_Value result = nullptr;
    if (ok) {
        JSVM_Value arrayBuffer = nullptr;
        void *data = nullptr;
        if (OH_JSVM_CreateArraybuffer(env, blob.len, &data, &arrayBuffer) == JSVM_OK &&
            arrayBuffer != nullptr && data != nullptr) {
            std::memcpy(data, blob.data, blob.len);
            OH_JSVM_CreateTypedarray(env, JSVM_UINT8_ARRAY, blob.len, arrayBuffer, 0, &result);
        }
    }
    if (blob.data != nullptr) {
        OH_Crypto_FreeDataBlob(&blob);
    }
    if (rand != nullptr) {
        OH_CryptoRand_Destroy(rand);
    }
    if (result == nullptr) {
        OH_JSVM_GetUndefined(env, &result);
    }
    return result;
}

static JSVM_Value NativeLog(JSVM_Env env, JSVM_CallbackInfo info)
{
    size_t argc = 2;
    JSVM_Value args[2] = {nullptr, nullptr};
    OH_JSVM_GetCbInfo(env, info, &argc, args, nullptr, nullptr);
    std::string level = argc > 0 ? ToStdString(env, args[0]) : "info";
    std::string msg = argc > 1 ? ToStdString(env, args[1]) : "";
    LogLevel priority = LOG_INFO;
    if (level == "warn") {
        priority = LOG_WARN;
    } else if (level == "error") {
        priority = LOG_ERROR;
    } else if (level == "debug") {
        priority = LOG_DEBUG;
    }
    OH_LOG_Print(LOG_APP, priority, JSVM_LOG_DOMAIN, JSVM_LOG_TAG, "%{public}s", msg.c_str());
    return nullptr;
}

// Static callback structs: must outlive the env (keep as globals, never free).
static JSVM_CallbackStruct g_httpCb = {NativeHttpRequest, nullptr};
static JSVM_CallbackStruct g_httpSharedCb = {NativeHttpRequestShared, nullptr};
static JSVM_CallbackStruct g_encodeGbkCb = {NativeUrlEncodeGbk, nullptr};
static JSVM_CallbackStruct g_dnsSetCb = {NativeDnsSet, nullptr};
static JSVM_CallbackStruct g_hostCallCb = {NativeHostCall, nullptr};
static JSVM_CallbackStruct g_selectorCb = {NativeSelector, nullptr};
static JSVM_CallbackStruct g_selectorBufferCb = {NativeSelectorBuffer, nullptr};
static JSVM_CallbackStruct g_logCb = {NativeLog, nullptr};
static JSVM_CallbackStruct g_randomBytesCb = {NativeRandomBytes, nullptr};

// ============================================================================
// Bootstrap & adapter JS
// ============================================================================

static const char *BOOTSTRAP_JS = R"JS((function () {
  'use strict';
  var g = globalThis;

  // ---- 暴露面收敛 ----------------------------------------------------------
  // raw native 桥捕获进闭包，IIFE 末尾从全局删除：插件只能访问公开包装
  // （console / fetch / fetchBytes / querySelectorAll），
  // raw native 桥不出现在插件可见全局里。
  var __nativeLog = g.__nativeLog;
  var __nativeHttpRequest = g.__nativeHttpRequest;
  var __nativeHttpRequestShared = g.__nativeHttpRequestShared;
  var nativeSelector = g.nativeSelector;
  var nativeSelectorBuffer = g.nativeSelectorBuffer;

  // ---- console -----------------------------------------------------------
  // 插件 key 由 createEngine 在 bootstrap 前写入，这里收进闭包后立刻从全局删掉。
  // 插件只调 console.*，日志自动带上 [key]，并打码 api_key / token / password。
  var pluginKey = typeof g.__honyomiPluginKey === 'string' ? g.__honyomiPluginKey : '';
  function redactLog(text) {
    return String(text)
      .replace(/([?&#](?:api[_-]?key|access[_-]?token|token|password|passwd|pwd|authorization|auth)=)[^&#\s]*/gi, '$1***')
      .replace(/((?:api[_-]?key|access[_-]?token|token|password|passwd|pwd|authorization)\s*[:=]\s*)(?!\[)([^\s,&;"']+)/gi, '$1***')
      .replace(/(MediaBrowser Token=")[^"]*(")/g, '$1***$2')
      .replace(/(Bearer\s+)\S+/gi, '$1***')
      .replace(/("(?:apiKey|api_key|password|token|authorization)"\s*:\s*")[^"]*(")/gi, '$1***$2');
  }
  function logAt(level) {
    return function () {
      try {
        var parts = [];
        for (var i = 0; i < arguments.length; i++) {
          var a = arguments[i];
          parts.push(typeof a === 'string' ? a : JSON.stringify(a));
        }
        var msg = redactLog(parts.join(' '));
        if (msg.length > 500) { msg = msg.slice(0, 500) + '…'; }
        if (pluginKey) { msg = '[' + pluginKey + '] ' + msg; }
        __nativeLog(level, msg);
      } catch (e) { /* never throw from logging */ }
    };
  }
  g.console = {
    log: logAt('info'), info: logAt('info'), debug: logAt('debug'),
    warn: logAt('warn'), error: logAt('error')
  };
  if (typeof g.global === 'undefined') { g.global = g; }
  if (typeof g.module === 'undefined') {
    g.module = { exports: {} };
    g.exports = g.module.exports;
  }

  // 同步 HTTP。只给下面的 fetch 用，不挂到全局。
  function httpRequest(url, method, headersJson, body, wantBytes) {
    var raw = __nativeHttpRequest(String(url), String(method || 'GET'),
      String(headersJson || '{}'), body == null ? '' : String(body), wantBytes === true);
    var r;
    try { r = JSON.parse(raw); } catch (e) {
      r = { status: 0, statusText: '', headersJson: '{}', body: '', url: '', error: 'bridge result parse failed' };
    }
    return r;
  }

  // runtime 捕获后会从插件可见面删掉，插件 HTTP 走 $.http / fetchBytes。
  g.fetch = function (url, options) {
    options = options || {};
    var headers = options.headers || {};
    var r = httpRequest(url, options.method || 'GET', JSON.stringify(headers),
      options.body == null ? '' : String(options.body), false);
    if (r.error) { throw new Error(r.error); }
    return {
      ok: r.status >= 200 && r.status < 300,
      status: r.status,
      statusText: r.statusText,
      headers: JSON.parse(r.headersJson || '{}'),
      url: r.url || url,
      text: function () { return r.body; },
      json: function () { return JSON.parse(r.body); }
    };
  };

  // ---- zero-copy bytes fetch ------------------------------------------------
  // Returns {ok, status, statusText, headers, bytes: ArrayBuffer}. `bytes`
  // shares memory with the native response buffer (released automatically
  // once garbage collected / no longer referenced by JS).
  g.fetchBytes = function (url, options) {
    options = options || {};
    var headers = options.headers || {};
    var r = __nativeHttpRequestShared(String(url), options.method || 'GET',
      JSON.stringify(headers), options.body == null ? '' : String(options.body));
    if (r.error) { throw new Error(r.error); }
    r.ok = r.status >= 200 && r.status < 300;
    r.url = r.url || url;
    try { r.headers = JSON.parse(r.headersJson || '{}'); } catch (e) { r.headers = {}; }
    return r;
  };

  // ---- DOM-ish selector bridge ---------------------------------------------
  // Accepts an HTML string, an ArrayBuffer or a TypedArray view. Buffer inputs
  // are parsed in place by lexbor (zero-copy). The native layer returns
  // {results, truncated}: truncated === true means the serialized output hit
  // the internal byte budget and the traversal stopped early — log it loudly
  // so incomplete data is never mistaken for a complete match set. The
  // plugin-visible API still returns the plain results array.
  g.querySelectorAll = function (html, cssQuery) {
    var raw = (html instanceof ArrayBuffer || (typeof ArrayBuffer !== 'undefined' &&
        ArrayBuffer.isView && ArrayBuffer.isView(html)))
      ? nativeSelectorBuffer(html, String(cssQuery))
      : nativeSelector(String(html), String(cssQuery));
    var r;
    try { r = JSON.parse(raw); } catch (e) { r = null; }
    if (r !== null && Array.isArray(r.results)) {
      if (r.truncated) {
        console.warn('querySelectorAll: output budget hit, truncated to ' +
          r.results.length + ' matched elements (selector: ' + String(cssQuery) + ')');
      }
      return r.results;
    }
    return [];
  };

  // raw native 桥退出插件可见全局（上方包装器已持有闭包引用）。
  // 只删可配置属性：JSVM_DEFAULT 绑定不可配置，strict delete 会抛
  // TypeError: Cannot delete property '…'，整段 bootstrap 中断后桥仍留在全局。
  function hideNative(name) {
    try {
      var desc = Object.getOwnPropertyDescriptor(g, name);
      if (desc && desc.configurable) {
        delete g[name];
      }
    } catch (e) { /* non-configurable: leave it */ }
  }
  hideNative('__nativeHttpRequest');
  hideNative('__nativeHttpRequestShared');
  hideNative('nativeSelector');
  hideNative('nativeSelectorBuffer');
  hideNative('__nativeLog');
  hideNative('__honyomiPluginKey');
})();)JS";

static const char *ADAPTER_JS = R"JS((function () {
  var g = globalThis;

  function errJson(msg) { return JSON.stringify({ ok: false, error: String(msg) }); }
  function okJson(v) { return JSON.stringify({ ok: true, data: v === undefined ? null : v }); }

  var hostObj = null;
  if (g.module && g.module.exports && typeof g.module.exports === 'object') {
    var mex = g.module.exports;
    if (typeof mex.getPopularWorks === 'function') {
      hostObj = mex;
    }
  }
  var simple = (g.extension && typeof g.extension === 'object') ? g.extension : null;
  var api = null;

  function pickFn(obj, names, args, required) {
    for (var i = 0; i < names.length; i++) {
      if (typeof obj[names[i]] === 'function') { return obj[names[i]].apply(obj, args); }
    }
    if (required) { throw new Error('method not supported: ' + names[0]); }
    return undefined;
  }

  function bindHost(obj, kind) {
    var hasLatest = typeof obj.getLatestWorks === 'function';
    var api = {
      kind: kind,
      getPopularWorks: function (page) { return obj.getPopularWorks(page); },
      getSearchWorks: function (page, query) { return obj.getSearchWorks(page, query); },
      getWorkDetail: function (url) {
        return typeof obj.getWorkDetail === 'function' ? obj.getWorkDetail(url) : undefined;
      },
      getChapterList: function (url) { return obj.getChapterList(url); },
      getPageList: function (url) { return obj.getPageList(url); }
    };
    if (hasLatest) {
      api.getLatestWorks = function (page) { return obj.getLatestWorks(page); };
    }
    if (typeof obj.getHeaders === 'function' || typeof obj.headers === 'function') {
      api.getHeaders = function () {
        var h = pickFn(obj, ['getHeaders'], [], false);
        if (h) { return h; }
        return typeof obj.headers === 'function' ? obj.headers() : {};
      };
    }
    if (typeof obj.getFilterList === 'function') {
      api.getFilterList = function () { return obj.getFilterList(); };
    }
    if (typeof obj.applyFilterState === 'function') {
      api.applyFilterState = function (state) { return obj.applyFilterState(state); };
    }
    if (typeof obj.resetFilters === 'function') {
      api.resetFilters = function () { return obj.resetFilters(); };
    }
    if (typeof obj.getChapterText === 'function') {
      api.getChapterText = function (url) { return obj.getChapterText(url); };
    }
    if (typeof obj.getVideoList === 'function') {
      api.getVideoList = function (url) { return obj.getVideoList(url); };
    }
    if (typeof obj.fetchImage === 'function') {
      api.fetchImage = function (pageUrl, imageUrl) { return obj.fetchImage(pageUrl, imageUrl); };
    }
    if (typeof obj.setPreference === 'function') {
      api.setPreference = function (key, value) { return obj.setPreference(key, value); };
    }
    if (typeof obj.getSettingsSchema === 'function') {
      api.getSettingsSchema = function () { return obj.getSettingsSchema(); };
    }
    return api;
  }

  if (hostObj) {
    api = bindHost(hostObj, 'simple');
  } else if (simple) {
    api = bindHost(simple, 'simple');
  }

  g.__honyomiApi = api;
  g.__honyomiKind = api ? api.kind : null;

  g.__honyomiCall = function (name, argsJson) {
    var state = { done: false, json: '' };
    g.__honyomiState = state;
    try {
      if (name === '__kind') {
        return api ? okJson(api.kind) : errJson('no extension exports found');
      }
      if (name === '__methods') {
        if (!api) { return errJson('no extension exports found'); }
        var names = [];
        for (var mk in api) {
          if (typeof api[mk] === 'function') { names.push(mk); }
        }
        return okJson(names);
      }
      if (name === '__prefsDump') {
        // prefs 存储为 shim 闭包私有，dump 经公开 DSL $.prefs 走（raw
        // __prefsDump 全局已随暴露面收敛移除）
        return okJson(g.$ && g.$.prefs && typeof g.$.prefs.dump === 'function'
          ? g.$.prefs.dump() : {});
      }
      // Escape hatch: "__"-prefixed global functions registered by the loaded
      // script itself are callable even when no extension api was found.
      if (name.length > 2 && name.indexOf('__') === 0 && typeof g[name] === 'function') {
        var fnArgs = [];
        if (typeof argsJson === 'string') {
          if (argsJson !== '') { fnArgs = JSON.parse(argsJson); }
        } else if (argsJson && typeof argsJson === 'object' && typeof argsJson.length === 'number') {
          fnArgs = argsJson;
        }
        var fnResult = g[name].apply(null, fnArgs);
        if (fnResult && typeof fnResult.then === 'function') {
          fnResult.then(function (v) {
            state.done = true;
            state.json = okJson(v);
          }, function (e) {
            state.done = true;
            state.json = errJson(e && e.message ? e.message : String(e));
          });
          return '__PENDING__';
        }
        return okJson(fnResult);
      }
      if (!api) {
        return errJson('no extension exports found (expected module.exports or globalThis.extension)');
      }
      var fn = api[name];
      if (typeof fn !== 'function') {
        return errJson('method not supported: ' + name);
      }
      // C++ CallFunction splices the args JSON as an array literal, but the
      // ArkTS side may also pass a JSON string: accept both.
      var args = [];
      if (typeof argsJson === 'string') {
        if (argsJson !== '') { args = JSON.parse(argsJson); }
      } else if (argsJson && typeof argsJson === 'object' && typeof argsJson.length === 'number') {
        args = argsJson;
      }
      var r = fn.apply(null, args);
      if (r && typeof r.then === 'function') {
        r.then(function (v) {
          state.done = true;
          state.json = okJson(v);
        }, function (e) {
          state.done = true;
          state.json = errJson(e && e.message ? e.message : String(e));
        });
        return '__PENDING__';
      }
      return okJson(r);
    } catch (e) {
      return errJson(e && e.message ? e.message : String(e));
    }
  };

  g.__honyomiPoll = function () {
    var s = g.__honyomiState;
    if (s && s.done) {
      s.done = false;
      return s.json;
    }
    return '';
  };

  return okJson(api ? api.kind : null);
})();)JS";

// ============================================================================
// NAPI surface (called from the dedicated worker thread)
// ============================================================================

static Engine *FindEngine(uint32_t id)
{
    std::lock_guard<std::mutex> lock(g_enginesLock);
    auto it = g_engines.find(id);
    return it == g_engines.end() ? nullptr : it->second;
}

static napi_value NapiString(napi_env env, const std::string &text)
{
    napi_value value = nullptr;
    napi_create_string_utf8(env, text.c_str(), text.size(), &value);
    return value;
}

static std::string NapiUtf8(napi_env env, napi_value value)
{
    napi_valuetype type = napi_undefined;
    if (value == nullptr || napi_typeof(env, value, &type) != napi_ok || type != napi_string) {
        return "";
    }
    size_t len = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok) {
        return "";
    }
    std::vector<char> buf(len + 1, '\0');
    size_t written = 0;
    if (napi_get_value_string_utf8(env, value, buf.data(), buf.size(), &written) != napi_ok) {
        return "";
    }
    return std::string(buf.data(), written);
}

// Ordinary configurable data property, so bootstrap can capture and delete it.
static bool SetGlobalString(JSVM_Env env, const char *name, const std::string &value)
{
    JSVM_HandleScope scope = nullptr;
    if (OH_JSVM_OpenHandleScope(env, &scope) != JSVM_OK) {
        return false;
    }
    bool ok = false;
    JSVM_Value global = nullptr;
    JSVM_Value jsValue = ToJsString(env, value);
    if (OH_JSVM_GetGlobal(env, &global) == JSVM_OK && global != nullptr && jsValue != nullptr) {
        ok = OH_JSVM_SetNamedProperty(env, global, name, jsValue) == JSVM_OK;
    }
    OH_JSVM_CloseHandleScope(env, scope);
    return ok;
}

// Raw bridges must be ordinary configurable data properties. CreateEnv
// descriptors with JSVM_DEFAULT are non-configurable (DontDelete); the
// strict-mode delete in bootstrap / plugin_runtime then throws
// "Cannot delete property '__nativeUrlEncodeGbk'" and plugin install fails.
// SetNamedProperty installs a writable, enumerable, configurable function,
// which bootstrap and the runtime shim can remove after capturing it.
static bool InstallNativeBridges(JSVM_Env env)
{
    struct Bridge {
        const char *name;
        JSVM_Callback callback;
    };
    const Bridge bridges[] = {
        {"__nativeHttpRequest", &g_httpCb},
        {"__nativeHttpRequestShared", &g_httpSharedCb},
        {"__nativeUrlEncodeGbk", &g_encodeGbkCb},
        {"__nativeDnsSet", &g_dnsSetCb},
        {"__nativeHostCall", &g_hostCallCb},
        {"nativeSelector", &g_selectorCb},
        {"nativeSelectorBuffer", &g_selectorBufferCb},
        {"__nativeLog", &g_logCb},
        {"__nativeRandomBytes", &g_randomBytesCb},
    };

    JSVM_EnvScope envScope = nullptr;
    if (OH_JSVM_OpenEnvScope(env, &envScope) != JSVM_OK) {
        return false;
    }
    JSVM_HandleScope scope = nullptr;
    if (OH_JSVM_OpenHandleScope(env, &scope) != JSVM_OK) {
        OH_JSVM_CloseEnvScope(env, envScope);
        return false;
    }
    bool ok = true;
    JSVM_Value global = nullptr;
    if (OH_JSVM_GetGlobal(env, &global) != JSVM_OK || global == nullptr) {
        ok = false;
    } else {
        for (const Bridge &bridge : bridges) {
            JSVM_Value fn = nullptr;
            JSVM_Value exc = nullptr;
            if (OH_JSVM_CreateFunction(env, bridge.name, std::strlen(bridge.name),
                    bridge.callback, &fn) != JSVM_OK || fn == nullptr) {
                OH_JSVM_GetAndClearLastException(env, &exc);
                ok = false;
                break;
            }
            if (OH_JSVM_SetNamedProperty(env, global, bridge.name, fn) != JSVM_OK) {
                OH_JSVM_GetAndClearLastException(env, &exc);
                ok = false;
                break;
            }
        }
    }
    OH_JSVM_CloseHandleScope(env, scope);
    OH_JSVM_CloseEnvScope(env, envScope);
    return ok;
}

static napi_value CreateEngine(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value inArgs[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, inArgs, nullptr, nullptr);
    const std::string pluginKey = argc >= 1 ? NapiUtf8(env, inArgs[0]) : "";

    napi_value result = nullptr;
    // Serialize JSVM init + VM/Env creation: without this, a concurrent creator
    // skips the (still in-progress) OH_JSVM_Init and crashes inside
    // OH_JSVM_CreateVM -> v8::Isolate::New with a NULL dereference.
    std::lock_guard<std::mutex> createGuard(g_createEngineLock);
    if (!g_jsvmInited.exchange(true)) {
        JSVM_InitOptions initOptions;
        std::memset(&initOptions, 0, sizeof(initOptions));
        if (OH_JSVM_Init(&initOptions) != JSVM_OK) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, JSVM_LOG_DOMAIN, JSVM_LOG_TAG, "OH_JSVM_Init failed");
            napi_create_int32(env, -1, &result);
            return result;
        }
    }

    JSVM_CreateVMOptions vmOptions;
    std::memset(&vmOptions, 0, sizeof(vmOptions));
    JSVM_VM vm = nullptr;
    if (OH_JSVM_CreateVM(&vmOptions, &vm) != JSVM_OK || vm == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, JSVM_LOG_DOMAIN, JSVM_LOG_TAG, "CreateVM failed");
        napi_create_int32(env, -1, &result);
        return result;
    }

    JSVM_VMScope vmScope = nullptr;
    OH_JSVM_OpenVMScope(vm, &vmScope);
    JSVM_Env jsvmEnv = nullptr;
    if (OH_JSVM_CreateEnv(vm, 0, nullptr, &jsvmEnv) != JSVM_OK || jsvmEnv == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, JSVM_LOG_DOMAIN, JSVM_LOG_TAG, "CreateEnv failed");
        OH_JSVM_CloseVMScope(vm, vmScope);
        OH_JSVM_DestroyVM(vm);
        napi_create_int32(env, -1, &result);
        return result;
    }
    if (!InstallNativeBridges(jsvmEnv)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, JSVM_LOG_DOMAIN, JSVM_LOG_TAG, "install native bridges failed");
        OH_JSVM_CloseVMScope(vm, vmScope);
        OH_JSVM_DestroyEnv(jsvmEnv);
        OH_JSVM_DestroyVM(vm);
        napi_create_int32(env, -1, &result);
        return result;
    }
    OH_JSVM_CloseVMScope(vm, vmScope);

    auto *engine = new Engine{g_nextEngineId.fetch_add(1), vm, jsvmEnv};
    {
        std::lock_guard<std::mutex> lock(g_enginesLock);
        g_engines[engine->id] = engine;
    }
    // Install fetch/console/selector bootstrap before any extension code runs.
    // A thrown bootstrap used to be ignored, leaving the raw bridges on the
    // global; surface the failure instead of continuing half-initialized.
    // Plugin key is captured by console and removed from the visible global.
    if (!pluginKey.empty() && !SetGlobalString(engine->env, "__honyomiPluginKey", pluginKey)) {
        OH_LOG_Print(LOG_APP, LOG_WARN, JSVM_LOG_DOMAIN, JSVM_LOG_TAG, "set plugin log key failed");
    }
    std::string boot = RunRawScript(engine, BOOTSTRAP_JS);
    if (boot.rfind("{\"ok\":false", 0) == 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, JSVM_LOG_DOMAIN, JSVM_LOG_TAG,
            "bootstrap failed: %{public}s", boot.c_str());
        {
            std::lock_guard<std::mutex> lock(g_enginesLock);
            g_engines.erase(engine->id);
        }
        OH_JSVM_DestroyEnv(engine->env);
        OH_JSVM_DestroyVM(engine->vm);
        delete engine;
        napi_create_int32(env, -1, &result);
        return result;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, JSVM_LOG_DOMAIN, JSVM_LOG_TAG, "engine %{public}u created", engine->id);
    napi_create_uint32(env, engine->id, &result);
    return result;
}

static napi_value DestroyEngine(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    uint32_t engineId = 0;
    if (argc < 1 || napi_get_value_uint32(env, args[0], &engineId) != napi_ok) {
        napi_value result = nullptr;
        napi_get_boolean(env, false, &result);
        return result;
    }
    Engine *engine = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_enginesLock);
        auto it = g_engines.find(engineId);
        if (it != g_engines.end()) {
            engine = it->second;
            g_engines.erase(it);
        }
    }
    if (engine == nullptr) {
        napi_value result = nullptr;
        napi_get_boolean(env, false, &result);
        return result;
    }
    OH_JSVM_DestroyEnv(engine->env);
    OH_JSVM_DestroyVM(engine->vm);
    delete engine;
    OH_LOG_Print(LOG_APP, LOG_INFO, JSVM_LOG_DOMAIN, JSVM_LOG_TAG, "engine %{public}u destroyed", engineId);
    napi_value result = nullptr;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value RunScript(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    uint32_t engineId = 0;
    if (argc < 2 || napi_get_value_uint32(env, args[0], &engineId) != napi_ok) {
        return NapiString(env, ErrEnvelope("runScript: invalid engineId"));
    }
    size_t len = 0;
    if (napi_get_value_string_utf8(env, args[1], nullptr, 0, &len) != napi_ok) {
        return NapiString(env, ErrEnvelope("runScript: invalid code"));
    }
    std::vector<char> buf(len + 1, '\0');
    size_t written = 0;
    napi_get_value_string_utf8(env, args[1], buf.data(), buf.size(), &written);
    std::string code(buf.data(), written);

    Engine *engine = FindEngine(engineId);
    if (engine == nullptr) {
        return NapiString(env, ErrEnvelope("engine not found"));
    }
    // Extension code first, then the export adapter that binds __honyomiCall.
    std::string full = code + "\n;\n" + ADAPTER_JS;
    std::string out = RunRawScript(engine, full);
    if (out.empty() || out == "null") {
        out = ErrEnvelope("script produced no result");
    }
    return NapiString(env, out);
}

static napi_value CallFunction(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    uint32_t engineId = 0;
    if (argc < 3 || napi_get_value_uint32(env, args[0], &engineId) != napi_ok) {
        return NapiString(env, ErrEnvelope("callFunction: invalid engineId"));
    }
    size_t nameLen = 0;
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &nameLen);
    std::vector<char> nameBuf(nameLen + 1, '\0');
    size_t nameWritten = 0;
    napi_get_value_string_utf8(env, args[1], nameBuf.data(), nameBuf.size(), &nameWritten);
    std::string name(nameBuf.data(), nameWritten);

    size_t argsLen = 0;
    napi_get_value_string_utf8(env, args[2], nullptr, 0, &argsLen);
    std::vector<char> argsBuf(argsLen + 1, '\0');
    size_t argsWritten = 0;
    napi_get_value_string_utf8(env, args[2], argsBuf.data(), argsBuf.size(), &argsWritten);
    std::string argsJson(argsBuf.data(), argsWritten);

    Engine *engine = FindEngine(engineId);
    if (engine == nullptr) {
        return NapiString(env, ErrEnvelope("engine not found"));
    }

    std::string callSource = "__honyomiCall(\"" + JsonEscape(name) + "\", " +
        (argsJson.empty() ? "[]" : argsJson) + ")";
    std::string first = RunRawScript(engine, callSource);
    if (first != "__PENDING__") {
        return NapiString(env, first.empty() ? ErrEnvelope("empty call result") : first);
    }

    // Async extension method: pump microtasks until the promise settles.
    const auto deadline = std::chrono::steady_clock::now() +
        std::chrono::seconds(ENGINE_CALL_TIMEOUT_S);
    while (std::chrono::steady_clock::now() < deadline) {
        OH_JSVM_PerformMicrotaskCheckpoint(engine->vm);
        bool hasMore = false;
        OH_JSVM_PumpMessageLoop(engine->vm, &hasMore);
        std::string poll = RunRawScript(engine, "__honyomiPoll()");
        if (!poll.empty()) {
            return NapiString(env, poll);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    return NapiString(env, ErrEnvelope("extension call timeout"));
}

// ============================================================================
// NAPI surface (called from the main ArkTS thread)
// ============================================================================

static void HttpTsfnCallJs(napi_env env, napi_value jsCallback, void *context, void *data)
{
    HttpTask *task = static_cast<HttpTask *>(data);
    if (env != nullptr && jsCallback != nullptr) {
        napi_value undefined = nullptr;
        napi_get_undefined(env, &undefined);
        napi_value arg = nullptr;
        napi_create_string_utf8(env, task->reqJson.c_str(), task->reqJson.size(), &arg);
        napi_value ignored = nullptr;
        napi_call_function(env, undefined, jsCallback, 1, &arg, &ignored);
    }
    delete task;
}

static napi_value InitHttpDispatcher(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    napi_value result = nullptr;
    if (argc < 1) {
        napi_get_boolean(env, false, &result);
        return result;
    }
    std::lock_guard<std::mutex> lock(g_tsfLock);
    if (g_httpTsf != nullptr) {
        napi_get_boolean(env, true, &result); // idempotent
        return result;
    }
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "jsvmHttpBridge", NAPI_AUTO_LENGTH, &resourceName);
    napi_status status = napi_create_threadsafe_function(env, args[0], nullptr, resourceName,
        0, 1, nullptr, nullptr, nullptr, HttpTsfnCallJs, &g_httpTsf);
    OH_LOG_Print(LOG_APP, LOG_INFO, JSVM_LOG_DOMAIN, JSVM_LOG_TAG,
                 "http dispatcher installed: %{public}d", static_cast<int>(status));
    napi_get_boolean(env, status == napi_ok, &result);
    return result;
}

static napi_value ResolveHttp(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    napi_value result = nullptr;
    uint32_t callId = 0;
    if (argc < 2 || napi_get_value_uint32(env, args[0], &callId) != napi_ok) {
        napi_get_boolean(env, false, &result);
        return result;
    }
    size_t len = 0;
    if (napi_get_value_string_utf8(env, args[1], nullptr, 0, &len) != napi_ok) {
        napi_get_boolean(env, false, &result);
        return result;
    }
    std::vector<char> buf(len + 1, '\0');
    size_t written = 0;
    napi_get_value_string_utf8(env, args[1], buf.data(), buf.size(), &written);
    std::string respJson(buf.data(), written);

    std::shared_ptr<PendingHttp> pending;
    {
        std::lock_guard<std::mutex> lock(g_pendingLock);
        auto it = g_pending.find(callId);
        if (it != g_pending.end()) {
            pending = it->second;
            g_pending.erase(it);
        }
    }
    if (pending != nullptr) {
        std::lock_guard<std::mutex> lock(pending->mtx);
        pending->resultJson = respJson;
        pending->done = true;
        pending->cv.notify_all();
    }
    napi_get_boolean(env, pending != nullptr, &result);
    return result;
}

// Main thread: answers a shared (zero-copy) bridge request. metaJson carries
// the JsvmHttpResult envelope (body left empty); body is the response
// ArrayBuffer, pinned here by a napi_ref and wrapped by the worker as a JSVM
// external ArrayBuffer over the same memory.
static napi_value ResolveHttpBytes(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    napi_value result = nullptr;
    uint32_t callId = 0;
    if (argc < 2 || napi_get_value_uint32(env, args[0], &callId) != napi_ok) {
        napi_get_boolean(env, false, &result);
        return result;
    }
    size_t len = 0;
    if (napi_get_value_string_utf8(env, args[1], nullptr, 0, &len) != napi_ok) {
        napi_get_boolean(env, false, &result);
        return result;
    }
    std::vector<char> buf(len + 1, '\0');
    size_t written = 0;
    napi_get_value_string_utf8(env, args[1], buf.data(), buf.size(), &written);
    std::string metaJson(buf.data(), written);

    SharedBody *body = nullptr;
    bool isAb = false;
    if (argc >= 3 && args[2] != nullptr &&
        napi_is_arraybuffer(env, args[2], &isAb) == napi_ok && isAb) {
        void *data = nullptr;
        size_t dataLen = 0;
        napi_ref ref = nullptr;
        if (napi_get_arraybuffer_info(env, args[2], &data, &dataLen) == napi_ok &&
            napi_create_reference(env, args[2], 1, &ref) == napi_ok && ref != nullptr) {
            body = new SharedBody{callId, env, ref, data, dataLen};
            std::lock_guard<std::mutex> lock(g_bodiesLock);
            g_sharedBodies[callId] = body;
        }
    }

    std::shared_ptr<PendingHttp> pending;
    {
        std::lock_guard<std::mutex> lock(g_pendingLock);
        auto it = g_pending.find(callId);
        if (it != g_pending.end()) {
            pending = it->second;
            g_pending.erase(it);
        }
    }
    if (pending == nullptr) {
        // Worker timed out or bogus callId: unpin immediately.
        ReleaseSharedBodyMain(env, callId);
        napi_get_boolean(env, false, &result);
        return result;
    }
    {
        std::lock_guard<std::mutex> lock(pending->mtx);
        pending->sharedBody = body;
        pending->resultJson = metaJson;
        pending->done = true;
        pending->cv.notify_all();
    }
    napi_get_boolean(env, true, &result);
    return result;
}

// Main thread: drops the napi_ref pinning a shared body (dispatched from the
// JSVM ArrayBuffer finalize callback through the TSF).
static napi_value ReleaseHttpBuffer(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    napi_value result = nullptr;
    uint32_t callId = 0;
    if (argc < 1 || napi_get_value_uint32(env, args[0], &callId) != napi_ok) {
        napi_get_boolean(env, false, &result);
        return result;
    }
    ReleaseSharedBodyMain(env, callId);
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value EngineMemoryBytes(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    uint32_t engineId = 0;
    napi_value result = nullptr;
    if (argc < 1 || napi_get_value_uint32(env, args[0], &engineId) != napi_ok) {
        napi_create_double(env, -1, &result);
        return result;
    }
    Engine *engine = FindEngine(engineId);
    if (engine == nullptr) {
        napi_create_double(env, -1, &result);
        return result;
    }
    JSVM_HeapStatistics stats;
    std::memset(&stats, 0, sizeof(stats));
    if (OH_JSVM_GetHeapStatistics(engine->vm, &stats) != JSVM_OK) {
        napi_create_double(env, -1, &result);
        return result;
    }
    napi_create_double(env, static_cast<double>(stats.usedHeapSize), &result);
    return result;
}

// ============================================================================
// Module registration
// ============================================================================

// avif_decoder.cpp — native AVIF → JPEG conversion (libavif + aom decode, system ImagePacker encode)
napi_value AvifDecodeToJpeg(napi_env env, napi_callback_info info);

EXTERN_C_START
static napi_value Export(napi_env env, napi_value exports)
{
    napi_value avifFn = nullptr;
    napi_create_function(env, "avifDecodeToJpeg", NAPI_AUTO_LENGTH, AvifDecodeToJpeg, nullptr, &avifFn);
    napi_set_named_property(env, exports, "avifDecodeToJpeg", avifFn);

    static napi_property_descriptor desc[] = {
        { "createEngine", nullptr, CreateEngine, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "destroyEngine", nullptr, DestroyEngine, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "runScript", nullptr, RunScript, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "callFunction", nullptr, CallFunction, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "initHttpDispatcher", nullptr, InitHttpDispatcher, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "resolveHttp", nullptr, ResolveHttp, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "resolveHttpBytes", nullptr, ResolveHttpBytes, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "releaseHttpBuffer", nullptr, ReleaseHttpBuffer, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "engineMemoryBytes", nullptr, EngineMemoryBytes, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Export,
    .nm_modname = "jsvmengine",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterJsvmEngineModule(void)
{
    napi_module_register(&g_module);
}
