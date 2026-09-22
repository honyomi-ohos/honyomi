// ar/ariatoon — bespoke JSON-API engine
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'genre browse filter not portable; plain text search only',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.ariatoon.com/v1';
var CDN = 'https://api.ariatoon.com/uploads';

function headers() {
  return { Accept: 'application/json' };
}

function mangaOut(d) {
  var status = '';
  if (d.status === 'ongoing') { status = 'ongoing'; }
  else if (d.status === 'completed') { status = 'completed'; }
  else if (d.status === 'hiatus') { status = 'hiatus'; }
  var desc = '';
  if (d.summary) { desc = d.summary; }
  if (d.announce) {
    if (desc) { desc += '\\n\\n'; }
    desc += 'إعلان:\\n' + d.announce;
  }
  return {
    key: '/series/manga/' + d.id,
    title: d.title,
    coverUrl: CDN + '/' + d.coverPath,
    author: d.author || '',
    artist: '',
    description: desc,
    genre: '',
    status: status,
  };
}

function chapterName(c) {
  var name = '';
  if (c.number !== null && c.number !== undefined) {
    name += 'الفصل ' + String(c.number).replace(/\\.0$/, '');
    if (c.title) { name += ' - '; }
  }
  if (c.title) { name += c.title; }
  if (!name) { name = 'الفصل'; }
  return name;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(API + '/feed/mangas/popular?page=' + page + '&limit=20', headers());
    var data = JSON.parse(text).data || [];
    var out = [];
    for (var i = 0; i < data.length; i++) { out.push(mangaOut(data[i])); }
    return { mangas: out, hasNextPage: data.length === 20 };
  },

  getSearchManga: async function (page, query) {
    var url;
    if (query) {
      url = API + '/mangas/search?page=' + page + '&limit=20&search=' + encodeURIComponent(query);
    } else {
      url = API + '/mangas?page=' + page + '&limit=20';
    }
    var text = await $.http.get(url, headers());
    var data = JSON.parse(text).data || [];
    var out = [];
    for (var i = 0; i < data.length; i++) { out.push(mangaOut(data[i])); }
    return { mangas: out, hasNextPage: data.length === 20 };
  },

  getMangaDetail: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var text = await $.http.get(API + '/mangas/' + id, headers());
    return mangaOut(JSON.parse(text).data);
  },

  getChapterList: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var collected = [];
    for (var page = 1; page <= 20; page++) {
      var text = await $.http.get(API + '/mangas/' + id + '/episodes?direction=desc&publishStatus=published&limit=100&page=' + page, headers());
      var data = JSON.parse(text).data || [];
      if (!data.length) { break; }
      collected = collected.concat(data);
      if (data.length < 100) { break; }
    }
    var out = [];
    for (var i = 0; i < collected.length; i++) {
      var c = collected[i];
      var ts = Date.parse(c.createdAt);
      out.push({
        key: '/series/manga/' + c.mangaID + '/episodes/' + c.id,
        name: chapterName(c),
        chapterNumber: (c.number === null || c.number === undefined) ? -1 : c.number,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0,
      });
    }
    // API returns newest-first (direction=desc); host convention is oldest-first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = String(chapterKey).split('/').filter(Boolean);
    // /series/manga/<mangaId>/episodes/<episodeId>
    var mangaId = parts[2] || '';
    var episodeId = parts[4] || '';
    var text = await $.http.get(API + '/mangas/' + mangaId + '/episodes/' + episodeId, headers());
    var images = (JSON.parse(text).data || {}).images || [];
    var pages = [];
    for (var i = 0; i < images.length; i++) {
      pages.push({ index: i, url: CDN + '/' + images[i] });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
