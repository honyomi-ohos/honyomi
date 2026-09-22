// id/komikucom — 01.komiku.asia JSON API (/api/v2), bespoke
// NOTE: upstream carries the comic id in SManga.memo; this port re-fetches
// /comics/<slug> to recover the id where needed.
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
var API = 'https://01.komiku.asia/api/v2';
var HDRS = { Accept: 'application/json, text/plain, */*', 'Accept-Language': 'id-ID,id;q=0.9,en-US;q=0.8', Referer: BASE + '/' };
function statusMap(v) {
  v = String(v || '').toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  if (v === 'hiatus') { return 'hiatus'; }
  if (v === 'cancelled' || v === 'canceled') { return 'cancelled'; }
  return '';
}
function toManga(v) {
  var authors = [];
  if (v.author) { authors.push(v.author); }
  if (v.artist) { authors.push(v.artist); }
  return {
    key: '/manga/' + v.slug,
    title: v.title || '',
    coverUrl: v.coverUrl || '',
    author: authors.join(', '),
    description: v.synopsis || '',
    genre: (v.genres || []).join(', '),
    status: statusMap(v.comicStatus || v.status)
  };
}
var MONTHS = { 'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'mei': 5, 'may': 5, 'jun': 6, 'jul': 7, 'agu': 8, 'aug': 8, 'sep': 9, 'okt': 10, 'oct': 10, 'nov': 11, 'des': 12, 'dec': 12 };
function parseLabel(label) {
  var v = String(label || '');
  if (!v) { return 0; }
  var now = Date.now();
  if (v.indexOf('baru saja') >= 0) { return now; }
  var digits = v.replace(/[^0-9]/g, '');
  var num = digits ? parseInt(digits, 10) : 0;
  if (v.indexOf('menit') >= 0) { return now - num * 60000; }
  if (v.indexOf('jam') >= 0) { return now - num * 3600000; }
  if (v.indexOf('hari') >= 0) { return now - num * 86400000; }
  var parts = v.split(' ');
  if (parts.length === 3) {
    var day = parseInt(parts[0], 10);
    var month = MONTHS[parts[1].toLowerCase()];
    var year = parseInt(parts[2], 10);
    if (day && month && year) { return Date.UTC(year, month - 1, day) - 7 * 3600000; }
  }
  return 0;
}
async function comicIdBySlug(mangaKey) {
  var slug = String(mangaKey).replace(/^\\/manga\\//, '');
  var d = JSON.parse(await H_get(API + '/comics/' + slug, HDRS));
  return d.id;
}
module.exports = {
  getPopularManga: async function (page) {
    var d = JSON.parse(await H_get(API + '/comics?sort=popular&page=' + page, HDRS));
    var out = [];
    var items = d.items || [];
    for (var i = 0; i < items.length; i++) {
      out.push({ key: '/manga/' + items[i].slug, title: items[i].title || '', coverUrl: items[i].coverUrl || '' });
    }
    return { mangas: out, hasNextPage: (d.page || 0) < (d.totalPages || 0) };
  },

  getSearchManga: async function (page, query) {
    var u = query ? API + '/comics/search?q=' + encodeURIComponent(query) + '&page=' + page : API + '/comics?page=' + page;
    var d = JSON.parse(await H_get(u, HDRS));
    var items = query ? d : (d.items || []);
    var out = [];
    for (var i = 0; i < items.length; i++) {
      out.push({ key: '/manga/' + items[i].slug, title: items[i].title || '', coverUrl: items[i].coverUrl || '' });
    }
    return { mangas: out, hasNextPage: items.length > 0 };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/manga\\//, '');
    var d = JSON.parse(await H_get(API + '/comics/' + slug, HDRS));
    return toManga(d);
  },

  getChapterList: async function (mangaKey) {
    var comicId = await comicIdBySlug(mangaKey);
    var list = JSON.parse(await H_get(API + '/comics/' + comicId + '/chapters', HDRS));
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var name = c.title || ('Chapter ' + (c.n != null ? c.n : ''));
      out.push({
        key: '/' + comicId + '/' + c.id,
        name: name,
        chapterNumber: c.n != null ? c.n : 0,
        dateUpload: c.releasedAt || parseLabel(c.releasedLabel),
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = String(chapterKey).split('/').filter(function (p) { return p; });
    var d = JSON.parse(await H_get(API + '/comics/' + parts[0] + '/chapters/id/' + parts[1], HDRS));
    var list = d.pages || [];
    var pages = [];
    for (var i = 0; i < list.length; i++) {
      pages.push({ index: i, url: list[i].url });
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
