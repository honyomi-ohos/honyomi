// pt/plumacomics — JSON API + Next.js HTML details (plumacomics)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['chapters parsed from embedded next.js payload via bracket scanner'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API+HTML)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};

function extractJsonArray(text, key) {
  var idx = text.indexOf('"' + key + '"');
  while (idx >= 0) {
    var colon = text.indexOf(':', idx + key.length + 2);
    if (colon < 0) { return null; }
    var start = -1;
    for (var p = colon + 1; p < text.length; p++) {
      var ch = text.charAt(p);
      if (ch === '[') { start = p; break; }
      if (ch !== ' ' && ch !== '\\n' && ch !== '\\r' && ch !== '\\t') { break; }
    }
    if (start >= 0) {
      var depth = 0;
      var inStr = false;
      var esc = false;
      for (var i = start; i < text.length; i++) {
        var c = text.charAt(i);
        if (inStr) {
          if (esc) { esc = false; }
          else if (c === '\\\\') { esc = true; }
          else if (c === '"') { inStr = false; }
          continue;
        }
        if (c === '"') { inStr = true; }
        else if (c === '[') { depth++; }
        else if (c === ']') {
          depth--;
          if (depth === 0) {
            try { return $.json.parse(text.substring(start, i + 1)); } catch (e) { return null; }
          }
        }
      }
    }
    idx = text.indexOf('"' + key + '"', idx + key.length + 2);
  }
  return null;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/api/obras?page=' + page + '&sort=popular');
    var j = $.json.parse(text);
    var out = [];
    var list = j.series || [];
    for (var i = 0; i < list.length; i++) {
      var it = list[i];
      var cover = '';
      if (it.coverPath) { cover = BASE + '/api/cover/' + it.coverPath.replace(/^\\/+|\\/+$/g, ''); }
      out.push({
        key: '/title/' + it.slug + '?id=' + it.id,
        title: it.title || '',
        coverUrl: cover
      });
    }
    return { mangas: out, hasNextPage: (j.page || 1) < (j.totalPages || 1) };
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/api/obras?page=' + page;
    if (query) { u += '&q=' + encodeURIComponent(query); }
    var text = await $.http.get(u);
    var j = $.json.parse(text);
    var out = [];
    var list = j.series || [];
    for (var i = 0; i < list.length; i++) {
      var it = list[i];
      var cover = '';
      if (it.coverPath) { cover = BASE + '/api/cover/' + it.coverPath.replace(/^\\/+|\\/+$/g, ''); }
      out.push({
        key: '/title/' + it.slug + '?id=' + it.id,
        title: it.title || '',
        coverUrl: cover
      });
    }
    return { mangas: out, hasNextPage: (j.page || 1) < (j.totalPages || 1) };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = mangaKey.split('?')[0].split('/').pop();
    var text = await $.http.get(BASE + '/title/' + encodeURIComponent(slug));
    var doc = $.html.parse(text);
    var title = '';
    var metaEls = R_sel(doc, 'meta[property*=title]');
    if (metaEls.length > 0) {
      var mt = metaEls[0].attr('content') || '';
      title = mt.split('|').slice(0, -1).join('|').trim() || mt;
    }
    var genres = [];
    var gels = R_sel(doc, "a[href*='?genre=']");
    for (var g = 0; g < gels.length; g++) { genres.push(gels[g].text()); }
    return {
      key: mangaKey,
      title: title || (R_selFirst(doc, 'h1') ? R_selFirst(doc, 'h1').text() : ''),
      coverUrl: R_img(R_selFirst(doc, 'img.object-cover')),
      author: '',
      description: R_ownText(R_selFirst(doc, 'div p.text-neutral-300.text-sm')) || '',
      genre: genres.join(', '),
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = mangaKey.split('?')[0].split('/').pop();
    var text = await $.http.get(BASE + '/title/' + encodeURIComponent(slug));
    var chapters = extractJsonArray(text, 'chapters') || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      if (!c || c.id === undefined) { continue; }
      var name = c.title || ('Capítulo ' + parseInt(c.number, 10));
      if (c.isVipOnly) { name = '🔒 ' + name; }
      out.push({
        key: '/viewer/' + c.id,
        name: name,
        chapterNumber: typeof c.number === 'number' ? c.number : parseFloat(c.number) || -1,
        dateUpload: c.publishedAt ? Date.parse(c.publishedAt) || 0 : 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = chapterKey.split('/').pop();
    var text = await $.http.get(BASE + '/api/viewer/bootstrap?c=' + encodeURIComponent(id));
    var j = $.json.parse(text);
    var pages = (j.pages || []).slice().sort(function (a, b) { return (a.i || 0) - (b.i || 0); });
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].u) { out.push({ index: out.length, url: R_abs(pages[i].u) }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
