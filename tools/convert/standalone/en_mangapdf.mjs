// en/mangapdf — purpose-built JSON API (api.coffeemanga.shop/api/v1/mihon)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.coffeemanga.shop/api/v1/mihon';
var HDRS = { 'X-Client': 'mihon-extension' };

function statusMap(s) {
  var v = String(s || '').toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  if (v === 'licensed') { return 'licensed'; }
  if (v === 'publishing_finished') { return 'publishing finished'; }
  if (v === 'cancelled') { return 'cancelled'; }
  if (v === 'on_hiatus') { return 'on hiatus'; }
  return '';
}

async function api(path) {
  return $.json.parse(await $.http.get(API + path, HDRS));
}

module.exports = {
  getPopularManga: async function (page) {
    var res = await api('/popular?page=' + page);
    return { mangas: (res.items || []).map(function (it) {
      return { key: '/manga/' + it.id, title: it.title || '', coverUrl: it.thumbnail_url || '' };
    }), hasNextPage: res.has_next === true };
  },

  getSearchManga: async function (page, query) {
    var res = await api('/search?q=' + encodeURIComponent(query || '') + '&page=' + page);
    return { mangas: (res.items || []).map(function (it) {
      return { key: '/manga/' + it.id, title: it.title || '', coverUrl: it.thumbnail_url || '' };
    }), hasNextPage: res.has_next === true };
  },

  getMangaDetail: async function (mangaKey) {
    var id = String(mangaKey).replace(/^\\/manga\\//, '');
    var res = await api('/manga/' + encodeURIComponent(id));
    var m = res.manga || {};
    return {
      key: mangaKey,
      title: m.title || '',
      coverUrl: m.thumbnail_url || '',
      author: m.author || '',
      artist: m.artist || '',
      description: m.description || '',
      genre: (m.genres || []).join(', '),
      status: statusMap(m.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var id = String(mangaKey).replace(/^\\/manga\\//, '');
    var res = await api('/manga/' + encodeURIComponent(id));
    var chapters = res.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var ch = chapters[i];
      var dv = ch.uploaded_at ? (Date.parse(ch.uploaded_at) || 0) : 0;
      out.push({
        key: '/chapter/' + ch.id,
        name: ch.name || '',
        chapterNumber: typeof ch.number === 'number' ? ch.number : -1,
        dateUpload: dv,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).replace(/^\\/chapter\\//, '');
    var res = await api('/chapter/' + encodeURIComponent(id) + '/pages');
    var pages = res.pages || [];
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].image_url) { out.push({ index: out.length, url: pages[i].image_url }); }
    }
    return out;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
