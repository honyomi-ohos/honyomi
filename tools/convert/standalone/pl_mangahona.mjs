// pl/mangahona — MangaHoNa (api.mangahona.pl JSON API)
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
var API = 'https://api.mangahona.pl/v1';
var CDN = 'https://cdn.mangahona.pl';

function coverUrl(coverImage) {
  if (!coverImage) { return ''; }
  return CDN + '/images.php?url=' + encodeURIComponent(coverImage) + '&w=1900';
}

function mangaEntry(dto) {
  return {
    key: dto.ID,
    title: dto.NAME,
    coverUrl: coverUrl(dto.cover_image)
  };
}

var categoriesCache = null;
async function fetchCategories() {
  if (categoriesCache) { return categoriesCache; }
  try {
    categoriesCache = $.json.parse(await $.http.get(API + '/categories'));
  } catch (e) {
    categoriesCache = null;
  }
  return categoriesCache;
}

async function genreString(genereIds, tagIds) {
  var categories = await fetchCategories();
  if (!categories) { return ''; }
  var out = [];
  var ids = (genereIds || '').split(';');
  for (var i = 0; i < ids.length; i++) {
    var id = ids[i].trim();
    for (var j = 0; j < categories.generes.length; j++) {
      if (categories.generes[j].ID === id) { out.push(categories.generes[j].NAME); break; }
    }
  }
  var tids = (tagIds || '').split(';');
  for (var k = 0; k < tids.length; k++) {
    var tid = tids[k].trim();
    for (var l = 0; l < categories.tags.length; l++) {
      if (categories.tags[l].ID === tid) { out.push(categories.tags[l].NAME); break; }
    }
  }
  return out.join(', ');
}

async function allMangas() {
  var list = $.json.parse(await $.http.get(API + '/manga'));
  return list.map(mangaEntry);
}

module.exports = {
  getPopularManga: async function (page) {
    return { mangas: await allMangas(), hasNextPage: false };
  },

  getLatestManga: async function (page) {
    return { mangas: [], hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var q = (query || '').trim();
    // deeplink support: mangahona.pl/manga/<id> or /czytaj/<id>/...
    if (/^https?:\/\/([^\/]*\.)?mangahona\.pl\//i.test(q)) {
      var m = /mangahona\.pl\/(manga|czytaj)\/([^\/\?]+)/i.exec(q);
      if (m) {
        var dto = $.json.parse(await $.http.get(API + '/manga/' + m[2]));
        return { mangas: [mangaEntry(dto)], hasNextPage: false };
      }
    }
    var all = await allMangas();
    if (!q) { return { mangas: all, hasNextPage: false }; }
    var ql = q.toLowerCase();
    var filtered = [];
    for (var i = 0; i < all.length; i++) {
      if (all[i].title.toLowerCase().indexOf(ql) >= 0) { filtered.push(all[i]); }
    }
    return { mangas: filtered, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var dto = $.json.parse(await $.http.get(API + '/manga/' + encodeURIComponent(mangaKey)));
    var status = 'unknown';
    var s = (dto.STATUS || '').toLowerCase();
    if (s === 'completed') { status = 'completed'; }
    else if (s === 'ongoing') { status = 'ongoing'; }
    return {
      key: dto.ID,
      title: dto.NAME,
      coverUrl: coverUrl(dto.cover_image),
      author: (dto.AUTHOR || '').trim(),
      description: dto.DESCRIPTION ? String(dto.DESCRIPTION).replace(/\r\n/g, '\n').trim() : '',
      genre: await genreString(dto.GENERE, dto.TAG),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var chapters = $.json.parse(await $.http.get(API + '/chapters/' + encodeURIComponent(mangaKey)));
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var dto = chapters[i];
      var ts = dto.DATE ? Date.parse(dto.DATE) : NaN;
      out.push({
        key: '/czytaj/' + mangaKey + '/' + dto.CHAPTER_INDEX,
        name: dto.CHAPTER_NAME,
        chapterNumber: -1,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0
      });
    }
    // API returns newest first; plugin contract wants oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = chapterKey.replace(/^\/czytaj\//, '').split('/');
    var mangaId = parts[0];
    var chapterIndex = parts[1];
    var chapterData = $.json.parse(await $.http.get(API + '/chapterData/' + encodeURIComponent(mangaId) + '/' + encodeURIComponent(chapterIndex)));
    var pages = $.json.parse(chapterData.data);
    var keys = Object.keys(pages);
    keys.sort(function (a, b) { return (parseInt(a, 10) || 0) - (parseInt(b, 10) || 0); });
    var out = [];
    for (var i = 0; i < keys.length; i++) {
      var src = pages[keys[i]] && pages[keys[i]].src;
      if (!src) { continue; }
      out.push({ index: out.length, url: src });
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
