// GalleryAdults theme engine (asmhentai, hentaienvy, hentaiera, hentaifox, hentairox,
// hentaizap, imhentai, nhentaito, nhentaixxx)
// HTML galleries: language-filtered lists, per-site info rows, parseJSON/thumbs page extraction.
export const runtime = 'wp';

const LANG_MAP = {
  en: 'english', ja: 'japanese', zh: 'chinese', ko: 'korean',
  es: 'spanish', fr: 'french', de: 'german', ru: 'russian', all: '',
};

function extractStr(kt, re) {
  const m = kt.match(re);
  return m ? m[1] : undefined;
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const extName = ctx.extName;
  const gradleLang = (ctx.gradle && ctx.gradle.sources && ctx.gradle.sources[0] ? ctx.gradle.sources[0].lang : 'all') || 'all';
  const mangaLang = LANG_MAP[gradleLang] !== undefined ? LANG_MAP[gradleLang] : '';
  const warnings = [];

  const config = {
    mangaLang,
    popularSelector: 'div.thumb',
    titleSelector: '.caption',
    urlSelector: '.inner_thumb a',
    thumbSelector: '.inner_thumb img',
    nextSelector: '.pagination li.active + li:not(.disabled), a[rel=next]',
    infoStyle: 'base',
    detailSelector: '.gallery_top',
    coverSelector: '.cover img',
    idPrefixUri: 'gallery',
    pageUri: 'g',
    pagesRequest: 'inc/thumbs_loader.php',
    formStyle: 'base',
    thumbnailSelector: '.gallery_thumb',
    serverPrefix: 'm',
    galleryIdStyle: 'input',
    totalPagesStyle: 'input',
    pageByPage: false,
    parseJsonStyle: 'base',
    dateStyle: 'uploaded',
    intermediateSearch: false,
    basicSearchKey: 'q',
    queryStyle: 'comma',
    pageUriStyle: 'base',
    searchStyle: 'base',
    langFilterStyle: 'none',
    langAttrMode: 'contains',
    langCodes: {},
    flagClass: '',
  };

  // --- selectors ---
  let v;
  v = extractStr(kt, /popularMangaSelector\(\)\s*=\s*"([^"]+)"/); if (v) { config.popularSelector = v; }
  v = extractStr(kt, /mangaTitleSelector\s*=\s*"([^"]+)"/); if (v) { config.titleSelector = v; }
  v = extractStr(kt, /fun Element\.mangaUrl\(\)\s*=\s*selectFirst\("([^"]+)"\)/); if (v) { config.urlSelector = v; }
  if (/Element\.mangaUrl\(\)\s*=\s*absUrl\("href"\)/.test(kt)) { config.urlSelector = '@self'; }
  v = extractStr(kt, /fun Element\.mangaThumbnail\(\)\s*=\s*selectFirst\("([^"]+)"/); if (v) { config.thumbSelector = v; }
  v = extractStr(kt, /popularMangaNextPageSelector\(\)(?::\s*String\?)?\s*=\s*"([^"]+)"/); if (v) { config.nextSelector = v; }
  v = extractStr(kt, /mangaDetailInfoSelector\s*=\s*"([^"]+)"/); if (v) { config.detailSelector = v; }
  v = extractStr(kt, /fun Element\.getCover\(\)\s*=\s*selectFirst\("([^"]+)"/); if (v) { config.coverSelector = v; }
  v = extractStr(kt, /idPrefixUri\s*=\s*"([^"]+)"/); if (v) { config.idPrefixUri = v; }
  v = extractStr(kt, /\bpageUri\s*=\s*"([^"]+)"/); if (v) { config.pageUri = v; }
  v = extractStr(kt, /pagesRequest\s*=\s*"([^"]+)"/); if (v) { config.pagesRequest = v; }
  v = extractStr(kt, /thumbnailSelector\s*=\s*"([^"]+)"/); if (v) { config.thumbnailSelector = v; }
  v = extractStr(kt, /serverPrefix\s*=\s*"([^"]+)"/); if (v) { config.serverPrefix = v; }

  // --- info style ---
  const infoSel = extractStr(kt, /getInfoSelector\(tag: String\)\s*=\s*"([^"]+)"/) || '';
  if (infoSel.indexOf('.tag_list') >= 0) { config.infoStyle = 'asm'; }
  else if (/ul\.\$\{tag\.lowercase\(\)\}/.test(infoSel)) { config.infoStyle = 'fox'; }
  else if (infoSel.indexOf('li:has(.tags_text') >= 0) {
    config.infoStyle = /\.item_name/.test(kt) ? 'rox' : 'imhentai';
  }
  else if (infoSel.indexOf('hnv-gallery-entity-group') >= 0) { config.infoStyle = 'envy'; }
  else if (infoSel.indexOf('hz-gallery-entity-group') >= 0) { config.infoStyle = 'zap'; }
  else if (infoSel.indexOf('#info-block .field-name') >= 0) { config.infoStyle = 'nhentaito'; }
  else if (infoSel.indexOf('a.tag_btn') >= 0) { config.infoStyle = 'nhentaixxx'; }

  // --- pages ---
  if (/fun pageRequestForm[\s\S]*?\.add\("id",/.test(kt)) { config.formStyle = 'asm'; }
  if (/fun Element\.galleryId\(\)\s*=\s*select\("\[data-gallery-id\]"/.test(kt)) { config.galleryIdStyle = 'data-attr'; }
  if (/fun Element\.totalPages\(\)\s*=\s*select\("\[data-total-pages\]"/.test(kt)) { config.totalPagesStyle = 'data-attr'; }
  if (/fun Element\.totalPages\(\)\s*=\s*getInfo\("Pages"\)/.test(kt)) { config.totalPagesStyle = 'info-pages'; }
  if (/parsingImagePageByPage\s*=\s*true/.test(kt)) { config.pageByPage = true; }
  if (/parseJSON\('\{"fl":'/.test(kt)) { config.parseJsonStyle = 'fl'; }

  // --- dates ---
  if (/\.pages:contains\(Posted:\)/.test(kt)) { config.dateStyle = 'fox'; }
  else if (/fun Element\.getTime\(\): Long = selectFirst\("\.tags time"\)/.test(kt)) { config.dateStyle = 'nhentaito'; }

  // --- search ---
  if (/useIntermediateSearch(: Boolean)? = true/.test(kt)) { config.intermediateSearch = true; }
  v = extractStr(kt, /basicSearchKey\s*=\s*"([^"]+)"/); if (v) { config.basicSearchKey = v; }
  if (/regexSpecialCharacters/.test(kt)) { config.queryStyle = 'plus-lang'; }
  if (/fun basicSearchUrl\(/.test(kt)) { config.searchStyle = 'nhentaito'; }
  if (/\/pag\/\$page\//.test(kt)) { config.pageUriStyle = 'fox'; }

  // --- language filter ---
  if (/attr\("data-languages"\)/.test(kt)) {
    config.langFilterStyle = 'attr';
    if (extName === 'nhentaixxx') { config.langAttrMode = 'exact'; }
    const codes = {};
    const langRe = /Pair\(LANGUAGE_(\w+), "(\d+)"\)/g;
    let lm;
    while ((lm = langRe.exec(kt)) !== null) {
      codes[lm[1].toLowerCase()] = lm[2];
    }
    config.langCodes = codes;
  } else {
    const lm = kt.match(/Element\.mangaLang\(\)\s*=\s*select(?:First)?\("([^"]+)"\)/);
    if (lm) {
      config.langFilterStyle = 'link';
      const cm = lm[1].match(/:has\(\.([\w-]+)\)/);
      if (cm) {
        config.flagClass = cm[1];
      } else {
        config.flagClass = lm[1]; // plain selector like .hnv-gallery-card__flag
      }
    }
  }

  // --- popular URL ---
  if (extName === 'hentairox' && !mangaLang) {
    config.popularUrl = 'BASE/top-rated';
  } else if (extName === 'hentaiera' && !mangaLang) {
    config.popularUrl = 'BASE/search/?q=&sort=popular';
  } else if (extName === 'nhentaixxx' && !mangaLang) {
    config.popularUrl = 'BASE/search/?key=&sort=popular';
  } else if (extName === 'nhentaito') {
    config.popularUrl = 'BASE/search?q=*&sort=most-favorited';
  } else {
    const supportsLatest = (extName === 'asmhentai' || extName === 'hentaifox') ? !!mangaLang : true;
    config.popularUrl = 'BASE/' + (mangaLang ? 'language/' + mangaLang + '/' : '') + (supportsLatest ? 'popular' : '');
  }

  warnings.push('favorites/random-entry filters require login or extra requests; not supported');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: galleryadults)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_sel/R_selFirst/R_ownText/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};
var LANG_URI = [['english', 'en'], ['japanese', 'jp'], ['spanish', 'es'], ['french', 'fr'],
  ['korean', 'kr'], ['german', 'de'], ['russian', 'ru']];

// ---------------- galleryadults engine ----------------
function imgAttr(el) {
  if (!el) { return ''; }
  var attrs = ['data-cfsrc', 'data-src', 'data-lazy-src', 'srcset', 'src'];
  for (var i = 0; i < attrs.length; i++) {
    var v = el.attr(attrs[i]);
    if (!v) { continue; }
    var abs = el.absUrl(attrs[i]);
    if (attrs[i] === 'srcset') { abs = abs.split(' ')[0]; }
    if (abs) { return abs; }
  }
  return '';
}

function thumbnailToFull(u) {
  var m = String(u).match(/\\.([a-zA-Z0-9]+)$/);
  if (!m) { return u; }
  return String(u).replace('t.' + m[1], '.' + m[1]);
}

function addPageUri(url, page) {
  if (CFG.pageUriStyle === 'fox') {
    if (url === BASE + '/' && page === 2) { return BASE + '/page/' + page + '/'; }
    if (url.indexOf('?') >= 0) { return url + '&page=' + page; }
    return url + '/pag/' + page + '/';
  }
  var t = url.replace(/^\\/+/, '').replace(/\\/+$/, '');
  return t + (t.indexOf('?') >= 0 ? '&' : '/?') + 'page=' + page;
}

function buildQueryString(query) {
  var terms = [query].filter(function (t) { return t; });
  if (CFG.queryStyle === 'plus-lang') {
    terms.push(CFG.mangaLang);
    return terms.filter(function (t) { return t; }).map(function (t) {
      return String(t).trim().replace(/[^a-zA-Z0-9"]+(?=[a-zA-Z0-9"])/g, '+');
    }).join('+');
  }
  return terms.map(function (t) {
    return String(t).trim().split(',').map(function (part) {
      return part.trim().replace(/\\s+/g, '+');
    }).join(',');
  }).join(',');
}

function itemLang(el) {
  if (CFG.mangaLang === '') { return CFG.mangaLang; }
  if (CFG.langFilterStyle === 'attr') {
    var raw = String(el.attr('data-languages') || '');
    var code = CFG.langCodes[CFG.mangaLang];
    if (CFG.langAttrMode === 'exact') {
      return raw === code ? CFG.mangaLang : 'other';
    }
    var parts = raw.split(' ');
    if (code && parts.indexOf(code) >= 0) { return CFG.mangaLang; }
    if (parts.length > 1 || (parts.length === 1 && parts[0] !== '')) { return 'other'; }
    return CFG.mangaLang;
  }
  if (CFG.langFilterStyle === 'link') {
    var href = '';
    if (CFG.flagClass.charAt(0) === '.') {
      var fEl = R_selFirst(el, CFG.flagClass);
      if (fEl) { href = fEl.attr('href') || ''; }
    } else {
      var links = R_sel(el, 'a');
      for (var i = 0; i < links.length; i++) {
        if (R_selFirst(links[i], '.' + CFG.flagClass)) {
          href = links[i].attr('href') || '';
          break;
        }
      }
    }
    if (!href) { return CFG.mangaLang; }
    return href.replace(/\\/+$/, '').split('/').pop();
  }
  return CFG.mangaLang;
}

function parseListItems(doc, hasNextPage) {
  var unfiltered = [];
  var els = R_sel(doc, CFG.popularSelector);
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var title = '';
    var tEl = R_selFirst(el, CFG.titleSelector);
    if (tEl) { title = tEl.text(); }
    var href = '';
    if (CFG.urlSelector === '@self') {
      href = el.absUrl('href');
    } else {
      var aEl = R_selFirst(el, CFG.urlSelector);
      if (aEl) { href = aEl.absUrl('href'); }
    }
    if (!title || !href) { continue; }
    unfiltered.push({
      key: R_path(href),
      title: title,
      coverUrl: imgAttr(R_selFirst(el, CFG.thumbSelector)),
      lang: itemLang(el)
    });
  }
  var results = unfiltered;
  if (CFG.mangaLang !== '') {
    results = unfiltered.filter(function (m) {
      return m.lang === 'speechless' || m.lang === CFG.mangaLang;
    });
  }
  if (results.length === 0 && hasNextPage && unfiltered.length > 0) {
    results = [unfiltered[0]];
  }
  return results;
}

function hasNext(doc) {
  return !!R_selFirst(doc, CFG.nextSelector);
}

// ---------- info rows ----------
function collectNames(sel, nameFn) {
  var out = [];
  for (var i = 0; i < sel.length; i++) {
    var n = nameFn(sel[i]);
    if (n) { out.push(n); }
  }
  return out;
}

function getInfo(info, tag) {
  var names = [];
  var i, j, els, sub;
  if (CFG.infoStyle === 'asm') {
    els = R_sel(info, '.tags');
    for (i = 0; i < els.length; i++) {
      var label = String(R_ownText(els[i]) || '').trim();
      if (label.replace(/:$/, '').trim() === tag) {
        names = names.concat(collectNames(R_sel(els[i], '.tag_list a'), function (a) {
          var t = R_selFirst(a, '.tag');
          return (t ? R_ownText(t) : '') || R_ownText(a) || a.text();
        }));
      }
    }
  } else if (CFG.infoStyle === 'fox') {
    names = collectNames(R_sel(info, 'ul.' + tag.toLowerCase() + ' a'), function (a) {
      return R_ownText(a) || a.text();
    });
  } else if (CFG.infoStyle === 'imhentai' || CFG.infoStyle === 'rox') {
    var needle = tag + ':';
    els = R_sel(info, 'li');
    for (i = 0; i < els.length; i++) {
      var tEl = R_selFirst(els[i], '.tags_text');
      if (!tEl) { continue; }
      var txt = String(tEl.text() || '');
      if (txt.indexOf(needle) < 0) { continue; }
      sub = R_sel(els[i], 'a.tag');
      for (j = 0; j < sub.length; j++) {
        var nEl = R_selFirst(sub[j], '.item_name');
        names.push((nEl ? R_ownText(nEl) : '') || R_ownText(sub[j]) || sub[j].text());
      }
    }
  } else if (CFG.infoStyle === 'envy' || CFG.infoStyle === 'zap') {
    var cls = CFG.infoStyle === 'envy' ? 'hnv' : 'hz';
    var needle2 = tag + ':';
    els = R_sel(info, 'div.' + cls + '-gallery-entity-group');
    for (i = 0; i < els.length; i++) {
      if (String(els[i].text() || '').indexOf(needle2) < 0) { continue; }
      sub = R_sel(els[i], 'a.' + cls + '-gallery-tag');
      for (j = 0; j < sub.length; j++) {
        var n2 = R_selFirst(sub[j], '.' + cls + '-gallery-tag__name');
        names.push(n2 ? n2.text() : sub[j].text());
      }
    }
  } else if (CFG.infoStyle === 'nhentaito') {
    els = R_sel(info, '.field-name');
    for (i = 0; i < els.length; i++) {
      if (String(els[i].text() || '').indexOf(tag) < 0) { continue; }
      sub = R_sel(els[i], '.tags a');
      for (j = 0; j < sub.length; j++) {
        var n3 = R_selFirst(sub[j], '.name');
        names.push((n3 ? R_ownText(n3) : '') || sub[j].text());
      }
    }
  } else if (CFG.infoStyle === 'nhentaixxx') {
    els = R_sel(info, '.tags');
    for (i = 0; i < els.length; i++) {
      if (String(els[i].text() || '').indexOf(tag) < 0) { continue; }
      sub = R_sel(els[i], 'a.tag_btn');
      for (j = 0; j < sub.length; j++) {
        var n4 = R_selFirst(sub[j], '.tag_name');
        names.push((n4 ? R_ownText(n4) : '') || sub[j].text());
      }
    }
  }
  var cleaned = [];
  for (i = 0; i < names.length; i++) {
    var v = String(names[i]).trim();
    if (v) { cleaned.push(v); }
  }
  cleaned.sort();
  return cleaned.join(', ');
}

function inputIdValueOf(doc, id) {
  var els = R_sel(doc, 'input[id=' + id + ']');
  return els.length > 0 ? (els[0].attr('value') || '') : '';
}

function galleryIdOf(doc) {
  if (CFG.galleryIdStyle === 'data-attr') {
    var els = R_sel(doc, '[data-gallery-id]');
    return els.length > 0 ? (els[0].attr('data-gallery-id') || '') : '';
  }
  return inputIdValueOf(doc, 'gallery_id');
}

function totalPagesOf(doc, info) {
  if (CFG.totalPagesStyle === 'data-attr') {
    var els = R_sel(doc, '[data-total-pages]');
    return els.length > 0 ? (els[0].attr('data-total-pages') || '') : '';
  }
  if (CFG.totalPagesStyle === 'info-pages') {
    return getInfo(info, 'Pages').replace(/,/g, '');
  }
  return inputIdValueOf(doc, 'load_pages');
}

function getServer(doc, coverUrl) {
  var num = inputIdValueOf(doc, 'load_server');
  if (num) {
    var domain = BASE.replace(/^https?:\\/\\//, '').split('/')[0];
    return CFG.serverPrefix + num + '.' + domain;
  }
  var m = String(coverUrl || '').match(/^https?:\\/\\/([^\\/]+)/);
  return m ? m[1] : BASE.replace(/^https?:\\/\\//, '').split('/')[0];
}

function parseDetail(doc, key) {
  var info = R_selFirst(doc, CFG.detailSelector);
  if (!info) {
    return { key: key, title: '', coverUrl: '', author: '', description: '', genre: '', status: 'completed' };
  }
  var title = '';
  var h1 = R_selFirst(info, 'h1');
  if (h1) { title = h1.text(); }
  var cover = imgAttr(R_selFirst(info, CFG.coverSelector));

  var genre = getInfo(info, 'Tags');
  var author = getInfo(info, 'Artists') || getInfo(info, 'Groups');

  var descParts = [];
  var tags = ['Parodies', 'Characters', 'Groups', 'Languages', 'Categories', 'Category'];
  for (var i = 0; i < tags.length; i++) {
    var val = getInfo(info, tags[i]);
    if (val) { descParts.push('**' + tags[i] + '**: ' + val); }
  }
  var pages = totalPagesOf(doc, info);
  if (pages) { descParts.push('**Pages**: ' + pages); }
  var alt = R_selFirst(info, 'h1 + h2, .subtitle');
  if (alt && R_ownText(alt)) { descParts.push('**Alternative title**: ' + R_ownText(alt)); }

  return {
    key: key,
    title: title,
    coverUrl: cover,
    author: author,
    description: descParts.join('\\n\\n'),
    genre: genre,
    status: 'completed'
  };
}

function chapterDate(doc, info) {
  var el, text;
  if (CFG.dateStyle === 'fox') {
    var els = R_sel(info, '.pages');
    for (var i = 0; i < els.length; i++) {
      var t = R_ownText(els[i]);
      if (t && String(t).indexOf('Posted:') >= 0) {
        text = String(t).replace(/^\\s*Posted:\\s*/, '');
        break;
      }
    }
    return R_date(text || '');
  }
  if (CFG.dateStyle === 'nhentaito') {
    el = R_selFirst(info, '.tags time');
    if (el) {
      var dt = Date.parse(el.attr('datetime') || '');
      return isNaN(dt) ? 0 : dt;
    }
    return 0;
  }
  el = R_selFirst(info, '.uploaded');
  return R_date(el ? R_ownText(el) : '');
}

// ---------- pages ----------
function extractParseJson(doc) {
  var scripts = R_sel(doc, 'script');
  for (var i = 0; i < scripts.length; i++) {
    var data = scripts[i].html() || '';
    if (data.indexOf('parseJSON') < 0) { continue; }
    if (CFG.parseJsonStyle === 'fl') {
      var a = data.indexOf('$.parseJSON(\\'{"fl":');
      if (a >= 0) {
        var rest = data.slice(a + '$.parseJSON(\\'{"fl":'.length);
        return rest.slice(0, rest.indexOf(',"th":')).trim();
      }
    } else {
      var marker = '$.parseJSON(\\'';
      var b = data.indexOf(marker);
      if (b >= 0) {
        var s = data.slice(b + marker.length);
        return s.slice(0, s.indexOf('\\');')).trim();
      }
    }
  }
  return null;
}

function pageUrlFor(idx) {
  // galleryId resolved by caller via closure-free globals below
  return BASE + '/' + CFG.pageUri + '/' + GALLERY_ID + '/' + idx + '/';
}

var GALLERY_ID = '';

function thumbnailImgs(doc, rootSel) {
  var out = [];
  var els = R_sel(doc, rootSel + ' a');
  for (var i = 0; i < els.length; i++) {
    var img = R_selFirst(els[i], 'img');
    if (img) {
      var u = imgAttr(img);
      if (u) { out.push(u); }
    }
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    var url = addPageUri(CFG.popularUrl.replace(/^BASE/, BASE), page);
    var doc = $.html.parse(await $.http.get(url));
    var hasNextPage = hasNext(doc);
    return { mangas: parseListItems(doc, hasNextPage), hasNextPage: hasNextPage };
  },

  getSearchManga: async function (page, query) {
    // numeric query -> direct gallery lookup
    if (/^\\d+$/.test(String(query || '').trim())) {
      var id = String(query).trim();
      var dDoc = $.html.parse(await $.http.get(BASE + '/' + CFG.idPrefixUri + '/' + id));
      var detail = parseDetail(dDoc, '/' + CFG.idPrefixUri + '/' + id + '/');
      return { mangas: [detail], hasNextPage: false };
    }

    var url;
    if (CFG.searchStyle === 'nhentaito') {
      url = BASE + '/search?q=' + encodeURIComponent(query || '*') + '&sort=relevance&lang=' + CFG.mangaLang;
    } else if (CFG.intermediateSearch) {
      url = BASE + '/search/?pp=0&lt=0&dl=0&tr=0';
      for (var li = 0; li < LANG_URI.length; li++) {
        var on = CFG.mangaLang === LANG_URI[li][0] || CFG.mangaLang === '';
        url += '&' + LANG_URI[li][1] + '=' + (on ? '1' : '0');
      }
      url += '&key=' + encodeURIComponent(buildQueryString(query));
    } else {
      url = BASE + '/search/?' + CFG.basicSearchKey + '=' + encodeURIComponent(buildQueryString(query)) + '&sort=popular';
    }
    url = addPageUri(url, page);
    var doc = $.html.parse(await $.http.get(url));
    var hasNextPage = hasNext(doc);
    return { mangas: parseListItems(doc, hasNextPage), hasNextPage: hasNextPage };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey)));
    return parseDetail(doc, mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey)));
    var info = R_selFirst(doc, CFG.detailSelector);
    return [{
      key: mangaKey,
      name: 'Chapter',
      chapterNumber: -1,
      dateUpload: info ? chapterDate(doc, info) : 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey)));
    var info = R_selFirst(doc, CFG.detailSelector);
    var cover = info ? imgAttr(R_selFirst(info, CFG.coverSelector)) : '';
    GALLERY_ID = galleryIdOf(doc);

    var json = extractParseJson(doc);
    if (json) {
      var loadDir = inputIdValueOf(doc, 'load_dir');
      var loadId = inputIdValueOf(doc, 'load_id');
      var server = getServer(doc, cover);
      var imagesUri = 'https://' + server + '/' + loadDir + '/' + loadId;
      try {
        var images = JSON.parse(json);
        var keys = [];
        for (var k in images) {
          if (Object.prototype.hasOwnProperty.call(images, k)) { keys.push(k); }
        }
        keys.sort(function (a, b) { return (+a) - (+b); });
        var pages = [];
        for (var i = 0; i < keys.length; i++) {
          var spec = String(images[keys[i]]).replace(/"/g, '').split(',');
          var extCode = spec[0];
          var ext = extCode === 'p' ? 'png' : extCode === 'b' ? 'bmp' : extCode === 'g' ? 'gif' : extCode === 'w' ? 'webp' : 'jpg';
          pages.push({ index: +keys[i], url: imagesUri + '/' + keys[i] + '.' + ext });
        }
        return pages;
      } catch (e) { /* fall through to alternative */ }
    }

    var totalPages = totalPagesOf(doc, info);
    var total = parseInt(totalPages, 10) || 0;

    if (CFG.pageByPage) {
      var out = [];
      for (var p = 1; p <= total; p++) {
        var pDoc = $.html.parse(await $.http.get(pageUrlFor(p)));
        var img = R_selFirst(pDoc, 'img#gimg') || R_selFirst(pDoc, 'img#fimg') || R_selFirst(pDoc, 'img#readerImg');
        var u = img ? imgAttr(img) : '';
        out.push({ index: out.length, url: u });
      }
      return out;
    }

    var thumbs = thumbnailImgs(doc, CFG.thumbnailSelector);

    if (total > thumbs.length) {
      var token = '';
      var tokenEl = R_selFirst(doc, '[name=csrf-token]');
      if (tokenEl) { token = tokenEl.attr('content') || ''; }
      var serverNumber = inputIdValueOf(doc, 'load_server');
      var body;
      if (CFG.formStyle === 'asm') {
        body = 'id=' + encodeURIComponent(inputIdValueOf(doc, 'load_id')) +
          '&dir=' + encodeURIComponent(inputIdValueOf(doc, 'load_dir')) +
          '&visible_pages=' + thumbs.length + '&t_pages=' + encodeURIComponent(totalPages) + '&type=2';
      } else {
        body = 'u_id=' + encodeURIComponent(GALLERY_ID) +
          '&g_id=' + encodeURIComponent(inputIdValueOf(doc, 'load_id')) +
          '&img_dir=' + encodeURIComponent(inputIdValueOf(doc, 'load_dir')) +
          '&visible_pages=' + thumbs.length + '&total_pages=' + encodeURIComponent(totalPages) + '&type=2';
        if (serverNumber) { body += '&server=' + encodeURIComponent(serverNumber); }
      }
      if (token) { body += '&_token=' + encodeURIComponent(token); }
      try {
        var moreText = await $.http.post(BASE + '/' + CFG.pagesRequest, body,
          { 'X-Requested-With': 'XMLHttpRequest', 'Content-Type': 'application/x-www-form-urlencoded' });
        var moreDoc = $.html.parse(moreText);
        var more = thumbnailImgs(moreDoc, CFG.thumbnailSelector);
        // thumbs_loader returns bare <a><img/></a> fragments
        if (more.length === 0) {
          var bareAs = R_sel(moreDoc, 'a');
          for (var bi = 0; bi < bareAs.length; bi++) {
            var bImg = R_selFirst(bareAs[bi], 'img');
            if (bImg) {
              var bu = imgAttr(bImg);
              if (bu) { more.push(bu); }
            }
          }
        }
        if (more.length > 0) {
          thumbs = thumbs.concat(more);
        } else {
          // dummy sequential generation
          var loadDir2 = inputIdValueOf(doc, 'load_dir');
          var loadId2 = inputIdValueOf(doc, 'load_id');
          var server2 = getServer(doc, cover);
          var imagesUri2 = 'https://' + server2 + '/' + loadDir2 + '/' + loadId2;
          var firstExt = thumbs.length > 0 ? thumbs[0].substring(thumbs[0].lastIndexOf('.') + 1) : 'jpg';
          for (var d = thumbs.length + 1; d <= total; d++) {
            thumbs.push(imagesUri2 + '/' + d + 't.' + firstExt);
          }
        }
      } catch (e) { /* keep collected thumbs */ }
    }

    var pages2 = [];
    for (var t = 0; t < thumbs.length; t++) {
      pages2.push({ index: t, url: thumbnailToFull(thumbs[t]) });
    }
    return pages2;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
