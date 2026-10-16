cmake_minimum_required(VERSION 3.5.0)
project(mihon_jsvm_engine)

# ============================================================================
# Lexbor (vendored v2.5.0) — HTML parsing + CSS selectors only.
# Excluded on purpose: css at_rule/declaration/property/rule/stylesheet/unit/
# value modules, unicode, encoding tables, url, style, engine, punycode.
# ============================================================================

set(LEXBOR_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/third_party/lexbor/source)

file(GLOB LEXBOR_CORE_SRC
    ${LEXBOR_ROOT}/lexbor/core/*.c)

file(GLOB LEXBOR_DOM_SRC
    ${LEXBOR_ROOT}/lexbor/dom/*.c
    ${LEXBOR_ROOT}/lexbor/dom/interfaces/*.c)

file(GLOB LEXBOR_HTML_SRC
    ${LEXBOR_ROOT}/lexbor/html/*.c
    ${LEXBOR_ROOT}/lexbor/html/interfaces/*.c
    ${LEXBOR_ROOT}/lexbor/html/tokenizer/*.c
    ${LEXBOR_ROOT}/lexbor/html/tree/*.c
    ${LEXBOR_ROOT}/lexbor/html/tree/insertion_mode/*.c)

set(LEXBOR_CSS_SRC
    ${LEXBOR_ROOT}/lexbor/css/css.c
    ${LEXBOR_ROOT}/lexbor/css/log.c
    ${LEXBOR_ROOT}/lexbor/css/parser.c
    ${LEXBOR_ROOT}/lexbor/css/state.c
    ${LEXBOR_ROOT}/lexbor/css/selectors/pseudo.c
    ${LEXBOR_ROOT}/lexbor/css/selectors/pseudo_state.c
    ${LEXBOR_ROOT}/lexbor/css/selectors/selector.c
    ${LEXBOR_ROOT}/lexbor/css/selectors/selectors.c
    ${LEXBOR_ROOT}/lexbor/css/selectors/state.c
    ${LEXBOR_ROOT}/lexbor/css/syntax/anb.c
    ${LEXBOR_ROOT}/lexbor/css/syntax/parser.c
    ${LEXBOR_ROOT}/lexbor/css/syntax/state.c
    ${LEXBOR_ROOT}/lexbor/css/syntax/syntax.c
    ${LEXBOR_ROOT}/lexbor/css/syntax/token.c
    ${LEXBOR_ROOT}/lexbor/css/syntax/tokenizer.c
    ${LEXBOR_ROOT}/lexbor/css/syntax/tokenizer/error.c)

add_library(lexbor STATIC
    ${LEXBOR_CORE_SRC}
    ${LEXBOR_DOM_SRC}
    ${LEXBOR_HTML_SRC}
    ${LEXBOR_CSS_SRC}
    ${LEXBOR_ROOT}/lexbor/ns/ns.c
    ${LEXBOR_ROOT}/lexbor/tag/tag.c
    ${LEXBOR_ROOT}/lexbor/selectors/selectors.c
    ${LEXBOR_ROOT}/lexbor/ports/posix/lexbor/core/memory.c)

target_include_directories(lexbor PUBLIC ${LEXBOR_ROOT})

# ============================================================================
# libavif (vendored v1.4.2) + libaom v3.15.2 + libjpeg-turbo 3.2.0 (prebuilt)
# Native AVIF → JPEG conversion (decode-only codec path).
# aom/jpeg static libs are cross-compiled with the OHOS llvm toolchain, one
# copy per ABI under prebuilt/. Update instructions: see third_party/avif.
# ============================================================================

set(AVIF_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/third_party/avif)
set(AVIF_PREBUILT ${AVIF_ROOT}/prebuilt/${OHOS_ARCH})

add_library(avif STATIC
    ${AVIF_ROOT}/libavif/src/alpha.c
    ${AVIF_ROOT}/libavif/src/avif.c
    ${AVIF_ROOT}/libavif/src/codec_aom.c
    ${AVIF_ROOT}/libavif/src/colr.c
    ${AVIF_ROOT}/libavif/src/colrconvert.c
    ${AVIF_ROOT}/libavif/src/diag.c
    ${AVIF_ROOT}/libavif/src/exif.c
    ${AVIF_ROOT}/libavif/src/gainmap.c
    ${AVIF_ROOT}/libavif/src/io.c
    ${AVIF_ROOT}/libavif/src/mem.c
    ${AVIF_ROOT}/libavif/src/obu.c
    ${AVIF_ROOT}/libavif/src/properties.c
    ${AVIF_ROOT}/libavif/src/rawdata.c
    ${AVIF_ROOT}/libavif/src/read.c
    ${AVIF_ROOT}/libavif/src/reformat.c
    ${AVIF_ROOT}/libavif/src/reformat_libsharpyuv.c
    ${AVIF_ROOT}/libavif/src/reformat_libyuv.c
    ${AVIF_ROOT}/libavif/src/sampletransform.c
    ${AVIF_ROOT}/libavif/src/scale.c
    ${AVIF_ROOT}/libavif/src/stream.c
    ${AVIF_ROOT}/libavif/src/utils.c
    ${AVIF_ROOT}/libavif/src/write.c
    # libyuv 桩实现：scale.c 无条件包含 <libyuv.h>，本项目不走缩放路径，
    # 桩函数一律返回失败（见 include/libyuv.h 注释）
    ${AVIF_ROOT}/libyuv_stub.c)

target_compile_definitions(avif PRIVATE
    AVIF_CODEC_AOM=1
    AVIF_CODEC_AOM_DECODE=1)

target_include_directories(avif PUBLIC ${AVIF_ROOT}/libavif/include)
target_include_directories(avif PUBLIC ${AVIF_ROOT}/include)

target_link_libraries(avif PUBLIC
    ${AVIF_PREBUILT}/libaom.a
    ${AVIF_PREBUILT}/libturbojpeg.a)

# ============================================================================

add_library(jsvmengine SHARED
    jsvm_engine.cpp
    html_selector.cpp
    avif_decoder.cpp)

target_include_directories(jsvmengine PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(jsvmengine PUBLIC
    lexbor
    avif
    libace_napi.z.so
    libjsvm.so
    libhilog_ndk.z.so)
