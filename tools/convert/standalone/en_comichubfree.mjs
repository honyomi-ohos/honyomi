// en/comichubfree — comichubfree.com HTML scraper with paginated chapter lists
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return { ok: true, config: {}, warnings: ['chapter order assumed newest-first on site and reversed to oldest-first'] };
}

export function generate(manifest) {
  return wrap(manifest, `
var HDRS = { Referer: BASE + '/' };
function parseList(doc) {
  var out = [];
  var items = R_sel(doc, '.movie-list-index .cartoon-box');
  for (var i = 0; i < items.length; i++) {
    if (!R_selFirst(items[i], '.detail')) { continue; }
    var a = R_selFirst(items[i], 'a');
    var h3 = R_selFirst(items[i], 'h3');
    if (!a || !h3) { continue; }
    var href = a.absUrl('href') || a.attr('href');
    if (!href) { continue; }
    var img = R_selFirst(items[i], 'img');
    out.push({ key: R_path(href), title: h3.text(), coverUrl: img ? (img.absUrl('data-src') || img.absUrl('src')) : '' });
  }
  var hasNext = !!R_selFirst(doc, 'ul.pagination a[rel=next]');
  return { mangas: out, hasNextPage: hasNext };
}
module.exports = {
  getPopularManga: async function (page) {
    var doc = await H_doc(BASE + '/popular-comic?page=' + page, HDRS);
    return parseList(doc);
  },
  getSearchManga: async function (page, query) {
    var doc = await H_doc(BASE + '/search-comic?key=' + encodeURIComponent(query) + '&page=' + page, HDRS);
    return parseList(doc);
  },
  getMangaDetail: async function (key) {
    var doc = await H_doc(R_abs(key), HDRS);
    var info = R_selFirst(doc, 'div.movie-info');
    var desc = '', cover = '', author = '', status = '';
    if (info) {
      var d = R_selFirst(info, '#film-content');
      desc = d ? d.text() : '';
      var img = R_selFirst(info, 'img');
      cover = img ? (img.absUrl('data-src') || img.absUrl('src')) : '';
      author = H_pairs(info, 'dt, dd', 'Authors:');
      var st = H_pairs(info, 'dt, dd', 'Status:');
      status = st === 'Ongoing' ? 'ongoing' : (st === 'Completed' ? 'completed' : '');
    }
    var title = H_firstText(doc, 'h1') || H_firstText(doc, '.series-info h1, .movie-info h3');
    return { key: key, title: title, coverUrl: cover, author: author, description: desc, genre: '', status: status };
  },
  getChapterList: async function (key) {
    var chapters = [];
    var url = R_abs(key);
    while (url) {
      var doc;
      try {
        doc = await H_doc(url, HDRS);
      } catch (e) {
        break;
      }
      var rows = R_sel(doc, 'div.episode-list > div > table > tbody > tr');
      for (var i = 0; i < rows.length; i++) {
        var a = R_selFirst(rows[i], 'a');
        if (!a) { continue; }
        var href = a.absUrl('href') || a.attr('href');
        if (!href) { continue; }
        var tds = R_sel(rows[i], 'td');
        var dateEl = tds.length > 0 ? tds[tds.length - 1] : null;
        chapters.push({
          key: R_path(href), name: a.text(), chapterNumber: -1,
          dateUpload: dateEl ? H_monthDate(dateEl.text()) : 0, pages: 0, sortOrder: 0
        });
      }
      var next = R_selFirst(doc, 'ul.pagination a[rel=next]');
      var nh = next ? next.absUrl('href') : '';
      url = nh && nh !== url ? nh : null;
    }
    chapters.reverse();
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey) + '/all', HDRS);
    var imgs = R_sel(doc, 'img.chapter_img');
    var pages = []; var seen = {};
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('data-src') || imgs[i].absUrl('src');
      if (u && !seen[u]) { seen[u] = true; pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
