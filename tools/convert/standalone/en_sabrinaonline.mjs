// en/sabrinaonline — bespoke scraper (single manga, paired archive table rows)
export const runtime = 'wp';

export function extract(ctx) {
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function mangaEntry() {
  return {
    key: '/archive.html',
    title: 'Sabrina Online',
    coverUrl: 'https://dummyimage.com/768x994/000/ffffff.jpg&text=Sabrina Online',
    author: 'Eric W. Schwartz',
    artist: 'Eric W. Schwartz',
    description: '',
    genre: '',
    status: ''
  };
}

function trToChapters(tr, sections) {
  var out = [];
  var tds = R_sel(tr, 'td');
  for (var i = 0; i < tds.length; i++) {
    var links = R_sel(tds[i], 'a');
    for (var j = 0; j < links.length; j++) {
      var a = links[j];
      var chapterName = a.text();
      if (!chapterName) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      var sec = sections[i] || '';
      var hasYear = sec && /[0-9]/.test(sec.charAt(0));
      out.push({
        key: R_path(href),
        name: hasYear ? (sec + ' ' + chapterName) : chapterName,
        chapterNumber: -1,
        dateUpload: 0,
        pages: 0,
        sortOrder: 0
      });
    }
  }
  return out;
}

module.exports = {
  getPopularManga: async function () {
    var m = mangaEntry();
    return { mangas: [{ key: m.key, title: m.title, coverUrl: m.coverUrl }], hasNextPage: false };
  },

  getSearchManga: async function () {
    return { mangas: [], hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    return mangaEntry();
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(BASE + '/archive.html', HDRS));
    var rows = R_sel(doc, 'center table tr');
    var chapters = [];
    for (var i = 0; i < rows.length; i += 2) {
      var first = rows[i];
      var second = rows[i + 1];
      if (!second) {
        chapters = chapters.concat(trToChapters(first, []));
      } else {
        var sections = [];
        var tds = R_sel(first, 'td');
        for (var j = 0; j < tds.length; j++) { sections.push(String(tds[j].text() || '').trim()); }
        var hasSections = tds.length > 0;
        if (hasSections) {
          chapters = chapters.concat(trToChapters(second, sections));
        } else {
          chapters = chapters.concat(trToChapters(second, []));
          chapters = chapters.concat(trToChapters(first, []));
        }
      }
    }
    for (var k = 0; k < chapters.length; k++) { chapters[k].sortOrder = k; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var imgs = R_sel(doc, 'center img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var img = imgs[i];
      var src = img.attr('src') || '';
      if (src.indexOf('strips/') < 0 && src.indexOf('pages/') < 0) { continue; }
      var u = '';
      var parent = img.parentNode;
      if (parent && parent.tagName === 'a') {
        u = parent.absUrl ? parent.absUrl('href') : R_abs(parent.attr('href') || '');
      } else {
        u = img.absUrl ? img.absUrl('src') : R_abs(src);
      }
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
