// en/xyzcomics — bespoke WP scraper (single-chapter galleries; chapter url == manga url)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['each post is a one-shot gallery exposed as a single "Chapter 1"'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function parseList(text) {
  var doc = $.html.parse(text);
  var items = R_sel(doc, 'article.post');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var thumb = R_selFirst(el, 'figure.post-image a');
    if (!thumb) { continue; }
    var href = thumb.absUrl('href');
    if (!href) { continue; }
    var titleEl = R_selFirst(el, 'h2.post-title a');
    out.push({
      key: R_path(href),
      title: titleEl ? titleEl.text().trim() : '',
      coverUrl: R_img(R_selFirst(el, 'figure.post-image img.wp-post-image'))
    });
  }
  var hasNext = !!R_selFirst(doc, 'a.nextp, .pagenav a.next, a.page-numbers.next, a[rel=next]');
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    var u = page > 1 ? BASE + '/allsexkomix/page/' + page + '/' : BASE + '/allsexkomix/';
    return parseList(await $.http.get(u, HDRS));
  },

  getSearchManga: async function (page, query) {
    var e = encodeURIComponent(query || '');
    var u = page > 1 ? BASE + '/page/' + page + '/?s=' + e : BASE + '/?s=' + e;
    return parseList(await $.http.get(u, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var title = '';
    var t1 = R_selFirst(doc, 'h1.post-title a');
    var t2 = R_selFirst(doc, 'h1.post-title');
    var t3 = R_selFirst(doc, 'title');
    if (t1) { title = t1.text().trim(); }
    else if (t2) { title = t2.text().trim(); }
    else if (t3) { title = t3.text().trim(); }
    var genres = [];
    var gels = R_sel(doc, 'a.post-tag-button');
    for (var i = 0; i < gels.length; i++) { genres.push(gels[i].text().trim()); }
    return {
      key: mangaKey,
      title: title,
      coverUrl: '',
      author: '',
      description: '',
      genre: genres.join(', '),
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    return [{
      key: mangaKey,
      name: 'Chapter 1',
      chapterNumber: 1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var links = R_sel(doc, '.pswp-gallery .pswp-gallery__item a[href]');
    var pages = [];
    for (var i = 0; i < links.length; i++) {
      var u = links[i].absUrl('href');
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
