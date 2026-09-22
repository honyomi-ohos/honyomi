// it/animegdrclub — agcscanlation.it custom PHP site (bespoke)
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
var HDRS = { Referer: BASE + '/' };
function keyFromHref(href) {
  var u = new URL(href, BASE);
  return u.pathname + u.search;
}
function statusFromText(text) {
  if (text.indexOf('In Corso') >= 0) { return 'ongoing'; }
  if (text.indexOf('Concluso') >= 0) { return 'completed'; }
  if (text.indexOf('Interrotto') >= 0) { return 'hiatus'; }
  return '';
}
async function serieMangas(query) {
  var doc = await H_doc(BASE + '/serie.php', HDRS);
  var els = R_sel(doc, 'div.manga');
  var out = [];
  var q = (query || '').toLowerCase();
  for (var i = 0; i < els.length; i++) {
    var link = R_selFirst(els[i], 'a.linkalmanga');
    var span = R_selFirst(els[i], 'div.nomeserie > span');
    if (!link || !span) { continue; }
    var title = span.text().trim();
    if (q && title.toLowerCase().indexOf(q) < 0) { continue; }
    var img = R_selFirst(els[i], 'img');
    out.push({
      key: keyFromHref(link.absUrl('href')),
      title: title,
      coverUrl: img ? img.absUrl('src') : ''
    });
  }
  return out;
}
module.exports = {
  getPopularManga: async function () {
    return { mangas: await serieMangas(''), hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    return { mangas: await serieMangas(query), hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var genres = [];
    var gas = R_sel(doc, '.tabellaalta span.generi > a');
    for (var i = 0; i < gas.length; i++) { genres.push(gas[i].text()); }
    var desc = '';
    var trama = R_selFirst(doc, 'span.trama');
    if (trama) {
      var t = trama.text();
      var p = t.indexOf('Trama: ');
      desc = p >= 0 ? t.substring(p + 7) : t;
    }
    var title = H_firstText(doc, 'div.nomeserie > span');
    var cover = R_selFirst(doc, '.tabellaalta .immagine img');
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover ? cover.absUrl('src') : '',
      author: '',
      description: desc.trim(),
      genre: genres.join(', '),
      status: statusFromText(H_firstText(doc, '.tabellaalta'))
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var els = R_sel(doc, '.capitoli_cont > a');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var href = els[i].absUrl('href');
      if (!href) { continue; }
      href = href.replace('reader', 'readerr');
      var name = els[i].text().trim();
      var num = parseFloat(name.replace('Capitolo', '').trim());
      out.push({
        key: keyFromHref(href),
        name: name,
        chapterNumber: isNaN(num) ? 0 : num,
        dateUpload: 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), HDRS);
    var nomeEl = R_selFirst(doc, '#nomemanga');
    var capEl = R_selFirst(doc, '.numcap');
    var maxEl = R_selFirst(doc, '.maxpag');
    var nomemanga = nomeEl ? nomeEl.attr('class') : '';
    var numcap = capEl ? capEl.text().trim() : '';
    var maxpag = maxEl ? parseInt(maxEl.text(), 10) : NaN;
    if (nomemanga && numcap && !isNaN(maxpag) && maxpag > 0) {
      var pages = [];
      for (var i = 1; i <= maxpag; i++) {
        pages.push({ index: i - 1, url: R_abs(nomemanga + '/cap.' + numcap + '/' + i + '.jpg') });
      }
      return pages;
    }
    var imgs = R_sel(doc, 'img.corrente');
    var out = [];
    for (var j = 0; j < imgs.length; j++) {
      out.push({ index: j, url: imgs[j].absUrl('src') });
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
