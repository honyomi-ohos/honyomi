// MangaReader theme engine (AniList-style reader: manganow / jmanga / klraw / mangamura / rawotaku)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  searchPathSegment: 'search',
  searchKeyword: 'keyword',
  pageParam: 'page',
  chapterIdSelect: 'en-chapters',
  ajaxUrl: '//ajax/image/list/{id}?mode=vertical',
  ivCardPages: false,
  authorText: 'Authors',
  statusText: 'Status',
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

  const sp = extractStrOverride(kt, 'searchPathSegment');
  if (sp !== undefined) { config.searchPathSegment = sp; }
  const sk = extractStrOverride(kt, 'searchKeyword');
  if (sk !== undefined) { config.searchKeyword = sk; }
  const ci = extractStrOverride(kt, 'chapterIdSelect');
  if (ci !== undefined) { config.chapterIdSelect = ci; }

  // jmanga-style custom search: query param "q" on the site root
  if (/addQueryParameter\("q",\s*query\)/.test(kt)) {
    config.searchPathSegment = '';
    config.searchKeyword = 'q';
  }

  const pm = kt.match(/override\s+fun\s+addPage\s*\([^)]*\)[\s\S]{0,200}?addQueryParameter\("([^"]+)",\s*page/);
  if (pm) { config.pageParam = pm[1]; }

  const am = kt.match(/override\s+fun\s+getAjaxUrl\s*\([^)]*\)[^=]*=\s*GET\(\s*"\$baseUrl([^"]*)"/) ||
    kt.match(/override\s+fun\s+getAjaxUrl\s*\([^)]*\)[^=]*=\s*"\$baseUrl([^"]*)"/);
  if (am) {
    config.ajaxUrl = am[1].replace('$id', '{id}');
  }

  if (/iv-card/.test(kt)) { config.ivCardPages = true; }

  const lang = ctx.gradle && ctx.gradle.sources && ctx.gradle.sources[0] ? ctx.gradle.sources[0].lang : '';
  if (lang === 'ja') {
    config.authorText = '著者';
    config.statusText = '場所';
  }

  if (/rateLimit\s*\(/.test(kt)) {
    warnings.push('rateLimit not portable; requests may be throttled by site');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mangareader)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_status/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- mangareader engine ----------------

function imgAttr(el) {
  if (!el) { return ''; }
  var names = ['data-lazy-src', 'data-src', 'data-url'];
  for (var i = 0; i < names.length; i++) {
    var v = el.attr(names[i]);
    if (v) { return R_abs(v); }
  }
  return el.attr('src') ? R_abs(el.attr('src')) : '';
}

async function listManga(page, query) {
  var url;
  if (query) {
    if (CFG.searchPathSegment) {
      url = BASE + '/' + CFG.searchPathSegment + '?' + CFG.searchKeyword + '=' + encodeURIComponent(query) + '&' + CFG.pageParam + '=' + page;
    } else {
      url = BASE + '/?' + CFG.searchKeyword + '=' + encodeURIComponent(query) + '&' + CFG.pageParam + '=' + page;
    }
  } else {
    url = BASE + '/filter?sort=most-viewed&' + CFG.pageParam + '=' + page;
  }
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var items = R_sel(doc, '.manga_list-sbs .manga-poster');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var href = el.attr('href') || el.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, 'img');
    out.push({
      key: R_path(href),
      title: img ? (img.attr('alt') || '') : '',
      coverUrl: imgAttr(img)
    });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, 'ul.pagination > li.active + li') };
}

function parseStatusValue(v) {
  var low = String(v || '').toLowerCase();
  if (low === 'ongoing' || low === 'publishing' || low === 'releasing') { return 'ongoing'; }
  if (low === 'completed' || low === 'finished') { return 'completed'; }
  if (low === 'on-hold' || low === 'on_hiatus') { return 'hiatus'; }
  if (low === 'canceled' || low === 'discontinued') { return 'cancelled'; }
  return '';
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga(page, '');
  },

  getSearchManga: async function (page, query) {
    return listManga(page, query || '');
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var root = R_selFirst(doc, '#ani_detail');
    if (!root) { return { key: mangaKey, title: '', coverUrl: '', author: '', description: '', genre: '', status: '' }; }

    var title = '';
    var nameEl = R_selFirst(root, '.manga-name');
    if (nameEl) { title = R_ownText(nameEl) || nameEl.text(); }

    var genres = [];
    var genreEls = R_sel(root, '.genres > a');
    for (var g = 0; g < genreEls.length; g++) { genres.push(R_ownText(genreEls[g]) || genreEls[g].text()); }

    var descParts = [];
    var descEl = R_selFirst(root, '.description');
    if (descEl) { descParts.push(R_ownText(descEl) || descEl.text()); }
    var altEl = R_selFirst(root, '.manga-name-or');
    var altText = altEl ? (R_ownText(altEl) || '').trim() : '';
    if (altText && altText !== title) {
      descParts.push('Alternative Title: ' + altText);
    }

    var author = '', artist = '', status = '';
    var infoItems = R_sel(root, '.anisc-info > .item');
    for (var i = 0; i < infoItems.length; i++) {
      var head = R_selFirst(infoItems[i], '.item-head');
      var headText = head ? (R_ownText(head) || '').trim() : '';
      if (headText === CFG.authorText + ':') {
        var authors = R_sel(infoItems[i], 'a');
        var authorList = [], artistList = [];
        for (var a = 0; a < authors.length; a++) {
          var name = (R_ownText(authors[a]) || authors[a].text()).replace(/,/g, '');
          var sib = authors[a].nextSibling;
          var sibText = sib && sib.nodeType === 3 ? String(sib.data || sib.wholeText || '') : '';
          if (sibText.indexOf('(Art)') >= 0) { artistList.push(name); } else { authorList.push(name); }
        }
        author = authorList.join(', ');
        artist = artistList.join(', ');
      } else if (headText === CFG.statusText + ':') {
        var nameEl2 = R_selFirst(infoItems[i], '.name');
        status = parseStatusValue(nameEl2 ? nameEl2.text() : '');
      }
    }

    return {
      key: mangaKey,
      title: title,
      coverUrl: imgAttr(R_selFirst(root, 'img')),
      author: author,
      artist: artist,
      description: descParts.join('\\n\\n'),
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, '#' + CFG.chapterIdSelect + ' > li.chapter-item');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var a = R_selFirst(els[i], 'a');
      if (!a) { continue; }
      var href = a.attr('href') || a.absUrl('href');
      if (!href) { continue; }
      var nameEl = R_selFirst(a, '.name');
      out.push({
        key: R_path(href),
        name: nameEl ? nameEl.text() : a.text(),
        chapterNumber: -1,
        dateUpload: 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // newest first on site; normalize to oldest-first
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = out.length - 1 - j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var chapterUrl = R_abs(chapterKey);
    var chapterText = await $.http.get(chapterUrl);
    var chapterDoc = $.html.parse(chapterText);
    var idEl = R_selFirst(chapterDoc, 'div[data-reading-id]');
    var chapterId = idEl ? idEl.attr('data-reading-id') : '';
    if (!chapterId) { return []; }

    var ajaxUrl = BASE + CFG.ajaxUrl.replace('{id}', chapterId);
    var ajaxText = await $.http.get(ajaxUrl, R_xhr({
      Accept: 'application/json, text/javascript, */*; q=0.01',
      Referer: encodeURIComponent(chapterUrl)
    }));
    var data;
    try { data = JSON.parse(ajaxText); } catch (e) { return []; }
    if (!data || !data.html) { return []; }
    var frag = $.html.parse(data.html);

    var pages = [];
    if (CFG.ivCardPages) {
      var cards = R_sel(frag, '.container-reader-chapter > .iv-card');
      for (var c = 0; c < cards.length; c++) {
        var du = cards[c].attr('data-url') || '';
        if (!du || du.indexOf('manganow.jpg') >= 0) { continue; }
        pages.push({ index: pages.length, url: R_abs(du) });
      }
    } else {
      var els = R_sel(frag, '.container-reader-chapter > div > img');
      for (var i = 0; i < els.length; i++) {
        var u = imgAttr(els[i]);
        if (!u) {
          var inner = R_selFirst(els[i], 'img');
          u = imgAttr(inner);
        }
        if (u) { pages.push({ index: pages.length, url: u }); }
      }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
