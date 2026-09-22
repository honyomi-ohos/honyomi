// id/soulscans — v1.soulscans.org JSON API (dreamteams-style, bespoke)
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
var HDRS = { Referer: BASE + '/' };
function statusMap(v) {
  v = String(v || '').toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  if (v === 'hiatus') { return 'hiatus'; }
  if (v === 'cancelled' || v === 'dropped') { return 'cancelled'; }
  return '';
}
function fmtNum(n) {
  var f = parseFloat(n);
  if (isNaN(f)) { return String(n); }
  return String(Math.round(f * 100) / 100);
}
module.exports = {
  getPopularManga: async function (page) {
    var d = JSON.parse(await H_get(BASE + '/api/search?type=COMIC&limit=20&page=' + page + '&sort=popular', HDRS));
    var out = [];
    for (var i = 0; i < d.data.length; i++) {
      out.push({ key: '/comic/' + d.data[i].slug, title: d.data[i].title || '', coverUrl: d.data[i]['poster_image_url'] || '' });
    }
    return { mangas: out, hasNextPage: page < d['total_pages'] };
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/api/search?type=COMIC&limit=20&page=' + page;
    if (query) { u += '&q=' + encodeURIComponent(query); }
    var d = JSON.parse(await H_get(u, HDRS));
    var out = [];
    for (var i = 0; i < d.data.length; i++) {
      out.push({ key: '/comic/' + d.data[i].slug, title: d.data[i].title || '', coverUrl: d.data[i]['poster_image_url'] || '' });
    }
    return { mangas: out, hasNextPage: page < d['total_pages'] };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/comic\\//, '');
    var d = JSON.parse(await H_get(BASE + '/api/series/comic/' + slug, HDRS));
    var genres = [];
    var gl = d.genres || [];
    for (var i = 0; i < gl.length; i++) { genres.push(gl[i].name); }
    return {
      key: '/comic/' + d.slug,
      title: d.title || '',
      coverUrl: d['poster_image_url'] || '',
      author: d['author_name'] || '',
      artist: d['artist_name'] || '',
      description: d.synopsis || '',
      genre: genres.join(', '),
      status: statusMap(d['comic_status'])
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/comic\\//, '');
    var d = JSON.parse(await H_get(BASE + '/api/series/comic/' + slug, HDRS));
    var out = [];
    var units = d.units || [];
    for (var i = 0; i < units.length; i++) {
      var u = units[i];
      out.push({
        key: '/comic/' + d.slug + '/chapter/' + u.slug,
        name: 'Chapter ' + fmtNum(u.number),
        chapterNumber: parseFloat(u.number) || -1,
        dateUpload: Date.parse(u['created_at'] || '') || 0,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var d = JSON.parse(await H_get(BASE + '/api/series' + String(chapterKey), HDRS));
    var list = (d.chapter && d.chapter.pages) || [];
    var pages = [];
    for (var i = 0; i < list.length; i++) {
      pages.push({ index: i, url: list[i]['image_url'] });
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
