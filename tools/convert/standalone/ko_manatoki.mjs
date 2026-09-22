// ko/manatoki — Manatoki (GNU-board scraper; base64 page HTML)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: [
      'native ext rate-limits to 2 req/s to avoid 403s; this port cannot throttle, so image loading may hit 403 occasionally',
    ],
  };
}

export function generate(manifest) {
  const body = String.raw`
var ORIGIN = (BASE.match(/^(https?:\/\/[^\/]+)/) || [ '', BASE ])[1];
var HDRS = { Referer: BASE + '/' };

function absSrc(src) {
  if (!src) { return ''; }
  if (/^https?:\/\//.test(src)) { return src; }
  if (src.charAt(0) === '/') { return ORIGIN + src; }
  return BASE + '/' + src;
}

function parseList(doc) {
  var items = R_sel(doc, '.list-row .list-item');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var a = R_selFirst(el, '.img-item a');
    if (!a) { continue; }
    var href = a.absUrl('href') || a.attr('href');
    if (!href) { continue; }
    var font = R_selFirst(el, '.in-lable a font');
    var title = font ? font.text() : (a.attr('title') || '');
    if (!title) { continue; }
    var img = R_selFirst(el, '.img-item img');
    out.push({
      key: R_path(href),
      title: title,
      coverUrl: img ? (img.absUrl('src') || absSrc(img.attr('src'))) : ''
    });
  }
  var hasNext = false;
  var lis = R_sel(doc, '.pagination li');
  for (var j = 0; j < lis.length; j++) {
    var cls = lis[j].attr('class') || '';
    if (cls.indexOf('active') >= 0 && lis[j + 1] && R_selFirst(lis[j + 1], 'a')) {
      hasNext = true;
      break;
    }
  }
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await H_doc(BASE + '/bbs/board.php?bo_table=cartoon&page=' + page, HDRS));
  },

  getLatestManga: async function (page) {
    return parseList(await H_doc(BASE + '/bbs/board.php?bo_table=cartoon&page=' + page, HDRS));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/bbs/board.php?bo_table=cartoon&stx=' + encodeURIComponent(query) + '&page=' + page;
    return parseList(await H_doc(u, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var titleEl = R_selFirst(doc, '.view-content span b');
    var cover = R_selFirst(doc, '.view-img img');
    var author = '';
    var genre = '';
    var infos = R_sel(doc, '.view-content');
    for (var i = 0; i < infos.length; i++) {
      var text = infos[i].text();
      if (text.indexOf('작가 :') >= 0) {
        author = text.substring(text.indexOf('작가 :') + 4).split('•')[0].trim();
      } else if (text.indexOf('분류 :') >= 0) {
        genre = text.substring(text.indexOf('분류 :') + 4).split('•')[0].trim();
      }
    }
    return {
      key: mangaKey,
      title: titleEl ? titleEl.text() : '',
      coverUrl: cover ? (cover.absUrl('src') || absSrc(cover.attr('src'))) : '',
      author: author,
      description: '',
      genre: genre,
      status: 'unknown'
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var items = R_sel(doc, '.list-body .list-item');
    var total = items.length;
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      var a = R_selFirst(el, '.item-subject');
      if (!a) { continue; }
      var href = a.absUrl('href') || a.attr('href');
      if (!href) { continue; }
      var numEl = R_selFirst(el, '.wr-num');
      var numTxt = numEl ? numEl.text().trim() : '';
      var num = /^\d+$/.test(numTxt) ? parseInt(numTxt, 10) : (total - i);
      var dateEl = R_selFirst(el, '.wr-date');
      var dateStr = dateEl ? dateEl.text().trim() : '';
      var ts = /^\d{4}\.\d{1,2}\.\d{1,2}$/.test(dateStr) ? Date.parse(dateStr.replace(/\./g, '-')) : NaN;
      out.push({
        key: R_path(href),
        name: 'Chapter ' + num,
        chapterNumber: num,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var html = await H_get(R_abs(chapterKey), HDRS);
    var m = html.match(/var\s+manamoa_img\s*=\s*'([^']+)'/);
    if (m) {
      var decoded = $.crypto.base64Decode(m[1]);
      var doc = $.html.parse(decoded);
      var imgs = R_sel(doc, 'img');
      var out = [];
      for (var i = 0; i < imgs.length; i++) {
        var u = imgs[i].absUrl('src') || absSrc(imgs[i].attr('src'));
        if (u) { out.push({ index: out.length, url: u }); }
      }
      return out;
    }
    var doc2 = $.html.parse(html);
    var imgs2 = R_sel(doc2, '.view-content img');
    var out2 = [];
    for (var k = 0; k < imgs2.length; k++) {
      var u2 = imgs2[k].absUrl('src') || absSrc(imgs2[k].attr('src'));
      if (u2) { out2.push({ index: out2.length, url: u2 }); }
    }
    return out2;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
