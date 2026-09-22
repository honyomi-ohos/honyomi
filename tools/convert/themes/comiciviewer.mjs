// ComiciViewer theme engine (Japanese ComiciViewer Next.js sites)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  apiPath: '/api',
  rankingPath: '/ranking/manga',
  listPath: '/series/list/up',
  searchPageSize: 24,
  rankingClass: 'series-list mode-ranking',
  itemSelector: 'div.series-list-item',
  itemLinkSelector: 'a.series-list-item-link',
  itemTitleSelector: 'div.series-list-item-h span[data-e2e=sliTitle]',
  itemImgSelector: 'img.series-list-item-img',
  pagerNextSelector: 'a.g-pager-link.mode-active + a.g-pager-link',
};

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  // `override val apiUrl get() = "..."` (default: "$baseUrl/api")
  const am = kt.match(/override\s+val\s+apiUrl\s*(?:get\s*\(\)\s*)?=\s*"([^"]*)"/);
  if (am && am[1] !== '$baseUrl/api') {
    const raw = am[1].replace('$baseUrl', '');
    if (/^\/[\w/-]*$/.test(raw)) {
      config.apiPath = raw;
      warnings.push(`custom apiUrl path: ${raw}`);
    } else {
      warnings.push('custom apiUrl not portable; using /api');
    }
  }

  if (/extraFilterOptions\s*=/.test(kt)) {
    warnings.push('extra filter options not portable; category filters unsupported');
  }
  warnings.push('site serves tile-scrambled (4x4) page images; without app-side descrambling some pages may appear scrambled');

  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  const base = manifest.baseUrl.replace(/\/+$/, '');
  return String.raw`// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: comiciviewer)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_sel/R_selFirst)
var BASE = ${JSON.stringify(base)};
var CFG = ${cfg};

// ---------------- comiciviewer engine ----------------

function httpGet(url, headers) {
  return $.http.get(url, headers);
}

function hashOfKey(key) {
  var s = String(key || '');
  var i = s.indexOf('/series/');
  if (i >= 0) { s = s.substring(i + 8); }
  var j = s.indexOf('/');
  if (j >= 0) { s = s.substring(0, j); }
  return s.split('?')[0];
}

function hashFromUrl(u) {
  try {
    var url = new URL(u, BASE);
    var segs = url.pathname.split('/');
    var idx = -1;
    for (var i = 0; i < segs.length; i++) { if (segs[i] === 'series') { idx = i; break; } }
    if (idx >= 0 && idx + 1 < segs.length) { return segs[idx + 1]; }
  } catch (e) { /* ignore */ }
  return '';
}

// ---- Next.js RSC flight payload parsing (ranking) ----

function flightRows(text) {
  var rows = {};
  var lines = String(text).split('\n');
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^([0-9a-f]+):([\s\S]*)$/);
    if (m) {
      try { rows[m[1]] = $.json.parse(m[2]); } catch (e) { /* skip */ }
    }
  }
  return rows;
}

function flightResolve(v, rows, depth) {
  if (depth > 16) { return v; }
  if (typeof v === 'string' && v.length > 1 && v.charAt(0) === '$') {
    var id = v.substring(1);
    if (rows[id] !== undefined) { return flightResolve(rows[id], rows, depth + 1); }
  }
  return v;
}

function flightFind(v, pred, rows, depth) {
  if (depth > 24 || v === null || v === undefined) { return null; }
  v = flightResolve(v, rows, 0);
  if (Array.isArray(v)) {
    for (var i = 0; i < v.length; i++) {
      var r = flightFind(v[i], pred, rows, depth + 1);
      if (r) { return r; }
    }
    return null;
  }
  if (typeof v === 'object') {
    if (pred(v)) { return v; }
    for (var k in v) {
      var r2 = flightFind(v[k], pred, rows, depth + 1);
      if (r2) { return r2; }
    }
  }
  return null;
}

function flightFindImg(v, rows, depth) {
  if (depth > 24 || v === null || v === undefined) { return null; }
  if (typeof v === 'string') {
    var r = flightResolve(v, rows, 0);
    return r === v ? null : flightFindImg(r, rows, depth + 1);
  }
  if (Array.isArray(v)) {
    for (var i = 0; i < v.length; i++) {
      var f = flightFindImg(v[i], rows, depth + 1);
      if (f) { return f; }
    }
    return null;
  }
  if (typeof v === 'object') {
    if (v.src !== undefined) { return v; }
    for (var k in v) {
      var f2 = flightFindImg(v[k], rows, depth + 1);
      if (f2) { return f2; }
    }
  }
  return null;
}

function thumbFromImg(img) {
  if (!img) { return ''; }
  if (img.srcSet) {
    var parts = String(img.srcSet).split(', ');
    var u = parts[parts.length - 1].split(' ')[0];
    if (u) { return u; }
  }
  return img.src || '';
}

function isItemTuple(t) {
  return Array.isArray(t) && t.length >= 4 && t[0] === '$' && t[1] === 'div' &&
    typeof t[2] === 'string' && /^[0-9a-f]+$/.test(t[2]) &&
    t[3] !== null && typeof t[3] === 'object' && !Array.isArray(t[3]) &&
    String(t[3].className || '').indexOf('series-list-item') === 0;
}

function flightFindTitle(v, rows, depth) {
  if (depth > 24 || v === null || v === undefined) { return ''; }
  v = flightResolve(v, rows, 0);
  if (Array.isArray(v)) {
    for (var i = 0; i < v.length; i++) {
      var t = flightFindTitle(v[i], rows, depth + 1);
      if (t) { return t; }
    }
    return '';
  }
  if (typeof v === 'object') {
    if (v['data-e2e'] === 'sliTitle') {
      var c = flightResolve(v.children, rows, 0);
      if (typeof c === 'string') { return c; }
      if (Array.isArray(c)) {
        var s = '';
        for (var q = 0; q < c.length; q++) {
          var cq = flightResolve(c[q], rows, 0);
          if (typeof cq === 'string') { s += cq; }
        }
        if (s) { return s; }
      }
    }
    for (var k in v) {
      var t2 = flightFindTitle(v[k], rows, depth + 1);
      if (t2) { return t2; }
    }
  }
  return '';
}

function rankingFromFlight(text) {
  var rows = flightRows(text);
  var tuples = [];
  var seen = {};
  var obj = flightFind(rows, function (o) { return o.className === CFG.rankingClass; }, rows, 0);
  if (obj && obj.children) {
    for (var i = 0; i < obj.children.length; i++) {
      var tuple = flightResolve(obj.children[i], rows, 0);
      if (isItemTuple(tuple) && !seen[tuple[2]]) { seen[tuple[2]] = 1; tuples.push(tuple); }
    }
  }
  // streamed rows: standalone item tuples on their own flight lines
  var lines = String(text).split('\n');
  for (var L = 0; L < lines.length; L++) {
    var m = lines[L].match(/^([0-9a-f]+):([\s\S]*)$/);
    if (!m) { continue; }
    var val;
    try { val = $.json.parse(m[2]); } catch (e) { continue; }
    if (isItemTuple(val) && !seen[val[2]]) { seen[val[2]] = 1; tuples.push(val); }
  }
  var out = [];
  for (var j = 0; j < tuples.length; j++) {
    var img = flightFindImg(tuples[j], rows, 0);
    out.push({
      key: '/series/' + tuples[j][2],
      title: flightFindTitle(tuples[j], rows, 0) || (img && img.alt) || '',
      coverUrl: R_abs(thumbFromImg(img))
    });
  }
  return out;
}

// ---- HTML list pages (latest / fallback) ----

function htmlToPage(text) {
  var doc = $.html.parse(text);
  var items = R_sel(doc, CFG.itemSelector);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var link = R_selFirst(items[i], CFG.itemLinkSelector);
    if (!link) { continue; }
    var hash = hashFromUrl(link.absUrl('href') || link.attr('href'));
    if (!hash) { continue; }
    var tEl = R_selFirst(items[i], CFG.itemTitleSelector);
    var img = R_selFirst(items[i], CFG.itemImgSelector);
    out.push({
      key: '/series/' + hash,
      title: tEl ? tEl.text() : '',
      coverUrl: img ? (img.absUrl('src') || img.attr('src')) : ''
    });
  }
  var hasNext = !!R_selFirst(doc, CFG.pagerNextSelector);
  return { mangas: out, hasNextPage: hasNext };
}

async function listPage(page) {
  var text = await httpGet(BASE + CFG.listPath + '/' + page);
  return htmlToPage(text);
}

// ---- API ----

async function fetchSeries(hash) {
  var url = BASE + CFG.apiPath + '/episodes?seriesHash=' + encodeURIComponent(hash) + '&episodeFrom=1&episodeTo=9999';
  var j = $.json.parse(await httpGet(url));
  return (j && j.series) || null;
}

function summaryToManga(s) {
  return {
    key: '/series/' + (s.id || ''),
    title: s.name || '',
    coverUrl: (s.images && s.images[0] && s.images[0].url) || ''
  };
}

function resolveDescText(node) {
  if (node.text !== null && node.text !== undefined) { return String(node.text); }
  if (node.children) {
    var inner = '';
    for (var i = 0; i < node.children.length; i++) { inner += resolveDescText(node.children[i]); }
    return node.url ? '[' + inner + '](' + node.url + ')' : inner;
  }
  return '';
}

function parseDescription(d) {
  if (!d) { return ''; }
  try {
    var nodes = $.json.parse(d);
    if (!Array.isArray(nodes)) { return String(d); }
    var lines = [];
    for (var i = 0; i < nodes.length; i++) {
      var children = (nodes[i] && nodes[i].children) || [];
      var line = '';
      for (var j = 0; j < children.length; j++) { line += resolveDescText(children[j]); }
      lines.push(line);
    }
    return lines.join('\n');
  } catch (e) {
    return String(d);
  }
}

function summaryToDetail(s, key) {
  var authors = [];
  var arr = s.author || [];
  for (var i = 0; i < arr.length; i++) { if (arr[i] && arr[i].name) { authors.push(arr[i].name); } }
  var genres = [];
  var tags = s.tag || [];
  for (var j = 0; j < tags.length; j++) { if (tags[j] && tags[j].name) { genres.push(tags[j].name); } }
  return {
    key: key,
    title: s.name || '',
    coverUrl: (s.images && s.images[0] && s.images[0].url) || '',
    author: authors.join(', '),
    description: parseDescription(s.description),
    genre: genres.join(', '),
    status: s.isCompleted === true ? 'completed' : 'ongoing'
  };
}

module.exports = {
  getPopularManga: async function (page) {
    try {
      var text = await httpGet(BASE + CFG.rankingPath, { rsc: '1' });
      var items = rankingFromFlight(text);
      if (items.length > 0) { return { mangas: items, hasNextPage: false }; }
    } catch (e) { /* fall through */ }
    return listPage(1);
  },

  getSearchManga: async function (page, query) {
    if (query) {
      var url = BASE + CFG.apiPath + '/search?q=' + encodeURIComponent(query) + '&page=' + page + '&size=' + CFG.searchPageSize;
      var j = $.json.parse(await httpGet(url));
      var result = (j && j.searchResult && j.searchResult.series) || { total: 0, series: [] };
      var mangas = [];
      var list = result.series || [];
      for (var i = 0; i < list.length; i++) { mangas.push(summaryToManga(list[i])); }
      return { mangas: mangas, hasNextPage: (result.total || 0) > page * CFG.searchPageSize };
    }
    return listPage(page);
  },

  getMangaDetail: async function (mangaKey) {
    var hash = hashOfKey(mangaKey);
    var series = await fetchSeries(hash);
    var s = (series && series.summary) || {};
    return summaryToDetail(s, '/series/' + hash);
  },

  getChapterList: async function (mangaKey) {
    var hash = hashOfKey(mangaKey);
    var series = await fetchSeries(hash);
    var episodes = (series && series.episodes) || [];
    var accesses = {};
    try {
      var at = BASE + CFG.apiPath + '/series/access?seriesHash=' + encodeURIComponent(hash);
      var aj = $.json.parse(await httpGet(at));
      var list = (aj.seriesAccess && aj.seriesAccess.episodeAccesses) || [];
      for (var i = 0; i < list.length; i++) { accesses[list[i].episodeId] = list[i]; }
    } catch (e) { /* optional */ }
    var out = [];
    for (var j = 0; j < episodes.length; j++) {
      var ep = episodes[j];
      var access = accesses[ep.id];
      var lock = '';
      if (access && access.hasAccess === false) {
        lock = access.accessType === 'memberOnlyFree' ? '[login] ' : '[locked] ';
      }
      out.push({
        key: '/episodes/' + ep.id,
        name: lock + (ep.title || ''),
        chapterNumber: -1,
        dateUpload: ep.datePublished ? ep.datePublished * 1000 : 0,
        pages: 0,
        sortOrder: j
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var key = String(chapterKey || '');
    var idx = key.indexOf('/episodes/');
    var id = idx >= 0 ? key.substring(idx + 10) : key;
    id = id.split('?')[0];
    var j = $.json.parse(await httpGet(BASE + CFG.apiPath + '/episodes/' + encodeURIComponent(id)));
    var ep = (j && j.episode) || {};
    var content = ep.content || [];
    var viewer = null;
    for (var i = 0; i < content.length; i++) {
      if (content[i].type === 'viewer' && content[i].viewerId) { viewer = content[i]; break; }
    }
    if (!viewer) {
      var urls = [];
      for (var k = 0; k < content.length; k++) {
        if (content[k].type === 'image' && content[k].url) { urls.push(content[k].url); }
      }
      if (urls.length === 0) { throw new Error('Log in via WebView and purchase this chapter to read.'); }
      var pages = [];
      for (var m = 0; m < urls.length; m++) { pages.push({ index: m, url: urls[m] }); }
      return pages;
    }
    var userId = '';
    try {
      var uj = $.json.parse(await httpGet(BASE + CFG.apiPath + '/user/info'));
      if (uj.user && uj.user.id) { userId = uj.user.id; }
    } catch (e2) { /* anonymous */ }
    var ci = BASE + CFG.apiPath + '/book/contentsInfo?comici-viewer-id=' + encodeURIComponent(viewer.viewerId) +
      '&contentId=' + encodeURIComponent(String(ep.contentId !== null && ep.contentId !== undefined ? ep.contentId : '')) +
      '&user-id=' + encodeURIComponent(userId) + '&page-from=0';
    var j1 = $.json.parse(await httpGet(ci + '&page-to=0'));
    var total = j1.totalPages || 0;
    var j2 = $.json.parse(await httpGet(ci + '&page-to=' + total));
    var result = (j2 && j2.result) || [];
    var out = [];
    for (var n = 0; n < result.length; n++) {
      var p = result[n];
      out.push({ index: p.sort !== null && p.sort !== undefined ? p.sort : n, url: p.imageUrl + '#scramble=' + (p.scramble || '') });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
