// ZManga theme engine (Indonesian WordPress manga themes)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  popularSelector: 'div.flexbox2-item',
  linkSelector: 'div.flexbox2-content a',
  titleSelector: 'div.flexbox2-title > span',
  nextPageSelector: 'div.pagination .next',
  thumbSelector: 'div.series-thumb img',
  altNameSelector: '.series-title span',
  altName: 'Alternative Name: ',
  seriesTypeSelector: 'div.block span.type',
  chapterSelector: 'ul.series-chapterlist div.flexch-infoz a',
  pageSelector: 'div.reader-area img',
};

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: zmanga)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_status/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- zmanga engine ----------------

var ID_MONTHS = ['januari', 'februari', 'maret', 'april', 'mei', 'juni', 'juli', 'agustus', 'september', 'oktober', 'november', 'desember'];

function parseDate(s) {
  var v = String(s || '').trim();
  if (!v) { return 0; }
  var m = v.match(/^(\\d{1,2})\\s+([A-Za-z]+)\\s+(\\d{4})$/);
  if (m) {
    var mon = m[2].toLowerCase();
    var mo = -1;
    for (var i = 0; i < ID_MONTHS.length; i++) {
      if (mon.indexOf(ID_MONTHS[i].slice(0, 3)) === 0) { mo = i; break; }
    }
    if (mo < 0) {
      var en = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
      for (var e = 0; e < en.length; e++) {
        if (mon.indexOf(en[e]) === 0) { mo = e; break; }
      }
    }
    if (mo >= 0) { return new Date(parseInt(m[3], 10), mo, parseInt(m[1], 10)).getTime(); }
  }
  var t = Date.parse(v);
  return isNaN(t) ? 0 : t;
}

function pagePath(page) {
  return page > 1 ? 'page/' + page + '/' : '';
}

function parseCards(doc) {
  var items = R_sel(doc, CFG.popularSelector);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = R_selFirst(el, CFG.linkSelector);
    if (!link) { continue; }
    var href = link.attr('abs:href') || link.attr('href');
    if (!href) { continue; }
    var tEl = R_selFirst(el, CFG.titleSelector);
    var img = R_selFirst(el, 'img');
    out.push({
      key: R_path(href),
      title: tEl ? tEl.text() : '',
      coverUrl: img ? R_abs(img.attr('src')) : ''
    });
  }
  return out;
}

function infoListValue(doc, label) {
  // equivalent of ".series-infolist li:contains(Label) span" without :contains
  var lis = R_sel(doc, '.series-infolist li');
  for (var i = 0; i < lis.length; i++) {
    if (lis[i].text().indexOf(label) >= 0) {
      var sp = R_selFirst(lis[i], 'span');
      if (sp) { return sp.text(); }
    }
  }
  return '';
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/advanced-search/' + pagePath(page) + '?order=popular');
    var doc = $.html.parse(text);
    return { mangas: parseCards(doc), hasNextPage: !!R_selFirst(doc, CFG.nextPageSelector) };
  },

  getSearchManga: async function (page, query) {
    if (!query) { return module.exports.getPopularManga(page); }
    var text = await $.http.get(BASE + '/advanced-search/' + pagePath(page) + '?title=' + encodeURIComponent(query));
    var doc = $.html.parse(text);
    return { mangas: parseCards(doc), hasNextPage: !!R_selFirst(doc, CFG.nextPageSelector) };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);

    var cover = '';
    var thumb = R_selFirst(doc, CFG.thumbSelector);
    if (thumb) {
      cover = thumb.attr('data-lazy-src') || thumb.attr('src') || '';
      cover = R_abs(cover);
    }
    var author = infoListValue(doc, 'Author');
    var artist = infoListValue(doc, 'Artist');

    var status = '';
    var statusEl = R_selFirst(doc, '.series-infoz .status');
    if (statusEl) {
      var sv = (R_ownText(statusEl) || statusEl.text()).toLowerCase();
      if (sv.indexOf('ongoing') >= 0) { status = 'ongoing'; }
      else if (sv.indexOf('completed') >= 0) { status = 'completed'; }
    }

    var desc = '';
    var descEl = R_selFirst(doc, 'div.series-synops');
    if (descEl) { desc = descEl.text(); }

    var genres = [];
    var genreEls = R_sel(doc, 'div.series-genres a');
    for (var g = 0; g < genreEls.length; g++) { genres.push(genreEls[g].text()); }

    var stEl = R_selFirst(doc, CFG.seriesTypeSelector);
    var seriesType = stEl ? (R_ownText(stEl) || '').trim() : '';
    if (seriesType && seriesType !== '-' && genres.indexOf(seriesType) < 0) {
      genres.push(seriesType);
    }

    var altEl = R_selFirst(doc, CFG.altNameSelector);
    var altText = altEl ? (R_ownText(altEl) || '').trim() : '';
    if (altText) {
      desc = desc ? desc + '\\n\\n' + CFG.altName + altText : CFG.altName + altText;
    }

    return {
      key: mangaKey,
      title: '',
      coverUrl: cover,
      author: author,
      artist: artist,
      description: desc,
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, CFG.chapterSelector);
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var href = el.attr('abs:href') || el.attr('href');
      if (!href) { continue; }
      var nameEl = R_selFirst(el, 'span');
      var dateEl = R_selFirst(el, 'span.date');
      out.push({
        key: R_path(href),
        name: nameEl ? (R_ownText(nameEl) || nameEl.text()) : '',
        chapterNumber: -1,
        dateUpload: dateEl ? parseDate(dateEl.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // newest first on site; normalize to oldest-first
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = out.length - 1 - j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, CFG.pageSelector);
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var img = els[i];
      // skip <noscript> fallback copies
      var p = img.parentElement, inNoscript = false;
      while (p) {
        if (p.tagName === 'NOSCRIPT') { inNoscript = true; break; }
        p = p.parentElement;
      }
      if (inNoscript) { continue; }
      var u = (img.attr('data-lazy-src') || img.attr('src') || '').replace(/\\\\/g, '');
      if (u) { pages.push({ index: pages.length, url: R_abs(u) }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
