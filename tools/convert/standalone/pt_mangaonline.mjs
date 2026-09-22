// pt/mangaonline — HTML scraper (mangaonline)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['filters not ported'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone scraper)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};

function parseCards(doc) {
  var out = [];
  var items = R_sel(doc, '.manga-card > a, .latest-manga-card');
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var href = el.absUrl('href');
    if (!href) {
      var inner = R_selFirst(el, 'a');
      href = inner ? inner.absUrl('href') : '';
    }
    if (!href) { continue; }
    var t = R_selFirst(el, 'h3');
    var img = R_selFirst(el, 'img');
    out.push({ key: R_path(href), title: t ? t.text() : el.text(), coverUrl: R_img(img) });
  }
  var hasNext = false;
  var links = R_sel(doc, 'a.public-page-link');
  for (var k = 0; k < links.length; k++) {
    if (links[k].text().indexOf('Proxima') >= 0) { hasNext = true; break; }
  }
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/catalogo?perPage=24&page=' + page + '&sort=popular');
    return parseCards($.html.parse(text));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/catalogo?perPage=24&page=' + page;
    if (query) { u += '&q=' + encodeURIComponent(query); }
    var text = await $.http.get(u);
    return parseCards($.html.parse(text));
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var statusRaw = R_selFirst(doc, '.manga-info-pill-status');
    var s = statusRaw ? statusRaw.text().toLowerCase() : '';
    var status = '';
    if (s === 'em andamento') { status = 'ongoing'; }
    else if (s === 'completo') { status = 'completed'; }
    else if (s === 'hiato') { status = 'hiatus'; }
    else if (s === 'cancelado') { status = 'cancelled'; }
    var genres = [];
    var gels = R_sel(doc, '.tags span');
    for (var g = 0; g < gels.length; g++) { genres.push(gels[g].text()); }
    return {
      key: mangaKey,
      title: R_ownText(R_selFirst(doc, 'h1')) || '',
      coverUrl: '',
      author: '',
      description: R_ownText(R_selFirst(doc, '.synopsis')) || '',
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var rows = R_sel(doc, '.chapter-row');
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var link = R_selFirst(rows[i], '.chapter-main-link');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var name = R_selFirst(rows[i], '.chapter-title-line');
      out.push({
        key: R_path(href),
        name: name ? name.text() : link.text(),
        chapterNumber: -1,
        dateUpload: 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, '.reader-content img');
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src');
      if (u) { out.push({ index: out.length, url: u }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
