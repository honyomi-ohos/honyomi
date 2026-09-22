// en/mangatown (www.mangatown.com) — Jsoup scraper; multi-page chapters resolve each
// page URL to its viewer image (N requests). Several upstream selectors rely on
// :has/:containsOwn which the host engine can't express, replaced with manual filtering.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'site geo-blocked in converter region (app-promo landing page like fanfox): live probe unavailable, port untested',
      'multi-page chapters issue one request per page to resolve image URLs',
    ],
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
  var lis = R_sel(doc, 'li');
  var out = [];
  var seen = {};
  for (var i = 0; i < lis.length; i++) {
    var li = lis[i];
    if (!R_selFirst(li, 'a.manga_cover')) { continue; }
    var link = R_selFirst(li, 'p.title a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href || seen[href]) { continue; }
    seen[href] = true;
    var img = R_selFirst(li, 'img');
    out.push({ key: R_path(href), title: link.text(), coverUrl: img ? R_abs(img.attr('src')) : '' });
  }
  var hasNext = false;
  var nexts = R_sel(doc, 'a.next');
  for (var n = 0; n < nexts.length; n++) {
    var h = nexts[n].attr('href');
    if (h && h.indexOf('javascript') !== 0) { hasNext = true; break; }
  }
  return { mangas: out, hasNextPage: hasNext };
}

function parseDate(s) {
  var v = String(s || '').trim();
  if (!v) { return 0; }
  if (v.indexOf('Today') >= 0) { return Date.now(); }
  if (v.indexOf('Yesterday') >= 0) { return Date.now() - 86400000; }
  // "MMM dd,yyyy"
  var t = Date.parse(v.replace(',', ', ').replace(/\\s+/g, ' '));
  return isNaN(t) ? 0 : t;
}

function parseStatus(s) {
  var v = String(s || '').toLowerCase();
  if (v.indexOf('ongoing') >= 0) { return 'ongoing'; }
  if (v.indexOf('completed') >= 0) { return 'completed'; }
  return '';
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(BASE + '/directory/0-0-0-0-0-0/' + page + '.htm', HDRS));
  },

  getSearchManga: async function (page, query) {
    return parseList(await $.http.get(BASE + '/search?page=' + page + '&name=' + encodeURIComponent(query || ''), HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var infos = R_sel(doc, 'div.article_content');
    var info = infos.length ? infos[0] : doc;
    var title = '';
    var h1 = R_selFirst(info, 'h1');
    if (h1) { title = h1.text(); }

    // author / artist: <b>author...</b> <a>Name</a> — extract via html regex (no sibling traversal)
    var infoHtml = info.html() || '';
    var author = '';
    var artist = '';
    var am = /<b[^>]*>[^<]*author[^<]*<\\/b>\\s*<a[^>]*>([^<]*)<\\/a>/i.exec(infoHtml);
    if (am) { author = am[1]; }
    var rm = /<b[^>]*>[^<]*artist[^<]*<\\/b>\\s*<a[^>]*>([^<]*)<\\/a>/i.exec(infoHtml);
    if (rm) { artist = rm[1]; }

    // status / genre from <li><b>status...</b> ... </li>
    var status = '';
    var genres = [];
    var licensed = false;
    var ccEls = R_sel(info, 'div.chapter_content');
    for (var c = 0; c < ccEls.length; c++) {
      if ((ccEls[c].text() || '').indexOf('has been licensed') >= 0) { licensed = true; break; }
    }
    var lis = R_sel(info, 'li');
    for (var i = 0; i < lis.length; i++) {
      var li = lis[i];
      var b = R_selFirst(li, 'b');
      if (!b) { continue; }
      var bt = (b.text() || '').toLowerCase();
      if (bt.indexOf('status') >= 0) { status = parseStatus(li.text()); }
      else if (bt.indexOf('genre') >= 0) {
        var as = R_sel(li, 'a');
        for (var a = 0; a < as.length; a++) {
          var t = as[a].text();
          if (t) { genres.push(t); }
        }
      }
    }

    var desc = '';
    var show = R_selFirst(doc, 'span#show');
    if (show) { desc = (show.text() || '').replace(/HIDE$/, ''); }

    return {
      key: mangaKey,
      title: title,
      coverUrl: R_abs((R_selFirst(doc, 'div.detail_info img') || { attr: function () { return ''; } }).attr('src')),
      author: author,
      artist: artist,
      description: desc,
      genre: genres.join(', '),
      status: licensed ? 'licensed' : status
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var els = R_sel(doc, 'ul.chapter_list li');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var link = R_selFirst(el, 'a');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var nameParts = [link.text()];
      var spans = R_sel(el, 'span');
      for (var s = 0; s < spans.length; s++) {
        var cls = spans[s].attr('class') || '';
        if (cls.indexOf('time') >= 0 || cls.indexOf('new') >= 0) { continue; }
        var st = spans[s].text();
        if (st) { nameParts.push(st); }
      }
      var timeEl = R_selFirst(el, 'span.time');
      out.push({
        key: R_path(href),
        name: nameParts.join(' ').trim(),
        chapterNumber: -1,
        dateUpload: timeEl ? parseDate(timeEl.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var options = R_sel(doc, 'div.page_select option');
    var pageUrls = [];
    for (var o = 0; o < options.length; o++) {
      var t = options[o].text() || '';
      if (t.toLowerCase().indexOf('featured') >= 0) { continue; }
      var path = options[o].attr('value');
      if (!path) { continue; }
      pageUrls.push(/^https?:\\/\\//.test(path) ? path : BASE + path);
    }
    if (pageUrls.length) {
      var pages = [];
      for (var i = 0; i < pageUrls.length; i++) {
        try {
          var pDoc = $.html.parse(await $.http.get(pageUrls[i], HDRS));
          var img = R_selFirst(pDoc, 'div#viewer img');
          if (img) {
            var src = img.absUrl('src');
            if (src) { pages.push({ index: pages.length, url: src }); }
          }
        } catch (e) { /* skip broken page */ }
      }
      return pages;
    }
    var els = R_sel(doc, 'div#viewer img');
    var out = [];
    for (var v = 0; v < els.length; v++) {
      var src2 = els[v].absUrl('src');
      if (src2) { out.push({ index: out.length, url: src2 }); }
    }
    return out;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
