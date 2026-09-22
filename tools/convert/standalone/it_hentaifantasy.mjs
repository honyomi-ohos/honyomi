// it/hentaifantasy — hentaifantasy.it (bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['tag filters not supported; plain search only (min 3 chars)'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var HDRS = { Referer: BASE + '/' };
function hasNextByNext(doc) {
  var els = R_sel(doc, 'div.next a.gbutton');
  for (var i = 0; i < els.length; i++) {
    if (els[i].text().indexOf('\\u00BB') >= 0) { return true; }
  }
  return false;
}
function parseChapterDate(v) {
  v = String(v || '').trim();
  if (v === 'Oggi') { return Date.now(); }
  if (v === 'Ieri') { return Date.now() - 86400000; }
  var m = v.match(/^(\\d{4})\\.(\\d{2})\\.(\\d{2})$/);
  if (m) { return Date.UTC(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10)); }
  return 0;
}
async function parseList(doc) {
  var out = [];
  var els = R_sel(doc, 'article.element');
  for (var i = 0; i < els.length; i++) {
    var thumb = R_selFirst(els[i], 'a.thumb');
    var title = R_selFirst(els[i], 'div.title > a');
    if (!thumb || !title) { continue; }
    var img = R_selFirst(els[i], 'img.cover');
    out.push({ key: R_path(thumb.absUrl('href')), title: title.attr('title') || title.text(), coverUrl: img ? img.absUrl('src') : '' });
  }
  if (out.length) { return out; }
  var groups = R_sel(doc, 'div.group');
  for (var j = 0; j < groups.length; j++) {
    var ta = R_selFirst(groups[j], 'div.title > a');
    if (!ta) { continue; }
    var pv = R_selFirst(groups[j], 'img.preview');
    out.push({ key: R_path(ta.absUrl('href')), title: ta.attr('title') || ta.text(), coverUrl: pv ? pv.absUrl('src') : '' });
  }
  return out;
}
module.exports = {
  getPopularManga: async function (page) {
    var doc = await H_doc(BASE + '/most_downloaded/' + page + '/', HDRS);
    return { mangas: await parseList(doc), hasNextPage: hasNextByNext(doc) };
  },

  getSearchManga: async function (page, query) {
    if (String(query || '').length < 3) {
      throw new Error('Inserisci almeno tre caratteri');
    }
    var doc = await $.html.parse(await $.http.post(BASE + '/search', 'search=' + encodeURIComponent(query), {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Referer': BASE + '/'
    }), BASE);
    return { mangas: await parseList(doc), hasNextPage: hasNextByNext(doc) };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var genres = [];
    var rows = R_sel(doc, 'div.meta-row');
    var author = '';
    for (var i = 0; i < rows.length; i++) {
      var key = R_selFirst(rows[i], 'div.meta-key');
      if (!key) { continue; }
      var kt = key.text();
      if (kt === 'Autore') {
        var av = R_selFirst(rows[i], 'div.meta-val > a');
        author = av ? av.text() : '';
      } else if (kt === 'Genere' || kt === 'Tipo') {
        var vals = R_sel(rows[i], 'div.meta-val > a');
        for (var j = 0; j < vals.length; j++) { genres.push(vals[j].text()); }
      }
    }
    var cover = R_selFirst(doc, 'section.comic-hero img');
    return {
      key: mangaKey,
      title: H_firstText(doc, 'section.comic-hero h1, h1'),
      coverUrl: cover ? cover.absUrl('src') : '',
      author: author,
      description: H_firstText(doc, 'div.desc-text'),
      genre: genres.join(', '),
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var els = R_sel(doc, 'article.chapter-card');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var anchor = R_selFirst(els[i], 'div.chapter-card__title > a');
      if (!anchor) { continue; }
      var meta = R_selFirst(els[i], 'div.chapter-card__meta');
      var dateStr = '';
      if (meta) {
        var own = R_ownText(meta);
        var c = own.lastIndexOf(', ');
        dateStr = c >= 0 ? own.substring(c + 2).trim() : own.trim();
      }
      out.push({
        key: R_path(anchor.absUrl('href')),
        name: anchor.text(),
        chapterNumber: -1,
        dateUpload: parseChapterDate(dateStr),
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var body = await H_get(R_abs(chapterKey), HDRS);
    var pages = [];
    var re = /"url":"(.*?)"/g;
    var m;
    while ((m = re.exec(body)) !== null) {
      pages.push({ index: pages.length, url: m[1].replace(/\\\\\\//g, '/') });
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
