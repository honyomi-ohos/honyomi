// all/taddyink — bespoke JSON-feed engine (taddy.org directory feeds)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['genre/creator/tag filters not portable; title display preference fixed to full title'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone JSON feed)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var LIMIT = 25;
var GENRE_MAP = {
  COMICSERIES_ACTION: 'Action', COMICSERIES_COMEDY: 'Comedy', COMICSERIES_DRAMA: 'Drama',
  COMICSERIES_EDUCATIONAL: 'Educational', COMICSERIES_FANTASY: 'Fantasy', COMICSERIES_HISTORICAL: 'Historical',
  COMICSERIES_HORROR: 'Horror', COMICSERIES_INSPIRATIONAL: 'Inspirational', COMICSERIES_MYSTERY: 'Mystery',
  COMICSERIES_ROMANCE: 'Romance', COMICSERIES_SCI_FI: 'Sci-Fi', COMICSERIES_SLICE_OF_LIFE: 'Slice Of Life',
  COMICSERIES_SUPERHERO: 'Superhero', COMICSERIES_SUPERNATURAL: 'Supernatural', COMICSERIES_WHOLESOME: 'Wholesome',
  COMICSERIES_BL: 'BL (Boy Love)', COMICSERIES_GL: 'GL (Girl Love)', COMICSERIES_LGBTQ: 'LGBTQ+',
  COMICSERIES_THRILLER: 'Thriller', COMICSERIES_ZOMBIES: 'Zombies', COMICSERIES_POST_APOCALYPTIC: 'Post Apocalyptic',
  COMICSERIES_SCHOOL: 'School', COMICSERIES_SPORTS: 'Sports', COMICSERIES_ANIMALS: 'Animals', COMICSERIES_GAMING: 'Gaming'
};

function comicToManga(c) {
  var thumbBase = (c.coverImage && c.coverImage.base_url) || '';
  var thumb = (c.coverImage && c.coverImage.cover_sm) || '';
  var genres = [];
  var gl = c.genres || [];
  for (var i = 0; i < gl.length; i++) {
    if (GENRE_MAP[gl[i]]) { genres.push(GENRE_MAP[gl[i]]); }
  }
  var creators = [];
  var cl = c.creators || [];
  for (var j = 0; j < cl.length; j++) {
    if (cl[j].name) { creators.push(cl[j].name); }
  }
  return {
    key: R_path(c.url),
    title: c.name || 'Unknown',
    coverUrl: (thumbBase && thumb) ? thumbBase + thumb : '',
    author: creators.join(', '),
    description: c.description || '',
    genre: genres.join(', '),
    status: 'ongoing',
  };
}
function parseDate(s) {
  if (!s) { return 0; }
  var ts = Date.parse(s);
  return isNaN(ts) ? 0 : ts;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/feeds/directory/list?lang=&taddyType=comicseries&ua=tc&page=' + page + '&limit=' + LIMIT);
    var j = JSON.parse(text);
    var list = j.comicseries || [];
    return { mangas: list.map(comicToManga), hasNextPage: list.length === LIMIT };
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/feeds/directory/search?q=' + encodeURIComponent(query || '') +
      '&lang=&taddyType=comicseries&ua=tc&page=' + page + '&limit=' + LIMIT);
    var j = JSON.parse(text);
    var list = j.comicseries || [];
    return { mangas: list.map(comicToManga), hasNextPage: list.length === LIMIT };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    return comicToManga(JSON.parse(text));
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var comic = JSON.parse(text);
    var issues = comic.issues || [];
    var out = [];
    for (var i = issues.length - 1; i >= 0; i--) {
      var ch = issues[i];
      out.push({
        key: R_path(comic.url) + '#' + ch.identifier,
        name: ch.name,
        chapterNumber: i + 1,
        dateUpload: parseDate(ch.datePublished),
        pages: 0,
        sortOrder: 0,
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var hashIdx = String(chapterKey).indexOf('#');
    var path = hashIdx >= 0 ? String(chapterKey).substring(0, hashIdx) : String(chapterKey);
    var issueUuid = hashIdx >= 0 ? String(chapterKey).substring(hashIdx + 1) : '';
    var text = await $.http.get(R_abs(path));
    var comic = JSON.parse(text);
    var issues = comic.issues || [];
    var issue = null;
    for (var i = 0; i < issues.length; i++) {
      if (issues[i].identifier === issueUuid) { issue = issues[i]; break; }
    }
    var pages = [];
    if (issue) {
      var stories = issue.stories || [];
      for (var s = 0; s < stories.length; s++) {
        var si = stories[s].storyImage;
        if (si && si.base_url && si.story) {
          pages.push({ index: pages.length, url: si.base_url + si.story });
        }
      }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
