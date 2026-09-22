// all/v2ph — bespoke scraper engine (album gallery; dt/dd definition pairing)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['category/country browse filters not portable (text search + popular only); premium /user/ albums throw like upstream'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone scraper)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};

function hdrs() {
  return {
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': BASE + '/',
  };
}
function checkPaywall(key) {
  if (String(key).indexOf('/user/') === 0) {
    throw new Error('This album requires a V2PH premium account. Open in WebView to upgrade.');
  }
}
function ddFor(root, dtText) {
  var dts = R_sel(root, 'dt');
  var dds = R_sel(root, 'dd');
  for (var i = 0; i < dts.length; i++) {
    if (dts[i].text().indexOf(dtText) >= 0) { return dds[i] || null; }
  }
  return null;
}
function hasNextPageEl(doc) {
  var links = R_sel(doc, 'ul.pagination li.page-item a');
  for (var i = 0; i < links.length; i++) {
    if (links[i].text() === 'Next') { return true; }
  }
  return false;
}
function parseList(doc) {
  var cards = R_sel(doc, '.albums-list .card');
  var out = [];
  for (var i = 0; i < cards.length; i++) {
    var el = cards[i];
    var link = R_selFirst(el, 'a.media-cover');
    var titleEl = R_selFirst(el, '.card-body h6 a');
    if (!link || !titleEl) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, '.card-cover img');
    out.push({ key: R_path(href), title: titleEl.text(), coverUrl: img ? img.absUrl('src') : '' });
  }
  return { mangas: out, hasNextPage: hasNextPageEl(doc) };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/category/best-quality?page=' + page, hdrs());
    return parseList($.html.parse(text));
  },

  getSearchManga: async function (page, query) {
    if (!query) {
      var t0 = await $.http.get(BASE + '/category/best-quality?page=' + page, hdrs());
      return parseList($.html.parse(t0));
    }
    var text = await $.http.get(BASE + '/search/?q=' + encodeURIComponent(query) + '&page=' + page, hdrs());
    return parseList($.html.parse(text));
  },

  getMangaDetail: async function (mangaKey) {
    checkPaywall(mangaKey);
    var text = await $.http.get(R_abs(mangaKey), hdrs());
    var doc = $.html.parse(text);
    var h1 = R_selFirst(doc, 'h1');
    var vendorDd = ddFor(doc, 'Vendor');
    var modelDd = ddFor(doc, 'Model');
    var tagsDd = ddFor(doc, 'Tags');
    var photosDd = ddFor(doc, 'Photos');
    var intro = R_selFirst(doc, '.album-intro');
    var desc = '';
    if (photosDd) { desc += 'Photos: ' + photosDd.text() + '\\n\\n'; }
    if (intro) { desc += intro.text(); }
    var genres = [];
    if (tagsDd) {
      var as = R_sel(tagsDd, 'a');
      for (var i = 0; i < as.length; i++) { genres.push(as[i].text()); }
    }
    return {
      key: mangaKey,
      title: h1 ? h1.text() : '',
      coverUrl: '',
      author: vendorDd ? vendorDd.text() : '',
      artist: modelDd ? modelDd.text() : '',
      description: desc.trim(),
      genre: genres.join(', '),
      status: 'completed',
    };
  },

  getChapterList: async function (mangaKey) {
    checkPaywall(mangaKey);
    var text = await $.http.get(R_abs(mangaKey), hdrs());
    var doc = $.html.parse(text);
    var dateDd = ddFor(doc, 'Date');
    var ts = 0;
    if (dateDd) {
      var parsed = Date.parse(dateDd.text().trim() + 'T00:00:00Z');
      if (!isNaN(parsed)) { ts = parsed; }
    }
    return [{
      key: mangaKey,
      name: 'Gallery',
      chapterNumber: 0,
      dateUpload: ts,
      pages: 0,
      sortOrder: 0,
    }];
  },

  getPageList: async function (chapterKey) {
    checkPaywall(chapterKey);
    var text = await $.http.get(R_abs(chapterKey), hdrs());
    var doc = $.html.parse(text);
    var photosDd = ddFor(doc, 'Photos');
    var photosCount = photosDd ? (parseInt(photosDd.text(), 10) || 0) : 0;
    var isGuest = !!R_selFirst(doc, "a[href*='/login'], a[href*='/register']");
    if (isGuest && photosCount > 20) {
      throw new Error('V2PH Session expired. Please log in via WebView to view more than 20 images.');
    }
    var maxPage = Math.ceil(photosCount / 10);
    var pages = [];
    var imgs = R_sel(doc, '.photos-list img');
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    for (var p = 2; p <= maxPage; p++) {
      try {
        var ptext = await $.http.get(BASE + chapterKey + '?page=' + p, hdrs());
        var pdoc = $.html.parse(ptext);
        var pimgs = R_sel(pdoc, '.photos-list img');
        for (var j = 0; j < pimgs.length; j++) {
          var u2 = pimgs[j].absUrl('src');
          if (u2) { pages.push({ index: pages.length, url: u2 }); }
        }
      } catch (e) { /* partial page */ }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
