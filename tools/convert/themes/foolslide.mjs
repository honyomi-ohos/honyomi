// FoolSlide theme engine (universal /directory/, /search/, /read/ reader)
export const runtime = 'wp';

const DEFAULTS = {
  urlModifier: '',
  infoSelector: 'div.info',
  chapterListSelector: 'div.group div.element, div.list div.element',
  popularNextSelectors: ['div.next', 'div.next a', 'a:has(span.next)'],
  searchNextSelectors: ['a:has(span.next)', 'div.next a'],
  popularPath: 'directory',
};

function extractStr(kt, name) {
  const re = new RegExp(`(?:override\\s+)?(?:open\\s+)?(?:val|fun)\\s+${name}(?:\\(\\))?\\s*(?::\\s*\\S+\\s*)?=\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = kt.match(re);
  return m ? m[1] : undefined;
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  const mod = extractStr(kt, 'urlModifier');
  if (mod !== undefined) { config.urlModifier = mod; }

  const chSel = extractStr(kt, 'chapterListSelector');
  if (chSel !== undefined) { config.chapterListSelector = chSel; }

  const pn = extractStr(kt, 'popularMangaNextPageSelector');
  if (pn !== undefined) { config.popularNextSelectors = [pn].concat(config.popularNextSelectors); }

  const info = extractStr(kt, 'mangaDetailsInfoSelector');
  if (info !== undefined) { config.infoSelector = info; }

  // JuinJutsuTeamReader serves popular from /latest/
  if (/getPopularManga[\s\S]{0,200}\$baseUrl\/latest\/\$page/.test(kt)) {
    config.popularPath = 'latest';
    warnings.push('popular list served from /latest/ (custom source)');
  }

  if (/WebView|CloudflareHelper/.test(kt)) {
    warnings.push('uses webview features; approximated');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: foolslide)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_sel/R_selFirst/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};
var MOD = CFG.urlModifier || '';

// ---------------- foolslide engine ----------------
function hasNext(doc, selectors) {
  for (var i = 0; i < selectors.length; i++) {
    if (R_selFirst(doc, selectors[i])) { return true; }
  }
  return false;
}

function parseItems(doc) {
  var out = [];
  var els = R_sel(doc, 'div.group');
  for (var i = 0; i < els.length; i++) {
    var link = R_selFirst(els[i], 'a[title]');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var cover = '';
    var img = R_selFirst(els[i], 'img');
    if (img) {
      var src = img.absUrl('src');
      cover = src.replace('/thumb_', '/');
    }
    out.push({ key: R_path(href), title: link.text(), coverUrl: cover });
  }
  return out;
}

async function adultFetch(url) {
  // FoolSlide adult-gate: the upstream client rewrites these requests to POST adult=true
  try {
    return await $.http.post(url, 'adult=true', { 'Content-Type': 'application/x-www-form-urlencoded' });
  } catch (e) {
    return await $.http.get(url);
  }
}

function parseInfoBlock(doc) {
  var info = R_selFirst(doc, CFG.infoSelector);
  var author = '', artist = '', desc = '';
  if (!info) { return { author: author, artist: artist, desc: desc }; }
  var html = info.html() || '';
  var parts = html.split(/<b[^>]*>/i);
  for (var i = 1; i < parts.length; i++) {
    var seg = parts[i];
    var closeIdx = seg.indexOf('</b>');
    if (closeIdx < 0) { continue; }
    var label = seg.slice(0, closeIdx).replace(/<[^>]*>/g, '').trim().toLowerCase();
    var value = seg.slice(closeIdx + 4).replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').trim();
    value = value.replace(/^:\\s*/, '').replace(/^:/, '').trim();
    if (!value) { continue; }
    if (label.indexOf('author') >= 0 || label.indexOf('autore') >= 0) { author = value; }
    else if (label.indexOf('artist') >= 0) { artist = value; }
    else if (label.indexOf('synopsis') >= 0 || label.indexOf('description') >= 0 || label.indexOf('trama') >= 0) { desc = value; }
  }
  return { author: author, artist: artist, desc: desc };
}

function parseChapters(doc) {
  var out = [];
  var els = R_sel(doc, CFG.chapterListSelector);
  for (var i = 0; i < els.length; i++) {
    var link = R_selFirst(els[i], 'a[title]');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var dateText = '';
    var dEl = R_selFirst(els[i], 'div.meta_r');
    if (dEl) { dateText = dEl.text(); }
    out.push({
      key: R_path(href),
      name: link.text(),
      chapterNumber: -1,
      dateUpload: R_date(dateText),
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

function parsePagesFromText(text) {
  var m = text.match(/var pages = (\\[[\\s\\S]*?\\]);/);
  if (!m) { return []; }
  var pages = [];
  try {
    var arr = JSON.parse(m[1]);
    for (var i = 0; i < arr.length; i++) {
      var u = arr[i] && arr[i].url ? String(arr[i].url) : '';
      if (u) { pages.push({ index: pages.length, url: R_abs(u) }); }
    }
  } catch (e) { /* keep empty */ }
  return pages;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + MOD + '/' + CFG.popularPath + '/' + page + '/');
    var doc = $.html.parse(text);
    var out = parseItems(doc);
    return { mangas: out, hasNextPage: hasNext(doc, CFG.popularNextSelectors) };
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.post(BASE + MOD + '/search/', 'search=' + encodeURIComponent(query || ''),
      { 'Content-Type': 'application/x-www-form-urlencoded' });
    var doc = $.html.parse(text);
    var out = parseItems(doc);
    return { mangas: out, hasNextPage: hasNext(doc, CFG.searchNextSelectors) };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await adultFetch(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var info = parseInfoBlock(doc);
    var cover = '';
    var thumb = R_selFirst(doc, 'div.thumbnail img, table.thumb img');
    if (thumb) { cover = thumb.absUrl('src'); }
    if (!cover) {
      // fall back to the first page of the last chapter
      var chapters = parseChapters(doc);
      if (chapters.length > 0) {
        try {
          var cText = await adultFetch(R_abs(chapters[chapters.length - 1].key));
          var cPages = parsePagesFromText(cText);
          if (cPages.length > 0) { cover = cPages[0].url; }
        } catch (e) { /* ignore */ }
      }
    }
    var title = '';
    var titleEl = R_selFirst(doc, 'h1.title, h1');
    if (titleEl) { title = titleEl.text(); }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: info.author,
      description: info.desc,
      genre: '',
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await adultFetch(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var chapters = parseChapters(doc);
    // page lists newest first; normalize to oldest-first
    chapters.reverse();
    for (var i = 0; i < chapters.length; i++) { chapters[i].sortOrder = i; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var text = await adultFetch(R_abs(chapterKey));
    var pages = parsePagesFromText(text);
    if (pages.length === 0) {
      var doc = $.html.parse(text);
      var els = R_sel(doc, 'img');
      for (var i = 0; i < els.length; i++) {
        var src = els[i].absUrl('src');
        if (src && /\\/\\d+\\.(jpg|jpeg|png|gif|webp)/i.test(src)) {
          pages.push({ index: pages.length, url: src });
        }
      }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
