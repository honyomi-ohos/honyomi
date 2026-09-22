// all/xkcd — bespoke engine (multi-lang collapsed to en; single-manga grouping)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'multi-language ext collapsed to single plugin (English xkcd.com)',
      'organization-method preference fixed to "single manga"; search not supported upstream',
      'hover-text TextInterceptor page not portable (image page only)',
      'bundled thumbnail asset not portable; cover resolved from newest comic best-effort',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var SYNOPSIS = 'A webcomic of romance, sarcasm, math and language.';

function pad2(s) { return s.length < 2 ? '0' + s : s; }
function timestamp(dateStr) {
  var parts = String(dateStr || '').split('-');
  var norm = parts.length === 3 ? parts[0] + '-' + pad2(parts[1]) + '-' + pad2(parts[2]) : dateStr;
  var ts = Date.parse(norm + 'T00:00:00Z');
  return isNaN(ts) ? 0 : ts;
}

module.exports = {
  getPopularManga: async function (page) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    var cover = '';
    try {
      var atext = await $.http.get(BASE + '/archive/');
      var adoc = $.html.parse(atext);
      var anchors = R_sel(adoc, '#middleContainer > a');
      if (anchors.length) {
        var newest = anchors[0].absUrl('href');
        var ctext = await $.http.get(newest);
        var cdoc = $.html.parse(ctext);
        var img = R_selFirst(cdoc, '#comic > img');
        if (img) {
          var srcset = img.absUrl('srcset');
          cover = srcset ? srcset.split(' ')[0] : img.absUrl('src');
        }
      }
    } catch (e) { /* cover optional */ }
    return {
      mangas: [{ key: '/single', title: 'xkcd', coverUrl: cover }],
      hasNextPage: false,
    };
  },

  getSearchManga: async function (page, query) {
    return { mangas: [], hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    return {
      key: mangaKey,
      title: 'xkcd',
      coverUrl: '',
      author: 'Randall Munroe',
      artist: 'Randall Munroe',
      description: SYNOPSIS,
      genre: '',
      status: 'ongoing',
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(BASE + '/archive/');
    var doc = $.html.parse(text);
    var anchors = R_sel(doc, '#middleContainer > a');
    var out = [];
    for (var i = 0; i < anchors.length; i++) {
      var a = anchors[i];
      var href = a.absUrl('href');
      if (!href) { continue; }
      var num = parseInt(R_path(href).replace(/\\//g, ''), 10);
      if (isNaN(num)) { continue; }
      out.push({
        key: '/' + num,
        name: num + ': ' + a.text(),
        chapterNumber: num,
        dateUpload: timestamp(a.attr('title')),
        pages: 0,
        sortOrder: 0,
      });
    }
    // archive lists newest-first; host convention is oldest-first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey) + '/');
    var doc = $.html.parse(text);
    var container = R_selFirst(doc, '#comic > img');
    if (!container) {
      throw new Error('To experience the interactive version of this comic, open it in WebView/browser.');
    }
    var srcset = container.absUrl('srcset');
    var image = srcset ? srcset.split(' ')[0] : container.absUrl('src');
    if (!image) {
      throw new Error('To experience the interactive version of this comic, open it in WebView/browser.');
    }
    return [{ index: 0, url: image }];
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
