// FansubsCat theme engine (ca: fansubscat, fansubscathentai) — JSON API
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {};
  const hm = kt.match(/override val apiBaseUrl[^=]*=\s*"([^"]*)"/);
  if (hm) config.apiBaseOverride = hm[1];
  config.isHentai = /override val isHentaiSite = true/.test(kt);
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: fansubscat)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var API = CFG.apiBaseOverride || BASE.replace('https://manga.', 'https://api.');

function statusMap(s) {
  var v = String(s || '').toLowerCase();
  if (v.indexOf('ongoing') >= 0) { return 'ongoing'; }
  if (v.indexOf('finished') >= 0) { return 'completed'; }
  return '';
}

function mapManga(j) {
  return {
    key: '/' + j.slug,
    title: j.name || '',
    coverUrl: j.thumbnail_url || '',
    author: j.author || '',
    description: j.synopsis || '',
    genre: j.genres || '',
    status: statusMap(j.status)
  };
}

async function listManga(path, page, query) {
  var url = API + path + page + (query ? '?type=all&query=' + encodeURIComponent(query) : '');
  var text = await $.http.get(url);
  var rows = JSON.parse(text).result || [];
  var mangas = [];
  for (var i = 0; i < rows.length; i++) { mangas.push(mapManga(rows[i])); }
  return { mangas: mangas, hasNextPage: rows.length >= 20 };
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga('/manga/popular/', page, '');
  },

  getSearchManga: async function (page, query) {
    return listManga('/manga/search/', page, query);
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).split('/').pop();
    var text = await $.http.get(API + '/manga/details/' + slug);
    var d = JSON.parse(text).result;
    var m = mapManga(d);
    m.key = mangaKey;
    return m;
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).split('/').pop();
    var text = await $.http.get(API + '/manga/chapters/' + slug);
    var rows = JSON.parse(text).result || [];
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var c = rows[i];
      out.push({
        key: '/' + c.id,
        name: c.title || '',
        chapterNumber: parseFloat(c.number) || 0,
        dateUpload: Number(c.created) || 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).split('/').pop();
    var text = await $.http.get(API + '/manga/pages/' + id);
    var rows = JSON.parse(text).result || [];
    var pages = [];
    for (var i = 0; i < rows.length; i++) {
      pages.push({ index: i, url: rows[i].url });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
