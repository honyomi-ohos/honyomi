// Masonry theme engine (elitebabes, xarthunter, ftvhunter, ... porn-gallery sites)
// HTML-only theme; no per-extension overrides exist in the Kotlin sources.
export const runtime = 'wp';

export function extract(ctx) {
  const warnings = [];
  const config = {
    itemSelector: '.list-gallery figure',
    nextSelector: '.pagination-a li.next',
    cdnLinkSelector: '.list-gallery a[href^="https://cdn."]',
  };
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: masonry)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_selFirst)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- masonry engine ----------------
function parseList(doc) {
  var out = [];
  var galleries = R_sel(doc, '.list-gallery');
  for (var g = 0; g < galleries.length; g++) {
    if (galleries[g].attr('class').indexOf('static') >= 0) { continue; }
    var figures = R_sel(galleries[g], 'figure');
    for (var i = 0; i < figures.length; i++) {
      var fig = figures[i];
      if (R_selFirst(fig, 'a[href*="/video/"]')) { continue; }
      var link = R_selFirst(fig, 'a');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      out.push({
        key: R_path(href),
        title: link.attr('title') || link.text(),
        coverUrl: R_img(R_selFirst(fig, 'img'))
      });
    }
  }
  return out;
}

async function listManga(page, query) {
  var url;
  if (query) {
    url = BASE + '/search/post/' + encodeURIComponent(String(query).trim()) + '/mpage/' + page + '/';
  } else if (page === 1) {
    url = BASE + '/';
  } else if (page === 2) {
    url = BASE + '/archive/';
  } else {
    url = BASE + '/archive/page/' + (page - 1) + '/';
  }
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var out = parseList(doc);
  return { mangas: out, hasNextPage: !!R_selFirst(doc, CFG.nextSelector) };
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga(page, '');
  },

  getSearchManga: async function (page, query) {
    return listManga(page, query || '');
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var artist = [];
    var genre = [];
    var author = '';
    var btn = R_selFirst(doc, 'p.link-btn');
    if (btn) {
      var models = R_sel(btn, 'a[href*="/model/"]');
      for (var i = 0; i < models.length; i++) { artist.push(models[i].text()); }
      var tags = R_sel(btn, 'a[href*="/tag/"]');
      for (var j = 0; j < tags.length; j++) { genre.push(tags[j].text()); }
      var firstA = R_selFirst(btn, 'a');
      if (firstA) { author = firstA.text(); }
    }
    var descEl = R_selFirst(doc, '#content > p');
    var cover = '';
    var cdn = R_selFirst(doc, CFG.cdnLinkSelector);
    if (cdn) { cover = cdn.absUrl('href'); }
    return {
      key: mangaKey,
      title: '',
      coverUrl: cover,
      author: author,
      description: descEl ? descEl.text() : '',
      genre: genre.join(', '),
      status: 'completed'
    };
  },

  getChapterList: async function (mangaKey) {
    return [{
      key: mangaKey,
      name: 'Gallery',
      chapterNumber: -1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, '.list-gallery a[href^="https://cdn."]');
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var u = els[i].absUrl('href');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
