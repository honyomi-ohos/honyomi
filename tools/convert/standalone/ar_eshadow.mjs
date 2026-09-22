// ar/eshadow — bespoke JSON-API engine
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};

function mangaOut(d) {
  var status = '';
  if (d.status === 'ONGOING') { status = 'ongoing'; }
  else if (d.status === 'COMPLETED') { status = 'completed'; }
  else if (d.status === 'HIATUS') { status = 'hiatus'; }
  return {
    key: '/manga/' + d.id,
    title: d.title,
    coverUrl: d.coverImage || '',
    author: d.author || '',
    artist: '',
    description: d.description || '',
    genre: '',
    status: status,
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/api/manga?page=' + page);
    var data = JSON.parse(text);
    var out = [];
    for (var i = 0; i < (data.data || []).length; i++) {
      out.push(mangaOut(data.data[i]));
    }
    return { mangas: out, hasNextPage: (data.page || 1) * (data.limit || 20) < (data.total || 0) };
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/api/manga?page=' + page + '&query=' + encodeURIComponent(query));
    var data = JSON.parse(text);
    var out = [];
    for (var i = 0; i < (data.data || []).length; i++) {
      out.push(mangaOut(data.data[i]));
    }
    return { mangas: out, hasNextPage: (data.page || 1) * (data.limit || 20) < (data.total || 0) };
  },

  getMangaDetail: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var text = await $.http.get(BASE + '/api/manga/' + id);
    return mangaOut(JSON.parse(text));
  },

  getChapterList: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var text = await $.http.get(BASE + '/api/manga/' + id);
    var manga = JSON.parse(text);
    var chapters = (manga.chapters || []).slice().sort(function (a, b) { return (b.number || 0) - (a.number || 0); });
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var ts = c.publishedAt ? Date.parse(c.publishedAt) : 0;
      out.push({
        key: mangaKey + '/chapters/' + c.id,
        name: 'الفصل ' + c.number + (c.title ? ' - ' + c.title : ''),
        chapterNumber: c.number,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0,
      });
    }
    // sorted newest-first above; host convention is oldest-first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    // /manga/<mangaId>/chapters/<chapterId>
    var parts = String(chapterKey).split('/').filter(Boolean);
    var mangaId = parts[1] || '';
    var chapterId = parts[3] || '';
    var text = await $.http.get(BASE + '/api/manga/' + mangaId);
    var chapters = (JSON.parse(text) || {}).chapters || [];
    var pages = [];
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].id === chapterId) {
        var imgs = chapters[i].images || [];
        for (var p = 0; p < imgs.length; p++) {
          pages.push({ index: p, url: imgs[p] });
        }
        break;
      }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
