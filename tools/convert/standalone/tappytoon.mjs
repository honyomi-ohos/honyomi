// all/tappytoon — bespoke engine (api-global.tappytoon.com JSON API; auth from homepage __NEXT_DATA__)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'multi-language ext collapsed to single plugin (locale=en)',
      'gradle baseUrl is an uninterpolated Kotlin template (https://www.tappytoon.com/$it); engine hardcodes https://www.tappytoon.com/en and never uses manifest.baseUrl',
      'genre filter and Link-header search pagination not portable (single search page)',
      'details may be sparse for comics absent from trending/default lists (source has no details-by-id endpoint)',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone JSON API)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = 'https://www.tappytoon.com/en';
var API = 'https://api-global.tappytoon.com';
var LANG = 'en';
var apiHeadersCache = null;

async function apiHeaders() {
  if (apiHeadersCache) { return apiHeadersCache; }
  var home = await $.http.get(BASE);
  var doc = $.html.parse(home);
  var el = R_selFirst(doc, '#__NEXT_DATA__');
  if (!el) { throw new Error('missing __NEXT_DATA__ on homepage'); }
  var obj = JSON.parse(el.text());
  var ax = obj.props.initialState.axios.headers;
  apiHeadersCache = {
    'Origin': 'https://www.tappytoon.com',
    'Accept-Language': LANG,
    'Authorization': ax.Authorization,
    'X-Device-Uuid': ax['X-Device-Uuid'],
    'Referer': 'https://www.tappytoon.com/',
  };
  return apiHeadersCache;
}

async function apiGet(path) {
  return JSON.parse(await $.http.get(API + path, await apiHeaders()));
}

function comicToManga(c) {
  return {
    key: '/comics/' + c.slug + '|' + c.id,
    title: c.title,
    coverUrl: c.posterThumbnailUrl || '',
  };
}
function keyId(key) {
  var s = String(key);
  return s.substring(s.indexOf('|') + 1);
}
function keySlug(key) {
  var s = String(key);
  return s.substring(s.lastIndexOf('/') + 1, s.indexOf('|'));
}
function padNum(s) { return String(s).length < 2 ? '0' + s : s; }
function parseDate(s) {
  if (!s) { return 0; }
  var m = String(s).match(/^(\\d+)-(\\d+)-(\\d+)T(.*)$/);
  var norm = m ? m[1] + '-' + padNum(m[2]) + '-' + padNum(m[3]) + 'T' + m[4] : s;
  var ts = Date.parse(norm);
  return isNaN(ts) ? 0 : ts;
}
function comicDetails(c, key) {
  var genres = [];
  for (var i = 0; i < (c.genres || []).length; i++) { genres.push(c.genres[i].name); }
  genres.push('Rating: ' + (c.ageRating ? c.ageRating.name : ''));
  var authors = [];
  for (var j = 0; j < (c.authors || []).length; j++) { authors.push(c.authors[j].name); }
  var status = '';
  if (c.isCompleted) { status = 'completed'; }
  else if (!c.isHiatus) { status = 'ongoing'; }
  return {
    key: key,
    title: c.title,
    coverUrl: c.posterThumbnailUrl || '',
    author: authors.join(', '),
    artist: authors.join(', '),
    description: c.longDescription || '',
    genre: genres.join(', '),
    status: status,
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var list = (await apiGet('/comics?sort_by=trending&filter=completed&locale=' + LANG)) || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].isAccessible) { out.push(comicToManga(list[i])); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var list = (await apiGet('/comics?locale=' + LANG + '&keyword=' + encodeURIComponent(query || ''))) || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].isAccessible) { out.push(comicToManga(list[i])); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var id = keyId(mangaKey);
    var lists = [
      '/comics?sort_by=trending&filter=completed&locale=' + LANG,
      '/comics?locale=' + LANG,
    ];
    for (var l = 0; l < lists.length; l++) {
      var list = (await apiGet(lists[l])) || [];
      for (var i = 0; i < list.length; i++) {
        if (String(list[i].id) === String(id)) { return comicDetails(list[i], mangaKey); }
      }
    }
    return {
      key: mangaKey,
      title: keySlug(mangaKey).replace(/-/g, ' '),
      coverUrl: '',
      author: '',
      description: '',
      genre: '',
      status: '',
    };
  },

  getChapterList: async function (mangaKey) {
    var raw = (await apiGet('/comics/' + keyId(mangaKey) + '/chapters?locale=' + LANG)) || [];
    var chapters = [];
    for (var i = 0; i < raw.length; i++) {
      if (raw[i].isAccessible) { chapters.push(raw[i]); }
    }
    chapters.reverse();
    var out = [];
    for (var j = 0; j < chapters.length; j++) {
      var ch = chapters[j];
      var name = ch.title || '';
      if (ch.subtitle) { name += ' - ' + ch.subtitle; }
      if (!ch.isFree && !(ch.isUserUnlocked || ch.isUserRented)) { name += ' \\uD83D\\uDD12'; }
      out.push({
        key: '/chapters/' + ch.id,
        name: name,
        chapterNumber: (ch.order || 0) + 1,
        dateUpload: parseDate(ch.willAccessibleAt),
        pages: 0,
        sortOrder: j,
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).split('/').pop();
    var j = await apiGet('/content-delivery/contents?chapterId=' + id + '&variant=high&locale=' + LANG);
    // current API wraps media in {media:[...]}; older shape was a bare array of {url}
    var arr = Array.isArray(j) ? j : (j && j.media) || [];
    var out = [];
    for (var i = 0; i < arr.length; i++) {
      var u = arr[i] && (arr[i].url || arr[i].path);
      if (u) { out.push({ index: out.length, url: u }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: 'https://www.tappytoon.com/' };
  },
};
`;
}
