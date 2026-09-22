// en/doujins — doujins.com gallery site (NSFW)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['series/sort/period filters not supported; popular=top month, search=default sort'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var HDRS = { Referer: BASE + '/' };
function parseGallery(doc) {
  var out = [];
  var items = R_sel(doc, 'div:not(.premium-folder) > .thumbnail-doujin a.gallery-visited-from-favorites');
  for (var i = 0; i < items.length; i++) {
    var href = items[i].absUrl('href') || items[i].attr('href');
    if (!href) { continue; }
    var t = R_selFirst(items[i], 'div.title .text');
    var img = R_selFirst(items[i], 'img');
    out.push({ key: R_path(href), title: t ? t.text() : '', coverUrl: img ? R_img(img) : '' });
  }
  var hasNext = false;
  var pager = R_selFirst(doc, '.pagination');
  if (pager) {
    var items2 = R_sel(pager, 'li.page-item');
    if (items2.length > 0) {
      hasNext = (items2[items2.length - 1].attr('class') || '').indexOf('disabled') < 0;
    }
  }
  return { mangas: out, hasNextPage: hasNext };
}
function parseDetailDate(v) {
  var s = String(v || '').split('\\u2014')[0].trim();
  s = s.replace(/(\\d+)(st|nd|rd|th)/i, '$1');
  return Date.parse(s) || 0;
}
module.exports = {
  getPopularManga: async function (page) {
    var doc = await H_doc(BASE + '/top/month', HDRS);
    return parseGallery(doc);
  },
  getSearchManga: async function (page, query) {
    var doc = await H_doc(BASE + '/searches?words=' + encodeURIComponent(query) + '&page=' + page, HDRS);
    return parseGallery(doc);
  },
  getMangaDetail: async function (key) {
    var doc = await H_doc(R_abs(key), HDRS);
    var titleEls = R_sel(doc, '.folder-title a');
    var title = titleEls.length ? titleEls[titleEls.length - 1].text() : '';
    return {
      key: key,
      title: title,
      coverUrl: '',
      author: H_texts(doc, '.gallery-artist a'),
      description: '',
      genre: (function () {
        var area = R_selFirst(doc, '.tag-area');
        return area ? H_texts(area, 'a') : '';
      })(),
      status: ''
    };
  },
  getChapterList: async function (key) {
    var doc = await H_doc(R_abs(key), HDRS);
    var dateEl = R_selFirst(doc, '.text-md-right.text-sm-left > .folder-message');
    return [{ key: key, name: 'Chapter', chapterNumber: -1, dateUpload: dateEl ? parseDetailDate(dateEl.text()) : 0, pages: 0, sortOrder: 0 }];
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), HDRS);
    var els = R_sel(doc, '.doujin');
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var u = R_abs(els[i].attr('data-file').replace(/amp;/g, ''));
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
