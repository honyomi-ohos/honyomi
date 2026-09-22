// id/pramramadhan — pramramadhan.com custom PHP site (bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['filters not supported; plain search only'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var MON = { 'januari': 0, 'februari': 1, 'maret': 2, 'april': 3, 'mei': 4, 'juni': 5, 'juli': 6, 'agustus': 7, 'september': 8, 'oktober': 9, 'november': 10, 'desember': 11 };
function parseChapterDate(v) {
  v = String(v || '').trim();
  if (!v) { return 0; }
  var rel = v.toLowerCase().replace('lalu', '').trim().split(' ');
  if (rel.length === 2) {
    var amount = parseInt(rel[0], 10);
    var ms = { 'detik': 1000, 'menit': 60000, 'jam': 3600000, 'hari': 86400000, 'minggu': 604800000, 'bulan': 2592000000, 'tahun': 31536000000 }[rel[1]];
    if (!isNaN(amount) && ms) { return Date.now() - amount * ms; }
  }
  var m = v.match(/^(\\d{1,2})\\s+([A-Za-z]+)\\s+(\\d{4})$/);
  if (m && MON[m[2].toLowerCase()] !== undefined) {
    return Date.UTC(parseInt(m[3], 10), MON[m[2].toLowerCase()], parseInt(m[1], 10)) - 7 * 3600000;
  }
  return R_date(v);
}
async function listPage(page, params) {
  var doc = await H_doc(BASE + '/search.php?' + params + '&page=' + page);
  var cards = R_sel(doc, 'a.result-card');
  var out = [];
  for (var i = 0; i < cards.length; i++) {
    var a = cards[i];
    var href = a.attr('href');
    if (!href) { continue; }
    var title = H_firstText(a, 'div.result-title');
    var img = R_selFirst(a, 'div.result-cover img');
    out.push({ key: R_path(href), title: title, coverUrl: img ? img.absUrl('src') : '' });
  }
  return { mangas: out, hasNextPage: false };
}
function tagRowValue(doc, label) {
  var rows = R_sel(doc, '.tag-row');
  for (var i = 0; i < rows.length; i++) {
    var lbl = R_selFirst(rows[i], '.tag-label');
    if (lbl && lbl.text().toLowerCase().indexOf(label.toLowerCase()) >= 0) {
      var pill = R_selFirst(rows[i], '.tag-pill');
      return pill ? pill.text() : '';
    }
  }
  return '';
}
module.exports = {
  getPopularManga: async function (page) { return listPage(page, 'sort=popular'); },
  getSearchManga: async function (page, query) {
    return listPage(page, 'sort=newest&q=' + encodeURIComponent(query || ''));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var cover = R_selFirst(doc, 'div.series-cover img');
    var desc = R_selFirst(doc, 'p.series-desc');
    var genres = [];
    var rows = R_sel(doc, '.tag-row');
    for (var i = 0; i < rows.length; i++) {
      var lbl = R_selFirst(rows[i], '.tag-label');
      if (lbl && lbl.text().toLowerCase().indexOf('genre') >= 0) {
        var pills = R_sel(rows[i], '.tag-list a.tag-pill');
        for (var p = 0; p < pills.length; p++) { genres.push(pills[p].text()); }
      }
    }
    var st = tagRowValue(doc, 'status').toLowerCase();
    return {
      key: mangaKey,
      title: H_firstText(doc, 'h1.series-title'),
      coverUrl: cover ? cover.absUrl('src') : '',
      author: tagRowValue(doc, 'author'),
      description: desc ? desc.text() : '',
      genre: genres.join(', '),
      status: st === 'ongoing' ? 'ongoing' : (st === 'completed' ? 'completed' : '')
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var cards = R_sel(doc, 'div.chapter-grid a.chapter-card');
    var out = [];
    for (var i = 0; i < cards.length; i++) {
      var a = cards[i];
      var href = a.attr('href');
      if (!href) { continue; }
      var title = H_firstText(a, 'div.chapter-title');
      var sub = H_firstText(a, 'div.chapter-sub');
      if (sub) { title += ' - ' + sub; }
      var time = R_selFirst(a, 'div.chapter-time');
      out.push({
        key: R_path(href),
        name: title,
        chapterNumber: -1,
        dateUpload: time ? parseChapterDate(time.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey));
    var imgs = R_sel(doc, 'div.reader-container img.page');
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
