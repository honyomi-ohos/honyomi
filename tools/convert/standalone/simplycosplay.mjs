// all/simplycosplay — bespoke JSON-API engine (api.simply-porn.com/v2, token w/ lazy refresh)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['browse-type preference fixed to gallery; tag/type filters not portable; url: search prefix not supported'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone JSON API)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.simply-porn.com/v2';
var LIMIT = 20;
var token = '01730876';

async function fetchNewToken() {
  var home = await $.http.get(BASE);
  var doc = $.html.parse(home);
  var scriptEl = R_selFirst(doc, 'script[src*=main]');
  if (!scriptEl) { throw new Error('Unable to fetch new Token'); }
  var scriptUrl = scriptEl.absUrl('src');
  if (!scriptUrl) { throw new Error('Unable to fetch new Token'); }
  var content = (await $.http.get(scriptUrl)).replace(/'/g, '"');
  var m = content.match(/token\\s*:\\s*"([^"]+)"/);
  if (!m) { throw new Error('Unable to fetch new Token'); }
  return m[1];
}

async function apiGet(path) {
  var sep = path.indexOf('?') >= 0 ? '&' : '?';
  try {
    return JSON.parse(await $.http.get(API + path + sep + 'token=' + token));
  } catch (e) {
    token = await fetchNewToken();
    return JSON.parse(await $.http.get(API + path + sep + 'token=' + token));
  }
}

function itemToManga(it) {
  return {
    key: '/' + String(it.type || '').toLowerCase().trim() + '/new/' + it.slug,
    title: it.title || '',
    coverUrl: (it.preview && it.preview.urls && it.preview.urls.thumb && it.preview.urls.thumb.url) || '',
  };
}
function partsFromKey(key) {
  var p = String(key).split('/');
  return { type: p[1] || '', slug: p[3] || '' };
}
function parseApiDate(s) {
  if (!s) { return 0; }
  var ts = Date.parse(String(s).substring(0, 23));
  return isNaN(ts) ? 0 : ts;
}

module.exports = {
  getPopularManga: async function (page) {
    var j = await apiGet('/gallery?sort=hot&limit=' + LIMIT + '&page=' + page);
    var items = j.data || [];
    return { mangas: items.map(itemToManga), hasNextPage: items.length >= LIMIT };
  },

  getSearchManga: async function (page, query) {
    var path = '/search?sort=new&limit=' + LIMIT + '&page=' + page;
    if (query) { path += '&query=' + encodeURIComponent(query); }
    var j = await apiGet(path);
    var items = j.data || [];
    return { mangas: items.map(itemToManga), hasNextPage: items.length >= LIMIT };
  },

  getMangaDetail: async function (mangaKey) {
    var parts = partsFromKey(mangaKey);
    var j = await apiGet('/' + parts.type + '/' + parts.slug);
    var d = j.data;
    if (!d) { throw new Error('entry not found: ' + mangaKey); }
    var genres = [];
    var tags = d.tags || [];
    for (var i = 0; i < tags.length; i++) {
      var n = tags[i].name;
      if (!n) { continue; }
      var words = String(n).trim().split(' ');
      for (var w = 0; w < words.length; w++) {
        if (words[w]) { words[w] = words[w].charAt(0).toUpperCase() + words[w].slice(1); }
      }
      genres.push(words.join(' '));
    }
    var desc = 'Type: ' + (d.type || '') + '\\n';
    if (d.image_count != null) { desc += 'Images: ' + d.image_count + '\\n'; }
    if (d.preview && d.preview.publish_date) { desc += 'Date: ' + d.preview.publish_date + '\\n'; }
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: (d.preview && d.preview.urls && d.preview.urls.thumb && d.preview.urls.thumb.url) || '',
      author: '',
      description: desc,
      genre: genres.join(', '),
      status: 'completed',
    };
  },

  getChapterList: async function (mangaKey) {
    var parts = partsFromKey(mangaKey);
    var type = parts.type;
    var name = type ? type.charAt(0).toUpperCase() + type.slice(1) : 'Chapter';
    // fetch detail for publish date
    var dateUpload = 0;
    try {
      var j = await apiGet('/' + type + '/' + parts.slug);
      if (j.data && j.data.preview && j.data.preview.publish_date) {
        dateUpload = parseApiDate(j.data.preview.publish_date);
      }
    } catch (e) { /* date optional */ }
    return [{
      key: mangaKey,
      name: name,
      chapterNumber: 0,
      dateUpload: dateUpload,
      pages: 0,
      sortOrder: 0,
    }];
  },

  getPageList: async function (chapterKey) {
    var parts = partsFromKey(chapterKey);
    var j = await apiGet('/' + parts.type + '/' + parts.slug);
    var d = j.data || {};
    var out = [];
    var images = d.images || [];
    for (var i = 0; i < images.length; i++) {
      var u = images[i].urls && images[i].urls.url;
      if (u) { out.push({ index: out.length, url: u }); }
    }
    if (out.length === 0 && d.preview && d.preview.urls && d.preview.urls.url) {
      out.push({ index: 0, url: d.preview.urls.url });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
