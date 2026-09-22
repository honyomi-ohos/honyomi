// pt/onereader — JSON API (api.onereader.net)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['filters not ported'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.onereader.net';

function toStatus(s) {
  var v = String(s || '').trim().toLowerCase();
  if (v === 'em lançamento' || v === 'lançando') { return 'ongoing'; }
  if (v === 'completo') { return 'completed'; }
  if (v === 'hiatus' || v === 'hiato') { return 'hiatus'; }
  if (v === 'cancelado') { return 'cancelled'; }
  return '';
}

function parseSearch(text) {
  var j = $.json.parse(text);
  var out = [];
  var list = j.data || [];
  for (var i = 0; i < list.length; i++) {
    out.push({
      key: '/manga/' + list[i].manga_key,
      title: list[i].display_name || '',
      coverUrl: list[i].cover_image || ''
    });
  }
  return { mangas: out, hasNextPage: (j.page || 1) < (j.totalPages || 1) };
}

module.exports = {
  getPopularManga: async function (page) {
    var u = API + '/api/mangas/search?page=' + page + '&limit=24&order=az&role=standard&search=&genre=&type=&status=';
    return parseSearch(await $.http.get(u));
  },

  getSearchManga: async function (page, query) {
    var u = API + '/api/mangas/search?page=' + page + '&limit=24&order=az&role=standard&search=' + encodeURIComponent((query || '').trim()) + '&genre=&type=&status=';
    return parseSearch(await $.http.get(u));
  },

  getMangaDetail: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var text = await $.http.get(API + '/api/mangas/' + encodeURIComponent(id));
    var d = $.json.parse(text);
    var meta = [];
    if (d.name && d.name.trim() && d.name.toLowerCase() !== String(d.display_name || '').toLowerCase()) {
      meta.push('Título original: ' + d.name);
    }
    if (d.japanese_name && d.japanese_name.trim() && d.japanese_name.toLowerCase() !== String(d.display_name || '').toLowerCase() && d.japanese_name !== d.name) {
      meta.push('Título nativo: ' + d.japanese_name);
    }
    if (d.type && d.type.trim()) { meta.push('Tipo: ' + d.type); }
    if (d.origin_country && d.origin_country.trim()) { meta.push('País: ' + d.origin_country); }
    meta.push('Ano: ' + d.year);
    if (d.publisher_name && d.publisher_name.trim()) { meta.push('Editora: ' + d.publisher_name); }
    var desc = d.synopsis || '';
    if (desc && meta.length > 0) { desc += '\\n\\n'; }
    desc += meta.join('\\n');
    var tags = d.tags || [];
    if (typeof tags === 'string') {
      try { tags = $.json.parse(tags); } catch (e2) { tags = []; }
    }
    if (!Array.isArray(tags)) { tags = []; }
    return {
      key: mangaKey,
      title: d.display_name || '',
      coverUrl: d.cover_image || '',
      author: d.author || '',
      description: desc,
      genre: tags.join(', '),
      status: toStatus(d.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var text = await $.http.get(API + '/api/chapters/' + encodeURIComponent(id));
    var map = $.json.parse(text);
    var keys = Object.keys(map);
    keys.sort(function (a, b) {
      var na = parseFloat(a), nb = parseFloat(b);
      if (isNaN(na)) { return 1; }
      if (isNaN(nb)) { return -1; }
      return nb - na;
    });
    var out = [];
    for (var i = 0; i < keys.length; i++) {
      var c = map[keys[i]];
      out.push({
        key: '/reader/' + id + '/' + keys[i],
        name: 'Capítulo ' + keys[i],
        chapterNumber: parseFloat(keys[i]) || -1,
        dateUpload: c && c.posted_date ? Date.parse(c.posted_date) || 0 : 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = chapterKey.split('/').filter(Boolean);
    var number = parts.pop();
    var id = parts.pop();
    var numUnderscore = number.replace('.', '_');
    var text = await $.http.get(API + '/api/chapters/' + encodeURIComponent(id) + '/' + encodeURIComponent(numUnderscore));
    var j = $.json.parse(text);
    var out = [];
    var pages = j.pages || [];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i]) { out.push({ index: i, url: new URL(pages[i], API + '/').href }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
