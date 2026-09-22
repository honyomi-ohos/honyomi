// en/mangauno (mangauno.com?) — JSON API under {base}/api; covers served from fstr-cdn
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['title-language preference not ported (English titles used); filters not ported, text search only'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = BASE + '/api';
var CDN = 'https://xz7.fstr-cdn.com';
var PAGE_SIZE = 24;

function pickTitle(dto) {
  return (dto.english_title && dto.english_title.length ? dto.english_title : null) ||
    dto.title || '';
}

function dtoToManga(dto) {
  return {
    key: '/m/' + dto.slug,
    title: pickTitle(dto),
    coverUrl: dto.cover ? (CDN + dto.cover) : ''
  };
}

function statusMap(s) {
  var v = String(s || '').toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  if (v === 'hiatus') { return 'on hiatus'; }
  if (v === 'cancelled') { return 'cancelled'; }
  return '';
}

function unescapeEntities(s) {
  return String(s || '')
    .replace(/&#(\\d+);/g, function (m, n) { return String.fromCharCode(parseInt(n, 10)); })
    .replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>');
}

function parseJsonArrayField(s) {
  if (!s) { return []; }
  try {
    var v = $.json.parse(s);
    return Array.isArray(v) ? v : [];
  } catch (e) { return []; }
}

module.exports = {
  getPopularManga: async function (page) {
    var res = $.json.parse(await $.http.get(API + '/list/popular?page=' + page + '&limit=' + PAGE_SIZE));
    var list = (res.data || []).map(dtoToManga);
    return { mangas: list, hasNextPage: list.length >= PAGE_SIZE };
  },

  getSearchManga: async function (page, query) {
    var u = API + '/search/advanced?page=' + page + '&limit=' + PAGE_SIZE +
      (query ? '&title=' + encodeURIComponent(query) : '');
    var res = $.json.parse(await $.http.get(u));
    var list = (res.data || []).map(dtoToManga);
    return { mangas: list, hasNextPage: list.length >= PAGE_SIZE };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/m\\//, '');
    var res = $.json.parse(await $.http.get(API + '/manga/' + encodeURIComponent(slug)));
    var m = res.manga || {};
    var genres = parseJsonArrayField(m.genres).concat(parseJsonArrayField(m.tags)).filter(function (g) { return g; });
    return {
      key: mangaKey,
      title: pickTitle(m),
      coverUrl: m.cover ? (CDN + m.cover) : '',
      author: (m.author || '').replace(/ & /g, ', '),
      artist: (m.artist || '').replace(/ & /g, ', '),
      description: m.synopsis || '',
      genre: genres.join(', '),
      status: statusMap(m.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/m\\//, '');
    var res = $.json.parse(await $.http.get(API + '/manga/' + encodeURIComponent(slug)));
    var chapters = res.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var ch = chapters[i];
      var num = parseFloat(ch.chapter_number);
      var parts = [];
      if (!isNaN(num)) { parts.push('Ch. ' + num); }
      if (typeof ch.volume === 'number') { parts.push('Vol. ' + ch.volume); }
      var t = unescapeEntities(ch.title);
      if (t) { parts.push(t); }
      var chName = parts.join(' \\u2013 ');
      out.push({
        key: '/r/' + slug + '/' + ch.id,
        name: chName || 'Chapter',
        chapterNumber: isNaN(num) ? -1 : num,
        dateUpload: ch.published_at ? (Date.parse(ch.published_at) || 0) : 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).split('/').pop();
    var res = $.json.parse(await $.http.get(API + '/chapter/' + encodeURIComponent(id)));
    var pages = res.pages || [];
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i]) { out.push({ index: out.length, url: pages[i] }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
