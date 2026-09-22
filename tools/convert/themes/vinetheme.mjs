// VineTheme engine (Next.js RSC: divascans / drakescans / kaynscans / valirscans / witchscans)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  hideLocked: true,
};

export function extract(ctx) {
  const warnings = [];
  const config = { ...DEFAULTS };
  // All current extensions are bare subclasses; preferences (hide locked) default to true.
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
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: vinetheme)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};
${RSC_PARSER_JS}

// ---------------- vine theme engine ----------------
function absoluteUrl(u) {
  if (!u) { return ''; }
  return /^https?:\\/\\//.test(u) ? u : BASE + u;
}

function numToStr(n) {
  var s = String(n);
  return s.replace(/\\.0$/, '');
}

function statusFrom(s) {
  switch (String(s || '')) {
    case 'ONGOING': return 'ongoing';
    case 'COMPLETED': return 'completed';
    case 'HIATUS': return 'hiatus';
    case 'CANCELLED': return 'cancelled';
    default: return '';
  }
}

function stripEmoji(s) {
  return String(s || '').replace(/[^\\x20-\\x7E\\p{L}0-9\\- ]+/gu, '').trim();
}

function htmlToText(html) {
  var t = String(html || '');
  t = t.replace(/<br\\s*\\/?>/gi, '\\n');
  t = t.replace(/<\\/p>/gi, '\\n\\n');
  t = t.replace(/<a[^>]*href="([^"]*)"[^>]*>([\\s\\S]*?)<\\/a>/gi, function (_m, href, text) {
    var label = text.replace(/<[^>]+>/g, '').trim();
    return label ? '[' + label + '](' + absoluteUrl(href) + ')' : absoluteUrl(href);
  });
  t = t.replace(/<[^>]+>/g, '');
  try { t = decodeURIComponent(t); } catch (e) { /* keep */ }
  return t.trim();
}

function mangaFromDto(dto) {
  var genres = [];
  if (dto.type) { genres.push(dto.type); }
  if (dto.origin) { genres.push(dto.origin); }
  if (dto.isMature) { genres.push('Mature'); }
  var genreList = dto.genres || [];
  for (var i = 0; i < genreList.length; i++) {
    var g = genreList[i] || {};
    var dn = g.name ? g.name : (g.genre ? g.genre.slug : '');
    if (dn) { genres.push(stripEmoji(dn)); }
  }
  var seen = {};
  var genreOut = [];
  for (var j = 0; j < genres.length; j++) {
    if (genres[j] && !seen[genres[j]]) { seen[genres[j]] = true; genreOut.push(genres[j]); }
  }
  var desc = '';
  if (dto.description) { desc = htmlToText(dto.description); }
  var info = [];
  if (dto.rating > 0) { info.push('Rating: ' + dto.rating); }
  if (dto.type) { info.push('Type: ' + dto.type); }
  if (dto.origin) { info.push('Origin: ' + dto.origin); }
  if (dto.isHot) { info.push('Featured'); }
  if (dto.isMature) { info.push('Mature'); }
  if (dto.salePercent > 0) { info.push('Sale: ' + dto.salePercent + '%'); }
  if (info.length > 0) { desc += (desc ? '\\n\\n' : '') + info.join('\\n'); }
  var altTitles = [];
  if (dto.originalTitle) { altTitles.push(String(dto.originalTitle).trim()); }
  var aliases = dto.aliases || [];
  for (var k = 0; k < aliases.length; k++) { altTitles.push(String(aliases[k]).trim()); }
  var altOut = [];
  var seenAlt = {};
  for (var l = 0; l < altTitles.length; l++) {
    var a = altTitles[l];
    if (a && !seenAlt[a] && a.toLowerCase() !== String(dto.title || '').toLowerCase()) {
      seenAlt[a] = true; altOut.push(a);
    }
  }
  if (altOut.length > 0) { desc += (desc ? '\\n\\n' : '') + 'Alternative titles: \\n' + altOut.map(function (x) { return '- ' + x; }).join('\\n'); }
  return {
    key: '/series/comic/' + (dto.slug || ''),
    title: dto.title || '',
    coverUrl: absoluteUrl(dto.coverImage),
    author: (dto.team && dto.team.name) ? dto.team.name : '',
    artist: '',
    description: desc,
    genre: genreOut.join(', '),
    status: statusFrom(dto.status)
  };
}

async function apiSeriesPage(page, sort, query) {
  var url = BASE + '/api/series?sort=' + encodeURIComponent(sort) +
    '&contentMode=comics&page=' + page + '&limit=24';
  if (query) { url += '&q=' + encodeURIComponent(query); }
  var text = await $.http.get(url);
  var data;
  try { data = JSON.parse(text); } catch (e) { data = null; }
  if (!data || !Array.isArray(data.data)) { return { mangas: [], hasNextPage: false }; }
  var out = [];
  for (var i = 0; i < data.data.length; i++) { out.push(mangaFromDto(data.data[i])); }
  return { mangas: out, hasNextPage: !!(data.meta && data.meta.hasMore) };
}

async function fetchDetailRsc(slug, page) {
  var url = BASE + '/series/comic/' + encodeURIComponent(slug) + '?sort=desc';
  if (page && page > 1) { url += '&page=' + page; }
  var text = await $.http.get(url, { rsc: '1' });
  return rscExtract(text, function (o) {
    return o && typeof o === 'object' && !Array.isArray(o) &&
      'series' in o && 'chapters' in o;
  });
}

function parseSlug(mangaKey) {
  var parts = String(mangaKey).split('/').filter(function (p) { return p.length > 0; });
  return parts[parts.length - 1] || '';
}

module.exports = {
  getPopularManga: async function (page) {
    return apiSeriesPage(page, 'popular', '');
  },

  getSearchManga: async function (page, query) {
    return apiSeriesPage(page, '', query || '');
  },

  getMangaDetail: async function (mangaKey) {
    var slug = parseSlug(mangaKey);
    var detail = await fetchDetailRsc(slug, 1);
    if (!detail || !detail.series) { throw new Error('Manga not found: ' + slug); }
    return mangaFromDto(detail.series);
  },

  getChapterList: async function (mangaKey) {
    var slug = parseSlug(mangaKey);
    var detail = await fetchDetailRsc(slug, 1);
    if (!detail || !detail.series) { return []; }
    var all = (detail.chapters || []).slice();
    var totalPages = Number(detail.totalPages) || 1;
    for (var p = 2; p <= totalPages; p++) {
      var next = await fetchDetailRsc(slug, p);
      all = all.concat((next && next.chapters) || []);
    }
    var chapters = [];
    for (var i = 0; i < all.length; i++) {
      var ch = all[i];
      if (CFG.hideLocked && ch.isLocked) { continue; }
      var numStr = numToStr(Number(ch.number));
      var title = ch.title || '';
      var name = (!title || title === numStr) ? 'Chapter ' + numStr : title;
      var ts = ch.publishedAt ? Date.parse(ch.publishedAt) : 0;
      chapters.push({
        key: '/series/comic/' + slug + '/chapter/' + numStr,
        name: name,
        chapterNumber: Number(ch.number) || -1,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0
      });
    }
    // site lists newest first (sort=desc); normalize to oldest-first
    chapters.sort(function (a, b) { return b.chapterNumber - a.chapterNumber; });
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = chapters.length - 1 - j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var parts = String(chapterKey).split('/').filter(function (p) { return p.length > 0; });
    var slug = parts[2] || '';
    var number = parts[4] || '';
    var url = BASE + '/series/comic/' + encodeURIComponent(slug) + '/chapter/' + encodeURIComponent(number);
    var text = await $.http.get(url, { rsc: '1' });
    var dto = rscExtract(text, function (o) {
      return o && typeof o === 'object' && !Array.isArray(o) && 'chapter' in o;
    });
    var pages = (dto && dto.chapter && dto.chapter.pages) || [];
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      var u = pages[i] ? pages[i].imageUrl : null;
      if (u) { out.push({ index: out.length, url: absoluteUrl(u) }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
