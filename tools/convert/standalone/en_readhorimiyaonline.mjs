// en/readhorimiyaonline — bespoke scraper (single hardcoded manga)
export const runtime = 'wp';

export function extract(ctx) {
  return { ok: true, config: {}, warnings: ['single-manga source; search only matches "horimiya"'] };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function parseMangaDoc(doc) {
  var cover = '';
  var img = R_selFirst(doc, 'ul.wp-block-gallery li.blocks-gallery-item img');
  if (img) {
    var lz = img.attr('data-lazy-src');
    cover = lz ? R_abs(lz) : R_abs(img.attr('src') || '');
  }
  var p = R_selFirst(doc, 'p');
  return {
    key: '/',
    title: 'Horimiya',
    coverUrl: cover,
    author: '',
    description: p ? p.text() : '',
    genre: '',
    status: ''
  };
}

module.exports = {
  getPopularManga: async function () {
    var doc = $.html.parse(await $.http.get(BASE + '/', HDRS));
    var m = parseMangaDoc(doc);
    return { mangas: [{ key: m.key, title: m.title, coverUrl: m.coverUrl }], hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var out = [];
    if (!query || query.toLowerCase().indexOf('horimiya') >= 0) {
      var doc = $.html.parse(await $.http.get(BASE + '/', HDRS));
      var m = parseMangaDoc(doc);
      out.push({ key: m.key, title: m.title, coverUrl: m.coverUrl });
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(BASE + '/', HDRS));
    return parseMangaDoc(doc);
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(BASE + '/', HDRS));
    var items = R_sel(doc, '#Chapters_List ul li ul li a');
    var chapters = [];
    for (var i = 0; i < items.length; i++) {
      var a = items[i];
      var href = a.absUrl('href');
      if (!href) { continue; }
      chapters.push({
        key: R_path(href),
        name: a.text(),
        chapterNumber: -1,
        dateUpload: 0,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var imgs = R_sel(doc, 'div.separator a > img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var img = imgs[i];
      var lz = img.attr('data-lazy-src');
      var u = lz ? R_abs(lz) : R_abs(img.attr('src') || '');
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
