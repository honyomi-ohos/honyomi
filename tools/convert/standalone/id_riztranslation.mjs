// id/riztranslation — riztranslation.com Supabase REST backend (bespoke)
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
var API = 'https://uefnaojxivvxeamljskn.supabase.co/rest/v1';
var APIKEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVlZm5hb2p4aXZ2eGVhbWxqc2tuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDc3MTU5MjksImV4cCI6MjA2MzI5MTkyOX0._lEBN5puTvATwtYodg4zbcoTwg0ss3j2BebD8WoHt9A';
var HDRS = { apikey: APIKEY, Authorization: 'Bearer ' + APIKEY, Referer: BASE + '/' };
function apiGet(path) {
  return H_get(API + path, HDRS).then(function (t) { return JSON.parse(t); });
}
function toManga(b) {
  return { key: '/detail/' + b.id, title: b['judul'] || '', coverUrl: b['cover'] || '' };
}
function parseDate(v) {
  var t = Date.parse(String(v || '').replace(/\\.\\d+/, ''));
  return isNaN(t) ? 0 : t;
}
function statusMap(v) {
  v = String(v || '').toLowerCase();
  if (v === 'completed' || v === 'complete' || v === 'oneshot') { return 'completed'; }
  if (v === 'ongoing') { return 'ongoing'; }
  return '';
}
module.exports = {
  getPopularManga: async function (page) {
    var d = await apiGet('/Book?select=id,judul,cover&type=not.ilike.*novel*&order=id.desc&offset=' + ((page - 1) * 20) + '&limit=20');
    var out = [];
    for (var i = 0; i < d.length; i++) { out.push(toManga(d[i])); }
    return { mangas: out, hasNextPage: d.length === 20 };
  },

  getSearchManga: async function (page, query) {
    var u = '/Book?select=id,judul,cover&type=not.ilike.*novel*&order=updated_at.desc&offset=' + ((page - 1) * 20) + '&limit=20';
    if (query) { u += '&judul=ilike.*' + encodeURIComponent(query) + '*'; }
    var d = await apiGet(u);
    var out = [];
    for (var i = 0; i < d.length; i++) { out.push(toManga(d[i])); }
    return { mangas: out, hasNextPage: d.length === 20 };
  },

  getMangaDetail: async function (mangaKey) {
    var id = String(mangaKey).replace(/^\\/detail\\//, '');
    var d = await apiGet('/Book?select=*%2Cgenres%3A_BookGenre%28genre%3AGenre%28*%29%29&type=not.ilike.*novel*&id=eq.' + id);
    if (!d.length) { throw new Error('Manga not found'); }
    var b = d[0];
    var genres = [];
    var gl = b['genres'] || [];
    for (var i = 0; i < gl.length; i++) {
      if (gl[i]['genre'] && gl[i]['genre']['nama']) { genres.push(gl[i]['genre']['nama']); }
    }
    return {
      key: '/detail/' + b.id,
      title: b['judul'] || '',
      coverUrl: b['cover'] || '',
      author: b['author'] || '',
      description: b['synopsis'] || '',
      genre: genres.join(', '),
      status: statusMap(b['status'])
    };
  },

  getChapterList: async function (mangaKey) {
    var id = String(mangaKey).replace(/^\\/detail\\//, '');
    var d = await apiGet('/Chapter?select=id,bookId,chapter,nama,created_at&bookId=eq.' + id + '&order=chapter.desc');
    var out = [];
    for (var i = 0; i < d.length; i++) {
      var c = d[i];
      var name = '';
      var num = c['chapter'] === null || c['chapter'] === undefined ? null : String(c['chapter']).replace(/\\.0$/, '');
      if (num !== null) { name = 'Chapter ' + num; }
      if (c['nama']) { name += (name ? ' - ' : '') + c['nama']; }
      out.push({
        key: '/view/' + c['bookId'] + '/' + c['id'],
        name: name,
        chapterNumber: c['chapter'] === null || c['chapter'] === undefined ? -1 : c['chapter'],
        dateUpload: parseDate(c['created_at']),
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).split('/').pop();
    var d = await apiGet('/Chapter?select=id,bookId,isigambar&id=eq.' + id);
    if (!d.length) { throw new Error('Chapter not found'); }
    var raw = d[0]['isigambar'];
    var pages = [];
    if (raw) {
      var imgs = JSON.parse(raw);
      for (var i = 0; i < imgs.length; i++) {
        pages.push({ index: i, url: imgs[i] });
      }
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
