// it/hentaiarchive — hentai-archive.com WordPress (bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: [],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var HDRS = { Referer: BASE + '/' };
function imgAttr(el) {
  var ds = el.attr('data-src');
  if (ds) { return el.absUrl('data-src'); }
  var s = el.attr('src');
  if (s) { return el.absUrl('src'); }
  return '';
}
module.exports = {
  getPopularManga: async function (page) {
    var doc = await H_doc(BASE + '/category/hentai-recenti/page/' + page, HDRS);
    var els = R_sel(doc, 'div.posts-container article');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var link = R_selFirst(els[i], 'a.entire-meta-link');
      var title = R_selFirst(els[i], 'span.screen-reader-text');
      if (!link || !title) { continue; }
      var img = R_selFirst(els[i], 'span.post-featured-img img.wp-post-image');
      out.push({
        key: R_path(link.absUrl('href')),
        title: title.text(),
        coverUrl: img ? img.absUrl('data-nectar-img-src') : ''
      });
    }
    return { mangas: out, hasNextPage: !!R_selFirst(doc, 'nav#pagination a.next.page-numbers') };
  },

  getSearchManga: async function (page, query) {
    var doc = await H_doc(BASE + '/page/' + page + '/?s=' + encodeURIComponent(query), HDRS);
    var els = R_sel(doc, 'article.result');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var link = R_selFirst(els[i], 'h2.title a');
      if (!link) { continue; }
      var img = R_selFirst(els[i], 'a img.wp-post-image');
      out.push({
        key: R_path(link.absUrl('href')),
        title: link.text(),
        coverUrl: img ? img.absUrl('src') : ''
      });
    }
    return { mangas: out, hasNextPage: !!R_selFirst(doc, 'a.next.page-numbers') };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var cats = R_sel(doc, 'div.main-content .meta-category');
    var names = [];
    for (var i = 0; i < cats.length; i++) {
      var children = R_sel(cats[i], 'a');
      if (!children.length) { children = R_sel(cats[i], '*'); }
      for (var j = 0; j < children.length; j++) {
        var cls = children[j].attr('class');
        if (cls) { names.push(cls); }
      }
    }
    var genre = names.join(', ').replace(/-/g, ' ').replace(/hentai/g, '').trim();
    return {
      key: mangaKey,
      title: H_firstText(doc, 'div.main-content h1'),
      coverUrl: '',
      author: '',
      description: '',
      genre: genre,
      status: 'completed'
    };
  },

  getChapterList: async function (mangaKey) {
    return [{
      key: mangaKey,
      name: 'Chapter',
      chapterNumber: 1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), HDRS);
    var els = R_sel(doc, 'div.content-inner img');
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var url = imgAttr(els[i]).replace(/-(\\d+x\\d+)(?=\\.jpg)/g, '');
      if (url) { pages.push({ index: pages.length, url: url }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/', Accept: 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8' };
  }
};
`);
}
