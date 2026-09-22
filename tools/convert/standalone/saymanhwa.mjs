// all/saymanhwa — bespoke scraper engine (multi-lang ext collapsed to en)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['multi-language ext (12 langs) collapsed to single plugin using English site paths'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone scraper)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var LANG = 'en';

async function parseMangaPage(url) {
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var items = R_sel(doc, 'article.series-card');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var link = R_selFirst(items[i], '.series-card-body h2 a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(items[i], '.series-card-cover img, a img');
    out.push({ key: R_path(href), title: link.text(), coverUrl: img ? img.absUrl('src') : '' });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, 'nav.pagination span + a') };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseMangaPage(BASE + '/' + LANG + '/popular' + (page > 1 ? '?page=' + page : ''));
  },

  getSearchManga: async function (page, query) {
    var url = BASE + '/' + LANG + '/series';
    var params = [];
    if (query && query.trim()) { params.push('q=' + encodeURIComponent(query.trim())); }
    if (page > 1) { params.push('page=' + page); }
    if (params.length) { url += '?' + params.join('&'); }
    return parseMangaPage(url);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var h1 = R_selFirst(doc, 'h1');
    var coverEl = R_selFirst(doc, '.series-v72-cover img');
    var creatorRows = R_sel(doc, '.series-v72-meta-row strong.series-creator-links');
    function joinLinks(row) {
      if (!row) { return ''; }
      var as = R_sel(row, 'a');
      var parts = [];
      for (var i = 0; i < as.length; i++) { parts.push(as[i].text()); }
      return parts.join(', ');
    }
    var author = joinLinks(creatorRows[0]);
    var artist = joinLinks(creatorRows[1]);
    var statusEl = R_selFirst(doc, '.series-v72-meta-pair > div:first-child strong');
    var status = statusEl ? R_status(R_ownText(statusEl)) : '';
    var typeEl = R_selFirst(doc, '.series-v72-meta-pair > div:nth-child(2) strong');
    var genres = [];
    var type = typeEl ? R_ownText(typeEl) : '';
    if (type) { genres.push(type); }
    var genreLinks = R_sel(doc, "a[href*='/genres/']");
    for (var g = 0; g < genreLinks.length; g++) {
      var t = genreLinks[g].text();
      if (t && genres.indexOf(t) < 0) { genres.push(t); }
    }
    var descEl = R_selFirst(doc, '.series-seo-context p');
    return {
      key: mangaKey,
      title: h1 ? R_ownText(h1) : '',
      coverUrl: coverEl ? coverEl.absUrl('src') : '',
      author: author,
      artist: artist,
      description: descEl ? descEl.text() : '',
      genre: genres.join(', '),
      status: status,
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var rows = R_sel(doc, '.series-v72-chapter-list > a.series-v72-chapter-row');
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var el = rows[i];
      var href = el.absUrl('href');
      if (!href) { continue; }
      var nameEl = R_selFirst(el, '.series-chapter-number-text');
      var name = nameEl ? R_ownText(nameEl) : '';
      if (R_selFirst(el, '.chapter-mini-lock')) { name = '\\uD83D\\uDD12 ' + name; }
      var timeEl = R_selFirst(el, 'time');
      var dt = timeEl ? timeEl.attr('datetime') : '';
      var ts = dt ? Date.parse(dt) : 0;
      out.push({
        key: R_path(href),
        name: name,
        chapterNumber: -1,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0,
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, '.reader-pages img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
