// pt/saikaiscan — JSON API (api.housesaikai.net) + S3 storage images
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'filters not ported',
      'site/API currently Cloudflare-blocked from test network (probe 403, environmental)',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HOST = BASE.replace(/^https?:\\/\\//, '');
var API = 'https://api.' + HOST;
var STORAGE = 'https://s3-beta.' + HOST;
var HDRS = { Origin: BASE, Referer: BASE + '/', Accept: 'application/json, text/plain, */*' };

function toStatus(name) {
  var v = String(name || '').trim();
  if (v === 'Concluído') { return 'completed'; }
  if (v === 'Em Andamento') { return 'ongoing'; }
  return '';
}

function parseSynopsis(html) {
  var doc = $.html.parse(html || '');
  var ps = R_sel(doc, 'p');
  var parts = [];
  for (var i = 0; i < ps.length; i++) {
    var t = ps[i].text();
    if (t) { parts.push(t); }
  }
  return parts.join('\\n\\n');
}

function parseList(text) {
  var j = $.json.parse(text);
  var out = [];
  var list = (j.data || []);
  for (var i = 0; i < list.length; i++) {
    out.push({
      key: '/comics/' + list[i].slug,
      title: list[i].title || '',
      coverUrl: list[i].image ? STORAGE + '/' + list[i].image : ''
    });
  }
  var meta = j.meta || {};
  return { mangas: out, hasNextPage: (meta.current_page || 1) < (meta.last_page || 1) };
}

module.exports = {
  getPopularManga: async function (page) {
    var u = API + '/api/stories?format=2&sortProperty=pageviews&sortDirection=desc&page=' + page + '&per_page=12&relationships=language,type,format';
    return parseList(await $.http.get(u, HDRS));
  },

  getSearchManga: async function (page, query) {
    var u = API + '/api/stories?format=2&q=' + encodeURIComponent(query || '') + '&sortProperty=pageviews&sortDirection=desc&page=' + page + '&per_page=12&relationships=language,type,format';
    return parseList(await $.http.get(u, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var u = API + '/api/stories?format=2&slug=' + encodeURIComponent(slug) + '&per_page=1&relationships=language,type,format,artists,status';
    var j = $.json.parse(await $.http.get(u, HDRS));
    var d = (j.data || [])[0];
    if (!d) { throw new Error('Manga not found: ' + slug); }
    var authors = [], artists = [], genres = [];
    (d.authors || []).forEach(function (p) { authors.push(p.name); });
    (d.artists || []).forEach(function (p) { artists.push(p.name); });
    (d.genres || []).forEach(function (g) { genres.push(g.name); });
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: d.image ? STORAGE + '/' + d.image : '',
      author: authors.join(', '),
      artist: artists.join(', '),
      genre: genres.join(', '),
      status: toStatus(d.status && d.status.name),
      description: parseSynopsis(d.synopsis)
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var u = API + '/api/stories?format=2&slug=' + encodeURIComponent(slug) + '&per_page=1&relationships=releases';
    var j = $.json.parse(await $.http.get(u, HDRS));
    var story = (j.data || [])[0];
    if (!story) { throw new Error('Manga not found: ' + slug); }
    var out = [];
    var releases = story.releases || [];
    for (var i = 0; i < releases.length; i++) {
      var r = releases[i];
      if (r.is_active !== 1) { continue; }
      var name = 'Capítulo ' + r.chapter;
      if (r.title) { name += ' - ' + r.title; }
      var num = parseFloat(r.chapter);
      out.push({
        key: '/ler/comics/' + slug + '/' + r.id + '/' + r.slug,
        name: name,
        chapterNumber: isNaN(num) ? -1 : num,
        dateUpload: r.published_at ? Date.parse(r.published_at.replace(' ', 'T')) || 0 : 0,
        pages: 0
      });
    }
    out.sort(function (a, b) { return b.chapterNumber - a.chapterNumber; });
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = chapterKey.split('/').filter(Boolean);
    var releaseId = parts[parts.length - 2];
    var u = API + '/api/releases/' + releaseId + '?relationships=releaseImages';
    var j = $.json.parse(await $.http.get(u, HDRS));
    var imgs = (j.data && j.data.release_images) || [];
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      out.push({ index: i, url: STORAGE + '/' + imgs[i].image });
    }
    return out;
  },

  imageHeaders: function () {
    return { Origin: BASE, Referer: BASE + '/' };
  }
};
`;
}
