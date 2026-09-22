// all/simplyhentai — bespoke JSON-API engine (multi-lang collapsed; english language filter)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['multi-language ext collapsed to single plugin (language filter fixed to English); blacklist/tag filters not portable'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone JSON API)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.simply-hentai.com/v3';
var LANG = 'english';

function objToManga(o) {
  return {
    key: '/' + (o.series && o.series.slug) + '/' + o.slug,
    title: o.title || '',
    coverUrl: (o.preview && o.preview.sizes && o.preview.sizes.thumb) || '',
  };
}
function slugFromKey(key) {
  var parts = String(key).split('/');
  return parts[2] || '';
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(API + '/tag/' + LANG + '?type=language&page=' + page);
    var j = JSON.parse(text);
    var albums = (j.data && j.data.albums) || [];
    return { mangas: albums.map(objToManga), hasNextPage: !!(j.pagination && j.pagination.next) };
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(API + '/search/complex?query=' + encodeURIComponent(query) +
      '&page=' + page + '&blacklist=&filter[language][0]=English');
    var j = JSON.parse(text);
    var data = j.data || [];
    var out = [];
    for (var i = 0; i < data.length; i++) {
      if (data[i] && data[i].object) { out.push(objToManga(data[i].object)); }
    }
    return { mangas: out, hasNextPage: !!(j.pagination && j.pagination.next) };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(API + '/manga/' + slugFromKey(mangaKey));
    var album = JSON.parse(text).data;
    if (!album) { throw new Error('album not found: ' + mangaKey); }
    function joinTags(list) {
      var out = [];
      for (var i = 0; i < (list || []).length; i++) { out.push(list[i].title); }
      return out.join(', ');
    }
    var desc = (album.description ? album.description + '\\n\\n' : '') +
      'Series: ' + (album.series ? album.series.title : '') + '\\n' +
      'Characters: ' + joinTags(album.characters);
    return {
      key: mangaKey,
      title: album.title || '',
      coverUrl: (album.preview && album.preview.sizes && album.preview.sizes.thumb) || '',
      author: joinTags(album.artists),
      description: desc,
      genre: joinTags(album.tags),
      status: '',
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(API + '/manga/' + slugFromKey(mangaKey));
    var album = JSON.parse(text).data;
    if (!album) { throw new Error('album not found: ' + mangaKey); }
    var ts = album.created_at ? Date.parse(album.created_at) : 0;
    return [{
      key: '/' + album.series.slug + '/' + album.slug + '/all-pages',
      name: 'Chapter',
      chapterNumber: 0,
      dateUpload: isNaN(ts) ? 0 : ts,
      pages: 0,
      sortOrder: 0,
    }];
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(API + '/manga/' + slugFromKey(chapterKey) + '/pages');
    var j = JSON.parse(text);
    var pages = (j.data && j.data.pages) || [];
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      var u = pages[i].sizes && pages[i].sizes.full;
      if (u) { out.push({ index: pages[i].page_num, url: u }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
