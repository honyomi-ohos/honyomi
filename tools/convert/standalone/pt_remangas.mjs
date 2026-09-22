// pt/remangas (NoxManga) — JSON API with request signing (/_nix/signer.js ported)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'site currently Cloudflare-blocked from test network; engine is a faithful port incl. request signer',
      'filters not ported',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API + signer)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = BASE + '/api/v1';
var SITE_ID = '00000000-0000-0000-0000-000000000003';

var signer = null;

function hexToBytes(h) {
  var out = [];
  for (var i = 0; i < h.length; i += 2) {
    out.push(String.fromCharCode(parseInt(h.substr(i, 2), 16)));
  }
  return out.join('');
}

function b64url(s) {
  var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  var out = '';
  for (var i = 0; i < s.length; i += 3) {
    var b0 = s.charCodeAt(i);
    var b1 = i + 1 < s.length ? s.charCodeAt(i + 1) : 0;
    var b2 = i + 2 < s.length ? s.charCodeAt(i + 2) : 0;
    out += chars.charAt(b0 >> 2) + chars.charAt(((b0 & 3) << 4) | (b1 >> 4));
    if (i + 1 < s.length) { out += chars.charAt(((b1 & 15) << 2) | (b2 >> 6)); } else { out += '='; }
    if (i + 2 < s.length) { out += chars.charAt(b2 & 63); } else { out += '='; }
  }
  return out.replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');
}

function parseSigner(script) {
  var arrayM = /z\\s*=\\s*\\[([^\\n]*?)\\]/.exec(script);
  if (!arrayM) { throw new Error('Falha ao interpretar o assinador do site (array)'); }
  var parts = [];
  var re = /"([^"]*)"/g;
  var m;
  while ((m = re.exec(arrayM[1])) !== null) {
    parts.push(m[1].split('').reverse().join(''));
  }
  var slotM = /=\\s*r\\(z\\[(\\d+)\\]\\)/.exec(script);
  var keyM = /k\\s*=\\s*j\\(z\\.slice\\((\\d+)\\s*,\\s*(\\d+)\\)\\)/.exec(script);
  var tokM = /t\\s*=\\s*j\\(z\\.slice\\((\\d+)\\)\\)/.exec(script);
  if (!slotM || !keyM || !tokM) { throw new Error('Falha ao interpretar o assinador do site'); }
  var slotIdx = parseInt(slotM[1], 10);
  var keyStart = parseInt(keyM[1], 10);
  var keyEnd = parseInt(keyM[2], 10);
  var tokStart = parseInt(tokM[1], 10);
  if (slotIdx >= parts.length || tokStart > parts.length || keyEnd > parts.length) {
    throw new Error('Falha ao interpretar o assinador do site (bounds)');
  }
  return {
    slot: parts[slotIdx],
    key: parts.slice(keyStart, keyEnd).join(''),
    token: parts.slice(tokStart).join('')
  };
}

async function fetchSigner() {
  var text = await $.http.get(BASE + '/_nix/signer.js');
  signer = parseSigner(text);
}

async function signHeaders(method, path) {
  var payload = [method.toUpperCase(), path, SITE_ID, signer.slot, signer.token, signer.key].join('|');
  var hex = await $.crypto.sha256(payload);
  return {
    'X-Site-ID': SITE_ID,
    'X-Web-Slot': signer.slot,
    'X-Web-Token': signer.token,
    'X-Web-Signature': b64url(hexToBytes(hex))
  };
}

async function apiGet(url) {
  if (!signer) { await fetchSigner(); }
  var path = url.replace(BASE, '');
  if (path.indexOf('http') === 0) { path = new URL(url).pathname + new URL(url).search; }
  var hdrs = await signHeaders('GET', path);
  var text = await $.http.get(url, hdrs);
  return text;
}

function toStatus(s) {
  var v = String(s || '').trim().toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  if (v === 'hiatus') { return 'hiatus'; }
  if (v === 'cancelled') { return 'cancelled'; }
  return '';
}

function dtoToManga(d) {
  var genres = [];
  if (d.type && String(d.type).trim()) {
    genres.push(String(d.type).charAt(0).toUpperCase() + String(d.type).slice(1));
  }
  (d.genres || []).forEach(function (g) {
    if (g && g.name) { genres.push(g.name); }
  });
  var desc = '';
  if (d.synopsis && String(d.synopsis).trim()) {
    desc = String(d.synopsis).trim();
  }
  var alts = (d.title_alt || []).filter(function (t) { return t && String(t).trim(); });
  if (alts.length > 0) {
    if (desc) { desc += '\\n\\n'; }
    desc += 'Títulos alternativos: ' + alts.join(', ');
  }
  return {
    key: '/manga/' + d.slug,
    title: d.title || '',
    coverUrl: d.cover || '',
    genre: genres.join(', '),
    status: toStatus(d.status),
    description: desc
  };
}

function parseList(text) {
  var j = $.json.parse(text);
  var out = [];
  var list = j.comics || [];
  for (var i = 0; i < list.length; i++) {
    out.push({
      key: '/manga/' + list[i].slug,
      title: list[i].title || '',
      coverUrl: list[i].cover || ''
    });
  }
  return { mangas: out, hasNextPage: (j.page || 1) < (j.total_pages || 1) };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await apiGet(API + '/comics?page=' + page + '&per_page=24'));
  },

  getSearchManga: async function (page, query) {
    var q = (query || '').trim();
    var u = API + '/comics?page=' + page + '&per_page=24';
    if (q) { u += '&q=' + encodeURIComponent(q); }
    return parseList(await apiGet(u));
  },

  getMangaDetail: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var text = await apiGet(API + '/comics/slug/' + encodeURIComponent(slug));
    return dtoToManga($.json.parse(text));
  },

  getChapterList: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var u = API + '/comics/slug/' + encodeURIComponent(slug) + '/chapters?page=1&per_page=10000&sort=newest';
    var j = $.json.parse(await apiGet(u));
    var list = j.chapters || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var num = c.number;
      var numStr = String(num).replace(/\\.0$/, '');
      var name = 'Capítulo ' + numStr;
      var title = (c.title || '').trim();
      if (title && title !== numStr && !/^Capítulo/i.test(title)) {
        name += ' - ' + title;
      }
      out.push({
        key: '/chapter/' + c.id + '?manga=' + slug + '&slug=' + encodeURIComponent(c.slug || ''),
        name: name,
        chapterNumber: num,
        dateUpload: c.published_at ? Date.parse(c.published_at) || 0 : 0,
        pages: 0
      });
    }
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = chapterKey.split('?')[0].split('/').pop();
    var text = await apiGet(API + '/chapters/' + encodeURIComponent(id) + '?skip_view=true');
    var j = $.json.parse(text);
    var pages = (j.pages || []).slice();
    pages.sort(function (a, b) { return (a.number || 0) - (b.number || 0); });
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      out.push({ index: i, url: pages[i].image_url });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/', 'Sec-Fetch-Site': 'same-origin' };
  }
};
`;
}
