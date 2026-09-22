// en/darkscience — dresdencodak Dark Science archive walk
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  return wrap(manifest, `
var DESC = 'Scientist Kimiko Ross has a problem: her money\\u2019s gone and a bank exploded her house. With no place else to go, she travels to Nephilopolis, the city of giants \\u2014 built from the ruins of an ancient war and a fading memory of tomorrow. Follow our cyborg hero as she attempts to survive the bureaucratic behemoth with a little \\u201chelp\\u201d from her \\u201cfriends.\\u201d And what exactly is Dark Science anyway?\\nSupport the comic on Patreon: https://www.patreon.com/dresdencodak';
function detailObj() {
  return {
    key: '/category/darkscience/',
    title: $.manifest.name,
    coverUrl: 'https://dresdencodak.com/wp-content/uploads/2019/03/DC_CastIcon_Kimiko.png',
    author: 'Sen (A. Senna Diaz)',
    description: DESC,
    genre: 'Science Fiction, Mystery, LGBT+',
    status: 'ongoing'
  };
}
module.exports = {
  getPopularManga: async function (page) {
    return { mangas: [{ key: '/category/darkscience/', title: $.manifest.name, coverUrl: detailObj().coverUrl }], hasNextPage: false };
  },
  getSearchManga: async function (page, query) {
    return { mangas: [], hasNextPage: false };
  },
  getMangaDetail: async function (key) { return detailObj(); },
  getChapterList: async function (key) {
    var chapters = [];
    var url = R_abs(key);
    var chLast = 0;
    while (url) {
      var doc = await H_doc(url, { Referer: BASE + '/' });
      var links = R_sel(doc, '#content article header > h2 > a');
      for (var i = 0; i < links.length; i++) {
        var chTitle = links[i].text();
        var chLink = links[i].absUrl('href') || links[i].attr('href');
        var m = chTitle.match(/Dark Science #(\\d+)/);
        var chNum = m ? parseFloat(m[1]) : (chLast + 0.01);
        chLast = chNum;
        var dm = chLink.match(/\\/(\\d{4}\\/\\d\\d\\/\\d\\d)\\//);
        var dv = dm ? Date.parse(dm[1].replace(/\\//g, '-')) : 0;
        chapters.push({ key: R_path(chLink), name: chTitle, chapterNumber: chNum, dateUpload: isNaN(dv) ? 0 : dv, pages: 0, sortOrder: 0 });
      }
      var next = R_selFirst(doc, '#nav-below .nav-previous > a');
      var nh = next ? (next.absUrl('href') || next.attr('href')) : '';
      url = nh && nh !== url ? nh : null;
    }
    chapters.reverse();
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), { Referer: BASE + '/' });
    var img = R_selFirst(doc, 'article.post img.aligncenter');
    var src = img ? (img.attr('src') || '') : '';
    return src ? [{ index: 0, url: R_abs(src) }] : [];
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
