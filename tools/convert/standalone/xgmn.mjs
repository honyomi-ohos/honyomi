// all/xgmn — bespoke engine (rotating-domain gallery site; sub-page image collection)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'site redirects to a rotating domain; image URLs resolve via baseUrl redirects',
      'category browse filters not portable (text search only)',
      'current site injects gallery content via JS (static HTML contains only placeholders); page lists may be empty exactly like the upstream extension',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};

function centeredImgs(doc) {
  var ps = R_sel(doc, '.article-content p');
  var urls = [];
  for (var i = 0; i < ps.length; i++) {
    var p = ps[i];
    var cls = p.attr('class') || '';
    var style = p.attr('style') || '';
    if (cls.indexOf('center') < 0 && style.indexOf('center') < 0) { continue; }
    var imgs = R_sel(p, 'img');
    for (var j = 0; j < imgs.length; j++) {
      var u = imgs[j].absUrl('src');
      if (u) { urls.push(u); }
    }
  }
  return urls;
}
// the site emits unquoted alt=[...] / title=[...] attributes that break lenient parsers
function cleanHtml(text) {
  return String(text).replace(/(\\s(?:alt|title)=)\\[([^\\]]*)\\]/g, '$1"$2"');
}
function parseDoc(text) {
  return $.html.parse(cleanHtml(text));
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/top.html');
    var doc = $.html.parse(text);
    var boxes = R_sel(doc, '.related_box');
    var out = [];
    for (var i = 0; i < boxes.length; i++) {
      var img = R_selFirst(boxes[i], 'img');
      var a = R_selFirst(boxes[i], 'a');
      if (!a) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      out.push({ key: R_path(href), title: a.attr('title') || a.text(), coverUrl: img ? img.absUrl('src') : '' });
    }
    var curEl = R_selFirst(doc, '.current');
    var totalEl = R_selFirst(doc, '.pagination strong');
    var cur = curEl ? parseInt(curEl.text(), 10) : NaN;
    var total = totalEl ? parseInt(totalEl.text(), 10) : NaN;
    return { mangas: out, hasNextPage: !isNaN(cur) && !isNaN(total) && cur < total };
  },

  getSearchManga: async function (page, query) {
    if (!query) {
      var t0 = await $.http.get(BASE + '/new.html');
      var doc0 = $.html.parse(t0);
      var out0 = [];
      var boxes0 = R_sel(doc0, '.related_box');
      for (var b = 0; b < boxes0.length; b++) {
        var a0 = R_selFirst(boxes0[b], 'a');
        if (!a0) { continue; }
        var href0 = a0.absUrl('href');
        if (!href0) { continue; }
        var img0 = R_selFirst(boxes0[b], 'img');
        out0.push({ key: R_path(href0), title: a0.attr('title') || a0.text(), coverUrl: img0 ? img0.absUrl('src') : '' });
      }
      return { mangas: out0, hasNextPage: false };
    }
    var text = await $.http.get(BASE + '/plus/search/index.asp?keyword=' + encodeURIComponent(query) + '&p=' + page);
    var doc = $.html.parse(text);
    var links = R_sel(doc, '.node > p > a');
    var out = [];
    for (var i = 0; i < links.length; i++) {
      var href = links[i].absUrl('href');
      if (!href) { continue; }
      var idm = href.match(/\\d+(?=\\.html)/);
      var thumb = idm ? BASE + '/uploadfile/pic/' + idm[0] + '.jpg' : '';
      out.push({ key: R_path(href), title: links[i].text(), coverUrl: thumb });
    }
    var curEl = R_selFirst(doc, '.current');
    var cur = curEl ? parseInt(curEl.text(), 10) : NaN;
    var pagLinks = R_sel(doc, '.list .pagination a');
    return { mangas: out, hasNextPage: !isNaN(cur) && cur < pagLinks.length };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = parseDoc(text);
    var item2 = R_selFirst(doc, '.item-2');
    var author = '';
    if (item2) {
      var t = item2.text();
      var idx = t.indexOf('模特：');
      if (idx >= 0) { author = t.substring(idx + 3).trim(); }
    }
    return {
      key: mangaKey,
      title: '',
      coverUrl: '',
      author: author,
      description: '',
      genre: '',
      status: 'completed',
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = parseDoc(text);
    var cur = R_selFirst(doc, '.current');
    var titleEl = R_selFirst(doc, '.article-title');
    var dateUpload = 0;
    var item1 = R_selFirst(doc, '.item-1');
    if (item1) {
      var t = item1.text();
      var idx = t.indexOf('更新：');
      if (idx >= 0) {
        var ds = t.substring(idx + 3).trim();
        var ts = Date.parse(ds.replace(/\\./g, '-') + 'T00:00:00+08:00');
        if (!isNaN(ts)) { dateUpload = ts; }
      }
    }
    return [{
      key: cur ? R_path(cur.absUrl('href')) : mangaKey,
      name: titleEl ? titleEl.text() : 'Gallery',
      chapterNumber: 1,
      dateUpload: dateUpload,
      pages: 0,
      sortOrder: 0,
    }];
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = parseDoc(text);
    var cur = R_selFirst(doc, '.current');
    var titleEl = R_selFirst(doc, '.article-title');
    var prefix = (cur ? R_path(cur.absUrl('href')) : chapterKey).replace(/\\.html$/, '');
    var title = titleEl ? titleEl.text() : '';
    var tm = title.match(/\\d+(?=P)/);
    var total = tm ? parseInt(tm[0], 10) : 0;
    var pages = [];
    var v = 0;
    for (var guard = 0; guard < 100; guard++) {
      var url = BASE + prefix + (v === 0 ? '' : '_' + v) + '.html';
      var ptext;
      try {
        ptext = await $.http.get(url);
      } catch (e) {
        break;
      }
      var pdoc = parseDoc(ptext);
      var urls = centeredImgs(pdoc);
      if (urls.length === 0) { break; }
      for (var j = 0; j < urls.length; j++) {
        pages.push({ index: pages.length, url: urls[j] });
      }
      if (total > 0 && pages.length >= total) { break; }
      v++;
    }
    if (total > 0 && pages.length > total) { pages = pages.slice(0, total); }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
