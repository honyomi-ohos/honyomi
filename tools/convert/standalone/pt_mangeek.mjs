// pt/mangeek — signed-URL JSON API (geekstations.com.br/api/v2/pt)
// URL shape: /api/v2/pt/{route}/{nonce}[/{input}]/{md5("M<"+sig+"#MANG33K>D")}
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['tag filters not ported; mirror chapter route used as fallback'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone signed API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'http://geekstations.com.br/api/v2/pt';

function signedUrl(route, input) {
  var nonce = Date.now().toString(16).toUpperCase();
  var sig = input !== undefined && input !== null ? String(input) : nonce;
  var key = $.crypto.md5('M<' + sig + '#MANG33K>D');
  var u = API + '/' + route + '/' + nonce;
  if (input !== undefined && input !== null) { u += '/' + encodeURIComponent(input); }
  return u + '/' + key;
}

function normalizeImage(u) {
  if (!u) { return ''; }
  return String(u)
    .replace(/^http:\\/\\/51\\.79\\.78\\.152/, 'https://static.geekstations.com.br')
    .replace(/^https:\\/\\/51\\.79\\.78\\.152/, 'https://static.geekstations.com.br');
}

function toManga(it) {
  return {
    key: '/manga/' + it.id,
    title: it.title || '',
    coverUrl: normalizeImage(it.thumbnail)
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(signedUrl('home'));
    var j = $.json.parse(text);
    var seen = {};
    var out = [];
    function add(list) {
      for (var i = 0; i < (list || []).length; i++) {
        var m = list[i];
        if (m && m.id && !seen[m.id]) { seen[m.id] = 1; out.push(toManga(m)); }
      }
    }
    add(j.tops); add(j.trending);
    var news = (j.news || []).concat(j.reading || []);
    for (var n = 0; n < news.length; n++) { add([news[n].manga]); }
    var cats = j.categories || [];
    for (var c = 0; c < cats.length; c++) { add(cats[c].list); }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var q = String(query || '').trim().toLowerCase();
    if (!q) { return module.exports.getPopularManga(page); }
    var text = await $.http.post(signedUrl('search', q), $.json.stringify({ tags: [] }));
    var list = $.json.parse(text) || [];
    var seen = {};
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var m = list[i];
      if (m && m.id && !seen[m.id]) { seen[m.id] = 1; out.push(toManga(m)); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var text = await $.http.get(signedUrl('manga', id));
    var d = $.json.parse(text);
    var status = d.finished === true ? 'completed' : (d.finished === false ? 'ongoing' : '');
    var desc = '';
    if (d.alternative_title && d.alternative_title.trim() && d.alternative_title.toLowerCase() !== String(d.title || '').toLowerCase()) {
      desc = 'Título alternativo: ' + d.alternative_title + '\\n\\n';
    }
    desc += d.description || '';
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: normalizeImage(d.thumbnail),
      author: '',
      description: desc,
      genre: (d.tags || []).join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var text = await $.http.get(signedUrl('manga', id));
    var d = $.json.parse(text);
    var chapters = (d.chapters || []).slice().reverse();
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var numMatch = String(c.title || '').match(/\\d+(?:[.,]\\d+)?/);
      out.push({
        key: '/chapter/' + c.id,
        name: c.title || '',
        chapterNumber: numMatch ? parseFloat(numMatch[0].replace(',', '.')) : -1,
        dateUpload: 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = chapterKey.split('/').pop();
    var out = [];
    try {
      var text = await $.http.get(signedUrl('chapter', id));
      var j = $.json.parse(text);
      var pages = j.pages || [];
      for (var i = 0; i < pages.length; i++) {
        var u = normalizeImage(pages[i]);
        if (u) { out.push({ index: out.length, url: u }); }
      }
    } catch (e) { /* fall through to mirror */ }
    if (out.length === 0) {
      var mtext = await $.http.get(signedUrl('mirror', id));
      var mj = $.json.parse(mtext);
      var mpages = mj.pages || [];
      for (var k = 0; k < mpages.length; k++) {
        var mu = normalizeImage(mpages[k]);
        if (mu) { out.push({ index: out.length, url: mu }); }
      }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
