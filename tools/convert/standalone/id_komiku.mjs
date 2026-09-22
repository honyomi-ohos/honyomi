// id/komiku — komiku.org list API + web reader (bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['filters (genre/type/status) not supported; plain search only'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var API = 'https://api.komiku.org';
var HDRS = { 'Accept-Language': 'id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7', Referer: BASE + '/' };
function noQuery(u) {
  return String(u || '').split('?')[0];
}
function parseRelativeDate(v) {
  var parts = String(v || '').replace(' lalu', '').trim().split(' ');
  if (parts.length < 2) { return 0; }
  var amount = parseInt(parts[0], 10);
  if (isNaN(amount)) { return 0; }
  var unit = parts[1];
  var ms = { 'detik': 1000, 'menit': 60000, 'jam': 3600000, 'hari': 86400000, 'minggu': 604800000, 'bulan': 2592000000, 'tahun': 31536000000 }[unit];
  return ms ? Date.now() - amount * ms : 0;
}
function parseChapterDate(v) {
  v = String(v || '').trim();
  if (!v) { return 0; }
  if (v.indexOf('lalu') >= 0) { return parseRelativeDate(v); }
  var m = v.match(/^(\\d{1,2})\\/(\\d{1,2})\\/(\\d{4})$/);
  if (m) { return Date.UTC(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10)) - 7 * 3600000; }
  return R_date(v);
}
async function mangaListParse(u) {
  var doc = await H_doc(u, HDRS);
  var items = R_sel(doc, 'div.bge');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var a = R_selFirst(el, 'a:has(h3)');
    if (!a) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    var h3 = R_selFirst(el, 'h3');
    var img = R_selFirst(el, 'img');
    out.push({ key: R_path(href), title: h3 ? h3.text() : '', coverUrl: img ? noQuery(img.absUrl('src')) : '' });
  }
  var hasNext = !!R_selFirst(doc, 'span[hx-get]') || out.length >= 10;
  return { mangas: out, hasNextPage: hasNext };
}
module.exports = {
  getPopularManga: async function (page) {
    var u = API + '/other/hot/' + (page > 1 ? 'page/' + page + '/' : '') + '?orderby=meta_value_num';
    return mangaListParse(u);
  },

  getSearchManga: async function (page, query) {
    var u = API + '/manga/' + (page > 1 ? 'page/' + page + '/' : '');
    if (query) { u += (u.indexOf('?') >= 0 ? '&' : '?') + 's=' + encodeURIComponent(query); }
    return mangaListParse(u);
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var desc = H_texts(doc, '#Sinopsis > p, p.desc[itemprop=description]');
    var alt = '';
    var rows = R_sel(doc, 'table.inftable tr');
    for (var i = 0; i < rows.length; i++) {
      var t = rows[i].text();
      if (t.indexOf('Judul Indonesia') >= 0 || t.indexOf('Judul Alternatif') >= 0) {
        var tds = R_sel(rows[i], 'td');
        if (tds.length >= 2) { alt = tds[1].text(); }
        if (alt) { break; }
      }
    }
    if (alt) { desc += (desc ? '\\n\\n' : '') + 'Judul Alternatif: ' + alt; }
    var author = '';
    var tds2 = R_sel(doc, 'table.inftable td');
    for (var j = 0; j < tds2.length; j++) {
      var lbl = tds2[j].text();
      if (/Pengarang|Komikus|Author/.test(lbl) && tds2[j + 1]) {
        author = tds2[j + 1].text();
        break;
      }
    }
    var status = '';
    for (var k = 0; k < tds2.length; k++) {
      if (tds2[k].text().indexOf('Status') >= 0 && tds2[k + 1]) {
        var s = tds2[k + 1].text().toLowerCase();
        if (s.indexOf('ongoing') >= 0 || s.indexOf('on going') >= 0) { status = 'ongoing'; }
        else if (s.indexOf('end') >= 0 || s.indexOf('completed') >= 0 || s.indexOf('tamat') >= 0) { status = 'completed'; }
        break;
      }
    }
    var img = R_selFirst(doc, 'div.ims > img, img[itemprop=image]');
    return {
      key: mangaKey,
      title: '',
      coverUrl: img ? noQuery(img.absUrl('src')) : '',
      author: author,
      description: desc,
      genre: H_texts(doc, 'ul.genre li.genre a span'),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var rows = R_sel(doc, '#Daftar_Chapter tr:has(td.judulseries)');
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var a = R_selFirst(rows[i], 'a');
      if (!a) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      var dt = R_selFirst(rows[i], 'td.tanggalseries');
      out.push({
        key: R_path(href),
        name: a.text(),
        chapterNumber: -1,
        dateUpload: dt ? parseChapterDate(dt.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), HDRS);
    var imgs = R_sel(doc, '#Baca_Komik img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].absUrl('src');
      if (!src || src.indexOf('komiku-promosi') >= 0) { continue; }
      pages.push({ index: pages.length, url: src });
    }
    return pages;
  },

  imageHeaders: function () {
    return {
      Referer: BASE + '/',
      Accept: 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Sec-Fetch-Dest': 'image',
      'Sec-Fetch-Mode': 'no-cors'
    };
  }
};
`);
}
