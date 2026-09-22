// en/comicland — api.comicland.org JSON API
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return { ok: true, config: {}, warnings: ['category filters not supported'] };
}

export function generate(manifest) {
  return wrap(manifest, `
var API = 'https://api.comicland.org/api';
var HDRS = { Origin: BASE, Referer: BASE + '/' };
function toManga(c) {
  return { key: '/comic/' + c.slug, title: c.title || '', coverUrl: c.cover_url || '' };
}
function parsePage(text) {
  var res = JSON.parse(text);
  var data = res.data;
  if (!data) { return { mangas: [], hasNextPage: false }; }
  var comics = data.list || data.items || [];
  var hasNext = data.has_more !== undefined ? data.has_more : comics.length === 20;
  return { mangas: comics.map(toManga), hasNextPage: hasNext };
}
module.exports = {
  getPopularManga: async function (page) {
    var text = await H_get(API + '/comics/popular?offset=' + ((page - 1) * 20) + '&limit=20', HDRS);
    return parsePage(text);
  },
  getSearchManga: async function (page, query) {
    var offset = (page - 1) * 20;
    var u;
    if (query) {
      u = API + '/comic/search?q=' + encodeURIComponent(query) + '&offset=' + offset + '&limit=20';
    } else {
      u = API + '/comics?offset=' + offset + '&limit=20';
    }
    var text = await H_get(u, HDRS);
    return parsePage(text);
  },
  getMangaDetail: async function (key) {
    var slug = key.replace(/^\\/comic\\//, '');
    var text = await H_get(API + '/comic/detail?slug=' + encodeURIComponent(slug), HDRS);
    var d = JSON.parse(text).data;
    if (!d) { throw new Error('Failed to parse manga details'); }
    return {
      key: key,
      title: d.title || '',
      coverUrl: d.cover_url || '',
      author: (d.authors || []).map(function (a) { return a.name; }).join(', '),
      description: d.description || '',
      genre: (d.genres || []).map(function (g) { return g.name; }).join(', '),
      status: ''
    };
  },
  getChapterList: async function (key) {
    var slug = key.replace(/^\\/comic\\//, '');
    var text = await H_get(API + '/comic/detail?slug=' + encodeURIComponent(slug), HDRS);
    var d = JSON.parse(text).data;
    if (!d) { throw new Error('Failed to parse chapters'); }
    var chapters = d.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var idx = String(c.chapter_index).replace(/\\.0$/, '');
      out.push({
        key: '/comic/' + d.slug + '/chapter/' + idx,
        name: c.title || ('Chapter ' + idx),
        chapterNumber: c.chapter_index,
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
    var rest = chapterKey.replace(/^\\/comic\\//, '');
    var slug = rest.substring(0, rest.indexOf('/chapter/'));
    var index = rest.substring(rest.indexOf('/chapter/') + 9);
    var text = await H_get(API + '/chapter/pages_by_index?slug=' + encodeURIComponent(slug) + '&index=' + encodeURIComponent(index), HDRS);
    var pages = (JSON.parse(text).data || {}).pages || [];
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      out.push({ index: i, url: pages[i] });
    }
    return out;
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
