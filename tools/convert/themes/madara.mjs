// Madara theme engine (covers: madara [ajax], madaralegacy, MadaraNoAjax [html])
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  archiveSelector: 'div.page-item-detail, .manga__item, .c-tabs-item__content',
  searchCardSelector: '.c-tabs-item__content',
  titleSelector: 'div.post-title h3, div.post-title h1, #manga-title > h1, div.post-title h5',
  authorSelector: 'div.author-content > a, div.manga-authors > a',
  artistSelector: 'div.artist-content > a',
  statusSelector: 'div.summary-content, div.summary-heading:contains(Status) + div',
  descriptionSelector: 'div.description-summary div.summary__content, div.summary_content div.post-content_item > h5 + div, div.summary_content div.manga-excerpt',
  thumbnailSelector: 'div.summary_image img',
  genreSelector: 'div.genres-content a',
  tagSelector: 'div.tags-content a',
  altNameSelector: '.post-content_item:contains(Alt) .summary-content',
  seriesTypeSelector: '.post-content_item:contains(Type) .summary-content',
  chapterListSelector: 'li.wp-manga-chapter',
  chapterUrlSelector: 'a',
  chapterDateSelector: 'span.chapter-release-date',
  pageSelector: 'div.page-break, li.blocks-gallery-item, .reading-content .text-left:not(:has(.blocks-gallery-item)) img',
  popularMangaSelector: '',
  popularMangaNextPageSelector: 'div.nav-previous, a.nextpostslink',
  searchMangaSelector: '',
  searchMangaNextPageSelector: 'div.nav-previous, a.nextpostslink',
};

const OVERRIDE_NAMES = Object.keys(DEFAULTS).concat([
  'mangaSubString', 'mangaDetailsSelectorTitle', 'mangaDetailsSelectorAuthor',
  'mangaDetailsSelectorArtist', 'mangaDetailsSelectorStatus', 'mangaDetailsSelectorDescription',
  'mangaDetailsSelectorThumbnail', 'mangaDetailsSelectorGenre', 'mangaDetailsSelectorTag',
]);

function extractStrOverride(kt, name) {
  const re = new RegExp(`override\\s+(?:open\\s+)?(?:val|fun)\\s+${name}\\s*(?:\\(\\))?\\s*(?::\\s*String\\s*)?=\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = kt.match(re);
  if (m) return m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  const tm = kt.match(new RegExp(`override\\s+(?:open\\s+)?(?:val|fun)\\s+${name}\\s*(?:\\(\\))?\\s*(?::\\s*String\\s*)?=\\s*([^\\n]+)`));
  if (tm && /"\s*\+\s*"/.test(tm[1])) {
    // simple string concatenation of literals
    const parts = tm[1].match(/"((?:[^"\\]|\\.)*)"/g);
    if (parts) return parts.map(p => p.slice(1, -1)).join('');
  }
  return undefined;
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  // base class -> mode
  let mode = 'html';
  if (/:\s*MadaraNoAjax\s*\(/.test(kt)) {
    mode = 'html';
  } else if (/:[\s\S]{0,80}?\bMadara\s*\(/.test(kt) && ctx.theme !== 'madaralegacy') {
    mode = 'ajax';
  } else if (/:\s*MadaraBase\s*\(/.test(kt)) {
    mode = 'html';
  }

  // selector prop aliases (new MadaraBase names -> canonical)
  const alias = {
    mangaDetailsSelectorTitle: 'titleSelector',
    mangaDetailsSelectorAuthor: 'authorSelector',
    mangaDetailsSelectorArtist: 'artistSelector',
    mangaDetailsSelectorStatus: 'statusSelector',
    mangaDetailsSelectorDescription: 'descriptionSelector',
    mangaDetailsSelectorThumbnail: 'thumbnailSelector',
    mangaDetailsSelectorGenre: 'genreSelector',
    mangaDetailsSelectorTag: 'tagSelector',
  };
  for (const name of OVERRIDE_NAMES) {
    const v = extractStrOverride(kt, name);
    if (v !== undefined) {
      const target = alias[name] ?? name;
      config[target] = v;
    }
  }

  const sub = extractStrOverride(kt, 'mangaSubString');
  config.mangaSubString = sub ?? 'manga';

  const fnm = kt.match(/filterNonMangaItems\s*(?:get\s*)?=\s*(true|false)/);
  config.filterNonMangaItems = fnm ? fnm[1] === 'true' : true;

  const cm = kt.match(/chapterMode\s*(?:get\s*)?=\s*ChapterMode\.(\w+)/);
  config.chapterMode = cm ? cm[1] : 'auto';

  const lm = kt.match(/useLoadMoreRequest\s*(?:get\s*)?=\s*LoadMoreStrategy\.(\w+)/);
  config.useLoadMore = lm ? lm[1] : 'AutoDetect';

  // guard: sources with heavy custom parsing still convert on defaults
  if (/chapterListParse\s*\(/.test(kt) && /element\.(select|selectFirst)\(/.test(kt) && !extractStrOverride(kt, 'chapterListSelector')) {
    warnings.push('custom chapterListParse not portable; using defaults');
  }
  if (/imageFromElement\s*\(/.test(kt) && /\{/.test(kt.split('imageFromElement')[1] ?? '')) {
    warnings.push('custom imageFromElement; using defaults');
  }
  if (/WebView|CloudflareHelper|rateLimit\(/.test(kt)) {
    warnings.push('uses interceptors/webview features; approximated');
  }
  config.mode = mode;
  return { ok: true, config, warnings, mode };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: madara/${config.mode})
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_status/R_date/R_form/R_xhr/R_wpProtector)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- madara engine ----------------
var PAGE_SIZE = 25;
var loadMoreDetected = null; // null=unknown true/false

function parseArchiveItems(doc) {
  var items = R_sel(doc, CFG.archiveSelector);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = R_selFirst(el, '.post-title a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, 'img');
    out.push({
      key: R_path(href),
      title: link.text(),
      coverUrl: R_img(img)
    });
  }
  return out;
}

function parseSearchCards(doc) {
  var items = R_sel(doc, CFG.searchCardSelector);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var link = R_selFirst(items[i], '.post-title a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(items[i], 'img');
    out.push({ key: R_path(href), title: link.text(), coverUrl: R_img(img) });
  }
  return out;
}

async function ajaxList(page, sortKey, query) {
  var pairs = [
    ['action', 'madara_load_more'],
    ['page', String(page - 1)],
    ['template', 'madara-core/content/content-archive'],
    ['vars[paged]', '1'],
    ['vars[template]', 'archive'],
    ['vars[posts_per_page]', String(PAGE_SIZE)],
    ['vars[post_type]', 'wp-manga'],
    ['vars[post_status]', 'publish'],
    ['vars[manga_archives_item_layout]', 'big_thumbnail']
  ];
  if (CFG.filterNonMangaItems) {
    pairs.push(['vars[meta_query][0][key]', '_wp_manga_chapter_type']);
    pairs.push(['vars[meta_query][0][value]', 'manga']);
  }
  if (sortKey) {
    pairs.push(['vars[orderby]', 'meta_value_num']);
    pairs.push(['vars[meta_key]', sortKey]);
    pairs.push(['vars[order]', 'DESC']);
  }
  if (query) { pairs.push(['vars[s]', query]); }
  var text = await $.http.post(BASE + '/wp-admin/admin-ajax.php', R_form(pairs), R_xhr());
  var doc = $.html.parse(text);
  var out = parseArchiveItems(doc);
  return { mangas: out, hasNextPage: out.length >= PAGE_SIZE };
}

function htmlNextPage(doc) {
  return !!R_selFirst(doc, CFG.popularMangaNextPageSelector + ', nav.navigation-ajax');
}

function detectLoadMore(doc) {
  if (loadMoreDetected === null) {
    loadMoreDetected = !!R_selFirst(doc, 'nav.navigation-ajax');
  }
  return loadMoreDetected;
}

async function htmlList(page, order, query) {
  var path = '/' + CFG.mangaSubString + '/';
  var url;
  if (query) {
    url = page > 1 ? BASE + '/page/' + page + '/?s=' + encodeURIComponent(query) + '&post_type=wp-manga'
      : BASE + '/?s=' + encodeURIComponent(query) + '&post_type=wp-manga';
  } else {
    url = page > 1 ? BASE + path + 'page/' + page + '/?m_orderby=' + order
      : BASE + path + '?m_orderby=' + order;
  }
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var out = parseArchiveItems(doc);
  if (out.length === 0 && query) { out = parseSearchCards(doc); }
  var hasNext = htmlNextPage(doc);
  if (!query && CFG.useLoadMore !== 'Never') { detectLoadMore(doc); }
  return { mangas: out, hasNextPage: hasNext };
}

function isAjaxMode() {
  return CFG.mode === 'ajax' || CFG.useLoadMore === 'Always' ||
    (CFG.useLoadMore !== 'Never' && loadMoreDetected === true);
}

async function listManga(page, query) {
  if (CFG.mode === 'ajax') {
    return ajaxList(page, query ? '' : '_wp_manga_views', query);
  }
  if (page > 1 && isAjaxMode()) {
    return ajaxList(page, '_wp_manga_views', query);
  }
  return htmlList(page, 'views', query);
}

function parseDetails(doc, key) {
  function texts(selector) {
    var els = R_sel(doc, selector);
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var t = els[i].text();
      if (t && !/^(updating|atualizando)/i.test(t)) { out.push(t); }
    }
    return out;
  }
  var title = '';
  var titleEl = R_selFirst(doc, CFG.titleSelector);
  if (titleEl) { title = R_ownText(titleEl) || titleEl.text(); }
  var author = texts(CFG.authorSelector).join(', ');
  var desc = '';
  var descEl = R_selFirst(doc, CFG.descriptionSelector);
  if (descEl) {
    var ps = R_sel(descEl, 'p');
    if (ps.length > 0) {
      var parts = [];
      for (var i = 0; i < ps.length; i++) {
        var pt = ps[i].text();
        if (pt) { parts.push(pt); }
      }
      desc = parts.join('\\n\\n');
    }
    if (!desc) { desc = descEl.text(); }
  }
  var status = '';
  var statusEls = R_sel(doc, CFG.statusSelector);
  if (statusEls.length > 0) { status = R_status(statusEls[statusEls.length - 1].text()); }
  var genres = texts(CFG.genreSelector).concat(texts(CFG.tagSelector));
  var seriesType = '';
  var stEl = R_selFirst(doc, CFG.seriesTypeSelector);
  if (stEl) { seriesType = stEl.text(); }
  if (seriesType) { genres.push(seriesType); }
  var cover = R_img(R_selFirst(doc, CFG.thumbnailSelector));
  return {
    key: key,
    title: title,
    coverUrl: cover,
    author: author,
    description: desc,
    genre: genres.join(', '),
    status: status
  };
}

function parseChaptersFrom(doc) {
  var els = R_sel(doc, CFG.chapterListSelector);
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var link = R_selFirst(el, CFG.chapterUrlSelector);
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var dateText = '';
    var imgEl = R_selFirst(el, 'img:not(.thumb)');
    if (imgEl) { dateText = imgEl.attr('alt'); }
    if (!dateText) {
      var aEl = R_selFirst(el, 'span a');
      if (aEl) { dateText = aEl.attr('title'); }
    }
    if (!dateText) {
      var dEl = R_selFirst(el, CFG.chapterDateSelector);
      if (dEl) { dateText = dEl.text(); }
    }
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
  // madara pages list newest-first; normalize to oldest-first (sortOrder ascending)
  for (var i = 0; i < chapters.length; i++) {
    chapters[i].sortOrder = chapters.length - 1 - i;
  }
  return chapters;
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga(page, '');
  },

  getSearchManga: async function (page, query) {
    return listManga(page, query);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    return parseDetails(doc, mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var doc, text;
    text = await $.http.get(R_abs(mangaKey));
    doc = $.html.parse(text);
    var chapters = parseChaptersFrom(doc);
    if (chapters.length === 0 && CFG.chapterMode !== 'MangaPage') {
      try {
        var ajaxUrl = R_abs(mangaKey).replace(/\\/+$/, '') + '/ajax/chapters/';
        var ajaxText = await $.http.post(ajaxUrl, '', R_xhr());
        chapters = parseChaptersFrom($.html.parse(ajaxText));
      } catch (e) { /* keep empty */ }
    }
    if (chapters.length === 0 && CFG.chapterMode === 'AdminAjax') {
      try {
        var holder = R_selFirst(doc, '[id^=manga-chapters-holder]');
        var id = holder ? holder.attr('data-id') : '';
        if (!id) {
          var rating = R_selFirst(doc, 'input.rating-post-id');
          id = rating ? rating.attr('value') : '';
        }
        if (id) {
          var adminText = await $.http.post(BASE + '/wp-admin/admin-ajax.php',
            R_form([['action', 'manga_get_chapters'], ['manga', id]]), R_xhr());
          chapters = parseChaptersFrom($.html.parse(adminText));
        }
      } catch (e2) { /* keep empty */ }
    }
    return withAscendingOrder(chapters);
  },

  getPageList: async function (chapterKey) {
    var url = R_abs(chapterKey);
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    if (R_selFirst(doc, '#single-pager')) {
      text = await $.http.get(url + (url.indexOf('?') >= 0 ? '&' : '?') + 'style=list');
      doc = $.html.parse(text);
    }
    var protector = R_selFirst(doc, '#chapter-protector-data');
    if (protector) {
      var urls = await R_wpProtector(protector);
      var prot = [];
      for (var j = 0; j < urls.length; j++) {
        prot.push({ index: j, url: R_abs(urls[j]) });
      }
      if (prot.length > 0) { return prot; }
    }
    var els = R_sel(doc, CFG.pageSelector);
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var node = els[i];
      var img = node.attr('src') !== '' || node.attr('data-src') !== '' ? node : R_selFirst(node, 'img');
      if (!img) { continue; }
      var u = R_img(img);
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
