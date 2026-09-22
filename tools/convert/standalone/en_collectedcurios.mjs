// en/collectedcurios — three static Jolly Jack webcomics, ?s=N page navigation
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  return wrap(manifest, `
var AUTHOR = 'Jolly Jack aka Phillip M Jackson';
var MANGAS = [
  { key: '/sequentialart.php', title: 'Sequential Art', cover: 'https://www.collectedcurios.com/images/CC_2011_Sequential_Art_Button.jpg', desc: 'Sequential Art webcomic.' },
  { key: '/battlebunnies.php', title: 'Battle Bunnies', cover: 'https://www.collectedcurios.com/images/CC_2011_Battle_Bunnies_Button.jpg', desc: 'Battle Bunnies webcomic.' },
  { key: '/spiderandscorpion.php', title: 'Spider and Scorpion', cover: 'https://www.collectedcurios.com/images/CC_2011_Spider_And_Scorpion_Button.jpg', desc: 'Spider and Scorpion webcomic.' }
];
function byKey(k) {
  for (var i = 0; i < MANGAS.length; i++) { if (MANGAS[i].key === k) { return MANGAS[i]; } }
  return null;
}
module.exports = {
  getPopularManga: async function (page) {
    var out = [];
    for (var i = 0; i < MANGAS.length; i++) {
      out.push({ key: MANGAS[i].key, title: MANGAS[i].title, coverUrl: MANGAS[i].cover });
    }
    return { mangas: out, hasNextPage: false };
  },
  getSearchManga: async function (page, query) {
    return await module.exports.getPopularManga(page);
  },
  getMangaDetail: async function (key) {
    var m = byKey(key) || { title: '', cover: '', desc: '' };
    return { key: key, title: m.title, coverUrl: m.cover, author: AUTHOR, description: m.desc, genre: '', status: 'ongoing' };
  },
  getChapterList: async function (key) {
    var doc = await H_doc(R_abs(key), { Referer: BASE + '/' });
    var n = NaN;
    var links = R_sel(doc, 'a[href]');
    for (var i = 0; i < links.length; i++) {
      if (R_selFirst(links[i], 'img[title=Last]')) {
        var h = links[i].attr('href');
        n = parseInt(h.substring(h.lastIndexOf('=') + 1), 10);
        break;
      }
    }
    if (isNaN(n)) {
      var inp = R_selFirst(doc, 'input[title=Jump to number]');
      if (inp) { n = parseInt(inp.attr('value'), 10); }
    }
    if (isNaN(n)) {
      for (var i2 = 0; i2 < links.length; i2++) {
        if (R_selFirst(links[i2], 'img[title="Back one"]')) {
          var h2 = links[i2].attr('href');
          n = parseInt(h2.substring(h2.lastIndexOf('=') + 1), 10) + 1;
          break;
        }
      }
    }
    if (isNaN(n) || n < 1) { n = 1; }
    var path = key.indexOf('/') === 0 ? key : R_path(key);
    var out = [];
    for (var c = 1; c <= n; c++) {
      out.push({ key: path + '?s=' + c, name: 'Chapter - ' + c, chapterNumber: c, dateUpload: 0, pages: 0, sortOrder: c - 1 });
    }
    return out;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), { Referer: BASE + '/' });
    var el;
    if (chapterKey.indexOf('sequentialart') >= 0) { el = R_selFirst(doc, '.w3-image'); }
    else { el = R_selFirst(doc, '#strip'); }
    return el ? [{ index: 0, url: el.absUrl('src') }] : [];
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
