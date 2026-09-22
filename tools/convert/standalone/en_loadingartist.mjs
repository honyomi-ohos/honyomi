// en/loadingartist — single-entry webcomic; chapters from search.json
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['single-entry webcomic: search unavailable upstream, popular returns the one entry'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};

function entry() {
  return {
    key: '/archives',
    title: 'Loading Artist',
    coverUrl: BASE + '/img/bg/logo-text_dark.png'
  };
}

module.exports = {
  getPopularManga: async function (page) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    return { mangas: [entry()], hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    if (page > 1 || (query && query.toLowerCase() !== 'loading artist')) {
      return { mangas: [], hasNextPage: false };
    }
    return { mangas: [entry()], hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var e = entry();
    return {
      key: mangaKey,
      title: e.title,
      coverUrl: e.coverUrl,
      author: 'Loading Artist',
      artist: 'Loading Artist',
      description: 'Loading Artist webcomic archives.',
      genre: '',
      status: 'ongoing'
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(BASE + '/search.json');
    var comics = $.json.parse(text);
    var validTypes = ['comic', 'game', 'art'];
    var out = [];
    for (var i = 0; i < comics.length; i++) {
      var c = comics[i];
      if (validTypes.indexOf(c.section) < 0) { continue; }
      out.push({
        key: R_path(c.url),
        name: c.title,
        chapterNumber: -1,
        dateUpload: c.date ? Date.parse(c.date) || 0 : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // search.json is newest-first; return oldest-first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var img = R_selFirst(doc, 'div.main-image-container img');
    var u = img ? R_img(img) : '';
    return u ? [{ index: 0, url: u }] : [];
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
