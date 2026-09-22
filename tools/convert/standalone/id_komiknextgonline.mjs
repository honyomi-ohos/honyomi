// id/komiknextgonline — komiknextgonline.com Toocheke single-chapter comics (bespoke)
// Site has changed since upstream: comic list lives on /comic/ archive with comic-thumbnail-wrapper cards.
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['site markup changed vs upstream; adapted to current /comic/ archive; single-chapter entries'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
async function listPage(page, query) {
  var u;
  if (query) {
    u = page > 1 ? BASE + '/page/' + page + '/?s=' + encodeURIComponent(query) : BASE + '/?s=' + encodeURIComponent(query);
  } else {
    u = page > 1 ? BASE + '/comic/page/' + page + '/' : BASE + '/comic/';
  }
  var doc = await H_doc(u);
  var items = R_sel(doc, '#left-content span.comic-thumbnail-wrapper, #left-content ul#comic-list li.comic, #left-content article.comic');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var a = R_selFirst(el, 'a');
    if (!a) { a = el; }
    var href = a.absUrl('href');
    if (!href || href.indexOf(BASE) !== 0) { continue; }
    if (!/\\/comic\\/[^/]+\\/?$/.test(R_path(href))) { continue; }
    var tEl = R_selFirst(el, '.comic-title, .entry-title, h3');
    var title = tEl ? tEl.text().replace(/^#\\d+\\.\\s*/, '') : (a.attr('title') || R_selFirst(el, 'img') ? (R_selFirst(el, 'img').attr('alt') || '') : '');
    var img = R_selFirst(el, 'img');
    out.push({ key: R_path(href), title: title, coverUrl: img ? R_img(img) : '' });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, 'a.next.page-numbers') };
}
module.exports = {
  getPopularManga: async function (page) { return listPage(page, ''); },
  getSearchManga: async function (page, query) { return listPage(page, query || ''); },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var ogTitle = R_selFirst(doc, 'meta[property="og:title"]');
    var ogDesc = R_selFirst(doc, 'meta[property="og:description"]');
    var og = R_selFirst(doc, 'meta[property="og:image"]');
    var h1 = R_selFirst(doc, 'h1.entry-title, h1');
    return {
      key: mangaKey,
      title: h1 ? h1.text() : (ogTitle ? ogTitle.attr('content') : ''),
      coverUrl: og ? og.absUrl('content') : '',
      author: '',
      description: ogDesc ? ogDesc.attr('content') : '',
      genre: '',
      status: 'completed'
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var posted = R_selFirst(doc, 'span.posted-on a, time');
    return [{
      key: mangaKey,
      name: 'Chapter 1',
      chapterNumber: 1,
      dateUpload: posted ? R_date(posted.text().replace('Posted on ', '')) : 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey));
    var imgs = R_sel(doc, 'div#spliced-comic img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = R_img(imgs[i]);
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
