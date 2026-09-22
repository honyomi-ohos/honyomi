// ja/mangaupjapan — Manga UP (manga-up.com) — HTML + RSC flight payload
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  const body = String.raw`
async function parseList(url) {
  var doc = await H_doc(url);
  var items = R_sel(doc, 'div.grid > a');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var href = items[i].absUrl('href');
    if (!href) { continue; }
    out.push({
      key: R_path(href),
      title: H_firstText(items[i], 'div.line-clamp-2') || items[i].text(),
      coverUrl: R_img(R_selFirst(items[i], 'img'))
    });
  }
  return { mangas: out, hasNextPage: false };
}

function findJsonLine(text, marker, endMarker, addClose) {
  var lines = String(text).split('\n');
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf(marker);
    if (idx >= 0) {
      var rest = lines[i].substring(idx + marker.length);
      var end = rest.indexOf(endMarker);
      if (end >= 0) { rest = rest.substring(0, end); }
      if (addClose) { rest = rest + ']'; }
      return rest;
    }
  }
  return '';
}

module.exports = {
  getPopularManga: function () { return parseList(BASE + '/rankings/1'); },

  getSearchManga: function (page, query) {
    return parseList(BASE + '/titles?word=' + encodeURIComponent(query));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var status = '';
    var divs = R_sel(doc, 'div');
    var done = false;
    for (var i = 0; i < divs.length && !done; i++) {
      var t = divs[i].text();
      if (t.indexOf('完結') >= 0) { status = 'completed'; done = true; }
    }
    if (!done) {
      for (var j = 0; j < divs.length; j++) {
        if (divs[j].text().indexOf('更新') >= 0) { status = 'ongoing'; break; }
      }
    }
    return {
      key: mangaKey,
      title: H_firstText(doc, 'h2'),
      coverUrl: R_img(R_selFirst(doc, 'section > img')),
      author: H_texts(doc, 'div.flex.flex-col.gap-2xsmall > div'),
      description: H_firstText(doc, 'h2:contains(あらすじ) + div'),
      genre: H_texts(doc, 'a[href*=/genres/]'),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await H_get(R_abs(mangaKey), { 'rsc': '1' });
    var json = findJsonLine(text, '"chapters":', ',"currentChapter"', false);
    var list = [];
    try { list = $.json.parse(json); } catch (e) { list = []; }
    var parts = String(mangaKey).split('/');
    var titleId = parts[1] || parts[parts.length - 1];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var lock = c.publishingStatus !== 3 ? '🔒 (Preview) ' : '';
      var sub = c.subName ? c.subName + ' - ' : '';
      out.push({
        key: '/titles/' + titleId + '/chapters/' + c.id,
        name: lock + sub + (c.name || ''),
        chapterNumber: -1,
        dateUpload: 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await H_get(R_abs(chapterKey), { 'rsc': '1' });
    var json = findJsonLine(text, '"pages":', '],"', true);
    var list = [];
    try { list = $.json.parse(json); } catch (e) { list = []; }
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var url = list[i].content && list[i].content.value ? (list[i].content.value.imageUrl || '') : '';
      if (url) { out.push({ index: out.length, url: url }); }
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
