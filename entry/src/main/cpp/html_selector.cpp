/*
 * Copyright (c) 2026 mihon-harmony
 *
 * Regex-based lightweight HTML selector (see html_selector.h).
 *
 * This is intentionally a "fast native parser" in the spirit of the spec:
 * a lightweight tag scanner + depth-matched range finder, good enough for
 * comic site scraping (list items, chapter links, page containers) while
 * staying allocation-light inside the JSVM worker thread.
 */

#include "html_selector.h"

#include <cctype>
#include <map>
#include <regex>
#include <set>
#include <sstream>

namespace {

struct SelectedElement {
    std::string outerHtml;
    std::string innerHtml;
    std::string text;
    std::map<std::string, std::string> attrs;
};

struct SimpleSelector {
    std::string tag;                                    // empty = any tag
    std::string id;                                     // empty = no constraint
    std::vector<std::string> classes;                   // all must be present
    std::vector<std::pair<std::string, std::string>> attrs; // exact match, value "" = exists
};

std::string TrimCopy(const std::string &s)
{
    size_t begin = 0;
    size_t end = s.size();
    while (begin < end && std::isspace(static_cast<unsigned char>(s[begin]))) {
        begin++;
    }
    while (end > begin && std::isspace(static_cast<unsigned char>(s[end - 1]))) {
        end--;
    }
    return s.substr(begin, end - begin);
}

std::string ToLowerCopy(const std::string &s)
{
    std::string out = s;
    for (size_t i = 0; i < out.size(); i++) {
        out[i] = static_cast<char>(std::tolower(static_cast<unsigned char>(out[i])));
    }
    return out;
}

// Parses one simple-selector segment: tag#id.class[attr=v][attr2]...
bool ParseSimpleSelector(const std::string &segment, SimpleSelector &out)
{
    if (segment.empty() || segment.find('>') != std::string::npos ||
        segment.find(',') != std::string::npos) {
        return false; // combinators/lists unsupported
    }
    size_t i = 0;
    // optional tag name
    if (std::isalpha(static_cast<unsigned char>(segment[0]))) {
        size_t start = i;
        while (i < segment.size() &&
               (std::isalnum(static_cast<unsigned char>(segment[i])) || segment[i] == '-' ||
                segment[i] == '_')) {
            i++;
        }
        out.tag = ToLowerCopy(segment.substr(start, i - start));
    }
    while (i < segment.size()) {
        char c = segment[i];
        if (c == '#') {
            i++;
            size_t start = i;
            while (i < segment.size() && segment[i] != '.' && segment[i] != '[') {
                i++;
            }
            out.id = TrimCopy(segment.substr(start, i - start));
            if (out.id.empty()) {
                return false;
            }
        } else if (c == '.') {
            i++;
            size_t start = i;
            while (i < segment.size() && segment[i] != '.' && segment[i] != '[' &&
                   segment[i] != '#') {
                i++;
            }
            std::string cls = TrimCopy(segment.substr(start, i - start));
            if (cls.empty()) {
                return false;
            }
            out.classes.push_back(cls);
        } else if (c == '[') {
            size_t close = segment.find(']', i);
            if (close == std::string::npos) {
                return false;
            }
            std::string inner = segment.substr(i + 1, close - i - 1);
            i = close + 1;
            size_t eq = inner.find('=');
            if (eq == std::string::npos) {
                std::string name = ToLowerCopy(TrimCopy(inner));
                if (name.empty()) {
                    return false;
                }
                out.attrs.push_back({name, ""});
            } else {
                std::string name = ToLowerCopy(TrimCopy(inner.substr(0, eq)));
                std::string value = TrimCopy(inner.substr(eq + 1));
                if (!value.empty() && (value.front() == '"' || value.front() == '\'')) {
                    value = value.substr(1, value.size() > 2 ? value.size() - 2 : 0);
                }
                if (name.empty()) {
                    return false;
                }
                out.attrs.push_back({name, value});
            }
        } else {
            return false; // unsupported char
        }
    }
    return !out.tag.empty() || !out.id.empty() || !out.classes.empty() || !out.attrs.empty();
}

// Parses "k=v" / "k='v'" / k="v" / bare-k attribute pairs from the raw text
// that follows the tag name inside "<tag ...>".
void ParseAttributes(const std::string &raw, std::map<std::string, std::string> &attrs)
{
    static const std::regex attrRe(
        "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*(?:=\\s*(\"[^\"]*\"|'[^']*'|[^\\s\"'>]+))?");
    std::sregex_iterator it(raw.begin(), raw.end(), attrRe);
    std::sregex_iterator end;
    for (; it != end; ++it) {
        std::string name = ToLowerCopy((*it)[1].str());
        std::string value = (*it)[2].str();
        if (!value.empty() && (value.front() == '"' || value.front() == '\'')) {
            value = value.substr(1, value.size() > 2 ? value.size() - 2 : 0);
        }
        if (!name.empty()) {
            attrs[name] = value;
        }
    }
}

bool IsVoidTag(const std::string &tag)
{
    static const std::set<std::string> voidTags = {
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    };
    return voidTags.find(tag) != voidTags.end();
}

// Extracts plain text from inner HTML: strips script/style blocks, then tags,
// then decodes the most common entities.
std::string ExtractText(const std::string &html)
{
    static const std::regex blockRe("<(script|style)\\b[^>]*>.*?</\\1\\s*>",
                                    std::regex::icase | std::regex::optimize);
    static const std::regex tagRe("<[^>]+>");
    std::string text = std::regex_replace(html, blockRe, "");
    text = std::regex_replace(text, tagRe, " ");
    // entity decode
    text = std::regex_replace(text, std::regex("&nbsp;"), " ");
    text = std::regex_replace(text, std::regex("&amp;"), "&");
    text = std::regex_replace(text, std::regex("&lt;"), "<");
    text = std::regex_replace(text, std::regex("&gt;"), ">");
    text = std::regex_replace(text, std::regex("&quot;"), "\"");
    text = std::regex_replace(text, std::regex("&#39;|&apos;"), "'");
    // collapse whitespace
    text = std::regex_replace(text, std::regex("\\s+"), " ");
    return TrimCopy(text);
}

// Finds all elements matching one SimpleSelector within [html].
std::vector<SelectedElement> FindMatches(const std::string &html, const SimpleSelector &sel)
{
    std::vector<SelectedElement> results;
    static const std::regex openTagRe("<([a-zA-Z][a-zA-Z0-9-]*)((?:[^<>]*)?)(/?)>");
    std::sregex_iterator it(html.begin(), html.end(), openTagRe);
    std::sregex_iterator end;
    for (; it != end; ++it) {
        const std::smatch &open = *it;
        std::string tag = ToLowerCopy(open[1].str());
        bool selfClosing = open[3].str() == "/";
        // tag constraint
        if (!sel.tag.empty() && tag != sel.tag) {
            continue;
        }
        std::map<std::string, std::string> attrs;
        ParseAttributes(open[2].str(), attrs);
        // id constraint
        if (!sel.id.empty()) {
            auto found = attrs.find("id");
            if (found == attrs.end() || found->second != sel.id) {
                continue;
            }
        }
        // class constraints
        if (!sel.classes.empty()) {
            auto found = attrs.find("class");
            if (found == attrs.end()) {
                continue;
            }
            std::string haystack = " " + ToLowerCopy(found->second) + " ";
            bool all = true;
            for (const std::string &cls : sel.classes) {
                if (haystack.find(" " + ToLowerCopy(cls) + " ") == std::string::npos) {
                    all = false;
                    break;
                }
            }
            if (!all) {
                continue;
            }
        }
        // attribute constraints (exact value; empty value = existence)
        bool attrsOk = true;
        for (const auto &want : sel.attrs) {
            auto found = attrs.find(want.first);
            if (found == attrs.end()) {
                attrsOk = false;
                break;
            }
            if (!want.second.empty() && found->second != want.second) {
                attrsOk = false;
                break;
            }
        }
        if (!attrsOk) {
            continue;
        }

        SelectedElement element;
        element.attrs = attrs;
        size_t openEnd = static_cast<size_t>(open.position()) +
                         static_cast<size_t>(open.length());
        size_t contentEnd = openEnd; // end of inner content
        size_t outerEnd = openEnd;
        if (selfClosing || IsVoidTag(tag)) {
            element.innerHtml = "";
        } else {
            // depth-scan for the matching close tag
            const std::string closeReSource = "</\\s*" + tag + "\\s*>";
            const std::string openReSource = "<" + tag + "(\\s|/|>)";
            const std::regex closeRe(closeReSource, std::regex::icase);
            const std::regex sameOpenRe(openReSource, std::regex::icase);
            size_t scan = openEnd;
            int depth = 1;
            bool closed = false;
            while (scan < html.size()) {
                std::string rest = html.substr(scan);
                std::sregex_iterator closeIt(rest.begin(), rest.end(), closeRe);
                std::sregex_iterator openIt(rest.begin(), rest.end(), sameOpenRe);
                size_t nextClose = std::string::npos;
                size_t closeLen = 0;
                if (closeIt != std::sregex_iterator()) {
                    nextClose = static_cast<size_t>(closeIt->position());
                    closeLen = static_cast<size_t>(closeIt->length());
                }
                size_t nextOpen = std::string::npos;
                if (openIt != std::sregex_iterator()) {
                    nextOpen = static_cast<size_t>(openIt->position());
                }
                if (nextClose == std::string::npos) {
                    break; // malformed: no close tag at all
                }
                if (nextOpen != std::string::npos && nextOpen < nextClose) {
                    // nested same-tag open (ignore self-closing "<tag/")
                    std::string after = rest.substr(nextOpen);
                    if (after.size() > 1 && after[1] != '/') {
                        depth++;
                    }
                    scan += nextOpen + 1;
                    continue;
                }
                depth--;
                if (depth == 0) {
                    contentEnd = scan + nextClose;
                    outerEnd = scan + nextClose + closeLen;
                    closed = true;
                    break;
                }
                scan += nextClose + closeLen;
            }
            if (!closed) {
                // tolerate truncated html: treat rest as inner content
                contentEnd = html.size();
                outerEnd = html.size();
            }
            element.innerHtml = html.substr(openEnd, contentEnd - openEnd);
        }
        element.outerHtml = html.substr(static_cast<size_t>(open.position()), outerEnd -
                           static_cast<size_t>(open.position()));
        element.text = ExtractText(element.innerHtml);
        results.push_back(element);
    }
    return results;
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

std::string NativeSelectHtml(const std::string &html, const std::string &cssQuery)
{
    if (html.empty() || cssQuery.empty()) {
        return "[]";
    }
    // split into whitespace-separated segments
    std::vector<SimpleSelector> selectors;
    std::istringstream stream(cssQuery);
    std::string segment;
    while (stream >> segment) {
        SimpleSelector sel;
        if (!ParseSimpleSelector(segment, sel)) {
            return "[]";
        }
        selectors.push_back(sel);
    }
    if (selectors.empty()) {
        return "[]";
    }

    std::vector<SelectedElement> current = FindMatches(html, selectors[0]);
    for (size_t i = 1; i < selectors.size() && !current.empty(); i++) {
        std::vector<SelectedElement> next;
        for (const SelectedElement &parent : current) {
            std::vector<SelectedElement> found = FindMatches(parent.innerHtml, selectors[i]);
            for (SelectedElement &e : found) {
                next.push_back(e);
            }
        }
        current = next;
    }

    std::ostringstream json;
    json << "[";
    for (size_t i = 0; i < current.size(); i++) {
        if (i > 0) {
            json << ",";
        }
        const SelectedElement &e = current[i];
        json << "{\"outerHtml\":\"" << JsonEscape(e.outerHtml) << "\",\"innerHtml\":\""
             << JsonEscape(e.innerHtml) << "\",\"text\":\"" << JsonEscape(e.text)
             << "\",\"attrs\":{";
        size_t a = 0;
        for (const auto &attr : e.attrs) {
            if (a > 0) {
                json << ",";
            }
            json << "\"" << JsonEscape(attr.first) << "\":\"" << JsonEscape(attr.second) << "\"";
            a++;
        }
        json << "}}";
    }
    json << "]";
    return json.str();
}
