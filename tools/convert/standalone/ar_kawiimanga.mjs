// ar/kawiimanga — bespoke JSON-API engine
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://manga-api.kawaii-anime.com/api/manga/own';

function headers() {
  return { 'x-app-key': 'km_2026_live' };
}

function valid(s) {
  if (!s) { return ''; }
  var t = String(s);
  if (!t.trim() || t.toLowerCase() === 'unknown') { return ''; }
  return t;
}

function mangaOut(d) {
  var status = '';
  if (d.status === 'ongoing' || d.status === 'coming_soon') { status = 'ongoing'; }
  else if (d.status === 'completed') { status = 'completed'; }
  else if (d.status === 'cancelled' || d.status === 'dropped') { status = 'cancelled'; }
  var genres = [];
  if (d.type === 'manga' || d.type === 'manhua' || d.type === 'manhwa') {
    genres.push(d.type.charAt(0).toUpperCase() + d.type.slice(1));
  }
  var raw = d.genres || [];
  for (var i = 0; i < raw.length; i++) {
    if (genres.indexOf(raw[i]) === -1) { genres.push(raw[i]); }
  }
  return {
    key: '/manga/' + d.slug,
    title: d.title,
    coverUrl: d.coverUrl || '',
    author: valid(d.author),
    artist: valid(d.artist),
    description: d.description || '',
    genre: genres.join(', '),
    status: status,
  };
}

function slugFromKey(key) {
  var parts = String(key).split('/').filter(Boolean);
  return parts[1] || '';
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(API + '?action=browse&page=' + page + '&sort=views', headers());
    var data = JSON.parse(text);
    var out = [];
    for (var i = 0; i < (data.results || []).length; i++) {
      out.push(mangaOut(data.results[i]));
    }
    return { mangas: out, hasNextPage: !!data.hasMore };
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(API + '?action=search&q=' + encodeURIComponent(query), headers());
    var data = JSON.parse(text);
    var out = [];
    for (var i = 0; i < (data.results || []).length; i++) {
      out.push(mangaOut(data.results[i]));
    }
    return { mangas: out, hasNextPage: !!data.hasMore };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = slugFromKey(mangaKey);
    var text = await $.http.get(API + '?action=series&slug=' + encodeURIComponent(slug), headers());
    return mangaOut(JSON.parse(text));
  },

  getChapterList: async function (mangaKey) {
    var slug = slugFromKey(mangaKey);
    var text = await $.http.get(API + '?action=series&slug=' + encodeURIComponent(slug), headers());
    var chapters = (JSON.parse(text) || {}).chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var name = 'الفصل ' + c.number;
      if (c.title && c.title !== name) { name += ' - ' + c.title; }
      var ts = c.createdAt ? Date.parse(c.createdAt) : 0;
      out.push({
        key: '/reader/' + slug + '/' + c.number + '#' + c.id,
        name: name,
        chapterNumber: c.number,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0,
      });
    }
    // sort ascending by number for oldest-first
    out.sort(function (a, b) { return a.chapterNumber - b.chapterNumber; });
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var chapterId = String(chapterKey).split('#').pop();
    var text = await $.http.get(API + '?action=pages&chapterId=' + encodeURIComponent(chapterId), headers());
    var imgs = (JSON.parse(text) || {}).pages || [];
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      pages.push({ index: i, url: imgs[i] });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
