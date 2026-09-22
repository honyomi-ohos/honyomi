// MangaK theme engine (en: mangabuddy, toonilyme) — Next.js RSC site with JSON API
// Includes a JS port of keiyoushi's extractNextJs (React Flight parser, reduced).
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { imageFallbackHost: 'rx.rzyn.net' };
  const am = kt.match(/override val apiUrl[^=]*=\s*get\(\)\s*=\s*"([^"]*)"/);
  if (am) config.apiUrl = am[1];
  warnings.push('image CDN fallback applied preemptively (rx.qvzrX.org -> rx.rzyn.net)');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mangak)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var API = CFG.apiUrl || ('https://api.' + BASE.replace(/^https?:\\/\\//, '').split('/')[0]);

// ---- React Flight (RSC) parser (ported from keiyoushi utils/NextJs.kt) ----

function flightBodyFromHtml(html) {
  var re = /self\\.__next_f\\.push\\(\\[1,("(?:[^"\\\\]|\\\\.)*")\\]/g;
  var body = '';
  var m;
  while ((m = re.exec(html)) !== null) {
    try { body += JSON.parse(m[1]); } catch (e) {}
  }
  return body;
}

function parseJsonAt(body, start) {
  if (start >= body.length) { return [null, start]; }
  var depth = 0, inString = false, escape = false, i = start;
  while (i < body.length) {
    var c = body.charAt(i); i++;
    if (escape) { escape = false; continue; }
    if (c === '\\\\' && inString) { escape = true; continue; }
    if (c === '"') { inString = !inString; continue; }
    if (inString) { continue; }
    if (c === '{' || c === '[') { depth++; }
    else if (c === '}' || c === ']') {
      depth--;
      if (depth === 0) {
        try { return [JSON.parse(body.substring(start, i)), i]; }
        catch (e) { return [null, i]; }
      }
    }
    if (depth === 0 && /\\s/.test(c)) {
      try { return [JSON.parse(body.substring(start, i - 1)), i]; }
      catch (e) { return [null, i]; }
    }
  }
  return [null, i];
}

function rscPayloads(body, chunkCache, modelCache) {
  var results = [];
  var pos = 0;
  while (pos < body.length) {
    var colonIdx = body.indexOf(':', pos);
    if (colonIdx === -1) { break; }
    var id = body.substring(pos, colonIdx);
    if (!id || !/^[0-9a-fA-F]+$/.test(id)) { pos++; continue; }
    pos = colonIdx + 1;
    if (pos >= body.length) { break; }
    if (body.charAt(pos) === 'T') {
      pos++;
      var commaIdx = body.indexOf(',', pos);
      if (commaIdx === -1) { break; }
      var byteLen = parseInt(body.substring(pos, commaIdx), 16);
      if (isNaN(byteLen)) { break; }
      pos = commaIdx + 1;
      var bytes = 0;
      var start = pos;
      while (pos < body.length && bytes < byteLen) {
        var code = body.charCodeAt(pos);
        if (code < 0x80) { bytes += 1; }
        else if (code < 0x800) { bytes += 2; }
        else if (code >= 0xD800 && code <= 0xDBFF) { bytes += 4; pos++; }
        else { bytes += 3; }
        pos++;
      }
      var content = body.substring(start, pos);
      chunkCache[id] = content;
      try { results.push(JSON.parse(content)); } catch (e) {}
    } else {
      var r = parseJsonAt(body, pos);
      if (r[0] !== null) {
        results.push(r[0]);
        modelCache[id] = r[0];
      }
      pos = r[1];
    }
  }
  return results;
}

function isPlainObj(v) { return v !== null && typeof v === 'object' && !Array.isArray(v); }

function walkRefSegment(value, seg) {
  if (isPlainObj(value)) { return (seg in value) ? value[seg] : null; }
  if (Array.isArray(value)) {
    if (value.length >= 4 && value[0] === '$') {
      if (seg === 'type') { return value[1]; }
      if (seg === 'key') { return value[2]; }
      if (seg === 'props') { return value[3]; }
    }
    var n = parseInt(seg, 10);
    return isNaN(n) ? null : (value[n] !== undefined ? value[n] : null);
  }
  return null;
}

function resolveRefs(element, chunkCache, modelCache, resolving) {
  if (Array.isArray(element)) {
    return element.map(function (v) { return resolveRefs(v, chunkCache, modelCache, resolving); });
  }
  if (!isPlainObj(element)) { return element; }
  var out = {};
  for (var k in element) { out[k] = resolveRefs(element[k], chunkCache, modelCache, resolving); }
  return out;
}

function resolveStr(str, chunkCache, modelCache, resolving) {
  if (str === '$undefined') { return null; }
  if (str === '$Infinity' || str === '$-Infinity' || str === '$NaN' || str === '$-0') { return str.substring(1); }
  if (str.charAt(1) === '$') { return str.substring(1); }
  if (str.charAt(1) === 'D' || str.charAt(1) === 'n') { return str.substring(2); }
  if (str.charAt(1) === 'Q') { return resolveMapRef(str.substring(2), chunkCache, modelCache, resolving) || str; }
  if (str.charAt(1) === 'W') { return resolveSetRef(str.substring(2), chunkCache, modelCache, resolving) || str; }
  if (str.charAt(1) === 'L' || str.charAt(1) === '@') { return resolveModelRef(str.substring(2), chunkCache, modelCache, resolving) || str; }
  return resolveModelRef(str.substring(1), chunkCache, modelCache, resolving) || str;
}

function resolveValue(value, chunkCache, modelCache, resolving) {
  if (typeof value === 'string' && value.charAt(0) === '$' && value.length >= 2) {
    return resolveStr(value, chunkCache, modelCache, resolving);
  }
  return resolveRefs(value, chunkCache, modelCache, resolving);
}

function resolveModelRef(reference, chunkCache, modelCache, resolving) {
  var segments = reference.split(':');
  var id = segments[0];
  if (segments.length === 1 && chunkCache[id] !== undefined) { return chunkCache[id]; }
  if (resolving[id]) { return null; }
  var guard = {};
  for (var r in resolving) { guard[r] = true; }
  guard[id] = true;
  var value = modelCache[id];
  if (value === undefined) { return null; }
  for (var i = 1; i < segments.length; i++) {
    if (typeof value === 'string' && value.charAt(0) === '$') {
      value = resolveStr(value, chunkCache, modelCache, guard);
    }
    value = walkRefSegment(value, segments[i]);
    if (value === null || value === undefined) { return null; }
  }
  return resolveValue(value, chunkCache, modelCache, guard);
}

function resolveMapRef(id, chunkCache, modelCache, resolving) {
  if (resolving[id]) { return null; }
  var entries = modelCache[id];
  if (!Array.isArray(entries)) { return null; }
  var guard = {};
  for (var r in resolving) { guard[r] = true; }
  guard[id] = true;
  var resolved = resolveRefs(entries, chunkCache, modelCache, guard);
  var out = {};
  for (var i = 0; i < resolved.length; i++) {
    var p = resolved[i];
    if (Array.isArray(p) && p.length === 2) {
      var key = typeof p[0] === 'string' ? p[0] : JSON.stringify(p[0]);
      out[key] = p[1];
    }
  }
  return out;
}

function resolveSetRef(id, chunkCache, modelCache, resolving) {
  if (resolving[id]) { return null; }
  var values = modelCache[id];
  if (!Array.isArray(values)) { return null; }
  var guard = {};
  for (var r in resolving) { guard[r] = true; }
  guard[id] = true;
  return resolveRefs(values, chunkCache, modelCache, guard);
}

function findValue(payload, pred) {
  if (!isPlainObj(payload) && !Array.isArray(payload)) { return null; }
  if (pred(payload)) { return payload; }
  var children = isPlainObj(payload) ? Object.keys(payload).map(function (k) { return payload[k]; }) : payload;
  for (var i = 0; i < children.length; i++) {
    var found = findValue(children[i], pred);
    if (found !== null) { return found; }
  }
  return null;
}

async function nextJsPageProps(url) {
  var html = await $.http.get(url);
  var body = flightBodyFromHtml(html);
  if (!body) { return null; }
  var chunkCache = {};
  var modelCache = {};
  var payloads = rscPayloads(body, chunkCache, modelCache);
  for (var i = 0; i < payloads.length; i++) {
    var resolved = resolveValue(payloads[i], chunkCache, modelCache, {});
    var found = findValue(resolved, function (o) { return isPlainObj(o) && ('pageProps' in o); });
    if (found !== null) { return found.pageProps; }
  }
  return null;
}

// ---- Source logic ----

function statusMap(s) {
  switch (String(s || '').toLowerCase()) {
    case 'ongoing': return 'ongoing';
    case 'completed': return 'completed';
    case 'hiatus': return 'on_hiatus';
    case 'cancelled': return 'cancelled';
    default: return '';
  }
}

function applyImageFallback(u) {
  return String(u || '').replace(/rx\\.qvzr[a-z]\\.org/g, CFG.imageFallbackHost);
}

async function searchApi(page, extra) {
  var url = API + '/titles/search?page=' + page + '&limit=24' + (extra || '');
  var text = await $.http.get(url);
  var data = JSON.parse(text).data || {};
  var items = data.items || [];
  var out = [];
  for (var i = 0; i < items.length; i++) {
    out.push({
      key: items[i].url + '@' + items[i].id,
      title: items[i].name || '',
      coverUrl: items[i].cover || ''
    });
  }
  return { mangas: out, hasNextPage: !!(data.pagination && data.pagination.has_next) };
}

module.exports = {
  getPopularManga: async function (page) {
    return searchApi(page, '&sort=popular&window=week');
  },

  getSearchManga: async function (page, query) {
    var q = '';
    if (query) {
      q = String(query).replace(/[^a-zA-Z0-9 ]/g, '').trim().substring(0, 50);
    }
    return searchApi(page, q ? '&q=' + encodeURIComponent(q) : '');
  },

  getMangaDetail: async function (mangaKey) {
    var urlPart = String(mangaKey).split('@')[0];
    var props = await nextJsPageProps(BASE + urlPart);
    var m = props && props.initialManga ? props.initialManga : {};
    var authors = m.authors || [];
    var genres = m.genres || [];
    return {
      key: mangaKey,
      title: m.name || '',
      coverUrl: m.cover || '',
      author: authors.map(function (a) { return a.name; }).join(', '),
      description: m.summary || '',
      genre: genres.map(function (g) { return g.name; }).join(', '),
      status: statusMap(m.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var id = String(mangaKey).split('@')[1] || '';
    var text = await $.http.get(API + '/titles/' + id + '/chapters?cv=' + Date.now());
    var data = JSON.parse(text).data || {};
    var rows = (data.chapters || []).slice().sort(function (a, b) {
      return (b.chapter_number || 0) - (a.chapter_number || 0);
    });
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      out.push({
        key: rows[i].url,
        name: rows[i].name || '',
        chapterNumber: rows[i].chapter_number !== undefined && rows[i].chapter_number !== null ? rows[i].chapter_number : -1,
        dateUpload: rows[i].updated_at ? Math.floor(new Date(rows[i].updated_at).getTime() / 1000) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var props = await nextJsPageProps(BASE + chapterKey);
    var images = props && props.initialChapter ? (props.initialChapter.images || []) : [];
    var pages = [];
    for (var i = 0; i < images.length; i++) {
      pages.push({ index: i, url: applyImageFallback(images[i]) });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
