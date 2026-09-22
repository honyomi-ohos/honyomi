// id/roseveil — roseveil.org JSON API (dreamteams-style, bespoke)
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
var API = 'https://api.roseveil.org/api';
var HDRS = { Referer: BASE + '/' };
function apiGet(path) {
  return H_get(API + path, HDRS).then(function (t) { return JSON.parse(t); });
}
function statusMap(v) {
  v = String(v || '').toUpperCase();
  if (v === 'ONGOING') { return 'ongoing'; }
  if (v === 'COMPLETED') { return 'completed'; }
  if (v === 'HIATUS') { return 'hiatus'; }
  if (v === 'CANCELED') { return 'cancelled'; }
  return '';
}
function fmtNum(n) {
  var f = parseFloat(n);
  if (isNaN(f)) { return String(n); }
  return String(Math.round(f * 100) / 100);
}
module.exports = {
  getPopularManga: async function (page) {
    var d = await apiGet('/search?type=COMIC&limit=20&page=' + page + '&sort=views&order=desc');
    var out = [];
    for (var i = 0; i < d.data.length; i++) {
      out.push({ key: '/comic/' + d.data[i].slug, title: d.data[i].title || '', coverUrl: d.data[i].thumbnail || '' });
    }
    return { mangas: out, hasNextPage: d.page < d['totalPages'] };
  },

  getSearchManga: async function (page, query) {
    var u = '/search?type=COMIC&limit=20&page=' + page + '&sort=new&order=desc';
    if (query) { u += '&q=' + encodeURIComponent(query); }
    var d = await apiGet(u);
    var out = [];
    for (var i = 0; i < d.data.length; i++) {
      out.push({ key: '/comic/' + d.data[i].slug, title: d.data[i].title || '', coverUrl: d.data[i].thumbnail || '' });
    }
    return { mangas: out, hasNextPage: d.page < d['totalPages'] };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/comic\\//, '');
    var d = await apiGet('/series/comic/' + slug);
    var genres = [];
    var gl = d.genres || [];
    for (var i = 0; i < gl.length; i++) { genres.push(gl[i].name); }
    return {
      key: '/comic/' + d.slug,
      title: d.title || '',
      coverUrl: d.thumbnail || '',
      author: d.author || '',
      description: d.synopsis || '',
      genre: genres.join(', '),
      status: statusMap(d.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/comic\\//, '');
    var d = await apiGet('/series/comic/' + slug);
    var out = [];
    var units = d.units || [];
    for (var i = 0; i < units.length; i++) {
      var u = units[i];
      out.push({
        key: '/comic/' + d.slug + '/chapter/' + u.slug,
        name: 'Chapter ' + fmtNum(u.number),
        chapterNumber: parseFloat(u.number) || -1,
        dateUpload: Date.parse(u.date || '') || 0,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var d = await apiGet('/series' + String(chapterKey));
    var pages = [];
    var list = (d.chapter && d.chapter.pages) || [];
    for (var i = 0; i < list.length; i++) {
      pages.push({ index: list[i].index - 1, url: list[i].url });
    }
    pages.sort(function (a, b) { return a.index - b.index; });
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/', Accept: 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8' };
  }
};
`);
}
