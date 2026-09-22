// ar/dilar — bespoke JSON-API engine with ECIES (ECDH P-256 + HKDF + AES-GCM) page decryption
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'chapter pages use ECIES-encrypted payloads; decrypted via Web Crypto (ECDH P-256/HKDF-SHA256/AES-GCM)',
      'browse filters not portable; plain text search only',
      'site now serves ECIES protocol v12, beyond the v1-v9 the upstream source implements — page loading fails on both; listing/details/chapters still work',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};

// ---------------- crypto helpers ----------------
function b64urlEncode(bytes) {
  var s = '';
  for (var i = 0; i < bytes.length; i++) { s += String.fromCharCode(bytes[i]); }
  return btoa(s).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');
}
function b64urlDecode(str) {
  var s = String(str).replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) { s += '='; }
  var bin = atob(s);
  var out = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) { out[i] = bin.charCodeAt(i); }
  return out;
}
function strBytes(s) { return new TextEncoder().encode(s); }
function bytesStr(bytes) {
  var s = '';
  for (var i = 0; i < bytes.length; i++) { s += String.fromCharCode(bytes[i]); }
  return s;
}
function hexBytes(bytes) {
  var s = '';
  for (var i = 0; i < bytes.length; i++) { s += (bytes[i] < 16 ? '0' : '') + bytes[i].toString(16); }
  return s;
}
function concatBytes() {
  var total = 0;
  for (var i = 0; i < arguments.length; i++) { total += arguments[i].length; }
  var out = new Uint8Array(total);
  var off = 0;
  for (var j = 0; j < arguments.length; j++) { out.set(arguments[j], off); off += arguments[j].length; }
  return out;
}
function u16(n) { return new Uint8Array([(n >> 8) & 0xFF, n & 0xFF]); }
async function sha256(data) {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', data));
}
async function hmac(key, data, alg) {
  var name = alg || 'SHA-256';
  var k = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: { name: name } }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', k, data));
}
async function hkdfSha256(ikm, salt, info, length) {
  var k = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  var bits = await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: salt, info: info }, k, length * 8);
  return new Uint8Array(bits);
}

// client ECDH keypair (lazy, one per session)
var DH = null;
async function getDh() {
  if (DH) { return DH; }
  var pair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  var raw = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey));
  DH = { pair: pair, raw: raw, b64: b64urlEncode(raw) };
  return DH;
}

async function baseHeaders() {
  var dh = await getDh();
  return { 'X-DH-Pub': dh.b64, 'X-Crypto-Caps': '1,2,3,4,5,6,7,8,9' };
}

async function eciesDecrypt(enc) {
  var dh = await getDh();
  var serverRaw = b64urlDecode(enc.epk);
  var iv = b64urlDecode(enc.iv);
  var ct = b64urlDecode(enc.ct);
  var tag = b64urlDecode(enc.tag);

  var serverKey = await crypto.subtle.importKey('raw', serverRaw, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  var shared = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: serverKey }, dh.pair.privateKey, 256));

  var clientRaw = dh.raw;
  var salt;
  var infoStr;
  if (enc.v === 1) {
    salt = concatBytes(clientRaw, serverRaw);
    infoStr = 'dilar.response.ecies.v1|' + enc.e;
  } else if (enc.v === 2) {
    salt = concatBytes(serverRaw, clientRaw);
    infoStr = 'dilar.response.ecies.v2|' + enc.e;
  } else if (enc.v === 3) {
    salt = await sha256(concatBytes(serverRaw, clientRaw));
    infoStr = 'dilar.response.ecies.v3|' + enc.e;
  } else if (enc.v === 4) {
    salt = await sha256(concatBytes(clientRaw, serverRaw, iv));
    infoStr = 'dilar.response.ecies.v4|' + enc.e + '|' + enc.iv;
  } else if (enc.v === 5) {
    salt = await hmac(iv, concatBytes(serverRaw, clientRaw));
    infoStr = 'dilar.response.ecies.v5|' + enc.e;
  } else if (enc.v === 6) {
    var c6 = await sha256(clientRaw);
    var s6 = await sha256(serverRaw);
    salt = await sha256(concatBytes(c6, s6, iv));
    infoStr = 'dilar.response.ecies.v6|' + enc.e + '|' + enc.iv;
  } else if (enc.v === 7) {
    salt = await hkdfSha256(iv, serverRaw, strBytes('dilar.response.ecies.v7.salt'), 32);
    infoStr = 'dilar.response.ecies.v7|' + enc.e;
  } else if (enc.v === 8) {
    salt = await sha256(concatBytes(u16(clientRaw.length), clientRaw, u16(serverRaw.length), serverRaw, u16(iv.length), iv));
    infoStr = 'dilar.response.ecies.v8|' + enc.e + '|' + hexBytes(iv);
  } else if (enc.v === 9) {
    var h9 = await hmac(iv, concatBytes(u16(serverRaw.length), serverRaw, u16(clientRaw.length), clientRaw), 'SHA-512');
    salt = h9.slice(0, 32);
    var ivHash = await sha256(iv);
    infoStr = 'dilar.response.ecies.v9|' + enc.e + '|' + hexBytes(ivHash).substring(0, 16);
  } else {
    throw new Error('Unsupported encryption protocol version: ' + enc.v);
  }

  var key = await hkdfSha256(shared, salt, strBytes(infoStr), 32);
  var aesKey = await crypto.subtle.importKey('raw', key, { name: 'AES-GCM' }, false, ['decrypt']);
  var plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: iv }, aesKey, concatBytes(ct, tag));
  return bytesStr(new Uint8Array(plain));
}

// ---------------- domain helpers ----------------
function isNovel(d) {
  return d.seriesType && d.seriesType.title === 'رواية';
}
function thumbnail(id, cover) {
  if (!cover) { return ''; }
  var thumb = 'large_' + cover.replace(/\\.[^.]*$/, '') + '.webp';
  return BASE + '/uploads/manga/cover/' + id + '/' + thumb;
}
function mangaOut(d) {
  var authors = [];
  var artists = [];
  var staff = d.staff || [];
  for (var i = 0; i < staff.length; i++) {
    if (staff[i].Staff && staff[i].Staff.role === 'Author') { authors.push(staff[i].name); }
    if (staff[i].Staff && staff[i].Staff.role === 'Artist') { artists.push(staff[i].name); }
  }
  var genres = [];
  var cats = d.categories || [];
  for (var c = 0; c < cats.length; c++) { genres.push(cats[c].name); }
  var status = '';
  if (d.translation_status === 'ongoing') { status = 'ongoing'; }
  else if (d.translation_status === 'completed') { status = 'completed'; }
  else if (d.translation_status === 'dropped') { status = 'cancelled'; }
  else if (d.translation_status === 'hiatus') { status = 'hiatus'; }
  return {
    key: '/' + d.id + '/' + encodeURIComponent(d.title),
    title: d.title,
    coverUrl: thumbnail(d.id, d.cover),
    author: authors.join(', '),
    artist: artists.join(', '),
    description: d.summary || '',
    genre: genres.join(', '),
    status: status,
  };
}
function mangaIdFromKey(key) {
  var parts = String(key).split('/');
  return parts.length > 1 ? parts[1] : '';
}

module.exports = {
  getPopularManga: async function (page) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    var text = await $.http.get(BASE + '/api/rankings', await baseHeaders());
    var list = JSON.parse(text).topSeries || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      if (!isNovel(list[i])) { out.push(mangaOut(list[i])); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var h = await baseHeaders();
    h['Content-Type'] = 'application/json';
    var text = await $.http.post(BASE + '/api/search/filter', JSON.stringify({ query: query, page: page }), h);
    var data = JSON.parse(text);
    var rows = data.rows || [];
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      if (!isNovel(rows[i])) { out.push(mangaOut(rows[i])); }
    }
    var hasNext = (data.total || 0) > ((data.page || 1) * (data.perPage || 20));
    return { mangas: out, hasNextPage: hasNext };
  },

  getMangaDetail: async function (mangaKey) {
    var id = mangaIdFromKey(mangaKey);
    var text = await $.http.get(BASE + '/api/series/' + id, await baseHeaders());
    return mangaOut(JSON.parse(text));
  },

  getChapterList: async function (mangaKey) {
    var id = mangaIdFromKey(mangaKey);
    var text = await $.http.get(BASE + '/api/series/' + id + '/chapters', await baseHeaders());
    var chapters = JSON.parse(text).chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var ch = chapters[i];
      var number = String(ch.chapter || '').replace(/\\.00$/, '');
      var titleSuffix = ch.title ? ' - ' + ch.title : '';
      var releases = ch.releases || [];
      for (var r = 0; r < releases.length; r++) {
        var ts = releases[r].created_at ? Date.parse(releases[r].created_at) : 0;
        out.push({
          key: mangaKey + '/' + number + '#' + releases[r].id,
          name: number + titleSuffix,
          chapterNumber: -1,
          dateUpload: isNaN(ts) ? 0 : ts,
          pages: 0,
          sortOrder: 0,
        });
      }
    }
    // host convention: oldest-first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var releaseId = String(chapterKey).split('#').pop();
    var h = await baseHeaders();
    h['Content-Type'] = 'application/json';
    var unlockText = await $.http.post(BASE + '/api/chapters/' + releaseId + '/unlock/free', '{}', h);
    var token = (JSON.parse(unlockText) || {}).token || '';
    var ch = await baseHeaders();
    ch['X-Unlock-Free-Chapter'] = token;
    var encText = await $.http.get(BASE + '/api/chapters/' + releaseId, ch);
    var enc = JSON.parse(encText);
    var data = JSON.parse(await eciesDecrypt(enc));
    var pages = (data.pages || []).slice().sort(function (a, b) { return (a.order || 0) - (b.order || 0); });
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      out.push({ index: i, url: BASE + '/uploads/releases/' + data.storage_key + '/hq/' + pages[i].url });
    }
    return out;
  },

  imageHeaders: async function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
