// ja/mangameets — JSON API (manga-meets)
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
var API = BASE + '/api';

async function listManga(page, query) {
  var u = API + '/comics/search.json?size=20&page=' + page + (query ? '&keywords=' + encodeURIComponent(query) : '&sort=weekly_view_count');
  var json = $.json.parse(await H_get(u));
  var included = json.included || [];
  var comics = [];
  var images = [];
  for (var i = 0; i < included.length; i++) {
    if (included[i].type === 'comic') { comics.push(included[i]); }
    else if (included[i].type === 'image') { images.push(included[i]); }
  }
  var out = [];
  for (var c = 0; c < comics.length; c++) {
    var dirName = (comics[c].attributes || {}).dir_name;
    if (!dirName) { continue; }
    var img = images[c] ? (images[c].attributes || {}).url : '';
    out.push({ key: '/comics/' + dirName, title: (comics[c].attributes || {}).title || dirName, coverUrl: img || '' });
  }
  var attrs = (json.data || {}).attributes || {};
  return { mangas: out, hasNextPage: (attrs.current_page || 1) < (attrs.total_page || 1) };
}

function dirFromKey(key) {
  var m = String(key).match(/\/comics\/([^\/]+)/);
  return m ? m[1] : String(key);
}

module.exports = {
  getPopularManga: function (page) { return listManga(page, ''); },

  getSearchManga: function (page, query) { return listManga(page, query); },

  getMangaDetail: async function (mangaKey) {
    var dir = dirFromKey(mangaKey);
    var json = $.json.parse(await H_get(API + '/comics/' + dir + '.json'));
    var included = json.included || [];
    var imageMap = {};
    var genreMap = {};
    for (var i = 0; i < included.length; i++) {
      if (included[i].type === 'image') { imageMap[included[i].id] = (included[i].attributes || {}).url; }
      else if (included[i].type === 'comic_genre') { genreMap[included[i].id] = (included[i].attributes || {}).name; }
    }
    var d = json.data || {};
    var a = d.attributes || {};
    var rel = d.relationships || {};
    var genreId = rel.comic_genre && rel.comic_genre.data ? rel.comic_genre.data.id : '';
    var thumbId = rel.thumbnail_image && rel.thumbnail_image.data ? rel.thumbnail_image.data.id : '';
    return {
      key: mangaKey,
      title: a.title || dir,
      coverUrl: thumbId ? (imageMap[thumbId] || '') : '',
      author: (a.authors || []).join(', '),
      description: a.outline || '',
      genre: genreId ? (genreMap[genreId] || '') : '',
      status: a.finished === true ? 'completed' : 'ongoing'
    };
  },

  getChapterList: async function (mangaKey) {
    var dir = dirFromKey(mangaKey);
    var json = $.json.parse(await H_get(API + '/comics/' + dir + '/episodes.json'));
    var list = json.data || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var a = list[i].attributes || {};
      var t = a.title ? ' - ' + a.title : '';
      out.push({
        key: '/comics/' + dir + '/' + (a.sort_volume !== undefined ? a.sort_volume : i),
        name: 'Chapter ' + (a.volume || '') + t,
        chapterNumber: a.sort_volume !== undefined ? a.sort_volume : -1,
        dateUpload: a.published_at ? Date.parse(a.published_at) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = String(chapterKey).split('/');
    var dir = parts[2] || '';
    var nr = parts[3] || '';
    var json = $.json.parse(await H_get(API + '/comics/' + dir + '/episodes/' + nr + '/viewer.json'));
    var pages = (json.episode_pages || []).slice(0);
    pages.sort(function (a, b) { return (a.order_index || 0) - (b.order_index || 0); });
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      var u = pages[i].image ? pages[i].image.original_url : '';
      if (u) { out.push({ index: out.length, url: u }); }
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
