// all/pornpics — bespoke engine (JSON gallery lists + html gallery pages)
// Multi-source ext (en/zh); converter emits one plugin from the first baseUrl.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['multi-language ext collapsed to single plugin (lang=en); category/tag/pornstar filters not portable'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var PAGE_SIZE = 19;
var SELECTOR = '#main li.thumbwook > a.rel-link';

function parseJsonList(text) {
  var arr = JSON.parse(text);
  var mangas = [];
  for (var i = 0; i < arr.length; i++) {
    var it = arr[i];
    mangas.push({
      key: R_path(it.g_url || it.url),
      title: it.desc || '',
      coverUrl: it.t_url || '',
    });
  }
  var hasNext = mangas.length > PAGE_SIZE;
  if (hasNext) { mangas = mangas.slice(0, PAGE_SIZE); }
  return { mangas: mangas, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    var url = BASE + '/popular/api/galleries/list/?limit=' + (PAGE_SIZE + 1) +
      '&offset=' + ((page - 1) * PAGE_SIZE) + '&lang=en&period=1&category_id=2586';
    return parseJsonList(await $.http.get(url));
  },

  getSearchManga: async function (page, query) {
    var url = BASE + '/search/srch.php?lang=en&limit=' + (PAGE_SIZE + 1) +
      '&offset=' + ((page - 1) * PAGE_SIZE) + '&q=' + encodeURIComponent(query);
    return parseJsonList(await $.http.get(url));
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var first = R_selFirst(doc, SELECTOR);
    var img = first ? R_selFirst(first, 'img') : null;
    var info = R_selFirst(doc, 'div.gallery-info.to-gall-info');
    var author = '';
    var genre = [];
    var description = '';
    if (info) {
      var items = R_sel(info, 'div.gallery-info__item');
      for (var i = 0; i < items.length; i++) {
        var links = R_sel(items[i], 'a');
        if (i === 1 && links.length > 0) {
          var names = [];
          for (var j = 0; j < links.length; j++) { names.push(links[j].text()); }
          author = names.join(', ');
        } else if (links.length > 0) {
          for (var k = 0; k < links.length; k++) { genre.push(links[k].text()); }
        }
      }
      var descEl = R_sel(info, 'div.gallery-info__item');
      if (descEl.length > 3) { description = descEl[3].text(); }
    }
    return {
      key: mangaKey,
      title: img ? img.attr('alt') : '',
      coverUrl: img ? R_img(img) : '',
      author: author,
      description: description,
      genre: genre.join(', '),
      status: 'completed',
    };
  },

  getChapterList: async function (mangaKey) {
    return [{
      key: mangaKey,
      name: 'Gallery',
      chapterNumber: 0,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0,
    }];
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var links = R_sel(doc, SELECTOR);
    var pages = [];
    for (var i = 0; i < links.length; i++) {
      var href = links[i].absUrl('href');
      if (href) { pages.push({ index: pages.length, url: href }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
