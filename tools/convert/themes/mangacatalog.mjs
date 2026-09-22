// MangaCatalog theme engine (static franchise catalog sites)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

function stripLineComments(kt) {
  return kt.split('\n').filter(l => !/^\s*\/\//.test(l)).join('\n');
}

export function extract(ctx) {
  const kt = stripLineComments(ctx.ktText);
  const warnings = [];
  const config = {
    sources: [],
    detailsMode: 'default',
    titleSelector: 'div.container > h1',
    titleStripPrefix: '',
    descSelector: '',
    thumbSelector: 'div.flex > img',
    chaptersMode: 'default',
    chapterListSelector: 'div.w-full > div.bg-bg-secondary > div.grid',
    chapterNameSelector: '.col-span-4 > a',
    chapterName2Selector: '.text-xs:not(a)',
    chapterUrlSelector: '.col-span-4 > a',
    chapterDateSelector: '',
    pagesMode: 'default',
    pagesSelector: 'img[data-src]',
    pagesAttr: 'data-src',
  };

  // sourceList pairs
  const listMatch = kt.match(/sourceList\s*=\s*listOf\(/);
  if (listMatch) {
    const start = listMatch.index + listMatch[0].length;
    let depth = 1, i = start;
    for (; i < kt.length && depth > 0; i++) {
      if (kt[i] === '(') depth++;
      else if (kt[i] === ')') depth--;
    }
    const body = kt.slice(start, i);
    const pre = /Pair\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"([^"]*)"\s*\)/g;
    let m;
    const seen = new Set();
    while ((m = pre.exec(body)) !== null) {
      let url = m[2].replace(/\$baseUrl/g, '');
      if (url === '') { url = '/'; }
      if (!url.startsWith('/')) { url = '/' + url; }
      if (seen.has(url)) { continue; }
      seen.add(url);
      config.sources.push({ name: m[1], url });
    }
  }
  if (config.sources.length === 0) {
    config.sources.push({ name: ctx.gradle.sources[0]?.name || ctx.extName, url: '/' });
  }

  // custom mangaDetailsParse (card-style variant)
  if (/mangaDetailsParse\(/.test(kt)) {
    config.detailsMode = 'card';
    const ts = kt.match(/title\s*=\s*document\.select\("([^"]+)"\)\.text\(\)/);
    if (ts) { config.titleSelector = ts[1]; }
    const tsp = kt.match(/title\s*=[\s\S]{0,120}?\.substringAfter\("([^"]*)"\)/);
    if (tsp) { config.titleStripPrefix = tsp[1]; }
    const ds = kt.match(/description\s*=\s*document\.select\("([^"]+)"\)\.text\(\)/);
    if (ds) { config.descSelector = ds[1]; }
    const th = kt.match(/thumbnail_url\s*=\s*document\.select\("([^"]+)"\)\.attr\("abs:src"\)/);
    if (th) { config.thumbSelector = th[1]; }
    warnings.push('custom details parse converted');
  }

  // custom chapter list
  const cls = kt.match(/chapterListSelector\(\)\s*:\s*String\s*=\s*"([^"]+)"/);
  if (cls) { config.chapterListSelector = cls[1]; }
  if (/chapterFromElement\(/.test(kt)) {
    if (/tbody\s*>/.test(config.chapterListSelector)) {
      config.chaptersMode = 'table';
      const ns = kt.match(/name\s*=\s*element\.select\("([^"]+)"\)\.text\(\)/);
      if (ns) { config.chapterNameSelector = ns[1]; config.chapterName2Selector = ''; }
      const us = kt.match(/url\s*=\s*element\.select\("([^"]+)"\)\.attr\("abs:href"\)/);
      if (us) { config.chapterUrlSelector = us[1]; }
      const dsel = kt.match(/date_upload\s*=[\s\S]{0,150}?element\.select\("([^"]+)"\)\.text\(\)/);
      if (dsel) { config.chapterDateSelector = dsel[1]; }
      warnings.push('custom table chapter parse converted');
    } else {
      config.chaptersMode = 'aot';
      warnings.push('custom chapter parse converted (aot variant)');
    }
  }

  // custom page list (anchor the search inside pageListParse body)
  const plIdx = kt.indexOf('pageListParse(');
  if (plIdx >= 0) {
    const plBody = kt.slice(plIdx, plIdx + 600);
    const ps = plBody.match(/document\.select\("([^"]+)"\)/);
    if (ps) {
      config.pagesSelector = ps[1];
      config.pagesMode = 'custom';
      config.pagesAttr = /attr\("abs:src"\)/.test(plBody) ? 'src' : 'data-src';
      warnings.push('custom page parse converted');
    }
  }

  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mangacatalog)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_* helpers)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- mangacatalog engine ----------------
function listSources() {
  var out = [];
  for (var i = 0; i < CFG.sources.length; i++) {
    var s = CFG.sources[i];
    out.push({ key: R_path(s.url), title: s.name, coverUrl: '' });
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    return { mangas: listSources(), hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var all = listSources();
    var out = [];
    var q = (query || '').toLowerCase();
    for (var i = 0; i < all.length; i++) {
      if (!q || all[i].title.toLowerCase().indexOf(q) >= 0) { out.push(all[i]); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var title = '';
    var desc = '';
    var cover = '';
    if (CFG.detailsMode === 'card') {
      var tEl = R_selFirst(doc, CFG.titleSelector);
      title = tEl ? tEl.text() : '';
      if (CFG.titleStripPrefix && title.indexOf(CFG.titleStripPrefix) === 0) {
        title = title.slice(CFG.titleStripPrefix.length).trim();
      }
      if (CFG.descSelector) {
        var dEl = R_selFirst(doc, CFG.descSelector);
        var parts = R_sel(doc, CFG.descSelector);
        var dTexts = [];
        for (var p = 0; p < parts.length; p++) {
          if (parts[p].text()) { dTexts.push(parts[p].text()); }
        }
        desc = dTexts.join('\\n');
        if (!desc && dEl) { desc = dEl.text(); }
      }
      var thEl = R_selFirst(doc, CFG.thumbSelector);
      cover = thEl ? thEl.absUrl('src') : '';
    } else {
      var tEl2 = R_selFirst(doc, CFG.titleSelector);
      title = tEl2 ? tEl2.text() : '';
      var infoEls = R_sel(doc, 'div.bg-bg-secondary > div.px-6 > div.flex-col');
      var info = infoEls.length > 0 ? infoEls[0].text() : '';
      var di = info.indexOf('Description');
      desc = di >= 0 ? info.slice(di + 11).trim() : info;
      var imEl = R_selFirst(doc, CFG.thumbSelector);
      cover = imEl ? imEl.absUrl('src') : '';
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: '',
      description: desc,
      genre: '',
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, CFG.chapterListSelector);
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var link = R_selFirst(el, CFG.chapterUrlSelector) || R_selFirst(el, 'a');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var name = '';
      var dateText = '';
      if (CFG.chaptersMode === 'table') {
        var nEl = R_selFirst(el, CFG.chapterNameSelector);
        name = nEl ? nEl.text() : link.text();
        if (CFG.chapterDateSelector) {
          var dEl = R_selFirst(el, CFG.chapterDateSelector);
          dateText = dEl ? dEl.text() : '';
        }
      } else if (CFG.chaptersMode === 'aot') {
        name = link.text();
        var n2 = R_selFirst(el, 'div.text-xs');
        if (n2 && n2.text()) { name += ' - ' + n2.text(); }
      } else {
        var nEl2 = R_selFirst(el, CFG.chapterNameSelector);
        name = nEl2 ? nEl2.text() : link.text();
        if (CFG.chapterName2Selector) {
          var n2El = R_selFirst(el, CFG.chapterName2Selector);
          if (n2El && n2El.text()) { name += ' - ' + n2El.text(); }
        }
      }
      var num = -1;
      var nm = name.match(/(\\d+(?:[.]\\d+)?)/);
      if (nm) { num = parseFloat(nm[1]); }
      out.push({
        key: R_path(href),
        name: name,
        chapterNumber: num,
        dateUpload: R_date(dateText),
        pages: 0,
        sortOrder: 0
      });
    }
    // catalog sites list newest chapter first -> normalize to oldest-first
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, CFG.pagesSelector);
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var u = els[i].absUrl(CFG.pagesAttr) || els[i].absUrl('data-src') || els[i].absUrl('src');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
