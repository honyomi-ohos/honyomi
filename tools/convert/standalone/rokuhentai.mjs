// all/rokuhentai — bespoke engine (stateful offset pagination, derived image URLs)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['thumbnail-image preference approximated to original images; reader mode (top-to-bottom) fixed'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };
var IMG_RE = /background-image:\\s*url\\("(.+?)"\\);/;
var popularOffset = null;
var searchOffsets = {};

function idOf(url) {
  return String(url).substring(String(url).lastIndexOf('/') + 1).split('#')[0];
}
function parseMangaCard(e) {
  var infoEl = R_selFirst(e, '.mdc-typography--caption:last-child');
  if (!infoEl) { return null; }
  var info = infoEl.text().split(' images ');
  var count = parseInt(info[0], 10);
  var dateMs = info.length > 1 ? R_date(info[1]) : 0;
  var href = e.absUrl('href') || (R_selFirst(e, 'a') ? R_selFirst(e, 'a').absUrl('href') : '');
  if (!href || isNaN(count)) { return null; }
  var url = href.substring(0, href.lastIndexOf('/'));
  var titleEl = R_selFirst(e, '.site-manga-card__title--primary');
  var mediaEl = R_selFirst(e, '.mdc-card__media');
  var thumb = '';
  if (mediaEl) {
    var m = mediaEl.attr('style').match(IMG_RE);
    if (m) { thumb = m[1]; }
  }
  return {
    key: R_path(url) + '#' + count + ',' + dateMs,
    title: titleEl ? titleEl.text() : '',
    coverUrl: thumb,
  };
}
function rememberOffset(mangas, query) {
  if (mangas.length === 0) { return; }
  var lastId = idOf(mangas[mangas.length - 1].key);
  if (query !== undefined) {
    searchOffsets['search:' + query] = lastId;
  } else {
    popularOffset = lastId;
  }
}
async function listPage(url, query) {
  var text = await $.http.get(url, HDRS);
  var mangas = [];
  if (/^\\s*[\\{\\[]/.test(text)) {
    var j = JSON.parse(text);
    var cards = j.mangaCards || [];
    for (var i = 0; i < cards.length; i++) {
      var doc = $.html.parse('<html><body>' + cards[i] + '</body></html>');
      var slot = R_selFirst(doc, '.site-popunder-ad-slot');
      if (!slot) { continue; }
      var manga = parseMangaCard(slot);
      if (manga) { mangas.push(manga); }
    }
  } else {
    var doc2 = $.html.parse(text);
    var slots = R_sel(doc2, '.site-popunder-ad-slot');
    for (var k = 0; k < slots.length; k++) {
      var m2 = parseMangaCard(slots[k]);
      if (m2) { mangas.push(m2); }
    }
  }
  rememberOffset(mangas, query);
  return { mangas: mangas, hasNextPage: mangas.length > 0 };
}
function parseKey(key) {
  var km = String(key).match(/^\\/([^/#]+)#([^,]+),?(\\d*)/);
  if (km) { return { id: km[1], count: parseInt(km[2], 10) || 0, date: parseInt(km[3], 10) || 0 }; }
  var bare = String(key).replace(/^\\//, '').split('#')[0];
  return { id: bare, count: 0, date: 0 };
}

module.exports = {
  getPopularManga: async function (page) {
    if (page === 1 || popularOffset === null) {
      return listPage(BASE, undefined);
    }
    return listPage(BASE + '/_search?p=' + popularOffset, undefined);
  },

  getSearchManga: async function (page, query) {
    var off = searchOffsets['search:' + query];
    if (page === 1 || off === undefined) {
      return listPage(BASE + '?q=' + encodeURIComponent(query), query);
    }
    return listPage(BASE + '/_search?p=' + off + '&q=' + encodeURIComponent(query), query);
  },

  getMangaDetail: async function (mangaKey) {
    var info = parseKey(mangaKey);
    var text = await $.http.get(BASE + '/' + info.id, HDRS);
    var doc = $.html.parse(text);
    var thumb = '';
    var mediaEl = R_selFirst(doc, '.site-manga-info .mdc-card__media');
    if (mediaEl) {
      var m = mediaEl.attr('style').match(IMG_RE);
      if (m) { thumb = m[1]; }
    }
    var titles = R_sel(doc, '.site-manga-info__info h6');
    var author = '';
    var genre = [];
    var chips = R_sel(doc, '.mdc-chip');
    for (var i = 0; i < chips.length; i++) {
      var parts = chips[i].text().split(': ');
      if (parts[0] === 'artist') { author = parts[1]; }
      if (parts.length > 1 && parts[1].indexOf(' ') >= 0) {
        genre.push(parts[0] + ': "' + parts[1] + '"');
      } else {
        genre.push(chips[i].text());
      }
    }
    return {
      key: mangaKey,
      title: titles.length > 0 ? titles[0].text() : info.id,
      coverUrl: thumb,
      author: author,
      description: titles.length > 1 ? titles[1].text() : '',
      genre: genre.join(', '),
      status: 'completed',
    };
  },

  getChapterList: async function (mangaKey) {
    var info = parseKey(mangaKey);
    var title = info.id;
    var count = info.count;
    try {
      var detail = await module.exports.getMangaDetail(mangaKey);
      title = detail.title;
    } catch (e) { /* keep id as title */ }
    if (!count) {
      // cover-image style attr also encodes nothing; try reading count from details page card
      try {
        var text = await $.http.get(BASE + '/' + info.id, HDRS);
        var m = text.match(/(\\d+)\\s+images/);
        if (m) { count = parseInt(m[1], 10); }
      } catch (e2) { /* ignore */ }
    }
    return [{
      key: '/' + info.id,
      name: title,
      chapterNumber: 0,
      dateUpload: info.date,
      pages: count,
      sortOrder: 0,
    }];
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).replace(/^\\//, '').split('#')[0];
    var text = await $.http.get(BASE + '/' + id, HDRS);
    var m = text.match(/(\\d+)\\s+images/);
    var count = m ? parseInt(m[1], 10) : 0;
    var pages = [];
    for (var i = 0; i < count; i++) {
      pages.push({ index: i, url: BASE + '/_images/pages/' + id + '/' + i + '.jpg' });
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  },
};
`;
}
