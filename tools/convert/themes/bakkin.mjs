// BakkinReaderX theme engine (en: bakkin, bakkinselfhosted) — JSON directory API
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {};
  const qm = kt.match(/val qualityPrefKey[^=]*=\s*Key[^\n]*\n[^\n]*"[^"]*"[\s\S]*?"""/) || kt.match(/readableValueList[^=]*=\s*listOf\(([^)]*)\)/);
  const rm = kt.match(/listOf\(\s*"([^"]*)"\s*,\s*"([^"]*)"/);
  if (rm) { config.qualityValues = [rm[1], rm[2]]; }
  const dv = kt.match(/defaultQuality[^\n]*"([^"]*)"/);
  if (dv) { config.defaultQuality = dv[1]; }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: bakkin)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var SERIES_CACHE = null;

function statusMap(s) {
  var v = String(s || '').toLowerCase();
  if (v.indexOf('complete') >= 0 || v.indexOf('finished') >= 0) { return 'completed'; }
  if (v.indexOf('ongoing') >= 0) { return 'ongoing'; }
  return '';
}

async function loadSeries() {
  if (SERIES_CACHE) { return SERIES_CACHE; }
  var text = await $.http.get(BASE + 'main.php');
  SERIES_CACHE = JSON.parse(text);
  return SERIES_CACHE;
}

function seriesToManga(dirName, s) {
  var cover = s.thumb || 'static/nocover.png';
  if (cover.indexOf('http') !== 0) { cover = BASE + cover; }
  return {
    key: '/' + s.dir,
    title: s.name || s.dir,
    coverUrl: cover,
    author: s.author || '',
    description: '',
    genre: '',
    status: statusMap(s.status)
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var db = await loadSeries();
    var keys = Object.keys(db);
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    var mangas = [];
    for (var i = 0; i < keys.length; i++) {
      mangas.push(seriesToManga(keys[i], db[keys[i]]));
    }
    return { mangas: mangas, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    var db = await loadSeries();
    var keys = Object.keys(db);
    var q = String(query || '').toLowerCase();
    var mangas = [];
    for (var i = 0; i < keys.length; i++) {
      var s = db[keys[i]];
      var t = (s.name || s.dir || '').toLowerCase();
      if (t.indexOf(q) >= 0) { mangas.push(seriesToManga(keys[i], s)); }
    }
    return { mangas: mangas, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var dir = String(mangaKey).split('/').pop();
    var db = await loadSeries();
    var s = db[dir] || db[Object.keys(db).find(function (k) { return db[k].dir === dir; })];
    var m = seriesToManga(dir, s || { dir: dir, name: dir });
    m.key = mangaKey;
    return m;
  },

  getChapterList: async function (mangaKey) {
    var dir = String(mangaKey).split('/').pop();
    var db = await loadSeries();
    var s = db[dir] || db[Object.keys(db).find(function (k) { return db[k].dir === dir; })];
    var out = [];
    if (s && s.volumes) {
      for (var vi = 0; vi < s.volumes.length; vi++) {
        var vol = s.volumes[vi];
        for (var ci = 0; ci < (vol.chapters || []).length; ci++) {
          var ch = vol.chapters[ci];
          out.push({
            key: '/' + s.dir + '/' + vol.dir + '/' + ch.dir,
            name: (vol.name || vol.dir) + ' - ' + (ch.name || ch.dir),
            pages: 0,
            sortOrder: 0
          });
        }
      }
    }
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = String(chapterKey).split('/').filter(Boolean);
    var sDir = parts[0], vDir = parts[1], cDir = parts[2];
    var db = await loadSeries();
    var s = db[sDir] || db[Object.keys(db).find(function (k) { return db[k].dir === sDir; })];
    var pages = [];
    if (s && s.volumes) {
      for (var vi = 0; vi < s.volumes.length; vi++) {
        var vol = s.volumes[vi];
        if (vol.dir !== vDir) { continue; }
        for (var ci = 0; ci < (vol.chapters || []).length; ci++) {
          var ch = vol.chapters[ci];
          if (ch.dir !== cDir) { continue; }
          var list = ch.pages || [];
          for (var pi = 0; pi < list.length; pi++) {
            var url = list[pi];
            if (url.indexOf('http') !== 0) { url = BASE + url; }
            pages.push({ index: pi, url: url });
          }
        }
      }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE };
  }
};
`;
}
