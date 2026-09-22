// en/manhwa18 (manhwa18.org) — NSFW manhwa scraper (tim-kiem listing)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'sort/status/genre filters not ported; text search only',
      'live site chapter markup differs from upstream Kotlin (au-chtile gone, ul.list-chapters now); both selectors included',
    ],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function styleUrl(el) {
  var style = el ? (el.attr('style') || '') : '';
  var m = /url\\('([^']*)'\\)/.exec(style);
  return m ? m[1] : '';
}

function parseList(text) {
  var doc = $.html.parse(text);
  var els = R_sel(doc, '.thumb-item-flow');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var a = R_selFirst(el, 'a');
    var titleEl = R_selFirst(el, '.series-title a');
    if (!a || !titleEl) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    var cover = '';
    var bg = R_selFirst(el, '.lazy-bg');
    if (bg && bg.attr('data-bg')) { cover = bg.attr('data-bg'); }
    else { cover = styleUrl(R_selFirst(el, '.img-in-ratio')); }
    out.push({ key: R_path(href), title: titleEl.text(), coverUrl: cover });
  }
  var hasNext = !!R_selFirst(doc, '.pagination_wrap a.next');
  return { mangas: out, hasNextPage: hasNext };
}

// "dd/MM/yyyy"
function parseDmy(s) {
  var v = String(s || '').trim();
  var m = /^(\\d{1,2})\\/(\\d{1,2})\\/(\\d{4})/.exec(v);
  if (!m) { return 0; }
  return new Date(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10)).getTime();
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(BASE + '/tim-kiem?sort=top&page=' + page, HDRS));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/tim-kiem?sort=update&page=' + page;
    if (query && query.trim()) { u = BASE + '/tim-kiem?q=' + encodeURIComponent(query.trim()) + '&sort=update&page=' + page; }
    return parseList(await $.http.get(u, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var title = '';
    var tEl = R_selFirst(doc, '.series-name a') || R_selFirst(doc, '.au-bento h1') || R_selFirst(doc, '.au-crumb a:last-child');
    if (tEl) { title = tEl.text(); }
    var author = '', genre = '', status = '';
    var items = R_sel(doc, '.series-information .info-item');
    for (var i = 0; i < items.length; i++) {
      var item = items[i];
      var nameEl = R_selFirst(item, '.info-name');
      var valueEl = R_selFirst(item, '.info-value');
      if (!nameEl || !valueEl) { continue; }
      var nm = (nameEl.text() || '').toLowerCase();
      var val = valueEl.text();
      if (nm.indexOf('author') >= 0) { author = val; }
      else if (nm.indexOf('genre') >= 0) {
        var genres = [];
        var as = R_sel(item, '.info-value a');
        for (var a = 0; a < as.length; a++) { genres.push(as[a].text()); }
        genre = genres.join(', ');
      } else if (nm.indexOf('status') >= 0) {
        var sv = val.toLowerCase();
        if (sv === 'ongoing') { status = 'ongoing'; }
        else if (sv === 'completed') { status = 'completed'; }
        else if (sv === 'on hold') { status = 'on hiatus'; }
      }
    }
    if (!author) {
      author = (R_selFirst(doc, '.fantrans-value a') || { text: function () { return ''; } }).text();
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: styleUrl(R_selFirst(doc, '.series-cover .img-in-ratio')),
      author: author,
      description: (R_selFirst(doc, '.summary-content') || { text: function () { return ''; } }).text(),
      genre: genre,
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var els = R_sel(doc, 'ul.list-chapters a');
    if (!els.length) { els = R_sel(doc, 'div.au-chgrid a.au-chtile'); }
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var a = els[i];
      var href = a.absUrl('href');
      if (!href) { continue; }
      var nm = a.attr('title') || a.attr('data-name') || '';
      if (!nm) {
        var nmEl = R_selFirst(a, '.chapter-name');
        nm = nmEl ? nmEl.text() : '';
      }
      var dateEl = R_selFirst(a, '.au-chtile-date') || R_selFirst(a, '.chapter-time');
      var dateStr = '';
      if (dateEl) {
        var t = dateEl.text() || '';
        var sepIdx = t.lastIndexOf('-');
        dateStr = sepIdx >= 0 ? t.substring(sepIdx + 1).trim() : t.trim();
      }
      out.push({
        key: R_path(href),
        name: nm,
        chapterNumber: -1,
        dateUpload: parseDmy(dateStr),
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
    var els = R_sel(doc, '#chapter-content img.lazy');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var src = els[i].absUrl('data-src');
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
