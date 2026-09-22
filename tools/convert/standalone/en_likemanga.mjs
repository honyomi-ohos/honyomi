// en/likemanga — bespoke scraper (searchadvance query + ajax chapter pagination + token pages)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['chapter pagination via ajax replicated; token-based page images decoded from base64 JWT payload'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function searchUrl(page, query) {
  var u = BASE + '?act=searchadvance&f[sortby]=top-manga';
  if (query) { u += '&f[keyword]=' + encodeURIComponent(query.trim()); }
  if (page > 1) { u += '&pageNum=' + page; }
  return u;
}

function parseList(text) {
  var doc = $.html.parse(text);
  var items = R_sel(doc, 'div.card-body div.card');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = R_selFirst(el, 'a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var t = R_selFirst(el, '.title-manga');
    out.push({ key: R_path(href), title: t ? t.text() : link.text(), coverUrl: R_img(R_selFirst(el, 'img')) });
  }
  var hasNext = false;
  var pager = R_sel(doc, 'ul.pagination a');
  for (var j = 0; j < pager.length; j++) {
    var tx = pager[j].text();
    if (tx.indexOf('\\u00bb') >= 0 || tx.indexOf('»') >= 0) { hasNext = true; }
  }
  return { mangas: out, hasNextPage: hasNext };
}

function statusMap(s) {
  var v = String(s || '').toLowerCase();
  if (v.indexOf('complete') >= 0) { return 'completed'; }
  if (v.indexOf('in process') >= 0) { return 'ongoing'; }
  if (v.indexOf('pause') >= 0) { return 'hiatus'; }
  return '';
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(searchUrl(page, ''), HDRS);
    return parseList(text);
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(searchUrl(page, query), HDRS);
    return parseList(text);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var author = '';
    var authorEl = R_selFirst(doc, '.list-info .author p:nth-child(2)');
    if (authorEl) {
      var at = authorEl.text().trim();
      if (at && at !== 'Updating') { author = at; }
    }
    var genres = [];
    var gels = R_sel(doc, '.list-info a[href*="/genres/"]');
    for (var i = 0; i < gels.length; i++) { genres.push(gels[i].text()); }
    var statusEl = R_selFirst(doc, '.list-info .status p:nth-child(2)');
    return {
      key: mangaKey,
      title: (R_selFirst(doc, '#title-detail-manga') || { text: function () { return ''; } }).text(),
      coverUrl: R_img(R_selFirst(doc, '.detail-info img')),
      author: author,
      description: (R_selFirst(doc, '#summary_shortened') || { text: function () { return ''; } }).text(),
      genre: genres.join(', '),
      status: statusMap(statusEl ? statusEl.text() : '')
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var chapters = [];
    function pushFrom(container) {
      var items = R_sel(container, '.wp-manga-chapter');
      for (var i = 0; i < items.length; i++) {
        var el = items[i];
        var link = R_selFirst(el, 'a');
        if (!link) { continue; }
        var href = link.absUrl('href');
        if (!href) { continue; }
        var dateEl = R_selFirst(el, '.chapter-release-date');
        chapters.push({
          key: R_path(href),
          name: link.text(),
          chapterNumber: -1,
          dateUpload: dateEl ? R_date(dateEl.text()) : 0,
          pages: 0,
          sortOrder: 0
        });
      }
    }
    pushFrom(doc);
    // ajax chapter pagination
    var pageLinks = R_sel(doc, 'div.chapters_pagination a:not(.next)');
    var lastPage = 0;
    if (pageLinks.length > 0) {
      var onclick = pageLinks[pageLinks.length - 1].attr('onclick');
      var m = /load_list_chapter\\((\\d+)\\)/.exec(onclick || '');
      if (m) { lastPage = parseInt(m[1], 10); }
    }
    var idEl = R_selFirst(doc, '#title-detail-manga');
    var mangaId = idEl ? parseInt(idEl.attr('data-manga'), 10) : NaN;
    if (lastPage > 1 && !isNaN(mangaId)) {
      for (var p = 2; p <= lastPage; p++) {
        try {
          var ajaxUrl = BASE + '?act=ajax&code=load_list_chapter&manga_id=' + mangaId + '&page_num=' + p + '&chap_id=0&keyword=';
          var ajaxText = await $.http.get(ajaxUrl, HDRS);
          var data = $.json.parse(ajaxText);
          var frag = $.html.parse(String((data && data.list_chap) || ''));
          pushFrom(frag);
        } catch (e) { /* stop paginating on error */ }
      }
    }
    chapters.reverse();
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), HDRS);
    var doc = $.html.parse(text);
    var tokenEl = R_selFirst(doc, 'div.reading input#next_img_token');
    if (tokenEl) {
      var cdnEl = R_selFirst(doc, 'div.reading #currentlink');
      var cdn = cdnEl ? cdnEl.attr('value') : '';
      var parts = String(tokenEl.attr('value') || '').split('.');
      var payload = null;
      try { payload = $.json.parse($.crypto.base64Decode(parts[1])); } catch (e) { payload = null; }
      if (cdn && payload && payload.data) {
        var imgArray = $.json.parse($.crypto.base64Decode(payload.data));
        var pages = [];
        for (var i = 0; i < imgArray.length; i++) {
          pages.push({ index: i, url: cdn + '/' + imgArray[i] });
        }
        return pages;
      }
    }
    var imgs = R_sel(doc, 'div.reading-detail.box_doc img');
    var pages2 = [];
    for (var k = 0; k < imgs.length; k++) {
      var u = R_img(imgs[k]);
      if (u) { pages2.push({ index: pages2.length, url: u }); }
    }
    return pages2;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
