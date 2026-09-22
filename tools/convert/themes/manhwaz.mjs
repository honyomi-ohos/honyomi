// ManhwaZ theme engine (madara-lite Vietnamese variant)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  searchPath: 'search',
  popularSelector: '#slide-top > .item',
  popularLinkSelector: '.info-item a',
  popularImgSelector: '.img-item img',
  latestSelector: '.page-item-detail',
  latestLinkSelector: '.item-summary a',
  latestImgSelector: '.item-thumb img',
  nextPageSelector: 'ul.pager a[rel=next]',
  titleSelector: 'div.post-title h1',
  descSelector: 'div.summary__content',
  genreSelector: 'div.genres-content a[rel=tag]',
  thumbSelector: 'div.summary_image img',
  chapterSelector: 'li.wp-manga-chapter',
  chapterDateSelector: 'span.chapter-release-date',
  pageSelector: 'div.page-break img',
  authorHeading: 'author(s)',
  statusHeading: 'status',
  popularGenre: '',
  chaptersMore: false,
};

function extractStrOverride(kt, name) {
  const re = new RegExp(`override\\s+(?:open\\s+)?(?:val|fun)\\s+${name}\\s*(?:\\(\\))?\\s*(?::\\s*String\\s*)?=\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = kt.match(re);
  if (m) return m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  return undefined;
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  const names = ['searchPath', 'popularSelector', 'authorHeading', 'statusHeading', 'chapterSelector', 'chapterDateSelector', 'pageSelector', 'latestSelector'];
  for (const name of names) {
    const v = extractStrOverride(kt, name);
    if (v !== undefined) { config[name] = v; }
  }

  // manhwaz.com replaces the homepage popular slider with a genre listing sorted by views
  const gm = kt.match(/getPopularManga\s*\([\s\S]{0,500}?"\$baseUrl\/(genre\/[a-z0-9-]+)"/);
  if (gm) { config.popularGenre = gm[1]; }

  if (/\.c-chapter-readmore/.test(kt)) { config.chaptersMore = true; }

  if (/rateLimit\s*\(/.test(kt)) {
    warnings.push('rateLimit not portable; requests may be throttled by site');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: manhwaz)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_status/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- manhwaz engine ----------------

function parseCards(doc, cardSel, linkSel, imgSel) {
  var items = R_sel(doc, cardSel);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = R_selFirst(el, linkSel);
    if (!link) { continue; }
    var href = link.attr('href') || link.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, imgSel);
    out.push({
      key: R_path(href),
      title: link.text(),
      coverUrl: R_img(img)
    });
  }
  return out;
}

function hasNext(doc) {
  return !!R_selFirst(doc, CFG.nextPageSelector);
}

function headingContent(doc, heading) {
  // equivalent of "div.summary-heading:contains(X) + div.summary-content" without :contains
  var heads = R_sel(doc, 'div.summary-heading');
  var low = String(heading).toLowerCase();
  for (var i = 0; i < heads.length; i++) {
    var t = (R_ownText(heads[i]) || heads[i].text()).toLowerCase();
    if (t.indexOf(low) >= 0) {
      var sib = heads[i].nextElementSibling;
      if (sib) { return sib.text(); }
    }
  }
  return '';
}

function parseStatus(s) {
  var v = String(s || '').toLowerCase();
  if (!v) { return ''; }
  if (v.indexOf('ongoing') >= 0 || v.indexOf('đang ra') >= 0) { return 'ongoing'; }
  if (v.indexOf('completed') >= 0 || v.indexOf('hoàn thành') >= 0 || v.indexOf('truyện full') >= 0) { return 'completed'; }
  return R_status(v);
}

async function fetchChapterDoc(key) {
  var text = await $.http.get(R_abs(key));
  return $.html.parse(text);
}

function parseChapters(doc) {
  var els = R_sel(doc, CFG.chapterSelector);
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var link = R_selFirst(el, 'a');
    if (!link) { continue; }
    var href = link.attr('href') || link.absUrl('href');
    if (!href) { continue; }
    var dateText = '';
    var dEl = R_selFirst(el, CFG.chapterDateSelector);
    if (dEl) { dateText = dEl.text(); }
    out.push({
      key: R_path(href),
      name: link.text(),
      chapterNumber: -1,
      dateUpload: R_date(dateText),
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

function withAscendingOrder(chapters) {
  for (var i = 0; i < chapters.length; i++) {
    chapters[i].sortOrder = chapters.length - 1 - i;
  }
  return chapters;
}

module.exports = {
  getPopularManga: async function (page) {
    if (CFG.popularGenre) {
      var url = BASE + '/' + CFG.popularGenre + '?m_orderby=views&page=' + page;
      var text = await $.http.get(url);
      var doc = $.html.parse(text);
      return { mangas: parseCards(doc, CFG.latestSelector, CFG.latestLinkSelector, CFG.latestImgSelector), hasNextPage: hasNext(doc) };
    }
    var homeText = await $.http.get(BASE + '/');
    var homeDoc = $.html.parse(homeText);
    return { mangas: parseCards(homeDoc, CFG.popularSelector, CFG.popularLinkSelector, CFG.popularImgSelector), hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    if (!query) { return module.exports.getPopularManga(page); }
    var url = BASE + '/' + CFG.searchPath + '?s=' + encodeURIComponent(query) + '&page=' + page;
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    return { mangas: parseCards(doc, CFG.latestSelector, CFG.latestLinkSelector, CFG.latestImgSelector), hasNextPage: hasNext(doc) };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await fetchChapterDoc(mangaKey);
    var title = '';
    var titleEl = R_selFirst(doc, CFG.titleSelector);
    if (titleEl) { title = titleEl.text(); }
    var desc = '';
    var descEl = R_selFirst(doc, CFG.descSelector);
    if (descEl) { desc = descEl.text(); }
    var genres = [];
    var genreEls = R_sel(doc, CFG.genreSelector);
    for (var i = 0; i < genreEls.length; i++) { genres.push(genreEls[i].text()); }
    var author = headingContent(doc, CFG.authorHeading);
    var statusText = headingContent(doc, CFG.statusHeading);
    return {
      key: mangaKey,
      title: title,
      coverUrl: R_img(R_selFirst(doc, CFG.thumbSelector)),
      author: author,
      description: desc,
      genre: genres.join(', '),
      status: parseStatus(statusText)
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await fetchChapterDoc(mangaKey);
    var chapters = parseChapters(doc);
    if (CFG.chaptersMore) {
      try {
        var more = R_selFirst(doc, '.c-chapter-readmore');
        var moreUrl = more ? (more.attr('data-ajax-url') || '') : '';
        if (moreUrl) {
          var moreText = await $.http.get(R_abs(moreUrl));
          chapters = chapters.concat(parseChapters($.html.parse(moreText)));
        }
      } catch (e) { /* keep base list */ }
    }
    return withAscendingOrder(chapters);
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, CFG.pageSelector);
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var u = R_img(els[i]);
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
