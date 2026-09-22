// SpicyTheme theme engine (es: colorcitoscan, spicyscan) — JSON API
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {};
  const am = kt.match(/override val apiBaseUrl[^=]*=\s*"([^"]*)"/);
  if (am) config.apiBase = am[1];
  if (/rateLimit\(/.test(kt)) warnings.push('rateLimit not enforced in plugin');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: spicytheme)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var API = CFG.apiBase || BASE.replace('https://', 'https://api.');

function statusMap(stateId) {
  switch (stateId) {
    case 1: return 'ongoing';
    case 2: return 'on_hiatus';
    case 3: case 5: return 'cancelled';
    case 4: return 'completed';
    default: return '';
  }
}

function parseDate(s) {
  var t = String(s || '').replace(/(\\.[0-9]{3})[0-9]+/, '$1');
  var v = Date.parse(t);
  return isNaN(v) ? 0 : Math.floor(v / 1000);
}

function mapManga(j) {
  return {
    key: '/' + j.slug,
    title: j.name || '',
    coverUrl: j.urlImg || ''
  };
}

async function filterList(page, orderBy) {
  var url = API + '/filtrar?page=' + page + '&limit=12&orderBy=' + orderBy +
    '&sort=desc&gendersId=&origin=&state=&loading=true';
  var text = await $.http.get(url);
  var j = JSON.parse(text);
  var rows = j.data || [];
  var out = [];
  for (var i = 0; i < rows.length; i++) { out.push(mapManga(rows[i])); }
  var meta = j.meta || {};
  return { mangas: out, hasNextPage: meta.current_page < meta.last_page };
}

async function fetchSeries(slug) {
  var text = await $.http.get(API + '/serie/' + slug);
  return JSON.parse(text).serie;
}

module.exports = {
  getPopularManga: async function (page) {
    return filterList(page, '6');
  },

  getSearchManga: async function (page, query) {
    if (query) {
      if (query.length < 2) { throw new Error('Escribe al menos 2 caracteres para buscar'); }
      var text = await $.http.get(API + '/home/buscar?query=' + encodeURIComponent(query));
      var rows = JSON.parse(text);
      var out = [];
      for (var i = 0; i < rows.length; i++) { out.push(mapManga(rows[i])); }
      return { mangas: out, hasNextPage: false };
    }
    return filterList(page, '3');
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/+/, '');
    var s = await fetchSeries(slug);
    var genres = [];
    var gs = s.genders || [];
    for (var i = 0; i < gs.length; i++) { genres.push(gs[i].name); }
    return {
      key: mangaKey,
      title: s.name || '',
      coverUrl: s.urlImg || '',
      description: s.sinopsis || '',
      genre: genres.join(', '),
      status: statusMap(s.stateId)
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/+/, '');
    var s = await fetchSeries(slug);
    var rows = s.chapters || [];
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var c = rows[i];
      out.push({
        key: '/' + slug + '/' + c.slug,
        name: 'Capítulo ' + c.num,
        chapterNumber: c.num,
        dateUpload: parseDate(c.createdAt),
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(API + '/serie' + chapterKey + '/');
    var j = JSON.parse(text);
    var pagesData = j.pageches;
    if (Array.isArray(pagesData)) { pagesData = pagesData[0]; }
    var urls = JSON.parse(pagesData.urlImg);
    var pages = [];
    for (var i = 0; i < urls.length; i++) {
      pages.push({ index: i, url: urls[i] });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/', Origin: BASE };
  }
};
`;
}
