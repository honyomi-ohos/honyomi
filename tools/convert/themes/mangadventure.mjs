// MangAdventure theme engine (en: arcrelight, assortedscans) — JSON API v2
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {};
  const cm = kt.match(/override val categories[^=]*=\s*listOf\(([^)]*)\)/);
  if (cm) {
    config.categories = cm[1].split(',').map(s => s.trim().replace(/^"|"$/g, '')).filter(Boolean);
  }
  const nm = kt.match(/override val genreSearchNoun[^=]*=\s*"([^"]*)"/);
  if (nm) config.genreNoun = nm[1];
  if (/override val archiveUrl/.test(kt)) {
    const am = kt.match(/override val archiveUrl[^=]*=\s*"([^"]*)"/);
    if (am) config.archiveUrl = am[1];
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mangadventure)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var API = BASE + '/api/v2';

function statusMap(s) {
  var v = String(s || '').toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  if (v === 'licensed') { return 'licensed'; }
  return '';
}

function mapManga(s) {
  var genres = [];
  var cats = s.categories || [];
  for (var i = 0; i < cats.length; i++) { genres.push(cats[i].name || cats[i]); }
  var cover = s.cover || '';
  if (cover && cover.indexOf('http') !== 0) { cover = BASE + cover; }
  return {
    key: '/series/' + s.slug,
    title: s.title || '',
    coverUrl: cover,
    author: (s.authors || []).join(', '),
    artist: (s.artists || []).join(', '),
    description: s.description || '',
    genre: genres.join(', '),
    status: statusMap(s.status)
  };
}

async function listManga(path) {
  var text = await $.http.get(API + path);
  var j = JSON.parse(text);
  var rows = j.results || [];
  var mangas = [];
  for (var i = 0; i < rows.length; i++) { mangas.push(mapManga(rows[i])); }
  var last = j.last ? j.last.page : 1;
  return { mangas: mangas, hasNextPage: false };
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga('/series/' + page + '?sort=title');
  },

  getSearchManga: async function (page, query) {
    return listManga('/series/' + page + '?title=' + encodeURIComponent(query));
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).split('/').pop();
    var text = await $.http.get(API + '/series/' + slug);
    var s = JSON.parse(text);
    var m = mapManga(s);
    m.key = mangaKey;
    return m;
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).split('/').pop();
    var text = await $.http.get(API + '/series/' + slug + '/chapters/');
    var rows = JSON.parse(text).results || [];
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var c = rows[i];
      out.push({
        key: '/series/' + slug + '/chapters/' + c.number,
        name: (c.title ? c.number + ' - ' + c.title : String(c.number)),
        chapterNumber: parseFloat(c.number) || 0,
        volume: Number(c.volume) || 0,
        dateUpload: c.released ? Math.floor(new Date(c.released).getTime() / 1000) : 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(API + chapterKey + '/');
    var rows = JSON.parse(text).results || [];
    var pages = [];
    for (var i = 0; i < rows.length; i++) {
      var url = rows[i].image || '';
      if (url && url.indexOf('http') !== 0) { url = BASE + url; }
      pages.push({ index: i, url: url });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
