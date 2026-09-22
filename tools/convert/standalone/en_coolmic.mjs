// en/coolmic — coolmic.com JSON API; locked chapters require login (free chapters work)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['locked/paid chapters require WebView login (free chapters work)', 'hide-locked-chapters preference not supported'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var API = BASE + '/api/v1';
var CDN = 'https://en-img.' + BASE.replace(/^https?:\\/\\//, '').split('/')[0];
var HDRS = { Referer: BASE + '/', Cookie: 'is_mature=true' };
function coverFor(id) {
  var s = String(id);
  while (s.length < 9) { s = '0' + s; }
  return CDN + '/titles/' + s.substring(0, 3) + '/' + s.substring(0, 6) + '/' + s + '/' + s + '_large_vertical.jpg';
}
function dleDate(v) {
  var m = String(v || '').match(/^(\\d{2})\\/(\\d{2})\\/(\\d{2})$/);
  if (!m) { return 0; }
  return Date.UTC(2000 + parseInt(m[3], 10), parseInt(m[1], 10) - 1, parseInt(m[2], 10));
}
module.exports = {
  getPopularManga: async function (page) {
    var u = API + '/search_titles?keyword=&page=' + page + '&per=20&search_field=all&sort=like_vote';
    var text = await H_get(u, HDRS);
    var res = JSON.parse(text);
    var mangas = (res.results || []).map(function (r) {
      return { key: '/titles/' + r.title_id, title: r.title_name, coverUrl: coverFor(r.title_id) };
    });
    return { mangas: mangas, hasNextPage: page * 20 < res.total };
  },
  getSearchManga: async function (page, query) {
    var u = API + '/search_titles?keyword=' + encodeURIComponent(query) + '&page=' + page + '&per=20&search_field=all&sort=relevance';
    var text = await H_get(u, HDRS);
    var res = JSON.parse(text);
    var mangas = (res.results || []).map(function (r) {
      return { key: '/titles/' + r.title_id, title: r.title_name, coverUrl: coverFor(r.title_id) };
    });
    return { mangas: mangas, hasNextPage: page * 20 < res.total };
  },
  getMangaDetail: async function (key) {
    var text = await H_get(R_abs(key), HDRS);
    var doc = $.html.parse(text);
    var el = R_selFirst(doc, 'title-page');
    if (!el) { throw new Error('page-objects not found'); }
    var obj = JSON.parse(el.attr(':page-objects'));
    var t = obj.title;
    var desc = t.summary || '';
    if (t.agency) { desc += '\\n\\nPublisher: ' + t.agency; }
    if (t.is_mature === true) { desc += '\\n\\nRating: 18+'; }
    var genres = [].concat(t.genres || [], t.sub_genres || [], t.tags || []).map(function (g) { return g.name; });
    var seen = {}; var guniq = [];
    for (var i = 0; i < genres.length; i++) { if (genres[i] && !seen[genres[i]]) { seen[genres[i]] = 1; guniq.push(genres[i]); } }
    var cover = t.vertical_thumbnail_url ? t.vertical_thumbnail_url.replace('_vertical.jpg', '_large_vertical.jpg') : '';
    return {
      key: key,
      title: t.name,
      coverUrl: cover,
      author: (t.artists || []).map(function (a) { return a.name; }).join(', '),
      description: desc,
      genre: guniq.join(', '),
      status: t.is_completed === true ? 'completed' : 'ongoing'
    };
  },
  getChapterList: async function (key) {
    var text = await H_get(R_abs(key), HDRS);
    var doc = $.html.parse(text);
    var el = R_selFirst(doc, 'title-page');
    if (!el) { throw new Error('page-objects not found'); }
    var obj = JSON.parse(el.attr(':page-objects'));
    var eps = obj.episodes || [];
    var out = [];
    for (var i = 0; i < eps.length; i++) {
      var e = eps[i];
      var locked = e.is_free === false && e.was_purchased === false;
      out.push({
        key: '/episodes/' + e.id,
        name: (locked ? '\\uD83D\\uDD12 ' : '') + 'Chapter ' + e.number,
        chapterNumber: e.display_order !== undefined && e.display_order !== null ? e.display_order : -1,
        dateUpload: dleDate(e.start_at),
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },
  getPageList: async function (chapterKey) {
    var id = chapterKey.replace(/^\\/episodes\\//, '');
    var text = await H_get(API + '/viewer/comic/secure_episodes/' + id, HDRS);
    var res = JSON.parse(text);
    if (!res.image_data) { throw new Error('Log in via WebView and purchase this chapter to read.'); }
    var pages = [];
    for (var i = 0; i < res.image_data.length; i++) {
      pages.push({ index: res.image_data[i].num - 1, url: res.image_data[i].path });
    }
    pages.sort(function (a, b) { return a.index - b.index; });
    return pages;
  },
  imageHeaders: function () { return { Referer: BASE + '/', Cookie: 'is_mature=true' }; }
};
`);
}
