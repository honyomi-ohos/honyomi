/*
 * Copyright (c) 2026 mihon-harmony
 *
 * Lexbor-based HTML selector bridge for JSVM.
 * JSVM is a pure ECMAScript runtime without DOM APIs; extensions rely on this
 * native bridge to run real CSS selector queries over fetched HTML documents.
 */

#ifndef HTML_SELECTOR_H
#define HTML_SELECTOR_H

#include <cstddef>
#include <cstdint>
#include <string>

/*
 * Selects elements from an HTML document with a full CSS selector list
 * (Lexbor CSS selectors: combinators, attribute operators, pseudo-classes,
 * comma-separated lists, ...).
 *
 * Returns a JSON array of hits:
 *   {"outerHtml","innerHtml","text","ownText","tag","attrs",
 *    "prev":{"tag","id","className","text","ownText"},
 *    "parents":[{"tag","id","className","text","ownText"}, ...]}
 * Returns "[]" when nothing matches or on parse failure.
 *
 * The input buffer is parsed IN PLACE: lexbor text nodes reference the caller's
 * memory, so [data, data + length) must stay alive for the whole call.
 */
std::string NativeSelectHtmlBytes(const uint8_t *data, size_t length, const std::string &cssQuery);

/* String convenience wrapper (UTF-8 encoded once by the caller). */
std::string NativeSelectHtml(const std::string &html, const std::string &cssQuery);

/* Escapes a UTF-8 string into a JSON string literal body (without quotes). */
std::string JsonEscape(const std::string &input);

#endif // HTML_SELECTOR_H
