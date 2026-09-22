// Shared driver for standalone (no-theme) sources.
// A per-source engine file imports makeScraper(config) and re-exports its extract/generate.
// config schema (all selectors CSS; relative to the item element unless noted):
// {
//   popular: { url: '{base}/Genre/All/{page}', firstUrl?: '{base}', item: 'div.ranking_item',
//              link: 'a', img?: 'img', hasNext: 'a.next_p' | <number min items> },
//   search:  { url: '{base}/Find/{query}', item, link, img?, hasNext? },
//   details: { title, cover?, author?, artist?, genre?, description?, status?,
//              statusMap?: { 'on-going': 'ongoing' } },
//   chapters:{ item, name, url, date?, dateFormat?: 'yyyy/MM/dd', reverse?: true },
//   pages:   { img: 'img#gohere[src]', attr?: 'src' },
//   headers?: { Referer: '{base}/' },   // {base} expanded
// }
// URL placeholders: {base} {page} {query} (query gets encodeURIComponent).
// Simple cases only — sources needing custom logic write bespoke engines instead.
export const runtime = 'wp';

export function makeScraper(config, opts = {}) {
  return {
    runtime,
    extract(ctx) {
      const warnings = [...(opts.warnings ?? [])];
      const required = ['popular', 'search', 'details', 'chapters', 'pages'];
      for (const k of required) {
        if (!config[k]) return { ok: false, reason: `missing config: ${k}` };
      }
      if (ctx.gradle.sources.length > 1 && !opts.multiOk) {
        return { ok: false, reason: 'multi-source ext needs bespoke engine' };
      }
      return { ok: true, config, warnings };
    },
    generate(manifest, cfg) {
      const json = JSON.stringify(cfg, null, 2);
      const name = manifest.name;
      return `// ${name} — auto-generated from keiyoushi/extensions-source (standalone scraper)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${json};

// ---------------- generic scraper driver ----------------
function url(tpl, page, query) {
  return tpl.replace('{base}', BASE)
    .replace('{page}', String(page))
    .replace('{query}', query === undefined ? '' : encodeURIComponent(query));
}
function headers(extra) {
  if (!extra) { return undefined; }
  var out = {};
  for (var k in extra) { out[k] = String(extra[k]).replace('{base}', BASE); }
  return out;
}
function parseList(sec, page, query) {
  var u = (page === 1 && sec.firstUrl) ? url(sec.firstUrl, page, query) : url(sec.url, page, query);
  return $.http.get(u, headers(CFG.headers)).then(function (text) {
    var doc = $.html.parse(text);
    var out = [];
    var items = R_sel(doc, sec.item);
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      var link = R_selFirst(el, sec.link);
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var img = sec.img ? R_selFirst(el, sec.img) : R_selFirst(el, 'img');
      out.push({ key: R_path(href), title: link.text(), coverUrl: R_img(img) });
    }
    var hasNext = false;
    if (typeof sec.hasNext === 'number') {
      hasNext = out.length >= sec.hasNext;
    } else if (sec.hasNext) {
      hasNext = !!R_selFirst(doc, sec.hasNext);
    }
    return { mangas: out, hasNextPage: hasNext };
  });
}
function texts(root, selector) {
  if (!selector) { return ''; }
  var els = R_sel(root, selector);
  var parts = [];
  for (var i = 0; i < els.length; i++) {
    var t = els[i].text();
    if (t) { parts.push(t); }
  }
  return parts.join(', ');
}
function firstText(root, selector) {
  if (!selector) { return ''; }
  var el = R_selFirst(root, selector);
  return el ? el.text() : '';
}
function fmtDate(s, fmt) {
  var v = String(s || '').trim();
  if (!v) { return 0; }
  if (fmt === 'yyyy/MM/dd' && /^\\d{4}\\/\\d{1,2}\\/\\d{1,2}$/.test(v)) {
    return Date.parse(v.replace(/\\//g, '-'));
  }
  return R_date(v);
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(CFG.popular, page, undefined);
  },

  getSearchManga: async function (page, query) {
    return parseList(CFG.search, page, query);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), headers(CFG.headers));
    var doc = $.html.parse(text);
    var d = CFG.details;
    var cover = d.cover ? R_img(R_selFirst(doc, d.cover)) : '';
    var statusRaw = firstText(doc, d.status);
    var status = '';
    if (statusRaw) {
      var mapped = d.statusMap && d.statusMap[statusRaw.toLowerCase()];
      status = mapped || R_status(statusRaw);
    }
    return {
      key: mangaKey,
      title: firstText(doc, d.title),
      coverUrl: cover,
      author: firstText(doc, d.author),
      description: firstText(doc, d.description),
      genre: texts(doc, d.genre),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), headers(CFG.headers));
    var doc = $.html.parse(text);
    var c = CFG.chapters;
    var items = R_sel(doc, c.item);
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      var link = R_selFirst(el, c.url);
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      out.push({
        key: R_path(href),
        name: firstText(el, c.name) || link.text(),
        chapterNumber: -1,
        dateUpload: fmtDate(firstText(el, c.date), c.dateFormat),
        pages: 0,
        sortOrder: 0
      });
    }
    if (c.reverse) { out.reverse(); }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), headers(CFG.headers));
    var doc = $.html.parse(text);
    var p = CFG.pages;
    var imgs = R_sel(doc, p.img);
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u;
      if (p.attr) {
        u = R_abs(imgs[i].attr(p.attr));
      } else {
        u = R_img(imgs[i]);
      }
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return headers(CFG.headers) || { Referer: BASE + '/' };
  }
};
`;
    },
  };
}
