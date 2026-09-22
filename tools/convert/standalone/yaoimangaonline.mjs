// all/yaoimangaonline — bespoke WordPress (herald theme) scraper
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'category/tag browse filters not portable; plain-text search only',
      'site currently behind a Cloudflare challenge from this network — probe may fail environmentally',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};

module.exports = {
  getPopularManga: async function (page) {
    return listMangas(BASE + '/page/' + page + '/');
  },

  getSearchManga: async function (page, query) {
    return listMangas(BASE + '/page/' + page + '/?s=' + encodeURIComponent(query));
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var title = R_selFirst(doc, 'h1.entry-title');
    var rawTitle = title ? title.text() : '';
    var cut = rawTitle.toLowerCase().lastIndexOf('by');
    var parsedTitle = cut > 0 ? rawTitle.substring(0, cut).trim() : rawTitle.trim();
    var cover = R_selFirst(doc, '.herald-post-thumbnail img');
    var descParts = [];
    var paras = R_sel(doc, '.entry-content > p');
    for (var i = 0; i < paras.length; i++) {
      var p = paras[i];
      if (R_selFirst(p, 'img')) { continue; }
      var t = p.text();
      if (!t || t.indexOf('You need to login') !== -1) { continue; }
      descParts.push(t);
    }
    var author = '';
    for (var j = 0; j < paras.length; j++) {
      var pt = paras[j].text();
      if (pt.indexOf('Mangaka:') !== -1) {
        author = pt.substring(pt.indexOf('Mangaka:') + 8);
        var langCut = author.indexOf('Language:');
        if (langCut !== -1) { author = author.substring(0, langCut); }
        author = author.trim();
        break;
      }
    }
    var tags = R_sel(doc, '.meta-tags > a');
    var tagNames = [];
    for (var k = 0; k < tags.length; k++) { tagNames.push(tags[k].text()); }
    return {
      key: mangaKey,
      title: parsedTitle,
      coverUrl: cover ? (cover.attr('src') || '') : '',
      author: author,
      artist: '',
      description: descParts.join('\\n\\n'),
      genre: tagNames.join(', '),
      status: 'completed',
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var anchors = R_sel(doc, '.mpp-toc a');
    var out = [];
    for (var i = 0; i < anchors.length; i++) {
      var a = anchors[i];
      var href = a.absUrl('href');
      if (!href) { href = R_abs(mangaKey); }
      out.push({
        key: R_path(href),
        name: R_ownText(a) || 'Chapter',
        chapterNumber: -1,
        dateUpload: 0,
        pages: 0,
        sortOrder: 0,
      });
    }
    if (out.length === 0) {
      out.push({
        key: mangaKey,
        name: 'Chapter',
        chapterNumber: -1,
        dateUpload: 0,
        pages: 0,
        sortOrder: 0,
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, '.entry-content img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].attr('src');
      if (u) { pages.push({ index: pages.length, url: R_abs(u) }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};

async function listMangas(url) {
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var anchors = R_sel(doc, '.post:not(.category-gay-movies):not(.category-yaoi-anime) > div > a');
  var out = [];
  var seen = {};
  for (var i = 0; i < anchors.length; i++) {
    var a = anchors[i];
    var href = a.absUrl('href');
    if (!href) { continue; }
    var key = R_path(href);
    if (seen[key]) { continue; }
    seen[key] = true;
    var img = R_selFirst(a, 'img');
    out.push({
      key: key,
      title: a.attr('title') || a.text(),
      coverUrl: img ? (img.attr('src') || '') : '',
    });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, '.herald-pagination > .next') };
}
`;
}
