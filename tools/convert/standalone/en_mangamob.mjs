// en/mangamob (mangamob.net, "Comivex") — simple Jsoup scraper with ajax explore listing
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['hide-stale-explore-entries preference not ported (stale pinned entries may appear in Updated sort); filters not ported'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function exploreParse(text) {
  var doc = $.html.parse(text);
  var els = R_sel(doc, 'article.manga-card');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var card = els[i];
    var link = R_selFirst(card, 'a.card-cover');
    var nameEl = R_selFirst(card, '.card-title a');
    if (!link || !nameEl) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    out.push({
      key: new URL(href, BASE).pathname + new URL(href, BASE).search,
      title: nameEl.text(),
      coverUrl: R_abs((R_selFirst(card, 'img') || { attr: function () { return ''; } }).attr('src'))
    });
  }
  return { mangas: out, hasNextPage: out.length > 0 };
}

function parseRelativeDate(dateStr) {
  var re = /(\\d+)\\s+(year|month|week|day|hour|minute)s?/g;
  var m;
  var matched = false;
  var ms = Date.now();
  while ((m = re.exec(String(dateStr || ''))) !== null) {
    matched = true;
    var amount = parseInt(m[1], 10);
    var unit = m[2];
    if (unit === 'year') { ms -= amount * 365 * 86400000; }
    else if (unit === 'month') { ms -= amount * 30 * 86400000; }
    else if (unit === 'week') { ms -= amount * 7 * 86400000; }
    else if (unit === 'day') { ms -= amount * 86400000; }
    else if (unit === 'hour') { ms -= amount * 3600000; }
    else if (unit === 'minute') { ms -= amount * 60000; }
  }
  return matched ? ms : 0;
}

function parseStatus(s) {
  var lower = String(s || '').toLowerCase();
  if (lower.indexOf('ongoing') >= 0) { return 'ongoing'; }
  if (lower.indexOf('completed') >= 0) { return 'completed'; }
  if (lower.indexOf('hiatus') >= 0) { return 'on hiatus'; }
  return '';
}

module.exports = {
  getPopularManga: async function (page) {
    return exploreParse(await $.http.get(BASE + '/explore/?sort_by=Views&results=' + page + '&ajax=1', HDRS));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/explore/?search=' + encodeURIComponent(query || '') +
      '&genre_included=&sort_by=Views&status=&results=' + page + '&ajax=1';
    return exploreParse(await $.http.get(u, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var genres = [];
    var gels = R_sel(doc, '.md-genres a.md-genre-pill');
    for (var i = 0; i < gels.length; i++) { genres.push(gels[i].text()); }
    var titleEl = R_selFirst(doc, '.md-title');
    if (!titleEl) { throw new Error('Title not found'); }
    return {
      key: mangaKey,
      title: titleEl.text(),
      coverUrl: R_abs((R_selFirst(doc, '.md-cover-wrap img.md-cover') || { attr: function () { return ''; } }).attr('src')),
      author: (R_selFirst(doc, '.md-author span') || { text: function () { return ''; } }).text(),
      description: (R_selFirst(doc, '#synopsis') || { text: function () { return ''; } }).text(),
      genre: genres.join(', '),
      status: parseStatus((R_selFirst(doc, '.md-status') || { text: function () { return ''; } }).text())
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var els = R_sel(doc, '.ch-list .ch-item');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var link = R_selFirst(el, 'a.ch-link');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var u = new URL(href, BASE);
      var numEl = R_selFirst(el, '.ch-num');
      var dateEl = R_selFirst(el, '.ch-date');
      out.push({
        key: u.pathname + u.search,
        name: numEl ? numEl.text() : '',
        chapterNumber: -1,
        dateUpload: parseRelativeDate(dateEl ? dateEl.text() : ''),
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var els = R_sel(doc, '#chapter-images .page-wrapper img');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var src = els[i].absUrl('src');
      if (src) { out.push({ index: out.length, url: src }); }
    }
    return out;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
