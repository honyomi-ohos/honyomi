// id/doujindesu — doujin.desu.xxx JSON API with XOR-encrypted responses (bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['taxonomy author/artist browse filters not supported; basic search only'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var API = BASE + '/api';
var APP_SECRET = 'dfdf72051dbfdc7d76889ebd31324e74';
var SALT = 'doujindesu-scrapers-cannot-read-this-super-secret-salt-2026-v2';
var LIMIT = 24;

function toSigned32(x) { return x | 0; }
function wH(e) {
  var t = SALT + '_' + e;
  var a = 0;
  for (var i = 0; i < t.length; i++) {
    a = toSigned32((a << 5) - a + t.charCodeAt(i));
  }
  var l = a !== 0 ? Math.abs(a) : 123456789;
  var out = '';
  for (var n = 0; n < 32; n++) {
    l = (l * 1664525 + 1013904223) % 4294967296;
    out += String.fromCharCode(33 + (l % 93));
  }
  return out;
}
function yre(hex, key) {
  var out = '';
  var d = 42;
  for (var idx = 0; idx < hex.length; idx += 2) {
    var byteVal = parseInt(hex.substr(idx, 2), 16);
    if (isNaN(byteVal)) { continue; }
    var k = (byteVal ^ key.charCodeAt(idx / 2 % key.length) ^ ((idx / 2 * 13) & 0xFF) ^ d) & 0xFF;
    out += String.fromCharCode(k);
    d = (d + byteVal) % 256;
  }
  return out;
}
function decryptPayload(text) {
  var dto = JSON.parse(text);
  var enc = dto['_enc_resp_'];
  if (!enc) { return text; }
  var t = Math.floor(Date.now() / 3600000);
  var keys = [wH(t), wH(t - 1), wH(t + 1)];
  for (var i = 0; i < keys.length; i++) {
    try {
      var decoded = decodeURIComponent(yre(enc, keys[i]));
      JSON.parse(decoded);
      return decoded;
    } catch (e) { /* try next key */ }
  }
  throw new Error('decryption failed');
}
function apiGet(path) {
  return H_get(API + path, { 'x-app-secret': APP_SECRET, Referer: BASE + '/' }).then(decryptPayload).then(function (t) { return JSON.parse(t); });
}
function stripHtml(html) {
  return String(html || '')
    .replace(/<br\\s*\\/?>/gi, '\\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/[ \\t]+/g, ' ');
}
function termMap(item) {
  var map = {};
  var tl = item['term_list'] || '';
  var parts = tl.split('|');
  for (var i = 0; i < parts.length; i++) {
    var seg = parts[i].split(':');
    if (seg.length === 3) {
      (map[seg[1]] = map[seg[1]] || []).push(seg[0]);
    }
  }
  return map;
}
function joinList(arr) {
  var out = [];
  for (var i = 0; i < (arr || []).length; i++) {
    var v = String(arr[i] || '').trim();
    if (v && v.toLowerCase() !== 'n/a') { out.push(v); }
  }
  return out.join(', ');
}
function toManga(item) {
  var map = termMap(item);
  var author = (item.author && item.author.trim() && item.author.toLowerCase() !== 'n/a')
    ? item.author
    : (joinList(map['author']) || joinList(map['artist']) || joinList(map['author_artist']) || joinList(map['creator']) || joinList(map['group']) || '');
  var st = String(item.status || '').toLowerCase();
  var status = (st === 'ongoing' || st === 'publishing') ? 'ongoing'
    : (st === 'completed' || st === 'finished') ? 'completed' : '';
  var cover = item['cover_url'] || '';
  if (cover.indexOf('/') === 0) { cover = BASE + cover; }
  var desc = stripHtml(item.description || '').trim();
  var extra = [];
  if (item.type) { extra.push('Tipe: ' + item.type); }
  var grp = joinList(map['group']);
  if (grp) { extra.push('Group: ' + grp); }
  var series = joinList(map['series']);
  if (series) { extra.push('Seri: ' + series); }
  var alt = item['alt_titles'] || '';
  if (alt.trim()) { extra.push('Judul Alternatif: ' + alt.split('|').join(',')); }
  if (extra.length) { desc += (desc ? '\\n\\n' : '') + extra.join('\\n'); }
  return {
    key: '/manga/' + item.slug,
    title: item.title || '',
    coverUrl: cover,
    author: author,
    description: desc,
    genre: joinList((map['genre'] || []).slice().sort(function (a, b) { return a.toLowerCase() < b.toLowerCase() ? -1 : 1; })),
    status: status
  };
}
function itemChapters(item) {
  var out = [];
  var chs = item.chapters || [];
  var completed = ['completed', 'finished'].indexOf(String(item.status || '').toLowerCase()) >= 0;
  for (var i = 0; i < chs.length; i++) {
    var c = chs[i];
    var numStr = String(c['chapter_number']).replace(/\\.0$/, '');
    out.push({
      key: '/reader/' + c.id,
      name: 'Chapter ' + numStr + (completed && i === 0 ? ' END' : ''),
      chapterNumber: c['chapter_number'],
      dateUpload: Date.parse(c['created_at'] || '') || 0,
      pages: 0,
      sortOrder: 0
    });
  }
  return out; // newest first upstream
}
function mangaSlug(key) {
  return String(key).replace(/^\\/manga\\//, '').replace(/\\/$/, '');
}
module.exports = {
  getPopularManga: async function (page) {
    var d = await apiGet('/manga?limit=' + LIMIT + '&offset=' + ((page - 1) * LIMIT) + '&sort=rating');
    var mangas = [];
    for (var i = 0; i < d.length; i++) { mangas.push(toManga(d[i])); }
    return { mangas: mangas, hasNextPage: true };
  },

  getSearchManga: async function (page, query) {
    var u = '/manga?limit=' + LIMIT + '&offset=' + ((page - 1) * LIMIT) + '&sort=latest_chapter';
    if (query) { u += '&search=' + encodeURIComponent(query); }
    var d = await apiGet(u);
    var mangas = [];
    for (var i = 0; i < d.length; i++) { mangas.push(toManga(d[i])); }
    return { mangas: mangas, hasNextPage: mangas.length >= LIMIT };
  },

  getMangaDetail: async function (mangaKey) {
    var item = await apiGet('/manga/' + mangaSlug(mangaKey));
    return toManga(item);
  },

  getChapterList: async function (mangaKey) {
    var item = await apiGet('/manga/' + mangaSlug(mangaKey));
    var out = itemChapters(item);
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).replace(/^\\/reader\\//, '');
    var d = await apiGet('/chapters/' + id);
    var urls = d['content_urls'] || [];
    var pages = [];
    for (var i = 0; i < urls.length; i++) {
      var p = urls[i];
      if (p.indexOf('/uploads/') >= 0 && p.indexOf('/storage/uploads/') < 0) { p = p.replace('/uploads/', '/storage/uploads/'); }
      else if (p.indexOf('/upload/') >= 0 && p.indexOf('/storage/upload/') < 0) { p = p.replace('/upload/', '/storage/upload/'); }
      pages.push({ index: pages.length, url: p });
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
