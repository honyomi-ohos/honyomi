/*
 * Copyright (c) 2026 honyomi
 *
 * avif_decoder.cpp — native AVIF → JPEG conversion (libavif + aom + turbojpeg).
 *
 * Replaces the JSVM/WASM pipeline for this hot path (~4-5x faster):
 *   1. libavif parses the ISO-BMFF container, aom decodes the AV1 keyframe
 *      (multi-threaded, NEON/SSE accelerated).
 *   2. YUV planes are converted to interleaved RGB (alpha dropped, same as
 *      the WASM path's mozjpeg behaviour).
 *   3. libjpeg-turbo re-encodes to JPEG at quality 88 / 4:4:4 to match the
 *      previous mozjpeg output.
 *
 * The exported function is synchronous and blocking; callers must run it off
 * the UI thread (AvifWorker.ets). Throws a JS error on any failure so the
 * ArkTS layer can fall back to the WASM converter.
 */

#include "avif/avif.h"
#include "turbojpeg.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "napi/native_api.h"

namespace {

constexpr int kMaxThreads = 4;
constexpr int kJpegQuality = 88;

bool ThrowAvif(napi_env env, const char* stage, avifResult result)
{
    char message[128];
    if (snprintf(message, sizeof(message), "%s: %s", stage,
                 avifResultToString(result)) < 0) {
        napi_throw_error(env, nullptr, stage);
        return false;
    }
    napi_throw_error(env, nullptr, message);
    return false;
}

} // namespace

// avifDecodeToJpeg(input: ArrayBuffer /* avif bytes */): ArrayBuffer /* jpeg bytes */
napi_value AvifDecodeToJpeg(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "avifDecodeToJpeg requires an ArrayBuffer");
        return nullptr;
    }
    bool isBuffer = false;
    napi_is_arraybuffer(env, args[0], &isBuffer);
    if (!isBuffer) {
        napi_throw_type_error(env, nullptr, "avifDecodeToJpeg: input must be an ArrayBuffer");
        return nullptr;
    }
    void* input = nullptr;
    size_t inputSize = 0;
    napi_get_arraybuffer_info(env, args[0], &input, &inputSize);
    if (input == nullptr || inputSize == 0) {
        napi_throw_error(env, nullptr, "avifDecodeToJpeg: empty input");
        return nullptr;
    }

    // ---- 1) AVIF decode (container + AV1) → YUV image
    avifDecoder* decoder = avifDecoderCreate();
    if (decoder == nullptr) {
        napi_throw_error(env, nullptr, "avifDecodeToJpeg: avifDecoderCreate failed");
        return nullptr;
    }
    decoder->maxThreads = kMaxThreads;
    avifResult result = avifDecoderSetIOMemory(decoder, static_cast<const uint8_t*>(input), inputSize);
    if (result == AVIF_RESULT_OK) {
        result = avifDecoderParse(decoder);
    }
    if (result == AVIF_RESULT_OK) {
        result = avifDecoderNextImage(decoder);
    }
    if (result != AVIF_RESULT_OK || decoder->image == nullptr) {
        avifDecoderDestroy(decoder);
        ThrowAvif(env, "avifDecodeToJpeg decode failed", result);
        return nullptr;
    }

    // ---- 2) YUV → packed RGB (alpha dropped; matches the WASM/mozjpeg path)
    avifRGBImage rgb;
    avifRGBImageSetDefaults(&rgb, decoder->image);
    rgb.format = AVIF_RGB_FORMAT_RGB;
    rgb.chromaUpsampling = AVIF_CHROMA_UPSAMPLING_AUTOMATIC;
    rgb.maxThreads = kMaxThreads;
    avifRGBImageAllocatePixels(&rgb);
    result = avifImageYUVToRGB(decoder->image, &rgb);
    avifDecoderDestroy(decoder);
    if (result != AVIF_RESULT_OK) {
        avifRGBImageFreePixels(&rgb);
        ThrowAvif(env, "avifDecodeToJpeg rgb conversion failed", result);
        return nullptr;
    }

    // ---- 3) RGB → JPEG (quality 88, 4:4:4 — mirrors mozjpeg@88 of the WASM path)
    tjhandle compressor = tjInitCompress();
    if (compressor == nullptr) {
        avifRGBImageFreePixels(&rgb);
        napi_throw_error(env, nullptr, "avifDecodeToJpeg: tjInitCompress failed");
        return nullptr;
    }
    unsigned char* jpegBuffer = nullptr;
    unsigned long jpegSize = 0;
    const int ok = tjCompress2(compressor, rgb.pixels, static_cast<int>(rgb.width),
                               static_cast<int>(rgb.rowBytes), static_cast<int>(rgb.height), TJPF_RGB,
                               &jpegBuffer, &jpegSize, TJSAMP_444, kJpegQuality, TJFLAG_FASTDCT);
    const char* tjError = ok == 0 ? nullptr : tjGetErrorStr2(compressor);
    avifRGBImageFreePixels(&rgb);
    if (ok != 0 || jpegBuffer == nullptr || jpegSize == 0) {
        if (jpegBuffer != nullptr) {
            tjFree(jpegBuffer);
        }
        tjDestroy(compressor);
        napi_throw_error(env, nullptr, tjError != nullptr ? tjError : "avifDecodeToJpeg: jpeg encode failed");
        return nullptr;
    }

    // ---- 4) copy into the JS-visible ArrayBuffer
    napi_value output = nullptr;
    void* outputData = nullptr;
    napi_status status = napi_create_arraybuffer(env, jpegSize, &outputData, &output);
    if (status == napi_ok && outputData != nullptr) {
        if (memcpy(outputData, jpegBuffer, jpegSize) == nullptr) {
            status = napi_generic_failure;
        }
    }
    tjFree(jpegBuffer);
    tjDestroy(compressor);
    if (status != napi_ok || output == nullptr) {
        napi_throw_error(env, nullptr, "avifDecodeToJpeg: out of memory");
        return nullptr;
    }
    return output;
}
