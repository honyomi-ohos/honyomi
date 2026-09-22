// all/xasiatalbums — bespoke engine (KVS async-block album lists; single Photobook chapter)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['dynamic category/tag filter not portable (popular + text search only)'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var ITEMS_PER_PAGE = 12;

function hdrs() {
  return { 'Referer': BASE + '/', 'X-Requested-With': 'XMLHttpRequest' };
}
async function fetchBlock(path, blockId, page, params) {
  var from = ((page - 1) * ITEMS_PER_PAGE) + 1;
  var url = BASE + '/' + path + '?mode=async&function=get_block&block_id=' + blockId +
    '&from=' + from;
  if (blockId.indexOf('search') >= 0) { url += '&from_albums=' + from; }
  for (var k in params) { url += '&' + k + '=' + encodeURIComponent(params[k]); }
  url += '&_=' + Date.now();
  var text = await $.http.get(url, hdrs());
  var doc = $.html.parse(text);
  var links = R_sel(doc, '.list-albums .item a[href]');
  var seen = {};
  var out = [];
  for (var i = 0; i < links.length; i++) {
    var link = links[i];
    var url2 = link.absUrl('href');
    if (!url2 || url2.indexOf('/albums/') < 0) { continue; }
    var key = R_path(url2);
    if (seen[key]) { continue; }
    seen[key] = true;
    var title = link.attr('title');
    var img = R_selFirst(link, 'img');
    if (!title && img) { title = img.attr('alt'); }
    var thumb = '';
    if (img) {
      thumb = img.attr('data-original') || img.attr('src') || '';
      if (thumb.indexOf('//') === 0) { thumb = 'https:' + thumb; }
      else if (thumb && thumb.indexOf('http') !== 0) { thumb = BASE + thumb; }
    }
    out.push({ key: key, title: title || '', coverUrl: thumb });
  }
  var hasNext = false;
  var pag = R_sel(doc, '.pagination a[href], .pages a[href], .pager a[href]');
  for (var p = 0; p < pag.length; p++) {
    if (/next/i.test(pag[p].text())) { hasNext = true; break; }
  }
  if (!hasNext) { hasNext = out.length >= ITEMS_PER_PAGE; }
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    return fetchBlock('albums/', 'list_albums_common_albums_list', page, { sort_by: 'album_viewed_week' });
  },

  getSearchManga: async function (page, query) {
    if (!query) {
      return fetchBlock('albums/', 'list_albums_common_albums_list', page, { sort_by: 'post_date' });
    }
    return fetchBlock('search/search/', 'list_albums_albums_list_search_result', page, { q: query });
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), hdrs());
    var doc = $.html.parse(text);
    var title = R_selFirst(doc, '.entry-title');
    var descMeta = R_selFirst(doc, 'meta[property="og:description"]');
    var imgMeta = R_selFirst(doc, 'meta[property="og:image"]');
    var genres = [];
    var infoLinks = R_sel(doc, '.info-content a');
    for (var i = 0; i < infoLinks.length; i++) {
      var a = infoLinks[i];
      var tag = a.text().trim();
      var href = a.absUrl('href');
      if (tag && href.indexOf('/albums/') >= 0) { genres.push(tag); }
    }
    return {
      key: mangaKey,
      title: title ? title.text() : '',
      coverUrl: imgMeta ? imgMeta.attr('content') : '',
      author: '',
      description: descMeta ? descMeta.attr('content') : '',
      genre: genres.join(', '),
      status: 'completed',
    };
  },

  getChapterList: async function (mangaKey) {
    return [{
      key: mangaKey,
      name: 'Photobook',
      chapterNumber: 0,
      dateUpload: Date.now(),
      pages: 0,
      sortOrder: 0,
    }];
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), hdrs());
    var doc = $.html.parse(text);
    var anchors = R_sel(doc, "a.item[href], a[href*='/get_image/']");
    var seen = {};
    var pages = [];
    for (var i = 0; i < anchors.length; i++) {
      var u = anchors[i].absUrl('href');
      if (!u || u.indexOf('/get_image/') < 0 || seen[u]) { continue; }
      seen[u] = true;
      pages.push({ index: pages.length, url: u });
    }
    return pages;
  },

  imageHeaders: function () {
    return { 'Referer': BASE + '/' };
  },
};
`;
}
