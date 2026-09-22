// en/mangareadercc (mangareader.cc, "MangaReaderIN") — chapter list requires a two-step
// flow: scrape mangaID from the detail page script, then fetch /ajax-list-chapter?mangaID=.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['genre/order filters not ported; text search only', 'site currently serves Cloudflare 526 (broken origin cert) on every URL — live probe unavailable, port untested'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

// div.anipost items; the link anchor is the one containing an <h3>
function parseList(text) {
  var doc = $.html.parse(text);
  var els = R_sel(doc, 'div.anipost');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var anchors = R_sel(el, 'a');
    var link = null;
    for (var a = 0; a < anchors.length; a++) {
      if ((anchors[a].html() || '').indexOf('<h3') >= 0) { link = anchors[a]; break; }
    }
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, 'img');
    out.push({
      key: new URL(href, BASE).pathname + new URL(href, BASE).search,
      title: link.text(),
      coverUrl: img ? R_abs(img.attr('src')) : ''
    });
  }
  var hasNext = !!R_selFirst(doc, 'a[rel=next]');
  return { mangas: out, hasNextPage: hasNext };
}

function parseStatusText(s) {
  var v = String(s || '');
  if (v.toLowerCase().indexOf('ongoing') >= 0) { return 'ongoing'; }
  if (v.toLowerCase().indexOf('completed') >= 0) { return 'completed'; }
  return '';
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(BASE + '/popular-manga?page=' + page, HDRS));
  },

  getSearchManga: async function (page, query) {
    if (query && query.trim()) {
      return parseList(await $.http.get(BASE + '/search?s=' + encodeURIComponent(query.trim()) + '&post_type=manga&page=' + page, HDRS));
    }
    return parseList(await $.http.get(BASE + '/popular-manga?page=' + page, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var author = '', artist = '', genre = '', status = '';
    var lis = R_sel(doc, '.listinfo li');
    for (var i = 0; i < lis.length; i++) {
      var t = lis[i].text();
      if (t.indexOf('Author') === 0) { author = t.substring(t.indexOf(':') + 1).trim(); }
      else if (t.indexOf('Artist') === 0) { artist = t.substring(t.indexOf(':') + 1).trim().replace(/;/g, ','); }
      else if (t.indexOf('Genre') === 0) { genre = t.substring(t.indexOf(':') + 1).trim().replace(/;/g, ','); }
      else if (t.indexOf('Status') === 0) { status = parseStatusText(t.substring(t.indexOf(':') + 1)); }
    }
    var descParts = [];
    var descEls = R_sel(doc, '#noidungm');
    for (var d = 0; d < descEls.length; d++) { descParts.push(descEls[d].text()); }
    return {
      key: mangaKey,
      title: (R_selFirst(doc, '.animeinfo .rm h1') || { text: function () { return ''; } }).text(),
      coverUrl: R_abs((R_selFirst(doc, '.animeinfo .lm img') || { attr: function () { return ''; } }).attr('src')),
      author: author,
      artist: artist,
      description: descParts.join('\\n'),
      genre: genre,
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var html = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(html);
    var mangaId = '';
    var scripts = R_sel(doc, 'script');
    for (var s = 0; s < scripts.length; s++) {
      var h = scripts[s].html ? scripts[s].html() : '';
      if (h.indexOf('var mangaID') >= 0) {
        var m = /var mangaID = '([^']*)'/.exec(h);
        if (m) { mangaId = m[1]; break; }
      }
    }
    if (!mangaId) { return []; }
    var titleEl = R_selFirst(doc, 'div.manga-detail h1');
    var mangaTitle = titleEl ? titleEl.text() : '';
    var listDoc = $.html.parse(await $.http.get(BASE + '/ajax-list-chapter?mangaID=' + encodeURIComponent(mangaId), HDRS));
    var els = R_sel(listDoc, 'li');
    var out = [];
    var seen = {};
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var leftoff = R_selFirst(el, '.leftoff');
      if (!leftoff) { continue; }
      var a = R_selFirst(leftoff, 'a');
      if (!a) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      var key = new URL(href, BASE).pathname + new URL(href, BASE).search;
      if (seen[key]) { continue; }
      seen[key] = true;
      var name = leftoff.text();
      if (mangaTitle && name.indexOf(mangaTitle + ' ') === 0) { name = name.substring(mangaTitle.length + 1); }
      var dateEl = R_selFirst(el, '.rightoff');
      out.push({
        key: key,
        name: name,
        chapterNumber: -1,
        dateUpload: dateEl ? (R_date(dateEl.text()) || 0) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // ajax list is newest-first; contract wants oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var el = R_selFirst(doc, '#arraydata');
    if (!el) { return []; }
    var t = el.text();
    if (!t) { return []; }
    var urls = t.split(',');
    var out = [];
    for (var i = 0; i < urls.length; i++) {
      var u = urls[i].trim();
      if (u) { out.push({ index: out.length, url: u }); }
    }
    return out;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
