// ZeistManga theme engine (Blogger/Blogspot label-feed based sources)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  mangaCategory: 'Series',
  excludedCategories: ['Anime', 'Novel', 'Novela'],
  supportsLatest: true,
  latestOrderBy: 'published',
  popularSelector: 'div.PopularPosts div.grid > figure',
  popularTitleSelector: 'figcaption > a',
  popularUrlSelector: 'figcaption > a',
  detailsRoot: '.grid.gtc-235fr',
  detailsTitleSelector: '',
  detailsThumbnailSelector: 'img',
  detailsDescriptionSelector: '#synopsis',
  detailsGenresSelector: 'div.mt-15 > a[rel=tag]',
  detailsAuthorSelector: 'span#author',
  detailsArtistSelector: 'span#artist',
  detailsAltNameSelector: 'header > p',
  detailsStatusSelector: 'span[data-status]',
  detailsInfoSelector: '.y6x11p',
  detailsInfoTitleSelector: 'strong',
  detailsInfoDescSelector: 'span.dt',
  statusKeywords: ['Status', 'Estado', 'الحالة'],
  authorKeywords: ['Author', 'Autor', 'Mangaka', 'الكاتب', 'Yazar'],
  artistKeywords: ['Artist', 'Artista', 'الرسام', 'Çizer'],
  statusOngoing: ['ongoing', 'en curso', 'en emisión', 'em lançamento', 'activo', 'ativo', 'lançando', 'مستمر', 'مستمرة'],
  statusCompleted: ['completed', 'completo', 'finalizado', 'مكتمل', 'مكتملة'],
  statusHiatus: ['hiatus', 'pausado'],
  statusCancelled: ['cancelled', 'dropped', 'dropado', 'abandonado', 'cancelado'],
  chapterCategoryList: ['Chapter'],
  supportsChapterFeed: true,
  useNewChapterFeed: false,
  useOldChapterFeed: false,
  preferUpdatedDate: false,
  chapterFeedRegex: 'clwd\\.run\\(["\'](.*?)["\']\\)',
  scriptSelector: '#clwd > script',
  feedTitleFrom: null,
  feedUrlPostProcess: null,
  pageListSelector: 'div.check-box div.separator',
  pagePreprocess: null,
  chapterFromDoc: null,
  appendDownloadChapters: false,
  searchPage: null,
  extraHeaders: null,
};

const STR_OVERRIDES = {
  mangaCategory: 'mangaCategory',
  popularMangaSelector: 'popularSelector',
  popularMangaSelectorTitle: 'popularTitleSelector',
  popularMangaSelectorUrl: 'popularUrlSelector',
  mangaDetailsSelector: 'detailsRoot',
  mangaDetailsSelectorThumbnail: 'detailsThumbnailSelector',
  mangaDetailsSelectorDescription: 'detailsDescriptionSelector',
  mangaDetailsSelectorGenres: 'detailsGenresSelector',
  mangaDetailsSelectorAuthor: 'detailsAuthorSelector',
  mangaDetailsSelectorArtist: 'detailsArtistSelector',
  mangaDetailsSelectorAltName: 'detailsAltNameSelector',
  mangaDetailsSelectorStatus: 'detailsStatusSelector',
  mangaDetailsSelectorInfo: 'detailsInfoSelector',
  mangaDetailsSelectorInfoTitle: 'detailsInfoTitleSelector',
  mangaDetailsSelectorInfoDescription: 'detailsInfoDescSelector',
  pageListSelector: 'pageListSelector',
  chapterCategory: 'chapterCategory',
};

const LIST_OVERRIDES = {
  excludedCategories: 'excludedCategories',
  statusOnGoingList: 'statusOngoing',
  statusCompletedList: 'statusCompleted',
  statusHiatusList: 'statusHiatus',
  statusCancelledList: 'statusCancelled',
  statusSelectorList: 'statusKeywords',
  authorSelectorList: 'authorKeywords',
  artisSelectorList: 'artistKeywords',
};

const BOOL_OVERRIDES = {
  supportsLatest: 'supportsLatest',
  supportsChapterFeed: 'supportsChapterFeed',
  useNewChapterFeed: 'useNewChapterFeed',
  useOldChapterFeed: 'useOldChapterFeed',
  preferChapterUpdatedDate: 'preferUpdatedDate',
};

function extractStrOverride(kt, name) {
  const m = kt.match(new RegExp('override\\s+val\\s+' + name + '\\s*(?::\\s*[^=]+)?=\\s*"((?:[^"\\\\]|\\\\.)*)"'));
  return m ? m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\') : undefined;
}

function extractBoolOverride(kt, name) {
  const m = kt.match(new RegExp('override\\s+val\\s+' + name + '\\s*=\\s*(true|false)'));
  return m ? m[1] === 'true' : undefined;
}

function extractListOverride(kt, name) {
  const m = kt.match(new RegExp('(?:override\\s+)?(?:private\\s+)?val\\s+' + name + '\\s*(?::\\s*List<String>\\s*)?=\\s*listOf\\(([^)]*)\\)'));
  if (!m) return undefined;
  const items = m[1].match(/"((?:[^"\\]|\\.)*)"/g);
  return items ? items.map(s => s.slice(1, -1)) : [];
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  for (const ktName of Object.keys(STR_OVERRIDES)) {
    const v = extractStrOverride(kt, ktName);
    if (v !== undefined) config[STR_OVERRIDES[ktName]] = v;
  }
  // alias assignment like `override val popularMangaSelectorUrl = popularMangaSelectorTitle`
  for (const ktName of Object.keys(STR_OVERRIDES)) {
    const m = kt.match(new RegExp('override\\s+val\\s+' + ktName + '\\s*=\\s*(\\w+)\\s*$', 'm'));
    if (m) {
      const srcCfg = STR_OVERRIDES[m[1]];
      if (srcCfg) config[STR_OVERRIDES[ktName]] = config[srcCfg];
    }
  }
  for (const ktName of Object.keys(LIST_OVERRIDES)) {
    const v = extractListOverride(kt, ktName);
    if (v !== undefined && v.length > 0) config[LIST_OVERRIDES[ktName]] = v;
  }
  for (const ktName of Object.keys(BOOL_OVERRIDES)) {
    const v = extractBoolOverride(kt, ktName);
    if (v !== undefined) config[BOOL_OVERRIDES[ktName]] = v;
  }

  // chapter categories
  const ccList = extractListOverride(kt, 'chapterCategories');
  if (ccList !== undefined && ccList.length > 0) {
    config.chapterCategoryList = ccList;
  } else {
    const cc = extractStrOverride(kt, 'chapterCategory');
    if (cc !== undefined) config.chapterCategoryList = [cc];
  }

  // latest ordering override (e.g. UlasComic "updated")
  if (/latestUpdatesUrl[\s\S]{0,160}?"updated"/.test(kt)) config.latestOrderBy = 'updated';

  // chapter feed title source overrides
  if (/getChapterFeedUrl[\s\S]{0,400}?data-labelchapter/.test(kt)) {
    config.feedTitleFrom = { type: 'attr', selector: '.chapter_get', attr: 'data-labelchapter' };
  } else if (/getChapterFeedUrl[\s\S]{0,400}?\[data-label\]/.test(kt)) {
    config.feedTitleFrom = { type: 'attr', selector: '[data-label]', attr: 'data-label' };
  } else if (/catNameProject/.test(kt)) {
    config.feedTitleFrom = { type: 'scriptText', text: 'catNameProject', regex: '=\\s+?\\(\'([^\']+)' };
  }

  // chapter feed url post-processing (YuriMoonSub: url-decode + strip arabic)
  if (/URLDecoder\.decode\(\s*super\.getChapterFeedUrl/.test(kt)) {
    config.feedUrlPostProcess = 'yurimoon';
  }

  // page list preprocessing modes
  if (/config\['chapterImage'\]/.test(kt)) {
    config.pagePreprocess = 'chapterimage';
  } else if (/PAGES_REGEX|\.chapter script/.test(kt)) {
    config.pagePreprocess = 'pagesjson';
  } else if (/const content = `/.test(kt)) {
    config.pagePreprocess = 'constcontent';
  } else if (/zeist-raw-data/.test(kt)) {
    config.pagePreprocess = 'rawdata';
  } else if (/override fun pageListParse/.test(kt)) {
    warnings.push('custom pageListParse not recognized; using selector defaults');
  }

  // chapters parsed straight from the manga page (Tooncubus)
  if (/series-chapterlist/.test(kt)) {
    config.chapterFromDoc = {
      listSelector: 'ul.series-chapterlist',
      itemSelector: 'div.flexch-infoz',
      nameSelector: 'span',
      linkSelector: 'a',
    };
  }

  // extra chapters from in-page download list (Yokai)
  if (/div#download > div\.index-list/.test(kt)) {
    config.appendDownloadChapters = true;
    warnings.push('custom chapter merge (download list) approximated; chapter renaming skipped');
  }

  // custom details parsing (OsakaScan: title from h1, whole-document root)
  if (/override fun mangaDetailsParse/.test(kt)) {
    if (/selectFirst\("h1"\)/.test(kt)) {
      config.detailsRoot = '';
      config.detailsTitleSelector = 'h1';
      const gm = kt.match(/select\("(dt:contains\([^)]*\)\s*\+\s*dd a)"\)/);
      if (gm) config.detailsGenresSelector = gm[1];
    } else {
      warnings.push('custom mangaDetailsParse approximated; extra parsing steps skipped');
    }
  }

  // HTML search page instead of feed search (Hanmokku Scan)
  if (/override fun searchMangaUrl/.test(kt) && /contains\("search"\)/.test(kt)) {
    const im = kt.match(/select\("(div\.grid\.gtc-f141a[^"]*)"\)/);
    config.searchPage = {
      path: '/search',
      itemSelector: im ? im[1] : 'div.grid.gtc-f141a > div',
      titleSelector: 'a.ck',
      urlSelector: 'a',
    };
    warnings.push('custom search page; search query is ignored by upstream source');
  }

  // extra request headers (e.g. YaoiFanClub Referer)
  const headers = {};
  let hm;
  const hre = /set\("([^"]+)",\s*"([^"]*)"\)/g;
  while ((hm = hre.exec(kt)) !== null) headers[hm[1]] = hm[2];
  if (Object.keys(headers).length > 0) {
    config.extraHeaders = headers;
    warnings.push('custom request headers applied to all requests');
  }

  if (/rateLimit\(/.test(kt)) warnings.push('rate limiting not portable; app-side throttling applies');
  if (/override fun getChapterList/.test(kt) && !config.chapterFromDoc && !config.appendDownloadChapters) {
    warnings.push('custom getChapterList not recognized; using feed defaults');
  }
  if (config.useNewChapterFeed || config.useOldChapterFeed) {
    warnings.push('non-default chapter feed mode');
  }

  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  const base = manifest.baseUrl.replace(/\/+$/, '');
  return String.raw`// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: zeistmanga)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_selFirst/R_ownText/R_status/R_date)
var BASE = ${JSON.stringify(base)};
var CFG = ${cfg};

// ---------------- zeistmanga engine ----------------
var MAX_MANGA = 20;
var URL_CACHE = {};
var BT = String.fromCharCode(96);

function httpGet(url) {
  if (CFG.extraHeaders) { return $.http.get(url, CFG.extraHeaders); }
  return $.http.get(url);
}

function z_selOne(node, css) {
  var m = css.match(/:contains(?:Own)?\(\s*"?([^")]*?)"?\s*\)/);
  if (!m) { return R_sel(node, css); }
  var needle = m[1].toLowerCase();
  var idx = css.indexOf(m[0]);
  var left = css.substring(0, idx).trim();
  var right = css.substring(idx + m[0].length);
  var comb = '';
  var rest = right;
  if (/^\s*\+/.test(right)) { comb = '+'; rest = right.replace(/^\s*\+\s*/, ''); }
  else if (/^\s*>/.test(right)) { comb = '>'; rest = right.replace(/^\s*>\s*/, ''); }
  else if (/^\s+\S/.test(right)) { comb = ' '; rest = right.replace(/^\s+/, ''); }
  if (comb === '+') {
    // no sibling access in host DOM wrapper; approximate with stripped selector
    return R_sel(node, css.replace(/:contains(?:Own)?\([^)]*\)/g, ''));
  }
  var cands = left ? R_sel(node, left) : [node];
  var out = [];
  for (var i = 0; i < cands.length; i++) {
    if (String(cands[i].text() || '').toLowerCase().indexOf(needle) < 0) { continue; }
    if (comb === '') { out.push(cands[i]); }
    else { var sub = R_sel(cands[i], rest); for (var j = 0; j < sub.length; j++) { out.push(sub[j]); } }
  }
  return out;
}

function z_sel(node, css) {
  if (!css) { return []; }
  if (css.indexOf(':contains') < 0) { return R_sel(node, css); }
  var parts = css.split(',');
  var out = [];
  for (var i = 0; i < parts.length; i++) {
    var one = z_selOne(node, parts[i].trim());
    for (var j = 0; j < one.length; j++) { out.push(one[j]); }
  }
  return out;
}

function z_selFirst(node, css) {
  var list = z_sel(node, css);
  return list.length > 0 ? list[0] : null;
}

function encSeg(s) { return encodeURIComponent(String(s)); }

function apiFeed(label) {
  return BASE + '/feeds/posts/default/-/' + encSeg(label) + '?alt=json';
}

function setQP(url, name, value) {
  var re = new RegExp('([?&])' + name + '=[^&]*');
  if (re.test(url)) { return url.replace(re, '$1' + name + '=' + encodeURIComponent(value)); }
  return url + (url.indexOf('?') >= 0 ? '&' : '?') + name + '=' + encodeURIComponent(value);
}

function fixThumb(u) {
  var v = String(u || '');
  if (!v) { return ''; }
  v = v.replace(/\/s.+?-c\//g, '/w600/');
  v = v.replace(/=s(?![\s\S]*=s).+?-c$/g, '=w600');
  return v;
}

function entryLinkHref(e) {
  var links = e.link || [];
  for (var i = 0; i < links.length; i++) {
    if (links[i].rel === 'alternate') { return links[i].href || ''; }
  }
  return '';
}

function entryHasCategory(e, list) {
  var cats = e.category || [];
  for (var i = 0; i < cats.length; i++) {
    for (var j = 0; j < list.length; j++) { if (cats[i].term === list[j]) { return true; } }
  }
  return false;
}

function entryCover(e) {
  var t = e['media$thumbnail'];
  if (t && t.url) { return R_abs(fixThumb(t.url)); }
  var c = e.content && e.content.$t;
  if (c) {
    try {
      var frag = $.html.parse(c);
      var img = R_selFirst(frag, 'img');
      if (img) { var s = img.attr('src'); if (s) { return R_abs(s); } }
    } catch (err) { /* ignore */ }
  }
  return '';
}

function feedToMangas(json) {
  var feed = (json && json.feed) || {};
  var entries = feed.entry || [];
  var out = [];
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i];
    if (!entryHasCategory(e, [CFG.mangaCategory])) { continue; }
    if (entryHasCategory(e, CFG.excludedCategories)) { continue; }
    var href = entryLinkHref(e);
    if (!href) { continue; }
    out.push({ key: R_path(href), title: (e.title && e.title.$t) || '', coverUrl: entryCover(e) });
  }
  return out;
}

async function feedList(page, query) {
  var start = MAX_MANGA * (page - 1) + 1;
  var url = apiFeed(CFG.mangaCategory);
  if (query) {
    url += '&q=' + encodeURIComponent('label:' + CFG.mangaCategory + ' ' + query);
  } else {
    url += '&orderby=' + encodeURIComponent(CFG.latestOrderBy || 'published');
  }
  url += '&max-results=' + (MAX_MANGA + 1) + '&start-index=' + start;
  var text = await httpGet(url);
  var mangas = feedToMangas($.json.parse(text));
  var hasNext = mangas.length > MAX_MANGA;
  if (hasNext) { mangas = mangas.slice(0, MAX_MANGA); }
  return { mangas: mangas, hasNextPage: hasNext };
}

async function popularFromHome() {
  var text = await httpGet(BASE + '/');
  var doc = $.html.parse(text);
  var items = z_sel(doc, CFG.popularSelector);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var urlEl = z_selFirst(el, CFG.popularUrlSelector);
    if (!urlEl) { continue; }
    var href = urlEl.absUrl('href') || urlEl.attr('href');
    if (!href) { continue; }
    var titleEl = z_selFirst(el, CFG.popularTitleSelector);
    var img = R_selFirst(el, 'img');
    out.push({ key: R_path(R_abs(href)), title: titleEl ? titleEl.text() : '', coverUrl: R_img(img) });
  }
  return out;
}

async function searchPageList() {
  var text = await httpGet(BASE + CFG.searchPage.path);
  var doc = $.html.parse(text);
  var items = z_sel(doc, CFG.searchPage.itemSelector);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var link = z_selFirst(items[i], CFG.searchPage.urlSelector);
    if (!link) { continue; }
    var href = link.absUrl('href') || link.attr('href');
    if (!href) { continue; }
    var titleEl = z_selFirst(items[i], CFG.searchPage.titleSelector);
    var img = R_selFirst(items[i], 'img');
    out.push({ key: R_path(R_abs(href)), title: titleEl ? titleEl.text() : '', coverUrl: R_img(img) });
  }
  return { mangas: out, hasNextPage: false };
}

function zStatus(s) {
  var v = String(s || '').toLowerCase().trim();
  var pairs = [['ongoing', CFG.statusOngoing], ['completed', CFG.statusCompleted], ['hiatus', CFG.statusHiatus], ['cancelled', CFG.statusCancelled]];
  for (var i = 0; i < pairs.length; i++) {
    var arr = pairs[i][1] || [];
    for (var j = 0; j < arr.length; j++) {
      if (v === String(arr[j]).toLowerCase().trim()) { return pairs[i][0]; }
    }
  }
  return R_status(v);
}

function containsAny(text, list) {
  var low = String(text || '').toLowerCase();
  for (var i = 0; i < list.length; i++) {
    if (low.indexOf(String(list[i]).toLowerCase()) >= 0) { return true; }
  }
  return false;
}

function parseDetails(doc, key) {
  var root = CFG.detailsRoot ? (z_selFirst(doc, CFG.detailsRoot) || doc) : doc;
  var title = '';
  if (CFG.detailsTitleSelector) {
    var tEl = z_selFirst(doc, CFG.detailsTitleSelector);
    if (tEl) { title = tEl.text(); }
  }
  if (!title) {
    var og = R_selFirst(doc, 'meta[property="og:title"]');
    if (og) { var c = og.attr('content'); if (c) { title = c.split('-')[0].trim(); } }
  }
  if (!title) {
    var h1 = R_selFirst(doc, 'h1');
    if (h1) { title = h1.text(); }
  }
  var cover = R_img(z_selFirst(root, CFG.detailsThumbnailSelector));
  var descParts = [];
  var descEls = z_sel(root, CFG.detailsDescriptionSelector);
  for (var i = 0; i < descEls.length; i++) {
    var t = descEls[i].text();
    if (t) { descParts.push(t); }
  }
  var desc = descParts.join(' ').trim();
  var altEl = z_selFirst(root, CFG.detailsAltNameSelector);
  if (altEl) {
    var at = altEl.text();
    if (at) { desc = (desc ? desc + '\n\n' : '') + 'Alternative Names: ' + at; }
  }
  var genres = [];
  var gEls = z_sel(root, CFG.detailsGenresSelector);
  for (var j = 0; j < gEls.length; j++) {
    var g = gEls[j].text();
    if (g) { genres.push(g); }
  }
  var author = '';
  var artist = '';
  var status = '';
  var aEl = z_selFirst(root, CFG.detailsAuthorSelector);
  if (aEl) { author = aEl.text(); }
  var rEl = z_selFirst(root, CFG.detailsArtistSelector);
  if (rEl) { artist = rEl.text(); }
  var sEl = z_selFirst(root, CFG.detailsStatusSelector);
  if (sEl) { status = zStatus(sEl.text()); }
  var infoEls = z_sel(root, CFG.detailsInfoSelector);
  for (var k = 0; k < infoEls.length; k++) {
    var el = infoEls[k];
    var infoText = R_ownText(el);
    if (!infoText && CFG.detailsInfoTitleSelector) {
      var tt = z_selFirst(el, CFG.detailsInfoTitleSelector);
      if (tt) { infoText = tt.text(); }
    }
    var dEls = z_sel(el, CFG.detailsInfoDescSelector);
    var descText = [];
    for (var n = 0; n < dEls.length; n++) {
      var dt = dEls[n].text();
      if (dt) { descText.push(dt); }
    }
    descText = descText.join(' ').trim();
    if (!status && containsAny(infoText, CFG.statusKeywords)) { status = zStatus(descText); }
    if (!author && containsAny(infoText, CFG.authorKeywords)) { author = descText; }
    if (!artist && containsAny(infoText, CFG.artistKeywords)) { artist = descText; }
  }
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

// ---- chapter feed url resolution ----

function feedTitle(doc) {
  var ft = CFG.feedTitleFrom;
  if (ft) {
    if (ft.type === 'attr') {
      var el = z_selFirst(doc, ft.selector);
      if (el) { var v = el.attr(ft.attr); if (v) { return v; } }
    } else if (ft.type === 'scriptText') {
      var scripts = R_sel(doc, 'script');
      for (var i = 0; i < scripts.length; i++) {
        var h = scripts[i].html();
        if (h.indexOf(ft.text) >= 0) {
          var m = h.match(new RegExp(ft.regex));
          if (m) { return m[1]; }
        }
      }
    }
  }
  var og = R_selFirst(doc, 'meta[property="og:title"]');
  if (og) { var c = og.attr('content'); if (c) { return c.split('-')[0].trim(); } }
  var h1 = R_selFirst(doc, 'h1');
  if (h1) { return h1.text(); }
  var et = R_selFirst(doc, '.entry-title, .post-title');
  if (et) { return et.text(); }
  return '';
}

function oldChapterFeedUrl(doc) {
  var script = z_selFirst(doc, '#myUL > script');
  var src = script ? script.attr('src') : '';
  if (!src) { throw new Error('no old feed script'); }
  var m = src.match(/([^']+)\?/);
  if (!m) { throw new Error('no old feed'); }
  return BASE + m[1] + '?alt=json';
}

function newChapterFeedUrl(doc) {
  var script = z_selFirst(doc, CFG.scriptSelector);
  var regex = CFG.chapterFeedRegex;
  if (!script) {
    script = z_selFirst(doc, '#latest > script');
    regex = "label\\s*=\\s*'([^']+)'";
  }
  if (!script) { throw new Error('no new feed script'); }
  var m = script.html().match(new RegExp(regex));
  if (!m) { throw new Error('no new feed'); }
  return apiFeed(m[1]) + '&start-index=1&max-results=999999';
}

function buildChapterFeedUrl(doc) {
  if (CFG.useOldChapterFeed) { return oldChapterFeedUrl(doc); }
  if (CFG.useNewChapterFeed) { return newChapterFeedUrl(doc); }
  var feed;
  var script = z_selFirst(doc, CFG.scriptSelector);
  if (!script) {
    try { return oldChapterFeedUrl(doc); } catch (e1) { return newChapterFeedUrl(doc); }
  }
  var m = script.html().match(new RegExp(CFG.chapterFeedRegex));
  feed = m ? m[1] : feedTitle(doc);
  var catSeg = CFG.chapterCategory ? encSeg(CFG.chapterCategory) + '/' : '';
  return BASE + '/feeds/posts/default/-/' + catSeg + encSeg(feed) + '?alt=json';
}

function yurimoonFix(url) {
  var v = url;
  try { v = decodeURIComponent(url); } catch (e) { /* keep */ }
  v = v.replace(/[\u0600-\u06FF]/g, '');
  v = v.replace(/\s{2,}/g, '');
  return v;
}

async function fetchAllEntries(feedUrl) {
  var entries = [];
  var first = $.json.parse(await httpGet(setQP(setQP(feedUrl, 'start-index', '1'), 'max-results', '150')));
  var feed = (first && first.feed) || {};
  var total = parseInt(feed['openSearch$totalResults'] && feed['openSearch$totalResults'].$t, 10);
  var perPage = parseInt(feed['openSearch$itemsPerPage'] && feed['openSearch$itemsPerPage'].$t, 10);
  if (isNaN(total)) { total = 150; }
  if (isNaN(perPage) || perPage <= 0) { perPage = 50; }
  entries = entries.concat(feed.entry || []);
  var guard = 0;
  while (entries.length < total && guard < 60) {
    guard++;
    var next = $.json.parse(await httpGet(setQP(setQP(feedUrl, 'start-index', String(entries.length + 1)), 'max-results', String(perPage))));
    var list = (next.feed && next.feed.entry) || [];
    if (list.length === 0) { break; }
    entries = entries.concat(list);
  }
  return entries;
}

function entriesToChapters(entries) {
  var catList = CFG.chapterCategoryList || [];
  var filterByCat = catList.length > 0 && catList[0] !== '';
  var out = [];
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i];
    if (filterByCat && !entryHasCategory(e, catList)) { continue; }
    var href = entryLinkHref(e);
    if (!href) { continue; }
    var pub = e.published && e.published.$t;
    var upd = e.updated && e.updated.$t;
    var dateStr = CFG.preferUpdatedDate ? (upd || pub) : (pub || upd);
    var path = R_path(href);
    if (href.indexOf(BASE) !== 0) { URL_CACHE[path] = href; }
    out.push({
      key: path,
      name: (e.title && e.title.$t) || '',
      chapterNumber: -1,
      dateUpload: R_date(dateStr),
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

function chaptersFromDoc(doc) {
  var cf = CFG.chapterFromDoc;
  var list = cf.listSelector ? z_selFirst(doc, cf.listSelector) : null;
  var items = list ? z_sel(list, cf.itemSelector) : z_sel(doc, cf.itemSelector);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = z_selFirst(el, cf.linkSelector);
    if (!link) { continue; }
    var href = link.absUrl('href') || link.attr('href');
    if (!href) { continue; }
    var nameEl = cf.nameSelector ? z_selFirst(el, cf.nameSelector) : null;
    var path = R_path(href);
    if (href.indexOf(BASE) !== 0) { URL_CACHE[path] = href; }
    out.push({
      key: path,
      name: nameEl ? nameEl.text() : link.text(),
      chapterNumber: -1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

function appendDownloadChapters(doc, chapters) {
  var seen = {};
  for (var i = 0; i < chapters.length; i++) { seen[chapters[i].key.split('?')[0]] = true; }
  var els = R_sel(doc, 'div#download > div.index-list > a');
  for (var j = 0; j < els.length; j++) {
    var href = els[j].absUrl('href') || els[j].attr('href');
    if (!href) { continue; }
    var p = R_path(href);
    var dedupe = p.split('?')[0];
    if (seen[dedupe]) { continue; }
    seen[dedupe] = true;
    if (href.indexOf(BASE) !== 0) { URL_CACHE[p] = href; }
    chapters.push({ key: p, name: els[j].text(), chapterNumber: -1, dateUpload: 0, pages: 0, sortOrder: 0 });
  }
  return chapters;
}

// ---- pages ----

function chapterImageUrls(doc) {
  var scripts = R_sel(doc, 'script');
  for (var i = 0; i < scripts.length; i++) {
    var h = scripts[i].html();
    var idx = h.indexOf("config['chapterImage']");
    if (idx >= 0) {
      var seg = h.substring(idx);
      var urls = [];
      var re = /"(https?:\/\/.*?)"/g;
      var m;
      while ((m = re.exec(seg)) !== null) { urls.push(m[1]); }
      if (urls.length > 0) { return urls; }
    }
  }
  return [];
}

function pagesJsonUrls(doc) {
  var sc = R_selFirst(doc, '.chapter script');
  if (!sc) { return []; }
  var m = sc.html().match(/=(\[[^\]]+\])/);
  if (!m) { return []; }
  try {
    var arr = $.json.parse(m[1]);
    if (Array.isArray(arr)) {
      var out = [];
      for (var i = 0; i < arr.length; i++) { if (typeof arr[i] === 'string') { out.push(arr[i]); } }
      return out;
    }
  } catch (e) { /* ignore */ }
  return [];
}

function extractPageUrls(doc) {
  var mode = CFG.pagePreprocess;
  if (mode === 'chapterimage') {
    var urls2 = chapterImageUrls(doc);
    if (urls2.length > 0) { return urls2; }
  }
  if (mode === 'pagesjson') {
    var urls3 = pagesJsonUrls(doc);
    if (urls3.length > 0) { return urls3; }
  }
  if (mode === 'rawdata') {
    var el = R_selFirst(doc, 'textarea#zeist-raw-data') || R_selFirst(doc, '#zeist-raw-data');
    if (el) {
      var raw = el.text();
      if (raw && raw.indexOf('<') >= 0) { doc = $.html.parse(raw); }
    }
  } else if (mode === 'constcontent') {
    var scripts = R_sel(doc, 'div.check-box script');
    var marker = 'const content = ' + BT;
    for (var s = 0; s < scripts.length; s++) {
      var h = scripts[s].html();
      var a = h.indexOf(marker);
      if (a >= 0) {
        var b = h.indexOf(BT + ';', a + marker.length);
        if (b > a) { doc = $.html.parse(h.substring(a + marker.length, b)); break; }
      }
    }
  }
  var els;
  if (CFG.pageListSelector === ':root') { els = [doc]; }
  else { els = z_sel(doc, CFG.pageListSelector); }
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var node = els[i];
    if (node.attr('src')) {
      var su = R_img(node);
      if (su && out.indexOf(su) < 0) { out.push(su); }
    }
    var imgs = R_sel(node, 'img[src]');
    for (var j = 0; j < imgs.length; j++) {
      var u = R_img(imgs[j]);
      if (u && out.indexOf(u) < 0) { out.push(u); }
    }
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    if (!CFG.supportsLatest) { return feedList(page, ''); }
    var out = await popularFromHome();
    if (out.length === 0) { return feedList(1, ''); }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    if (query && CFG.searchPage) { return searchPageList(); }
    return feedList(page, query || '');
  },

  getMangaDetail: async function (mangaKey) {
    var text = await httpGet(R_abs(mangaKey));
    var doc = $.html.parse(text);
    return parseDetails(doc, mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var text = await httpGet(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var chapters;
    if (CFG.chapterFromDoc) {
      chapters = chaptersFromDoc(doc);
    } else {
      var feedUrl = buildChapterFeedUrl(doc);
      if (CFG.feedUrlPostProcess === 'yurimoon') { feedUrl = yurimoonFix(feedUrl); }
      var entries = [];
      try { entries = await fetchAllEntries(feedUrl); } catch (e) { /* keep empty */ }
      chapters = entriesToChapters(entries);
    }
    // blogger feeds are newest-first; normalize to oldest-first
    chapters.reverse();
    chapters.sort(function (a, b) { return (a.dateUpload || 0) - (b.dateUpload || 0); });
    if (CFG.appendDownloadChapters) { chapters = appendDownloadChapters(doc, chapters); }
    for (var k = 0; k < chapters.length; k++) { chapters[k].sortOrder = k; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var url = URL_CACHE[chapterKey] || R_abs(chapterKey);
    var text = await httpGet(url);
    var doc = $.html.parse(text);
    var urls = extractPageUrls(doc);
    var pages = [];
    for (var i = 0; i < urls.length; i++) { pages.push({ index: i, url: urls[i] }); }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
