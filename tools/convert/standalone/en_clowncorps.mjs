// en/clowncorps — single webcomic, paginated /comic archive
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ["author's notes text pages dropped (no text interceptor); chapter cache not persisted"],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var CREATOR = 'Joe Chouinard';
function staticManga() {
  return {
    key: '/comic', title: $.manifest.name, coverUrl: BASE + '/wp-content/uploads/2022/11/clowns41.jpg',
    author: CREATOR, description: 'Clown Corps is a comic about crime-fighting clowns.\\nIt\\'s pronounced "core." Like marine corps.',
    genre: '', status: 'ongoing',
  };
}
module.exports = {
  getPopularManga: async function (page) {
    return { mangas: [{ key: '/comic', title: $.manifest.name, coverUrl: BASE + '/wp-content/uploads/2022/11/clowns41.jpg' }], hasNextPage: false };
  },
  getSearchManga: async function (page, query) {
    return await module.exports.getPopularManga(page);
  },
  getMangaDetail: async function (key) { return staticManga(); },
  getChapterList: async function (key) {
    var doc = await H_doc(R_abs(key), { Referer: BASE + '/' });
    var ind = R_selFirst(doc, '#paginav li.paginav-pages');
    var total = 1;
    if (ind) {
      var parts = ind.text().split(' ');
      total = parseInt(parts[parts.length - 1], 10) || 1;
    }
    var seen = {}; var all = [];
    for (var p = 1; p <= total; p++) {
      var pdoc = p === 1 ? doc : await H_doc(BASE + '/comic/page/' + p + '/', { Referer: BASE + '/' });
      var items = R_sel(pdoc, '.comic');
      var added = false;
      for (var i = 0; i < items.length; i++) {
        var a = R_selFirst(items[i], '.post-title a');
        if (!a) { continue; }
        var href = a.absUrl('href') || a.attr('href');
        if (!href || seen[href]) { continue; }
        seen[href] = true; added = true;
        var ds = R_selFirst(items[i], '.post-date');
        var ts = R_selFirst(items[i], '.post-time');
        var dv = Date.parse(((ts ? ts.text() + ' ' : '') + (ds ? ds.text() : '')).trim());
        all.push({ key: R_path(href), name: a.text(), chapterNumber: -1, dateUpload: isNaN(dv) ? 0 : dv, pages: 0, sortOrder: 0 });
      }
      if (!added && p > 1) { break; }
    }
    all.sort(function (x, y) { return x.dateUpload - y.dateUpload; });
    for (var j = 0; j < all.length; j++) { all[j].sortOrder = j; }
    return all;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), { Referer: BASE + '/' });
    var img = R_selFirst(doc, '#comic img');
    var src = img ? (img.attr('src') || '') : '';
    return src ? [{ index: 0, url: R_abs(src) }] : [];
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
