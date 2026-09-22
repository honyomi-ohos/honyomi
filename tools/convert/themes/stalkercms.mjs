// StalkerCms theme engine (pt: risentoons) — Django-style CMS with live search
export const runtime = 'wp';

export function extract(ctx) {
  const warnings = [];
  const config = {};
  warnings.push('chapter list pagination followed eagerly (multiple requests)');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: stalkercms)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function parseDate(s) {
  var m = /(\\d{1,2})\\/(\\d{1,2})\\/(\\d{4})/.exec(String(s || '').trim());
  if (!m) { return 0; }
  return Math.floor(Date.UTC(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10)) / 1000);
}

function statusMap(s) {
  var t = String(s || '').trim().toLowerCase();
  if (t === 'em andamento') { return 'ONGOING'; }
  if (t === 'concluído' || t === 'concluido') { return 'COMPLETED'; }
  if (t === 'hiato') { return 'ON_HIATUS'; }
  if (t === 'cancelado') { return 'CANCELLED'; }
  return 'UNKNOWN';
}

function parseCards(doc) {
  var items = R_sel(doc, '.comics-grid a.comic-card-link, div.manga-card-simple');
  var mangas = [];
  for (var i = 0; i < items.length; i++) {
    var h3 = R_selFirst(items[i], 'h3');
    if (!h3) { continue; }
    var href = items[i].absUrl('href');
    if (!href) {
      var a = R_selFirst(items[i], 'a');
      href = a ? a.absUrl('href') : '';
    }
    var img = R_selFirst(items[i], 'img');
    mangas.push({
      key: R_path(href),
      title: h3.text(),
      coverUrl: img ? (img.absUrl('src') || img.attr('src') || '') : ''
    });
  }
  var hasNextPage = !!R_selFirst(doc, '.page-link[aria-label=Próxima]:not(disabled)');
  return { mangas: mangas, hasNextPage: hasNextPage };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/manga/todos/?page=' + page);
    return parseCards($.html.parse(text));
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/search/live-search/?q=' + encodeURIComponent(query));
    var data = JSON.parse(text);
    var results = (data && data.results) || [];
    var mangas = [];
    for (var i = 0; i < results.length; i++) {
      var r = results[i];
      var key = R_path(r.url || '');
      if (!key) { continue; }
      var cover = r.cover_url || '';
      if (cover && cover.indexOf('http') !== 0) { cover = BASE + cover; }
      mangas.push({ key: key, title: r.title || '', coverUrl: cover });
    }
    return { mangas: mangas, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(BASE + mangaKey);
    var doc = $.html.parse(text);
    var titleEl = R_selFirst(doc, 'h1');
    var img = R_selFirst(doc, '.sidebar-cover-image img');
    var descEl = R_selFirst(doc, '.manga-description');
    var statusEl = R_selFirst(doc, '.status-tag');
    var genreEls = R_sel(doc, 'a.genre-tag');
    var genres = [];
    for (var g = 0; g < genreEls.length; g++) { genres.push(genreEls[g].text()); }
    return {
      key: mangaKey,
      title: titleEl ? titleEl.text() : '',
      coverUrl: img ? (img.absUrl('src') || img.attr('src') || '') : '',
      description: descEl ? descEl.text() : '',
      genre: genres.join(', '),
      status: statusMap(statusEl ? statusEl.text() : '')
    };
  },

  getChapterList: async function (mangaKey) {
    var chapters = [];
    var page = 1;
    var hasNext = true;
    while (hasNext && page < 200) {
      var url = BASE + mangaKey;
      url += (url.indexOf('?') >= 0 ? '&' : '?') + 'page=' + page;
      var text = await $.http.get(url);
      var doc = $.html.parse(text);
      var links = R_sel(doc, '.chapter-item-list a.chapter-link');
      for (var i = 0; i < links.length; i++) {
        var nameEl = R_selFirst(links[i], '.chapter-number');
        var dateEl = R_selFirst(links[i], '.chapter-date');
        var key = R_path(links[i].absUrl('href') || links[i].attr('href'));
        if (!key || !nameEl) { continue; }
        chapters.push({
          key: key,
          name: nameEl.text(),
          dateUpload: dateEl ? parseDate(R_ownText(dateEl)) : 0
        });
      }
      hasNext = !!R_selFirst(doc, '.page-link[aria-label=Próxima]:not(disabled)');
      page++;
    }
    // site lists newest first; host expects oldest first
    chapters.reverse();
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(BASE + chapterKey);
    var doc = $.html.parse(text);
    var els = R_sel(doc, '.chapter-image-canvas');
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var src = els[i].absUrl('data-src-url') || els[i].attr('data-src-url') || '';
      if (src) { pages.push(src); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { 'Referer': BASE + '/' };
  }
};
`;
}
