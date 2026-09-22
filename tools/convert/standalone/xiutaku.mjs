// all/xiutaku — bespoke scraper engine (blog-style photo galleries, per-page chapters)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['mobile random UA approximated with default UA; URL-as-query search not portable'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone scraper)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};

function parseList(doc) {
  var items = R_sel(doc, '.blog > div');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var link = R_selFirst(items[i], '.item-content .item-link');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(items[i], 'img');
    out.push({ key: R_path(href), title: link.text(), coverUrl: img ? img.absUrl('src') : '' });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, '.pagination-next:not([disabled])') };
}
function detailsFrom(doc, key) {
  var header = R_selFirst(doc, '.article-header');
  if (!header) { throw new Error('Title is mandatory'); }
  var desc = '';
  var infos = R_sel(doc, '.article-info');
  for (var i = 0; i < infos.length; i++) {
    if (!R_selFirst(infos[i], 'small')) { desc = infos[i].text(); break; }
  }
  var genres = [];
  var tagsEl = R_selFirst(doc, '.article-tags');
  if (tagsEl) {
    var tags = R_sel(tagsEl, '.tags > .tag');
    for (var t = 0; t < tags.length; t++) {
      var name = tags[t].text().replace(/^#/, '');
      if (name) { genres.push(name); }
    }
  }
  return {
    key: key,
    title: header.text(),
    coverUrl: '',
    author: '',
    description: desc,
    genre: genres.join(', '),
    status: 'completed',
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/hot?start=' + (20 * (page - 1)));
    return parseList($.html.parse(text));
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/?search=' + encodeURIComponent(query || '') + '&start=' + (20 * (page - 1)));
    var doc = $.html.parse(text);
    if (R_selFirst(doc, '.article-header')) {
      var path = R_path(BASE + '/?search=' + encodeURIComponent(query));
      return { mangas: [{ key: path, title: '', coverUrl: '' }], hasNextPage: false };
    }
    return parseList(doc);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    return detailsFrom($.html.parse(text), mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var dateUpload = 0;
    var small = R_selFirst(doc, '.article-info > small');
    if (small) {
      var ds = small.text().replace(/^\\uD83D\\uDD52/, '').trim();
      var m = ds.match(/(\\d{2}):(\\d{2})\\s+(\\d{2})-(\\d{2})-(\\d{4})/);
      if (m) {
        var ts = Date.parse(m[5] + '-' + m[4] + '-' + m[3] + 'T' + m[1] + ':' + m[2] + ':00Z');
        if (!isNaN(ts)) { dateUpload = ts; }
      }
    }
    var maxPage = 1;
    var spanEl = R_selFirst(doc, '.pagination-list > span:last-child > a');
    if (spanEl) {
      var n = parseInt(spanEl.text(), 10);
      if (!isNaN(n)) { maxPage = n; }
    }
    var out = [];
    for (var p = 1; p <= maxPage; p++) {
      out.push({
        key: mangaKey + '/page/' + p,
        name: 'Page ' + p,
        chapterNumber: p,
        dateUpload: dateUpload,
        pages: 0,
        sortOrder: p - 1,
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var idx = String(chapterKey).indexOf('/page/');
    var mangaPath = idx >= 0 ? String(chapterKey).substring(0, idx) : String(chapterKey);
    var pageNo = idx >= 0 ? String(chapterKey).substring(idx + 6) : '1';
    var text = await $.http.get(BASE + mangaPath + '?page=' + pageNo);
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, '.article-fulltext img');
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
