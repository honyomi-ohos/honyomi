// ja/nicovideoseiga — Nicovideo Seiga (nicomanga.jp) JSON API
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['paid (drm.cdn) page images are XOR-encrypted and will not render; free chapters unaffected'],
  };
}

export function generate(manifest) {
  const body = String.raw`
var API = 'https://api.nicomanga.jp/api/v1/app/manga';

function resultList(json) {
  var r = (json.data || {}).result;
  if (!r) { return []; }
  return Array.isArray(r) ? r : [r];
}

module.exports = {
  getPopularManga: async function (page) {
    var json = $.json.parse(await H_get(BASE + '/manga/ajax/ranking?span=total&category=all&page=' + page));
    var out = [];
    for (var i = 0; i < json.length; i++) {
      out.push({
        key: '/comic/' + json[i].id,
        title: json[i].title || '',
        coverUrl: R_abs(json[i].thumbnail_url || '')
      });
    }
    return { mangas: out, hasNextPage: page < 5 };
  },

  getSearchManga: async function (page, query) {
    var url = API + '/contents?mode=keyword&sort=score&q=' + encodeURIComponent(query) + '&limit=20&offset=' + ((page - 1) * 20);
    var json = $.json.parse(await H_get(url));
    var list = resultList(json);
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var m = list[i];
      out.push({
        key: '/comic/' + m.id,
        title: (m.meta || {}).title || '',
        coverUrl: R_abs(((m.meta || {}).square_image_url) || '')
      });
    }
    var hasNext = false;
    if (json.data && json.data.extra) { hasNext = json.data.extra.has_next === true; }
    return { mangas: out, hasNextPage: hasNext };
  },

  getMangaDetail: async function (mangaKey) {
    var id = String(mangaKey).split('/').pop();
    var json = $.json.parse(await H_get(API + '/contents/' + id));
    var m = resultList(json)[0] || {};
    var meta = m.meta || {};
    var status = '';
    if (meta.serial_status === 'serial') { status = 'ongoing'; }
    else if (meta.serial_status === 'concluded') { status = 'completed'; }
    return {
      key: mangaKey,
      title: meta.title || id,
      coverUrl: R_abs(meta.square_image_url || ''),
      author: meta.display_author_name || '',
      description: String(meta.description || '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim(),
      genre: '',
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var id = String(mangaKey).split('/').pop();
    var json = $.json.parse(await H_get(API + '/contents/' + id + '/episodes'));
    var list = resultList(json).filter(function (c) {
      return !c.own_status || c.own_status.sell_status !== 'publication_finished';
    });
    list.sort(function (a, b) { return ((a.meta || {}).number || 0) - ((b.meta || {}).number || 0); });
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var sell = c.own_status ? c.own_status.sell_status : '';
      var prefix = sell === 'selling' ? '\uD83D\uDCB4 ' : (sell === 'pre_selling' ? '\u23F3\uD83D\uDCB4 ' : '');
      out.push({
        key: '/episodes/' + c.id,
        name: prefix + ((c.meta || {}).title || ''),
        chapterNumber: (c.meta || {}).number !== undefined ? (c.meta || {}).number : -1,
        dateUpload: ((c.meta || {}).created_at || 0) * 1000,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).split('/').pop();
    var json = $.json.parse(await H_get(API + '/episodes/' + id + '/frames?enable_webp=true'));
    var list = resultList(json);
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var u = (list[i].meta || {}).source_url || '';
      if (u) { out.push({ index: out.length, url: u }); }
    }
    return out;
  },

  imageHeaders: function () {
    return {
      Referer: BASE + '/',
      accept: 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      pragma: 'no-cache',
      'cache-control': 'no-cache'
    };
  }
};
`;
  return wrap(manifest, body);
}
