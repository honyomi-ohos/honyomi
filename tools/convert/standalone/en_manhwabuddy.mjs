// en/manhwabuddy (manhwabuddy.com) — simple Jsoup scraper
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

var MONTHS = { January: 0, February: 1, March: 2, April: 3, May: 4, June: 5, July: 6, August: 7, September: 8, October: 9, November: 10, December: 11 };
function parseDate(s) {
  var m = /(\\d{1,2})\\s+([A-Za-z]+)\\s+(\\d{4})/.exec(String(s || '').trim());
  if (!m) { return 0; }
  var mo = MONTHS[m[2]];
  if (mo === undefined) { return 0; }
  return new Date(parseInt(m[3], 10), mo, parseInt(m[1], 10)).getTime();
}

module.exports = {
  getPopularManga: async function (page) {
    var doc = $.html.parse(await $.http.get(BASE + '/', {}));
    var els = R_sel(doc, '.item-move');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var a = R_selFirst(el, 'a');
      var h = R_selFirst(el, 'h3');
      if (!a || !h) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      var img = R_selFirst(el, 'img');
      out.push({ key: R_path(href), title: h.text(), coverUrl: img ? (img.attr('src') || '') : '' });
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var doc = $.html.parse(await $.http.get(BASE + '/search?s=' + encodeURIComponent(query || '') + '&page=' + page, {}));
    var hasNext = !!R_selFirst(doc, '.next');
    var els = R_sel(doc, '.latest-list .latest-item');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var a = R_selFirst(el, 'a');
      if (!a) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      var img = R_selFirst(el, 'img');
      out.push({ key: R_path(href), title: a.attr('title') || '', coverUrl: img ? (img.attr('src') || '') : '' });
    }
    return { mangas: out, hasNextPage: hasNext };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), {}));
    var info = R_selFirst(doc, '.main-info-right');
    var author = '', artist = '', genre = '', status = '';
    if (info) {
      var lis = R_sel(info, 'li');
      for (var i = 0; i < lis.length; i++) {
        var li = lis[i];
        var t = (li.text() || '').trim();
        if (t.indexOf('Author') === 0) {
          var aa = R_selFirst(li, 'a');
          author = aa ? aa.text() : '';
        } else if (t.indexOf('Artist') === 0) {
          var ar = R_selFirst(li, 'a');
          artist = ar ? ar.text() : '';
        } else if (t.indexOf('Status') === 0) {
          var sp = R_selFirst(li, 'span');
          var sv = sp ? (sp.text() || '').trim() : '';
          if (sv === 'Ongoing') { status = 'ongoing'; }
          else if (sv === 'Complete') { status = 'completed'; }
        } else if (t.indexOf('Genres') === 0) {
          var gs = [];
          var gas = R_sel(li, 'a');
          for (var g = 0; g < gas.length; g++) { gs.push(gas[g].text()); }
          genre = gs.join(', ');
        }
      }
    }
    var desc = [];
    var ps = R_sel(doc, '.short-desc-content p');
    for (var p = 0; p < ps.length; p++) { desc.push(ps[p].text()); }
    return {
      key: mangaKey,
      title: '',
      coverUrl: '',
      author: author,
      artist: artist,
      description: desc.join('\\n'),
      genre: genre,
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), {}));
    var els = R_sel(doc, '.chapter-list a');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var a = els[i];
      var href = a.absUrl('href');
      var nm = R_selFirst(a, '.chapter-name');
      if (!href || !nm) { continue; }
      var dt = R_selFirst(a, '.ct-update');
      out.push({
        key: R_path(href),
        name: nm.text(),
        chapterNumber: -1,
        dateUpload: dt ? parseDate(dt.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), {}));
    var els = R_sel(doc, '.loading');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var src = els[i].absUrl('src');
      if (src) { out.push({ index: out.length, url: src }); }
    }
    return out;
  },

  imageHeaders: function () {
    return {};
  }
};
`;
}
