// en/mangarawclub (mangarawclub.com / mgeko) — browse list via JSON endpoint returning
// an HTML fragment; search via /search/ page; chapter list at {mangaUrl}all-chapters/.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['filters not ported (text search via /search/ only); safe_mode preference not ported (NSFW shown)'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function parseComicCards(html) {
  var doc = $.html.parse(html);
  var els = R_sel(doc, '.comic-card');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var titleEl = R_selFirst(el, '.comic-card__title a');
    var link = R_selFirst(el, 'a');
    if (!titleEl || !link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, '.comic-card__cover img');
    out.push({ key: R_path(href), title: titleEl.text(), coverUrl: img ? (R_img(img)) : '' });
  }
  return out;
}

function parseSearchPage(text) {
  var doc = $.html.parse(text);
  var els = R_sel(doc, '.novel-item');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var titleEl = R_selFirst(el, '.novel-title');
    var link = R_selFirst(el, 'a');
    if (!titleEl || !link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, '.novel-cover img');
    out.push({ key: R_path(href), title: titleEl.text(), coverUrl: img ? R_img(img) : '' });
  }
  var hasNext = false;
  var pageLinks = R_sel(doc, 'nav.paging a');
  for (var j = 0; j < pageLinks.length; j++) {
    if ((pageLinks[j].text() || '').indexOf('Next') >= 0) { hasNext = true; break; }
  }
  return { mangas: out, hasNextPage: hasNext };
}

function capWords(s) {
  return String(s || '').split(' ').map(function (w) {
    return w.toLowerCase().replace(/^./, function (c) { return c.toUpperCase(); });
  }).join(' ');
}

function parseAltNames(raw) {
  if (!raw) { return null; }
  var parts = String(raw).split(/[,;\\u2022]/).map(function (s) { return s.trim(); })
    .filter(function (s) { return s && s.toLowerCase() !== 'updating'; });
  return parts.length ? parts : null;
}

function parseChapterDate(s) {
  if (!s) { return 0; }
  var v = String(s).replace(/\\./g, '').replace('Sept', 'Sep');
  var t = Date.parse(v);
  if (!isNaN(t)) { return t; }
  // "MMMM dd, yyyy, h a" (no minutes) — drop ", h a" tail: try cutting at 2nd comma
  var first = v.indexOf(',');
  if (first >= 0) {
    var head = v.substring(0, first);
    var t2 = Date.parse(head);
    if (!isNaN(t2)) { return t2; }
  }
  return R_date(v) || 0;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/browse-comics/data/?page=' + page + '&sort=popular_all_time&safe_mode=0', HDRS);
    var data = $.json.parse(text);
    return { mangas: parseComicCards(data.results_html || ''), hasNextPage: (data.page || 0) < (data.num_pages || 0) };
  },

  getSearchManga: async function (page, query) {
    if (query && query.trim()) {
      return parseSearchPage(await $.http.get(BASE + '/search/?search=' + encodeURIComponent(query.trim()) + '&results=' + page, HDRS));
    }
    var text = await $.http.get(BASE + '/browse-comics/data/?page=' + page + '&sort=latest&safe_mode=0', HDRS);
    var data = $.json.parse(text);
    return { mangas: parseComicCards(data.results_html || ''), hasNextPage: (data.page || 0) < (data.num_pages || 0) };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    if (!R_selFirst(doc, '.novel-header')) { throw new Error('Page not found'); }
    var desc = '';
    var descEl = R_selFirst(doc, '.description');
    if (descEl) {
      var t = descEl.text();
      var idx = t.indexOf('Summary is');
      desc = idx >= 0 ? t.substring(idx + 'Summary is'.length) : t;
    }
    var altNames = parseAltNames(R_ownText(R_selFirst(doc, '.alternative-title')));
    if (altNames) {
      desc += (desc ? '\\n\\n' : '') + 'Alternative Names:';
      for (var a = 0; a < altNames.length; a++) { desc += '\\n- ' + altNames[a]; }
    }
    var authorEl = R_selFirst(doc, '.author a');
    var author = '';
    if (authorEl) {
      author = (authorEl.attr('title') || '').trim();
      if (author.toLowerCase() === 'updating') { author = ''; }
    }
    var genres = [];
    var gels = R_sel(doc, '.categories a[href*=genre]');
    for (var i = 0; i < gels.length; i++) { genres.push(capWords(R_ownText(gels[i]))); }
    var status = '';
    if (R_selFirst(doc, 'div.header-stats strong.completed')) { status = 'completed'; }
    else if (R_selFirst(doc, 'div.header-stats strong.ongoing')) { status = 'ongoing'; }
    return {
      key: mangaKey,
      title: '',
      coverUrl: R_img(R_selFirst(doc, '.cover img')),
      author: author,
      description: desc.trim(),
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var listUrl = R_abs(mangaKey);
    if (!/\\/$/.test(listUrl)) { listUrl += '/'; }
    var doc = $.html.parse(await $.http.get(listUrl + 'all-chapters/', HDRS));
    var els = R_sel(doc, 'ul.chapter-list > li');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var link = R_selFirst(el, 'a');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var nameEl = R_selFirst(el, '.chapter-title') || R_selFirst(el, '.chapter-number');
      var chapterName = nameEl ? R_ownText(nameEl).replace(/-eng-li$/, '') : '';
      var dateEl = R_selFirst(el, '.chapter-update');
      out.push({
        key: R_path(href),
        name: 'Chapter ' + chapterName,
        chapterNumber: -1,
        dateUpload: parseChapterDate(dateEl ? dateEl.attr('datetime') : ''),
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
    var els = R_sel(doc, '#chapter-reader img');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var src = els[i].absUrl('src');
      if (src && src.indexOf('credits-mgeko.png') < 0) {
        out.push({ index: out.length, url: src });
      }
    }
    return out;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
