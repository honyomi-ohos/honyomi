// EroMuse theme engine (en: eightmuses, erofus) — nested album galleries
// The upstream source uses a persistent request stack across pages; we emulate
// the same stack with module-level state (plugin instance persists between calls).
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    topLevel: 'comics/album',
    listSel: 'a.c-tile',
    popularUrl: '/comics/album/Various-Authors',
    popularSort: ''
  };
  const am = kt.match(/override val albumSelector[^=]*=\s*"([^"]*)"/);
  if (am) {
    config.listSel = am[1].replace(/:has\([^)]*\)/g, '').replace(/:not\([^)]*\)/g, '').replace(/\[[^\]]*\]/g, '').trim();
  }
  const tm = kt.match(/override val topLevelPathSegment[^=]*=\s*"([^"]*)"/);
  if (tm) config.topLevel = tm[1];
  const pm = kt.match(/fetchPopularManga\(page: Int\): Observable<MangasPage> = fetchManga\("\$baseUrl([^"]*)", page, "([^"]*)"\)/);
  if (pm) {
    config.popularUrl = pm[1];
    config.popularSort = pm[2];
  }
  warnings.push('stack-based pagination approximated with plugin-local state; album-filter browse not supported (text search only)');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: eromuse)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var STACK = [];
var CUR = null;

var VA_ALBUMS = ['album/various-authors', 'album/fakku-comics', 'album/hentai-and-manga-english'];

function isVA(url) {
  var u = String(url).toLowerCase();
  for (var i = 0; i < VA_ALBUMS.length; i++) {
    if (u.indexOf(VA_ALBUMS[i]) >= 0) { return true; }
  }
  return false;
}

function absHref(el) {
  return el.absUrl('href') || el.attr('href') || '';
}

function tilesOf(doc) {
  var els = R_sel(doc, CFG.listSel);
  var out = [];
  for (var i = 0; i < els.length; i++) {
    if (!R_selFirst(els[i], 'img')) { continue; }
    if (R_selFirst(els[i], '.members-only')) { continue; }
    out.push(els[i]);
  }
  return out;
}

function tileToManga(el) {
  var img = R_selFirst(el, 'img');
  var cover = '';
  if (img) {
    cover = img.absUrl('data-src') || img.absUrl('src') || img.attr('data-src') || img.attr('src') || '';
  }
  return { key: R_path(absHref(el)), title: el.text(), coverUrl: cover };
}

function tilesToMangas(tiles) {
  var out = [];
  for (var i = 0; i < tiles.length; i++) { out.push(tileToManga(tiles[i])); }
  return out;
}

function setPage(url, n) {
  if (/[?&]page=\\d+/.test(url)) { return url.replace(/([?&])page=\\d+/, '$1page=' + n); }
  var m = url.match(/^(.*\\/(\\d+))(?:\\?|$)/);
  if (m) {
    var rest = url.substring(m[1].length);
    return m[1].substring(0, m[1].length - m[2].length) + n + rest;
  }
  return url + (url.indexOf('?') >= 0 ? '&' : '?') + 'page=' + n;
}

function nextUrl(doc) {
  var cur = R_selFirst(doc, '.pagination span.current');
  if (!cur) { return ''; }
  var n = parseInt(cur.text(), 10);
  if (isNaN(n)) { return ''; }
  var links = R_sel(doc, '.pagination a');
  for (var i = 0; i < links.length; i++) {
    var t = parseInt(links[i].text(), 10);
    if (t === n + 1) { return absHref(links[i]); }
  }
  return '';
}

function pushNextPage(doc, type) {
  var nu = nextUrl(doc);
  if (nu) { STACK.push({ url: nu, type: type, sort: CUR ? CUR.sort : '' }); }
}

async function fetchDoc(url) {
  var text = await $.http.get(url);
  return $.html.parse(text);
}

async function stackPop() {
  CUR = STACK.pop();
  var url = CUR.url;
  if (CUR.type === 1 && CUR.sort && url.indexOf('sort=') < 0) {
    url += (url.indexOf('?') >= 0 ? '&' : '?') + 'sort=' + CUR.sort;
  }
  return url;
}

async function internalParse(doc) {
  if (CUR.type === 0) {
    var tiles = tilesOf(doc);
    for (var i = tiles.length - 1; i >= 0; i--) {
      STACK.push({ url: absHref(tiles[i]), type: 1, sort: CUR.sort });
    }
    var url = await stackPop();
    var authorDoc = await fetchDoc(url);
    pushNextPage(authorDoc, 1);
    return tilesToMangas(tilesOf(authorDoc));
  }
  pushNextPage(doc, CUR.type);
  return tilesToMangas(tilesOf(doc));
}

async function parseManga(doc) {
  if (CUR.type === 0 || CUR.type === 2) { pushNextPage(doc, CUR.type); }
  if (CUR.type === 0) {
    var tiles = tilesOf(doc);
    for (var i = tiles.length - 1; i >= 0; i--) {
      STACK.push({ url: absHref(tiles[i]), type: 1, sort: CUR.sort });
    }
    return await internalParse(doc);
  }
  if (CUR.type === 1) {
    return await internalParse(doc);
  }
  if (CUR.type === 2) {
    var mangas = [];
    var els = tilesOf(doc);
    var prefix = BASE + '/' + CFG.topLevel + '/';
    for (var j = 0; j < els.length; j++) {
      var url = absHref(els[j]);
      var rest = url.indexOf(prefix) === 0 ? url.substring(prefix.length).split('?')[0] : url;
      var depth = rest.split('/').length;
      if (isVA(url)) {
        if (depth === 1) {
          STACK.push({ url: url, type: 0, sort: CUR.sort });
          if (mangas.length === 0) { mangas = mangas.concat(await internalParse(await fetchDoc(await stackPop()))); }
        } else if (depth === 2) {
          STACK.push({ url: url, type: 1, sort: CUR.sort });
          if (mangas.length === 0) { mangas = mangas.concat(await internalParse(await fetchDoc(await stackPop()))); }
        } else {
          mangas.push(tileToManga(els[j]));
        }
      } else {
        if (depth === 1) {
          STACK.push({ url: url, type: 1, sort: CUR.sort });
          if (mangas.length === 0) { mangas = mangas.concat(await internalParse(await fetchDoc(await stackPop()))); }
        } else {
          mangas.push(tileToManga(els[j]));
        }
      }
    }
    return mangas;
  }
  return [];
}

async function stackFetch(page, query) {
  if (page === 1) {
    STACK = [];
    if (query) {
      STACK.push({ url: BASE + '/search?q=' + encodeURIComponent(query) + '&page=1', type: 2, sort: '' });
    } else {
      STACK.push({ url: BASE + CFG.popularUrl, type: 0, sort: CFG.popularSort });
    }
  }
  if (STACK.length === 0) { return { mangas: [], hasNextPage: false }; }
  var url = await stackPop();
  var doc = await fetchDoc(url);
  var mangas = await parseManga(doc);
  return { mangas: mangas, hasNextPage: STACK.length > 0 };
}

function chapterTiles(doc) {
  var els = R_sel(doc, 'a.c-tile');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var href = absHref(els[i]);
    if (href.indexOf('/comics/album/') >= 0 && R_selFirst(els[i], 'img')) { out.push(els[i]); }
  }
  if (out.length === 0 && CFG.listSel !== 'a.c-tile') {
    var alt = R_sel(doc, CFG.listSel);
    for (var k = 0; k < alt.length; k++) {
      var h = absHref(alt[k]);
      if (h.indexOf('/comics/album/') >= 0 && R_selFirst(alt[k], 'img')) { out.push(alt[k]); }
    }
  }
  return out;
}

function pictureImgs(doc) {
  var els = R_sel(doc, 'a.c-tile');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var href = absHref(els[i]);
    if (href.indexOf('/comics/picture/') >= 0) {
      var img = R_selFirst(els[i], 'img');
      if (img) { out.push(img); }
    }
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    return stackFetch(page, '');
  },

  getSearchManga: async function (page, query) {
    return stackFetch(page, query);
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await fetchDoc(R_abs(mangaKey));
    var tiles = tilesOf(doc);
    var cover = '';
    if (tiles.length > 0) {
      var img = R_selFirst(tiles[0], 'img');
      if (img) { cover = img.absUrl('data-src') || img.absUrl('src') || img.attr('data-src') || img.attr('src') || ''; }
    }
    var crumb = R_sel(doc, 'div.top-menu-breadcrumb li');
    var author = '';
    var title = '';
    if (crumb.length >= 2) {
      author = crumb[isVA(R_abs(mangaKey)) ? 2 : 1].text();
      title = crumb[crumb.length - 1].text();
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: author,
      description: '',
      genre: '',
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var out = [];
    var url = R_abs(mangaKey);
    var guard = 0;
    while (url && guard < 20) {
      guard++;
      var doc = await fetchDoc(url);
      var tiles = chapterTiles(doc);
      for (var i = 0; i < tiles.length; i++) {
        out.push({
          key: R_path(absHref(tiles[i])),
          name: tiles[i].text(),
          chapterNumber: 0,
          dateUpload: 0,
          pages: 0,
          sortOrder: 0
        });
      }
      if (guard === 1 && pictureImgs(doc).length > 0) {
        out.push({ key: R_path(mangaKey), name: 'Chapter', chapterNumber: 0, dateUpload: 0, pages: 0, sortOrder: 0 });
      }
      url = nextUrl(doc);
    }
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var pages = [];
    var queue = [R_abs(chapterKey)];
    var guard = 0;
    while (queue.length > 0 && guard < 60) {
      guard++;
      var url = queue.shift();
      var doc = await fetchDoc(url);
      var tiles = chapterTiles(doc);
      for (var i = 0; i < tiles.length; i++) { queue.push(absHref(tiles[i])); }
      var imgs = pictureImgs(doc);
      for (var j = 0; j < imgs.length; j++) {
        var u = imgs[j].absUrl('data-src') || imgs[j].absUrl('src') || imgs[j].attr('data-src') || imgs[j].attr('src') || '';
        u = String(u).replace('/th/', '/fl/');
        if (u) { pages.push({ index: pages.length, url: u }); }
      }
      var nu = nextUrl(doc);
      if (nu) { queue.push(nu); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
