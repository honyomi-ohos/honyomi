// id/shinigami — shinigami.asia JSON API (api.shngm.io), bespoke
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['filters not supported; plain search only'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var API = 'https://api.shngm.io';
var HDRS = { Accept: 'application/json', DNT: '1', 'Sec-GPC': '1', Referer: BASE + '/' };
function apiGet(path) {
  return H_get(API + path, HDRS).then(function (t) { return JSON.parse(t); });
}
function statusMap(v) {
  if (v === 1) { return 'ongoing'; }
  if (v === 2) { return 'completed'; }
  if (v === 3) { return 'hiatus'; }
  return '';
}
function fmtNum(n) {
  var f = parseFloat(n);
  if (isNaN(f)) { return String(n); }
  return String(Math.round(f * 100) / 100);
}
module.exports = {
  getPopularManga: async function (page) {
    var d = await apiGet('/v1/manga/list?page=' + page + '&page_size=30&sort=popularity');
    var out = [];
    for (var i = 0; i < d.data.length; i++) {
      out.push({ key: d.data[i].manga_id, title: d.data[i].title || '', coverUrl: d.data[i].cover_image_url || d.data[i].cover_portrait_url || '' });
    }
    return { mangas: out, hasNextPage: d.meta.page < d.meta.total_page };
  },

  getSearchManga: async function (page, query) {
    var u = '/v1/manga/list?page=' + page + '&page_size=30';
    if (query) { u += '&q=' + encodeURIComponent(query); }
    var d = await apiGet(u);
    var out = [];
    for (var i = 0; i < d.data.length; i++) {
      out.push({ key: d.data[i].manga_id, title: d.data[i].title || '', coverUrl: d.data[i].cover_image_url || d.data[i].cover_portrait_url || '' });
    }
    return { mangas: out, hasNextPage: d.meta.page < d.meta.total_page };
  },

  getMangaDetail: async function (mangaKey) {
    var d = await apiGet('/v1/manga/detail/' + mangaKey);
    var v = d.data;
    var tax = v.taxonomy || {};
    function taxJoin(k) {
      var arr = tax[k] || [];
      var names = [];
      for (var i = 0; i < arr.length; i++) { names.push(arr[i].name); }
      return names.join(', ');
    }
    var desc = v.description || '';
    if (v.alternative_title) {
      desc += (desc ? '\\n\\n' : '') + 'Alternative Title: ' + v.alternative_title;
    }
    var genres = [taxJoin('Genre'), taxJoin('Format')].filter(function (g) { return g; });
    return {
      key: mangaKey,
      title: v.title || '',
      coverUrl: v.cover_portrait_url || v.cover_image_url || '',
      author: taxJoin('Author'),
      artist: taxJoin('Artist'),
      description: desc,
      genre: genres.join(', '),
      status: statusMap(v.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var d = await apiGet('/v1/chapter/' + mangaKey + '/list?page_size=3000');
    var list = d.data || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var name = ('Chapter ' + fmtNum(c.chapter_number) + ' ' + (c.chapter_title || '')).trim();
      out.push({
        key: c.chapter_id,
        name: name,
        chapterNumber: parseFloat(c.chapter_number) || -1,
        dateUpload: Date.parse(c.release_date || '') || 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var d = await apiGet('/v1/chapter/detail/' + chapterKey);
    var v = d.data;
    var names = (v.chapter && v.chapter.data) || [];
    var pages = [];
    for (var i = 0; i < names.length; i++) {
      pages.push({ index: i, url: v.base_url + v.chapter.path + names[i] });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/', Accept: 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8' };
  }
};
`);
}
