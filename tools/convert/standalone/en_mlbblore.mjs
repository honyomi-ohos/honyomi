// en/mlbblore (api.mobilelegends.com) — Mobile Legends lore comics, form-POST JSON API
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['no real search: search returns popular list (upstream behavior)'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var API = 'https://api.mobilelegends.com';
var PAGE_SIZE = 5;

function absUrl(u) {
  var s = String(u || '');
  if (s.indexOf('//') === 0) { return 'https:' + s; }
  return s;
}

async function albumList(sort, page) {
  var body = 'type=3&sort=' + sort + '&page=' + page + '&page_size=' + PAGE_SIZE + '&lang=en&token=';
  var arr = JSON.parse(await $.http.post(API + '/lore/album/list', body, {
    'Content-Type': 'application/x-www-form-urlencoded'
  }));
  var data = arr.data || [];
  var out = [];
  for (var i = 0; i < data.length; i++) {
    var e = data[i];
    if (e.type !== 3) { continue; }
    out.push({ key: String(e.id), title: e.title || '', coverUrl: absUrl(e.thumb), author: (e.hero_name || '').trim() });
  }
  return { mangas: out, hasNextPage: data.length >= PAGE_SIZE };
}

async function albumDetail(id) {
  var body = 'id=' + encodeURIComponent(id) + '&lang=en&token=';
  var resp = JSON.parse(await $.http.post(API + '/lore/album/detail', body, {
    'Content-Type': 'application/x-www-form-urlencoded'
  }));
  return resp.data || null;
}

module.exports = {
  getPopularManga: async function (page) {
    return albumList(3, page);
  },

  getSearchManga: async function (page, query) {
    return albumList(3, page);
  },

  getMangaDetail: async function (mangaKey) {
    var d = await albumDetail(mangaKey);
    if (!d) {
      return { key: mangaKey, title: '', coverUrl: '', author: '', description: '', genre: '', status: '' };
    }
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: absUrl(d.thumb),
      author: (d.hero_name || '').trim(),
      description: d.share_content || '',
      genre: '',
      status: 'completed'
    };
  },

  getChapterList: async function (mangaKey) {
    var d = await albumDetail(mangaKey);
    if (!d) { return []; }
    return [{
      key: String(d.id),
      name: 'Chapter 1',
      chapterNumber: 1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var d = await albumDetail(chapterKey);
    if (!d) { return []; }
    var content = d.comic_content || [];
    var out = [];
    for (var i = 0; i < content.length; i++) {
      out.push({ index: i, url: absUrl(content[i]) });
    }
    return out;
  },

  imageHeaders: function () {
    return {};
  }
};
`;
}
