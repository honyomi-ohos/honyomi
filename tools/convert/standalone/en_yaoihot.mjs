// en/yaoihot — bespoke WP scraper (manga grid, orderby=views popular, relative chapter dates)
export const runtime = 'wp';

export function extract(ctx) {
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function listUrl(page, query) {
  var q = (query || '').trim();
  if (q) {
    var e = encodeURIComponent(q);
    return page > 1
      ? BASE + '/page/' + page + '/?s=' + e + '&post_type=manga'
      : BASE + '/?s=' + e + '&post_type=manga';
  }
  var u = BASE + '/manga';
  if (page > 1) { u += '/page/' + page; }
  return u + '?orderby=views';
}

function parseList(text) {
  var doc = $.html.parse(text);
  var items = R_sel(doc, '.manga-grid .manga-card');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = R_selFirst(el, '.manga-card-link');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var titleEl = R_selFirst(el, '.manga-card-title');
    var img = R_selFirst(el, '.manga-cover-img');
    out.push({
      key: R_path(href),
      title: titleEl ? titleEl.text() : link.text(),
      coverUrl: img ? R_abs(img.attr('src') || img.attr('data-src') || '') : ''
    });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, '.next.page-numbers') };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(listUrl(page, ''), HDRS));
  },

  getSearchManga: async function (page, query) {
    return parseList(await $.http.get(listUrl(page, query), HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var author = '';
    var aEl = R_selFirst(doc, '.author-line');
    if (aEl) {
      var at = aEl.text().trim();
      var c = at.indexOf(':');
      author = (c >= 0 ? at.substring(c + 1) : at).trim();
    }
    var genres = [];
    var gels = R_sel(doc, '.genre-tag');
    for (var i = 0; i < gels.length; i++) { genres.push(gels[i].text()); }
    return {
      key: mangaKey,
      title: (R_selFirst(doc, '.manga-title') || { text: function () { return ''; } }).text(),
      coverUrl: R_img(R_selFirst(doc, '.manga-cover-img')),
      author: author,
      description: (R_selFirst(doc, '.summary-content') || { text: function () { return ''; } }).text(),
      genre: genres.join(', '),
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var items = R_sel(doc, '.chapters-list .chapter-item');
    var chapters = [];
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      var href = (typeof el.absUrl === 'function') ? el.absUrl('href') : '';
      if (!href) { href = R_abs(el.attr('href') || ''); }
      if (!href) { continue; }
      var dateEl = R_selFirst(el, '.chapter-date');
      chapters.push({
        key: R_path(href),
        name: (R_selFirst(el, '.chapter-title') || el).text(),
        chapterNumber: -1,
        dateUpload: dateEl ? R_date(dateEl.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    chapters.reverse();
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var imgs = R_sel(doc, '.reader-page img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = R_img(imgs[i]);
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
