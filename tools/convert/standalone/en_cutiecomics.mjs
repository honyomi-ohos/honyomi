// en/cutiecomics — DLE gallery site; single-chapter galleries
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  return wrap(manifest, `
var HDRS = { Referer: BASE + '/' };
function parseList(doc) {
  var out = [];
  var items = R_sel(doc, '#dle-content > div.w25');
  for (var i = 0; i < items.length; i++) {
    var a = R_selFirst(items[i], 'strong.field-content > a');
    if (!a) { continue; }
    var href = a.absUrl('href') || a.attr('href');
    if (!href) { continue; }
    var img = R_selFirst(items[i], 'a > img');
    out.push({ key: R_path(href), title: R_ownText(a), coverUrl: img ? img.absUrl('src') : '' });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, '.navigation > a > i.fa-angle-right') };
}
module.exports = {
  getPopularManga: async function (page) {
    var doc = await H_doc(BASE + '/page/' + page, HDRS);
    return parseList(doc);
  },
  getSearchManga: async function (page, query) {
    var body = 'do=search&subaction=search&full_search=0&search_start=' + page +
      '&result_from=' + ((page - 1) * 20 + 1) + '&story=' + encodeURIComponent(query);
    var text = await $.http.post(BASE + '/index.php?do=search', body, {
      'Content-Type': 'application/x-www-form-urlencoded', Referer: BASE + '/'
    });
    return parseList($.html.parse(text));
  },
  getMangaDetail: async function (key) {
    var doc = await H_doc(R_abs(key), HDRS);
    var img = R_selFirst(doc, 'div.galery > img');
    return {
      key: key,
      title: H_firstText(doc, 'h1#page-title'),
      coverUrl: img ? img.absUrl('src') : '',
      author: '',
      description: '',
      genre: H_texts(doc, 'h3.field-label ~ span'),
      status: 'completed'
    };
  },
  getChapterList: async function (key) {
    return [{ key: key, name: 'Chapter', chapterNumber: 1, dateUpload: 0, pages: 0, sortOrder: 0 }];
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), HDRS);
    var imgs = R_sel(doc, 'div.galery > img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
