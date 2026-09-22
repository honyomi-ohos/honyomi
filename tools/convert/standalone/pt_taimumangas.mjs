// pt/taimumangas — JSON API (apiv2.taimumangas.com/api/v1/reader)
export const runtime = 'wp';

export function extract(ctx) {
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
var API = 'https://apiv2.taimumangas.com/api/v1/reader';
var HDRS = { Accept: 'application/json', Referer: BASE + '/' };

function toStatus(s) {
  var v = String(s || '').toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'finished') { return 'completed'; }
  if (v === 'hiatus') { return 'hiatus'; }
  if (v === 'dropped') { return 'cancelled'; }
  return '';
}

function parseDate(date) {
  var v = String(date || '').trim();
  if (!v) { return 0; }
  v = v.replace(/\\.(\\d{3})\\d+/, '.$1');
  return Date.parse(v) || 0;
}

function parseLibrary(text) {
  var j = $.json.parse(text);
  var out = [];
  var list = j.items || [];
  for (var i = 0; i < list.length; i++) {
    out.push({
      key: '/series/' + list[i].identifier,
      title: list[i].title || '',
      coverUrl: list[i].cover || ''
    });
  }
  var perPage = j.per_page || 0;
  return { mangas: out, hasNextPage: (j.page || 1) * perPage < (j.total || 0) };
}

module.exports = {
  getPopularManga: async function (page) {
    var u = API + '/library?page=' + page + '&per_page=24&adult=true&sort=rating&order=desc';
    return parseLibrary(await $.http.get(u, HDRS));
  },

  getSearchManga: async function (page, query) {
    var u = API + '/library?page=' + page + '&per_page=24&adult=true';
    var q = (query || '').trim();
    if (q) { u += '&q=' + encodeURIComponent(q); }
    return parseLibrary(await $.http.get(u, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var d = $.json.parse(await $.http.get(API + '/series/' + encodeURIComponent(id), HDRS));
    var authors = [], artists = [], genres = [];
    (d.authors || []).forEach(function (a) { authors.push(a.name); });
    (d.artists || []).forEach(function (a) { artists.push(a.name); });
    (d.genres || []).forEach(function (g) { genres.push(g.name); });
    var desc = '';
    if (d.synopsis && String(d.synopsis).trim()) { desc = String(d.synopsis).trim(); }
    if (d.type && String(d.type).trim()) {
      if (desc) { desc += '\\n\\n'; }
      desc += 'Tipo: ' + d.type;
    }
    if (d.group && d.group.name && String(d.group.name).trim()) {
      if (desc) { desc += '\\n\\n'; }
      desc += 'Scanlator: ' + d.group.name;
    }
    if (d.adult) {
      if (desc) { desc += '\\n\\n'; }
      desc += 'Conteudo adulto';
    }
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: d.cover || '',
      author: authors.join(', '),
      artist: artists.join(', '),
      genre: genres.join(', '),
      status: toStatus(d.status),
      description: desc
    };
  },

  getChapterList: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var all = [];
    var page = 1;
    for (;;) {
      var u = API + '/series/' + encodeURIComponent(id) + '/chapters?page=' + page + '&per_page=100&order=desc';
      var j = $.json.parse(await $.http.get(u, HDRS));
      var items = j.items || [];
      for (var i = 0; i < items.length; i++) {
        all.push(items[i]);
      }
      if (!j.has_more || items.length === 0) { break; }
      page = (j.page || page) + 1;
    }
    var out = [];
    for (var k = 0; k < all.length; k++) {
      var c = all[k];
      var num = parseFloat(c.number);
      out.push({
        key: '/reader/' + c.identifier,
        name: 'Capitulo ' + String(c.number),
        chapterNumber: isNaN(num) ? -1 : num,
        dateUpload: parseDate(c.published_at),
        pages: 0
      });
    }
    out.reverse();
    for (var m = 0; m < out.length; m++) { out[m].sortOrder = m; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = chapterKey.split('/').pop();
    var j = $.json.parse(await $.http.get(API + '/chapters/' + encodeURIComponent(id) + '?adult=true', HDRS));
    var pages = (j.pages || []).slice();
    pages.sort(function (a, b) { return (a.number || 0) - (b.number || 0); });
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      out.push({ index: i, url: pages[i].url });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
