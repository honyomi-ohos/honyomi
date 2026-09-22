// GigaViewer theme engine (Hatena GigaViewer: Shueisha/Shogakukan etc.)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

function overrideStr(kt, name) {
  const re = new RegExp(`(?:override\\s+)?(?:protected\\s+)?(?:open\\s+)?(?:val|fun)\\s+${name}\\s*(?:\\(\\))?\\s*(?::\\s*String\\s*)?(?:\\?\\s*)?=\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = kt.match(re);
  if (m) return m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  return undefined;
}

// extract the triple (titleSelector/titleAttr, thumbSelector+attr, urlSelector) from a *FromElement body
function extractItemPatterns(kt, fnName) {
  const idx = kt.indexOf(`${fnName}(element: Element)`);
  if (idx < 0) return null;
  const body = kt.slice(idx, idx + 900);
  const item = { titleSelector: '', titleAttr: '', thumbSelector: '', thumbAttr: '', urlSelector: '', thumbReplace: [] };

  let m = body.match(/title\s*=\s*(?:element|link)\.attr\("([^"]+)"\)/);
  if (m) { item.titleAttr = m[1]; }
  m = body.match(/title\s*=\s*(?:element|link)\.selectFirst\("([^"]+)"\)/);
  if (m) { item.titleSelector = m[1]; }

  m = body.match(/thumbnail_url\s*=\s*(?:element|link)\.selectFirst\("([^"]+)"\)\?\.(?:absUrl|attr)\("([^"]+)"\)/);
  if (m) { item.thumbSelector = m[1]; item.thumbAttr = m[2]; }

  let rm;
  const rre = /\.replace\("\{(\w+)\}",\s*"(\d+)"\)/g;
  while ((rm = rre.exec(body)) !== null) { item.thumbReplace.push([rm[1], rm[2]]); }

  m = body.match(/setUrlWithoutDomain\(element\.selectFirst\("([^"]+)"\)!!\.absUrl\("href"\)\)/);
  if (m) { item.urlSelector = m[1]; }
  else if (/setUrlWithoutDomain\(element\.absUrl\("href"\)\)/.test(body)) { item.urlSelector = ''; }
  else if (/setUrlWithoutDomain\(link\.absUrl\("href"\)\)/.test(body)) { item.urlSelector = 'a'; }
  return item;
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];

  if (/graphQLPost|parseGraphQLAs/.test(kt)) {
    warnings.push('GraphQL-based listing (site redesigned); HTML fallback may not work');
  }

  const config = {
    popularPath: '/series',
    popularSelector: 'ul.series-list li a',
    popularTitleSelector: 'h2.series-list-title',
    popularTitleAttr: '',
    popularThumbSelector: 'div.series-list-thumb img',
    popularThumbAttr: 'data-src',
    popularThumbReplace: [],
    popularUrlSelector: '',
    searchSelector: 'ul.search-series-list li, ul.series-list li',
    searchTitleSelector: 'div.title-box p.series-title',
    searchThumbSelector: 'div.thmb-container a img',
    searchThumbAttr: 'src',
    searchUrlSelector: 'div.thmb-container a',
    searchNextPageSelector: '',
    searchSupported: true,
  };

  const prm = kt.match(/popularMangaRequest\(page: Int\): Request = GET\("([^"]*)"/);
  if (prm) {
    let p = prm[1].replace(/\$baseUrl/, '');
    if (p === '') p = '/';
    config.popularPath = p;
  }

  const popularSel = overrideStr(kt, 'popularMangaSelector');
  if (popularSel) { config.popularSelector = popularSel; }
  const item = extractItemPatterns(kt, 'popularMangaFromElement');
  if (item) {
    if (item.titleSelector) config.popularTitleSelector = item.titleSelector;
    if (item.titleAttr) { config.popularTitleAttr = item.titleAttr; config.popularTitleSelector = ''; }
    if (item.thumbSelector) config.popularThumbSelector = item.thumbSelector;
    if (item.thumbAttr) config.popularThumbAttr = item.thumbAttr;
    if (item.thumbReplace.length) config.popularThumbReplace = item.thumbReplace;
    config.popularUrlSelector = item.urlSelector;
  }

  const searchSel = overrideStr(kt, 'searchMangaSelector');
  if (searchSel) { config.searchSelector = searchSel; }
  const sItem = extractItemPatterns(kt, 'searchMangaFromElement');
  if (sItem) {
    if (sItem.titleSelector) config.searchTitleSelector = sItem.titleSelector;
    if (sItem.titleAttr) { config.searchTitleAttr = sItem.titleAttr; config.searchTitleSelector = ''; }
    if (sItem.thumbSelector) config.searchThumbSelector = sItem.thumbSelector;
    if (sItem.thumbAttr) config.searchThumbAttr = sItem.thumbAttr;
    if (sItem.urlSelector !== undefined) config.searchUrlSelector = sItem.urlSelector;
  }
  if (!config.searchTitleAttr) config.searchTitleAttr = '';

  const snp = overrideStr(kt, 'searchMangaNextPageSelector');
  if (snp) { config.searchNextPageSelector = snp; }

  if (/searchMangaRequest\(page: Int[^)]*\)[\s\S]{0,60}= throw UnsupportedOperationException/.test(kt)) {
    config.searchSupported = false;
    warnings.push('search not supported by source; search falls back to popular filtered by title');
  }

  if (/choJuGiga|ImageInterceptor/.test(kt)) {
    warnings.push('scrambled (baku) images cannot be unscrambled in-plugin');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: gigaviewer)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_* helpers)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- gigaviewer engine ----------------
function gvHeaders(referer) {
  return { 'Referer': referer || BASE + '/', 'Origin': BASE };
}

function gvItem(el, m) {
  var link = el;
  if (m.urlSelector) {
    var l2 = R_selFirst(el, m.urlSelector);
    if (l2) { link = l2; }
  }
  var href = (link && link.absUrl('href')) || el.absUrl('href') || '';
  if (!href) {
    var la = R_selFirst(el, 'a');
    href = la ? la.absUrl('href') : '';
  }
  if (!href) { return null; }
  var title = '';
  if (m.titleAttr) {
    title = el.attr(m.titleAttr) || (link !== el ? link.attr(m.titleAttr) : '') || '';
  }
  if (!title && m.titleSelector) {
    var tEl = R_selFirst(el, m.titleSelector);
    if (!tEl && link !== el) { tEl = R_selFirst(link, m.titleSelector); }
    title = tEl ? tEl.text() : '';
  }
  var thumb = '';
  if (m.thumbSelector) {
    var imgEl = R_selFirst(el, m.thumbSelector);
    if (imgEl) {
      thumb = imgEl.absUrl(m.thumbAttr) || '';
      if (!thumb) { thumb = imgEl.absUrl('data-src') || imgEl.absUrl('src') || ''; }
    }
  }
  if (!thumb) {
    var imgs = R_sel(el, 'img');
    for (var i = 0; i < imgs.length; i++) {
      thumb = imgs[i].absUrl('data-src') || imgs[i].absUrl('src') || imgs[i].absUrl('data-lazy-src') || '';
      if (thumb) { break; }
    }
    if (!thumb) {
      var hm = (el.html() || '').match(/<img[^>]+src="([^"]+)"/);
      if (hm) { thumb = R_abs(hm[1]); }
    }
  }
  for (var r = 0; r < m.thumbReplace.length; r++) {
    thumb = thumb.split('{' + m.thumbReplace[r][0] + '}').join(m.thumbReplace[r][1]);
  }
  return { key: R_path(href), title: title.trim(), coverUrl: R_abs(thumb) };
}

var POP = {
  titleSelector: CFG.popularTitleSelector, titleAttr: CFG.popularTitleAttr,
  thumbSelector: CFG.popularThumbSelector, thumbAttr: CFG.popularThumbAttr,
  thumbReplace: CFG.popularThumbReplace, urlSelector: CFG.popularUrlSelector
};
var SRCH = {
  titleSelector: CFG.searchTitleSelector, titleAttr: CFG.searchTitleAttr,
  thumbSelector: CFG.searchThumbSelector, thumbAttr: CFG.searchThumbAttr,
  thumbReplace: [], urlSelector: CFG.searchUrlSelector
};

async function fetchChapterPage(type, aggregateId, offset, referer) {
  var url = BASE + '/api/viewer/pagination_readable_products?type=' + type +
    '&aggregate_id=' + encodeURIComponent(aggregateId) +
    '&sort_order=desc&offset=' + offset;
  var text = await $.http.get(url, gvHeaders(referer));
  var data;
  try { data = JSON.parse(text); } catch (e) { data = []; }
  return Array.isArray(data) ? data : [];
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + CFG.popularPath, gvHeaders());
    var doc = $.html.parse(text);
    var els = R_sel(doc, CFG.popularSelector);
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var m = gvItem(els[i], POP);
      if (m && m.key && m.title) { out.push(m); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    if (!CFG.searchSupported || !query) {
      var pop = await module.exports.getPopularManga(page);
      if (query) {
        var filtered = [];
        for (var f = 0; f < pop.mangas.length; f++) {
          if (pop.mangas[f].title.toLowerCase().indexOf(query.toLowerCase()) >= 0) { filtered.push(pop.mangas[f]); }
        }
        pop.mangas = filtered;
      }
      pop.hasNextPage = false;
      return pop;
    }
    var url = BASE + '/search?q=' + encodeURIComponent(query);
    if (page > 1) { url += '&page=' + page; }
    var text;
    try {
      text = await $.http.get(url, gvHeaders());
    } catch (e) {
      return { mangas: [], hasNextPage: false };
    }
    var doc = $.html.parse(text);
    var els = R_sel(doc, CFG.searchSelector);
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var m = gvItem(els[i], SRCH);
      if (m && m.key && m.title) { out.push(m); }
    }
    var hasNext = false;
    if (CFG.searchNextPageSelector) { hasNext = !!R_selFirst(doc, CFG.searchNextPageSelector); }
    return { mangas: out, hasNextPage: hasNext };
  },

  getMangaDetail: async function (mangaKey) {
    var url = R_abs(mangaKey);
    var text = await $.http.get(url, gvHeaders());
    var doc = $.html.parse(text);
    var info = R_selFirst(doc, 'section.series-information div.series-header');
    var title = '';
    var author = '';
    var desc = '';
    var cover = '';
    if (info) {
      var tEl = R_selFirst(info, 'h1.series-header-title');
      title = tEl ? tEl.text() : '';
      var aEl = R_selFirst(info, 'h2.series-header-author');
      author = aEl ? aEl.text() : '';
      var dEl = R_selFirst(info, 'p.series-header-description');
      desc = dEl ? dEl.text() : '';
      var imgEl = R_selFirst(info, 'div.series-header-image-wrapper img');
      cover = imgEl ? (imgEl.absUrl('data-src') || imgEl.absUrl('src')) : '';
    }
    if (!title) {
      var h1 = R_selFirst(doc, 'h1');
      title = h1 ? h1.text() : mangaKey;
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: author,
      description: desc,
      genre: '',
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var url = R_abs(mangaKey);
    var text = await $.http.get(url, gvHeaders());
    var doc = $.html.parse(text);
    var valve = R_selFirst(doc, 'script.js-valve');
    var aggregateId = valve ? valve.attr('data-giga_series') : '';
    if (!aggregateId) {
      var pag = R_selFirst(doc, '.js-readable-products-pagination');
      aggregateId = pag ? pag.attr('data-aggregate-id') : '';
    }
    if (!aggregateId) { throw new Error('aggregate id not found'); }
    var episodes = [];
    var volumes = [];
    for (var t = 0; t < 2; t++) {
      var type = t === 0 ? 'episode' : 'volume';
      var offset = 0;
      var collected = [];
      while (true) {
        var batch = await fetchChapterPage(type, aggregateId, offset, url);
        if (!batch.length) { break; }
        for (var i = 0; i < batch.length; i++) { collected.push(batch[i]); }
        offset += batch.length;
        if (batch.length < 5 && offset > 500) { break; }
      }
      for (var c = 0; c < collected.length; c++) {
        var ch = collected[c];
        if (!ch || !ch.readable_product_id) { continue; }
        var label = ch.status && ch.status.label ? ch.status.label : '';
        var prefix = '';
        if (label === 'unpublished') { prefix = '\\uD83D\\uDD12 '; }
        else if (label === 'is_rentable' || label === 'is_purchasable' || label === 'is_rentable_and_subscribable') { prefix = '\\uD83D\\uDCB4 '; }
        var volPrefix = type === 'volume' ? '(Volume) ' : '';
        var name = prefix + volPrefix + (ch.title || '');
        var date = ch.display_open_at ? R_date(ch.display_open_at) : 0;
        var key = '/' + type + '/' + ch.readable_product_id;
        var num = -1;
        var nm = String(name).match(/(\\d+(?:[.]\\d+)?)/);
        if (nm) { num = parseFloat(nm[1]); }
        (type === 'volume' ? volumes : episodes).push({
          key: key, name: name, chapterNumber: num,
          dateUpload: date, pages: 0, sortOrder: 0
        });
      }
    }
    // api returns desc (newest first): episodes then volumes.
    // oldest-first == exact reverse of upstream order: volumes asc then episodes asc.
    episodes.reverse();
    volumes.reverse();
    var all = volumes.concat(episodes);
    for (var k = 0; k < all.length; k++) { all[k].sortOrder = k; }
    return all;
  },

  getPageList: async function (chapterKey) {
    var url = R_abs(chapterKey);
    var text = await $.http.get(url, gvHeaders());
    var doc = $.html.parse(text);
    var scriptEl = R_selFirst(doc, 'script#episode-json');
    if (!scriptEl) { throw new Error('episode json not found (chapter may be unavailable)'); }
    var raw = scriptEl.attr('data-value');
    var data;
    try { data = JSON.parse(raw); } catch (e) { throw new Error('episode json parse failed'); }
    var structure = data && data.readableProduct ? data.readableProduct.pageStructure : null;
    if (!structure || !structure.pages || !structure.pages.length) {
      throw new Error('chapter is either unavailable or must be purchased');
    }
    var pages = [];
    for (var i = 0; i < structure.pages.length; i++) {
      var p = structure.pages[i];
      if (p && p.type === 'main' && p.src) {
        pages.push({ index: pages.length, url: p.src });
      }
    }
    if (pages.length === 0) { throw new Error('no readable pages'); }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/', Origin: BASE };
  }
};
`;
}
