/*
 * Copyright (c) 2026 mihon-harmony
 *
 * Regex-based lightweight HTML selector bridge for JSVM.
 * JSVM is a pure ECMAScript runtime without DOM APIs; extensions rely on this
 * native bridge to run CSS-selector-like queries over fetched HTML documents.
 */

#ifndef HTML_SELECTOR_H
#define HTML_SELECTOR_H

#include <string>
#include <vector>

/*
 * Selects elements from raw HTML with a CSS-like query.
 *
 * Supported grammar (segments separated by whitespace = descendant combinator):
 *   tag            e.g. "div"
 *   #id            e.g. "#content"
 *   .class         e.g. ".item"
 *   [attr]         e.g. "[data-src]"
 *   [attr=value]   e.g. "[href^=https]" (only exact match supported)
 * Segments may be combined: "div.card#main[data-x=1]"
 *
 * Returns a JSON array: [{"outerHtml":"...","innerHtml":"...","text":"...",
 *                         "attrs":{"name":"value",...}}, ...]
 * Returns "[]" when nothing matches; returns "" on invalid query.
 */
std::string NativeSelectHtml(const std::string &html, const std::string &cssQuery);

/* Escapes a UTF-8 string into a JSON string literal body (without quotes). */
std::string JsonEscape(const std::string &input);

#endif // HTML_SELECTOR_H
