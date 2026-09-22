// VerComics theme engine (es: chochox, vcpvmp) — WP one-shot comics
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    urlSuffix: '',
    genreSuffix: '',
    useSuffixOnSearch: true
  };
  const srcName = ((ctx.gradle && ctx.gradle.sources && ctx.gradle.sources[0]) || {}).name || '';
  function pickVal(prop) {
    const simple = kt.match(new RegExp(`override val ${prop}\\s*=\\s*"([^"]*)"`));
    if (simple) return simple[1];
    const whenMatch = kt.match(new RegExp(`override val ${prop}\\s*=\\s*when \\(name\\) \\{([\\s\\S]*?)\\n\\s*\\}`));
    if (whenMatch) {
      const re = /"([^"]+)"\s*->\s*"([^"]*)"/g;
      let m;
      for (let entry = 0; (m = re.exec(whenMatch[1])) !== null;) {
        entry++;
        if (m[1] === srcName) return m[2];
      }
    }
    return undefined;
  }
  const us = pickVal('urlSuffix');
  if (us !== undefined) config.urlSuffix = us;
  const gs = pickVal('genreSuffix');
  if (gs !== undefined) config.genreSuffix = gs;
  if (/override val useSuffixOnSearch\s*=\s*false/.test(kt)) config.useSuffixOnSearch = false;
  warnings.push('genre browse filters not supported; only text search');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: vercomics)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function imgAttr(el) {
  if (el.attr('data-src')) { return el.absUrl('data-src') || el.attr('data-src'); }
  if (el.attr('data-lazy-src')) { return el.absUrl('data-lazy-src') || el.attr('data-lazy-src'); }
  if (el.attr('srcset')) {
    var parts = String(el.attr('srcset')).split(' ').filter(function (p) { return /^https?:\\/\\//.test(p); });
    if (parts.length > 0) { return parts[parts.length - 1]; }
  }
  if (el.attr('data-cfsrc')) { return el.absUrl('data-cfsrc') || el.attr('data-cfsrc'); }
  return el.absUrl('src') || el.attr('src') || '';
}

function parseEntries(doc) {
  var els = R_sel(doc, '.entry');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var a = R_selFirst(els[i], 'a.popimg');
    if (!a) { continue; }
    var href = a.absUrl('href') || a.attr('href');
    if (!href) { continue; }
    var img = R_selFirst(a, 'img');
    out.push({
      key: R_path(href),
      title: img ? (img.attr('alt') || '') : '',
      coverUrl: img ? imgAttr(img) : ''
    });
  }
  return out;
}

function hasNextPage(doc) {
  var cur = R_selFirst(doc, 'div.wp-pagenavi .current');
  if (!cur) { return false; }
  var n = parseInt(cur.text(), 10);
  if (isNaN(n)) { return false; }
  var links = R_sel(doc, 'div.wp-pagenavi a');
  for (var i = 0; i < links.length; i++) {
    var t = parseInt(links[i].text(), 10);
    if (!isNaN(t) && t > n) { return true; }
  }
  return false;
}

module.exports = {
  getPopularManga: async function (page) {
    var path = CFG.urlSuffix ? '/' + CFG.urlSuffix + '/page/' + page : '/page/' + page;
    var text = await $.http.get(BASE + path);
    var doc = $.html.parse(text);
    return { mangas: parseEntries(doc), hasNextPage: hasNextPage(doc) };
  },

  getSearchManga: async function (page, query) {
    var url;
    if (query) {
      var path = (CFG.useSuffixOnSearch && CFG.urlSuffix) ? '/' + CFG.urlSuffix : '';
      url = BASE + path + '/page/' + page + '?s=' + encodeURIComponent(query);
    } else {
      url = BASE + (CFG.urlSuffix ? '/' + CFG.urlSuffix : '') + '/page/' + page;
    }
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    return { mangas: parseEntries(doc), hasNextPage: hasNextPage(doc) };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var genres = [];
    var links = R_sel(doc, 'a');
    for (var i = 0; i < links.length; i++) {
      if (links[i].attr('rel') === 'tag') {
        var t = links[i].text();
        if (t) { genres.push(t.charAt(0).toUpperCase() + t.slice(1)); }
      }
    }
    var h1 = R_selFirst(doc, 'h1');
    return {
      key: mangaKey,
      title: h1 ? R_ownText(h1) : '',
      status: R_selFirst(doc, 'div.tax_post') ? 'completed' : '',
      genre: genres.join(', '),
      description: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var name = 'Chapter';
    try {
      var text = await $.http.get(R_abs(mangaKey));
      var doc = $.html.parse(text);
      var h1 = R_selFirst(doc, 'h1');
      if (h1) { name = R_ownText(h1) || name; }
    } catch (e) {}
    return [{
      key: mangaKey,
      name: name,
      chapterNumber: 1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var urls = [];
    var seen = {};
    var groups = ['div.wp-content img', 'div.post-imgs img'];
    for (var g = 0; g < groups.length; g++) {
      var els = R_sel(doc, groups[g]);
      for (var i = 0; i < els.length; i++) {
        var u = imgAttr(els[i]);
        if (u && !seen[u]) {
          seen[u] = true;
          urls.push(u);
        }
      }
    }
    var pages = [];
    for (var k = 0; k < urls.length; k++) { pages.push({ index: k, url: urls[k] }); }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
