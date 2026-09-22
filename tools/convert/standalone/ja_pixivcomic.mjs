// ja/pixivcomic — Pixiv Comic (free episodes; JSON API + Next.js salt hash)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: [
      'store volumes (Publus viewer, e.g. purchased books) are excluded; only free web episodes are supported',
      'store tab excluded from search; serial works only',
      'locked chapters are listed but reading them will fail (login/purchase required)',
    ],
  };
}

export function generate(manifest) {
  const body = String.raw`
var API = BASE + '/api/app';
var HDRS = { 'X-Requested-With': 'pixivcomic', Referer: BASE + '/' };

// mirrors Kotlin: drop first two path segments (pximg resize prefix)
function stripSegs(u) {
  var m = String(u).match(/^(https?:\/\/[^\/]+)(\/.*)$/);
  if (!m) { return u; }
  var segs = m[2].split('/');
  segs.splice(1, 2);
  return m[1] + segs.join('/');
}

function workToManga(w) {
  return {
    key: String(w.id),
    title: w.name || String(w.id),
    coverUrl: w.image && w.image.main_big ? stripSegs(w.image.main_big) : ''
  };
}

function hasNext(d) {
  return d.next_page_number !== null && d.next_page_number !== undefined || !!d.next_url;
}

async function latest(page) {
  var json = $.json.parse(await H_get(API + '/works/recent_updates/v2?page=' + page, HDRS));
  var d = json.data || {};
  var works = d.official_works || [];
  return { mangas: works.map(workToManga), hasNextPage: hasNext(d) };
}

module.exports = {
  getPopularManga: async function (page) {
    var count = 30 * page;
    var u = API + '/rankings/popularity?label=' + encodeURIComponent('総合') + '&count=' + count;
    var json = $.json.parse(await H_get(u, HDRS));
    var ranking = (json.data || {}).ranking || [];
    var start = (page - 1) * 30;
    var slice = ranking.slice(start, start + 30);
    return { mangas: slice.map(workToManga), hasNextPage: slice.length > 0 && ranking.length >= count };
  },

  getLatestManga: latest,

  getSearchManga: async function (page, query) {
    var u = API + '/works/search/v2/' + encodeURIComponent(query) + '?page=' + page;
    var json = $.json.parse(await H_get(u, HDRS));
    var d = json.data || {};
    return { mangas: (d.official_works || []).map(workToManga), hasNextPage: hasNext(d) };
  },

  getMangaDetail: async function (mangaKey) {
    var json = $.json.parse(await H_get(API + '/works/v5/' + mangaKey, HDRS));
    var w = (json.data || {}).official_work || {};
    var genres = [];
    var cats = w.categories || [];
    var tags = w.tags || [];
    for (var i = 0; i < cats.length; i++) { if (cats[i] && cats[i].name) genres.push(cats[i].name); }
    for (var j = 0; j < tags.length; j++) { if (tags[j] && tags[j].name) genres.push(tags[j].name); }
    var desc = String(w.description || '').replace(/<[^>]*>/g, '');
    if (w.magazine && w.magazine.name) { desc += (desc ? '\n\n' : '') + 'Magazine: ' + w.magazine.name; }
    return {
      key: String(w.id || mangaKey),
      title: w.name || String(mangaKey),
      coverUrl: w.image && w.image.main_big ? stripSegs(w.image.main_big) : '',
      author: w.author || '',
      description: desc,
      genre: genres.join(', '),
      status: 'unknown'
    };
  },

  getChapterList: async function (mangaKey) {
    var u = API + '/works/' + mangaKey + '/episodes/v2?order=desc';
    var json = $.json.parse(await H_get(u, HDRS));
    var eps = (json.data || {}).episodes || [];
    var out = [];
    for (var i = 0; i < eps.length; i++) {
      var e = eps[i] && eps[i].episode;
      if (!e) { continue; }
      var lock = e.state && e.state !== 'readable' ? '🔒 ' : '';
      var sub = e.sub_title ? ': ' + e.sub_title : '';
      out.push({
        key: String(e.id),
        name: lock + (e.numbering_title || '') + sub,
        chapterNumber: -1,
        dateUpload: e.read_start_at || 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // API returned desc (newest first); plugin contract wants oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var html = await H_get(BASE + '/viewer/stories/' + chapterKey, HDRS);
    var m = html.match(/"salt"\s*:\s*"([^"]*)"/);
    var salt = m ? m[1] : '';
    var time = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
    var hash = $.crypto.sha256(time + salt);
    var json = $.json.parse(await H_get(API + '/episodes/' + chapterKey + '/read_v4', {
      'X-Requested-With': 'pixivcomic',
      Referer: BASE + '/',
      'X-Client-Time': time,
      'X-Client-Hash': hash
    }));
    var pages = ((json.data || {}).reading_episode || {}).pages || [];
    if (!pages.length) {
      throw new Error('Log in via WebView and purchase this chapter to read.');
    }
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      var u = pages[i].url ? stripSegs(pages[i].url) : '';
      if (u) { out.push({ index: out.length, url: u }); }
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/', 'X-Requested-With': 'pixivcomic' }; }
};
`;
  return wrap(manifest, body);
}
