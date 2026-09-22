// en/digitalcomicmuseum — digitalcomicmuseum.com public-domain comics archive
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return { ok: true, config: {}, warnings: ['page images resolved by fetching each slide link (N requests per chapter)'] };
}

export function generate(manifest) {
  return wrap(manifest, `
var HDRS = { Referer: BASE + '/' };
function parseStats(doc) {
  var out = [];
  var rows = R_sel(doc, 'tbody > .mainrow');
  for (var i = 0; i < rows.length; i++) {
    var link = R_selFirst(rows[i], 'a');
    if (!link) { continue; }
    var href = link.absUrl('href') || link.attr('href');
    if (!href) { continue; }
    var img = R_selFirst(rows[i], 'img');
    out.push({ key: R_path(href), title: link.text(), coverUrl: img ? img.absUrl('src') : '' });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, 'img[alt=Next]') };
}
module.exports = {
  getPopularManga: async function (page) {
    var doc = await H_doc(BASE + '/stats.php?ACT=topdl&start=' + (page - 1) + '00&limit=100', HDRS);
    return parseStats(doc);
  },
  getSearchManga: async function (page, query) {
    var boundary = '----mihonform' + Date.now();
    var body = '--' + boundary + '\\r\\nContent-Disposition: form-data; name="terms"\\r\\n\\r\\n' + query + '\\r\\n--' + boundary + '--\\r\\n';
    var text = await $.http.post(BASE + '/index.php?ACT=dosearch', body, {
      'Content-Type': 'multipart/form-data; boundary=' + boundary, Referer: BASE + '/'
    });
    var doc = $.html.parse(text);
    var out = [];
    var rows = R_sel(doc, '#search-results tbody > tr');
    for (var i = 0; i < rows.length; i++) {
      var a = R_selFirst(rows[i], 'td > a');
      if (!a) { continue; }
      var href = a.absUrl('href') || a.attr('href');
      if (!href) { continue; }
      out.push({ key: R_path(href), title: a.text(), coverUrl: '' });
    }
    return { mangas: out, hasNextPage: false };
  },
  getMangaDetail: async function (key) {
    var doc = await H_doc(R_abs(key), HDRS);
    var els = R_sel(doc, '.tableborder');
    var title = '', cover = '', desc = '';
    if (els.length > 0) {
      var cat = R_selFirst(els[0], '#catname');
      title = cat ? cat.text() : '';
      var catLink = R_selFirst(els[0], '#catname > a');
      var img = R_selFirst(els[0], 'table img');
      cover = img ? img.absUrl('src') : '';
    }
    for (var i = 0; i < els.length; i++) {
      var c = R_selFirst(els[i], '#catname');
      if (c && c.text() === 'Description') {
        var t = R_selFirst(els[i], 'table');
        desc = t ? t.text() : '';
      }
    }
    return { key: key, title: title, coverUrl: cover, author: '', description: desc, genre: '', status: '' };
  },
  getChapterList: async function (key) {
    var doc = await H_doc(R_abs(key), HDRS);
    var els = R_sel(doc, '.tableborder:first-of-type');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var cat = R_selFirst(els[i], '#catname');
      var link = R_selFirst(els[i], '.tablefooter a');
      if (!cat || !link) { continue; }
      var href = link.absUrl('href') || link.attr('href');
      if (!href) { continue; }
      out.push({ key: R_path(href), name: cat.text(), chapterNumber: -1, dateUpload: 0, pages: 0, sortOrder: 0 });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), HDRS);
    var slides = R_sel(doc, '.latest-slide > .slick-slide > a');
    var pages = [];
    for (var i = 0; i < slides.length; i++) {
      var href = slides[i].absUrl('href') || slides[i].attr('href');
      if (!href) { continue; }
      try {
        var pdoc = await H_doc(href, HDRS);
        var img = R_selFirst(pdoc, 'body > a:nth-of-type(2) > img');
        var src = img ? (img.absUrl('src') || img.attr('src')) : '';
        if (src) { pages.push({ index: pages.length, url: src }); }
      } catch (e) { /* skip broken slide */ }
    }
    return pages;
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
