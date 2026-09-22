// FMReader theme engine (Flat-Manga CMS: mangagun / rawinu / rawlh / welovemangaone)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  requestPath: 'manga-list.html',
  popularUrl: '/{requestPath}?listType=pagination&page={page}&sort=views&sort_type=DESC',
  latestUrl: '/{requestPath}?listType=pagination&page={page}&sort=last_update&sort_type=DESC',
  cardSelector: 'div.media, .thumb-item-flow',
  cardMode: 'default',
  headerSelector: 'h3 a, .series-title a',
  nextPageOverride: '',
  infoSelector: 'div.row',
  descSelector: 'div.detail .content, div.row ~ div.row:has(h3:first-child) p, .summary-content p',
  chaptersMode: 'page',
  chapterNameAttr: false,
  pagesMode: 'default',
  ddosGuard: false,
  extraCookie: '',
};

function extractStrOverride(kt, name) {
  const re = new RegExp(`override\\s+(?:open\\s+)?(?:val|fun)\\s+${name}\\s*(?:\\(\\))?\\s*(?::\\s*String\\s*)?=\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = kt.match(re);
  if (m) return m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  return undefined;
}

function extractUrlTemplate(kt, fn) {
  const re = new RegExp(`override\\s+fun\\s+${fn}\\s*\\(\\s*page:\\s*Int[^)]*\\)[^=]*=[\\s\\S]{0,300}?GET\\(\\s*"((?:[^"\\\\]|\\\\.)*)"`, 'm');
  const m = kt.match(re);
  if (!m) return undefined;
  return m[1].replace(/\$baseUrl/g, '').replace(/\$page/g, '{page}').replace(/\$sortBy/g, '{sort}');
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  const rp = extractStrOverride(kt, 'requestPath');
  if (rp !== undefined) { config.requestPath = rp; }

  const pop = extractUrlTemplate(kt, 'popularMangaRequest');
  if (pop !== undefined) { config.popularUrl = pop; }
  const lat = extractUrlTemplate(kt, 'latestUpdatesRequest');
  if (lat !== undefined) { config.latestUrl = lat; }

  const ps = extractStrOverride(kt, 'popularMangaSelector');
  if (ps !== undefined) { config.cardSelector = ps; }

  const hs = extractStrOverride(kt, 'headerSelector');
  if (hs !== undefined) { config.headerSelector = hs; }

  const np = extractStrOverride(kt, 'popularMangaNextPageSelector');
  if (np !== undefined) { config.nextPageOverride = np; }

  const ie = extractStrOverride(kt, 'infoElementSelector');
  if (ie !== undefined) { config.infoSelector = ie; }

  const ds = extractStrOverride(kt, 'mangaDetailsSelectorDescription');
  if (ds !== undefined) { config.descSelector = ds; }

  // custom card parsing variants
  if (/\.manga-title/.test(kt) && /\.manga-cover/.test(kt)) {
    config.cardMode = 'mangagun';
  } else if (/img-in-ratio/.test(kt) && /BACKGROUND_IMAGE_REGEX/.test(kt)) {
    config.cardMode = 'bgstyle';
  }

  // chapter listing variants
  if (/cont\.Listchapter\.php\?slug=/.test(kt)) {
    config.chaptersMode = 'xhr-slug';
  } else if (/cont\.Listchapter\.php/.test(kt) && /mid/.test(kt)) {
    config.chaptersMode = 'xhr-mid';
  }
  if (/override\s+val\s+chapterUrlSelector\s*=\s*""/.test(kt)) {
    config.chapterNameAttr = true;
  }

  // page listing variants
  if (/base64PageListParse/.test(kt)) {
    config.pagesMode = 'base64';
  } else if (/cont\.imagesChap\.php/.test(kt)) {
    config.pagesMode = 'xhr-imageschap';
  } else if (/cont\.listImg\.php/.test(kt)) {
    config.pagesMode = 'xhr-listimg';
  } else if (/img\[id~=page/.test(kt)) {
    config.pagesMode = 'mangagun';
  }

  if (/DDoS protection is activated/.test(kt)) {
    config.ddosGuard = true;
    warnings.push('DDoS challenge replicated via cookie retry; may fail if site changes');
  }
  if (/smartlink_shown/.test(kt)) {
    config.extraCookie = 'smartlink_shown=1';
  }
  if (/rateLimit\s*\(/.test(kt)) {
    warnings.push('rateLimit not portable; requests may be throttled by site');
  }
  if (/imageRequest\s*\(/.test(kt)) {
    warnings.push('per-page image Referer not portable; using site root Referer');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: fmreader)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_status/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- fmreader engine ----------------

function baseHeaders(extra) {
  var h = { Referer: BASE + '/' };
  if (CFG.extraCookie) { h.Cookie = CFG.extraCookie; }
  if (extra) { for (var k in extra) { h[k] = extra[k]; } }
  return h;
}

async function httpGet(url, headers) {
  var text = await $.http.get(url, baseHeaders(headers));
  if (CFG.ddosGuard && text.indexOf('DDoS protection is activated for your IP') >= 0) {
    var m = text.match(/'([a-f0-9]{32})'/);
    if (m) {
      var h2 = baseHeaders(headers);
      h2.Cookie = (h2.Cookie ? h2.Cookie + '; ' : '') + 'ct_anti_ddos_key=' + m[1];
      text = await $.http.get(url, h2);
    }
  }
  return text;
}

function resolveUrl(href, base) {
  try { return new URL(href, base).href; } catch (e) { return R_abs(href); }
}

function imgAttr(el) {
  if (!el) { return ''; }
  var names = ['data-original', 'data-src', 'data-bg', 'data-srcset'];
  for (var i = 0; i < names.length; i++) {
    var v = el.attr(names[i]);
    if (v) { return R_abs(v); }
  }
  var style = el.attr('style');
  if (style && style.indexOf('(') >= 0) {
    var inner = style.substring(style.indexOf('(') + 1, style.indexOf(')'));
    return R_abs(inner.replace(/['"]/g, '').trim());
  }
  return el.attr('src') ? R_abs(el.attr('src')) : '';
}

function parseCards(doc) {
  var items = R_sel(doc, CFG.cardSelector);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var key = '', title = '', cover = '';
    if (CFG.cardMode === 'mangagun') {
      var mt = R_selFirst(el, '.manga-title');
      if (!mt) { continue; }
      key = R_path(resolveUrl(mt.attr('href') || mt.absUrl('href'), BASE + '/'));
      title = mt.text();
      cover = imgAttr(R_selFirst(el, '.manga-cover'));
    } else if (CFG.cardMode === 'bgstyle') {
      var hsel = R_selFirst(el, CFG.headerSelector);
      if (!hsel) { continue; }
      key = R_path(resolveUrl(hsel.attr('href') || hsel.absUrl('href'), BASE + '/'));
      title = hsel.text();
      var bg = R_selFirst(el, 'div.content.img-in-ratio');
      if (bg) {
        var m = String(bg.attr('style') || '').match(/url\\(['"]?(.*?)['"]?\\)/);
        if (m) { cover = R_abs(m[1]); }
      }
    } else {
      var h = R_selFirst(el, CFG.headerSelector);
      if (!h) { continue; }
      key = R_path(resolveUrl(h.attr('href') || h.absUrl('href'), BASE + '/'));
      title = h.text();
      cover = imgAttr(R_selFirst(el, 'img, .thumb-wrapper .img-in-ratio'));
    }
    if (!key) { continue; }
    out.push({ key: key, title: title, coverUrl: cover });
  }
  return out;
}

function hasNextPage(doc) {
  if (CFG.nextPageOverride) {
    var el = R_selFirst(doc, CFG.nextPageOverride);
    if (!el) { return false; }
    if (el.attr('href')) { return true; }
    var t = el.text() || '';
    var m = t.match(/page\\s+(\\d+)\\s+of\\s+(\\d+)/i);
    if (m) { return m[1] !== m[2]; }
    return t.trim().length > 0;
  }
  var btn = R_selFirst(doc, 'div.col-lg-9 button.btn-info');
  if (btn) {
    var t2 = btn.text() || '';
    var m2 = t2.match(/page\\s+(\\d+)\\s+of\\s+(\\d+)/i);
    if (m2) { return m2[1] !== m2[2]; }
    return t2.trim().length > 0;
  }
  var links = R_sel(doc, '.pagination a');
  for (var i = 0; i < links.length; i++) {
    var cls = links[i].attr('class') || '';
    if (cls.indexOf('disabled') < 0 && (links[i].text() || '').indexOf('\\u00BB') >= 0) { return true; }
  }
  return false;
}

async function listManga(page, query) {
  var url;
  if (query) {
    url = BASE + '/' + CFG.requestPath + '?name=' + encodeURIComponent(query) + '&page=' + page;
  } else {
    url = BASE + (CFG.popularUrl.indexOf('{requestPath}') >= 0 ? CFG.popularUrl.replace('{requestPath}', CFG.requestPath) : CFG.popularUrl);
    url = url.replace('{page}', String(page)).replace('{sort}', 'views');
  }
  var text = await httpGet(url);
  var doc = $.html.parse(text);
  return { mangas: parseCards(doc), hasNextPage: hasNextPage(doc) };
}

function parseStatus(s) {
  var low = String(s || '').toLowerCase();
  var completed = ['completed', 'complete', 'đã hoàn thành', 'hoàn thành', 'tamamlandı'];
  var ongoing = ['ongoing', 'on going', 'updating', 'incomplete', 'chưa hoàn thành', 'đang cập nhật', 'đang tiến hành', 'devam ediyor'];
  for (var i = 0; i < completed.length; i++) { if (low === completed[i]) { return 'completed'; } }
  for (var j = 0; j < ongoing.length; j++) { if (low === ongoing[j]) { return 'ongoing'; } }
  return '';
}

function parseAbsoluteDate(s) {
  var m = String(s || '').match(/^(\\d{2})\\/(\\d{2})\\/(\\d{4})$/);
  if (!m) { return R_date(s); }
  return new Date(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10)).getTime();
}

function parseDetails(doc, key) {
  var info = R_selFirst(doc, CFG.infoSelector);
  var author = '', genre = '', status = '', cover = '';
  if (info) {
    var authors = [];
    var aEls = R_sel(info, 'li a.btn-info');
    for (var a = 0; a < aEls.length; a++) {
      var t = aEls[a].text();
      if (t && t.toLowerCase() !== 'updating') { authors.push(t); }
    }
    author = authors.join(', ');
    var gEls = R_sel(info, 'li a.btn-danger');
    var genres = [];
    for (var g = 0; g < gEls.length; g++) { genres.push(gEls[g].text()); }
    genre = genres.join(', ');
    var sEl = R_selFirst(info, 'li a.btn-success');
    status = parseStatus(sEl ? sEl.text() : '');
    cover = imgAttr(R_selFirst(info, 'img.thumbnail'));
  }
  var desc = '';
  var descEls = R_sel(doc, CFG.descSelector);
  var parts = [];
  for (var d = 0; d < descEls.length; d++) {
    if (descEls[d].text()) { parts.push(descEls[d].text()); }
  }
  desc = parts.join(' ');
  if (info) {
    // alternative name from "li:contains(Other names)" ownText
    var lis = R_sel(info, 'li');
    for (var l = 0; l < lis.length; l++) {
      if ((lis[l].text() || '').indexOf('Other names') >= 0) {
        var own = R_ownText(lis[l]);
        if (own && own.toLowerCase().indexOf('updating') < 0 && own.trim() !== '') {
          if (desc) { desc = desc + '\\n\\nAlternative Name' + own; }
          else { desc = 'Alternative Name' + own; }
        }
        break;
      }
    }
  }
  return {
    key: key,
    title: '',
    coverUrl: cover,
    author: author,
    description: desc,
    genre: genre,
    status: status
  };
}

function cleanName(mangaTitle, name) {
  var n = String(name || '');
  var prefix = String(mangaTitle || '') + ' ';
  if (prefix.trim() && n.indexOf(prefix) === 0) { n = n.substring(prefix.length); }
  return n;
}

function chaptersFromDoc(doc, mangaTitle, baseUrlForResolve) {
  var els = R_sel(doc, 'div#list-chapters p, table.table tr, .list-chapters > a');
  var out = [];
  var seen = {};
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var key = '', name = '', dateText = '';
    if (CFG.chapterNameAttr) {
      key = R_path(resolveUrl(el.attr('href') || el.absUrl('href'), baseUrlForResolve));
      name = el.attr('title') || '';
    } else {
      var a = R_selFirst(el, 'a');
      if (!a && el.attr('href')) { a = el; }
      if (!a) { continue; }
      key = R_path(resolveUrl(a.attr('href') || a.absUrl('href'), baseUrlForResolve));
      name = (a === el && el.attr('title')) || a.text();
    }
    if (!key || seen[key]) { continue; }
    seen[key] = true;
    var dEl = R_selFirst(el, 'time, .chapter-time, .publishedDate');
    if (dEl && dEl.text()) { dateText = dEl.text(); }
    out.push({
      key: key,
      name: cleanName(mangaTitle, name),
      chapterNumber: -1,
      dateUpload: dateText ? (R_date(dateText) || parseAbsoluteDate(dateText)) : 0,
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

function xhrChapters(doc, mangaTitle) {
  var els = R_sel(doc, '.at-series a');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var a = els[i];
    var href = a.attr('href') || a.absUrl('href');
    if (!href) { continue; }
    var resolved = resolveUrl(href, BASE + '/app/manga/controllers/');
    var key = resolved.indexOf('controllers') >= 0 ? resolved.substring(resolved.indexOf('controllers') + 'controllers'.length) : R_path(resolved);
    var nameEl = R_selFirst(a, '.chapter-name');
    var timeEl = R_selFirst(a, '.chapter-time');
    out.push({
      key: key,
      name: nameEl ? nameEl.text() : a.text(),
      chapterNumber: -1,
      dateUpload: timeEl ? R_date(timeEl.text()) : 0,
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga(page, '');
  },

  getSearchManga: async function (page, query) {
    return listManga(page, query || '');
  },

  getMangaDetail: async function (mangaKey) {
    var text = await httpGet(R_abs(mangaKey));
    var doc = $.html.parse(text);
    return parseDetails(doc, mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var mangaUrl = R_abs(mangaKey);
    var text = await httpGet(mangaUrl);
    var doc = $.html.parse(text);
    var mangaTitle = '';
    var titleEl = R_selFirst(doc, '.manga-info h1, .manga-info h3');
    if (titleEl) { mangaTitle = titleEl.text(); }

    var chapters = [];
    if (CFG.chaptersMode === 'xhr-slug') {
      var sm = mangaKey.match(/manga-([^\\/.]*)/) || mangaKey.match(/raw-([^\\/.]*)/);
      var slug = sm ? sm[1] : '';
      if (slug) {
        var xhrText = await httpGet(BASE + '/app/manga/controllers/cont.Listchapter.php?slug=' + slug);
        chapters = xhrChapters($.html.parse(xhrText), mangaTitle);
      }
    } else if (CFG.chaptersMode === 'xhr-mid') {
      var mm = mangaKey.match(/(\\d+)\\//);
      var mid = mm ? mm[1] : '';
      if (mid) {
        var midText = await httpGet(BASE + '/app/manga/controllers/cont.Listchapter.php?mid=' + mid);
        chapters = chaptersFromDoc($.html.parse(midText), mangaTitle, BASE + '/');
      }
    } else {
      chapters = chaptersFromDoc(doc, mangaTitle, BASE + '/');
    }
    // newest first on site; normalize to oldest-first
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = chapters.length - 1 - j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var chapterUrl = R_abs(chapterKey);
    var text = await httpGet(chapterUrl);
    var doc = $.html.parse(text);
    var pages = [];

    if (CFG.pagesMode === 'xhr-imageschap' || CFG.pagesMode === 'xhr-listimg') {
      var idEl = R_selFirst(doc, 'input[name=chapter]#chapter, #chapter');
      var cid = idEl ? idEl.attr('value') : '';
      if (!cid) { return []; }
      var endpoint = CFG.pagesMode === 'xhr-imageschap' ? 'cont.imagesChap.php' : 'cont.listImg.php';
      var xhrText = await httpGet(BASE + '/app/manga/controllers/' + endpoint + '?cid=' + cid);
      var xdoc = $.html.parse(xhrText);
      var imgs = R_sel(xdoc, 'img.chapter-img');
      for (var xi = 0; xi < imgs.length; xi++) {
        var xu = imgAttr(imgs[xi]);
        if (!xu) { xu = resolveUrl(imgs[xi].attr('src') || '', chapterUrl); }
        if (xu) { pages.push({ index: pages.length, url: xu }); }
      }
      return pages;
    }

    if (CFG.pagesMode === 'mangagun') {
      var mgImgs = R_sel(doc, 'img[id^=page]');
      for (var mi = 0; mi < mgImgs.length; mi++) {
        var mu = mgImgs[mi].attr('src') || '';
        if (mu) { pages.push({ index: pages.length, url: R_abs(mu) }); }
      }
      return pages;
    }

    var els = R_sel(doc, 'img.chapter-img');
    for (var i = 0; i < els.length; i++) {
      var img = els[i];
      var url = '';
      if (CFG.pagesMode === 'base64') {
        var attrs = ['data-img', 'data-original', 'data-src', 'data-srcset', 'data-aload', 'src'];
        for (var aa = 0; aa < attrs.length; aa++) {
          var val = img.attr(attrs[aa]);
          if (val) {
            if (val.indexOf('.') < 0) {
              try { url = $.crypto.base64Decode(val); } catch (e) { url = ''; }
            } else {
              url = R_abs(val);
            }
            break;
          }
        }
      } else {
        url = imgAttr(img);
      }
      if (url) { pages.push({ index: pages.length, url: url }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return baseHeaders();
  }
};
`;
}
