// id/dreamteamsscans — dreamteams.space JSON API (bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['filters (genre/status/type/color/format) not supported; plain search only'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var API = 'https://api.dreamteams.space/api';
var HDRS = { Referer: BASE + '/', Origin: BASE };
function apiGet(path) {
  return H_get(API + path, HDRS).then(function (t) { return JSON.parse(t); });
}
function listUrl(page, sort, query) {
  var u = '/search?type=COMIC&limit=20&page=' + page;
  if (sort) { u += '&sort=' + sort + '&order=desc'; }
  if (query) { u += '&q=' + encodeURIComponent(query); }
  return u;
}
function toManga(m) {
  return {
    key: '/comic/' + m.slug,
    title: m.title || '',
    coverUrl: m['poster_image_url'] || '',
    author: '',
    description: '',
    genre: '',
    status: ''
  };
}
function statusMap(v) {
  v = String(v || '').toUpperCase();
  if (v === 'ONGOING') { return 'ongoing'; }
  if (v === 'COMPLETED') { return 'completed'; }
  if (v === 'HIATUS') { return 'hiatus'; }
  if (v === 'CANCELLED') { return 'cancelled'; }
  return '';
}
module.exports = {
  getPopularManga: async function (page) {
    var d = await apiGet(listUrl(page, 'popular', ''));
    var out = [];
    for (var i = 0; i < d.data.length; i++) { out.push(toManga(d.data[i])); }
    return { mangas: out, hasNextPage: d.page < d['total_pages'] };
  },

  getSearchManga: async function (page, query) {
    var d = await apiGet(listUrl(page, '', query));
    var out = [];
    for (var i = 0; i < d.data.length; i++) { out.push(toManga(d.data[i])); }
    return { mangas: out, hasNextPage: d.page < d['total_pages'] };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/comic\\//, '');
    var d = await apiGet('/series/comic/' + slug);
    var genres = [];
    if (d['primary_genre']) { genres.push(d['primary_genre']); }
    var gl = d.genres || [];
    for (var i = 0; i < gl.length; i++) {
      if (genres.indexOf(gl[i].name) < 0) { genres.push(gl[i].name); }
    }
    return {
      key: '/comic/' + d.slug,
      title: d.title || '',
      coverUrl: d['poster_image_url'] || '',
      author: d['author_name'] || '',
      description: d.synopsis || '',
      genre: genres.join(', '),
      status: statusMap(d['comic_status'])
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/comic\\//, '');
    var d = await apiGet('/series/comic/' + slug);
    var out = [];
    var units = d.units || [];
    for (var i = 0; i < units.length; i++) {
      var u = units[i];
      var num = String(u.number || '').replace(/\\.00$/, '');
      var name = 'Chapter ' + num + (u.title ? ' - ' + u.title : '');
      out.push({
        key: '/comic/' + slug + '/chapter/' + u.slug,
        name: name,
        chapterNumber: parseFloat(num) || -1,
        dateUpload: Date.parse(u['created_at'] || '') || 0,
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
      pages.push({ index: list[i]['page_number'] - 1, url: list[i]['image_url'] });
    }
    pages.sort(function (a, b) { return a.index - b.index; });
    return pages;
  },

  imageHeaders: function () { return HDRS; }
};
`);
}
