// en/mangamelon — JSON API (api.mangamelon.com); requests are form POSTs carrying a
// base64-encoded JSON body in the "data" field. Default-valued fields must be included
// or the server hides NSFW content (per upstream comment).
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['genre/sort filters not ported; popular=sort:popular, search=sort:latest'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.mangamelon.com';
var PAGE_SIZE = 36;
var CHAPTER_LIMIT = 1000;
var HDRS = { 'Content-Type': 'application/x-www-form-urlencoded', Referer: BASE + '/' };

async function api(path, bodyObj) {
  var data = $.crypto.base64Encode($.json.stringify(bodyObj));
  var text = await $.http.post(API + '/' + path, R_form([['data', data], ['sessionid', '']]), HDRS);
  return $.json.parse(text);
}

function mangaStatus(s) {
  var v = String(s || '').toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  if (v === 'licensed') { return 'licensed'; }
  if (v === 'on hiatus' || v === 'hiatus') { return 'on hiatus'; }
  if (v === 'cancelled' || v === 'canceled') { return 'cancelled'; }
  return '';
}

function dtoToManga(dto) {
  var genres = dto.genres || [];
  return {
    key: '/manga/' + dto.id,
    title: dto.title || '',
    coverUrl: dto.cover || '',
    author: dto.authors || '',
    description: dto.desc || '',
    genre: genres.join(', '),
    status: mangaStatus(dto.status)
  };
}

function idFromKey(key) {
  // '/manga/<id>' -> '<id>'
  return String(key).replace(/^\\/manga\\//, '');
}

function listBody(search, sort, page) {
  return {
    search: search,
    genre: '',
    lang: 'en',
    sort: sort,
    includeNsfw: true,
    limit: PAGE_SIZE,
    skip: (page - 1) * PAGE_SIZE
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var res = await api('api/manga/list', listBody('', 'popular', page));
    var list = res.list || [];
    var skip = (page - 1) * PAGE_SIZE;
    var hasNext = res.total > 0 ? (skip + list.length < res.total) : (list.length >= PAGE_SIZE);
    return { mangas: list.map(dtoToManga), hasNextPage: hasNext };
  },

  getSearchManga: async function (page, query) {
    var res = await api('api/manga/list', listBody(query || '', 'latest', page));
    var list = res.list || [];
    var skip = (page - 1) * PAGE_SIZE;
    var hasNext = res.total > 0 ? (skip + list.length < res.total) : (list.length >= PAGE_SIZE);
    return { mangas: list.map(dtoToManga), hasNextPage: hasNext };
  },

  getMangaDetail: async function (mangaKey) {
    var res = await api('api/manga/get', { target: idFromKey(mangaKey), withReviews: false });
    var m = dtoToManga(res.manga || {});
    m.key = mangaKey;
    return m;
  },

  getChapterList: async function (mangaKey) {
    var id = idFromKey(mangaKey);
    var chapters = [];
    var skip = 0;
    var batch;
    do {
      var res = await api('api/chapter/list', { target: id, status: 0, limit: CHAPTER_LIMIT, skip: skip, pending: '', force: true });
      batch = res.chapters || [];
      chapters = chapters.concat(batch);
      skip += batch.length;
    } while (batch.length === CHAPTER_LIMIT);
    chapters.sort(function (a, b) { return (a.seq || 0) - (b.seq || 0); });
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var ch = chapters[i];
      var updated = ch.updated && String(ch.updated).indexOf('0001-') !== 0 ? (Date.parse(ch.updated) || 0) : 0;
      out.push({
        key: '/chapter/' + id + '/' + ch.id,
        name: ch.title || ('Chapter ' + (i + 1)),
        chapterNumber: -1,
        dateUpload: updated,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    // '/chapter/<mangaId>/<chapterId>'
    var parts = String(chapterKey).split('/');
    var chapterId = parts[parts.length - 1];
    var res = await api('api/chapter/get', { target: chapterId, all: true });
    var pages = (res.chapter && res.chapter.pages) || [];
    pages.sort(function (a, b) { return (a.seq || 0) - (b.seq || 0); });
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].url) { out.push({ index: out.length, url: pages[i].url }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
