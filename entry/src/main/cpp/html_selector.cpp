/*
 * Copyright (c) 2026 honyomi
 *
 * Lexbor-based HTML selector (see html_selector.h).
 *
 * Uses only the HTML parsing + CSS selector modules of Lexbor: the document is
 * parsed in place over the caller's buffer (zero-copy for the ArrayBuffer
 * pipeline), matched with lxb_selectors_find, and each hit is serialized to
 * outer/inner HTML, text, ownText, tag, attributes, previous sibling, and
 * parent chain. Historical fields consumed by extension scripts are preserved.
 */

#include "html_selector.h"

#include <lexbor/css/css.h>
#include <lexbor/html/html.h>
#include <lexbor/selectors/selectors.h>

#include <cstdio>
#include <map>
#include <vector>

namespace {

struct AncestorInfo {
    std::string tag;
    std::string id;
    std::string className;
    std::string text;
    std::string ownText;
};

struct SelectedElement {
    std::string outerHtml;
    std::string innerHtml;
    std::string text;
    std::string ownText;
    std::string tag;
    std::map<std::string, std::string> attrs;
    AncestorInfo prev;
    std::vector<AncestorInfo> parents;
};

struct SelectContext {
    std::vector<SelectedElement> *out;
};

lxb_status_t AppendSerialize(const lxb_char_t *data, size_t len, void *ctx)
{
    static_cast<std::string *>(ctx)->append(reinterpret_cast<const char *>(data), len);
    return LXB_STATUS_OK;
}

// Collects decoded text from all descendant TEXT nodes, skipping script/style
// subtrees; collapses whitespace like the historical implementation.
void CollectTextFrom(const lxb_dom_node_t *node, std::string &out)
{
    for (const lxb_dom_node_t *child = node->first_child; child != nullptr; child = child->next) {
        if (child->type == LXB_DOM_NODE_TYPE_TEXT) {
            const lexbor_str_t &data = lxb_dom_interface_text(const_cast<lxb_dom_node_t *>(child))
                                           ->char_data.data;
            if (data.data != nullptr && data.length > 0) {
                out.append(reinterpret_cast<const char *>(data.data), data.length);
            }
        } else if (child->type == LXB_DOM_NODE_TYPE_ELEMENT) {
            const lxb_tag_id_t tagId = lxb_dom_node_tag_id(const_cast<lxb_dom_node_t *>(child));
            if (tagId == LXB_TAG_SCRIPT || tagId == LXB_TAG_STYLE) {
                continue;
            }
            CollectTextFrom(child, out);
        }
    }
}

void CollectOwnTextFrom(const lxb_dom_node_t *node, std::string &out)
{
    for (const lxb_dom_node_t *child = node->first_child; child != nullptr; child = child->next) {
        if (child->type != LXB_DOM_NODE_TYPE_TEXT) {
            continue;
        }
        const lexbor_str_t &data = lxb_dom_interface_text(const_cast<lxb_dom_node_t *>(child))
                                       ->char_data.data;
        if (data.data != nullptr && data.length > 0) {
            out.append(reinterpret_cast<const char *>(data.data), data.length);
        }
    }
}

std::string CollapseWhitespace(const std::string &input);

std::string ElementTag(lxb_dom_element_t *el)
{
    size_t nameLen = 0;
    const lxb_char_t *name = lxb_dom_element_qualified_name(el, &nameLen);
    if (name == nullptr || nameLen == 0) {
        return "";
    }
    return std::string(reinterpret_cast<const char *>(name), nameLen);
}

void FillAncestor(const lxb_dom_node_t *node, AncestorInfo &info)
{
    if (node == nullptr || node->type != LXB_DOM_NODE_TYPE_ELEMENT) {
        return;
    }
    lxb_dom_element_t *el = lxb_dom_interface_element(const_cast<lxb_dom_node_t *>(node));
    info.tag = ElementTag(el);
    for (lxb_dom_attr_t *attr = lxb_dom_element_first_attribute(el); attr != nullptr;
         attr = lxb_dom_element_next_attribute(attr)) {
        size_t nameLen = 0;
        const lxb_char_t *name = lxb_dom_attr_qualified_name(attr, &nameLen);
        size_t valueLen = 0;
        const lxb_char_t *value = lxb_dom_attr_value(attr, &valueLen);
        if (name == nullptr || nameLen == 0) {
            continue;
        }
        std::string key(reinterpret_cast<const char *>(name), nameLen);
        std::string val = value == nullptr ? "" : std::string(reinterpret_cast<const char *>(value), valueLen);
        if (key == "id") {
            info.id = val;
        } else if (key == "class") {
            info.className = val;
        }
    }
    std::string rawText;
    CollectTextFrom(node, rawText);
    info.text = CollapseWhitespace(rawText);
    std::string own;
    CollectOwnTextFrom(node, own);
    info.ownText = CollapseWhitespace(own);
}

const lxb_dom_node_t *PreviousElementSibling(const lxb_dom_node_t *node)
{
    for (const lxb_dom_node_t *p = node->prev; p != nullptr; p = p->prev) {
        if (p->type == LXB_DOM_NODE_TYPE_ELEMENT) {
            return p;
        }
    }
    return nullptr;
}

std::string CollapseWhitespace(const std::string &input)
{
    std::string out;
    out.reserve(input.size());
    size_t i = 0;
    // trim leading
    while (i < input.size() &&
           (input[i] == ' ' || input[i] == '\t' || input[i] == '\n' || input[i] == '\r' ||
            input[i] == '\f' || input[i] == '\v')) {
        i++;
    }
    bool pendingSpace = false;
    for (; i < input.size(); i++) {
        const char c = input[i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v') {
            pendingSpace = !out.empty();
            continue;
        }
        if (pendingSpace) {
            out += ' ';
            pendingSpace = false;
        }
        out += c;
    }
    return out;
}

lxb_status_t FindCallback(lxb_dom_node_t *node, lxb_css_selector_specificity_t spec, void *ctx)
{
    (void)spec;
    auto *selectCtx = static_cast<SelectContext *>(ctx);
    if (node == nullptr || node->type != LXB_DOM_NODE_TYPE_ELEMENT) {
        return LXB_STATUS_OK;
    }

    SelectedElement element;
    (void)lxb_html_serialize_cb(node, AppendSerialize, &element.outerHtml);
    (void)lxb_html_serialize_tree_cb(node, AppendSerialize, &element.innerHtml);
    std::string rawText;
    CollectTextFrom(node, rawText);
    element.text = CollapseWhitespace(rawText);
    std::string own;
    CollectOwnTextFrom(node, own);
    element.ownText = CollapseWhitespace(own);

    lxb_dom_element_t *el = lxb_dom_interface_element(node);
    element.tag = ElementTag(el);
    for (lxb_dom_attr_t *attr = lxb_dom_element_first_attribute(el); attr != nullptr;
         attr = lxb_dom_element_next_attribute(attr)) {
        size_t nameLen = 0;
        const lxb_char_t *name = lxb_dom_attr_qualified_name(attr, &nameLen);
        size_t valueLen = 0;
        const lxb_char_t *value = lxb_dom_attr_value(attr, &valueLen);
        if (name == nullptr || nameLen == 0) {
            continue;
        }
        element.attrs[std::string(reinterpret_cast<const char *>(name), nameLen)] =
            value == nullptr ? "" : std::string(reinterpret_cast<const char *>(value), valueLen);
    }

    const lxb_dom_node_t *prev = PreviousElementSibling(node);
    if (prev != nullptr) {
        FillAncestor(prev, element.prev);
    }
    constexpr size_t kMaxParents = 24;
    for (const lxb_dom_node_t *p = node->parent; p != nullptr && element.parents.size() < kMaxParents;
         p = p->parent) {
        if (p->type != LXB_DOM_NODE_TYPE_ELEMENT) {
            continue;
        }
        AncestorInfo info;
        FillAncestor(p, info);
        if (info.tag.empty()) {
            continue;
        }
        element.parents.push_back(std::move(info));
    }

    selectCtx->out->push_back(std::move(element));
    return LXB_STATUS_OK;
}

std::string BuildJson(const std::vector<SelectedElement> &elements)
{
    std::string json = "[";
    for (size_t i = 0; i < elements.size(); i++) {
        if (i > 0) {
            json += ",";
        }
        const SelectedElement &e = elements[i];
        json += "{\"outerHtml\":\"" + JsonEscape(e.outerHtml) + "\",\"innerHtml\":\"" +
                JsonEscape(e.innerHtml) + "\",\"text\":\"" + JsonEscape(e.text) +
                "\",\"ownText\":\"" + JsonEscape(e.ownText) + "\",\"tag\":\"" + JsonEscape(e.tag) +
                "\",\"attrs\":{";
        size_t a = 0;
        for (const auto &attr : e.attrs) {
            if (a > 0) {
                json += ",";
            }
            json += "\"" + JsonEscape(attr.first) + "\":\"" + JsonEscape(attr.second) + "\"";
            a++;
        }
        json += "},\"prev\":{\"tag\":\"" + JsonEscape(e.prev.tag) + "\",\"id\":\"" +
                JsonEscape(e.prev.id) + "\",\"className\":\"" + JsonEscape(e.prev.className) +
                "\",\"text\":\"" + JsonEscape(e.prev.text) + "\",\"ownText\":\"" +
                JsonEscape(e.prev.ownText) + "\"},\"parents\":[";
        for (size_t p = 0; p < e.parents.size(); p++) {
            if (p > 0) {
                json += ",";
            }
            const AncestorInfo &an = e.parents[p];
            json += "{\"tag\":\"" + JsonEscape(an.tag) + "\",\"id\":\"" + JsonEscape(an.id) +
                    "\",\"className\":\"" + JsonEscape(an.className) + "\",\"text\":\"" +
                    JsonEscape(an.text) + "\",\"ownText\":\"" + JsonEscape(an.ownText) + "\"}";
        }
        json += "]}";
    }
    json += "]";
    return json;
}

std::string RunSelect(const lxb_char_t *data, size_t length, const std::string &cssQuery)
{
    if (data == nullptr || length == 0 || cssQuery.empty()) {
        return "[]";
    }

    lxb_html_document_t *document = lxb_html_document_create();
    if (document == nullptr) {
        return "[]";
    }
    lxb_status_t status = lxb_html_document_parse(document, data, length);
    if (status != LXB_STATUS_OK) {
        lxb_html_document_destroy(document);
        return "[]";
    }

    lxb_css_parser_t *parser = lxb_css_parser_create();
    if (parser == nullptr || lxb_css_parser_init(parser, nullptr) != LXB_STATUS_OK) {
        if (parser != nullptr) {
            lxb_css_parser_destroy(parser, true);
        }
        lxb_html_document_destroy(document);
        return "[]";
    }

    lxb_selectors_t *selectors = lxb_selectors_create();
    if (selectors == nullptr || lxb_selectors_init(selectors) != LXB_STATUS_OK) {
        if (selectors != nullptr) {
            lxb_selectors_destroy(selectors, true);
        }
        lxb_css_parser_destroy(parser, true);
        lxb_html_document_destroy(document);
        return "[]";
    }

    lxb_css_selector_list_t *list = lxb_css_selectors_parse(
        parser, reinterpret_cast<const lxb_char_t *>(cssQuery.c_str()), cssQuery.size());
    if (list == nullptr || parser->status != LXB_STATUS_OK) {
        (void)lxb_selectors_destroy(selectors, true);
        lxb_css_parser_destroy(parser, true);
        if (list != nullptr) {
            lxb_css_selector_list_destroy_memory(list);
        }
        lxb_html_document_destroy(document);
        return "[]";
    }

    std::vector<SelectedElement> results;
    SelectContext ctx{&results};
    (void)lxb_selectors_find(selectors, lxb_dom_interface_node(document), list, FindCallback, &ctx);

    (void)lxb_selectors_destroy(selectors, true);
    lxb_css_parser_destroy(parser, true);
    lxb_css_selector_list_destroy_memory(list);
    lxb_html_document_destroy(document);

    return BuildJson(results);
}

} // namespace

std::string JsonEscape(const std::string &input)
{
    std::string out;
    out.reserve(input.size() + 16);
    for (size_t i = 0; i < input.size(); i++) {
        unsigned char c = static_cast<unsigned char>(input[i]);
        switch (c) {
            case '"':
                out += "\\\"";
                break;
            case '\\':
                out += "\\\\";
                break;
            case '\b':
                out += "\\b";
                break;
            case '\f':
                out += "\\f";
                break;
            case '\n':
                out += "\\n";
                break;
            case '\r':
                out += "\\r";
                break;
            case '\t':
                out += "\\t";
                break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    (void)snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
        }
    }
    return out;
}

std::string NativeSelectHtmlBytes(const uint8_t *data, size_t length, const std::string &cssQuery)
{
    return RunSelect(reinterpret_cast<const lxb_char_t *>(data), length, cssQuery);
}

std::string NativeSelectHtml(const std::string &html, const std::string &cssQuery)
{
    return RunSelect(reinterpret_cast<const lxb_char_t *>(html.data()), html.size(), cssQuery);
}
