// pt/roxinha — JSON API (/api) with chapter-access ticket; account login optional (not ported)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'reading chapters requires an account (x-chapter-access endpoint returns 401 anonymously); login not supported — pages will fail without credentials',
      'filters not ported',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = BASE + '/api';
var HDRS = { Referer: BASE + '/', Origin: BASE };

function toStatus(s) {
  var v = String(s || '').trim().toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  return '';
}

function parseList(text) {
  var j = $.json.parse(text);
  var out = [];
  var list = j.mangas || [];
  for (var i = 0; i < list.length; i++) {
    out.push({
      key: '/manga/' + list[i].id,
      title: list[i].title || '',
      coverUrl: list[i].cover ? BASE + list[i].cover : ''
    });
  }
  return { mangas: out, hasNextPage: j.hasMore === true };
}

module.exports = {
  getPopularManga: async function (page) {
    var offset = (page - 1) * 24;
    var u = API + '/manga/search/advanced?sort=views&order=DESC&limit=24&offset=' + offset;
    return parseList(await $.http.get(u, HDRS));
  },

  getSearchManga: async function (page, query) {
    var offset = (page - 1) * 24;
    var u = API + '/manga/search/advanced?limit=24&offset=' + offset + '&mode=default&sort=title&order=ASC';
    var q = (query || '').trim();
    if (q) { u += '&q=' + encodeURIComponent(q); }
    return parseList(await $.http.get(u, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var d = $.json.parse(await $.http.get(API + '/manga/' + id, HDRS));
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: d.cover ? BASE + d.cover : '',
      author: d.author || '',
      description: d.description || '',
      genre: d.genres || '',
      status: toStatus(d.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var d = $.json.parse(await $.http.get(API + '/manga/' + id, HDRS));
    var chapters = d.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var name;
      var t = (c.title || '').trim();
      if (t && isNaN(parseFloat(t))) {
        name = t;
      } else {
        var numStr = c.chapterNumber === null || c.chapterNumber === undefined
          ? ''
          : String(c.chapterNumber).replace(/\\.0$/, '');
        name = ('Capítulo ' + numStr).trim();
      }
      out.push({
        key: '/chapter/' + c.id,
        name: name,
        chapterNumber: c.chapterNumber === null || c.chapterNumber === undefined ? -1 : c.chapterNumber,
        dateUpload: c.createdAt ? Date.parse(c.createdAt) || 0 : 0,
        pages: 0
      });
    }
    out.sort(function (a, b) { return b.chapterNumber - a.chapterNumber; });
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = chapterKey.split('/').pop();
    var chapterUrl = API + '/manga/chapter/' + id;
    var access = $.json.parse(await $.http.get(chapterUrl + '/access', HDRS));
    var hdrs = {
      Referer: BASE + '/',
      Origin: BASE,
      'x-chapter-access': access.ticket
    };
    var d = $.json.parse(await $.http.get(chapterUrl, hdrs));
    var out = [];
    var pages = d.pages || [];
    for (var i = 0; i < pages.length; i++) {
      out.push({ index: i, url: BASE + pages[i] });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
