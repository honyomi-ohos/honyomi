// en/mangahen (gensura.net) — single-chapter doujin scraper
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['single "Chapter" per entry (site is one-shot doujins); tags filter not ported'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function parseList(text) {
  var doc = $.html.parse(text);
  var els = R_sel(doc, 'a[href^="/manga/"]');
  var out = [];
  var seen = {};
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var h2 = R_selFirst(el, 'h2');
    var img = R_selFirst(el, 'img');
    if (!h2 || !img) { continue; }
    var href = el.absUrl('href');
    if (!href) { continue; }
    var k = R_path(href);
    if (seen[k]) { continue; }
    seen[k] = true;
    out.push({ key: k, title: R_ownText(h2), coverUrl: R_abs(img.attr('src')) });
  }
  var hasNext = false;
  var pageLinks = R_sel(doc, 'a[href*="page"]');
  for (var j = 0; j < pageLinks.length; j++) {
    if (!pageLinks[j].text()) { hasNext = true; break; }
  }
  return { mangas: out, hasNextPage: hasNext };
}

function joinTexts(doc, sel) {
  var els = R_sel(doc, sel);
  var parts = [];
  for (var i = 0; i < els.length; i++) { parts.push(els[i].text()); }
  return parts.join(', ');
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(BASE + '/advanced-search/?search=1&type=0&sort=1&page=' + page, HDRS));
  },

  getSearchManga: async function (page, query) {
    return parseList(await $.http.get(BASE + '/advanced-search/?search=1&type=0&sort=1&name=' + encodeURIComponent(query || '') + '&page=' + page, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var authors = joinTexts(doc, 'a[href*="/circles/"]');
    var artists = joinTexts(doc, 'a[href*="/authors/"]');
    var h1 = R_selFirst(doc, 'h1.font-semibold');
    var titles = h1 ? h1.text().split(' | ') : [];
    var altH2 = R_selFirst(doc, 'h2.text-lg.font-medium');
    var altit = altH2 ? altH2.text() : '';
    var desc = '';
    if (titles.length > 1) {
      desc += 'Alternative Titles:\\n- ' + titles[1] + '\\n';
      if (altit) { desc += '- ' + altit + '\\n'; }
      desc += '\\n';
    }
    desc += 'Categories: ' + (R_selFirst(doc, 'a[href*="/categories/"]') || { text: function () { return ''; } }).text() + '\\n';
    desc += 'Parodies: ' + (R_selFirst(doc, 'a[href*="/parodies/"]') || { text: function () { return ''; } }).text() + '\\n';
    desc += 'Circles: ' + (R_selFirst(doc, 'a[href*="/circles/"]') || { text: function () { return ''; } }).text() + '\\n\\n';
    var pageRows = R_sel(doc, 'tr');
    for (var i = 0; i < pageRows.length; i++) {
      var t = pageRows[i].text().toLowerCase();
      if (t.indexOf('page') >= 0 || t.indexOf('view') >= 0) { desc += pageRows[i].text() + '\\n'; }
    }
    return {
      key: mangaKey,
      title: titles[0] || '',
      coverUrl: R_img(R_selFirst(doc, 'img[src*="thumbnail"].w-96')),
      author: authors || artists,
      artist: artists,
      description: desc,
      genre: joinTexts(doc, 'a[href*="/tags/"]'),
      status: 'completed'
    };
  },

  getChapterList: async function (mangaKey) {
    return [{
      key: mangaKey,
      name: 'Chapter',
      chapterNumber: -1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), HDRS);
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, 'img');
    var pages = [];
    var seen = {};
    for (var i = 0; i < imgs.length; i++) {
      var img = imgs[i];
      var src = img.attr('src');
      var dsrc = img.attr('data-src');
      var u = '';
      if (src && src.indexOf('images') >= 0 && src.indexOf('thumbnail') < 0) { u = R_abs(src); }
      else if (dsrc && dsrc.indexOf('images') >= 0) { u = R_abs(dsrc); }
      if (!u || seen[u]) { continue; }
      seen[u] = true;
      pages.push({ index: pages.length, url: u.replace(/-t(?=\\.)/, '') });
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
