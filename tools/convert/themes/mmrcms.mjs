// MMRCMS theme engine (readcomicsonline / mangasin / scanvf / onma / utsukushii)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  itemPath: 'manga',
  detailsTitleSelector: '.listmanga-header, .widget-title',
  chapterString: 'Chapter',
  searchSelector: 'div.media',
  searchLinkSelector: '.media-heading a, .manga-heading a',
  pageSelector: '#all > img.img-responsive',
  popularUrl: '/filterList?page={page}&sortBy=views&asc=false',
  searchParam: 'query',
  searchArrayResponse: false,
  directoryNoItemPath: false,
  onmaDetails: false,
  rcoMode: false,
  mangasinMode: false,
  latestUrl: '/latest-release?page={page}',
  dateFormat: 'd MMM. yyyy',
};

function extractStrOverride(kt, name) {
  const re = new RegExp(`override\\s+(?:open\\s+)?(?:val|fun)\\s+${name}\\s*(?:\\(\\))?\\s*(?::\\s*String\\s*)?=\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = kt.match(re);
  if (m) return m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  return undefined;
}

function extractUrlOverride(kt, fn) {
  // matches: override fun <fn>(page: Int): Request = GET("$baseUrl/xxx$page...", headers)
  const re = new RegExp(`override\\s+fun\\s+${fn}\\s*\\(\\s*page:\\s*Int[^)]*\\)[^=]*=\\s*GET\\(\\s*"((?:[^"\\\\]|\\\\.)*)"`, 'm');
  const m = kt.match(re);
  if (!m) return undefined;
  return m[1]
    .replace(/\$baseUrl/g, '')
    .replace(/\$page/g, '{page}');
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  const v = extractStrOverride(kt, 'itemPath');
  if (v !== undefined) { config.itemPath = v; }
  const ts = extractStrOverride(kt, 'detailsTitleSelector');
  if (ts !== undefined) { config.detailsTitleSelector = ts; }
  const cs = extractStrOverride(kt, 'chapterString');
  if (cs !== undefined) { config.chapterString = cs; }
  const ss = extractStrOverride(kt, 'searchMangaSelector');
  if (ss !== undefined) { config.searchSelector = ss; }

  const pop = extractUrlOverride(kt, 'popularMangaRequest');
  if (pop !== undefined) { config.popularUrl = pop; }
  const lat = extractUrlOverride(kt, 'latestUpdatesRequest');
  if (lat !== undefined) { config.latestUrl = lat; }

  // readcomicsonline: fully custom tailwind-styled site
  if (/h1\.text-2xl/.test(kt)) {
    config.rcoMode = true;
    config.pageSelector = '#reader-all img';
    config.dateFormat = 'd MMM yyyy';
  }

  // mangasin: ?q= search with array response, JSON latest, AES chapter list
  if (/LastedUpdateResponse/.test(kt) || /CHAPTER_DATA_REGEX/.test(kt)) {
    config.mangasinMode = true;
    config.searchParam = 'q';
    config.searchArrayResponse = true;
    config.dateFormat = 'yyyy-MM-dd HH:mm:ss';
    warnings.push('mangasin AES-encrypted chapter list not portable; using default page selectors as approximation');
  }

  // scanvf: search-directory keys are bare "/{data}"
  if (/override\s+val\s+itemPath\s*=\s*""/.test(kt)) {
    config.directoryNoItemPath = true;
  }

  // onma: extra details parsed from .panel-body h3 blocks
  if (/\.panel-body h3/.test(kt)) {
    config.onmaDetails = true;
  }

  if (/rateLimit\s*\(/.test(kt)) {
    warnings.push('rateLimit not portable; requests may be throttled by site');
  }
  if (/Deobfuscator/.test(kt)) {
    warnings.push('JS deobfuscator (synchrony) not portable; encrypted chapter fallback is approximate');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mmrcms)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_status/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- mmrcms engine ----------------
var searchDirectory = [];

var DETAIL_AUTHOR = ['author(s)', 'autor(es)', 'auteur(s)', 'yazar(lar)', 'mangaka(lar)', 'pengarang/penulis', 'pengarang', 'penulis', 'autor', 'الكمؤلف', 'перевод', 'autor/autorzy'];
var DETAIL_ARTIST = ['artist(s)', 'artiste(s)', 'sanatçi(lar)', 'artista(s)', 'artist(s)/ilustrator', 'الرسام', 'seniman', 'rysownik/rysownicy', 'artista'];
var DETAIL_GENRE = ['categories', 'categorías', 'catégories', 'kategoriler', 'categorias', 'kategorie', 'التصنيفات', 'жанр', 'kategori', 'tagi', 'género'];
var DETAIL_STATUS = ['status', 'statut', 'estado', 'durum', 'الحالة', 'статус'];
var STATUS_COMPLETE = ['complete', 'مكتملة', 'complet', 'completo', 'zakończone', 'concluído', 'finalizado'];
var STATUS_ONGOING = ['ongoing', 'مستمرة', 'en cours', 'em lançamento', 'prace w toku', 'ativo', 'em andamento', 'activo'];
var STATUS_DROPPED = ['dropped'];

function inSet(set, v) {
  var low = String(v || '').toLowerCase();
  for (var i = 0; i < set.length; i++) { if (set[i] === low) { return true; } }
  return false;
}

function imgAttr(el) {
  if (!el) { return ''; }
  var names = ['data-background-image', 'data-cfsrc', 'data-lazy-src', 'data-src'];
  for (var i = 0; i < names.length; i++) {
    var v = el.attr(names[i]);
    if (v) { return R_abs(v); }
  }
  return el.attr('src') ? R_abs(el.attr('src')) : '';
}

function guessCover(mangaUrl, url) {
  if (url && url.indexOf('no-image.png') < 0) { return url; }
  return BASE + '/uploads/manga/' + String(mangaUrl || '').split('/').pop() + '/cover/cover_250x350.jpg';
}

function parseDate(s) {
  var v = String(s || '').trim();
  if (!v) { return 0; }
  if (/^\\d{4}-\\d{2}-\\d{2}/.test(v)) {
    var t = Date.parse(v.replace(' ', 'T'));
    return isNaN(t) ? 0 : t;
  }
  var cleaned = v.replace(/\\./g, ' ').replace(/\\s+/g, ' ').trim();
  var t2 = Date.parse(cleaned);
  if (!isNaN(t2)) { return t2; }
  var m = cleaned.match(/^(\\d{1,2}) ([A-Za-z]+) (\\d{4})$/);
  if (m) {
    var t3 = Date.parse(m[2] + ' ' + m[1] + ', ' + m[3]);
    if (!isNaN(t3)) { return t3; }
  }
  return R_date(v);
}

function parseCard(el, linkSel) {
  var link = R_selFirst(el, linkSel);
  if (!link) { return null; }
  var href = link.attr('href') || link.absUrl('href');
  if (!href) { return null; }
  var key = R_path(href);
  var img = R_selFirst(el, 'img');
  return {
    key: key,
    title: link.text(),
    coverUrl: guessCover(key, img ? imgAttr(img) : '')
  };
}

function parseCards(doc, cardSel, linkSel) {
  var items = R_sel(doc, cardSel);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var c = parseCard(items[i], linkSel);
    if (c) { out.push(c); }
  }
  return out;
}

function listUrl(template, page) {
  return BASE + template.replace('{page}', String(page));
}

// ------- rco (readcomicsonline) custom parsing -------
function rcoCards(doc) {
  var items = R_sel(doc, 'div.comic-list-layout .grid > .group');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var anchor = R_selFirst(items[i], 'a.block.text-sm.font-semibold');
    if (!anchor) { continue; }
    var href = anchor.attr('href') || anchor.absUrl('href');
    if (!href) { continue; }
    var key = R_path(href);
    var img = R_selFirst(items[i], 'img');
    out.push({ key: key, title: anchor.text(), coverUrl: guessCover(key, img ? img.attr('src') : '') });
  }
  return out;
}

function rcoSearchCards(doc) {
  // equivalent of "div a:has(img)" without :has
  var anchors = R_sel(doc, 'div a');
  var out = [];
  var seen = {};
  for (var i = 0; i < anchors.length; i++) {
    var a = anchors[i];
    if (!R_selFirst(a, 'img')) { continue; }
    var href = a.attr('href') || a.absUrl('href');
    if (!href) { continue; }
    var key = R_path(href);
    if (seen[key]) { continue; }
    seen[key] = true;
    var p = R_selFirst(a, 'p');
    var img = R_selFirst(a, 'img');
    out.push({ key: key, title: p ? p.text() : '', coverUrl: img ? img.absUrl('src') : '' });
  }
  return out;
}

function rcoDetails(doc, key) {
  var title = '';
  var titleEl = R_selFirst(doc, 'h1.text-2xl');
  if (titleEl) { title = titleEl.text(); }
  var desc = '';
  var descEl = R_selFirst(doc, 'p.mt-5.text-sm');
  if (descEl) { desc = descEl.text(); }
  var status = '';
  var statusEl = R_selFirst(doc, 'div.flex.flex-wrap.gap-2 span.rounded-full');
  if (statusEl) {
    var st = statusEl.text().toLowerCase();
    if (inSet(STATUS_COMPLETE, st)) { status = 'completed'; }
    else if (inSet(STATUS_ONGOING, st)) { status = 'ongoing'; }
    else if (inSet(STATUS_DROPPED, st)) { status = 'cancelled'; }
  }
  var genres = [];
  var genreEls = R_sel(doc, 'dl div a');
  for (var i = 0; i < genreEls.length; i++) { genres.push(genreEls[i].text()); }
  var authors = [];
  var authorEls = R_sel(doc, 'div a');
  for (var j = 0; j < authorEls.length; j++) {
    var parent = authorEls[j].parentElement;
    var ptext = parent ? parent.text() : '';
    if (/Author:/i.test(ptext)) { authors.push(authorEls[j].text()); }
  }
  var img = R_selFirst(doc, 'img.w-full.rounded-xl');
  return {
    key: key,
    title: title,
    coverUrl: guessCover(key, img ? imgAttr(img) : ''),
    author: authors.join(', '),
    description: desc,
    genre: genres.join(', '),
    status: status
  };
}

// ------- default details parsing -------
function detailsFromDoc(doc, key) {
  var title = '';
  var titleEl = R_selFirst(doc, CFG.detailsTitleSelector);
  if (titleEl) { title = titleEl.text(); }
  var coverImg = R_selFirst(doc, '.row img.img-responsive');
  var desc = '';
  var well = R_selFirst(doc, '.row .well');
  if (well) {
    var h5 = R_selFirst(well, 'h5');
    desc = h5 ? (well.text().replace(h5.text(), '')) : well.text();
  }
  var author = '', artist = '', genre = '', status = '';
  var dts = R_sel(doc, '.row .dl-horizontal dt');
  for (var i = 0; i < dts.length; i++) {
    var label = dts[i].text().toLowerCase().replace(/:$/, '');
    var dd = dts[i].nextElementSibling;
    if (!dd) { continue; }
    if (inSet(DETAIL_AUTHOR, label)) { author = dd.text(); }
    else if (inSet(DETAIL_ARTIST, label)) { artist = dd.text(); }
    else if (inSet(DETAIL_GENRE, label)) {
      var as = R_sel(dd, 'a');
      var gs = [];
      for (var g = 0; g < as.length; g++) { gs.push(as[g].text()); }
      genre = gs.join(', ');
    } else if (inSet(DETAIL_STATUS, label)) {
      var sv = dd.text().toLowerCase();
      if (inSet(STATUS_COMPLETE, sv)) { status = 'completed'; }
      else if (inSet(STATUS_ONGOING, sv)) { status = 'ongoing'; }
      else if (inSet(STATUS_DROPPED, sv)) { status = 'cancelled'; }
    }
  }
  if (CFG.onmaDetails) {
    var h3s = R_sel(doc, '.panel-body h3');
    for (var k = 0; k < h3s.length; k++) {
      var lbl = (R_ownText(h3s[k]) || '').toLowerCase().replace(/\\s+:$/, '').replace(/:$/, '');
      var val = R_selFirst(h3s[k].parentElement || h3s[k], 'div.text');
      var holder = h3s[k].nextElementSibling;
      if (inSet(DETAIL_AUTHOR, lbl)) { author = holder ? holder.text() : ''; }
      else if (inSet(DETAIL_ARTIST, lbl)) { artist = holder ? holder.text() : ''; }
      else if (inSet(DETAIL_GENRE, lbl)) {
        var ga = holder ? R_sel(holder, 'a') : [];
        var gs2 = [];
        for (var g2 = 0; g2 < ga.length; g2++) { gs2.push(ga[g2].text()); }
        genre = gs2.join(', ');
      } else if (inSet(DETAIL_STATUS, lbl)) {
        var sv2 = holder ? holder.text().toLowerCase() : '';
        if (inSet(STATUS_COMPLETE, sv2)) { status = 'completed'; }
        else if (inSet(STATUS_ONGOING, sv2)) { status = 'ongoing'; }
        else if (inSet(STATUS_DROPPED, sv2)) { status = 'cancelled'; }
      }
    }
  }
  return {
    key: key,
    title: title,
    coverUrl: guessCover(key, coverImg ? imgAttr(coverImg) : ''),
    author: author,
    artist: artist,
    description: desc,
    genre: genre,
    status: status
  };
}

function chapterName(mangaTitle, rawName) {
  var name = String(rawName || '');
  var idx = name.indexOf(mangaTitle);
  if (idx === 0) {
    name = CFG.chapterString + name.substring(mangaTitle.length);
  }
  var parts = name.split(':');
  var a = (parts[0] || '').trim();
  var b = (parts[1] || '').trim();
  if (parts.length < 2 || a === b) { return a; }
  return a + ': ' + b;
}

function parseChapters(doc) {
  var sel = CFG.rcoMode ? '.overflow-hidden.border-ink-600 > a' : 'ul.chapters > li:not(.btn)';
  var els = R_sel(doc, sel);
  var mangaTitle = '';
  var titleEl = R_selFirst(doc, CFG.detailsTitleSelector);
  if (titleEl) { mangaTitle = titleEl.text(); }
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var link, dateText = '', nameText = '';
    if (CFG.rcoMode) {
      link = el;
      var nEl = R_selFirst(el, '.text-brand-400');
      nameText = nEl ? nEl.text() : el.text();
      var dEl = R_selFirst(el, '.text-slate-500');
      dateText = dEl ? dEl.text() : '';
    } else {
      var wrapper = R_selFirst(el, '.chapter-title-rtl');
      link = wrapper ? R_selFirst(wrapper, 'a') : R_selFirst(el, 'a');
      if (!link) { continue; }
      nameText = wrapper ? wrapper.text() : link.text();
      var dEl2 = R_selFirst(el, '.date-chapter-title-rtl');
      dateText = dEl2 ? dEl2.text() : '';
    }
    var href = link.attr('href') || link.absUrl('href');
    if (!href) { continue; }
    out.push({
      key: R_path(href),
      name: chapterName(mangaTitle, nameText),
      chapterNumber: -1,
      dateUpload: parseDate(dateText),
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

function parseSearchDirectory(page) {
  var start = (page - 1) * 24;
  var slice = searchDirectory.slice(start, start + 24);
  var manga = [];
  for (var i = 0; i < slice.length; i++) {
    var key = CFG.directoryNoItemPath ? '/' + slice[i].data : '/' + CFG.itemPath + '/' + slice[i].data;
    manga.push({ key: key, title: slice[i].value, coverUrl: guessCover(key, '') });
  }
  return { mangas: manga, hasNextPage: (page + 1) * 24 <= searchDirectory.length };
}

module.exports = {
  getPopularManga: async function (page) {
    if (CFG.rcoMode) {
      var text = await $.http.get(listUrl('/comic-list?sort=views&page={page}', page));
      var doc = $.html.parse(text);
      var cards = rcoCards(doc);
      var hasNext = !!R_selFirst(doc, 'nav a[rel=next]');
      return { mangas: cards, hasNextPage: hasNext };
    }
    var t = await $.http.get(listUrl(CFG.popularUrl, page));
    var d = $.html.parse(t);
    return { mangas: parseCards(d, CFG.searchSelector, CFG.searchLinkSelector), hasNextPage: !!R_selFirst(d, '.pagination a[rel=next]') };
  },

  getSearchManga: async function (page, query) {
    if (!query) { return module.exports.getPopularManga(page); }
    if (page > 1 && searchDirectory.length > 0) { return parseSearchDirectory(page); }
    if (CFG.rcoMode) {
      var rcoText = await $.http.get(BASE + '/advanced-search?name=' + encodeURIComponent(query) + '&page=' + page);
      var rcoDoc = $.html.parse(rcoText);
      return { mangas: rcoSearchCards(rcoDoc), hasNextPage: !!R_selFirst(rcoDoc, 'span a[rel=next], a[rel=next]') };
    }
    var url = BASE + '/search?' + CFG.searchParam + '=' + encodeURIComponent(query);
    var text = await $.http.get(url);
    var arr;
    try { arr = JSON.parse(text); } catch (e) { arr = null; }
    if (arr && Array.isArray(arr)) {
      searchDirectory = arr;
    } else if (arr && Array.isArray(arr.suggestions)) {
      searchDirectory = arr.suggestions;
    } else {
      // fallback: HTML response
      var doc = $.html.parse(text);
      return { mangas: parseCards(doc, CFG.searchSelector, CFG.searchLinkSelector), hasNextPage: false };
    }
    return parseSearchDirectory(page);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    if (CFG.rcoMode) { return rcoDetails(doc, mangaKey); }
    return detailsFromDoc(doc, mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    return withAscendingOrder(parseChapters(doc));
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, CFG.pageSelector);
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var u = imgAttr(els[i]);
      if (!u) { continue; }
      if (CFG.mangasinMode && /^base64:/.test(u)) {
        try {
          var b64 = u.substring(u.indexOf('://') + 3);
          u = decodeURIComponent($.crypto.base64Decode(b64));
        } catch (e) { /* keep raw */ }
      }
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
