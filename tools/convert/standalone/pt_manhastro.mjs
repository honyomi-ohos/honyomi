// pt/manhastro — JSON API (api2.manhastro.net)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['searches filter the full /dados catalog client-side; genre/type filters not ported'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api2.manhastro.net';

function clean(text) {
  var v = String(text).replace(/^\\uFEFF/, '');
  while (true) {
    var t = v;
    t = t.replace(/^\\)\\]\\}'/, '').replace(/^,/, '').replace(/^_/, '').replace(/^\\s+/, '');
    if (t === v) { break; }
    v = t;
  }
  return v;
}

async function apiGet(path) {
  var text = await $.http.get(API + path);
  return $.json.parse(clean(text));
}

var allCache = null;
var rankCache = null;

async function fetchAll() {
  if (allCache) { return allCache; }
  var j = await apiGet('/dados');
  allCache = j.data || [];
  return allCache;
}

async function fetchRank() {
  if (rankCache) { return rankCache; }
  var j = await apiGet('/rank/diario');
  rankCache = j.data || [];
  return rankCache;
}

async function findManga(id) {
  var all = await fetchAll();
  for (var i = 0; i < all.length; i++) {
    if (all[i].manga_id === id) { return all[i]; }
  }
  var rank = await fetchRank();
  for (var k = 0; k < rank.length; k++) {
    if (rank[k].manga_id === id) { return rank[k]; }
  }
  return null;
}

function toManga(m) {
  var title = (m.titulo_brasil && m.titulo_brasil.trim()) ? m.titulo_brasil : m.titulo;
  var cover = m.imagem || '';
  if (cover && cover.indexOf('http') !== 0) { cover = 'https://' + cover; }
  return {
    key: '/manga/' + m.manga_id,
    title: title || '',
    coverUrl: cover
  };
}

function normalize(s) {
  return String(s || '').toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
}

module.exports = {
  getPopularManga: async function (page) {
    var rank = await apiGet('/rank/diario');
    var out = [];
    var ids = rank.data || [];
    for (var k = 0; k < ids.length; k++) {
      var m = ids[k];
      if (m && m.manga_id !== undefined && (m.titulo || m.titulo_brasil)) { out.push(toManga(m)); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var all = await fetchAll();
    var q = normalize(query);
    var filtered = all;
    if (q) {
      filtered = [];
      for (var i = 0; i < all.length; i++) {
        var m = all[i];
        if (normalize(m.titulo).indexOf(q) >= 0 || normalize(m.titulo_brasil).indexOf(q) >= 0) {
          filtered.push(m);
        }
      }
    }
    filtered = filtered.slice().sort(function (a, b) {
      return (parseInt(b.views_mes, 10) || 0) - (parseInt(a.views_mes, 10) || 0);
    });
    var start = (page - 1) * 30;
    var slice = filtered.slice(start, start + 30);
    var out = [];
    for (var s = 0; s < slice.length; s++) { out.push(toManga(slice[s])); }
    return { mangas: out, hasNextPage: start + 30 < filtered.length };
  },

  getMangaDetail: async function (mangaKey) {
    var id = parseInt(mangaKey.split('/').pop(), 10);
    var found = await findManga(id);
    if (!found) { throw new Error('Manga not found'); }
    var m = toManga(found);
    return {
      key: mangaKey,
      title: m.title,
      coverUrl: m.coverUrl,
      author: '',
      description: (found.descricao_brasil && found.descricao_brasil.trim()) ? found.descricao_brasil : (found.descricao || ''),
      genre: (found.generos || []).join(', '),
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var j = await apiGet('/dados/' + id);
    var chapters = j.data || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var numMatch = String(c.capitulo_nome || '').match(/(\\d+(?:\\.\\d+)?)/);
      out.push({
        key: '/capitulo/' + c.capitulo_id,
        name: c.capitulo_nome || '',
        chapterNumber: numMatch ? parseFloat(numMatch[1]) : -1,
        dateUpload: c.capitulo_data ? Date.parse(String(c.capitulo_data).replace(' ', 'T')) || 0 : 0,
        pages: 0,
        sortOrder: 0,
        _n: numMatch ? parseFloat(numMatch[1]) : -1
      });
    }
    out.sort(function (a, b) { return b._n - a._n; });
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; delete out[k]._n; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = chapterKey.split('/').pop();
    var j = await apiGet('/paginas/' + id);
    var ch = j.data && j.data.chapter;
    if (!ch) { return []; }
    var out = [];
    for (var i = 0; i < (ch.data || []).length; i++) {
      out.push({ index: i, url: ch.baseUrl + '/' + ch.hash + '/' + ch.data[i] });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
