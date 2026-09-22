// en/mangapill (mangapill.com) — Jsoup scraper; popular = homepage "Trending" grid.
// The host selector API has no DOM traversal, so the trending grid is isolated by card
// shape: trending/chapter grids share "div.grid > div:not([class])", but trending cards
// have their cover anchor (a.relative) pointing at /manga/ while homepage chapter cards
// point at /chapters/.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['filters (genre/status/type) not ported; text search only'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function itemToManga(el, trendingOnly) {
  var coverLink = R_selFirst(el, 'a.relative');
  var link = R_selFirst(el, "a[href^='/manga/']");
  var titleEl = R_selFirst(el, 'div.line-clamp-2');
  if (!link || !titleEl) { return null; }
  if (trendingOnly) {
    if (!coverLink) { return null; }
    var cu = coverLink.absUrl('href');
    if (!cu || new URL(cu, BASE).pathname.indexOf('/manga/') !== 0) { return null; }
  }
  var href = link.absUrl('href');
  if (!href) { return null; }
  var img = R_selFirst(el, 'img');
  return {
    key: new URL(href, BASE).pathname + new URL(href, BASE).search,
    title: titleEl.text(),
    coverUrl: img ? (img.attr('data-src') || '') : ''
  };
}

function parseGrid(text, trendingOnly) {
  var doc = $.html.parse(text);
  var els = R_sel(doc, 'div.grid > div:not([class])');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var m = itemToManga(els[i], trendingOnly);
    if (m) { out.push(m); }
  }
  return { doc: doc, mangas: out };
}

module.exports = {
  getPopularManga: async function (page) {
    var r = parseGrid(await $.http.get(BASE + '/', HDRS), true);
    return { mangas: r.mangas, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/search?page=' + page + '&q=' + encodeURIComponent(query || ''), HDRS);
    var r = parseGrid(text, false);
    var hasNext = !!R_selFirst(r.doc, 'a.btn.btn-sm');
    return { mangas: r.mangas, hasNextPage: hasNext };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var genres = [];
    var gels = R_sel(doc, 'a[href*=genre]');
    for (var i = 0; i < gels.length; i++) {
      var t = gels[i].text();
      if (t) { genres.push(t); }
    }
    var statusEl = R_selFirst(doc, 'div.container > div:first-child > div:last-child > div:nth-child(3) > div:nth-child(2) > div');
    var descEl = R_selFirst(doc, 'div.container > div:first-child > div:last-child > div:nth-child(2) > p');
    var coverEl = R_selFirst(doc, 'div.container > div:first-child > div:first-child > img');
    var st = String(statusEl ? statusEl.text() : '').toLowerCase();
    return {
      key: mangaKey,
      title: '',
      coverUrl: coverEl ? (coverEl.attr('data-src') || '') : '',
      author: '',
      artist: '',
      description: descEl ? descEl.text() : '',
      genre: genres.join(', '),
      status: st.indexOf('publishing') >= 0 ? 'ongoing' : (st.indexOf('finished') >= 0 ? 'completed' : '')
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var els = R_sel(doc, '#chapters > div > a');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var href = els[i].absUrl('href');
      if (!href) { continue; }
      var u = new URL(href, BASE);
      out.push({
        key: u.pathname + u.search,
        name: els[i].text(),
        chapterNumber: -1,
        dateUpload: 0,
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
    var els = R_sel(doc, 'picture img');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var src = els[i].attr('data-src');
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
