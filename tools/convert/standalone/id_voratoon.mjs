// id/voratoon — v2.voratoon.com JSON API (api.voratoon.com), bespoke
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
var API = 'https://api.voratoon.com';
var HDRS = { Accept: 'application/json', 'Accept-language': 'en-US,en;q=0.9,id;q=0.8', Referer: BASE + '/' };
function statusMap(v) {
  v = String(v || '').toLowerCase();
  if (v === 'ongoing' || v === 'on going') { return 'ongoing'; }
  if (v === 'completed' || v === 'complete') { return 'completed'; }
  if (v === 'hiatus') { return 'hiatus'; }
  if (v === 'cancelled' || v === 'canceled') { return 'cancelled'; }
  return '';
}
function fromSeries(item) {
  var v = item.data || {};
  var genres = [];
  var gl = v.genres || [];
  for (var i = 0; i < gl.length; i++) {
    if (gl[i].data && gl[i].data.name) { genres.push(gl[i].data.name); }
  }
  return {
    key: '/series/' + (v.slug || String(item.id)),
    title: v.title || '',
    coverUrl: v.coverImage || '',
    author: v.author || '',
    description: v.synopsis || '',
    genre: genres.join(', '),
    status: statusMap(v.status)
  };
}
function fmtNum(n) {
  var f = parseFloat(n);
  if (isNaN(f)) { return String(n); }
  return String(Math.round(f * 100) / 100);
}
module.exports = {
  getPopularManga: async function (page) {
    var d = JSON.parse(await H_get(API + '/series?includeMeta=true&take=30&page=' + page + '&sort=popularity&sortOrder=desc', HDRS));
    var out = [];
    for (var i = 0; i < d.data.length; i++) {
      var m = fromSeries(d.data[i]);
      out.push({ key: m.key, title: m.title, coverUrl: m.coverUrl });
    }
    return { mangas: out, hasNextPage: d.meta ? (d.meta.page || 0) < (d.meta.lastPage || 0) : false };
  },

  getSearchManga: async function (page, query) {
    var u = API + '/series?includeMeta=true&take=30&page=' + page;
    if (query) { u += '&title=' + encodeURIComponent(query); }
    var d = JSON.parse(await H_get(u, HDRS));
    var out = [];
    for (var i = 0; i < d.data.length; i++) {
      var m = fromSeries(d.data[i]);
      out.push({ key: m.key, title: m.title, coverUrl: m.coverUrl });
    }
    return { mangas: out, hasNextPage: d.meta ? (d.meta.page || 0) < (d.meta.lastPage || 0) : false };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/series\\//, '');
    var d = JSON.parse(await H_get(API + '/series/' + slug, HDRS));
    return fromSeries(d.data);
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/series\\//, '');
    var d = JSON.parse(await H_get(API + '/series/' + slug + '/chapters', HDRS));
    var out = [];
    for (var i = 0; i < d.data.length; i++) {
      var c = d.data[i];
      var v = c.data || {};
      var idx = v.index != null ? v.index : (c.chapterIndex || 0);
      var fi = fmtNum(idx);
      var name = !v.title ? 'Chapter ' + fi : 'Chapter ' + fi + ': ' + v.title;
      out.push({
        key: '/series/' + slug + '/chapter/' + fi,
        name: name,
        chapterNumber: parseFloat(idx) || 0,
        dateUpload: Date.parse(c.createdAt || c.updatedAt || '') || 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = String(chapterKey).split('/');
    var slug = parts[2];
    var idx = parts[4];
    var d = JSON.parse(await H_get(API + '/series/' + slug + '/chapters/' + idx, HDRS));
    var images = (d.data && d.data.data && d.data.data.images) || [];
    var pages = [];
    for (var i = 0; i < images.length; i++) {
      pages.push({ index: i, url: images[i] });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/', Accept: 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8' };
  }
};
`);
}
