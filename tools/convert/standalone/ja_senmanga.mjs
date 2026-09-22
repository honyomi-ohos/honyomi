// ja/senmanga — Sen Manga (JSON API)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  const body = String.raw`
var API = BASE + '/api';

function toManga(s) {
  return { key: s.slug || '', title: s.title || '', coverUrl: s.cover || '' };
}

function parseStatus(v) {
  var s = String(v || '').toLowerCase();
  if (!s) { return 'unknown'; }
  if (s.indexOf('ongoing') >= 0) { return 'ongoing'; }
  if (s.indexOf('complete') >= 0) { return 'completed'; }
  if (s.indexOf('hiatus') >= 0) { return 'on_hiatus'; }
  if (s.indexOf('dropped') >= 0) { return 'cancelled'; }
  return 'unknown';
}

module.exports = {
  getPopularManga: async function (page) {
    var json = $.json.parse(await H_get(API + '/directory?order=Popular&page=' + page));
    return {
      mangas: (json.series || []).map(toManga),
      hasNextPage: (json.currentPage || 1) < (json.totalPages || 1)
    };
  },

  getLatestManga: async function (page) {
    var json = $.json.parse(await H_get(API + '/home?page=' + page));
    var mangas = (json.series || []).map(toManga);
    return { mangas: mangas, hasNextPage: mangas.length > 0 };
  },

  getSearchManga: async function (page, query) {
    var u = API + '/directory?page=' + page + (query ? '&s=' + encodeURIComponent(query) : '');
    var json = $.json.parse(await H_get(u));
    return {
      mangas: (json.series || []).map(toManga),
      hasNextPage: (json.currentPage || 1) < (json.totalPages || 1)
    };
  },

  getMangaDetail: async function (mangaKey) {
    var json = $.json.parse(await H_get(API + '/manga/' + mangaKey));
    return {
      key: json.slug || String(mangaKey),
      title: json.title || String(mangaKey),
      coverUrl: json.cover || '',
      description: json.description || '',
      genre: json.genre || '',
      status: parseStatus(json.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var json = $.json.parse(await H_get(API + '/manga/' + mangaKey));
    var slug = json.slug || mangaKey;
    var list = json.chapterList || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      if (!c.url) { continue; }
      var ts = c.datetime ? Date.parse(c.datetime) : NaN;
      out.push({
        key: slug + '/' + c.url,
        name: c.title || c.url,
        chapterNumber: -1,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var json = $.json.parse(await H_get(API + '/read/' + chapterKey));
    var pages = json.pages || [];
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i]) { out.push({ index: out.length, url: pages[i] }); }
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
