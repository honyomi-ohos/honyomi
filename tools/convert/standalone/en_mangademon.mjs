// en/mangademon — simple Jsoup scraper (advanced.php / search.php / chplinks)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['encoded href handling simplified to raw paths; filters not ported'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function hasNext(doc) {
  var pager = R_sel(doc, 'div.pagination > ul > a > li');
  for (var i = 0; i < pager.length; i++) {
    if (/next/i.test(pager[i].text())) { return true; }
  }
  return false;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/advanced.php?list=' + page + '&status=all&orderby=' + encodeURIComponent('VIEWS DESC'), HDRS);
    var doc = $.html.parse(text);
    var els = R_sel(doc, 'div#advanced-content > div.advanced-element');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var link = R_selFirst(el, 'a');
      var h1 = R_selFirst(el, 'h1');
      if (!link || !h1) { continue; }
      out.push({
        key: R_path(link.absUrl('href')),
        title: R_ownText(h1).split('\\n')[0].trim(),
        coverUrl: R_img(R_selFirst(el, 'img'))
      });
    }
    return { mangas: out, hasNextPage: hasNext(doc) };
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/search.php?manga=' + encodeURIComponent(query || ''), HDRS);
    var doc = $.html.parse(text);
    var els = R_sel(doc, 'body > a[href]');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var titleEl = R_selFirst(el, 'div.seach-right > div');
      var img = R_selFirst(el, 'img');
      if (!titleEl) { continue; }
      out.push({
        key: R_path(el.absUrl('href')),
        title: R_ownText(titleEl),
        coverUrl: img ? R_img(img) : ''
      });
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var root = R_selFirst(doc, 'div#manga-info-container');
    var title = '', cover = '', desc = '', author = '', status = '';
    var genres = [];
    if (root) {
      var tEl = R_selFirst(root, 'h1.big-fat-titles');
      title = tEl ? R_ownText(tEl) : '';
      cover = R_img(R_selFirst(root, 'div#manga-page img'));
      var lis = R_sel(root, 'div.genres-list > li');
      for (var i = 0; i < lis.length; i++) { genres.push(lis[i].text()); }
      var dEl = R_selFirst(root, 'div#manga-info-rightColumn > div > div.white-font');
      desc = dEl ? dEl.text() : '';
      var stats = R_sel(root, 'div#manga-info-stats > div');
      for (var j = 0; j < stats.length; j++) {
        var lis2 = R_sel(stats[j], 'li');
        if (lis2.length < 2) { continue; }
        var label = lis2[0].text().toLowerCase();
        var value = lis2[1].text();
        if (label.indexOf('author') >= 0) {
          if (value.toLowerCase().indexOf('updating') < 0) { author = value; }
        } else if (label.indexOf('status') >= 0) {
          if (value.toLowerCase().indexOf('ongoing') >= 0) { status = 'ongoing'; }
          else if (value.toLowerCase().indexOf('completed') >= 0) { status = 'completed'; }
        }
      }
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: author,
      description: desc,
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var els = R_sel(doc, 'div#chapters-list a.chplinks');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var href = el.absUrl('href');
      if (!href) { continue; }
      var u;
      try { u = new URL(href, BASE); } catch (e) { continue; }
      var dateEl = R_selFirst(el, 'span');
      out.push({
        key: u.pathname + u.search,
        name: R_ownText(el),
        chapterNumber: -1,
        dateUpload: dateEl ? (Date.parse(R_ownText(dateEl)) || 0) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // newest first -> oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), HDRS);
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, 'img.imgholder');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = R_img(imgs[i]);
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
