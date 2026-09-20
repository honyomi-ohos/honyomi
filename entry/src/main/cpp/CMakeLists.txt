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

add_library(jsvmengine SHARED
    jsvm_engine.cpp
    html_selector.cpp)

target_include_directories(jsvmengine PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(jsvmengine PUBLIC
    lexbor
    libace_napi.z.so
    libjsvm.so
    libhilog_ndk.z.so)
