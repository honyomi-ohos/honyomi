// id/mangalay — mangalay.blogspot.com Blogger list site (bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['no search/latest support (upstream none either); details unavailable upstream'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var LIST_URL = BASE + '/2013/04/daftar-baca-komik_20.html';
var listCache = null;
async function getList() {
  if (listCache) { return listCache; }
  var doc = await H_doc(LIST_URL);
  var tables = R_sel(doc, '.post-body table');
  var out = [];
  for (var i = 0; i < tables.length; i++) {
    var t = tables[i];
    var a = R_selFirst(t, 'a');
    if (!a) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    var cap = R_selFirst(t, '.tr-caption');
    var img = R_selFirst(t, 'img');
    out.push({ key: R_path(href), title: cap ? cap.text() : a.text(), coverUrl: img ? img.absUrl('src') : '' });
  }
  listCache = out;
  return out;
}
module.exports = {
  getPopularManga: async function () {
    var all = await getList();
    return { mangas: all, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var all = await getList();
    var q = String(query || '').toLowerCase();
    var filtered = [];
    for (var i = 0; i < all.length; i++) {
      if (!q || all[i].title.toLowerCase().indexOf(q) >= 0) { filtered.push(all[i]); }
    }
    return { mangas: filtered, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    return { key: mangaKey, title: '', coverUrl: '', author: '', description: '', genre: '', status: '' };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var links = R_sel(doc, '.post-body span > a');
    var out = [];
    for (var i = 0; i < links.length; i++) {
      var href = links[i].absUrl('href');
      if (!href) { continue; }
      var b = R_selFirst(links[i], 'b');
      out.push({
        key: R_path(href),
        name: b ? b.text() : links[i].text(),
        chapterNumber: -1,
        dateUpload: 0,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey));
    var imgs = R_sel(doc, '.separator img');
    var pages = [];
    for (var i = 0; i < imgs.length - 1; i++) { // last image is not a page (upstream drops it)
      var u = imgs[i].absUrl('src');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
