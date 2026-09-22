// Monochrome theme engine (en: monochromecustom, monochromescans) — MonochromeCMS JSON API
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {};
  const dm = kt.match(/DEMO_API_URL\s*=\s*"([^"]*)"/);
  if (dm) {
    config.apiUrl = dm[1];
    warnings.push('custom API URL preference approximated with demo/default URL');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: monochrome)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var API = CFG.apiUrl || BASE.replace('://', '://api.');

function statusMap(s) {
  switch (s) {
    case 'ongoing': case 'hiatus': return 'ongoing';
    case 'completed': case 'cancelled': return 'completed';
    default: return '';
  }
}

function parseDate(s) {
  var t = String(s || '').replace(/(\\.[0-9]{3})[0-9]+/, '$1');
  var v = Date.parse(t);
  return isNaN(v) ? 0 : Math.floor(v / 1000);
}

function mapManga(m) {
  return {
    key: '/m/' + m.id,
    title: m.title || '',
    coverUrl: API + '/media/' + m.id + '/cover.jpg?version=' + m.version,
    author: m.author || '',
    artist: m.artist || '',
    description: m.description || '',
    status: statusMap(m.status)
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var offset = 10 * (page - 1);
    var text = await $.http.get(API + '/manga?limit=10&offset=' + offset + '&title=');
    var j = JSON.parse(text);
    var rows = j.results || [];
    var out = [];
    for (var i = 0; i < rows.length; i++) { out.push(mapManga(rows[i])); }
    var hasNext = j.total > rows.length + j.offset * j.limit;
    return { mangas: out, hasNextPage: hasNext };
  },

  getSearchManga: async function (page, query) {
    var offset = 10 * (page - 1);
    var text = await $.http.get(API + '/manga?limit=10&offset=' + offset + '&title=' + encodeURIComponent(query || ''));
    var j = JSON.parse(text);
    var rows = j.results || [];
    var out = [];
    for (var i = 0; i < rows.length; i++) { out.push(mapManga(rows[i])); }
    var hasNext = j.total > rows.length + j.offset * j.limit;
    return { mangas: out, hasNextPage: hasNext };
  },

  getMangaDetail: async function (mangaKey) {
    var id = String(mangaKey).split('/').pop();
    var text = await $.http.get(API + '/manga/' + id);
    var m = mapManga(JSON.parse(text));
    m.key = mangaKey;
    return m;
  },

  getChapterList: async function (mangaKey) {
    var id = String(mangaKey).split('/').pop();
    var text = await $.http.get(API + '/manga/' + id + '/chapters');
    var rows = JSON.parse(text);
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var c = rows[i];
      var name = '';
      if (c.volume !== null && c.volume !== undefined) { name += 'Vol ' + c.volume + ' '; }
      name += 'Chapter ' + c.number;
      if (c.name) { name += ' - ' + c.name; }
      out.push({
        key: '/c/' + c.id + '/' + c.version + '/' + c.length,
        name: name,
        chapterNumber: c.number,
        scanlator: c.scanGroup || '',
        dateUpload: parseDate(c.uploadTime),
        pages: c.length || 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = String(chapterKey).split('/').filter(Boolean);
    var uuid = parts[1], version = parts[2], length = parseInt(parts[3], 10) || 0;
    var pages = [];
    for (var n = 1; n <= length; n++) {
      pages.push({ index: n - 1, url: API + '/media/' + uuid + '/' + n + '.jpg?version=' + version });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
