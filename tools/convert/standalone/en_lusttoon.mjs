// en/lusttoon — Next.js site with JSON filter API; details/pages via RSC flight payload extraction
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['RSC flight payload extraction simplified (basic $id ref resolution); filters not ported'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke Next.js/RSC)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://back.lustoon.com';

// ---- minimal Next.js RSC flight parsing ----
function rscRows(text, models) {
  var results = [];
  var lines = String(text).split('\\n');
  for (var i = 0; i < lines.length; i++) {
    var m = /^([0-9a-fA-F]+):(.*)$/.exec(lines[i]);
    if (!m) { continue; }
    var id = m[1], val = m[2];
    if (!val || val[0] === 'T') { continue; }
    if (val[0] !== '{' && val[0] !== '[') { continue; }
    var parsed = null;
    try { parsed = $.json.parse(val); } catch (e) { parsed = null; }
    if (parsed === null) { continue; }
    results.push(parsed);
    if (models) { models[id] = parsed; }
  }
  return results;
}

function resolveRefs(el, models, depth) {
  if (depth > 8) { return el; }
  if (Array.isArray(el)) {
    return el.map(function (x) { return resolveRefs(x, models, depth + 1); });
  }
  if (el && typeof el === 'object') {
    var out = {};
    for (var k in el) { out[k] = resolveRefs(el[k], models, depth + 1); }
    return out;
  }
  if (typeof el === 'string' && el[0] === '$' && el.length >= 2) {
    if (el[1] === '$') { return el.substring(1); }
    if (el === '$undefined') { return null; }
    var ref = el.substring(el[1] === 'D' || el[1] === 'n' || el[1] === 'L' || el[1] === 'Q' || el[1] === 'W' || el[1] === '@' ? 2 : 1);
    var parts = ref.split(':');
    var v = models ? models[parts[0]] : undefined;
    if (v === undefined) { return el; }
    for (var i = 1; i < parts.length && v !== undefined && v !== null; i++) {
      v = v[parts[i]];
    }
    if (v === undefined) { return el; }
    return resolveRefs(v, models, depth + 1);
  }
  return el;
}

function deepFind(el, pred, depth) {
  if (depth > 12 || el === null || el === undefined) { return null; }
  if (Array.isArray(el)) {
    for (var i = 0; i < el.length; i++) {
      var r = deepFind(el[i], pred, depth + 1);
      if (r) { return r; }
    }
    return null;
  }
  if (el && typeof el === 'object') {
    if (pred(el)) { return el; }
    for (var k in el) {
      var r2 = deepFind(el[k], pred, depth + 1);
      if (r2) { return r2; }
    }
  }
  return null;
}

function findInRsc(text, pred) {
  var models = {};
  var rows = rscRows(text, models);
  for (var i = 0; i < rows.length; i++) {
    var resolved = resolveRefs(rows[i], models, 0);
    var found = deepFind(resolved, pred, 0);
    if (found) { return found; }
  }
  return null;
}

function extractFlightFromHtml(html) {
  // concatenate all self.__next_f.push([1,"..."]) string chunks into one stream
  var stream = '';
  var re = /self\\.__next_f\\.push\\(\\s*\\[\\s*1\\s*,\\s*("((?:[^"\\\\]|\\\\.)*)")\\s*\\]\\s*\\)\\s*;?/g;
  var m;
  while ((m = re.exec(html)) !== null) {
    try { stream += $.json.parse(m[1]); } catch (e) { /* skip */ }
  }
  return stream;
}

function https(u) {
  return String(u || '').replace('http://', 'https://');
}

function statusMap(s) {
  var v = String(s || '').toLowerCase();
  if (v === 'en emision' || v === 'ongoing') { return 'ongoing'; }
  if (v === 'completado' || v === 'finalizado' || v === 'completed') { return 'completed'; }
  if (v === 'cancelado' || v === 'cancelled') { return 'cancelled'; }
  if (v === 'pausado' || v === 'hiatus' || v === 'paused') { return 'hiatus'; }
  return '';
}

function filtrar(page, orderBy) {
  return API + '/filtrar?page=' + page + '&limit=24&orderBy=' + orderBy + '&sort=desc&gendersId=&origin=&state=&loading=true';
}

function parseFiltrar(text) {
  var r = $.json.parse(text);
  var data = (r && r.data) || [];
  var mangas = [];
  for (var i = 0; i < data.length; i++) {
    var d = data[i];
    if (!d.slug) { continue; }
    mangas.push({ key: '/comic/' + d.slug, title: d.name || '', coverUrl: https(d.urlImg) });
  }
  var cur = (r && r.meta && r.meta.current_page) || 1;
  var last = (r && r.meta && r.meta.last_page) || 1;
  return { mangas: mangas, hasNextPage: cur < last };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseFiltrar(await $.http.get(filtrar(page, '6')));
  },

  getSearchManga: async function (page, query) {
    if (query && query.trim()) {
      var text = await $.http.get(API + '/home/buscar?query=' + encodeURIComponent(query));
      var items = $.json.parse(text);
      var mangas = [];
      for (var i = 0; i < items.length; i++) {
        var d = items[i];
        if (!d.slug) { continue; }
        mangas.push({ key: '/comic/' + d.slug, title: d.name || '', coverUrl: https(d.urlImg) });
      }
      return { mangas: mangas, hasNextPage: false };
    }
    return parseFiltrar(await $.http.get(filtrar(page, '1')));
  },

  getMangaDetail: async function (mangaKey) {
    var rscText = await $.http.get(BASE + mangaKey, { RSC: '1' });
    var serie = findInRsc(rscText, function (o) { return 'slug' in o && 'chapters' in o; });
    if (!serie) { throw new Error('series data not found in RSC payload'); }
    var genres = (serie.genders || []).map(function (g) { return g.name; }).join(', ');
    return {
      key: mangaKey,
      title: serie.name || '',
      coverUrl: https(serie.urlImg),
      author: '',
      description: serie.sinopsis || '',
      genre: genres,
      status: statusMap(serie.state && serie.state.estado)
    };
  },

  getChapterList: async function (mangaKey) {
    var rscText = await $.http.get(BASE + mangaKey, { RSC: '1' });
    var serie = findInRsc(rscText, function (o) { return 'slug' in o && 'chapters' in o; });
    if (!serie) { throw new Error('series data not found in RSC payload'); }
    var mangaSlug = serie.slug || mangaKey.substring(mangaKey.lastIndexOf('/') + 1);
    var chapters = serie.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      if (!c.slug) { continue; }
      var nm = c.name;
      if (!nm || !nm.trim() || !/\\d/.test(nm)) {
        var numStr = c.num !== undefined && c.num !== null ? String(c.num).replace(/\\.0$/, '') : '';
        nm = ('Chapter ' + numStr).trim();
      }
      out.push({
        key: '/comic/' + mangaSlug + '/' + c.slug,
        name: nm,
        chapterNumber: typeof c.num === 'number' ? c.num : -1,
        dateUpload: c.createdAt ? Date.parse(c.createdAt) || 0 : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // upstream lists newest first; return oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var html = await $.http.get(BASE + chapterKey);
    var stream = extractFlightFromHtml(html);
    var images = [];
    if (stream) {
      var dto = findInRsc(stream, function (o) { return 'urlImg' in o && 'chapterId' in o; });
      if (dto && dto.urlImg) {
        try { images = $.json.parse(dto.urlImg) || []; } catch (e) { images = []; }
      }
    }
    if (!images.length) {
      var seen = {};
      var re = /https?:\\/\\/media\\.lustoon\\.com\\/file\\/[^"'\\\\\\s]+\\.(?:jpg|jpeg|png|webp|avif)/gi;
      var m;
      while ((m = re.exec(html)) !== null) {
        var u = https(m[0]);
        if (u.indexOf('/serie/') >= 0 && u.indexOf('brakeout') < 0 && !seen[u]) {
          seen[u] = true;
          images.push(u);
        }
      }
    }
    var out = [];
    var seen2 = {};
    for (var i = 0; i < images.length; i++) {
      var u2 = https(images[i]);
      if (u2.indexOf('brakeout') >= 0 || seen2[u2]) { continue; }
      seen2[u2] = true;
      out.push({ index: out.length, url: u2 });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
