// pt/mangaflix — JSON API (api.mangaflix.net/v1)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['genre filter browsing approximated by latest list; browse sections truncated to most-read'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.mangaflix.net/v1';

function toManga(it) {
  return {
    key: '/br/manga/' + it._id,
    title: it.name || '',
    coverUrl: (it.poster && it.poster.default_url) || ''
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(API + '/browse');
    var j = $.json.parse(text);
    var sections = j.data || [];
    var out = [];
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].key === 'most-read' && sections[i].items) {
        var items = $.json.parse($.json.stringify(sections[i].items));
        if (items && items.length) {
          for (var k = 0; k < items.length; k++) { out.push(toManga(items[k])); }
        }
      }
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    if (query) {
      var text = await $.http.get(API + '/search/mangas?query=' + encodeURIComponent(query) + '&selected_language=pt-br');
      var j = $.json.parse(text);
      var works = (j.data && j.data.works) || [];
      var out = [];
      for (var i = 0; i < works.length; i++) { out.push(toManga(works[i])); }
      return { mangas: out, hasNextPage: false };
    }
    var lt = await $.http.get(API + '/latest-releases?selected_language=pt-br');
    var lj = $.json.parse(lt);
    var lout = [];
    var list = lj.data || [];
    for (var k = 0; k < list.length; k++) { lout.push(toManga(list[k])); }
    return { mangas: lout, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var text = await $.http.get(API + '/mangas/' + id);
    var d = $.json.parse(text).data || {};
    var author = '';
    if (d.chapters && d.chapters.length > 0 && d.chapters[0].owners && d.chapters[0].owners.length > 0) {
      author = d.chapters[0].owners[0].name || '';
    }
    var genres = [];
    for (var i = 0; i < (d.genres || []).length; i++) { genres.push(d.genres[i].name || ''); }
    return {
      key: mangaKey,
      title: d.name || '',
      coverUrl: (d.poster && d.poster.default_url) || '',
      author: author,
      description: d.description || '',
      genre: genres.join(', '),
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var text = await $.http.get(API + '/mangas/' + id);
    var d = $.json.parse(text).data || {};
    var chapters = d.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      out.push({
        key: '/br/manga/chapter/' + c._id,
        name: (c.name && c.name.trim()) || ('Capítulo ' + (c.number || '')),
        chapterNumber: parseFloat(c.number) || 0,
        dateUpload: c.iso_date ? Date.parse(c.iso_date) || 0 : 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = chapterKey.split('/').pop();
    var text = await $.http.get(API + '/chapters/' + id + '?selected_language=pt-br');
    var j = $.json.parse(text);
    var images = (j.data && j.data.images) || [];
    var out = [];
    for (var i = 0; i < images.length; i++) {
      if (images[i].default_url) { out.push({ index: out.length, url: images[i].default_url }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
