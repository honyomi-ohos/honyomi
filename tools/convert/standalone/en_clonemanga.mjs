// en/clonemanga — clone-army.org webcomics; chapter count from inline script
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['chapter count extracted from page scripts (fragile upstream heuristic kept)'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
async function mangaList() {
  var doc = await H_doc(BASE + '/viewer_landing.php', { Referer: BASE + '/' });
  var els = R_sel(doc, '.comicPreviewContainer');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var a = R_selFirst(els[i], 'a');
    var h3 = R_selFirst(els[i], 'h3');
    var h4 = R_selFirst(els[i], 'h4');
    var pv = R_selFirst(els[i], '.comicPreview');
    if (!a || !h3) { continue; }
    var href = a.absUrl('href') || a.attr('href');
    if (!href) { continue; }
    var cover = '';
    if (pv) {
      var st = pv.attr('style');
      var i1 = st.indexOf('site/themes');
      var i2 = i1 >= 0 ? st.indexOf(')', i1) : -1;
      if (i1 >= 0 && i2 > i1) { cover = BASE + '/' + st.substring(i1, i2).replace(/['"]/g, ''); }
    }
    out.push({ key: R_path(href), title: h3.text(), coverUrl: cover, description: h4 ? h4.text() : '' });
  }
  return out;
}
module.exports = {
  getPopularManga: async function (page) {
    var list = await mangaList();
    return { mangas: list, hasNextPage: false };
  },
  getSearchManga: async function (page, query) {
    var list = await mangaList();
    var q = String(query || '').toLowerCase();
    var filtered = [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].title.toLowerCase().indexOf(q) >= 0) { filtered.push(list[i]); }
    }
    return { mangas: filtered, hasNextPage: false };
  },
  getMangaDetail: async function (key) {
    var list = await mangaList();
    for (var i = 0; i < list.length; i++) {
      if (list[i].key === key) {
        return { key: key, title: list[i].title, coverUrl: list[i].coverUrl, author: 'Dan Kim', description: list[i].description, genre: '', status: '' };
      }
    }
    return { key: key, title: '', coverUrl: '', author: 'Dan Kim', description: '', genre: '', status: '' };
  },
  getChapterList: async function (key) {
    var doc = await H_doc(R_abs(key), { Referer: BASE + '/' });
    var scripts = R_sel(doc, 'script');
    var re = /&page=(.*?)&lang=/g;
    var matches = [];
    if (scripts.length > 3) {
      var sc = scripts[3].html() || '';
      var m;
      while ((m = re.exec(sc)) !== null) { matches.push(m[1]); }
    }
    if (matches.length < 4) {
      matches = [];
      for (var s = 0; s < scripts.length; s++) {
        var c = scripts[s].html() || '';
        var m2;
        while ((m2 = re.exec(c)) !== null) { matches.push(m2[1]); }
      }
    }
    var n = matches.length >= 4 ? parseInt(matches[3], 10) : 0;
    if (isNaN(n) || n < 1) { n = 1; }
    var sep = key.indexOf('?') >= 0 ? '&' : '?';
    var out = [];
    for (var i = 1; i <= n; i++) {
      out.push({ key: key + sep + 'page=' + i, name: 'Chapter ' + i, chapterNumber: i, dateUpload: 0, pages: 0, sortOrder: i - 1 });
    }
    return out;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), { Referer: BASE + '/' });
    var el = R_selFirst(doc, '.subsectionContainer img');
    return el ? [{ index: 0, url: el.absUrl('src') }] : [];
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
