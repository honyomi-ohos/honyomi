// Aurora theme engine (Next.js RSC + AT-Field encrypted images: manganyx / mangasbrasuka / mugiwarasoficial / leitordemangas)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {};

export function extract(ctx) {
  const warnings = [];
  const config = { ...DEFAULTS };
  if (/rateLimit\s*\(/.test(ctx.ktText)) {
    warnings.push('rateLimit not portable; requests may be throttled by site');
  }
  return { ok: true, config, warnings };
}

// RSC flight parser shared block (ported from keiyoushi/utils/NextJs.kt)
const RSC_PARSER_JS = `
// ---------------- RSC flight parser (port of NextJs.kt) ----------------
function rscExtractPayloads(body, chunkCache, modelCache) {
  var results = [];
  var pos = 0;
  while (pos < body.length) {
    var colonIdx = body.indexOf(':', pos);
    if (colonIdx === -1) { break; }
    var id = body.substring(pos, colonIdx);
    if (id.length === 0 || !/^[0-9a-fA-F]+$/.test(id)) { pos++; continue; }
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
      var chunkContent = body.substring(start, pos);
      chunkCache[id] = chunkContent;
      try { results.push(JSON.parse(chunkContent)); } catch (e) { /* not JSON */ }
    } else {
      var parsed = rscParseJsonAt(body, pos);
      if (parsed.element !== null) {
        results.push(parsed.element);
        modelCache[id] = parsed.element;
      }
      pos = parsed.end;
    }
  }
  return results;
}

function rscParseJsonAt(body, start) {
  if (start >= body.length) { return { element: null, end: start }; }
  var depth = 0;
  var inString = false;
  var escape = false;
  var i = start;
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
        try { return { element: JSON.parse(body.substring(start, i)), end: i }; }
        catch (e) { return { element: null, end: i }; }
      }
    }
    if (depth === 0 && /\\s/.test(c)) {
      try { return { element: JSON.parse(body.substring(start, i - 1)), end: i }; }
      catch (e) { return { element: null, end: i }; }
    }
  }
  return { element: null, end: i };
}

function rscResolveRefs(element, chunkCache, modelCache, resolving) {
  if (Array.isArray(element)) {
    return element.map(function (x) { return rscResolveRefs(x, chunkCache, modelCache, resolving); });
  }
  if (element && typeof element === 'object') {
    var out = {};
    for (var k in element) { out[k] = rscResolveRefs(element[k], chunkCache, modelCache, resolving); }
    return out;
  }
  if (typeof element === 'string' && element.charAt(0) === '$' && element.length >= 2) {
    var c1 = element.charAt(1);
    if (element === '$undefined') { return null; }
    if (element === '$Infinity' || element === '$-Infinity' || element === '$NaN' || element === '$-0') {
      return element.substring(1);
    }
    if (c1 === '$') { return element.substring(1); }
    if (c1 === 'D' || c1 === 'n') { return element.substring(2); }
    if (c1 === 'Q') { return rscResolveMapRef(element.substring(2), chunkCache, modelCache, resolving) || element; }
    if (c1 === 'W') { return rscResolveSetRef(element.substring(2), chunkCache, modelCache, resolving) || element; }
    if (c1 === 'L' || c1 === '@') { return rscResolveModelRef(element.substring(2), chunkCache, modelCache, resolving) || element; }
    return rscResolveModelRef(element.substring(1), chunkCache, modelCache, resolving) || element;
  }
  return element;
}

function rscResolveModelRef(reference, chunkCache, modelCache, resolving) {
  var segments = reference.split(':');
  var id = segments[0];
  if (segments.length === 1 && Object.prototype.hasOwnProperty.call(chunkCache, id)) {
    return chunkCache[id];
  }
  if (resolving.indexOf(id) >= 0) { return null; }
  var guard = resolving.concat([id]);
  var value = Object.prototype.hasOwnProperty.call(modelCache, id) ? modelCache[id] : null;
  if (value === null || value === undefined) { return null; }
  for (var i = 1; i < segments.length; i++) {
    if (typeof value === 'string' && value.charAt(0) === '$') {
      value = rscResolveRefs(value, chunkCache, modelCache, guard);
    }
    value = rscWalkSegment(value, segments[i]);
    if (value === null || value === undefined) { return null; }
  }
  return rscResolveRefs(value, chunkCache, modelCache, guard);
}

function rscWalkSegment(value, segment) {
  if (Array.isArray(value)) {
    if (value.length >= 4 && value[0] === '$') {
      if (segment === 'type') { return value[1]; }
      if (segment === 'key') { return value[2]; }
      if (segment === 'props') { return value[3]; }
    }
    var idx = parseInt(segment, 10);
    return isNaN(idx) ? null : (idx >= 0 && idx < value.length ? value[idx] : null);
  }
  if (value && typeof value === 'object') {
    return Object.prototype.hasOwnProperty.call(value, segment) ? value[segment] : null;
  }
  return null;
}

function rscResolveMapRef(id, chunkCache, modelCache, resolving) {
  if (resolving.indexOf(id) >= 0) { return null; }
  var entries = Object.prototype.hasOwnProperty.call(modelCache, id) ? modelCache[id] : null;
  if (!Array.isArray(entries)) { return null; }
  var resolved = rscResolveRefs(entries, chunkCache, modelCache, resolving.concat([id]));
  var out = {};
  for (var i = 0; i < resolved.length; i++) {
    var p = resolved[i];
    if (Array.isArray(p) && p.length === 2) {
      var k = (typeof p[0] === 'string') ? p[0] : JSON.stringify(p[0]);
      out[k] = p[1];
    }
  }
  return out;
}

function rscResolveSetRef(id, chunkCache, modelCache, resolving) {
  if (resolving.indexOf(id) >= 0) { return null; }
  var values = Object.prototype.hasOwnProperty.call(modelCache, id) ? modelCache[id] : null;
  if (!Array.isArray(values)) { return null; }
  return rscResolveRefs(values, chunkCache, modelCache, resolving.concat([id]));
}

function rscFindValue(payload, predicate) {
  if (!payload || typeof payload !== 'object') { return null; }
  if (predicate(payload)) { return payload; }
  var children = Array.isArray(payload) ? payload : (function () { var v = []; for (var k in payload) { v.push(payload[k]); } return v; })();
  for (var i = 0; i < children.length; i++) {
    var result = rscFindValue(children[i], predicate);
    if (result !== null) { return result; }
  }
  return null;
}

// Extract the first RSC payload matching predicate from an HTTP body
// (text/x-component raw flight, or HTML with inline self.__next_f.push scripts).
function rscExtract(body, predicate) {
  var chunkCache = {};
  var modelCache = {};
  var payloads = [];
  if (/self\\.__next_f\\.push/.test(body)) {
    var re = /self\\.__next_f\\.push\\(\\s*(\\[[\\s\\S]*?\\])\\s*\\)\\s*;/g;
    var m;
    while ((m = re.exec(body)) !== null) {
      try {
        var arr = JSON.parse(m[1]);
        var content = (typeof arr[1] === 'string') ? arr[1] : '';
        payloads = payloads.concat(rscExtractPayloads(content, chunkCache, modelCache));
      } catch (e) { /* skip chunk */ }
    }
  } else {
    payloads = rscExtractPayloads(body, chunkCache, modelCache);
  }
  for (var i = 0; i < payloads.length; i++) {
    var resolved = rscResolveRefs(payloads[i], chunkCache, modelCache, []);
    var found = rscFindValue(resolved, predicate);
    if (found !== null) { return found; }
  }
  return null;
}
`;

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: aurora)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};
${RSC_PARSER_JS}

// ---------------- aurora theme engine ----------------
function baseHeaders(extra) {
  var h = {
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Sec-Fetch-User': '?1',
    'Alt-Used': BASE.replace(/^https?:\\/\\//, ''),
    'Cookie': 'mnx_adulto=1'
  };
  if (extra) { for (var k in extra) { h[k] = extra[k]; } }
  return h;
}

function mangaFromDto(dto, keepKey) {
  var title = dto.title || dto.name || '';
  var cover = dto.coverUrl || dto.image || '';
  var slugRaw = dto.slug || dto.url || '';
  var type = '';
  var slug = slugRaw;
  if (/^https?:\\/\\//.test(slugRaw)) {
    try {
      var u = new URL(slugRaw);
      var segs = u.pathname.split('/').filter(function (p) { return p.length > 0; });
      type = (segs[0] || '').toLowerCase();
      slug = segs[segs.length - 1] || '';
    } catch (e) { /* keep raw slug */ }
  }
  return {
    key: keepKey || (type ? '/' + type + '/' + slug : '/' + slug),
    title: title,
    coverUrl: cover,
    author: (dto.author && dto.author.name) ? dto.author.name : '',
    artist: '',
    description: dto.description || '',
    genre: Array.isArray(dto.genre) ? dto.genre.join(', ') : '',
    status: ''
  };
}

async function fetchCatalog() {
  var text = await $.http.get(BASE + '/catalogo', baseHeaders());
  var dto = rscExtract(text, function (o) {
    if (!o || typeof o !== 'object' || Array.isArray(o)) { return false; }
    return Array.isArray(o.series) || Array.isArray(o.updates);
  });
  var list = dto ? (dto.series || dto.updates || []) : [];
  var out = [];
  for (var i = 0; i < list.length; i++) { out.push(mangaFromDto(list[i])); }
  return out;
}

function entryPath(mangaKey) {
  var parts = String(mangaKey).split('/').filter(function (p) { return p.length > 0; });
  return '/' + parts.join('/');
}

var PT_MONTHS = { janeiro: 0, fevereiro: 1, 'março': 2, abril: 3, maio: 4, junho: 5, julho: 6, agosto: 7, setembro: 8, outubro: 9, novembro: 10, dezembro: 11 };

function parsePtDate(s) {
  var m = /(\\d{1,2})\\s+de\\s+([a-zçà-ÿ]+)\\s+de\\s+(\\d{4})/i.exec(String(s || ''));
  if (!m) { return 0; }
  var mo = PT_MONTHS[m[2].toLowerCase()];
  if (mo === undefined) { return 0; }
  return Date.UTC(Number(m[3]), mo, Number(m[1]));
}

// ---------------- AT-Field decryption ----------------
var atFieldKey = null;

function b64ToBytes(b64) {
  var s = String(b64 || '').replace(/\\s+/g, '').replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4 !== 0) { s += '='; }
  var bin = atob(s);
  var bytes = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) { bytes[i] = bin.charCodeAt(i); }
  return bytes;
}

async function hmacSha256Bytes(keyBytes, data) {
  var key = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, data));
}

function auroraGetParams(payload) {
  var bytes = b64ToBytes(payload);
  var v = bytes.length > 0 ? bytes[0] : 0;
  var e = 0;
  if (bytes.length >= 5) { e = (bytes[1] << 24) | (bytes[2] << 16) | (bytes[3] << 8) | bytes[4]; }
  return { v: v, e: e };
}

async function getAtFieldKey(payload) {
  if (atFieldKey) { return atFieldKey; }
  var p = auroraGetParams(payload);
  var text = await $.http.get(BASE + '/api/atfield/key?v=' + p.v + '&e=' + p.e, baseHeaders({ Accept: '*/*' }));
  var dto;
  try { dto = JSON.parse(text); } catch (e) { dto = null; }
  if (!dto || !dto.k) { throw new Error('AT-Field key fetch failed'); }
  atFieldKey = dto.k;
  return atFieldKey;
}

async function auroraDecrypt(payload, key) {
  var bytes = b64ToBytes(payload);
  if (bytes.length < 14) { return ''; }
  var baseData = bytes.subarray(5, 13);
  var cipherText = bytes.subarray(13);
  var chapterKey = b64ToBytes(key);
  var out = new Uint8Array(cipherText.length);
  var o = 0;
  var i = 0;
  while (o < cipherText.length) {
    var block = new Uint8Array(baseData.length + 1);
    block.set(baseData, 0);
    block[baseData.length] = i & 0xFF;
    var hashBlock = await hmacSha256Bytes(chapterKey, block);
    var copyLen = Math.min(hashBlock.length, cipherText.length - o);
    for (var j = 0; j < copyLen; j++) { out[o + j] = cipherText[o + j] ^ hashBlock[j]; }
    o += copyLen;
    i++;
  }
  return new TextDecoder('utf-8').decode(out);
}

module.exports = {
  getPopularManga: async function (_page) {
    return { mangas: await fetchCatalog(), hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var all = await fetchCatalog();
    var q = String(query || '').toLowerCase();
    var out = [];
    for (var i = 0; i < all.length; i++) {
      if (all[i].title.toLowerCase().indexOf(q) >= 0) { out.push(all[i]); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(BASE + entryPath(mangaKey), baseHeaders());
    var doc = $.html.parse(text);
    var scripts = doc.select('script');
    var dataText = '';
    var fallbackText = '';
    for (var i = 0; i < scripts.length; i++) {
      var s = scripts[i];
      var body = s.text();
      if (body.indexOf('ComicSeries') < 0) { continue; }
      if (!dataText && s.attr('type')) { dataText = body; }
      if (!fallbackText) { fallbackText = body; }
    }
    if (dataText) {
      try {
        var dto = JSON.parse(dataText);
        return mangaFromDto(dto, mangaKey);
      } catch (e) { /* fall through to regex fallback */ }
    }
    var detail = { key: mangaKey, title: '', coverUrl: '', author: '', artist: '', description: '', genre: '', status: '' };
    if (fallbackText) {
      var cleaned = fallbackText.replace(/\\\\{2,}/g, '');
      var dm = /description":"([^"]+)/.exec(cleaned);
      if (dm) { detail.description = dm[1]; }
      var gm = /genre":([^\\]]+\\])/.exec(cleaned);
      if (gm) {
        try { detail.genre = JSON.parse(gm[1]).join(', '); } catch (e2) { /* keep empty */ }
      }
      var am = /author[^.]+name":"([^"]+)/.exec(cleaned);
      if (am) { detail.author = am[1]; }
    }
    return detail;
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(BASE + entryPath(mangaKey), baseHeaders());
    var dto = rscExtract(text, function (o) {
      if (!o || typeof o !== 'object' || Array.isArray(o)) { return false; }
      if (!Array.isArray(o.chapters)) { return false; }
      return ('serieSlug' in o) || ('slug' in o);
    });
    var list = dto ? dto.chapters : [];
    var chapters = [];
    for (var i = 0; i < list.length; i++) {
      var ch = list[i];
      var num = String(ch.number || '');
      chapters.push({
        key: entryPath(mangaKey) + '/' + num,
        name: 'Capítulo ' + num,
        chapterNumber: parseFloat(num) || -1,
        dateUpload: parsePtDate(ch.releaseDate),
        pages: 0,
        sortOrder: 0
      });
    }
    // site lists newest first; normalize to oldest-first
    chapters.sort(function (a, b) { return b.chapterNumber - a.chapterNumber; });
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = chapters.length - 1 - j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var parts = String(chapterKey).split('/').filter(function (p) { return p.length > 0; });
    var number = parts.pop() || '';
    var entry = '/' + parts.join('/');
    var headers = baseHeaders({
      'rsc': '1',
      'Referer': BASE + entry,
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Site': 'same-origin',
      'next-url': entry,
      'Accept': '*/*',
      'Cookie': 'mnx_adulto=1; mnx_gate_' + number + '=1'
    });
    var text = await $.http.get(BASE + entry + '/' + number, headers);
    var dto = rscExtract(text, function (o) {
      return o && typeof o === 'object' && !Array.isArray(o) && Array.isArray(o.pages);
    });
    var pages = dto ? dto.pages : [];
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      var enc = pages[i] ? pages[i].url : '';
      if (!enc) { continue; }
      var key = await getAtFieldKey(enc);
      var url = await auroraDecrypt(enc, key);
      if (url) { out.push({ index: out.length, url: url }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/', Cookie: 'mnx_adulto=1' };
  }
};
`;
}
