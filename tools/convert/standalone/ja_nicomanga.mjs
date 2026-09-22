// ja/nicomanga — NicoManga — HTML lists + XOR-obfuscated RSC payload (key "NicoMangaX2")
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return { ok: true, config: {}, warnings: ['author-fallback search and genre filters not supported'] };
}

export function generate(manifest) {
  const body = String.raw`
var PAYLOAD_KEY = 'NicoMangaX2';

function utf8Decode(bytes) {
  var out = '';
  var i = 0;
  while (i < bytes.length) {
    var b = bytes[i];
    var cp;
    if (b < 0x80) { cp = b; i += 1; }
    else if (b < 0xE0) { cp = ((b & 31) << 6) | (bytes[i + 1] & 63); i += 2; }
    else if (b < 0xF0) { cp = ((b & 15) << 12) | ((bytes[i + 1] & 63) << 6) | (bytes[i + 2] & 63); i += 3; }
    else { cp = ((b & 7) << 18) | ((bytes[i + 1] & 63) << 12) | ((bytes[i + 2] & 63) << 6) | (bytes[i + 3] & 63); i += 4; }
    out += String.fromCodePoint(cp);
  }
  return out;
}

function findJsonObjectEnd(text) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    var c = text.charAt(i);
    if (inString) {
      if (escaped) { escaped = false; }
      else if (c === '\\') { escaped = true; }
      else if (c === '"') { inString = false; }
      continue;
    }
    if (c === '"') { inString = true; }
    else if (c === '{') { depth++; }
    else if (c === '}') {
      depth--;
      if (depth === 0) { return i + 1; }
    }
  }
  return -1;
}

function decodePayload(body) {
  var marker = /([0-9a-z]+):T[0-9a-f]+,"/g;
  var m;
  while ((m = marker.exec(body)) !== null) {
    var after = m.index + m[0].length;
    var windowEnd = Math.min(body.length, after + 600);
    var start = after;
    var found = false;
    while (start < windowEnd) {
      if (body.charCodeAt(start) >= 0x3000) { found = true; break; }
      start++;
    }
    if (!found) { continue; }
    var end = body.indexOf('</script>', start);
    if (end === -1) { continue; }
    var encoded = body.substring(start, end);
    var key = PAYLOAD_KEY;
    var bytes = new Array(encoded.length);
    for (var i = 0; i < encoded.length; i++) {
      bytes[i] = ((encoded.charCodeAt(i) - 19968) ^ key.charCodeAt(i % key.length)) & 0xFF;
    }
    var decoded = utf8Decode(bytes);
    if (decoded.replace(/^\s+/, '').charAt(0) !== '{') { continue; }
    var jsonEnd = findJsonObjectEnd(decoded);
    if (jsonEnd < 0) { continue; }
    try {
      var payload = $.json.parse(decoded.substring(0, jsonEnd));
      if (payload && payload.manga) { return payload; }
    } catch (e) { /* next match */ }
  }
  throw new Error('Encoded site payload not found');
}

function htmlToText(html) {
  return String(html || '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div)>/gi, '\n\n')
    .replace(/<[^>]*>/g, '')
    .split('\n').map(function (l) { return l.trim(); }).join('\n')
    .replace(/\n{3,}/g, '\n\n').trim();
}

async function fetchMangaListPage(url) {
  var doc = await H_doc(url);
  var out = [];
  var items = R_sel(doc, '.manga-grid .manga-card');
  for (var i = 0; i < items.length; i++) {
    var titleEl = R_selFirst(items[i], '.manga-title');
    if (!titleEl) { continue; }
    var href = titleEl.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(items[i], 'img.manga-img');
    var cover = '';
    if (img) { cover = img.attr('data-src') || img.attr('src'); }
    out.push({ key: R_path(href), title: titleEl.text(), coverUrl: R_abs(cover) });
  }
  return { mangas: out, hasNextPage: R_sel(doc, '.custom-pagination .page-link.next:not(.disabled)').length > 0 };
}

function parseRelativeDate(text) {
  var m = String(text || '').trim().match(/(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago/);
  if (!m) { return 0; }
  var amount = parseInt(m[1], 10);
  var units = { second: 1, minute: 60, hour: 3600, day: 86400, week: 604800, month: 2629746, year: 31556952 };
  return Date.now() - amount * units[m[2]] * 1000;
}

module.exports = {
  getPopularManga: function (page) {
    return fetchMangaListPage(BASE + '/manga-list.html?p=' + page + '&pr=popular');
  },

  getSearchManga: function (page, query) {
    return fetchMangaListPage(BASE + '/manga-list.html?p=' + page + '&n=' + encodeURIComponent(query));
  },

  getMangaDetail: async function (mangaKey) {
    var payload = decodePayload(await H_get(R_abs(mangaKey)));
    var m = payload.manga;
    var desc = htmlToText(m.description);
    if (desc.toLowerCase() === 'updating') { desc = ''; }
    if (m.other_name) { desc = desc ? desc + '\n\n' + m.other_name : m.other_name; }
    var status = '';
    var st = (m.status_text || '').toLowerCase();
    if (st === 'on going' || st === 'ongoing') { status = 'ongoing'; }
    else if (st === 'completed') { status = 'completed'; }
    return {
      key: mangaKey,
      title: m.n,
      coverUrl: R_abs(m.c || ''),
      author: (m.authors_list || []).map(function (a) { return a.n; }).join(', '),
      description: desc,
      genre: (m.genres_list || []).map(function (g) { return g.n; }).join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var payload = decodePayload(await H_get(R_abs(mangaKey)));
    var list = payload.chapters_list || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var href = c.ur || '';
      if (!href) { continue; }
      out.push({
        key: R_path(R_abs(href)),
        name: (c.n && c.n.trim()) ? c.n : ('Chapter ' + (c.chapter || '')),
        chapterNumber: -1,
        dateUpload: parseRelativeDate(c.t),
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var payload = decodePayload(await H_get(R_abs(chapterKey)));
    var images = payload.images || [];
    var out = [];
    for (var i = 0; i < images.length; i++) {
      out.push({ index: out.length, url: R_abs(images[i]) });
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
