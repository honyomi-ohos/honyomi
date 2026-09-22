// en/duskscans — duskscans.com Next.js RSC site with JSON API
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['premium/locked chapters hidden (upstream default); filters not supported'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var HDRS = { Referer: BASE + '/' };
async function getCatalog() {
  var text = await H_get(BASE + '/api/manga', HDRS);
  return JSON.parse(text);
}
function toManga(m) {
  var st = m.status === 'Ongoing' ? 'ongoing' : (m.status === 'Completed' ? 'completed' : (m.status === 'Hiatus' ? 'hiatus' : ''));
  return {
    key: '/series/' + m.slug,
    title: m.title || '',
    coverUrl: m.cover || '',
    author: m.author || '',
    description: m.description || '',
    genre: (m.genres || []).join(', '),
    status: st
  };
}
function extractRscSeries(text) {
  var i = text.indexOf('{"initialManga"');
  if (i < 0) { return null; }
  var depth = 0, inStr = false, esc = false;
  for (var j = i; j < text.length; j++) {
    var c = text.charAt(j);
    if (inStr) {
      if (esc) { esc = false; }
      else if (c === '\\\\') { esc = true; }
      else if (c === '"') { inStr = false; }
    } else {
      if (c === '"') { inStr = true; }
      else if (c === '{') { depth++; }
      else if (c === '}') { depth--; if (depth === 0) { return JSON.parse(text.substring(i, j + 1)); } }
    }
  }
  return null;
}
async function getSeriesPage(slug) {
  var text = await H_get(BASE + '/series/' + slug, { Referer: BASE + '/', RSC: '1' });
  return extractRscSeries(text);
}
function isLocked(c) {
  if (c.requiresLogin) { return true; }
  if (!c.price || c.price <= 0) { return false; }
  if (!c.freeDate) { return true; }
  var t = Date.parse(c.freeDate);
  return isNaN(t) || t > Date.now();
}
module.exports = {
  getPopularManga: async function (page) {
    var cat = await getCatalog();
    cat.sort(function (a, b) { return (b.views || 0) - (a.views || 0); });
    return { mangas: cat.map(toManga), hasNextPage: false };
  },
  getSearchManga: async function (page, query) {
    var cat = await getCatalog();
    var q = String(query || '').toLowerCase();
    var filtered = cat.filter(function (m) {
      return !q || (m.title || '').toLowerCase().indexOf(q) >= 0 || (m.alternativeTitle || '').toLowerCase().indexOf(q) >= 0;
    });
    return { mangas: filtered.map(toManga), hasNextPage: false };
  },
  getMangaDetail: async function (key) {
    var slug = key.replace(/^\\/series\\//, '');
    var series = await getSeriesPage(slug);
    if (series && series.initialManga) { return toManga(series.initialManga); }
    var cat = await getCatalog();
    for (var i = 0; i < cat.length; i++) {
      if (cat[i].slug === slug) { return toManga(cat[i]); }
    }
    throw new Error('Series not found');
  },
  getChapterList: async function (key) {
    var slug = key.replace(/^\\/series\\//, '');
    var series = await getSeriesPage(slug);
    if (!series) { throw new Error('Series not found'); }
    var chapters = series.initialChapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      if (isLocked(c)) { continue; }
      var numberStr = String(c.number).replace(/\\.0$/, '');
      var name = c.title || ('Chapter ' + numberStr);
      var dv = Date.parse(c.releaseDate || '');
      out.push({
        key: '/chapter/' + c.id,
        name: name,
        chapterNumber: c.number,
        dateUpload: isNaN(dv) ? 0 : dv,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },
  getPageList: async function (chapterKey) {
    var id = chapterKey.replace(/^\\/chapter\\//, '');
    var text = await H_get(BASE + '/api/chapter/' + id, HDRS);
    var d = JSON.parse(text);
    var urls = typeof d.pages === 'string' ? JSON.parse(d.pages) : (d.pages || []);
    var pages = [];
    for (var i = 0; i < urls.length; i++) {
      pages.push({ index: i, url: urls[i] });
    }
    return pages;
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
