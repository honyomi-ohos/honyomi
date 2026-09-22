// en/xomanga — bespoke JSON scraper (index.json + per-manga details.json / chapters json)
export const runtime = 'wp';

export function extract(ctx) {
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function idFromLink(link) {
  var m = /[?&]id=([^&#]+)/.exec(String(link || ''));
  return m ? decodeURIComponent(m[1]) : '';
}
function chFromLink(link) {
  var m = /[?&]ch=([^&#]+)/.exec(String(link || ''));
  if (m) { return decodeURIComponent(m[1]); }
  var f = /#(.+)$/.exec(String(link || ''));
  return f ? decodeURIComponent(f[1]) : '';
}
function toManga(it) {
  return {
    key: '/manga/' + idFromLink(it.link) + '/details.json',
    title: it.title || '',
    coverUrl: R_abs(it.image || '')
  };
}
function normalizeTitle(t) {
  return String(t || '').toLowerCase().trim().replace(/\\s+/g, ' ');
}

module.exports = {
  getPopularManga: async function () {
    var out = [];
    var excl = [];
    try {
      var works = await $.http.get(BASE + '/our-works', HDRS);
      var block = /myExclusiveWorksTitles\\s*=\\s*\\[([\\s\\S]*?)\\]/.exec(works);
      if (block) {
        var re = /["']([^"'\\n]+)["']/g;
        var m;
        while ((m = re.exec(block[1])) !== null) {
          excl.push(normalizeTitle(m[1]));
        }
      }
    } catch (e) { /* no exclusive list -> empty popular */ }
    if (excl.length === 0) { return { mangas: out, hasNextPage: false }; }
    var idx = $.json.parse(await $.http.get(BASE + '/index.json', HDRS));
    var latest = (idx && idx.latest) || [];
    for (var i = 0; i < latest.length; i++) {
      var it = latest[i];
      if (!it || !it.link || !idFromLink(it.link)) { continue; }
      var norm = normalizeTitle(it.title);
      var found = false;
      for (var j = 0; j < excl.length; j++) {
        if (norm.indexOf(excl[j]) >= 0) { found = true; break; }
      }
      if (found) { out.push(toManga(it)); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var idx = $.json.parse(await $.http.get(BASE + '/index.json', HDRS));
    var latest = (idx && idx.latest) || [];
    var q = normalizeTitle(query);
    var out = [];
    for (var i = 0; i < latest.length; i++) {
      var it = latest[i];
      if (!it || !it.link || !idFromLink(it.link)) { continue; }
      if (q && normalizeTitle(it.title).indexOf(q) < 0) { continue; }
      out.push(toManga(it));
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var d = $.json.parse(await $.http.get(BASE + mangaKey, HDRS));
    var statusMap = { ongoing: 'ongoing', completed: 'completed', hiatus: 'hiatus', cancelled: 'cancelled' };
    var tags = d.tags || [];
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: R_abs(d.cover || ''),
      author: '',
      description: d.description || '',
      genre: tags.join(', '),
      status: statusMap[String(d.status || '').toLowerCase()] || ''
    };
  },

  getChapterList: async function (mangaKey) {
    var d = $.json.parse(await $.http.get(BASE + mangaKey, HDRS));
    var list = d.chapters_list || [];
    var chapters = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var slug = idFromLink(c.link);
      var num = chFromLink(c.link);
      if (!slug || !num) { continue; }
      var n = parseFloat(c.chapter);
      chapters.push({
        key: '/manga/' + slug + '/chapters/' + num + '.json',
        name: 'Chapter ' + (n % 1 === 0 ? String(n) : String(c.chapter)),
        chapterNumber: isNaN(n) ? -1 : n,
        dateUpload: R_date(c.date || ''),
        pages: 0,
        sortOrder: 0
      });
    }
    chapters.sort(function (a, b) { return a.chapterNumber - b.chapterNumber; });
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var data = $.json.parse(await $.http.get(BASE + chapterKey, HDRS));
    var images = (data && data.images) || [];
    var pages = [];
    for (var i = 0; i < images.length; i++) {
      var u = R_abs(images[i]);
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
