// MangaWorld theme engine (it: mangaworld, mangaworldadult) — WP archive theme
export const runtime = 'wp';

export function extract(ctx) {
  const warnings = [];
  const config = {};
  warnings.push('archive filters (genre/status/type/year/sort) not supported by host; text search only');
  warnings.push('CookieRedirectInterceptor not replicable; cookie-gated redirects may fail');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mangaworld)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var IT_MONTHS = {
  'gennaio': 1, 'febbraio': 2, 'marzo': 3, 'aprile': 4, 'maggio': 5, 'giugno': 6,
  'luglio': 7, 'agosto': 8, 'settembre': 9, 'ottobre': 10, 'novembre': 11, 'dicembre': 12
};

function parseItDate(s) {
  var m = /(\\d{1,2})\\s+([A-Za-z]+)\\s+(\\d{4})/.exec(String(s || '').trim());
  if (!m) { return 0; }
  var mo = IT_MONTHS[m[2].toLowerCase()];
  if (!mo) { return 0; }
  return Math.floor(Date.UTC(parseInt(m[3], 10), mo - 1, parseInt(m[1], 10)) / 1000);
}

function statusMap(s) {
  var t = String(s || '').toLowerCase();
  if (t === 'in corso') { return 'ONGOING'; }
  if (t === 'finito') { return 'COMPLETED'; }
  if (t === 'in pausa') { return 'ON_HIATUS'; }
  if (t === 'cancellato') { return 'CANCELLED'; }
  return 'UNKNOWN';
}

function parseList(doc) {
  var entries = R_sel(doc, 'div.comics-grid .entry');
  var mangas = [];
  for (var i = 0; i < entries.length; i++) {
    var a = R_selFirst(entries[i], 'a');
    if (!a) { continue; }
    var img = R_selFirst(entries[i], 'a.thumb img');
    var href = (a.absUrl('href') || a.attr('href') || '').replace(/\\/+$/, '');
    mangas.push({
      key: R_path(href),
      title: a.attr('title') || '',
      coverUrl: img ? (img.absUrl('src') || img.attr('src') || '') : ''
    });
  }
  return { mangas: mangas, hasNextPage: mangas.length === 16 };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/archive?sort=most_read&page=' + page);
    return parseList($.html.parse(text));
  },

  getSearchManga: async function (page, query) {
    var url = BASE + '/archive?page=' + page;
    if (query) { url += '&keyword=' + encodeURIComponent(query); }
    var text = await $.http.get(url);
    return parseList($.html.parse(text));
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(BASE + mangaKey);
    var doc = $.html.parse(text);
    var info = R_selFirst(doc, 'div.comic-info');
    var author = '', artist = '', cover = '', desc = '', genre = '', status = 'UNKNOWN';
    if (info) {
      var authorEl = R_selFirst(info, 'a[href*="/archive?author="]');
      var artistEl = R_selFirst(info, 'a[href*="/archive?artist="]');
      var coverEl = R_selFirst(info, '.thumb > img');
      var statusEl = R_selFirst(info, 'a[href*="/archive?status="]');
      author = authorEl ? authorEl.text() : '';
      artist = artistEl ? artistEl.text() : '';
      cover = coverEl ? (coverEl.absUrl('src') || coverEl.attr('src') || '') : '';
      status = statusMap(statusEl ? statusEl.text() : '');
      var badges = R_sel(info, 'div.meta-data a.badge');
      var gs = [];
      for (var b = 0; b < badges.length; b++) { gs.push(badges[b].text()); }
      genre = gs.join(', ');
    }
    var bodyEl = R_selFirst(doc, 'div#noidungm');
    if (bodyEl) { desc = bodyEl.text(); }
    var altEl = R_selFirst(doc, 'div.meta-data > div');
    if (altEl) {
      var alt = altEl.text();
      if (alt.indexOf('Titoli alternativi') >= 0) {
        desc += (desc ? '\\n\\n' : '') + alt;
      }
    }
    var titleEl = R_selFirst(doc, 'h1.name, h1');
    return {
      key: mangaKey,
      title: titleEl ? titleEl.text() : '',
      coverUrl: cover,
      author: author,
      artist: artist,
      description: desc,
      genre: genre,
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(BASE + mangaKey);
    var doc = $.html.parse(text);
    var rows = R_sel(doc, '.chapters-wrapper .chapter');
    var chapters = [];
    for (var i = 0; i < rows.length; i++) {
      var link = R_selFirst(rows[i], 'a.chap');
      if (!link) { continue; }
      var nameEl = R_selFirst(rows[i], 'span.d-inline-block');
      var dates = R_sel(rows[i], '.chap-date');
      var dateStr = dates.length > 0 ? dates[dates.length - 1].text() : '';
      var key = R_path(link.absUrl('href') || link.attr('href'));
      if (!key) { continue; }
      chapters.push({
        key: key,
        name: nameEl ? nameEl.text() : '',
        dateUpload: parseItDate(dateStr)
      });
    }
    // site lists newest first; host expects oldest first
    chapters.reverse();
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var url = BASE + chapterKey;
    url += (url.indexOf('?') >= 0 ? '&' : '?') + 'style=list';
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, 'div#page img.page-image');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].absUrl('src') || imgs[i].attr('src') || '';
      if (src) { pages.push(src); }
    }
    return pages;
  },

  imageHeaders: function () {
    return {
      'User-Agent': 'Mozilla/5.0 (Linux; U; Android 4.1.1; en-gb; Build/KLP) AppleWebKit/534.30 (KHTML, like Gecko) Version/4.0 Safari/534.30',
      'Referer': BASE + '/'
    };
  }
};
`;
}
