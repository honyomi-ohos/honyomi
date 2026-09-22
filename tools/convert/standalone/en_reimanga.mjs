// en/reimanga — bespoke JSON + RSC scraper (trending/popular API, Next.js chapter & page payloads)
export const runtime = 'wp';

import { RSC_SRC } from './_nextjs.mjs';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['adult cookie (showAdultContent=true) sent on every request to mirror source client config'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/', Cookie: 'showAdultContent=true' };
var RSC_HDRS = { Referer: BASE + '/', Cookie: 'showAdultContent=true', rsc: '1' };
${RSC_SRC}
function toManga(m) {
  return {
    key: m.name_url + '-' + m.id,
    title: m.title || '',
    coverUrl: m.cover_url ? R_abs(m.cover_url) : BASE + '/covers/' + m.id + '/thumbnail.png'
  };
}
function searchUrl(page, query, sort) {
  var u = BASE + '/api/manga?page=' + page + '&limit=24';
  if (query) { u += '&search=' + encodeURIComponent(query.trim()); }
  if (sort) { u += '&sort=' + sort + '&order=desc'; }
  return u;
}
async function fetchList(u) {
  var data = $.json.parse(await $.http.get(u, HDRS));
  var list = (data && data.data) || [];
  var out = [];
  for (var i = 0; i < list.length; i++) { out.push(toManga(list[i])); }
  var hasNext = false;
  if (data && data.pagination) {
    hasNext = (data.pagination.currentPage || 0) < (data.pagination.totalPages || 0);
  }
  return { mangas: out, hasNextPage: hasNext };
}
async function fetchApiManga(mangaKey) {
  var requestId = String(mangaKey).split('-').pop();
  var page = $.json.parse(await $.http.get(BASE + '/api/manga/' + requestId, HDRS));
  var m = page && page.manga;
  if (!m) { return null; }
  var resolvedId = (m.main_manga_id && m.main_manga_id > 0) ? m.main_manga_id : m.id;
  if (String(resolvedId) !== String(requestId)) {
    page = $.json.parse(await $.http.get(BASE + '/api/manga/' + resolvedId, HDRS));
    m = page && page.manga;
  }
  return m;
}
function chapterPageUrl(m) {
  if (m.main_manga_id && m.main_manga_id > 0 && m.main_name_url) {
    return BASE + '/manga/' + m.main_name_url + '-' + m.main_manga_id;
  }
  return BASE + '/manga/' + m.name_url + '-' + m.id;
}
function buildDescription(m) {
  var parts = [];
  if (typeof m.rating === 'number' && m.rating > 0) {
    var filled = Math.round(m.rating / 2);
    if (filled < 0) { filled = 0; }
    if (filled > 5) { filled = 5; }
    var stars = '';
    for (var i = 0; i < 5; i++) { stars += i < filled ? '★' : '☆'; }
    parts.push(stars + ' ' + m.rating);
  }
  var desc = (m.ai_description || m.description || '').trim();
  if (desc) { parts.push(desc); }
  if (m.alt_title && m.alt_title.trim()) {
    var lines = ['Alternative Titles:'];
    var titles = String(m.alt_title).split(/[,;]/);
    for (var j = 0; j < titles.length; j++) {
      var t = titles[j].trim();
      if (t) { lines.push('- ' + t); }
    }
    parts.push(lines.join('\\n'));
  }
  return parts.join('\\n\\n');
}

module.exports = {
  getPopularManga: async function (page) {
    if (page > 1) {
      return fetchList(searchUrl(page - 1, '', 'viewed'));
    }
    var list = $.json.parse(await $.http.get(BASE + '/api/manga/trending?limit=100', HDRS));
    var out = [];
    for (var i = 0; i < list.length; i++) { out.push(toManga(list[i])); }
    return { mangas: out, hasNextPage: true };
  },

  getSearchManga: async function (page, query) {
    return fetchList(searchUrl(page, query, ''));
  },

  getMangaDetail: async function (mangaKey) {
    var m = await fetchApiManga(mangaKey);
    if (!m) {
      return { key: mangaKey, title: '', coverUrl: '', author: '', description: '', genre: '', status: '' };
    }
    var genres = [];
    if (m.is_adult === 1) { genres.push('Adult'); }
    var gl = m.genres || [];
    for (var i = 0; i < gl.length; i++) { genres.push(String(gl[i].name || '').trim()); }
    var tl = m.tags || [];
    for (var j = 0; j < tl.length; j++) { genres.push(String(tl[j].name || '').trim()); }
    var authors = m.authors || [];
    var anames = [];
    for (var k = 0; k < authors.length; k++) {
      var an = String(authors[k].name || '').trim();
      if (an.slice(-1) === ',') { an = an.slice(0, -1).trim(); }
      anames.push(an);
    }
    return {
      key: mangaKey,
      title: m.title || '',
      coverUrl: m.cover_url ? R_abs(m.cover_url) : BASE + '/covers/' + m.id + '/thumbnail.png',
      author: anames.join(', '),
      description: buildDescription(m),
      genre: genres.join(', '),
      status: m.completed === 1 ? 'completed' : 'ongoing'
    };
  },

  getChapterList: async function (mangaKey) {
    var m = await fetchApiManga(mangaKey);
    if (!m) { return []; }
    var text = await $.http.get(chapterPageUrl(m), RSC_HDRS);
    var rows = RSC.parse(text);
    var data = RSC.find(rows, ['manga', 'chapters']);
    var chapters = [];
    if (data) {
      var slug = data.manga.name_url + '-' + data.manga.id;
      var list = data.chapters || [];
      for (var i = 0; i < list.length; i++) {
        var c = list[i];
        var dateStr = c.gdrive_upload_date || c.updated_at || c.created_at || '';
        chapters.push({
          key: '/manga/' + slug + '/' + c.id,
          name: String(c.name || '').replace(/\\s+/g, ' ').trim(),
          chapterNumber: -1,
          dateUpload: dateStr ? (Date.parse(dateStr) || 0) : 0,
          pages: 0,
          sortOrder: 0
        });
      }
    }
    chapters.reverse();
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), RSC_HDRS);
    var rows = RSC.parse(text);
    var images = RSC.arr(rows, 'images') || [];
    var pages = [];
    for (var i = 0; i < images.length; i++) {
      var u = R_abs(images[i].image_url || '');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
