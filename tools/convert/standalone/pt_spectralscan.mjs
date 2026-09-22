// pt/spectralscan (Nexus Toons) — JSON API with custom "Orion" response cipher (ported)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'filters not ported',
      'site currently Cloudflare-blocked from test network (probe 403, environmental)',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API + Orion cipher)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Accept: 'application/json', Referer: BASE + '/' };
var SECRET = 'OrionNexus2025CryptoKey!Secure';
var KEYS = null;

function b64ToBytes(b64) {
  var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  b64 = String(b64).replace(/[^A-Za-z0-9+\\/]/g, '');
  var out = [];
  for (var i = 0; i < b64.length; i += 4) {
    var c0 = chars.indexOf(b64.charAt(i));
    var c1 = chars.indexOf(b64.charAt(i + 1));
    var c2 = chars.indexOf(b64.charAt(i + 2));
    var c3 = chars.indexOf(b64.charAt(i + 3));
    out.push(((c0 << 2) | (c1 >> 4)) & 0xFF);
    if (c2 >= 0) { out.push(((c1 & 15) << 4) | (c2 >> 2)); }
    if (c3 >= 0) { out.push(((c2 & 3) << 6) | c3); }
  }
  return out;
}

function utf8Decode(bytes) {
  var out = '';
  var i = 0;
  while (i < bytes.length) {
    var b = bytes[i];
    if (b < 0x80) {
      out += String.fromCharCode(b);
      i += 1;
    } else if (b < 0xE0) {
      out += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
      i += 2;
    } else if (b < 0xF0) {
      out += String.fromCharCode(((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F));
      i += 3;
    } else {
      var cp = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
      cp -= 0x10000;
      out += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
      i += 4;
    }
  }
  return out;
}

async function getKeys() {
  if (KEYS) { return KEYS; }
  var keys = [];
  for (var i = 0; i < 5; i++) {
    var hex = await $.crypto.sha256('_orion_key_' + i + '_v2_' + SECRET);
    var key = [];
    for (var j = 0; j < hex.length; j += 2) { key.push(parseInt(hex.substr(j, 2), 16)); }
    var sbox = [];
    for (var s = 0; s < 256; s++) { sbox[s] = s; }
    var jj = 0;
    for (var t = 0; t < 256; t++) {
      jj = (jj + sbox[t] + key[t % key.length]) % 256;
      var tmp = sbox[t]; sbox[t] = sbox[jj]; sbox[jj] = tmp;
    }
    var rsbox = [];
    for (var r = 0; r < 256; r++) { rsbox[sbox[r]] = r; }
    keys.push({ key: key, rsbox: rsbox });
  }
  KEYS = keys;
  return keys;
}

async function tryDecrypt(text) {
  var j;
  try { j = $.json.parse(text); } catch (e) { return text; }
  if (!j || typeof j !== 'object' || !j.d || (j.v !== 1 && j.v !== 2)) { return text; }
  try {
    var keyIndex = j.v === 1 ? 0 : (j.k || 0);
    var kd = (await getKeys())[keyIndex];
    var key = kd.key, rsbox = kd.rsbox, keyLen = key.length;
    var input = b64ToBytes(j.d);
    var out = new Array(input.length);
    for (var i = input.length - 1; i >= 0; i--) {
      var b = input[i] & 0xFF;
      b = b ^ (i > 0 ? (input[i - 1] & 0xFF) : key[keyLen - 1]);
      b = rsbox[b & 0xFF];
      var rot = ((key[(i + 3) % keyLen] + (i & 0xFF)) & 0xFF) % 7 + 1;
      b = ((b >>> rot) | (b << (8 - rot))) & 0xFF;
      b = (b ^ key[i % keyLen]) & 0xFF;
      out[i] = b;
    }
    return utf8Decode(out);
  } catch (e2) {
    return text;
  }
}

async function apiGet(url) {
  return tryDecrypt(await $.http.get(url, HDRS));
}

function toStatus(s) {
  var v = String(s || '').toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  if (v === 'hiatus') { return 'hiatus'; }
  if (v === 'cancelled') { return 'cancelled'; }
  return '';
}

function parseList(text) {
  var j = $.json.parse(text);
  var out = [];
  var list = j.data || [];
  for (var i = 0; i < list.length; i++) {
    out.push({
      key: '/manga/' + list[i].slug,
      title: list[i].title || '',
      coverUrl: list[i].coverImage || ''
    });
  }
  return { mangas: out, hasNextPage: (j.page || 1) < (j.pages || 1) };
}

module.exports = {
  getPopularManga: async function (page) {
    var u = BASE + '/api/mangas?page=' + page + '&limit=50&includeNsfw=true&sortBy=views';
    return parseList(await apiGet(u));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/api/mangas?page=' + page + '&limit=30&includeNsfw=true&sortBy=updatedAt&sortOrder=desc&categoryMode=or';
    var q = (query || '').trim();
    if (q) { u += '&search=' + encodeURIComponent(q); }
    return parseList(await apiGet(u));
  },

  getMangaDetail: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var d = $.json.parse(await apiGet(BASE + '/api/manga/' + encodeURIComponent(slug)));
    var genres = [];
    (d.categories || []).forEach(function (c) { if (c && c.name) { genres.push(c.name); } });
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: d.coverImage || '',
      author: d.author || '',
      artist: d.artist || '',
      description: d.description || '',
      genre: genres.join(', '),
      status: toStatus(d.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var d = $.json.parse(await apiGet(BASE + '/api/manga/' + encodeURIComponent(slug)));
    var out = [];
    var chapters = d.chapters || [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var name;
      if (c.title && String(c.title).trim()) {
        name = c.title + ' ' + c.number;
      } else {
        name = 'Capítulo ' + String(c.number).replace(/\\.0$/, '');
      }
      var dateStr = String(c.createdAt || '').split('.')[0];
      out.push({
        key: '/read/' + c.id + '/' + slug,
        name: name,
        chapterNumber: parseFloat(c.number) || -1,
        dateUpload: dateStr ? Date.parse(dateStr + 'Z') || 0 : 0,
        pages: 0
      });
    }
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var chapterId = chapterKey.split('/')[2];
    var j = $.json.parse(await apiGet(BASE + '/api/read/' + chapterId));
    var pages = j.pages || [];
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].imageUrl) {
        out.push({ index: i, url: pages[i].imageUrl });
      }
    }
    if (out.length > 0) { return out; }
    for (var k = 0; k < pages.length; k++) {
      out.push({ index: k, url: BASE + '/api/p/' + j.pageToken + '/' + k });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
