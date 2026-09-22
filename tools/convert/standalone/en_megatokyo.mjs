// en/megatokyo (megatokyo.com) — single-title webcomic, archive listing
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'single-title source; search unsupported (upstream throws)',
      'upstream ignores TLS errors (self-signed/broken cert); if fetch fails on-device the site cert is the cause',
    ],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};

var MONTHS = { January: 0, February: 1, March: 2, April: 3, May: 4, June: 5, July: 6, August: 7, September: 8, October: 9, November: 10, December: 11 };
function parseDate(s) {
  var v = String(s || '').replace(/(\\d+)(st|nd|rd|th)/, '$1').trim();
  var m = /([A-Za-z]+)\\s+(\\d{1,2}),?\\s+(\\d{4})/.exec(v);
  if (!m) { return 0; }
  var mo = MONTHS[m[1]];
  if (mo === undefined) { return 0; }
  return new Date(parseInt(m[3], 10), mo, parseInt(m[2], 10)).getTime();
}

var FIXED = {
  key: '/archive.php?list_by=date',
  title: 'Megatokyo',
  artist: 'Fred Gallagher',
  author: 'Fred Gallagher',
  status: 'ongoing',
  description: 'Relax, we understand j00',
  coverUrl: 'https://i.ibb.co/yWQM1gY/megatokyo.png'
};

module.exports = {
  getPopularManga: async function (page) {
    return { mangas: [FIXED], hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    throw new Error('search not supported');
  },

  getMangaDetail: async function (mangaKey) {
    return FIXED;
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(BASE + '/archive.php?list_by=date', {}));
    var els = R_sel(doc, 'div.content h2 + div ul li a[name]');
    if (!els.length) { els = R_sel(doc, 'a[name]'); }
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var a = els[i];
      var href = a.attr('href') || '';
      if (!href) { continue; }
      var num = parseFloat(href.substring(href.lastIndexOf('/') + 1));
      out.push({
        key: R_path(href),
        name: a.text(),
        chapterNumber: isNaN(num) ? -1 : num,
        dateUpload: parseDate(a.attr('title')),
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
    var els = R_sel(doc, '#strip img');
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
