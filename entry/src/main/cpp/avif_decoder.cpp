/*
 * Copyright (c) 2026 honyomi
 *
 * avif_decoder.cpp — native AVIF → JPEG conversion (libavif + aom decode,
 * system ImagePacker encode).
 *
 * Replaces the JSVM/WASM pipeline for this hot path (~4-5x faster):
 *   1. libavif parses the ISO-BMFF container, aom decodes the AV1 keyframe
 *      (multi-threaded, NEON/SSE accelerated).
 *   2. YUV planes are converted to packed RGBA (alpha forced opaque via
 *      memset, same flattening as the WASM path's mozjpeg behaviour).
 *   3. An OH_PixelmapNative wraps the RGBA buffer and the system
 *      ImagePacker (libimage_packer.so) encodes JPEG at quality 88,
 *      matching the previous mozjpeg output size class.
 *
 * The exported function is synchronous and blocking; callers must run it off
 * the UI thread (AvifWorker.ets). Throws a JS error on any failure so the
 * ArkTS layer can fall back to the WASM converter.
 */

#include "avif/avif.h"

#include <multimedia/image_framework/image/image_common.h>
#include <multimedia/image_framework/image/image_packer_native.h>
#include <multimedia/image_framework/image/pixelmap_native.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "napi/native_api.h"

namespace {

constexpr int kMaxThreads = 4;
constexpr uint32_t kJpegQuality = 88;

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

bool ThrowImage(napi_env env, const char* stage, Image_ErrorCode code)
{
    char message[128];
    if (snprintf(message, sizeof(message), "%s: %d", stage, static_cast<int>(code)) < 0) {
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

    // ---- 2) YUV → packed RGBA (alpha forced opaque; matches the WASM/mozjpeg path)
    const uint32_t width = decoder->image->width;
    const uint32_t height = decoder->image->height;
    const size_t rgbaStride = static_cast<size_t>(width) * 4;
    const size_t rgbaSize = rgbaStride * height;
    uint8_t* rgba = static_cast<uint8_t*>(malloc(rgbaSize));
    if (rgba == nullptr) {
        avifDecoderDestroy(decoder);
        napi_throw_error(env, nullptr, "avifDecodeToJpeg: out of memory");
        return nullptr;
    }
    memset(rgba, 0xFF, rgbaSize); // ignoreAlpha leaves the alpha channel untouched
    avifRGBImage rgb;
    memset(&rgb, 0, sizeof(rgb));
    rgb.width = width;
    rgb.height = height;
    rgb.depth = 8;
    rgb.format = AVIF_RGB_FORMAT_RGBA;
    rgb.chromaUpsampling = AVIF_CHROMA_UPSAMPLING_AUTOMATIC;
    rgb.maxThreads = kMaxThreads;
    rgb.ignoreAlpha = AVIF_TRUE;
    rgb.pixels = rgba;
    rgb.rowBytes = rgbaStride;
    result = avifImageYUVToRGB(decoder->image, &rgb);
    avifDecoderDestroy(decoder);
    if (result != AVIF_RESULT_OK) {
        free(rgba);
        ThrowAvif(env, "avifDecodeToJpeg rgb conversion failed", result);
        return nullptr;
    }

    // ---- 3) RGBA → OH_PixelmapNative (the call copies the buffer)
    OH_Pixelmap_InitializationOptions* initOptions = nullptr;
    OH_PixelmapNative* pixelmap = nullptr;
    Image_ErrorCode code = OH_PixelmapInitializationOptions_Create(&initOptions);
    if (code == IMAGE_SUCCESS && initOptions != nullptr) {
        OH_PixelmapInitializationOptions_SetWidth(initOptions, width);
        OH_PixelmapInitializationOptions_SetHeight(initOptions, height);
        OH_PixelmapInitializationOptions_SetSrcPixelFormat(initOptions, PIXEL_FORMAT_RGBA_8888);
        OH_PixelmapInitializationOptions_SetPixelFormat(initOptions, PIXEL_FORMAT_RGBA_8888);
        OH_PixelmapInitializationOptions_SetAlphaType(initOptions, PIXELMAP_ALPHA_TYPE_OPAQUE);
        code = OH_PixelmapNative_CreatePixelmap(rgba, rgbaSize, initOptions, &pixelmap);
    }
    free(rgba);
    if (initOptions != nullptr) {
        OH_PixelmapInitializationOptions_Release(initOptions);
    }
    if (code != IMAGE_SUCCESS || pixelmap == nullptr) {
        ThrowImage(env, "avifDecodeToJpeg pixelmap creation failed", code);
        return nullptr;
    }

    // ---- 4) Pixelmap → JPEG via the system ImagePacker (quality 88)
    OH_PackingOptions* packingOptions = nullptr;
    OH_ImagePackerNative* packer = nullptr;
    // JPEG@88 fits the RGBA budget for real-world images, but tiny frames
    // (headers + entropy floor can exceed a few hundred bytes of raw data)
    // and noise-heavy content can overflow it; give the encoder a budget
    // with a floor instead of failing those into the WASM fallback.
    const size_t jpegBudget = rgbaSize > (64 * 1024) ? rgbaSize : (64 * 1024);
    uint8_t* jpegBuffer = static_cast<uint8_t*>(malloc(jpegBudget));
    size_t jpegSize = jpegBuffer != nullptr ? jpegBudget : 0;
    if (jpegBuffer == nullptr) {
        code = IMAGE_BAD_PARAMETER;
    }
    if (code == IMAGE_SUCCESS) {
        code = OH_PackingOptions_Create(&packingOptions);
    }
    if (code == IMAGE_SUCCESS && packingOptions != nullptr) {
        Image_MimeType mime;
        mime.data = const_cast<char*>("image/jpeg");
        mime.size = strlen("image/jpeg");
        code = OH_PackingOptions_SetMimeType(packingOptions, &mime);
        if (code == IMAGE_SUCCESS) {
            code = OH_PackingOptions_SetQuality(packingOptions, kJpegQuality);
        }
    }
    if (code == IMAGE_SUCCESS) {
        code = OH_ImagePackerNative_Create(&packer);
    }
    if (code == IMAGE_SUCCESS && packer != nullptr) {
        code = OH_ImagePackerNative_PackToDataFromPixelmap(packer, packingOptions, pixelmap, jpegBuffer, &jpegSize);
    }
    if (packingOptions != nullptr) {
        OH_PackingOptions_Release(packingOptions);
    }
    if (packer != nullptr) {
        OH_ImagePackerNative_Release(packer);
    }
    OH_PixelmapNative_Release(pixelmap);
    if (code != IMAGE_SUCCESS || jpegSize == 0) {
        free(jpegBuffer);
        ThrowImage(env, "avifDecodeToJpeg jpeg encode failed", code);
        return nullptr;
    }

    // ---- 5) copy into the JS-visible ArrayBuffer
    napi_value output = nullptr;
    void* outputData = nullptr;
    napi_status status = napi_create_arraybuffer(env, jpegSize, &outputData, &output);
    if (status == napi_ok && outputData != nullptr) {
        if (memcpy(outputData, jpegBuffer, jpegSize) == nullptr) {
            status = napi_generic_failure;
        }
    }
    free(jpegBuffer);
    if (status != napi_ok || output == nullptr) {
        napi_throw_error(env, nullptr, "avifDecodeToJpeg: out of memory");
        return nullptr;
    }
    return output;
}
