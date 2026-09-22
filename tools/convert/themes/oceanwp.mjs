// OceanWP theme engine (id: hentaicrot, pixhentai) — WP blog-style single-chapter reader
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText || '';
  const warnings = [];
  const config = { hasTagFilter: true };
  if (/hasTagFilter\s*=\s*false/.test(kt)) config.hasTagFilter = false;
  warnings.push('category/tag browse filters not supported by host; text search only');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: oceanwp)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

module.exports = {
  getPopularManga: async function (page) {
    var url = page > 1 ? BASE + '/page/' + page + '/' : BASE + '/';
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    var entries = R_sel(doc, 'article.blog-entry');
    var mangas = [];
    for (var i = 0; i < entries.length; i++) {
      var link = R_selFirst(entries[i], 'h2.blog-entry-title a');
      if (!link) { continue; }
      var img = R_selFirst(entries[i], 'div.thumbnail img');
      var href = link.absUrl('href') || link.attr('href') || '';
      mangas.push({
        key: R_path(href),
        title: link.text(),
        coverUrl: img ? (img.absUrl('src') || img.attr('src') || '') : ''
      });
    }
    var hasNextPage = !!R_selFirst(doc, 'ul.page-numbers a.next');
    return { mangas: mangas, hasNextPage: hasNextPage };
  },

  getSearchManga: async function (page, query) {
    var url;
    if (query) {
      url = BASE + '/?s=' + encodeURIComponent(query);
      if (page > 1) { url = BASE + '/page/' + page + '/?s=' + encodeURIComponent(query); }
    } else {
      url = page > 1 ? BASE + '/page/' + page + '/' : BASE + '/';
    }
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    var entries = R_sel(doc, 'article');
    var mangas = [];
    for (var i = 0; i < entries.length; i++) {
      var link = R_selFirst(entries[i], 'h2.search-entry-title a, h2.blog-entry-title a');
      if (!link) { continue; }
      var img = R_selFirst(entries[i], 'div.thumbnail img');
      var href = link.absUrl('href') || link.attr('href') || '';
      mangas.push({
        key: R_path(href),
        title: link.text(),
        coverUrl: img ? (img.absUrl('src') || img.attr('src') || '') : ''
      });
    }
    var hasNextPage = !!R_selFirst(doc, 'ul.page-numbers a.next');
    return { mangas: mangas, hasNextPage: hasNextPage };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(BASE + mangaKey);
    var doc = $.html.parse(text);
    var content = R_selFirst(doc, 'div#content') || doc;
    var titleEl = R_selFirst(content, '.entry-title');
    var descEl = R_selFirst(content, 'div.entry-content');
    var img = R_selFirst(content, 'div.thumbnail img');
    var cats = R_sel(content, 'li.meta-cat a, li.meta-category a');
    var genres = [];
    for (var i = 0; i < cats.length; i++) { genres.push(cats[i].text()); }
    return {
      key: mangaKey,
      title: titleEl ? titleEl.text() : '',
      coverUrl: img ? (img.absUrl('src') || img.attr('src') || '') : '',
      description: descEl ? descEl.text() : '',
      genre: genres.join(', '),
      status: 'COMPLETED'
    };
  },

  getChapterList: async function (mangaKey) {
    return [
      { key: mangaKey, name: 'Chapter 1', dateUpload: 0 }
    ];
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(BASE + chapterKey);
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, 'div.entry-content img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].absUrl('src') || imgs[i].attr('src') || '';
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
