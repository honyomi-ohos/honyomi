// en/mangade — JSON API at api.mangade.io
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['filters not ported; search + popular only'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke JSON API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.mangade.io/api';

function parseList(text, page) {
  var r = $.json.parse(text);
  var d = r.data || {};
  var list = d.list || [];
  var mangas = [];
  for (var i = 0; i < list.length; i++) {
    var m = list[i];
    mangas.push({ key: '/comics/' + m.id, title: m.name || '', coverUrl: m.image || '' });
  }
  var cur = parseInt(d.page, 10) || page;
  var total = parseInt(d.totalPage, 10) || 0;
  return { mangas: mangas, hasNextPage: cur < total };
}

function statusMap(s) {
  switch (s) {
    case 'Ongoing': case 'Releasing': return 'ongoing';
    case 'Completed': return 'completed';
    case 'On Hiatus': return 'hiatus';
    default: return '';
  }
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(API + '/comics?page=' + page + '&size=20&sort=most-viewed'), page);
  },

  getSearchManga: async function (page, query) {
    var u = API + '/comics?page=' + page + '&size=20';
    if (query) { u += '&name=' + encodeURIComponent(query); }
    return parseList(await $.http.get(u), page);
  },

  getMangaDetail: async function (mangaKey) {
    var id = mangaKey.replace(/^\\//, '').split('/')[1];
    var text = await $.http.get(API + '/comics/' + id + '/view');
    var d = $.json.parse(text).data || {};
    return {
      key: mangaKey,
      title: d.name || '',
      coverUrl: d.image || '',
      author: '',
      description: d.description || '',
      genre: (d.genre_names || '').replace(/,/g, ', '),
      status: statusMap(d.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var id = mangaKey.replace(/^\\//, '').split('/')[1];
    var text = await $.http.get(API + '/comics/' + id + '/view');
    var d = $.json.parse(text).data || {};
    var chapters = d.news_chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      out.push({
        key: '/chapters/' + c.id,
        name: c.name || '',
        chapterNumber: c.chapter_number !== undefined && c.chapter_number !== null && c.chapter_number !== '' ? parseFloat(c.chapter_number) : -1,
        dateUpload: c.published_date ? Date.parse(String(c.published_date).replace(' ', 'T')) || 0 : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.sort(function (a, b) { return a.chapterNumber - b.chapterNumber; });
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = chapterKey.replace(/^\\//, '').split('/')[1];
    var text = await $.http.get(API + '/chapters/' + id + '/view');
    var d = $.json.parse(text).data || {};
    var imgs = d.chapter_images || [];
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      if (imgs[i].image) { pages.push({ index: i, url: imgs[i].image }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
