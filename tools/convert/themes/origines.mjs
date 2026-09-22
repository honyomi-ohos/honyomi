// Origines theme engine (fr: hentaiorigines, mangasoriginesfr) — Madara child theme, admin-ajax catalogue
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText || '';
  const warnings = [];
  const config = { mangaPath: 'manga', legacyPaths: [] };
  const src = (ctx.gradle && ctx.gradle.sources && ctx.gradle.sources[0]) || {};
  const base = String(src.baseUrl || '');
  if (/mangas-origines/.test(base)) {
    config.mangaPath = 'oeuvre';
    config.legacyPaths = ['catalogues'];
  }
  // Catalogue filters (genre/origin/status/rating/chapter count) not supported by host
  warnings.push('catalogue filters (genres, status, rating, origin, chapter count) not supported; popular/search only');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: origines)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var KNOWN = {};
KNOWN[CFG.mangaPath] = true;
for (var lp = 0; lp < (CFG.legacyPaths || []).length; lp++) { KNOWN[CFG.legacyPaths[lp]] = true; }

function pathSegs(p) {
  var path = String(p || '');
  if (path.indexOf('http') === 0) {
    var noProto = path.replace(/^[a-z]+:\\/\\//, '');
    path = '/' + noProto.split('/').slice(1).join('/');
  }
  path = path.split('?')[0].split('#')[0];
  var segs = path.split('/');
  var out = [];
  for (var i = 0; i < segs.length; i++) {
    if (segs[i] && !KNOWN[segs[i]]) { out.push(segs[i]); }
  }
  return out;
}

function toMangaSlug(p) { var s = pathSegs(p); return s.length > 0 ? s[0] : String(p); }

function toChapterSlug(p) { return pathSegs(p).slice(0, 2).join('/'); }

function mangaUrl(key) { return BASE + '/' + CFG.mangaPath + '/' + toMangaSlug(key) + '/'; }

var MONTHS = [
  ['jan', 1], ['fev', 2], ['fv', 2], ['mar', 3], ['avr', 4], ['mai', 5],
  ['juin', 6], ['juil', 7], ['ao', 8], ['sep', 9], ['oct', 10], ['nov', 11], ['dec', 12], ['dc', 12]
];

function monthNumber(name) {
  var n = String(name || '').toLowerCase();
  for (var i = 0; i < MONTHS.length; i++) {
    if (n.indexOf(MONTHS[i][0]) === 0) { return MONTHS[i][1]; }
  }
  return 0;
}

function parseChapterDate(s) {
  var m = /(\\d{1,2})\\s+([^\\s]+)\\.?(?:\\s+(\\d{4}))?/.exec(String(s || ''));
  if (!m) { return 0; }
  var mo = monthNumber(m[2]);
  if (!mo) { return 0; }
  var now = new Date();
  var year = m[3] ? parseInt(m[3], 10) : now.getFullYear();
  var ts = Date.UTC(year, mo - 1, parseInt(m[1], 10)) / 1000;
  if (!m[3] && ts > Math.floor(Date.now() / 1000) + 86400) {
    ts = Date.UTC(year - 1, mo - 1, parseInt(m[1], 10)) / 1000;
  }
  return Math.floor(ts);
}

function statusMap(s) {
  var t = String(s || '').toLowerCase();
  if (t.indexOf('en cours') >= 0) { return 'ONGOING'; }
  if (t.indexOf('termin') >= 0) { return 'COMPLETED'; }
  if (t.indexOf('pause') >= 0) { return 'ON_HIATUS'; }
  if (t.indexOf('abandonn') >= 0 || t.indexOf('annul') >= 0) { return 'CANCELLED'; }
  return 'UNKNOWN';
}

async function getCatalogue(page, query, tri) {
  var body = 'action=madara_child_catalogue'
    + '&s=' + encodeURIComponent(query || '')
    + '&genres=&statut=tous&note=0&origine='
    + '&tri=' + tri
    + '&chmin=0&chmax=0'
    + '&page=' + page
    + '&auteur=&artiste=&annee=';
  var text = await $.http.post(BASE + '/wp-admin/admin-ajax.php', body, {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Referer': BASE + '/'
  });
  var data = JSON.parse(text).data || {};
  var doc = $.html.parse(data.html || '');
  var cards = R_sel(doc, 'a.ori-card');
  var mangas = [];
  for (var i = 0; i < cards.length; i++) {
    var card = cards[i];
    var titleEl = R_selFirst(card, 'span.ori-card-title');
    if (!titleEl) { continue; }
    var img = R_selFirst(card, 'img');
    mangas.push({
      key: '/' + CFG.mangaPath + '/' + toMangaSlug(card.attr('href')),
      title: titleEl.text(),
      coverUrl: img ? (img.absUrl('src') || img.attr('src') || '') : ''
    });
  }
  return { mangas: mangas, hasNextPage: !!data.more };
}

module.exports = {
  getPopularManga: async function (page) {
    return getCatalogue(page, '', 'populaire');
  },

  getSearchManga: async function (page, query) {
    return getCatalogue(page, query, 'recents');
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(mangaUrl(mangaKey));
    var doc = $.html.parse(text);
    var infos = {};
    var nodes = R_sel(doc, 'div.ori-sr-infos dt, div.ori-sr-infos dd');
    for (var i = 0; i < nodes.length; i += 2) {
      var label = nodes[i].text().trim().toLowerCase();
      var value = i + 1 < nodes.length ? nodes[i + 1].text().trim() : '';
      if (label) { infos[label] = value; }
    }
    var titleEl = R_selFirst(doc, 'h1.ori-sr-title');
    var coverEl = R_selFirst(doc, 'div.ori-sr-cover img');
    var desc = [];
    var ps = R_sel(doc, 'div.ori-sr-syn-texte p');
    for (var p = 0; p < ps.length; p++) {
      if (ps[p].text().trim()) { desc.push(ps[p].text().trim()); }
    }
    if (infos['nom alternatif']) {
      desc.push('Nom alternatif: ' + infos['nom alternatif']);
    }
    var genres = [];
    var gs = R_sel(doc, 'div.ori-sr-genres a.ori-sr-genre');
    for (var g = 0; g < gs.length; g++) { genres.push(gs[g].text()); }
    if (infos['type']) { genres.push(infos['type']); }
    return {
      key: mangaKey,
      title: titleEl ? titleEl.text() : '',
      coverUrl: coverEl ? (coverEl.absUrl('src') || coverEl.attr('src') || '') : '',
      author: infos['auteur'] || infos['scénario'] || '',
      artist: infos['artiste'] || infos['dessin'] || '',
      description: desc.join('\\n'),
      genre: genres.filter(Boolean).join(', '),
      status: statusMap(infos['statut'])
    };
  },

  getChapterList: async function (mangaKey) {
    var url = BASE + '/' + CFG.mangaPath + '/' + toMangaSlug(mangaKey) + '/ajax/chapters/';
    var text = await $.http.post(url, '', {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Referer': mangaUrl(mangaKey)
    });
    var doc = $.html.parse(text);
    var rows = R_sel(doc, 'div.ori-chl-row');
    var chapters = [];
    for (var i = 0; i < rows.length; i++) {
      var link = R_selFirst(rows[i], 'a.ori-chl-corps');
      if (!link) { continue; }
      var nameEl = R_selFirst(rows[i], 'span.ori-chl-nom');
      var dateEl = R_selFirst(rows[i], 'span.ori-chl-date');
      var slug = toChapterSlug(link.attr('href'));
      if (!slug) { continue; }
      chapters.push({
        key: '/' + CFG.mangaPath + '/' + slug,
        name: nameEl ? nameEl.text() : link.text(),
        dateUpload: dateEl ? parseChapterDate(dateEl.attr('title')) : 0
      });
    }
    // site lists newest first; host expects oldest first
    chapters.reverse();
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var url = BASE + '/' + CFG.mangaPath + '/' + toChapterSlug(chapterKey) + '/?style=list';
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, 'div.reading-content img.wp-manga-chapter-img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var src;
      if (imgs[i].attr('data-src')) {
        src = (imgs[i].absUrl('data-src') || imgs[i].attr('data-src') || '').trim();
      } else {
        src = (imgs[i].absUrl('src') || imgs[i].attr('src') || '').trim();
      }
      pages.push(src);
    }
    return pages;
  },

  imageHeaders: function () {
    return { 'Referer': BASE + '/' };
  }
};
`;
}
