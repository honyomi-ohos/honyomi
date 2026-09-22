// SinMH theme engine (zh: jiuermanhua, manhuadui) — SinMH CMS with mobile/desktop split
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText || '';
  const warnings = [];
  const config = { style: 'default' }; // default | dmzj
  const src = (ctx.gradle && ctx.gradle.sources && ctx.gradle.sources[0]) || {};
  const base = String(src.baseUrl || '');
  if (/mangaDetailsParseDMZJStyle/.test(kt)) config.style = 'dmzj';
  if (/92mh/.test(base) || /92mh\.com/.test(kt)) {
    config.fixedMobileUrl = 'http://h5.92mh.com';
    config.pagesFromDesktop = true;
  }
  if (/sortedDescending\(\)\s*=\s*this\b/.test(kt)) {
    config.noItemReverse = true; // manhuadui: sections already ascending within
  }
  warnings.push('category filters not supported by host; text search only');
  warnings.push('site may block non-China IPs (manhuadui)');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: sinmh)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var MOBILE = CFG.fixedMobileUrl || BASE.replace('www.', 'm.');
var IMAGE_HOST = null;

function parseDate(s) {
  var m = /(\\d{4})-(\\d{1,2})-(\\d{1,2})/.exec(String(s || ''));
  if (!m) { return 0; }
  return Math.floor(Date.UTC(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10)) / 1000);
}

async function imageHost() {
  if (IMAGE_HOST !== null) { return IMAGE_HOST; }
  var text = await $.http.get(BASE + '/js/config.js');
  var m = /resHost:.+?"?domain"?:\\["(.+?)"/.exec(text);
  IMAGE_HOST = m ? m[1] : '';
  return IMAGE_HOST;
}

function parseList(doc) {
  var items = R_sel(doc, '#contList > li, li.list-comic');
  var mangas = [];
  for (var i = 0; i < items.length; i++) {
    var titleEl = R_selFirst(items[i], 'p > a, h3 > a');
    if (!titleEl) { continue; }
    var img = R_selFirst(items[i], 'img');
    mangas.push({
      key: R_path(titleEl.absUrl('href') || titleEl.attr('href')),
      title: titleEl.text(),
      coverUrl: img ? (img.absUrl('src') || img.absUrl('data-src') || img.attr('src') || '') : ''
    });
  }
  var hasNextPage = !!R_selFirst(doc, 'ul.pagination > li.next:not(.disabled)');
  return { mangas: mangas, hasNextPage: hasNextPage };
}

function findStrongSibling(container, label, combinator, extra) {
  var strongs = R_sel(container, 'strong');
  for (var i = 0; i < strongs.length; i++) {
    if (strongs[i].text().indexOf(label) >= 0) {
      return R_selFirst(strongs[i], ':scope ' + combinator + ' ' + extra);
    }
  }
  return null;
}

function detailsDefault(doc) {
  var titleEl = R_selFirst(doc, '.book-title > h1');
  var out = { title: titleEl ? titleEl.text() : '', author: '', genre: '', status: 'UNKNOWN' };
  var detailsList = R_selFirst(doc, '.detail-list');
  if (detailsList) {
    var authorEl = findStrongSibling(detailsList, '作者', '~', '*');
    out.author = authorEl ? authorEl.text() : '';
    var statusEl = findStrongSibling(detailsList, '状态', '+', '*');
    var st = statusEl ? statusEl.text() : '';
    if (st === '连载中') { out.status = 'ONGOING'; }
    else if (st === '已完结') { out.status = 'COMPLETED'; }
    var catEl = findStrongSibling(detailsList, '类型', '+', 'a');
    var parts = [];
    if (catEl) { parts.push(catEl.text()); }
    var crumb = R_selFirst(doc, 'div.breadcrumb-bar');
    if (crumb) {
      var crumbs = R_sel(crumb, 'a[href^="/list/"]');
      for (var c = 0; c < crumbs.length; c++) {
        if (crumbs[c].text()) { parts.push(crumbs[c].text()); }
      }
    }
    out.genre = parts.join(', ');
  }
  return out;
}

function detailsDmzj(doc) {
  var detailsDiv = R_selFirst(doc, 'div.comic_deCon');
  var out = { title: '', author: '', genre: '', status: 'UNKNOWN' };
  if (!detailsDiv) { return out; }
  var h1 = R_selFirst(detailsDiv, 'h1');
  out.title = h1 ? h1.text() : '';
  var details = R_sel(detailsDiv, ':scope > ul > li');
  if (details.length > 0) {
    out.author = String(details[0].text()).replace(/^作者：/, '').replace(/^\\s+/, '');
  }
  if (details.length > 1) {
    var a = R_selFirst(details[1], 'a');
    var st = a ? a.text() : '';
    if (st === '连载中') { out.status = 'ONGOING'; }
    else if (st === '已完结') { out.status = 'COMPLETED'; }
  }
  var genres = [];
  var seen = {};
  if (details.length > 2) {
    var cat = R_selFirst(details[2], 'a');
    if (cat && !seen[cat.text()]) { seen[cat.text()] = true; genres.push(cat.text()); }
  }
  if (details.length > 3) {
    var typeAs = R_sel(details[3], 'a');
    for (var t = 0; t < typeAs.length; t++) {
      if (!seen[typeAs[t].text()]) { seen[typeAs[t].text()] = true; genres.push(typeAs[t].text()); }
    }
  }
  out.genre = genres.join(', ');
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/list/click/?page=' + page);
    return parseList($.html.parse(text));
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/search/?keywords=' + encodeURIComponent(query) + '&page=' + page);
    return parseList($.html.parse(text));
  },

  getMangaDetail: async function (mangaKey) {
    var url = (CFG.pagesFromDesktop ? BASE : MOBILE) + mangaKey;
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    var info = CFG.style === 'dmzj' ? detailsDmzj(doc) : detailsDefault(doc);
    var desc = '';
    if (CFG.style === 'dmzj') {
      var pEl = R_selFirst(doc, 'div.comic_deCon > p.comic_deCon_d');
      desc = pEl ? pEl.text() : '';
    } else {
      var intro = R_selFirst(doc, '#intro-all');
      if (intro) {
        desc = String(intro.text()).replace(/^漫画简介：/, '').replace(/^\\s+/, '').replace(/^漫画简介：/, '').replace(/^\\s+/, '');
      }
    }
    var coverEl = R_selFirst(doc, CFG.style === 'dmzj' ? 'div.comic_i_img > img' : 'div.book-cover img');
    return {
      key: mangaKey,
      title: info.title,
      coverUrl: coverEl ? (coverEl.absUrl('src') || coverEl.attr('src') || '') : '',
      author: info.author,
      description: desc,
      genre: info.genre,
      status: info.status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(MOBILE + mangaKey);
    var doc = $.html.parse(text);
    var sections = R_sel(doc, '.chapter-body');
    var chapters = [];
    for (var s = sections.length - 1; s >= 0; s--) {
      var anchors = R_sel(sections[s], 'li > a');
      var sectionChapters = [];
      for (var i = 0; i < anchors.length; i++) {
        var a = anchors[i];
        var key = R_path(a.absUrl('href') || a.attr('href'));
        if (!key) { continue; }
        var first = R_selFirst(a, ':scope > *');
        sectionChapters.push({
          key: key,
          name: first ? first.text() : a.text(),
          dateUpload: 0
        });
      }
      if (!CFG.noItemReverse) { sectionChapters.reverse(); }
      for (var k = 0; k < sectionChapters.length; k++) { chapters.push(sectionChapters[k]); }
    }
    if (chapters.length > 0) {
      var dateEl = R_selFirst(doc, '.date');
      if (dateEl) {
        chapters[0].dateUpload = parseDate(R_ownText(dateEl));
      }
    }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var url = (CFG.pagesFromDesktop ? BASE : MOBILE) + chapterKey;
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    var scriptEl = R_selFirst(doc, 'body > script');
    if (!scriptEl) { return []; }
    var body = scriptEl.html();
    var m = /chapterImages\\s*=\\s*([\\s\\S]*?);/.exec(body);
    if (!m) { return []; }
    var images = m[1];
    if (images.length <= 2) { return []; }
    var pm = /chapterPath\\s*=\\s*"([^"]*)"/.exec(body);
    var path = pm ? pm[1] : '';
    var inner;
    if (images.length > 4) {
      inner = images.substring(2, images.length - 2).replace(/\\\\\\//g, '/').split('","');
    } else {
      inner = [];
    }
    var host = await imageHost();
    var pages = [];
    for (var i = 0; i < inner.length; i++) {
      var image = inner[i];
      var imageUrl;
      if (image.indexOf('https://') === 0) { imageUrl = image; }
      else if (image.charAt(0) === '/') { imageUrl = host + image; }
      else { imageUrl = host + '/' + path + image; }
      pages.push(imageUrl);
    }
    return pages;
  },

  imageHeaders: function () {
    return { 'Referer': BASE + '/' };
  }
};
`;
}
