// en/manhwalike (manhwalike.com) — homepage hot list + form POST search
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['genre filter not ported; text search only'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

var MONTHS = { January: 0, February: 1, March: 2, April: 3, May: 4, June: 5, July: 6, August: 7, September: 8, October: 9, November: 10, December: 11 };
function parseDate(s) {
  var m = /([A-Za-z]+)\\s+(\\d{1,2}),?\\s+(\\d{4})/.exec(String(s || '').trim());
  if (!m) { return 0; }
  var mo = MONTHS[m[1]];
  if (mo === undefined) { return 0; }
  return new Date(parseInt(m[3], 10), mo, parseInt(m[2], 10)).getTime();
}

function imgOriginal(img) {
  if (!img) { return ''; }
  if (img.attr('data-original')) { return img.absUrl('data-original'); }
  return img.absUrl('src');
}

function parseVisualList(doc) {
  var els = R_sel(doc, 'div.visual');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var a = R_selFirst(el, 'a');
    var h = R_selFirst(el, 'h3.title a');
    if (!a) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    out.push({ key: R_path(href), title: h ? h.text() : '', coverUrl: imgOriginal(R_selFirst(el, 'img')) });
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    var doc = $.html.parse(await $.http.get(BASE + '/', HDRS));
    var mangas = [];
    var els = R_sel(doc, 'ul.list-hot div.visual');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var a = R_selFirst(el, 'a');
      var h = R_selFirst(el, 'h3.title a');
      if (!a || !h) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      mangas.push({ key: R_path(href), title: h.text(), coverUrl: imgOriginal(R_selFirst(el, 'img')) });
    }
    return { mangas: mangas, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var body = 'keyword=' + encodeURIComponent(query || '');
    var text = await $.http.post(BASE + '/search/html/1', body, {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'text/html',
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': BASE + '/'
    });
    var doc = $.html.parse(text);
    var lis = R_sel(doc, 'ul.normal li');
    if (!lis.length) { lis = R_sel(doc, 'ul li'); }
    var out = [];
    for (var i = 0; i < lis.length; i++) {
      var li = lis[i];
      var img = R_selFirst(li, 'img');
      var a = R_selFirst(li, 'a');
      if (!img || !a) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      out.push({ key: R_path(href), title: img.attr('alt') || '', coverUrl: imgOriginal(img) });
    }
    var hasNext = !!R_selFirst(doc, 'ul.pagination li:last-child a');
    return { mangas: out, hasNextPage: hasNext };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var status = '';
    var sm = /<small[^>]*>[^<]*Status[^<]*<\\/small>\\s*<strong[^>]*>([^<]*)<\\/strong>/.exec(text);
    if (sm) {
      var sv = sm[1].trim();
      if (/ongoing/i.test(sv)) { status = 'ongoing'; }
      else if (/finish/i.test(sv)) { status = 'completed'; }
    }
    var genres = [];
    var gas = R_sel(doc, 'div.categories a');
    for (var g = 0; g < gas.length; g++) { genres.push(gas[g].text()); }
    return {
      key: mangaKey,
      title: '',
      coverUrl: (function (el) { return el ? el.absUrl('src') : ''; })(R_selFirst(doc, 'div.fixed-img img')),
      author: (R_selFirst(doc, 'div.author a') || { text: function () { return ''; } }).text(),
      description: (R_selFirst(doc, 'div.summary-block p.about') || { text: function () { return ''; } }).text(),
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var els = R_sel(doc, 'ul.chapter-list li');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var li = els[i];
      var a = R_selFirst(li, 'a');
      if (!a) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      var timeEl = R_selFirst(li, '.time');
      out.push({
        key: R_path(href),
        name: a.text(),
        chapterNumber: -1,
        dateUpload: timeEl ? parseDate(timeEl.text()) : 0,
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
    var els = R_sel(doc, '.chapter-content .page-chapter img');
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
