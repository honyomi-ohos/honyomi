// Manga18 theme engine (Flat manga-list CMS variant)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  popularSelector: 'div.story_item',
  nextPageSelector: '.pagination > li:last-child:not(.active)',
  infoSelector: 'div.detail_listInfo',
  titleSelector: 'div.detail_name > h1',
  descriptionSelector: 'div.detail_reviewContent',
  genreSelector: 'div.info_value > a[href*=/manga-list/]',
  thumbnailSelector: 'div.detail_avatar > img',
  chapterSelector: 'div.chapter_box .item',
  thumbReplaces: [],
};

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  // hentai3zcc rewrites thumbnail hosts/formats in popularMangaFromElement
  const re = /\.replace\("((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\)/g;
  let m;
  while ((m = re.exec(kt)) !== null) {
    config.thumbReplaces.push([m[1], m[2]]);
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: manga18)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_status/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- manga18 engine ----------------

function applyThumbReplaces(u) {
  var v = String(u || '');
  for (var i = 0; i < CFG.thumbReplaces.length; i++) {
    v = v.split(CFG.thumbReplaces[i][0]).join(CFG.thumbReplaces[i][1]);
  }
  return v;
}

function parseCards(doc) {
  var items = R_sel(doc, CFG.popularSelector);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var a = R_selFirst(el, 'a');
    if (!a) { continue; }
    var href = a.absUrl('href') || a.attr('href');
    if (!href) { continue; }
    var tEl = R_selFirst(el, 'div.mg_info > div.mg_name a');
    var img = R_selFirst(el, 'img');
    var thumb = img ? (img.absUrl('src') || img.attr('src')) : '';
    out.push({
      key: R_path(href),
      title: tEl ? tEl.text() : '',
      coverUrl: applyThumbReplaces(R_abs(thumb))
    });
  }
  return out;
}

async function listManga(page, query) {
  var url = BASE + '/list-manga/' + page;
  if (query) {
    url += '?search=' + encodeURIComponent(query);
  } else {
    url += '?order_by=views';
  }
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  return { mangas: parseCards(doc), hasNextPage: !!R_selFirst(doc, CFG.nextPageSelector) };
}

function infoValueByItemLabel(info, label) {
  // equivalent of "div.item:contains(Label) div.info_value" without :contains
  var items = R_sel(info, 'div.item');
  for (var i = 0; i < items.length; i++) {
    if (items[i].text().indexOf(label) >= 0) {
      var v = R_selFirst(items[i], 'div.info_value');
      if (v) { return v.text(); }
    }
  }
  return '';
}

function infoValueByLabelSibling(info, words) {
  // equivalent of "div.info_label:contains(word) + div.info_value" without :contains
  var labels = R_sel(info, 'div.info_label');
  for (var i = 0; i < labels.length; i++) {
    var t = (R_ownText(labels[i]) || labels[i].text()).toLowerCase();
    for (var w = 0; w < words.length; w++) {
      if (t.indexOf(words[w]) >= 0) {
        var sib = labels[i].nextElementSibling;
        if (sib) { return sib.text(); }
      }
    }
  }
  return '';
}

function parseDate(s) {
  var m = String(s || '').match(/^(\\d{2})-(\\d{2})-(\\d{4})$/);
  if (!m) { return R_date(s); }
  return new Date(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10)).getTime();
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
    var info = R_selFirst(doc, CFG.infoSelector);

    var title = '';
    var titleEl = R_selFirst(doc, CFG.titleSelector);
    if (titleEl) { title = titleEl.text(); }

    var descParts = [];
    var descEls = R_sel(doc, CFG.descriptionSelector);
    for (var i = 0; i < descEls.length; i++) {
      var dt = descEls[i].text();
      if (dt) { descParts.push(dt); }
    }
    if (info) {
      var alt = infoValueByItemLabel(info, 'Other name');
      if (alt && alt !== 'Updating') {
        descParts.push('Alternative Names:\\n' + alt);
      }
    }

    var status = '';
    if (info) {
      var sv = infoValueByItemLabel(info, 'Status');
      if (sv === 'On Going') { status = 'ongoing'; }
      else if (sv === 'Completed') { status = 'completed'; }
    }

    var author = '', artist = '';
    if (info) {
      artist = infoValueByLabelSibling(info, ['artist']);
      if (artist === 'Updating') { artist = ''; }
      author = infoValueByLabelSibling(info, ['author', 'autor']);
      if (author === 'Updating') { author = ''; }
    }

    var genres = [];
    var genreEls = R_sel(doc, CFG.genreSelector);
    for (var g = 0; g < genreEls.length; g++) { genres.push(genreEls[g].text()); }

    var thumbEl = R_selFirst(doc, CFG.thumbnailSelector);
    return {
      key: mangaKey,
      title: title,
      coverUrl: thumbEl ? R_abs(thumbEl.absUrl('src') || thumbEl.attr('src')) : '',
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
    var els = R_sel(doc, CFG.chapterSelector);
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var a = R_selFirst(els[i], 'a');
      if (!a) { continue; }
      var href = a.absUrl('href') || a.attr('href');
      if (!href) { continue; }
      var pEl = R_selFirst(els[i], 'p');
      out.push({
        key: R_path(href),
        name: a.text(),
        chapterNumber: -1,
        dateUpload: pEl ? parseDate(pEl.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // newest first on site; normalize to oldest-first
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = out.length - 1 - j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var scripts = R_sel(doc, 'script');
    var data = '';
    for (var i = 0; i < scripts.length; i++) {
      var c = scripts[i].html() || scripts[i].text() || '';
      if (c.indexOf('slides_p_path') >= 0) { data = c; break; }
    }
    if (!data) { return []; }
    var start = data.indexOf('[');
    var end = data.indexOf(',]');
    if (start < 0 || end < 0) { return []; }
    var encoded = data.substring(start + 1, end).replace(/"/g, '').split(',');
    var pages = [];
    for (var j = 0; j < encoded.length; j++) {
      var enc = encoded[j].trim();
      if (!enc) { continue; }
      var url;
      try { url = $.crypto.base64Decode(enc); } catch (e) { continue; }
      if (!url) { continue; }
      pages.push({ index: pages.length, url: R_abs(url) });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
