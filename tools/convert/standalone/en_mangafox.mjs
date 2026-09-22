// en/mangafox — fanfox-style directory scraper; pages via mobile site (roll_manga)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['page images fetched from mobile site with readway=2 cookie (all pages at once); filters not ported'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var MOBILE = BASE.replace('://', '://m.');
var HDRS = { Referer: BASE + '/', Cookie: 'isAdult=1' };
var MOBILE_HDRS = { Referer: MOBILE + '/', Cookie: 'readway=2; isAdult=1' };

function parseList(doc, itemSel) {
  var els = R_sel(doc, itemSel);
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var link = R_selFirst(el, 'a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var title = link.attr('title') || link.text();
    out.push({ key: R_path(href), title: title, coverUrl: R_img(R_selFirst(el, 'img')) });
  }
  var hasNext = !!R_selFirst(doc, '.pager-list-left a.active + a + a');
  return { mangas: out, hasNextPage: hasNext };
}

function parseDate(s) {
  var v = String(s || '').trim();
  if (!v) { return 0; }
  if (v.indexOf('Today') >= 0 || v.indexOf('ago') >= 0) {
    return Date.now() - Date.now() % 86400000;
  }
  if (v.indexOf('Yesterday') >= 0) {
    return Date.now() - Date.now() % 86400000 - 86400000;
  }
  return Date.parse(v) || 0;
}

module.exports = {
  getPopularManga: async function (page) {
    var u = page === 1 ? BASE + '/directory/' : BASE + '/directory/' + page + '.html';
    return parseList($.html.parse(await $.http.get(u, HDRS)), 'ul.manga-list-1-list li');
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/search?title=' + encodeURIComponent(query || '') + '&sort=&stype=1';
    return parseList($.html.parse(await $.http.get(u, HDRS)), 'ul.manga-list-4-list li');
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var right = R_selFirst(doc, '.detail-info-right');
    var authors = [], genres = [];
    if (right) {
      var aels = R_sel(right, '.detail-info-right-say a');
      for (var i = 0; i < aels.length; i++) { authors.push(aels[i].text()); }
      var gels = R_sel(right, '.detail-info-right-tag-list a');
      for (var j = 0; j < gels.length; j++) { genres.push(gels[j].text()); }
    }
    var statusEl = right ? R_selFirst(right, '.detail-info-right-title-tip') : null;
    var status = '';
    if (statusEl) {
      var st = statusEl.text();
      if (st.indexOf('Ongoing') >= 0) { status = 'ongoing'; }
      else if (st.indexOf('Completed') >= 0) { status = 'completed'; }
    }
    return {
      key: mangaKey,
      title: (R_selFirst(doc, '.detail-info-right-title') || { text: function () { return ''; } }).text(),
      coverUrl: R_img(R_selFirst(doc, '.detail-info-cover-img')),
      author: authors.join(', '),
      description: (R_selFirst(doc, 'p.fullcontent') || { text: function () { return ''; } }).text(),
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var els = R_sel(doc, 'ul.detail-main-list li a');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var href = el.absUrl('href');
      if (!href) { continue; }
      var ps = R_sel(el, '.detail-main-list-main p');
      var nm = ps.length ? ps[0].text() : el.text();
      var date = ps.length > 1 ? parseDate(ps[ps.length - 1].text()) : 0;
      out.push({ key: R_path(href), name: nm, chapterNumber: -1, dateUpload: date, pages: 0, sortOrder: 0 });
    }
    // newest first -> oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var path = chapterKey.replace('/manga/', '/roll_manga/');
    var text = await $.http.get(MOBILE + path, MOBILE_HDRS);
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, '#viewer img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = R_abs(imgs[i].attr('data-original'));
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/', Cookie: 'isAdult=1' };
  }
};
`;
}
