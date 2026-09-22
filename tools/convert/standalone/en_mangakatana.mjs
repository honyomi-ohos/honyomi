// en/mangakatana (mangakatana.com) — Jsoup scraper with JS-embedded image arrays
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['server preference (?sv=) setting not ported (defaults to server 1); filters not ported, text search only'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function parseItems(doc) {
  var els = R_sel(doc, 'div#book_list > div.item');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var link = R_selFirst(el, 'div.text > h3 > a');
    var img = R_selFirst(el, 'img');
    if (!link || !img) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    out.push({ key: R_path(href), title: R_ownText(link), coverUrl: R_abs(img.attr('src')) });
  }
  var hasNext = !!R_selFirst(doc, 'a.next.page-numbers');
  return { mangas: out, hasNextPage: hasNext };
}

function parseKatanaDate(s) {
  // "MMM-dd-yyyy" e.g. Sep-20-2026
  var v = String(s || '').trim();
  if (!v) { return 0; }
  var t = Date.parse(v.replace(/-/g, ' '));
  return isNaN(t) ? (R_date(v) || 0) : t;
}

function parseStatus(s) {
  var v = String(s || '');
  if (v.indexOf('Ongoing') >= 0) { return 'ongoing'; }
  if (v.indexOf('Completed') >= 0) { return 'completed'; }
  return '';
}

function eachTextJoin(doc, sel, sep) {
  var els = R_sel(doc, sel);
  var parts = [];
  for (var i = 0; i < els.length; i++) {
    var t = els[i].text();
    if (t) { parts.push(t); }
  }
  return parts.join(sep || ', ');
}

module.exports = {
  getPopularManga: async function (page) {
    return parseItems($.html.parse(await $.http.get(BASE + '/manga/page/' + page, HDRS)));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/page/' + page + '?search=' + encodeURIComponent(query || '') + '&search_by=book';
    var text = await $.http.get(u, HDRS);
    var doc = $.html.parse(text);
    if (!R_selFirst(doc, 'div#book_list')) {
      // redirected straight to a single manga page
      var h1 = R_selFirst(doc, 'h1.heading');
      if (h1) {
        var canon = R_selFirst(doc, 'link[rel=canonical]');
        var k = canon ? R_path(canon.absUrl('href')) : '';
        if (k) {
          return {
            mangas: [{ key: k, title: h1.text(), coverUrl: R_img(R_selFirst(doc, 'div.media div.cover img')) }],
            hasNextPage: false
          };
        }
      }
      return { mangas: [], hasNextPage: false };
    }
    return parseItems(doc);
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var desc = '';
    var ps = R_sel(doc, '.summary > p');
    for (var i = 0; i < ps.length; i++) { desc += ps[i].text() + ' '; }
    desc = desc.trim();
    var alt = (R_selFirst(doc, '.alt_name') || { text: function () { return ''; } }).text();
    if (alt) { desc += '\\n\\nAlt name(s): ' + alt; }
    return {
      key: mangaKey,
      title: (R_selFirst(doc, 'h1.heading') || { text: function () { return ''; } }).text(),
      coverUrl: R_img(R_selFirst(doc, 'div.media div.cover img')),
      author: eachTextJoin(doc, '.author'),
      description: desc,
      genre: eachTextJoin(doc, '.genres > a'),
      status: parseStatus((R_selFirst(doc, '.value.status') || { text: function () { return ''; } }).text())
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var rows = R_sel(doc, 'tr');
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      if (!R_selFirst(row, '.chapter')) { continue; }
      var link = R_selFirst(row, 'a');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var dEl = R_selFirst(row, '.update_time');
      out.push({
        key: R_path(href),
        name: link.text(),
        chapterNumber: -1,
        dateUpload: dEl ? parseKatanaDate(dEl.text()) : 0,
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
    var scripts = R_sel(doc, 'script');
    var imageScript = '';
    for (var s = 0; s < scripts.length; s++) {
      var h = scripts[s].html ? scripts[s].html() : '';
      if (h.indexOf('data-src') >= 0) { imageScript = h; break; }
    }
    if (!imageScript) { return []; }
    var nameMatch = /data-src['"],\\s*(\\w+)/.exec(imageScript);
    if (!nameMatch) { return []; }
    var arrMatch = new RegExp('var ' + nameMatch[1] + '=\\\\[([^\\\\[]*)\\\\]').exec(imageScript);
    if (!arrMatch) { return []; }
    var urls = arrMatch[1].match(/'([^']*)'/g) || [];
    var pages = [];
    for (var i = 0; i < urls.length; i++) {
      var u = urls[i].substring(1, urls[i].length - 1);
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
