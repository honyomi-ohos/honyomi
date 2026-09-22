// en/revivalscans — bespoke RSC scraper (Next.js flight payloads for all endpoints)
export const runtime = 'wp';

import { RSC_SRC } from './_nextjs.mjs';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['premium chapters are hidden (default of original source; they are unreadable without subscription)'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/', RSC: '1' };
${RSC_SRC}
var STATUS_MAP = { ongoing: 'ongoing', completed: 'completed', hiatus: 'hiatus' };

function isPremium(ch) {
  return !!(ch.accessRoles && ch.accessRoles.indexOf('reader') < 0);
}

async function fetchSeriesList() {
  var rows = RSC.parse(await $.http.get(BASE + '/series', HDRS));
  var series = RSC.arr(rows, 'series') || [];
  var out = [];
  for (var i = 0; i < series.length; i++) {
    var s = series[i];
    out.push({
      key: String(s.id),
      title: s.title || '',
      coverUrl: s.coverImage ? R_abs(s.coverImage) : ''
    });
  }
  return out;
}

async function fetchManhwa(mangaKey) {
  var rows = RSC.parse(await $.http.get(BASE + '/series/' + mangaKey, HDRS));
  var wrapper = RSC.find(rows, ['manhwa']);
  return wrapper ? wrapper.manhwa : null;
}

module.exports = {
  getPopularManga: async function () {
    return { mangas: await fetchSeriesList(), hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var q = (query || '').toLowerCase();
    var all = await fetchSeriesList();
    var out = [];
    for (var i = 0; i < all.length; i++) {
      if (!q || all[i].title.toLowerCase().indexOf(q) >= 0) { out.push(all[i]); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var m = await fetchManhwa(mangaKey);
    if (!m) {
      return { key: mangaKey, title: '', coverUrl: '', author: '', description: '', genre: '', status: '' };
    }
    var genres = m.genres || [];
    return {
      key: mangaKey,
      title: m.title || '',
      coverUrl: m.coverImage ? R_abs(m.coverImage) : '',
      author: m.author || '',
      artist: m.artist || '',
      description: m.description || '',
      genre: genres.join(', '),
      status: STATUS_MAP[String(m.status || '').toLowerCase()] || ''
    };
  },

  getChapterList: async function (mangaKey) {
    var m = await fetchManhwa(mangaKey);
    if (!m) { return []; }
    var list = m.chapters || [];
    var chapters = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      if (isPremium(c)) { continue; }
      var n = typeof c.number === 'number' ? c.number : parseFloat(c.number);
      var chName = c.title || ('Chapter ' + String(c.number).replace(/\\.0$/, ''));
      if (isPremium(c)) { chName = '🔒 ' + chName; }
      chapters.push({
        key: '/read/' + mangaKey + '/' + c.id,
        name: chName,
        chapterNumber: isNaN(n) ? -1 : n,
        dateUpload: c.releaseDate ? (Date.parse(c.releaseDate) || 0) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    chapters.sort(function (a, b) { return a.chapterNumber - b.chapterNumber; });
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var rows = RSC.parse(await $.http.get(BASE + chapterKey, HDRS));
    var pagesDto = RSC.arr(rows, 'pages') || [];
    var pages = [];
    for (var i = 0; i < pagesDto.length; i++) {
      var u = pagesDto[i].url;
      if (!u) { continue; }
      pages.push({ index: pages.length, url: /^https?:\\/\\//.test(u) ? u : BASE + u });
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
