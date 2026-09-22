// pt/revistasequadrinhos — WP-like HTML site; each post is a single "chapter" gallery
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['filters not ported (category/tag browse)'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone scraper)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};

function parseList(doc) {
  var out = [];
  var items = R_sel(doc, 'ul.videos > li');
  for (var i = 0; i < items.length; i++) {
    var a = R_selFirst(items[i], 'a.titulo');
    if (!a) { continue; }
    var href = a.attr('href');
    if (!href) { continue; }
    var img = R_selFirst(items[i], 'div.thumb-conteudo img');
    out.push({ key: R_path(href), title: a.text(), coverUrl: R_img(img) });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, '.paginacao li.next') };
}

module.exports = {
  getPopularManga: async function (page) {
    var u = BASE + '/category/popular-comics' + (page > 1 ? '/page/' + page : '');
    return parseList($.html.parse(await $.http.get(u)));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + (page > 1 ? '/page/' + page : '') + '?s=' + encodeURIComponent(query || '');
    return parseList($.html.parse(await $.http.get(u)));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey)));
    var desc = [];
    var ps = R_sel(doc, '.post-texto p');
    for (var i = 0; i < ps.length; i++) {
      var t = ps[i].text();
      if (t) { desc.push(t); }
    }
    var genres = [];
    var tags = R_sel(doc, '.post-tags a');
    for (var j = 0; j < tags.length; j++) { genres.push(tags[j].text()); }
    var og = R_selFirst(doc, 'meta[property="og:image"]');
    return {
      key: mangaKey,
      title: R_ownText(R_selFirst(doc, '.post-conteudo h1')) || '',
      coverUrl: og ? (og.attr('content') || '') : '',
      description: desc.join('\\n'),
      genre: genres.join(', '),
      status: 'completed'
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey)));
    var meta = R_selFirst(doc, 'meta[property="article:published_time"]');
    var dateStr = meta ? meta.attr('content') : '';
    var ts = 0;
    if (dateStr) {
      ts = Date.parse(dateStr.replace(/([-+]\\d{2}):(\\d{2})$/, '$1$2')) || 0;
    }
    return [{
      key: mangaKey,
      name: 'Capítulo Único',
      chapterNumber: -1,
      dateUpload: ts,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey)));
    var out = [];
    var gallery = R_sel(doc, 'div.dgwt-jg-gallery figure.dgwt-jg-item a');
    if (gallery.length > 0) {
      for (var i = 0; i < gallery.length; i++) {
        var href = R_abs(gallery[i].attr('href'));
        if (href) { out.push({ index: out.length, url: href }); }
      }
      return out;
    }
    var imgs = R_sel(doc, '.post-texto img');
    for (var j = 0; j < imgs.length; j++) {
      var u = R_abs(imgs[j].attr('src')) || R_abs(imgs[j].attr('data-lazy-src'));
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
