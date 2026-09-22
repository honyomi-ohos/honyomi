// en/mangayi — JSON search API (POST /api/search) + Jsoup detail pages
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['covers served from scp.keterfoundation.com per upstream (may 404)'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { 'Content-Type': 'application/json', Referer: BASE + '/' };
var pageSize = 24;

function statusMap(s) {
  var v = String(s || '').toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  if (v === 'hiatus' || v === 'on hiatus') { return 'on hiatus'; }
  if (v === 'cancelled') { return 'cancelled'; }
  return '';
}

async function fetchMangasPage(payload, page) {
  var res = $.json.parse(await $.http.post(BASE + '/api/search', $.json.stringify(payload), HDRS));
  var results = res.results || [];
  if (results.length > pageSize) { pageSize = results.length; }
  var mangas = [];
  for (var i = 0; i < results.length; i++) {
    var r = results[i];
    mangas.push({
      key: '/read/' + r.i + '/',
      title: r.t || '',
      coverUrl: 'https://scp.keterfoundation.com/cover/' + r.i + '.jpg'
    });
  }
  return { mangas: mangas, hasNextPage: page * pageSize < (res.total || 0) };
}

module.exports = {
  getPopularManga: async function (page) {
    return fetchMangasPage({ p: page, t: 1 }, page);
  },

  getSearchManga: async function (page, query) {
    return fetchMangasPage({ p: page, s: query || '' }, page);
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    // .m-stat:contains(Status) .value — :contains unsupported; scan .m-stat blocks
    var status = '';
    var stats = R_sel(doc, '.m-stat');
    for (var i = 0; i < stats.length; i++) {
      if ((stats[i].text() || '').indexOf('Status') >= 0) {
        var val = R_selFirst(stats[i], '.value');
        if (val) { status = statusMap(val.text()); }
        break;
      }
    }
    var genres = [];
    var pills = R_sel(doc, '.m-genres .pill');
    for (var g = 0; g < pills.length; g++) { genres.push(pills[g].text()); }
    var descParts = [];
    var ps = R_sel(doc, '.m-summary p');
    for (var p = 0; p < ps.length; p++) { descParts.push(ps[p].text()); }
    return {
      key: mangaKey,
      title: (R_selFirst(doc, 'h1.m-title') || { text: function () { return ''; } }).text(),
      coverUrl: R_abs((R_selFirst(doc, '.cover-wrap img.cover-image') || { attr: function () { return ''; } }).attr('src')),
      author: (R_selFirst(doc, '.m-authors') || { text: function () { return ''; } }).text(),
      description: descParts.join('\\n'),
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var els = R_sel(doc, 'div.chapters-list a.c');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if ((el.attr('class') || '').indexOf('unreleased') >= 0) { continue; }
      var href = el.absUrl('href');
      if (!href) { continue; }
      var tEl = R_selFirst(el, '.t');
      var dEl = R_selFirst(el, '.chapter-d');
      out.push({
        key: R_path(href),
        name: tEl ? tEl.text() : '',
        chapterNumber: -1,
        dateUpload: dEl ? (R_date(dEl.text()) || 0) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var els = R_sel(doc, 'div.c-images img');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var src = els[i].absUrl('src');
      if (src) { out.push({ index: out.length, url: src }); }
    }
    return out;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
