// en/darthsdroids — Darths & Droids archive-table webcomic
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return { ok: true, config: {}, warnings: ['archive footer date parsing approximated for dateless archives'] };
}

export function generate(manifest) {
  return wrap(manifest, `
var THUMBS = ['QuiGon', 'Anakin2', 'ObiWan3', 'JarJar2', 'Leia4', 'Han5', 'Luke6', 'Cassian', 'C3PO4', 'Finn7', 'Han4', 'Hux8'];
var AUTHOR = 'David Morgan-Mar & Co.';
var DESC = "What if Star Wars as we know it didn't exist, but instead the plot of the movies was being made up on the spot by players of a Tabletop Game? Well, for one, the results might actually make a lot more sense, from an out-of-story point of view.";
function thumbFor(n) { return BASE + '/cast/' + (THUMBS[n] || 'Vader4') + '.jpg'; }
var MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };
function parseDate(v) {
  var m = String(v || '').match(/([A-Za-z]{3})\\s+(\\d+),\\s+(\\d{4})/);
  if (!m) { return Date.parse(v) || 0; }
  var mo = MONTHS[m[1].toLowerCase()];
  if (mo === undefined) { return 0; }
  return Date.UTC(parseInt(m[3], 10), mo, parseInt(m[2], 10));
}
async function archiveMangas() {
  var doc = await H_doc(BASE + '/archive.html', { Referer: BASE + '/' });
  var rows = R_sel(doc, 'div.text > table.text > tbody > tr');
  var mangas = [];
  var nextTitle = $.manifest.name;
  var nth = 0;
  for (var i = 0; i < rows.length; i++) {
    var th = R_selFirst(rows[i], 'th');
    if (th) { nextTitle = $.manifest.name + ' ' + th.text(); continue; }
    var arch = R_selFirst(rows[i], 'td[colspan="3"] > a');
    var href = arch ? arch.absUrl('href') : '';
    if (href) {
      mangas.push({ key: R_path(href), title: nextTitle, coverUrl: thumbFor(nth++), status: 'completed' });
    } else {
      mangas.push({ key: '/archive.html', title: nextTitle, coverUrl: thumbFor(nth), status: 'ongoing' });
      break;
    }
  }
  return mangas;
}
function detailOf(m) {
  return { key: m.key, title: m.title, coverUrl: m.coverUrl, author: AUTHOR, description: DESC, genre: 'Campaign Comic, Comedy, Space Opera, Science Fiction', status: m.status };
}
module.exports = {
  getPopularManga: async function (page) {
    var list = await archiveMangas();
    var out = [];
    for (var i = 0; i < list.length; i++) { out.push({ key: list[i].key, title: list[i].title, coverUrl: list[i].coverUrl }); }
    return { mangas: out, hasNextPage: false };
  },
  getSearchManga: async function (page, query) {
    return { mangas: [], hasNextPage: false };
  },
  getMangaDetail: async function (key) {
    var list = await archiveMangas();
    for (var i = 0; i < list.length; i++) {
      if (list[i].key === key) { return detailOf(list[i]); }
    }
    return { key: key, title: '', coverUrl: '', author: AUTHOR, description: DESC, genre: 'Campaign Comic, Comedy, Space Opera, Science Fiction', status: '' };
  },
  getChapterList: async function (key) {
    var doc = await H_doc(R_abs(key), { Referer: BASE + '/' });
    var pageDate = 0;
    var ital = R_sel(doc, 'br + i');
    for (var t = 0; t < ital.length; t++) {
      var m = ital[t].text().match(/Published:\\s+(.+)/);
      if (m) { pageDate = Date.parse(m[1].replace(/;/, '')) || 0; break; }
    }
    var rows = R_sel(doc, 'div.text > table.text > tbody > tr');
    var out = [];
    var i = 0;
    for (var r = 0; r < rows.length; r++) {
      var tds = R_sel(rows[r], 'td');
      if (!tds.length) { continue; }
      var anchor = tds.length > 2 ? R_selFirst(tds[2], 'a') : null;
      var dv = 0;
      if (anchor) {
        dv = parseDate(tds[0].text());
      } else {
        var anyColspan = false;
        for (var c = 0; c < tds.length; c++) { if (tds[c].attr('colspan')) { anyColspan = true; break; } }
        if (anyColspan) { continue; }
        anchor = tds.length > 0 ? R_selFirst(tds[0], 'a') : null;
        dv = pageDate;
      }
      if (!anchor) { continue; }
      var href = anchor.absUrl('href');
      if (!href) { continue; }
      out.push({ key: R_path(href), name: anchor.text(), chapterNumber: i++, dateUpload: dv, pages: 0, sortOrder: 0 });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), { Referer: BASE + '/' });
    var imgs = R_sel(doc, 'div.center img');
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
