// en/darklegacycomics — static WoW webcomic with archive + specials
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  return wrap(manifest, `
var THUMB = 'https://images2.imgbox.com/5d/d8/BVxRdljH_o.png';
var AUTHOR = 'Arad Kedar (Keydar)';
var SPECIALS_DATE = 1399926480000;
var SPECIALS = { '1': 'Looking For Group', '2': 'Rover', '3': 'Fan Comic' };
module.exports = {
  getPopularManga: async function (page) {
    return {
      mangas: [
        { key: '/archive', title: 'Dark Legacy Comics', coverUrl: THUMB },
        { key: '/specials/1.php', title: 'Dark Legacy Comics Specials', coverUrl: THUMB }
      ],
      hasNextPage: false
    };
  },
  getSearchManga: async function (page, query) {
    return await module.exports.getPopularManga(page);
  },
  getMangaDetail: async function (key) {
    var isSpecials = key.indexOf('/specials/') === 0;
    return {
      key: key,
      title: isSpecials ? 'Dark Legacy Comics Specials' : 'Dark Legacy Comics',
      coverUrl: THUMB,
      author: AUTHOR,
      description: '',
      genre: '',
      status: isSpecials ? 'completed' : 'ongoing'
    };
  },
  getChapterList: async function (key) {
    var out = [];
    if (key === '/archive') {
      var doc = await H_doc(R_abs(key), { Referer: BASE + '/' });
      var items = R_sel(doc, '.archive_link');
      for (var i = 0; i < items.length; i++) {
        var idxEl = R_selFirst(items[i], '.index');
        var dateEl = R_selFirst(items[i], '.date');
        var nameEl = R_selFirst(items[i], '.name');
        if (!idxEl) { continue; }
        var index = idxEl.text();
        var date = dateEl ? R_ownText(dateEl) : '';
        var dv;
        if (date === 'Sep 20') { dv = 1442696400000; }
        else { dv = Date.parse(date) || 0; }
        var nr = parseFloat(index);
        out.push({
          key: '/' + index,
          name: '#' + index + ': ' + (nameEl ? nameEl.text() : ''),
          chapterNumber: isNaN(nr) ? -1 : nr,
          dateUpload: dv,
          pages: 0,
          sortOrder: 0
        });
      }
      out.reverse();
    } else {
      for (var k in SPECIALS) {
        var nr2 = parseFloat(k);
        out.push({ key: '/specials/' + k, name: SPECIALS[k], chapterNumber: isNaN(nr2) ? -1 : nr2, dateUpload: SPECIALS_DATE, pages: 0, sortOrder: 0 });
      }
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), { Referer: BASE + '/' });
    var imgs = R_sel(doc, '.comic > img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
