// id/komikindoid — komikindo.id WordPress theme (bespoke HTML scraper)
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
function parseChapterDate(date) {
  var v = String(date || '').trim();
  if (!v) { return 0; }
  if (v.indexOf('yang lalu') >= 0) {
    var m = v.split(' ')[0];
    var amount = parseInt(m, 10);
    if (isNaN(amount)) { return 0; }
    if (v.indexOf('detik') >= 0) { return Date.now() - amount * 1000; }
    if (v.indexOf('menit') >= 0) { return Date.now() - amount * 60000; }
    if (v.indexOf('jam') >= 0) { return Date.now() - amount * 3600000; }
    if (v.indexOf('hari') >= 0) { return Date.now() - amount * 86400000; }
    if (v.indexOf('minggu') >= 0) { return Date.now() - amount * 604800000; }
    if (v.indexOf('bulan') >= 0) { return Date.now() - amount * 2592000000; }
    if (v.indexOf('tahun') >= 0) { return Date.now() - amount * 31536000000; }
    return 0;
  }
  return R_date(v);
}
function pagePath(page) { return page > 1 ? 'page/' + page + '/' : ''; }
async function listPage(page, extra) {
  var u = BASE + '/daftar-manga/' + pagePath(page) + (extra || '');
  var doc = await H_doc(u);
  var items = R_sel(doc, 'div.animepost');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var a = R_selFirst(el, 'div.animposx > a');
    if (!a) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    var title = H_firstText(el, 'div.tt h3');
    if (!title) { title = a.attr('title').replace(/^Komik/, '').trim(); }
    var img = R_selFirst(el, 'div.limit img');
    out.push({ key: R_path(href), title: title, coverUrl: img ? (img.absUrl('data-lazy-src') || img.absUrl('data-src') || img.absUrl('src')) : '' });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, 'a.next.page-numbers') };
}
module.exports = {
  getPopularManga: async function (page) { return listPage(page, '?order=popular'); },
  getSearchManga: async function (page, query) {
    return listPage(page, query ? '?title=' + encodeURIComponent(query) : '');
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var title = H_firstText(doc, 'h1.entry-title').replace(/^Komik/, '').trim();
    // author/artist: span text minus its leading bold label
    var author = '';
    var artist = '';
    var spans = R_sel(doc, '.infox .spe span');
    for (var i = 0; i < spans.length; i++) {
      var t = spans[i].text();
      var b = R_selFirst(spans[i], 'b');
      var label = b ? b.text() : '';
      if (/Pengarang/i.test(label)) { author = t.substring(t.indexOf(label) + label.length).trim(); }
      if (/Ilustrator/i.test(label)) { artist = t.substring(t.indexOf(label) + label.length).trim(); }
    }
    var genres = [];
    var gels = R_sel(doc, '.infox .genre-info a, .infox .spe span a');
    for (var g = 0; g < gels.length; g++) {
      var gt = gels[g].text();
      if (gt && genres.indexOf(gt) < 0) { genres.push(gt); }
    }
    var statusRaw = '';
    var speSpans = R_sel(doc, '.infox > .spe > span');
    if (speSpans.length >= 2) {
      var s = speSpans[1].text().toLowerCase();
      if (s.indexOf('berjalan') >= 0 || s.indexOf('ongoing') >= 0) { statusRaw = 'ongoing'; }
      else if (s.indexOf('tamat') >= 0 || s.indexOf('completed') >= 0) { statusRaw = 'completed'; }
    }
    var desc = '';
    var descEl = R_selFirst(doc, 'div.desc > .entry-content.entry-content-single');
    if (descEl) {
      var ps = R_sel(descEl, 'p');
      var parts = [];
      for (var p = 0; p < ps.length; p++) {
        if (ps[p].text()) { parts.push(ps[p].text()); }
      }
      var main = parts.join(' ');
      var idx = main.toLowerCase().indexOf('bercerita tentang ');
      if (idx >= 0) { main = main.substring(idx + 'bercerita tentang '.length); }
      desc = main;
    }
    if (speSpans.length >= 1 && speSpans[0].text()) {
      desc += (desc ? '\\n\\n' : '') + speSpans[0].text();
    }
    var thumb = R_selFirst(doc, '.thumb > img:nth-child(1), .thumb img');
    var cover = thumb ? (thumb.absUrl('data-lazy-src') || thumb.absUrl('data-src') || thumb.absUrl('src')) : '';
    cover = cover.split('?')[0];
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: author,
      description: desc,
      genre: genres.join(', '),
      status: statusRaw
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var items = R_sel(doc, '#chapter_list li');
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      var a = R_selFirst(el, '.lchx a');
      if (!a) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      var name = a.text();
      var numM = name.match(/Chapter\\s+([0-9]+(?:\\.[0-9]+)?)/i);
      var dt = R_selFirst(el, '.dt a');
      out.push({
        key: R_path(href),
        name: name,
        chapterNumber: numM ? parseFloat(numM[1]) : -1,
        dateUpload: dt ? parseChapterDate(dt.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey));
    var imgs = R_sel(doc, 'div.img-landmine img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var el = imgs[i];
      var onerror = el.attr('onError');
      var u;
      if (onerror.indexOf("src='") >= 0) {
        u = onerror.substring(onerror.indexOf("src='") + 5);
        u = u.split("';")[0];
      } else {
        u = el.absUrl('data-lazy-src') || el.absUrl('data-src') || el.absUrl('src');
      }
      if (u) { pages.push({ index: pages.length, url: R_abs(u) }); }
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
