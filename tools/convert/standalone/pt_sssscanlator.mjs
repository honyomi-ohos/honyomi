// pt/sssscanlator (Yomu Comics) — JSON API (yomu.tauruus.com)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'filters not ported',
      'API (yomu.tauruus.com) currently returns 502 / site 403 from test network (environmental)',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://yomu.tauruus.com';

function toStatus(s) {
  var v = String(s || '').toUpperCase();
  if (v === 'ONGOING') { return 'ongoing'; }
  if (v === 'COMPLETED') { return 'completed'; }
  if (v === 'HIATUS') { return 'hiatus'; }
  if (v === 'CANCELED' || v === 'CANCELLED') { return 'cancelled'; }
  return '';
}

function parseList(text) {
  var j = $.json.parse(text);
  var out = [];
  var list = j.series || [];
  for (var i = 0; i < list.length; i++) {
    out.push({
      key: '/obra/' + list[i].slug,
      title: list[i].title || '',
      coverUrl: (list[i].cover || '').trim()
    });
  }
  return { mangas: out, hasNextPage: j.hasNextPage === true };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(API + '/list?page=' + page + '&sort=popular'));
  },

  getSearchManga: async function (page, query) {
    var u = API + '/list?page=' + page;
    var q = (query || '').trim();
    if (q) { u += '&q=' + encodeURIComponent(q); }
    return parseList(await $.http.get(u));
  },

  getMangaDetail: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var d = $.json.parse(await $.http.get(API + '/manga/' + encodeURIComponent(slug)));
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: (d.cover || '').trim(),
      author: (d.author || '').trim(),
      artist: (d.artist || '').trim(),
      description: (d.description || '').trim(),
      genre: (d.genres || []).join(', '),
      status: toStatus(d.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var d = $.json.parse(await $.http.get(API + '/manga/' + encodeURIComponent(slug)));
    var out = [];
    var chapters = d.chapters || [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var label = String(c.number).replace(/\\.0$/, '');
      var title = (c.title || '').trim();
      var ts = 0;
      if (c.releaseAt) {
        ts = Date.parse(c.releaseAt) || 0;
      }
      if (!ts && c.releaseDate) {
        var m = /^(\\d{2})\\/(\\d{2})\\/(\\d{4})$/.exec(String(c.releaseDate).trim());
        if (m) {
          ts = Date.parse(m[3] + '-' + m[2] + '-' + m[1]) || 0;
        }
      }
      out.push({
        key: '/ler/' + slug + '/' + label + '?id=' + encodeURIComponent(c.id),
        name: title || ('Capítulo ' + label),
        chapterNumber: c.number,
        dateUpload: ts,
        pages: 0
      });
    }
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var path = chapterKey.split('?')[0];
    var parts = path.split('/').filter(Boolean);
    var number = parts.pop();
    var slug = parts.pop();
    var j = $.json.parse(await $.http.get(API + '/chapter/' + encodeURIComponent(slug) + '/' + encodeURIComponent(number)));
    var out = [];
    var pages = j.pages || [];
    for (var i = 0; i < pages.length; i++) {
      out.push({ index: i, url: pages[i] });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
