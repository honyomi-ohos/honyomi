// pt/leituramanga — Next.js site + JSON API (api.leituramanga.net / cdn.leituramanga.net)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['mangaId extracted from embedded next.js payloads via regex; genre filters not ported'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API+HTML)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.leituramanga.net';
var CDN = 'https://cdn.leituramanga.net';
var HDRS = { Origin: BASE, Referer: BASE + '/' };

function findMangaId(html) {
  var m = html.match(/"mangaId"\\s*:\\s*"([^"]+)"/);
  if (m) { return m[1]; }
  var m2 = html.match(/"manga"\\s*:\\s*\\{[^{}]*?"_id"\\s*:\\s*"([^"]+)"/);
  if (m2) { return m2[1]; }
  return '';
}

function parseList(text) {
  var j = $.json.parse(text);
  var inner = j.data || {};
  var list = inner.data || [];
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var it = list[i];
    out.push({
      key: '/manga/' + it.slug,
      title: it.title || '',
      coverUrl: CDN + '/' + it.slug + '/cover-md.webp'
    });
  }
  var pg = inner.pagination || {};
  return { mangas: out, hasNextPage: (pg.page || 1) < (pg.totalPage || 1) };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(API + '/api/manga/?sort=view&limit=24&page=' + page, HDRS);
    return parseList(text);
  },

  getSearchManga: async function (page, query) {
    var u = API + '/api/manga/?limit=24&page=' + page;
    if (query) { u += '&keyword=' + encodeURIComponent(query); }
    var text = await $.http.get(u, HDRS);
    return parseList(text);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var desc = R_selFirst(doc, 'h2:contains(Sinopse) + div p');
    var authorEl = R_selFirst(doc, 'h2:contains(Informações) + div p:contains(Autor)');
    var author = authorEl ? authorEl.text().split(':').pop().trim() : '';
    var statusEl = R_selFirst(doc, 'h2:contains(Informações) + div p:contains(Status)');
    var statusRaw = statusEl ? statusEl.text().split(':').pop().trim().toLowerCase() : '';
    var status = '';
    if (statusRaw === 'em breve' || statusRaw === 'em andamento') { status = 'ongoing'; }
    else if (statusRaw === 'completo') { status = 'completed'; }
    else if (statusRaw === 'cancelado') { status = 'cancelled'; }
    else if (statusRaw === 'em pausa') { status = 'hiatus'; }
    var genres = [];
    var gels = R_sel(doc, 'h2 + div > a[href*=genre]');
    for (var i = 0; i < gels.length; i++) { genres.push(gels[i].text()); }
    var slug = mangaKey.split('/').pop();
    return {
      key: mangaKey,
      title: R_ownText(R_selFirst(doc, 'h1')) || '',
      coverUrl: CDN + '/' + slug + '/cover-md.webp',
      author: author,
      description: desc ? desc.text() : '',
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var mangaId = findMangaId(text);
    if (!mangaId) { return []; }
    var slug = mangaKey.split('/').pop();
    var ct = await $.http.get(API + '/api/chapter/get-by-manga-id?mangaId=' + encodeURIComponent(mangaId) + '&page=1&limit=9007199254740991', HDRS);
    var j = $.json.parse(ct);
    var list = (j.data && j.data.data) || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var numStr = String(c.chapterNumber).replace(/\\.0$/, '');
      out.push({
        key: '/manga/' + slug + '/chapter/' + numStr,
        name: c.title || ('Capítulo ' + numStr),
        chapterNumber: c.chapterNumber,
        dateUpload: c.releaseDate ? Date.parse(c.releaseDate) || 0 : 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), HDRS);
    var m = text.match(/"images"\\s*:\\s*(\\[[^\\]]*\\])/);
    var out = [];
    if (m) {
      var urls = m[1].match(/"url"\\s*:\\s*"([^"]+)"/g) || [];
      for (var i = 0; i < urls.length; i++) {
        var um = urls[i].match(/"url"\\s*:\\s*"([^"]+)"/);
        if (um) { out.push({ index: out.length, url: CDN + '/' + um[1] }); }
      }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
