// en/mangabolt — site redesigned: manga list now served as JSON from /manga-list (XHR)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['site redesigned since upstream ext: list switched to /manga-list JSON endpoint; chapter selectors kept with fallback'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

async function fetchList(page, query) {
  var u = BASE + '/manga-list?search=' + encodeURIComponent(query || '') + '&_=/';
  if (page > 1) { u += '&page=' + page; }
  var text = await $.http.get(u, { 'X-Requested-With': 'XMLHttpRequest', 'Accept': 'application/json' });
  var r = $.json.parse(text);
  var data = (r && r.mangas) || [];
  var mangas = [];
  for (var i = 0; i < data.length; i++) {
    var d = data[i];
    if (!d.slug) { continue; }
    mangas.push({
      key: '/manga/' + d.slug + '/',
      title: d.name || '',
      coverUrl: d.image_url || ''
    });
  }
  return { mangas: mangas, hasNextPage: !!(r && r.next_page_url) };
}

module.exports = {
  getPopularManga: async function (page) {
    return fetchList(page, '');
  },

  getSearchManga: async function (page, query) {
    return fetchList(page, query || '');
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var tEl = R_selFirst(doc, '#main-content h1') || R_selFirst(doc, 'h1');
    var title = tEl ? tEl.text().trim() : '';
    var dEl = R_selFirst(doc, 'div.bg-bg-secondary div.px-6 div.flex-col div.text-text-muted');
    return {
      key: mangaKey,
      title: title,
      coverUrl: R_img(R_selFirst(doc, 'div.flex img')),
      author: '',
      description: dEl ? dEl.text().trim() : '',
      genre: '',
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var out = [];
    var seen = {};
    var els = R_sel(doc, 'div.w-full div.bg-bg-secondary');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (!R_selFirst(el, 'div.grid')) { continue; }
      var link = R_selFirst(el, 'div.grid a');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var name = link.text();
      var sec = R_selFirst(el, '.text-xs');
      if (sec) {
        var st = sec.text();
        if (st && st.toLowerCase() !== 'read') { name += ' - ' + st; }
      }
      var k = R_path(href);
      if (seen[k]) { continue; }
      seen[k] = true;
      out.push({ key: k, name: name, chapterNumber: -1, dateUpload: 0, pages: 0, sortOrder: 0 });
    }
    if (!out.length) {
      // fallback: all chapter links on the page
      var links = R_sel(doc, 'a[href*="/chapter/"]');
      for (var j = 0; j < links.length; j++) {
        var h = links[j].absUrl('href');
        if (!h) { continue; }
        var k2 = R_path(h);
        if (seen[k2]) { continue; }
        seen[k2] = true;
        out.push({ key: k2, name: links[j].text() || k2, chapterNumber: -1, dateUpload: 0, pages: 0, sortOrder: 0 });
      }
    }
    // newest first on site -> oldest first
    out.reverse();
    for (var n = 0; n < out.length; n++) { out[n].sortOrder = n; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), HDRS);
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, '.js-pages-container img.js-page');
    if (!imgs.length) { imgs = R_sel(doc, 'img.js-page'); }
    var pages = [];
    var seen = {};
    for (var i = 0; i < imgs.length; i++) {
      var u = R_img(imgs[i]);
      if (!u || u.indexOf('data:image') >= 0 || seen[u]) { continue; }
      seen[u] = true;
      pages.push({ index: pages.length, url: u });
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
