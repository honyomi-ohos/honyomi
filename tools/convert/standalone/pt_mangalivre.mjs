// pt/mangalivre — JSON API (mangalivre.net/api); reader verification WebView fallback not portable
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['reader chapter verification (WebView challenge) not portable — such chapters will error; alt-title pref not ported'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = BASE + '/api';
var HDRS = { Accept: '*/*', 'Accept-Language': 'pt-BR,en-US;q=0.9,en;q=0.8' };

function parseList(text) {
  var j = $.json.parse(text);
  var list = j.mangas || [];
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var it = list[i];
    out.push({
      key: '/manga/' + it.id,
      title: it.title || '',
      coverUrl: it.coverUrl || ''
    });
  }
  return { mangas: out, hasNextPage: !!(j.pagination && j.pagination.hasNextPage) };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(API + '/mangas/search?page=' + page + '&limit=24&sortBy=popular&sortOrder=desc', HDRS);
    return parseList(text);
  },

  getSearchManga: async function (page, query) {
    var u = API + '/mangas/search?page=' + page + '&limit=24&sortBy=updated&sortOrder=desc';
    if (query) { u += '&q=' + encodeURIComponent(query); }
    var text = await $.http.get(u, HDRS);
    return parseList(text);
  },

  getMangaDetail: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var text = await $.http.get(API + '/manga-by-slug/' + encodeURIComponent(slug), HDRS);
    var d = $.json.parse(text);
    var desc = d.description || '';
    if (d.alternativeTitle) { desc += '\\n\\n\\n Nome alternativo: ' + d.alternativeTitle; }
    var status = '';
    var s = String(d.status || '').toLowerCase();
    if (s === 'ongoing') { status = 'ongoing'; }
    else if (s === 'completed') { status = 'completed'; }
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: d.coverUrl || '',
      author: (d.authors || []).join(', '),
      description: desc,
      genre: (d.genres || []).join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = mangaKey.split('/').pop();
    var text = await $.http.get(API + '/manga-by-slug/' + encodeURIComponent(slug), HDRS);
    var d = $.json.parse(text);
    var chapters = d.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      out.push({
        key: '/' + slug + '/' + c.number + '?mangaId=' + encodeURIComponent(d.id) + '&chapterId=' + encodeURIComponent(c.id),
        name: 'Capítulo ' + c.number,
        chapterNumber: parseFloat(c.number) || -1,
        dateUpload: c.timestamp || 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var m = chapterKey.match(/[?&]mangaId=([^&]*)&chapterId=([^&]*)/);
    if (!m) { throw new Error('chapter reference missing'); }
    var mangaId = decodeURIComponent(m[1]);
    var chapterId = decodeURIComponent(m[2]);
    var chapterNumber = chapterKey.split('?')[0].split('/').filter(Boolean).pop() || '';
    var body = $.json.stringify({ mangaId: mangaId, chapterId: chapterId });
    var text;
    try {
      text = await $.http.post(API + '/reader/chapter/access', body, { 'Content-Type': 'application/json', Accept: '*/*' });
    } catch (e) {
      throw new Error('Reader verification required (WebView challenge not supported)');
    }
    var j = $.json.parse(text);
    var pages = (j.chapter && j.chapter.pages) || [];
    var seen = {};
    var urls = [];
    for (var i = 0; i < pages.length; i++) {
      var raw = pages[i];
      if (!raw) { continue; }
      var u = raw;
      if (raw.indexOf('url=') >= 0) {
        var qm = raw.match(/[?&]url=([^&]+)/);
        if (qm) { u = decodeURIComponent(qm[1]); }
      }
      if (u.indexOf('https://cdn.toonlivre.net/') !== 0) { continue; }
      var seg = u.split('?')[0].split('/').filter(Boolean);
      if (seg.length < 4 || seg[0] !== 'obras' || seg[1] !== mangaId || seg[2] !== chapterNumber) { continue; }
      if (!seen[u]) { seen[u] = 1; urls.push(u); }
    }
    urls.sort(function (a, b) {
      function num(x) {
        var mm = x.match(/_(\\d+)\\.[^.]+$/);
        return mm ? parseInt(mm[1], 10) : 999999999;
      }
      return num(a) - num(b) || (a < b ? -1 : 1);
    });
    var out = [];
    for (var k = 0; k < urls.length; k++) { out.push({ index: k, url: urls[k] }); }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
