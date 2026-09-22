// en/sacachispa — bespoke JSON + HTML + RSC scraper
export const runtime = 'wp';

import { RSC_SRC } from './_nextjs.mjs';

export function extract(ctx) {
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };
${RSC_SRC}
function parseSeriesList(text) {
  var dto = $.json.parse(text);
  var items = (dto && dto.items) || [];
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var s = items[i];
    out.push({
      key: s.slug,
      title: s.title || '',
      coverUrl: R_abs(s.cover_image_url || '')
    });
  }
  var hasNext = false;
  if (dto) { hasNext = (dto.page || 0) < (dto.totalPages || 0); }
  return { mangas: out, hasNextPage: hasNext };
}
function textAfter(root, selector, marker) {
  var els = R_sel(root, selector);
  for (var i = 0; i < els.length; i++) {
    var t = String(els[i].text() || '');
    if (t.indexOf(marker) >= 0) {
      return t.substring(t.indexOf(marker) + marker.length).trim();
    }
  }
  return '';
}

module.exports = {
  getPopularManga: async function (page) {
    return parseSeriesList(await $.http.get(BASE + '/api/series?page=' + page + '&pageSize=24', HDRS));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/api/series?page=' + page + '&pageSize=24&search=' + encodeURIComponent(query || '');
    return parseSeriesList(await $.http.get(u, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(BASE + '/series/' + mangaKey, HDRS));
    var title = (R_selFirst(doc, 'h1.font-heading') || { text: function () { return ''; } }).text();
    var desc = (R_selFirst(doc, 'p.max-w-2xl') || { text: function () { return ''; } }).text();
    var author = textAfter(doc, 'span', 'Author:');
    var artist = textAfter(doc, 'span', 'Artist:');
    var status = '';
    var badges = R_sel(doc, 'span[data-slot=badge]');
    for (var i = 0; i < badges.length; i++) {
      var bt = String(badges[i].text() || '').toLowerCase();
      if (bt === 'ongoing') { status = 'ongoing'; break; }
      if (bt === 'completed') { status = 'completed'; break; }
    }
    var genres = [];
    var gels = R_sel(doc, 'a[href^="/browse?genre="] span');
    for (var j = 0; j < gels.length; j++) { genres.push(gels[j].text()); }
    var cover = '';
    var img = R_selFirst(doc, 'div.aspect-\\\\[2\\\\/3\\\\] img');
    if (!img) { img = R_selFirst(doc, 'div[class*="aspect-"] img'); }
    if (img) { cover = R_abs(img.attr('src') || ''); }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: author,
      artist: artist,
      description: desc,
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(BASE + '/series/' + mangaKey, HDRS);
    var rows = RSC.parse(text);
    var data = RSC.find(rows, ['chapters']);
    var chapters = [];
    if (data) {
      var list = data.chapters || [];
      for (var i = 0; i < list.length; i++) {
        var c = list[i];
        var n = typeof c.chapter_number === 'number' ? c.chapter_number : parseFloat(c.chapter_number);
        var numStr = String(c.chapter_number).replace(/\\.0$/, '');
        var nm = 'Chapter ' + numStr;
        if (c.title && String(c.title).trim()) { nm += ' - ' + c.title; }
        chapters.push({
          key: '/series/' + mangaKey + '/chapter/' + numStr,
          name: nm,
          chapterNumber: isNaN(n) ? -1 : n,
          dateUpload: c.created_at ? (Date.parse(c.created_at) || 0) : 0,
          pages: 0,
          sortOrder: 0
        });
      }
    }
    chapters.sort(function (a, b) { return a.chapterNumber - b.chapterNumber; });
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), HDRS);
    var rows = RSC.parse(text);
    var holder = RSC.walk(rows, function (v) {
      return !!v && typeof v === 'object' && !Array.isArray(v) &&
        !!v.chapter && typeof v.chapter === 'object' && Array.isArray(v.chapter.pages);
    });
    var urls = holder ? (holder.chapter.pages || []) : [];
    var pages = [];
    for (var i = 0; i < urls.length; i++) {
      var u = R_abs(urls[i]);
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
