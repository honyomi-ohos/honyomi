// id/wurmz — wurm.net Next.js RSC (bespoke)
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
var RSC_HDRS = { Referer: BASE + '/', Rsc: '1' };
function statusMap(v) {
  v = String(v || '').trim().toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'tamat' || v === 'completed') { return 'completed'; }
  if (v === 'hiatus') { return 'ongoing'; }
  if (v === 'drop') { return 'cancelled'; }
  return '';
}
// extract the JSON array following "key":[ in an RSC payload (bracket scan)
function rscArray(body, key) {
  var marker = '"' + key + '":[';
  var start = body.indexOf(marker);
  if (start < 0) { return null; }
  var i = start + marker.length - 1;
  var depth = 0;
  var inStr = false;
  var esc = false;
  while (i < body.length) {
    var c = body.charAt(i);
    if (inStr) {
      if (esc) { esc = false; }
      else if (c === '\\\\') { esc = true; }
      else if (c === '"') { inStr = false; }
    } else {
      if (c === '"') { inStr = true; }
      else if (c === '[') { depth++; }
      else if (c === ']') {
        depth--;
        if (depth === 0) {
          return JSON.parse(body.substring(start + marker.length - 1, i + 1));
        }
      }
    }
    i++;
  }
  return null;
}
module.exports = {
  getPopularManga: async function (page) {
    var doc = await H_doc(BASE + '/semua-komik' + (page > 1 ? '?page=' + page : ''), HDRS);
    var els = R_sel(doc, 'article.comic-card');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var link = R_selFirst(els[i], 'a');
      if (!link) { continue; }
      var title = link.attr('aria-label');
      if (!title) {
        var h2 = R_selFirst(els[i], 'h2');
        title = h2 ? h2.text() : '';
      }
      var img = R_selFirst(els[i], 'img');
      out.push({ key: R_path(link.absUrl('href')), title: title, coverUrl: img ? img.absUrl('src') : '' });
    }
    var hasNext = false;
    var links = R_sel(doc, 'a');
    for (var j = 0; j < links.length; j++) {
      if (links[j].text().indexOf('Berikutnya') >= 0) { hasNext = true; break; }
    }
    return { mangas: out, hasNextPage: hasNext };
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/semua-komik?q=' + encodeURIComponent(query) + (page > 1 ? '&page=' + page : '');
    var doc = await H_doc(u, HDRS);
    var els = R_sel(doc, 'article.comic-card');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var link = R_selFirst(els[i], 'a');
      if (!link) { continue; }
      var title = link.attr('aria-label');
      if (!title) {
        var h2 = R_selFirst(els[i], 'h2');
        title = h2 ? h2.text() : '';
      }
      var img = R_selFirst(els[i], 'img');
      out.push({ key: R_path(link.absUrl('href')), title: title, coverUrl: img ? img.absUrl('src') : '' });
    }
    var hasNext = false;
    var links = R_sel(doc, 'a');
    for (var j = 0; j < links.length; j++) {
      if (links[j].text().indexOf('Berikutnya') >= 0) { hasNext = true; break; }
    }
    return { mangas: out, hasNextPage: hasNext };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var details = null;
    var scripts = R_sel(doc, 'script[type="application/ld+json"]');
    for (var i = 0; i < scripts.length; i++) {
      try {
        var j = JSON.parse(scripts[i].text());
        if (j && j['@type'] === 'ComicSeries') { details = j; break; }
      } catch (e) { /* not json */ }
    }
    if (!details) { throw new Error('Gagal memproses detail komik'); }
    var desc = details.description || '';
    if (details.alternateName) {
      desc += (desc ? '\\n\\n' : '') + 'Nama Alternatif: ' + details.alternateName;
    }
    var genres = details.genre || [];
    return {
      key: mangaKey,
      title: details.name || '',
      coverUrl: details.image || '',
      author: details.author ? details.author.name : '',
      description: desc,
      genre: genres.join(', '),
      status: statusMap(H_firstText(doc, '.status-badge'))
    };
  },

  getChapterList: async function (mangaKey) {
    var body = await H_get(R_abs(mangaKey), RSC_HDRS);
    var chapters = rscArray(body, 'chapters');
    if (!chapters) { throw new Error('Gagal memproses daftar chapter'); }
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      out.push({
        key: mangaKey + '/chapter/' + c['chapter_label'],
        name: 'Chapter ' + c['chapter_label'],
        chapterNumber: parseFloat(c['chapter_sort']) || -1,
        dateUpload: 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var body = await H_get(R_abs(chapterKey), RSC_HDRS);
    var images = rscArray(body, 'images');
    if (!images) { throw new Error('Gagal memproses daftar gambar'); }
    var pages = [];
    for (var i = 0; i < images.length; i++) {
      pages.push({ index: i, url: images[i] });
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
