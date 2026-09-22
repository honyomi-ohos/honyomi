// id/komiknesia — komiknesiaku.com backend JSON API with AES-CBC envelope (bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['genre/status filters not supported; plain search only'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var API = 'https://api-be.komiknesia.my.id/api';
function b64bytes(b64) {
  var s = atob(b64);
  var out = new Uint8Array(s.length);
  for (var i = 0; i < s.length; i++) { out[i] = s.charCodeAt(i); }
  return out;
}
function keyStr(time) {
  var v = (time / 32.0).toFixed(8);
  while (v.length < 32) { v += '0'; }
  return v.slice(0, 32);
}
async function decryptEnvelope(env) {
  var key = new TextEncoder().encode(keyStr(env.time));
  var raw = b64bytes(env.data);
  var iv = raw.subarray(0, 16);
  var ct = raw.subarray(16);
  var subtle = crypto.subtle;
  var k = await subtle.importKey('raw', key, { name: 'AES-CBC' }, false, ['decrypt']);
  var buf = await subtle.decrypt({ name: 'AES-CBC', iv: iv }, k, ct);
  var s = '';
  var bytes = new Uint8Array(buf);
  for (var i = 0; i < bytes.length; i++) { s += String.fromCharCode(bytes[i]); }
  try { return decodeURIComponent(escape(s)); } catch (e) { return s; }
}
async function apiGet(path) {
  var text = await H_get(API + path, { Referer: BASE + '/', Accept: 'application/json' });
  var body = text;
  if (text.indexOf('"encrypted":true') >= 0 || text.indexOf('"encrypted": true') >= 0) {
    var env = JSON.parse(text);
    body = await decryptEnvelope(env);
  }
  return JSON.parse(body);
}
function statusMap(v) {
  v = String(v || '').toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  if (v === 'hiatus') { return 'hiatus'; }
  return '';
}
function toManga(m) {
  var desc = String(m['sinopsis'] || '').replace(/<\\/?p\\s*\\/?>/g, '').trim();
  var alt = m['alternative_name'];
  if (alt) {
    var alts = alt.split(',').map(function (s) { return s.trim(); }).filter(function (s) { return s; });
    desc += (desc ? '\\n\\n' : '') + 'Alternative Names:\\n' + alts.join('\\n');
  }
  var genres = [];
  var gl = m.genres || [];
  for (var i = 0; i < gl.length; i++) { genres.push(gl[i].name); }
  return {
    key: '/komik/' + m.slug,
    title: m.title || '',
    coverUrl: m.cover || '',
    author: m.author || '',
    description: desc,
    genre: genres.join(', '),
    status: statusMap(m.status)
  };
}
function chapterDate(c) {
  var t = (c['scheduled_release_at'] ? c['scheduled_release_at'].time : (c['created_at'] ? c['created_at'].time : 0)) * 1000;
  return t;
}
module.exports = {
  getPopularManga: async function (page) {
    var d = await apiGet('/contents?page=' + page + '&orderBy=views');
    var out = [];
    for (var i = 0; i < d.data.length; i++) { out.push(toManga(d.data[i])); }
    return { mangas: out, hasNextPage: d.meta ? d.meta.page < d.meta['total_pages'] : false };
  },

  getSearchManga: async function (page, query) {
    var u = '/contents?page=' + page;
    if (query) { u += '&q=' + encodeURIComponent(query); }
    var d = await apiGet(u);
    var out = [];
    for (var i = 0; i < d.data.length; i++) { out.push(toManga(d.data[i])); }
    return { mangas: out, hasNextPage: d.meta ? d.meta.page < d.meta['total_pages'] : false };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/komik\\//, '');
    var d = await apiGet('/comic/' + slug);
    return toManga(d.data);
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/komik\\//, '');
    var d = await apiGet('/comic/' + slug);
    var out = [];
    var chs = d.data.chapters || [];
    for (var i = 0; i < chs.length; i++) {
      var c = chs[i];
      out.push({
        key: '/view/' + c.slug,
        name: c.title || '',
        chapterNumber: parseFloat(c.number) || -1,
        dateUpload: chapterDate(c),
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var slug = String(chapterKey).replace(/^\\/view\\//, '');
    var d = await apiGet('/chapters/slug/' + slug);
    var pages = [];
    var imgs = d.data.images || [];
    for (var i = 0; i < imgs.length; i++) {
      pages.push({ index: i, url: imgs[i] });
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
