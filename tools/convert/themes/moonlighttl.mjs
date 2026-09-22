// MoonlightTL theme engine (es: lectorasteria, traduccionesmoonlight) — JSON API + HTML reader
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { blockPages: false };
  if (/img\.block/.test(kt)) config.blockPages = true;
  if (/rateLimit\(/.test(kt)) warnings.push('rateLimit not enforced in plugin');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: moonlighttl)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var SERIES_PATH = '/ver';
var COMICS_CACHE = null;

function parseDate(s) {
  var t = String(s || '').replace(/(\\.[0-9]{3})[0-9]+Z?$/, '$1Z');
  var v = Date.parse(t);
  return isNaN(v) ? 0 : Math.floor(v / 1000);
}

function seriesToManga(s) {
  return {
    key: SERIES_PATH + '/' + s.slug,
    title: s.name || '',
    coverUrl: s.urlImg || ''
  };
}

async function loadComics() {
  if (COMICS_CACHE) { return COMICS_CACHE; }
  var text = await $.http.get(BASE + '/api/comics');
  COMICS_CACHE = JSON.parse(text).response || [];
  return COMICS_CACHE;
}

async function fetchSeries(slug) {
  var text = await $.http.get(BASE + '/api/showProject/' + slug);
  return JSON.parse(text).response;
}

function imgAttr(el) {
  if (el.attr('data-lazy-src')) { return el.absUrl('data-lazy-src') || el.attr('data-lazy-src'); }
  if (el.attr('data-src')) { return el.absUrl('data-src') || el.attr('data-src'); }
  if (el.attr('data-cfsrc')) { return el.absUrl('data-cfsrc') || el.attr('data-cfsrc'); }
  return el.absUrl('src') || el.attr('src') || '';
}

module.exports = {
  getPopularManga: async function (page) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    var text = await $.http.get(BASE + '/api/topSerie');
    var r = JSON.parse(text).response || {};
    var all = [];
    var seen = {};
    var groups = [r.diario || [], r.semanal || [], r.mensual || []];
    for (var g = 0; g < groups.length; g++) {
      for (var i = 0; i < groups[g].length; i++) {
        var inner = groups[g][i];
        var list = Array.isArray(inner) ? inner : [inner];
        for (var k = 0; k < list.length; k++) {
          var s = list[k].project || list[k];
          if (s && s.slug && !seen[s.slug]) {
            seen[s.slug] = true;
            all.push(seriesToManga(s));
          }
        }
      }
    }
    return { mangas: all, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var comics = await loadComics();
    var q = String(query || '').toLowerCase();
    var filtered = [];
    for (var i = 0; i < comics.length; i++) {
      var c = comics[i];
      if (q) {
        var name = String(c.name || '').toLowerCase();
        var alt = String(c.alternativeName || '').toLowerCase();
        if (name.indexOf(q) < 0 && alt.indexOf(q) < 0) { continue; }
      }
      filtered.push(c);
    }
    filtered.sort(function (a, b) {
      var av = String(a.actualizacionCap || '');
      var bv = String(b.actualizacionCap || '');
      return av < bv ? 1 : av > bv ? -1 : 0;
    });
    var perPage = 15;
    var start = (page - 1) * perPage;
    var end = Math.min(page * perPage, filtered.length);
    var out = [];
    for (var j = start; j < end; j++) { out.push(seriesToManga(filtered[j])); }
    return { mangas: out, hasNextPage: filtered.length > page * perPage };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).split('/').pop();
    var s = await fetchSeries(slug);
    var desc = s.sinopsis || '';
    if (s.alternativeName) {
      desc += (desc ? '\\n\\n' : '') + 'Nombres alternativos: ' + s.alternativeName;
    }
    var genres = [];
    var gs = s.genders || [];
    for (var i = 0; i < gs.length; i++) { genres.push(gs[i].gender ? gs[i].gender.name : ''); }
    var authors = [];
    var as = s.autors || [];
    for (var a = 0; a < as.length; a++) { authors.push(as[a].autor ? as[a].autor.name : ''); }
    var artists = [];
    var arts = s.artists || [];
    for (var r = 0; r < arts.length; r++) { artists.push(arts[r].artist ? arts[r].artist.name : ''); }
    return {
      key: mangaKey,
      title: s.name || '',
      coverUrl: s.urlImg || '',
      author: authors.join(', '),
      artist: artists.join(', '),
      description: desc,
      genre: genres.filter(Boolean).join(', '),
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var parts = String(mangaKey).split('/').filter(Boolean);
    var slug = parts[parts.length - 1];
    var s = await fetchSeries(slug);
    var rows = s.lastChapters || [];
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var c = rows[i];
      var num = String(c.num).replace(/\\.0$/, '');
      var name = 'Capítulo ' + num;
      if (c.name) { name += ' - ' + c.name; }
      out.push({
        key: SERIES_PATH + '/' + slug + '/' + c.slug,
        name: name,
        chapterNumber: c.num,
        dateUpload: parseDate(c.created_at),
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var form = R_selFirst(doc, 'form[method=post]');
    if (form) {
      var action = form.absUrl('action') || form.attr('action') || R_abs(chapterKey);
      var inputs = R_sel(form, 'input');
      var pairs = [];
      for (var i = 0; i < inputs.length; i++) {
        var n = inputs[i].attr('name');
        if (n) { pairs.push(encodeURIComponent(n) + '=' + encodeURIComponent(inputs[i].attr('value') || '')); }
      }
      var posted = await $.http.post(action, pairs.join('&'), {
        'Content-Type': 'application/x-www-form-urlencoded',
        Referer: R_abs(chapterKey)
      });
      doc = $.html.parse(posted);
    }
    var sel = CFG.blockPages ? 'main > div > img.block' : 'main.contenedor.read img, main > img';
    var els = R_sel(doc, sel);
    var pages = [];
    for (var k = 0; k < els.length; k++) {
      var u = CFG.blockPages ? (els[k].absUrl('src') || els[k].attr('src') || '') : imgAttr(els[k]);
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
