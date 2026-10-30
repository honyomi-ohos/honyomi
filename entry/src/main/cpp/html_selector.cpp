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
#include <memory>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace {

struct AncestorInfo {
    std::string tag;
    std::string id;
    std::string className;
    std::string text;
    std::string ownText;
    // 前置兄弟元素摘要（最近优先，最多 kMaxPrevSiblings 个；兄弟自身不再嵌套展开）
    std::vector<std::shared_ptr<AncestorInfo>> prevSiblings;
};

constexpr size_t kMaxPrevSiblings = 16;
// Accumulated serialized-output budget per query. Match COUNT is a poor cost
// proxy (1024 nested <div> matches dwarf 100k tiny ones), so the guard is on
// output bytes instead: realistic result sets (chapter/image lists, whole-page
// anchors) stay far below it, while pathological selectors ("div", "*") that
// would otherwise accumulate O(page_size x depth) serialized memory are cut
// off here and the caller sees "truncated": true in the result.
constexpr size_t kMaxOutputBytes = 64 * 1024 * 1024;
// Uniform early-return value; every failure path keeps the same JSON shape.
constexpr char kEmptyResultJson[] = "{\"results\":[],\"truncated\":false}";

struct SelectedElement {
    std::string outerHtml;
    std::string innerHtml;
    std::string text;
    std::string ownText;
    std::string tag;
    std::map<std::string, std::string> attrs;
    std::shared_ptr<AncestorInfo> prev;
    std::vector<std::shared_ptr<AncestorInfo>> prevSiblings;
    std::vector<std::shared_ptr<AncestorInfo>> parents;
};

struct SelectContext {
    std::vector<SelectedElement> *out;
    // Per-RunSelect memoization of AncestorInfo keyed by node pointer.
    // Adjacent matches share parents/siblings heavily; without the cache
    // every match would re-collect the full text of each of its (up to 24)
    // ancestors and their prev-siblings — quadratic blowup on large
    // documents. The document is immutable during the find, so pointers
    // are stable keys.
    std::unordered_map<const lxb_dom_node_t *, std::shared_ptr<AncestorInfo>> nodeCache;
    // Serialized-output bytes accumulated so far (per-match owned strings).
    // Bounds both the results vector and, indirectly, the nodeCache: the
    // cache only grows while the traversal keeps producing matches.
    size_t accumulatedBytes = 0;
    bool truncated = false;
    // lxb_selectors_find 对逗号选择器列表的每个匹配段都会对同一节点回调一次
    // （lxb_selectors_next_list 在同一节点上继续尝试列表中的下一段）。合并段
    // （jsoup 逗号 = 文档序去重并集）后同一元素会重复序列化；按节点指针去重，
    // 文档在 find 期间不可变，指针是稳定键。
    std::unordered_set<const lxb_dom_node_t *> seenNodes;
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

void FillAncestorBase(const lxb_dom_node_t *node, AncestorInfo &info)
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

std::shared_ptr<AncestorInfo> GetNodeInfo(SelectContext &ctx, const lxb_dom_node_t *node);

// 前置兄弟元素摘要（最近优先），供 '+'/'~' 组合器在链式判断中使用
void FillPrevSiblings(SelectContext &ctx, const lxb_dom_node_t *node,
                      std::vector<std::shared_ptr<AncestorInfo>> &out)
{
    size_t count = 0;
    for (const lxb_dom_node_t *p = node->prev; p != nullptr && count < kMaxPrevSiblings; p = p->prev) {
        if (p->type != LXB_DOM_NODE_TYPE_ELEMENT) {
            continue;
        }
        std::shared_ptr<AncestorInfo> info = GetNodeInfo(ctx, p);
        if (info == nullptr || info->tag.empty()) {
            continue;
        }
        out.push_back(std::move(info));
        count++;
    }
}

// Returns the memoized AncestorInfo for an element node (base fields plus
// prevSiblings); nullptr for null / non-element nodes. Recursion terminates:
// prevSiblings of a node only ever reference strictly earlier siblings,
// which are cached on first computation.
std::shared_ptr<AncestorInfo> GetNodeInfo(SelectContext &ctx, const lxb_dom_node_t *node)
{
    if (node == nullptr || node->type != LXB_DOM_NODE_TYPE_ELEMENT) {
        return nullptr;
    }
    auto it = ctx.nodeCache.find(node);
    if (it != ctx.nodeCache.end()) {
        return it->second;
    }
    auto info = std::make_shared<AncestorInfo>();
    FillAncestorBase(node, *info);
    ctx.nodeCache[node] = info;
    FillPrevSiblings(ctx, node, info->prevSiblings);
    return info;
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
    // 同一元素命中逗号列表的多个段时只保留首次（jsoup 去重并集语义）
    if (selectCtx->seenNodes.find(node) != selectCtx->seenNodes.end()) {
        return LXB_STATUS_OK;
    }
    selectCtx->seenNodes.insert(node);

    SelectedElement element;
    // serialize semantics (lexbor):
    //   serialize_cb(element)  -> open tag markup only
    //   serialize_tree_cb(node) -> node + whole subtree (outerHTML)
    //   serialize_deep_cb(node) -> children only (innerHTML)
    (void)lxb_html_serialize_tree_cb(node, AppendSerialize, &element.outerHtml);
    (void)lxb_html_serialize_deep_cb(node, AppendSerialize, &element.innerHtml);
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
    element.prev = prev != nullptr ? GetNodeInfo(*selectCtx, prev) : nullptr;
    if (element.prev == nullptr) {
        element.prev = std::make_shared<AncestorInfo>(); // keep the JSON shape
    }
    FillPrevSiblings(*selectCtx, node, element.prevSiblings);
    constexpr size_t kMaxParents = 24;
    for (const lxb_dom_node_t *p = node->parent; p != nullptr && element.parents.size() < kMaxParents;
         p = p->parent) {
        std::shared_ptr<AncestorInfo> info = GetNodeInfo(*selectCtx, p);
        if (info == nullptr || info->tag.empty()) {
            continue;
        }
        element.parents.push_back(std::move(info));
    }

    selectCtx->accumulatedBytes += element.outerHtml.size() + element.innerHtml.size() +
                                   element.text.size() + element.ownText.size();
    selectCtx->out->push_back(std::move(element));
    if (selectCtx->accumulatedBytes >= kMaxOutputBytes) {
        // LXB_STATUS_STOP aborts the traversal cleanly: matches collected so
        // far are kept and lxb_selectors_find still returns LXB_STATUS_OK.
        selectCtx->truncated = true;
        return LXB_STATUS_STOP;
    }
    return LXB_STATUS_OK;
}

// 序列化 AncestorInfo；siblings 中的条目不递归展开 prevSiblings
std::string AncestorToJson(const AncestorInfo &an, bool withPrevSiblings)
{
    std::string json = "{\"tag\":\"" + JsonEscape(an.tag) + "\",\"id\":\"" + JsonEscape(an.id) +
                       "\",\"className\":\"" + JsonEscape(an.className) + "\",\"text\":\"" +
                       JsonEscape(an.text) + "\",\"ownText\":\"" + JsonEscape(an.ownText) + "\"";
    if (withPrevSiblings) {
        json += ",\"prevSiblings\":[";
        for (size_t s = 0; s < an.prevSiblings.size(); s++) {
            if (s > 0) {
                json += ",";
            }
            json += AncestorToJson(*an.prevSiblings[s], false);
        }
        json += "]";
    }
    json += "}";
    return json;
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
        json += "},\"prev\":" + AncestorToJson(*e.prev, false) + ",\"prevSiblings\":[";
        for (size_t s = 0; s < e.prevSiblings.size(); s++) {
            if (s > 0) {
                json += ",";
            }
            json += AncestorToJson(*e.prevSiblings[s], false);
        }
        json += "],\"parents\":[";
        for (size_t p = 0; p < e.parents.size(); p++) {
            if (p > 0) {
                json += ",";
            }
            json += AncestorToJson(*e.parents[p], true);
        }
        json += "]}";
    }
    json += "]";
    return json;
}

std::string RunSelect(const lxb_char_t *data, size_t length, const std::string &cssQuery)
{
    if (data == nullptr || length == 0 || cssQuery.empty()) {
        return kEmptyResultJson;
    }

    lxb_html_document_t *document = lxb_html_document_create();
    if (document == nullptr) {
        return kEmptyResultJson;
    }
    lxb_status_t status = lxb_html_document_parse(document, data, length);
    if (status != LXB_STATUS_OK) {
        lxb_html_document_destroy(document);
        return kEmptyResultJson;
    }

    lxb_css_parser_t *parser = lxb_css_parser_create();
    if (parser == nullptr || lxb_css_parser_init(parser, nullptr) != LXB_STATUS_OK) {
        if (parser != nullptr) {
            lxb_css_parser_destroy(parser, true);
        }
        lxb_html_document_destroy(document);
        return kEmptyResultJson;
    }

    lxb_selectors_t *selectors = lxb_selectors_create();
    if (selectors == nullptr || lxb_selectors_init(selectors) != LXB_STATUS_OK) {
        if (selectors != nullptr) {
            lxb_selectors_destroy(selectors, true);
        }
        lxb_css_parser_destroy(parser, true);
        lxb_html_document_destroy(document);
        return kEmptyResultJson;
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
        return kEmptyResultJson;
    }

    std::vector<SelectedElement> results;
    SelectContext ctx{&results};
    (void)lxb_selectors_find(selectors, lxb_dom_interface_node(document), list, FindCallback, &ctx);

    (void)lxb_selectors_destroy(selectors, true);
    lxb_css_parser_destroy(parser, true);
    lxb_css_selector_list_destroy_memory(list);
    lxb_html_document_destroy(document);

    std::string json = "{\"results\":" + BuildJson(results);
    json += ctx.truncated ? ",\"truncated\":true}" : ",\"truncated\":false}";
    return json;
}

} // namespace

// Escapes JSON-special characters AND sanitizes to strict UTF-8: any invalid
// byte sequence is replaced with U+FFFD, so the result can never smuggle
// malformed UTF-8 into JS strings. Pages served as GBK/Shift-JIS/latin-1
// (this build has no lexbor encoding module, so bytes pass through raw)
// otherwise produce corrupted text downstream.
std::string JsonEscape(const std::string &input)
{
    std::string out;
    out.reserve(input.size() + 16);
    const size_t n = input.size();
    size_t i = 0;
    while (i < n) {
        const unsigned char c = static_cast<unsigned char>(input[i]);
        char simple = '\0';
        switch (c) {
            case '"':
                simple = '"';
                break;
            case '\\':
                simple = '\\';
                break;
            case '\b':
                simple = 'b';
                break;
            case '\f':
                simple = 'f';
                break;
            case '\n':
                simple = 'n';
                break;
            case '\r':
                simple = 'r';
                break;
            case '\t':
                simple = 't';
                break;
            default:
                break;
        }
        if (simple != '\0') {
            out += '\\';
            out += simple;
            i += 1;
            continue;
        }
        if (c < 0x20) {
            char buf[8];
            (void)snprintf(buf, sizeof(buf), "\\u%04x", c);
            out += buf;
            i += 1;
            continue;
        }
        if (c < 0x80) {
            out += static_cast<char>(c);
            i += 1;
            continue;
        }
        // Multi-byte UTF-8 sequence: validate structure, overlong forms,
        // surrogates and > U+10FFFF before passing through.
        size_t len = 0;
        uint32_t cp = 0;
        if ((c & 0xE0) == 0xC0) {
            len = 2;
            cp = c & 0x1Fu;
        } else if ((c & 0xF0) == 0xE0) {
            len = 3;
            cp = c & 0x0Fu;
        } else if ((c & 0xF8) == 0xF0) {
            len = 4;
            cp = c & 0x07u;
        }
        bool valid = len > 0 && i + len <= n;
        if (valid) {
            for (size_t k = 1; k < len; k++) {
                const unsigned char cc = static_cast<unsigned char>(input[i + k]);
                if ((cc & 0xC0) != 0x80) {
                    valid = false;
                    break;
                }
                cp = (cp << 6) | (cc & 0x3Fu);
            }
        }
        if (valid) {
            if ((len == 2 && cp < 0x80) || (len == 3 && cp < 0x800) ||
                (len == 4 && cp < 0x10000) || cp > 0x10FFFF ||
                (cp >= 0xD800 && cp <= 0xDFFF)) {
                valid = false;
            }
        }
        if (valid) {
            out.append(input, i, len);
            i += len;
        } else {
            out += "\xEF\xBF\xBD"; // U+FFFD
            i += 1;
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
