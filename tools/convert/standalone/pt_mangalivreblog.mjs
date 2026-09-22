// pt/mangalivreblog — WordPress + admin-ajax (mangalivre.blog)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['popular list via admin-ajax with scraped nonce; filters not ported'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone WP scraper)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/', 'X-Requested-With': 'XMLHttpRequest' };

var cachedNonce = null;

async function getNonce() {
  if (cachedNonce) { return cachedNonce; }
  var text = await $.http.get(BASE + '/', { Referer: BASE + '/' });
  var doc = $.html.parse(text);
  var scripts = R_sel(doc, 'script');
  for (var i = 0; i < scripts.length; i++) {
    var html = scripts[i].html();
    if (html.indexOf('slimeReadPopular') >= 0) {
      var m = html.match(/"nonce":"([^"]+)"/);
      if (m) { cachedNonce = m[1]; return cachedNonce; }
    }
  }
  throw new Error('failed to extract nonce from home page');
}

function cleanThumb(u) { return String(u || '').replace('-150x150', ''); }

function parseLatest(text) {
  var doc = $.html.parse(text);
  var out = [];
  var items = R_sel(doc, 'section.latest-section .manga-card-modern');
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = R_selFirst(el, 'a.manga-cover-link') || R_selFirst(el, 'a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var t = R_selFirst(el, 'h3.manga-title-modern a');
    var img = R_selFirst(el, 'img');
    out.push({ key: R_path(href), title: t ? t.text() : link.text(), coverUrl: cleanThumb(img ? img.absUrl('src') : '') });
  }
  var hasNext = !!R_selFirst(doc, 'a.next.page-numbers');
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    var nonce = await getNonce();
    var body = 'action=get_popular_manga&period=month&nonce=' + encodeURIComponent(nonce);
    var postHeaders = { Referer: BASE + '/', 'X-Requested-With': 'XMLHttpRequest', 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' };
    var text = await $.http.post(BASE + '/wp-admin/admin-ajax.php', body, postHeaders);
    var j = $.json.parse(text);
    var doc = $.html.parse((j.data && j.data.html) || '');
    var out = [];
    var items = R_sel(doc, 'div.popular-manga-item');
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      var t = R_selFirst(el, 'h4.popular-manga-title a');
      var link = R_selFirst(el, 'a');
      if (!t || !link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var img = R_selFirst(el, 'img');
      out.push({ key: R_path(href), title: t.text(), coverUrl: cleanThumb(img ? img.absUrl('src') : '') });
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/?s=' + encodeURIComponent(query || '');
    if (page > 1) { u += '&paged=' + page; }
    var text = await $.http.get(u, { Referer: BASE + '/' });
    var doc = $.html.parse(text);
    var out = [];
    var items = R_sel(doc, '.manga-grid.search-results-grid .manga-card');
    if (items.length === 0) { return parseLatest(text); }
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      var link = R_selFirst(el, 'a.manga-card-link');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var t = R_selFirst(el, 'h3.manga-card-title');
      var img = R_selFirst(el, 'img');
      out.push({ key: R_path(href), title: t ? t.text() : link.text(), coverUrl: cleanThumb(img ? img.absUrl('src') : '') });
    }
    return { mangas: out, hasNextPage: !!R_selFirst(doc, 'a.next.page-numbers') };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), { Referer: BASE + '/' });
    var doc = $.html.parse(text);
    var status = '';
    var author = '';
    var items = R_sel(doc, '.manga-meta-item');
    for (var i = 0; i < items.length; i++) {
      var label = R_selFirst(items[i], '.meta-label');
      var value = R_selFirst(items[i], '.meta-value');
      if (!label || !value) { continue; }
      var l = label.text().trim();
      var v = value.text().trim();
      if (l === 'Status:') {
        if (v === 'Em Lançamento' || v === 'Em Andamento') { status = 'ongoing'; }
        else if (v === 'Completo') { status = 'completed'; }
        else if (v === 'Cancelado') { status = 'cancelled'; }
        else if (v === 'Pausado' || v === 'Hiato') { status = 'hiatus'; }
      } else if (l === 'Autor:') { author = v; }
    }
    var genres = [];
    var gels = R_sel(doc, '.manga-tag');
    for (var g = 0; g < gels.length; g++) { genres.push(gels[g].text()); }
    return {
      key: mangaKey,
      title: R_ownText(R_selFirst(doc, 'h1.manga-title')) || '',
      coverUrl: '',
      author: author,
      description: R_ownText(R_selFirst(doc, '.synopsis-content')) || '',
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), { Referer: BASE + '/' });
    var doc = $.html.parse(text);
    var items = R_sel(doc, '.chapters-list .chapter-item');
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      var link = R_selFirst(el, '.chapter-link');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var name = R_selFirst(el, '.chapter-number');
      var date = R_selFirst(el, '.chapter-date');
      out.push({
        key: R_path(href),
        name: name ? name.text() : 'Capítulo',
        chapterNumber: -1,
        dateUpload: R_date(date ? date.text() : ''),
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), { Referer: BASE + '/' });
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, '.chapter-image-container img');
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
