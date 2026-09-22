// en/luminaretranslations — wp-json/yarnovel API primary; HTML fallback (site API currently
// returns PHP fatal errors for detail/chapters endpoints)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['site detail/chapter API currently broken (PHP memory exhaustion); HTML fallback added; filters not ported'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke JSON API + HTML fallback)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = BASE + '/wp-json/yarnovel/v1';
var PAGE_SIZE = 24;
var EXCLUDED = ['novel', 'light_novel', 'web_novel'];
var HDRS = { Referer: BASE + '/' };

function listUrl(page, query, sort) {
  var u = API + '/series?page=' + page + '&per_page=' + PAGE_SIZE + '&type=manga&sort=' + sort;
  if (query) { u += '&search=' + encodeURIComponent(query); }
  return u;
}

function parseList(text, page) {
  var r = $.json.parse(text);
  var data = (r && r.data) || [];
  var mangas = [];
  for (var i = 0; i < data.length; i++) {
    var d = data[i];
    if (EXCLUDED.indexOf(d.type) >= 0) { continue; }
    if (!d.slug) { continue; }
    mangas.push({ key: '/' + d.slug, title: d.title || '', coverUrl: d.cover_image || '' });
  }
  var total = (r && r.meta && r.meta.total) || 0;
  return { mangas: mangas, hasNextPage: page * PAGE_SIZE < total };
}

function statusMap(s) {
  switch (s) {
    case 'ongoing': return 'ongoing';
    case 'completed': return 'completed';
    case 'hiatus': return 'hiatus';
    case 'dropped': return 'cancelled';
    default: return '';
  }
}

function tryJson(text) {
  try { return $.json.parse(text); } catch (e) { return null; }
}

function metaContent(html, prop) {
  var m = new RegExp('<meta[^>]+property="' + prop + '"[^>]+content="([^"]*)"').exec(html) ||
    new RegExp('<meta[^>]+content="([^"]*)"[^>]+property="' + prop + '"').exec(html);
  if (!m) { return ''; }
  return m[1].replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/&amp;/g, '&');
}

function extractChaptersJson(html) {
  var m = /chapters\\s*:\\s*\\[/.exec(html);
  if (!m) { return null; }
  var start = m.index + m[0].length - 1;
  var depth = 0, inStr = false, esc = false;
  for (var i = start; i < html.length; i++) {
    var c = html[i];
    if (esc) { esc = false; continue; }
    if (c === '\\\\' && inStr) { esc = true; continue; }
    if (c === '"') { inStr = !inStr; continue; }
    if (inStr) { continue; }
    if (c === '[' || c === '{') { depth++; }
    if (c === ']' || c === '}') {
      depth--;
      if (depth === 0) {
        var raw = html.substring(start, i + 1).replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/&amp;/g, '&');
        return tryJson(raw);
      }
    }
  }
  return null;
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(listUrl(page, '', 'popular'), HDRS), page);
  },

  getSearchManga: async function (page, query) {
    return parseList(await $.http.get(listUrl(page, query, 'latest'), HDRS), page);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(API + '/series' + mangaKey, HDRS);
    var r = tryJson(text);
    if (r && r.data) {
      var d = r.data;
      return {
        key: mangaKey,
        title: d.title || '',
        coverUrl: d.cover_image || '',
        author: d.author || '',
        artist: d.artist || '',
        description: d.description || '',
        genre: (d.genres || []).join(', '),
        status: statusMap(d.status)
      };
    }
    // HTML fallback (API broken server-side)
    var html = await $.http.get(BASE + '/series' + mangaKey, HDRS);
    var title = metaContent(html, 'og:title').replace(/\\s*-\\s*Luminare Translations.*$/, '');
    var doc = $.html.parse(html);
    var genres = [];
    var gels = R_sel(doc, 'a[href*="/series/?genre="]');
    for (var i = 0; i < gels.length; i++) { genres.push(gels[i].text()); }
    var author = '';
    var aels = R_sel(doc, 'a[href*="/series/?author="]');
    if (aels.length) { author = aels[0].text(); }
    return {
      key: mangaKey,
      title: title,
      coverUrl: metaContent(html, 'og:image'),
      author: author,
      description: metaContent(html, 'og:description'),
      genre: genres.join(', '),
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(API + '/series' + mangaKey + '/chapters?per_page=999', HDRS);
    var r = tryJson(text);
    var data = (r && r.data) || null;
    if (!data) {
      // HTML fallback: embedded chapters JSON
      var html = await $.http.get(BASE + '/series' + mangaKey, HDRS);
      var arr = extractChaptersJson(html);
      data = arr || [];
    }
    var out = [];
    for (var i = 0; i < data.length; i++) {
      var c = data[i];
      var k = c.slug ? ('/' + mangaKey.replace(/^\\//, '') + '/' + c.slug)
        : (c.url ? R_path(c.url).replace(/^\\/series/, '') : (c.id !== undefined ? mangaKey + '/' + c.id : null));
      if (!k) { continue; }
      out.push({
        key: k,
        name: c.title || ('Chapter ' + c.number),
        chapterNumber: typeof c.number === 'number' ? c.number : -1,
        dateUpload: c.published_at ? Date.parse(c.published_at) || 0 : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // sort ascending by chapter number -> oldest first
    out.sort(function (a, b) { return a.chapterNumber - b.chapterNumber; });
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(API + '/series' + chapterKey, HDRS);
    var r = tryJson(text);
    if (r && r.data && r.data.pages) {
      var pages = r.data.pages;
      var out = [];
      for (var i = 0; i < pages.length; i++) { out.push({ index: i, url: pages[i] }); }
      return out;
    }
    // HTML fallback: reader page images
    var html = await $.http.get(BASE + '/series' + chapterKey, HDRS);
    var doc = $.html.parse(html);
    var imgs = R_sel(doc, 'img');
    var out2 = [];
    for (var k = 0; k < imgs.length; k++) {
      var u = R_img(imgs[k]);
      if (u.indexOf('/wp-content/uploads/') < 0) { continue; }
      out2.push({ index: out2.length, url: u });
    }
    return out2;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
