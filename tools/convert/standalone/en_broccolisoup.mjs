// en/broccolisoup — single-comic webcomic (politeandgood.com), archive-based chapter list
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['character-summary text pages dropped (no text interceptor); character images kept'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var COVER = 'https://politeandgood.com/assets/images/static/Bocki%20(correct%20size).png';
var DESC = ' Hello there! How is the Weather? This comic is made by me, Secret Pie. I am a pie with legs who draws comics and makes music. I am also an entomologist.';
function mangaObj() {
  return { key: '/comic/archive', title: 'Broccoli Soup', coverUrl: COVER, author: 'Secret Pie', description: DESC, genre: '', status: '' };
}
module.exports = {
  getPopularManga: async function (page) {
    return { mangas: [{ key: '/comic/archive', title: 'Broccoli Soup', coverUrl: COVER }], hasNextPage: false };
  },
  getSearchManga: async function (page, query) {
    return { mangas: [], hasNextPage: false };
  },
  getMangaDetail: async function (key) { return mangaObj(); },
  getChapterList: async function (key) {
    var doc = await H_doc(R_abs(key), { Referer: BASE + '/' });
    var out = [{ key: '/comic-characters', name: 'Characters', chapterNumber: 0, dateUpload: 0, pages: 0, sortOrder: 0 }];
    var groups = R_sel(doc, 'li.archive-marker');
    var arcCount = {};
    for (var g = 0; g < groups.length; g++) {
      var arcEl = R_selFirst(groups[g], '.archive-header .marker-title');
      var arcTitle = arcEl ? arcEl.text() : '';
      var pages = R_sel(groups[g], 'li.archive-page');
      for (var i = 0; i < pages.length; i++) {
        var link = R_selFirst(pages[i], 'a');
        if (!link) { continue; }
        var tEl = R_selFirst(link, 'span.page-title');
        if (!tEl) { continue; }
        var href = link.absUrl('href') || link.attr('href');
        if (!href) { continue; }
        var num = parseInt(href.substring(href.lastIndexOf('/') + 1), 10);
        var parts = [];
        if (!isNaN(num)) { parts.push(num + ':'); }
        parts.push(tEl.text());
        if (arcTitle) {
          arcCount[arcTitle] = (arcCount[arcTitle] || 0) + 1;
          parts.push('(' + arcTitle + ' #' + arcCount[arcTitle] + ')');
        }
        out.push({ key: R_path(href), name: parts.join(' '), chapterNumber: isNaN(num) ? -1 : num, dateUpload: 0, pages: 0, sortOrder: 0 });
      }
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), { Referer: BASE + '/' });
    var pages = [];
    if (chapterKey.indexOf('comic-characters') >= 0) {
      var secs = R_sel(doc, 'section.static-block');
      for (var i = 0; i < secs.length; i++) {
        var body = R_selFirst(secs[i], 'div.block-content');
        var img = R_selFirst(secs[i], 'figure img');
        if (!img && !body) { continue; }
        if (img) { var u = img.absUrl('src'); if (u) { pages.push({ index: pages.length, url: u }); } }
      }
    } else {
      var imgs = R_sel(doc, '#comic img');
      for (var k = 0; k < imgs.length; k++) {
        var u2 = imgs[k].absUrl('src');
        if (u2) { pages.push({ index: pages.length, url: u2 }); }
      }
    }
    return pages;
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
