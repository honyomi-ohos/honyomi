// pt/mangalivreorg — JSON API (api.mangalivre.org/api/v1) with X-ML-Nonce chapter pages
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['X-ML-Nonce scraped from site JS bundle with hardcoded fallback; category filters not ported'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.mangalivre.org/api/v1';
var DEFAULT_NONCE = '3dce95d4540e54086a970da4ea44cf46';
var HDRS = { 'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.8' };
var cachedNonce = null;

async function fetchNonce() {
  try {
    var homeText = await $.http.get(BASE + '/');
    var doc = $.html.parse(homeText);
    var scriptEl = R_selFirst(doc, 'script[type=module][src*=/assets/]');
    if (!scriptEl) { return DEFAULT_NONCE; }
    var src = scriptEl.absUrl('src');
    if (!src) { return DEFAULT_NONCE; }
    var js = await $.http.get(src);
    var vm = js.match(/(?:X-ML-Nonce|Nonce"]\\.join\\("-"\\))"?]\\s*=\\s*(\\w+)/);
    if (!vm) { return DEFAULT_NONCE; }
    var re = new RegExp('\\\\b' + vm[1] + '\\\\s*=\\\\s*');
    var found = null;
    var m;
    var guard = 0;
    while ((m = re.exec(js)) !== null && guard < 20) {
      guard++;
      var assignment = js.substring(m.index + m[0].length).substring(0, 300).split(';')[0];
      var decoded = null;
      var lit = assignment.match(/["'\`]([0-9a-f]{32})["'\`]/);
      if (lit) { decoded = lit[1]; }
      if (!decoded) {
        var b64 = assignment.match(/atob\\(\\s*["']([A-Za-z0-9+/=]+)["']/);
        if (b64) {
          try { decoded = $.crypto.base64Decode(b64[1]); } catch (e) { decoded = null; }
        }
      }
      if (!decoded) {
        var cc = assignment.match(/fromCharCode\\(([\\d,\\s]+)\\)/);
        if (cc) {
          var codes = cc[1].split(',');
          var s = '';
          for (var i = 0; i < codes.length; i++) {
            var n = parseInt(codes[i].trim(), 10);
            if (!isNaN(n)) { s += String.fromCharCode(n); }
          }
          decoded = s;
        }
      }
      if (decoded && /^[0-9a-f]{32}$/.test(decoded)) {
        found = assignment.indexOf('reverse()') >= 0 ? decoded.split('').reverse().join('') : decoded;
        break;
      }
    }
    return found || DEFAULT_NONCE;
  } catch (e) {
    return DEFAULT_NONCE;
  }
}

async function nonceHeaders() {
  if (!cachedNonce) { cachedNonce = await fetchNonce(); }
  var h = {};
  for (var k in HDRS) { h[k] = HDRS[k]; }
  h['X-ML-Nonce'] = cachedNonce;
  return h;
}

function parseList(text) {
  var j = $.json.parse(text);
  var list = j.series || [];
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var it = list[i];
    var link = it.link || '';
    var slug = link.split('/').filter(Boolean).pop() || link;
    out.push({
      key: '/manga/' + slug,
      title: it.name || '',
      coverUrl: it.cover || ''
    });
  }
  return { mangas: out, hasNextPage: (j.page || 1) < (j.total_pages || 1) };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(API + '/mangas/list?order=views&period=ever&page=' + page, HDRS);
    return parseList(text);
  },

  getSearchManga: async function (page, query) {
    var u = API + '/mangas/list?page=' + page;
    if (query) { u += '&filter=' + encodeURIComponent(query); }
    var text = await $.http.get(u, HDRS);
    return parseList(text);
  },

  getMangaDetail: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var text = await $.http.get(API + '/mangas/' + encodeURIComponent(slug), HDRS);
    var j = $.json.parse(text);
    var d = j.manga || {};
    var desc = d.description || '';
    if (d.alternative) { desc += (desc ? '\\n' : '') + '\\nTítulo alternativo: ' + d.alternative; }
    var genres = [];
    for (var i = 0; i < (d.genres || []).length; i++) { genres.push(d.genres[i].name || ''); }
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: d.coverUrl || '',
      author: d.author || '',
      description: desc.trim(),
      genre: genres.join(', '),
      status: d.status === 'ongoing' ? 'ongoing' : (d.status === 'completed' ? 'completed' : '')
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var text = await $.http.get(API + '/mangas/' + encodeURIComponent(slug), HDRS);
    var j = $.json.parse(text);
    var chapters = j.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var numStr = (c.number % 1 === 0) ? String(c.number) : String(c.number);
      var name = 'Capítulo ' + numStr;
      if (c.title && c.title !== numStr && c.title.toLowerCase() !== name.toLowerCase()) {
        name += ': ' + c.title;
      }
      out.push({
        key: '/chapters/' + c.id,
        name: name,
        chapterNumber: c.number,
        dateUpload: c.publishedAt ? Date.parse(c.publishedAt) || 0 : 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = chapterKey.split('/').pop();
    var url = API + '/chapters/' + encodeURIComponent(id);
    var text;
    try {
      text = await $.http.get(url, await nonceHeaders());
    } catch (e) {
      cachedNonce = null;
      text = await $.http.get(url, await nonceHeaders());
    }
    var j = $.json.parse(text);
    var pages = (j.pages || []).slice().sort(function (a, b) { return (a.number || 0) - (b.number || 0); });
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].imageUrl) { out.push({ index: out.length, url: pages[i].imageUrl }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
