// Keyoapp theme engine (WP + JS/Livewire heavy theme)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

function overrideStr(kt, name) {
  const re = new RegExp(`override\\s+(?:open\\s+)?(?:val|fun)\\s+${name}\\s*(?:\\(\\))?\\s*(?::\\s*String\\s*)?=\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = kt.match(re);
  if (m) return m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  return undefined;
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    popularSelectors: [],
    searchPath: '/series',
    searchQParam: 'q',
    searchPageParam: '',
    searchThreshold: 0,
    searchSelector: '#searched_series_page > button',
    popularViaSearch: false,
    statusSelector: '',
    authorSelector: '',
    artistSelector: '',
    typeSelector: '',
    altNameSelector: 'div.font-medium:containsOwn(Alternative titles) ~ div span',
    genreSelector: "a[href*='genre=']",
    descriptionSelector: '#expand_content p',
    dateSelector: '.text-xs',
    showPaidChapters: false,
  };

  const popularSel = overrideStr(kt, 'popularMangaSelector');
  if (popularSel) { config.popularSelectors.push(popularSel); }
  config.popularSelectors.push('.group.overflow-hidden.grid', '.series-splide .splide__slide', 'div.grid > div.group', '.group.overflow-hidden');

  const searchSel = overrideStr(kt, 'searchMangaSelector');
  if (searchSel) { config.searchSelector = searchSel; }

  // searchUrlBuilder overrides (livewire /search variants)
  if (/searchUrlBuilder[\s\S]{0,400}?basename\.search"|searchUrlBuilder[\s\S]{0,400}?\$baseUrl\/search"/.test(kt)) {
    config.searchPath = '/search';
    if (/addQueryParameter\(\s*"title"/.test(kt)) { config.searchQParam = 'title'; }
    if (/addQueryParameter\(\s*"page"/.test(kt)) { config.searchPageParam = 'page'; }
    const thr = kt.match(/hasNextPage\s*=\s*mangas\.size\s*>=\s*(\d+)/);
    if (thr) { config.searchThreshold = parseInt(thr[1], 10); }
  }

  if (/getPopularManga\(page: Int\)\s*=\s*getSearchMangaList/.test(kt)) {
    config.popularViaSearch = true;
  }

  for (const name of ['statusSelector', 'authorSelector', 'artistSelector', 'typeSelector', 'altNameSelector', 'genreSelector', 'descriptionSelector', 'dateSelector']) {
    const v = overrideStr(kt, name);
    if (v !== undefined) { config[name] = v; }
  }

  if (/OLD_CHAPTER_SLUG_REGEX/.test(kt)) {
    warnings.push('legacy id-slug URL rewrite (asmotoon) not portable; old URLs may 404');
  }
  if (/immersiveReader/.test(kt)) {
    warnings.push('livewire immersiveReader page parse approximated');
  }
  if (/rateLimit\(/.test(kt)) {
    warnings.push('rate limiter not portable');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: keyoapp)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_* helpers)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- keyoapp engine ----------------
function bgImageUrl(el) {
  if (!el) { return ''; }
  var style = el.attr('style') || '';
  var m = style.match(/url\\(['"]?([^'")]+)/);
  if (!m) { return ''; }
  var u = R_abs(m[1]);
  try {
    var uu = new URL(u);
    uu.searchParams.set('w', '480');
    return uu.href;
  } catch (e) { return u; }
}

function isNovel(el) {
  if ((el.attr('data-type') || '').toLowerCase() === 'novel') { return true; }
  var spans = R_sel(el, 'span');
  for (var i = 0; i < spans.length; i++) {
    if (spans[i].text().trim().toLowerCase() === 'novel') { return true; }
  }
  return false;
}

function cardFrom(el) {
  var a = R_selFirst(el, 'a[href]') || el;
  var href = a.absUrl('href') || el.absUrl('href');
  if (!href) { return null; }
  var title = (a.attr('title') || el.attr('title') || a.text() || '').trim();
  var bg = R_selFirst(el, '[style*=background-image]');
  var cover = bg ? bgImageUrl(bg) : '';
  return { key: R_path(href), title: title, coverUrl: cover };
}

async function doSearch(page, query) {
  var url = BASE + CFG.searchPath;
  var qs = [];
  if (query) { qs.push(CFG.searchQParam + '=' + encodeURIComponent(query)); }
  if (CFG.searchPageParam && page > 1) { qs.push(CFG.searchPageParam + '=' + page); }
  if (qs.length > 0) { url += '?' + qs.join('&'); }
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var els = R_sel(doc, CFG.searchSelector);
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    if (isNovel(el)) { continue; }
    var m = cardFrom(el);
    if (!m || !m.key) { continue; }
    if (query && m.title.toLowerCase().indexOf(query.toLowerCase()) < 0) { continue; }
    out.push(m);
  }
  var hasNext = CFG.searchThreshold > 0 && out.length >= CFG.searchThreshold;
  return { mangas: out, hasNextPage: hasNext };
}

function fieldByLabel(doc, label) {
  var rows = R_sel(doc, 'div.w-full.flex-wrap > div');
  for (var i = 0; i < rows.length; i++) {
    var inner = $.html.parse('<div id="row">' + rows[i].html() + '</div>');
    var cells = R_sel(inner, '#row > div');
    if (cells.length < 2) { continue; }
    var lab = cells[0].text().toLowerCase();
    if (lab.indexOf(label) >= 0) { return cells[cells.length - 1].text().trim(); }
  }
  return '';
}

function pickField(doc, selector, label) {
  if (selector) {
    var el = R_selFirst(doc, selector);
    if (el) { return el.text().trim(); }
  }
  return fieldByLabel(doc, label);
}

function parseDetails(doc, key) {
  var title = '';
  var tEl = R_selFirst(doc, 'div.grid > h1') || R_selFirst(doc, 'h1');
  if (tEl) { title = tEl.text(); }
  var coverEl = R_selFirst(doc, 'div[class*=photoURL], div[style*=photoURL]') || R_selFirst(doc, '[style*=background-image]');
  var cover = bgImageUrl(coverEl);
  var statusRaw = pickField(doc, CFG.statusSelector, 'status');
  var status = '';
  var sl = statusRaw.toLowerCase();
  if (sl === 'dropped') { status = 'cancelled'; }
  else if (sl === 'paused') { status = 'hiatus'; }
  else { status = R_status(sl); }
  var author = pickField(doc, CFG.authorSelector, 'author');
  var artist = pickField(doc, CFG.artistSelector, 'artist');
  var type = pickField(doc, CFG.typeSelector, 'type');
  var genres = [];
  if (type) { genres.push(type.charAt(0).toUpperCase() + type.slice(1)); }
  var gEls = R_sel(doc, CFG.genreSelector);
  for (var i = 0; i < gEls.length; i++) {
    var g = gEls[i].text().trim().replace(/^[,\\s]+|[,\\s]+$/g, '');
    if (g) { genres.push(g); }
  }
  var desc = '';
  var dEl = R_selFirst(doc, CFG.descriptionSelector);
  if (dEl) { desc = dEl.text(); }
  var altEls = R_sel(doc, CFG.altNameSelector);
  var alts = [];
  for (var j = 0; j < altEls.length; j++) {
    var t = altEls[j].text();
    if (t && t !== 'No alternative titles.') { alts.push(t); }
  }
  if (alts.length > 0) {
    if (desc) { desc += '\\n\\n'; }
    desc += 'Alternative Titles:\\n- ' + alts.join('\\n- ');
  }
  return {
    key: key,
    title: title,
    coverUrl: cover,
    author: author,
    artist: artist,
    description: desc,
    genre: genres.join(', '),
    status: status
  };
}

function isPaidChapter(el) {
  var imgs = R_sel(el, 'img');
  for (var i = 0; i < imgs.length; i++) {
    if (/coin/i.test(imgs[i].attr('alt') || '')) { return true; }
    if ((imgs[i].attr('src') || '').indexOf('star-circle') >= 0) { return true; }
  }
  return false;
}

function findCdn(doc) {
  var scripts = R_sel(doc, 'script');
  for (var i = 0; i < scripts.length; i++) {
    var h = scripts[i].html() || '';
    var m = h.match(/realUrl\\s*=\\s*\\x60[^\\x60]+\\/\\/([^\\/\\x60]+)/);
    if (m) {
      var host = m[1].replace(/\\$\\{[^}]*\\}/g, '');
      return 'https://' + host + '/uploads';
    }
  }
  return '';
}

function extractPagesJson(xData) {
  var raw = '';
  var m = xData.match(/JSON\\.parse\\('([\\s\\S]*?)'\\)/);
  if (m) { raw = m[1]; }
  if (!raw) {
    var pi = xData.indexOf('pages:');
    if (pi < 0) { return null; }
    var after = xData.slice(pi + 6).replace(/^\\s+/, '');
    if (after.charAt(0) !== '[') { return null; }
    var depth = 0;
    for (var i = 0; i < after.length; i++) {
      if (after.charAt(i) === '[') { depth++; }
      else if (after.charAt(i) === ']') {
        depth--;
        if (depth === 0) { raw = after.slice(0, i + 1); break; }
      }
    }
  }
  if (!raw) { return null; }
  var parsed = null;
  try { parsed = JSON.parse(raw); } catch (e) {
    try { parsed = JSON.parse(JSON.parse('"' + raw + '"')); } catch (e2) {
      try { parsed = JSON.parse(raw.replace(/\\\\"/g, '"').replace(/\\\\\\\\/g, '\\\\')); } catch (e3) { parsed = null; }
    }
  }
  return parsed;
}

module.exports = {
  getPopularManga: async function (page) {
    if (CFG.popularViaSearch) { return doSearch(page, ''); }
    var text = await $.http.get(BASE + '/');
    var doc = $.html.parse(text);
    var out = [];
    var seen = {};
    for (var s = 0; s < CFG.popularSelectors.length; s++) {
      var els = R_sel(doc, CFG.popularSelectors[s]);
      for (var i = 0; i < els.length; i++) {
        if (isNovel(els[i])) { continue; }
        var m = cardFrom(els[i]);
        if (m && m.key && !seen[m.key]) { seen[m.key] = 1; out.push(m); }
      }
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    return doSearch(page, query || '');
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    return parseDetails(doc, mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, '#chapters > a, #chapters > div');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var ups = R_sel(el, '.text-sm span');
      var upcoming = false;
      for (var u = 0; u < ups.length; u++) {
        if (/upcoming/i.test(ups[u].text())) { upcoming = true; break; }
      }
      if (upcoming) { continue; }
      if (!CFG.showPaidChapters && isPaidChapter(el)) { continue; }
      var link = el.attr('href') ? el : R_selFirst(el, 'a[href]');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var nameEl = R_selFirst(el, '.text-sm');
      var name = nameEl ? nameEl.text() : (link.attr('title') || link.attr('alt') || link.text());
      var num = -1;
      var nm = name.match(/(\\d+(?:[.]\\d+)?)/);
      if (nm) { num = parseFloat(nm[1]); }
      var dateEl = R_selFirst(el, CFG.dateSelector);
      out.push({
        key: R_path(href),
        name: name,
        chapterNumber: num,
        dateUpload: dateEl ? R_date(dateEl.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // legacy-layout fallback: no #chapters container; collect links under the series path
    if (out.length === 0) {
      var slug = String(mangaKey).replace(/\\/+$/, '').split('/').pop() || '';
      var anchors = R_sel(doc, 'a[href*="chapter"]');
      var seenCh = {};
      for (var a2 = 0; a2 < anchors.length; a2++) {
        var an = anchors[a2];
        var ah = an.absUrl('href');
        if (!ah) { continue; }
        var ap = R_path(ah);
        if (!/chapter/i.test(ap)) { continue; }
        var belongs = ap.indexOf(String(mangaKey).replace(/\\/+$/, '') + '/chapter') === 0 ||
          (slug && ap.indexOf(slug + '-chapter') >= 0) ||
          (slug && ap.indexOf('/' + slug + '/') >= 0 && ap !== String(mangaKey));
        if (!belongs) { continue; }
        var atext = an.text().replace(/\\s+/g, ' ').trim();
        if (!CFG.showPaidChapters && /coins?/i.test(atext)) { continue; }
        var ckey = ap;
        if (seenCh[ckey]) { continue; }
        seenCh[ckey] = 1;
        var cnm = atext.match(/chapter\\s*\\d+(?:[.]\\d+)?/i);
        var cname = cnm ? cnm[0].replace(/\\s+/g, ' ') : (atext.slice(0, 60) || 'Chapter');
        var cnum = -1;
        var chn = ckey.match(/chapter[-\\/(\\s]*(\\d+(?:[.]\\d+)?)/i);
        if (chn) { cnum = parseFloat(chn[1]); }
        if (cnum >= 0 && !cnm) { cname = 'Chapter ' + cnum; }
        var cdate = atext.match(/(\\d{1,2}\\/\\d{1,2}\\/\\d{2,4})/);
        out.push({
          key: ckey,
          name: cname,
          chapterNumber: cnum,
          dateUpload: cdate ? R_date(cdate[1]) : 0,
          pages: 0,
          sortOrder: 0
        });
      }
      // numeric sort when every fallback entry parsed a number (chapter 0 prologues first)
      var allNum = out.length > 0;
      for (var s2 = 0; s2 < out.length; s2++) { if (!(out[s2].chapterNumber >= 0)) { allNum = false; break; } }
      if (allNum) {
        out.sort(function (x1, x2) { return x1.chapterNumber - x2.chapterNumber; });
        for (var s3 = 0; s3 < out.length; s3++) { out[s3].sortOrder = s3; }
        return out;
      }
    }
    // site lists newest first -> normalize to oldest-first
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    // livewire immersiveReader variant
    var xds = R_sel(doc, '[x-data]');
    for (var x = 0; x < xds.length; x++) {
      var attrVal = xds[x].attr('x-data') || '';
      if (attrVal.indexOf('immersiveReader') < 0) { continue; }
      var cr = attrVal.match(/canRead\\s*:\\s*(true|false)/);
      var pagesJson = extractPagesJson(attrVal);
      if (cr && cr[1] === 'false' && (!pagesJson || !pagesJson.length)) {
        throw new Error('chapter locked (login via WebView required)');
      }
      if (pagesJson && pagesJson.length) {
        var bl = attrVal.match(/baseLink\\s*:\\s*['"]([^'"]+)['"]/);
        var baseL = bl ? bl[1] : BASE + '/storage/';
        var pages = [];
        for (var p = 0; p < pagesJson.length; p++) {
          var path = pagesJson[p] && pagesJson[p].path ? pagesJson[p].path : '';
          if (!path) { continue; }
          var u = /^https?:\\/\\//.test(path) ? path : baseL.replace(/\\/+$/, '') + '/' + path.replace(/^\\/+/, '');
          pages.push({ index: pages.length, url: u });
        }
        if (pages.length > 0) { return pages; }
      }
    }
    // default keyoapp method
    var imgs = R_sel(doc, '#pages > img');
    var cdn = findCdn(doc);
    var uidPages = [];
    for (var i = 0; i < imgs.length; i++) {
      var uid = imgs[i].attr('uid');
      if (uid) { uidPages.push(cdn ? cdn + '/' + uid : ''); }
    }
    if (uidPages.length > 0 && cdn) {
      var out2 = [];
      for (var j = 0; j < uidPages.length; j++) { out2.push({ index: j, url: uidPages[j] }); }
      return out2;
    }
    // fallback: old cdn urls
    var oldPages = [];
    for (var k = 0; k < imgs.length; k++) {
      var src = imgs[k].attr('data-lazy-src') || imgs[k].attr('data-src') || imgs[k].attr('src');
      if (src && /cdn\\d*\\.keyoapp\\.com/.test(src)) { oldPages.push(R_abs(src)); }
    }
    if (oldPages.length > 0) {
      var out3 = [];
      for (var n = 0; n < oldPages.length; n++) { out3.push({ index: n, url: oldPages[n] }); }
      return out3;
    }
    // legacy chapter layout: plain page images with direct src
    var legacy = [];
    var allImgs = R_sel(doc, 'img');
    for (var g = 0; g < allImgs.length; g++) {
      var im = allImgs[g];
      var alt = im.attr('alt') || '';
      var isrc = im.attr('src') || '';
      if (!isrc) { continue; }
      var altPage = /^page\\s*\\d+$/i.test(alt.trim());
      var srcPage = /\\.(jpe?g|png|webp|avif|gif)(\\?|$)/i.test(isrc) && /p-\\d+|pages?|ch-?\\d+|chapters?|storage/i.test(isrc);
      if (altPage || srcPage) { legacy.push(R_abs(isrc)); }
    }
    if (legacy.length > 0) {
      var out4 = [];
      for (var r = 0; r < legacy.length; r++) { out4.push({ index: r, url: legacy[r] }); }
      return out4;
    }
    throw new Error('no pages found (chapter may require login)');
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
