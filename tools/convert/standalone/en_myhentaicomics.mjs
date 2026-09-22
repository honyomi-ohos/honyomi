// en/myhentaicomics (myhentaicomics.com) — NSFW gallery listing, single-chapter comics
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['sort/category filters not ported; text search only'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};

function encSpaces(u) {
  return String(u || '').replace(/ /g, '%20');
}

function parseList(text) {
  var doc = $.html.parse(text);
  var els = R_sel(doc, 'li.item:not(.image-block) .comic-inner a');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var href = el.absUrl('href');
    var nameEl = R_selFirst(el, 'h2.comic-name');
    if (!href || !nameEl) { continue; }
    var img = R_selFirst(el, 'img');
    out.push({ key: R_path(href), title: nameEl.text(), coverUrl: img ? encSpaces(img.absUrl('src')) : '' });
  }
  var hasNext = !!R_selFirst(doc, 'li.next a');
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(BASE + '/views/' + page, {}));
  },

  getSearchManga: async function (page, query) {
    return parseList(await $.http.get(BASE + '/search/' + page + '?query=' + encodeURIComponent(query || ''), {}));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), {}));
    var descDiv = R_selFirst(doc, 'div.comic-description');
    var cats = [], artists = [], groups = [], pagesText = '';
    if (descDiv) {
      var cas = R_sel(descDiv, "a[href*='/gallery/category/']");
      for (var c = 0; c < cas.length; c++) { cats.push(cas[c].text()); }
      var aas = R_sel(descDiv, "a[href*='/gallery/artist/']");
      for (var a = 0; a < aas.length; a++) { artists.push(aas[a].text()); }
      var gas = R_sel(descDiv, "a[href*='/gallery/group/']");
      for (var g = 0; g < gas.length; g++) { groups.push(gas[g].text()); }
      var divs = R_sel(descDiv, 'div');
      for (var d = 0; d < divs.length; d++) {
        if ((divs[d].text() || '').indexOf('Pages:') === 0) { pagesText = divs[d].text(); break; }
      }
    }
    var h1 = descDiv ? R_selFirst(descDiv, 'h1') : null;
    var cover = R_selFirst(doc, 'div.comic-cover img');
    var desc = '';
    if (artists.length) { desc += 'Artists: ' + artists.join(', ') + '\\n'; }
    if (groups.length) { desc += 'Groups: ' + groups.join(', ') + '\\n'; }
    if (pagesText) { desc += pagesText; }
    return {
      key: mangaKey,
      title: h1 ? h1.text() : '',
      coverUrl: cover ? encSpaces(cover.absUrl('src')) : '',
      author: artists.join(', '),
      description: desc.trim(),
      genre: cats.concat(artists).concat(groups).join(', '),
      status: 'completed'
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), {}));
    var a = R_selFirst(doc, 'div.comic-cover a');
    if (!a) { return []; }
    var href = a.absUrl('href');
    if (!href) { return []; }
    var id = href.split('/gallery/show/')[1];
    if (!id) { return []; }
    id = id.split('/')[0];
    return [{
      key: '/gallery/show/' + id + '/1',
      name: 'Chapter 1',
      chapterNumber: 1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var comicId = chapterKey.split('/gallery/show/')[1];
    if (comicId) { comicId = comicId.split('/')[0]; }
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), {}));
    var img = R_selFirst(doc, 'ul.gallery-slide li img');
    if (!img) { return []; }
    var imageUrl = img.absUrl('src');
    if (!imageUrl) { return []; }
    var imageBase = imageUrl.substring(0, imageUrl.lastIndexOf('/') + 1);
    var fileName = imageUrl.substring(imageUrl.lastIndexOf('/') + 1);
    var ext = fileName.substring(fileName.indexOf('.') + 1);
    var els = R_sel(doc, "ul li a[href*='/gallery/show/" + comicId + "/']");
    var totalPages = 1;
    for (var i = 0; i < els.length; i++) {
      var n = parseInt(els[i].attr('href').split('/').pop(), 10);
      if (!isNaN(n) && n > totalPages) { totalPages = n; }
    }
    var out = [];
    for (var p = 1; p <= totalPages; p++) {
      var padded = '' + p;
      while (padded.length < 3) { padded = '0' + padded; }
      out.push({ index: p - 1, url: encSpaces(imageBase + padded + '.' + ext) });
    }
    return out;
  },

  imageHeaders: function () {
    return {};
  }
};
`;
}
