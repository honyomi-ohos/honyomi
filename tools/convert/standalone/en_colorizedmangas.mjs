// en/colorizedmangas — homepage library grid, local search filtering
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  return wrap(manifest, `
function classHas(el, token) { return (' ' + (el.attr('class') || '') + ' ').indexOf(' ' + token + ' ') >= 0; }
async function mangaList() {
  var doc = await H_doc(BASE + '/', { Referer: BASE + '/' });
  var els = R_sel(doc, 'div.lib-color-view a[href], div.lib-bw-view a[href]');
  var seen = {}; var out = [];
  for (var i = 0; i < els.length; i++) {
    var href = els[i].attr('href') || '';
    var slug = href.replace(/\\/$/, '').substring(href.replace(/\\/$/, '').lastIndexOf('/') + 1);
    if (!slug || seen[slug]) { continue; }
    var h3 = R_selFirst(els[i], 'h3');
    if (!h3) { continue; }
    seen[slug] = true;
    var img = R_selFirst(els[i], 'img');
    out.push({ key: '/' + slug, title: h3.text(), coverUrl: img ? img.absUrl('src') : '' });
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
    var q = String(query || '').trim().toLowerCase();
    if (q) {
      var filtered = [];
      for (var i = 0; i < list.length; i++) {
        if (list[i].title.toLowerCase().indexOf(q) >= 0) { filtered.push(list[i]); }
      }
      list = filtered;
    }
    return { mangas: list, hasNextPage: false };
  },
  getMangaDetail: async function (key) {
    var doc = await H_doc(R_abs(key), { Referer: BASE + '/' });
    var aside = R_selFirst(doc, 'aside');
    var title = '', cover = '', author = '', genre = '', desc = '';
    if (aside) {
      var h1 = R_selFirst(aside, 'h1');
      title = h1 ? h1.text().replace(/^Colorized/, '').trim() : '';
      var img = R_selFirst(aside, 'img');
      cover = img ? img.absUrl('src') : '';
      author = H_pairs(aside, 'dl dt, dl dd', 'Author');
      var ps = R_sel(aside, 'p');
      for (var i = 0; i < ps.length; i++) {
        var cls = ' ' + (ps[i].attr('class') || '') + ' ';
        if (genre === '' && cls.indexOf('text-[11px]') >= 0) {
          genre = ps[i].text().split('\\u8def').map(function (s) { return s.trim(); }).filter(Boolean).join(', ');
        }
        if (desc === '' && cls.indexOf('border-t') >= 0) { desc = ps[i].text(); }
      }
    }
    return { key: key, title: title, coverUrl: cover, author: author, description: desc, genre: genre, status: '' };
  },
  getChapterList: async function (key) {
    var doc = await H_doc(R_abs(key), { Referer: BASE + '/' });
    var links = R_sel(doc, 'div[class*=space-y-4] section div[class*=space-y-2] > a');
    var out = [];
    for (var i = 0; i < links.length; i++) {
      var numEl = R_selFirst(links[i], 'span[class*=font-bold]');
      var titleEl = R_selFirst(links[i], 'div[class*=truncate]');
      var numText = numEl ? numEl.text() : '';
      var titleText = titleEl ? titleEl.text() : '';
      if (!numText && !titleText) { continue; }
      var name = '';
      if (numText) {
        name = numText;
        if (titleText && titleText.toLowerCase() !== numText.toLowerCase()) { name += ' - ' + titleText; }
      } else { name = titleText; }
      var href = links[i].absUrl('href') || links[i].attr('href');
      var m = (numText || titleText).match(/\\d+(\\.\\d+)?/);
      var nr = m ? parseFloat(m[0]) : -1;
      out.push({ key: R_path(href), name: name, chapterNumber: nr, dateUpload: 0, pages: 0, sortOrder: 0 });
    }
    out.sort(function (a, b) { return a.chapterNumber - b.chapterNumber; });
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), { Referer: BASE + '/' });
    var imgs = R_sel(doc, 'main img[src*=pages]');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src') || R_abs(imgs[i].attr('src'));
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
