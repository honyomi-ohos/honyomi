// Hwalumi theme engine (id: hwago, lumoskomik) — Laravel-ish reader with base64 synopsis
export const runtime = 'wp';

export function extract(ctx) {
  const warnings = [];
  const config = {};
  warnings.push('browse filters (status/type/genre) not supported by host; text search only');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: hwalumi)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function mangaSlug(href) {
  var path = String(href || '');
  path = path.split('?')[0].split('#')[0];
  var segs = path.split('/');
  for (var i = segs.length - 1; i >= 0; i--) {
    if (segs[i]) { return segs[i]; }
  }
  return '';
}

function decodeB64(encoded) {
  var value = String(encoded || '').trim();
  var rem = value.length % 4;
  if (rem !== 0) { value += '='.repeat(4 - rem); }
  try { return atob(value).trim(); } catch (e) { return ''; }
}

function parseRelativeDate(s) {
  var t = String(s || '').toLowerCase().trim();
  if (!t) { return 0; }
  if (t === 'baru saja') { return Math.floor(Date.now() / 1000); }
  var m = /\\d+/.exec(t);
  if (!m) { return 0; }
  var n = parseInt(m[0], 10);
  var now = Math.floor(Date.now() / 1000);
  if (t.indexOf('detik') >= 0) { return now - n; }
  if (t.indexOf('menit') >= 0) { return now - n * 60; }
  if (t.indexOf('jam') >= 0) { return now - n * 3600; }
  if (t.indexOf('hari') >= 0) { return now - n * 86400; }
  if (t.indexOf('minggu') >= 0) { return now - n * 7 * 86400; }
  if (t.indexOf('bulan') >= 0) { return now - n * 30 * 86400; }
  if (t.indexOf('tahun') >= 0) { return now - n * 365 * 86400; }
  return 0;
}

function parseList(doc, page) {
  var links = R_sel(doc, 'a[href*="/comic/"]');
  var seen = {};
  var mangas = [];
  for (var i = 0; i < links.length; i++) {
    var el = links[i];
    var img = R_selFirst(el, 'img');
    if (!img) { continue; }
    var src = img.attr('src') || '';
    if (src.indexOf('flagcdn') >= 0) { continue; }
    var title = (img.attr('alt') || '').trim() || el.text().trim();
    if (!title) { continue; }
    var key = '/comic/' + mangaSlug(el.absUrl('href') || el.attr('href'));
    if (seen[key]) { continue; }
    seen[key] = true;
    mangas.push({
      key: key,
      title: title,
      coverUrl: img.absUrl('src') || src
    });
  }
  var hasNextPage = R_sel(doc, 'a[href*="page=' + (page + 1) + '"]').length > 0;
  return { mangas: mangas, hasNextPage: hasNextPage };
}

function infoValue(doc, tag, label) {
  var els = R_sel(doc, tag);
  for (var i = 0; i < els.length; i++) {
    if (els[i].text().trim().toLowerCase() === label) {
      var v = R_selFirst(els[i], ':scope + ' + tag);
      return v ? v.text().trim() : '';
    }
  }
  return '';
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/all-series?sort=popular&lang=id&page=' + page);
    return parseList($.html.parse(text), page);
  },

  getSearchManga: async function (page, query) {
    var url = BASE + '/browse?sort=latest&lang=id&page=' + page;
    if (query) { url += '&q=' + encodeURIComponent(query); }
    var text = await $.http.get(url);
    return parseList($.html.parse(text), page);
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/comic\\//, '').replace(/^\\/+/, '');
    var text = await $.http.get(BASE + '/comic/' + slug);
    var doc = $.html.parse(text);
    var titleEl = R_selFirst(doc, 'h1');
    var coverEl = R_selFirst(doc, 'aside img[src*="/cover"]');
    var desc = '';
    var srEl = R_selFirst(doc, 'div[data-sr]');
    if (srEl && srEl.attr('data-sr')) {
      desc = decodeB64(srEl.attr('data-sr'));
    }
    if (!desc) {
      var pEl = R_selFirst(doc, 'p.text-sm');
      if (pEl) { desc = pEl.text().trim(); }
    }
    var author = infoValue(doc, 'span', 'author');
    var artist = infoValue(doc, 'span', 'artist');
    if (author && author.toLowerCase() === 'updating') { author = ''; }
    if (artist && artist.toLowerCase() === 'updating') { artist = ''; }
    var statusText = infoValue(doc, 'div', 'status').toLowerCase();
    var status = 'UNKNOWN';
    if (statusText === 'completed' || statusText === 'tamat') { status = 'COMPLETED'; }
    else if (statusText === 'ongoing' || statusText === 'berjalan') { status = 'ONGOING'; }
    else if (statusText === 'hiatus') { status = 'ON_HIATUS'; }
    var gas = R_sel(doc, 'a[href*="genre="]');
    var genres = [];
    for (var g = 0; g < gas.length; g++) {
      var gt = gas[g].text().trim();
      if (gt && genres.indexOf(gt) < 0) { genres.push(gt); }
    }
    return {
      key: mangaKey,
      title: titleEl ? titleEl.text().trim() : '',
      coverUrl: coverEl ? (coverEl.absUrl('src') || coverEl.attr('src') || '') : '',
      author: author,
      artist: artist,
      description: desc,
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/comic\\//, '').replace(/^\\/+/, '');
    var text = await $.http.get(BASE + '/comic/' + slug);
    var doc = $.html.parse(text);
    var anchors = R_sel(doc, 'a[href*="/read/"][data-chapter]');
    var chapters = [];
    for (var i = 0; i < anchors.length; i++) {
      var a = anchors[i];
      var key = R_path(a.absUrl('href') || a.attr('href'));
      if (!key) { continue; }
      var nameEl = R_selFirst(a, 'span.text-sm, span[class*="font-semibold"]');
      var dateEl = R_selFirst(a, 'span.tabular-nums, span[class*="tabular-nums"]');
      chapters.push({
        key: key,
        name: nameEl ? nameEl.text().trim() : a.text().trim(),
        dateUpload: parseRelativeDate(dateEl ? dateEl.text() : '')
      });
    }
    // site lists newest first; host expects oldest first
    chapters.reverse();
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(BASE + chapterKey);
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, 'img[alt^="Page "]');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].absUrl('src') || imgs[i].attr('src') || '';
      if (src && src.indexOf('/api/image/p/') < 0) { pages.push(src); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { 'Referer': BASE + '/' };
  }
};
`;
}
