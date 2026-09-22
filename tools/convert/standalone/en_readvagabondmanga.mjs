// en/readvagabondmanga — bespoke JSON API scraper
export const runtime = 'wp';

export function extract(ctx) {
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };
var STATUS_MAP = { ongoing: 'ongoing', completed: 'completed', hiatus: 'hiatus' };

function toManga(m) {
  return {
    key: '/api/mihon/mangas/' + m.id,
    title: m.title || '',
    coverUrl: R_abs(m.cover || '')
  };
}

module.exports = {
  getPopularManga: async function () {
    var list = $.json.parse(await $.http.get(BASE + '/api/mihon/mangas', HDRS));
    var out = [];
    for (var i = 0; i < list.length; i++) { out.push(toManga(list[i])); }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/api/mihon/mangas?q=' + encodeURIComponent(query || '') + '&page=' + page;
    var list = $.json.parse(await $.http.get(u, HDRS));
    var out = [];
    for (var i = 0; i < list.length; i++) { out.push(toManga(list[i])); }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var m = $.json.parse(await $.http.get(BASE + mangaKey, HDRS));
    return {
      key: mangaKey,
      title: m.title || '',
      coverUrl: R_abs(m.cover || ''),
      author: m.author || '',
      artist: m.artist || '',
      description: m.description || '',
      genre: '',
      status: STATUS_MAP[String(m.status || '').toLowerCase()] || 'ongoing'
    };
  },

  getChapterList: async function (mangaKey) {
    var list = $.json.parse(await $.http.get(BASE + mangaKey + '/chapters', HDRS));
    var chapters = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      chapters.push({
        key: mangaKey + '/chapters/' + c.number,
        name: c.title || ('Chapter ' + c.number),
        chapterNumber: typeof c.number === 'number' ? c.number : -1,
        dateUpload: R_date(c.releaseDate || ''),
        pages: 0,
        sortOrder: 0
      });
    }
    chapters.sort(function (a, b) { return a.chapterNumber - b.chapterNumber; });
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var c = $.json.parse(await $.http.get(BASE + chapterKey, HDRS));
    var pages = [];
    var count = c.pageCount || 0;
    for (var i = 1; i <= count; i++) {
      pages.push({ index: i - 1, url: 'https://pub.moleve.net/chapter-' + c.number + '/page-' + i + '.png' });
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
