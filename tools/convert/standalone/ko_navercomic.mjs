// ko/navercomic — Naver Webtoon (first source of the 3-source ext)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    // policy: one plugin from the first source; the other flavors differ only by mType
    return {
      ok: true,
      config: {},
      warnings: [
        'multi-source ext: only the first source (Naver Webtoon) is provided; "Naver Webtoon Best Challenge" and "Naver Webtoon Challenge" flavors are not included',
      ],
    };
  }
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  const body = String.raw`
var M = 'https://m.comic.naver.com';
var HDRS = { Referer: BASE + '/' };

function titleIdOf(key) {
  var m = String(key).match(/titleId=(\d+)/);
  return m ? m[1] : '';
}

// yy.MM.dd (Seoul) -> ms; "HH:mm" (today) -> now
function parseDate(v) {
  var s = String(v || '').trim();
  if (!s) { return 0; }
  if (s.indexOf(':') >= 0) { return Date.now(); }
  var m = s.match(/^(\d{2})\.(\d{1,2})\.(\d{1,2})$/);
  if (m) { return Date.parse('20' + m[1] + '-' + (m[2].length < 2 ? '0' : '') + m[2] + '-' + (m[3].length < 2 ? '0' : '') + m[3] + 'T00:00:00+09:00'); }
  return R_date(s);
}

function apiMangaToItem(mm) {
  var artists = mm.communityArtists || [];
  var names = [];
  for (var i = 0; i < artists.length; i++) { if (artists[i].name) { names.push(artists[i].name); } }
  return {
    key: '/webtoon/list?titleId=' + mm.titleId,
    title: mm.titleName || '',
    coverUrl: mm.thumbnailUrl || '',
    author: names.join(', '),
    description: mm.synopsis || '',
    status: mm.rest ? 'on_hiatus' : (mm.finished ? 'completed' : 'ongoing')
  };
}

function parseMobileWeekday(doc) {
  var out = [];
  var els = R_sel(doc, '.list_toon [class*=item]');
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var cls = (el.attr('class') || '').replace(/\s+/g, ' ').trim();
    if (cls !== 'item') { continue; }
    var a = R_selFirst(el, 'a');
    var strong = R_selFirst(el, 'strong');
    if (!a || !strong) { continue; }
    var href = a.absUrl('href') || a.attr('href') || '';
    var m = href.match(/titleId=(\d+)/);
    if (!m) { continue; }
    var img = R_selFirst(el, 'img');
    var authorEl = R_selFirst(el, 'span.author');
    out.push({
      key: '/webtoon/list?titleId=' + m[1],
      title: strong.text(),
      coverUrl: img ? (img.absUrl('src') || img.attr('src') || '') : '',
      author: authorEl ? authorEl.text().split(' / ').join(', ') : ''
    });
  }
  return { mangas: out, hasNextPage: false };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseMobileWeekday(await H_doc(M + '/webtoon/weekday?sort=ALL_READER', HDRS));
  },

  getLatestManga: async function (page) {
    return parseMobileWeekday(await H_doc(M + '/webtoon/weekday?sort=UPDATE', HDRS));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/api/search/webtoon?keyword=' + encodeURIComponent(query) + '&page=' + page;
    var json = $.json.parse(await H_get(u, HDRS));
    return {
      mangas: (json.searchList || []).map(apiMangaToItem),
      hasNextPage: !!(json.pageInfo && json.pageInfo.nextPage)
    };
  },

  getMangaDetail: async function (mangaKey) {
    var id = titleIdOf(mangaKey);
    var json = $.json.parse(await H_get(BASE + '/api/article/list/info?titleId=' + id, HDRS));
    var d = apiMangaToItem(json);
    d.key = mangaKey;
    return d;
  },

  getChapterList: async function (mangaKey) {
    var id = titleIdOf(mangaKey);
    var out = [];
    var page = 1;
    while (page > 0) {
      var json = $.json.parse(await H_get(BASE + '/api/article/list?titleId=' + id + '&page=' + page, HDRS));
      var list = json.articleList || [];
      for (var i = 0; i < list.length; i++) {
        var c = list[i];
        out.push({
          key: '/webtoon/detail?titleId=' + json.titleId + '&no=' + c.no,
          name: c.subtitle || '',
          chapterNumber: c.no,
          dateUpload: parseDate(c.serviceDateDescription),
          pages: 0,
          sortOrder: 0
        });
      }
      var next = json.pageInfo ? json.pageInfo.nextPage : 0;
      if (!next || !list.length) { break; }
      page = next;
      if (out.length > 3000) { break; }
    }
    // API serves newest first; plugin contract wants oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), HDRS);
    var imgs = R_sel(doc, '.wt_viewer img');
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src') || imgs[i].attr('src') || '';
      if (u) { out.push({ index: out.length, url: u }); }
    }
    if (!out.length) {
      var imgs2 = R_sel(doc, '.toon_view_lst img.toon_image');
      for (var k = 0; k < imgs2.length; k++) {
        var u2 = imgs2[k].absUrl('data-src') || imgs2[k].absUrl('src') || imgs2[k].attr('src') || '';
        if (u2) { out.push({ index: out.length, url: u2 }); }
      }
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
