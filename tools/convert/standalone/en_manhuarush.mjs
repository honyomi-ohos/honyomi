// en/manhuarush — single-title Next.js site; chapters/pages extracted from RSC flight
// payloads (RSC: 1 header), reusing the minimal flight parser from the lusttoon engine.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'single-title source (one manga listed in Popular); no search/latest upstream',
      'site hosted on vercel.app which is DNS-blocked in the converter region: live probe unavailable, port untested',
    ],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };
var RSC_HDRS = { RSC: '1' };

// ---- minimal Next.js RSC flight parsing ----
function rscRows(text, models) {
  var results = [];
  var lines = String(text).split('\\n');
  for (var i = 0; i < lines.length; i++) {
    var m = /^([0-9a-fA-F]+):(.*)$/.exec(lines[i]);
    if (!m) { continue; }
    var id = m[1], val = m[2];
    if (!val || val[0] === 'T') { continue; }
    if (val[0] !== '{' && val[0] !== '[') { continue; }
    var parsed = null;
    try { parsed = $.json.parse(val); } catch (e) { parsed = null; }
    if (parsed === null) { continue; }
    results.push(parsed);
    if (models) { models[id] = parsed; }
  }
  return results;
}

function resolveRefs(el, models, depth) {
  if (depth > 8) { return el; }
  if (Array.isArray(el)) {
    return el.map(function (x) { return resolveRefs(x, models, depth + 1); });
  }
  if (el && typeof el === 'object') {
    var out = {};
    for (var k in el) { out[k] = resolveRefs(el[k], models, depth + 1); }
    return out;
  }
  if (typeof el === 'string' && el[0] === '$' && el.length >= 2) {
    if (el[1] === '$') { return el.substring(1); }
    if (el === '$undefined') { return null; }
    var ref = el.substring(el[1] === 'D' || el[1] === 'n' || el[1] === 'L' || el[1] === 'Q' || el[1] === 'W' || el[1] === '@' ? 2 : 1);
    var parts = ref.split(':');
    var v = models ? models[parts[0]] : undefined;
    if (v === undefined) { return el; }
    for (var i = 1; i < parts.length && v !== undefined && v !== null; i++) {
      v = v[parts[i]];
    }
    if (v === undefined) { return el; }
    return resolveRefs(v, models, depth + 1);
  }
  return el;
}

function deepFind(el, pred, depth) {
  if (depth > 12 || el === null || el === undefined) { return null; }
  if (Array.isArray(el)) {
    for (var i = 0; i < el.length; i++) {
      var r = deepFind(el[i], pred, depth + 1);
      if (r) { return r; }
    }
    return null;
  }
  if (el && typeof el === 'object') {
    if (pred(el)) { return el; }
    for (var k in el) {
      var r2 = deepFind(el[k], pred, depth + 1);
      if (r2) { return r2; }
    }
  }
  return null;
}

function findInRsc(text, pred) {
  var models = {};
  var rows = rscRows(text, models);
  for (var i = 0; i < rows.length; i++) {
    var resolved = resolveRefs(rows[i], models, 0);
    var found = deepFind(resolved, pred, 0);
    if (found) { return found; }
  }
  return null;
}

module.exports = {
  getPopularManga: async function (page) {
    var doc = $.html.parse(await $.http.get(BASE + '/', HDRS));
    var links = R_sel(doc, 'li a.nav-link');
    var out = [];
    for (var i = 0; i < links.length; i++) {
      if (links[i].attr('href') !== '/ttp-providence') { continue; }
      var title = (R_selFirst(doc, 'footer .footer-tagline strong') || { text: function () { return ''; } }).text();
      var bgEl = R_selFirst(doc, 'div[style*=background-image]');
      var cover = '';
      if (bgEl) {
        var style = bgEl.attr('style') || '';
        var m = /url\\('([^']*)'\\)/.exec(style);
        if (m) { cover = BASE + m[1]; }
      }
      out.push({ key: '/ttp-providence', title: title, coverUrl: cover });
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    return { mangas: [], hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(BASE + mangaKey, HDRS));
    var genres = [];
    var pills = R_sel(doc, '.tag-pill');
    for (var i = 0; i < pills.length; i++) { genres.push(pills[i].text()); }
    return {
      key: mangaKey,
      title: (R_selFirst(doc, 'h1.manga-title') || { text: function () { return ''; } }).text(),
      coverUrl: R_abs((R_selFirst(doc, '.cover img') || { attr: function () { return ''; } }).attr('src')),
      author: '',
      description: (R_selFirst(doc, '.manga-desc p') || { text: function () { return ''; } }).text(),
      genre: genres.join(', '),
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var rscText = await $.http.get(BASE + mangaKey, RSC_HDRS);
    var dto = findInRsc(rscText, function (o) { return 'chapters' in o && 'mangadexId' in o; });
    if (!dto) { throw new Error('Failed to extract chapters'); }
    var chapters = dto.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var nm = 'Chapter ' + c.chapter + (c.title ? ' - ' + c.title : '');
      out.push({
        key: '/reader/' + dto.mangadexId + '/' + c.chapter,
        name: nm,
        chapterNumber: -1,
        dateUpload: c.createdAt ? (Date.parse(c.createdAt) || 0) : 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var rscText = await $.http.get(BASE + chapterKey, RSC_HDRS);
    var dto = findInRsc(rscText, function (o) { return 'imageUrls' in o; });
    if (!dto) { return []; }
    var urls = dto.imageUrls || [];
    var out = [];
    for (var i = 0; i < urls.length; i++) {
      if (urls[i]) { out.push({ index: out.length, url: urls[i] }); }
    }
    return out;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
