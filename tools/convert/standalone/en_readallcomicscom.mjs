// en/readallcomicscom — bespoke WP scraper (comic archive; author is LAST strong tag)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['chapter dates approximated to the year parsed from the chapter name'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function parseList(text, popular) {
  var doc = $.html.parse(text);
  var items = R_sel(doc, 'ul.list-story.categories li');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var a = R_selFirst(el, 'a.cat-title');
    if (!a) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, 'img.book-cover');
    out.push({
      key: R_path(href),
      title: a.text(),
      coverUrl: img ? R_abs(img.attr('src') || '') : ''
    });
  }
  var hasNext;
  if (popular) {
    hasNext = !!R_selFirst(doc, '.pagination .page-numbers.current + .page-numbers');
  } else {
    hasNext = !!R_selFirst(doc, 'a.next');
  }
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    var u = page > 1 ? BASE + '/?paged=' + page : BASE + '/';
    return parseList(await $.http.get(u, HDRS), true);
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/?story=' + encodeURIComponent(query || '') + '&s=&type=comic';
    if (page > 1) { u += '&paged=' + page; }
    return parseList(await $.http.get(u, HDRS), false);
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var archive = R_selFirst(doc, '.description-archive');
    var title = '', cover = '', genre = '', author = '', description = '';
    if (archive) {
      var h1 = R_selFirst(archive, 'h1');
      title = h1 ? h1.text() : '';
      var img = R_selFirst(archive, 'p img');
      cover = img ? R_abs(img.attr('src') || '') : '';
      var strongs = R_sel(archive, '.b > p strong');
      if (strongs.length > 0) { genre = strongs[0].text(); }
      if (strongs.length > 1) { author = strongs[strongs.length - 1].text(); }
      var descEl = R_selFirst(doc, '#hidden-description');
      if (descEl) { description = String(descEl.text() || '').trim(); }
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: author,
      description: description,
      genre: genre,
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var items = R_sel(doc, '.list-story a');
    var chapters = [];
    for (var i = 0; i < items.length; i++) {
      var a = items[i];
      var href = a.absUrl('href');
      if (!href) { continue; }
      var chName = a.text();
      var ym = /\\((\\d{4})\\)/.exec(chName);
      var date = 0;
      if (ym) { date = new Date(parseInt(ym[1], 10), 0, 1).getTime(); }
      chapters.push({
        key: R_path(href),
        name: chName,
        chapterNumber: -1,
        dateUpload: date,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var imgs = R_sel(doc, 'body img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var img = imgs[i];
      var inLogo = false;
      var p = img;
      while (p && p.parentNode) {
        if (p.id === 'logo') { inLogo = true; break; }
        p = p.parentNode;
      }
      if (inLogo) { continue; }
      var u = R_abs(img.attr('src') || '');
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
