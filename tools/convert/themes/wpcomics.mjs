// WPComics theme engine (nettruyen family, Vietnamese WP comic sites)
export const runtime = 'wp';

const DEFAULTS = {
  popularPath: 'hot',
  searchPath: 'tim-truyen',
  queryParam: 'keyword',
  popularSelector: 'div.items div.item',
  nextSelectors: ['a.next-page, a[rel=next]'],
  chapterListSelector: 'div.list-chapter li.row:not(.heading)',
  pageSelector: 'div.page-chapter > img, li.blocks-gallery-item img',
  detailStyle: 'default', // 'default' | 'toptruyen'
  chapterApi: 'none',     // 'none' | 'asmx'
  asmxComicId: false,
  pageListAll: false,
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

  for (const [ktName, cfgName] of [
    ['popularPath', 'popularPath'],
    ['searchPath', 'searchPath'],
    ['queryParam', 'queryParam'],
  ]) {
    const v = extractStr(kt, ktName);
    if (v !== undefined) { config[cfgName] = v; }
  }

  const sel = extractStr(kt, 'popularMangaSelector');
  if (sel !== undefined) { config.popularSelector = sel; }

  const nxt = extractStr(kt, 'popularMangaNextPageSelector');
  if (nxt !== undefined) { config.nextSelectors = [nxt]; }

  const chSel = extractStr(kt, 'chapterListSelector');
  if (chSel !== undefined) { config.chapterListSelector = chSel; }

  const pSel = extractStr(kt, 'pageListSelector');
  if (pSel !== undefined) { config.pageSelector = pSel; }

  if (/ComicService\.asmx\/ChapterList/.test(kt)) {
    config.chapterApi = 'asmx';
    config.asmxComicId = /addQueryParameter\("comicId"/.test(kt);
    warnings.push('chapters fetched from ComicService.asmx JSON endpoint');
  }

  if (/chapter\.url\}\/all/.test(kt)) {
    config.pageListAll = true;
  }

  if (ctx.extName === 'toptruyen') {
    config.detailStyle = 'toptruyen';
  }

  if (/rateLimit\(/.test(kt)) {
    warnings.push('source uses rate limiting; requests may be slow');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: wpcomics)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_sel/R_selFirst/R_img/R_status/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- wpcomics engine ----------------
function parseWpDate(s) {
  var v = String(s || '').trim();
  if (!v) { return 0; }
  var low = v.toLowerCase();
  if (/ago|trước|trước đây/.test(low)) { return R_date(v); }
  // yyyy-MM-dd HH:mm:ss (chapter APIs)
  var m = v.match(/^(\\d{4})-(\\d{2})-(\\d{2})[T ](\\d{2}):(\\d{2})(?::(\\d{2}))?/);
  if (m) {
    return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], m[6] ? +m[6] : 0).getTime();
  }
  // dd/MM/yyyy, dd-MM-yyyy, MM/dd/yyyy, dd/MM/yy ... with optional HH:mm prefix
  var tm = v.match(/^(\\d{1,2}):(\\d{2})\\s*-\\s*/);
  var hh = tm ? +tm[1] : 0, mm = tm ? +tm[2] : 0;
  if (tm) { v = v.slice(tm[0].length); }
  var d = v.match(/(\\d{1,2})[-/.](\\d{1,2})[-/.](\\d{2,4})/);
  if (d) {
    var a = +d[1], b = +d[2], y = +d[3];
    if (y < 100) { y += 2000; }
    var day, mon;
    if (a > 12) { day = a; mon = b; }
    else if (b > 12) { day = b; mon = a; }
    else { day = a; mon = b; } // assume dd/MM (Vietnamese default)
    return new Date(y, mon - 1, day, hh, mm, 0).getTime();
  }
  return R_date(v);
}

function imageOrNull(img) {
  if (!img) { return ''; }
  var names = ['data-original', 'data-src', 'src'];
  for (var i = 0; i < names.length; i++) {
    var v = img.attr(names[i]);
    if (v && /^https?:\\/\\//.test(v)) { return v; }
    if (v && v.indexOf('http') < 0) {
      var abs = img.absUrl(names[i]);
      if (abs && /^https?:\\/\\//.test(abs)) { return abs; }
    }
  }
  return '';
}

function hasNextPage(doc) {
  for (var i = 0; i < CFG.nextSelectors.length; i++) {
    if (R_selFirst(doc, CFG.nextSelectors[i])) { return true; }
  }
  return false;
}

function parseList(doc) {
  var out = [];
  var els = R_sel(doc, CFG.popularSelector);
  for (var i = 0; i < els.length; i++) {
    var link = R_selFirst(els[i], 'h3 a');
    if (!link) { link = R_selFirst(els[i], 'a'); }
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    out.push({
      key: R_path(href),
      title: link.text(),
      coverUrl: imageOrNull(R_selFirst(els[i], 'img'))
    });
  }
  return out;
}

function parseDetail(doc, key) {
  if (CFG.detailStyle === 'toptruyen') {
    var t = R_selFirst(doc, 'h1.title-manga');
    var descEls = R_sel(doc, 'p.detail-summary');
    var parts = [];
    for (var di = 0; di < descEls.length; di++) {
      if (descEls[di].text()) { parts.push(descEls[di].text()); }
    }
    return {
      key: key,
      title: t ? t.text() : '',
      coverUrl: imageOrNull(R_selFirst(doc, 'img.image-comic')),
      author: R_selFirst(doc, 'li.author p.col-sm-8') ? R_selFirst(doc, 'li.author p.col-sm-8').text() : '',
      description: parts.join('\\n'),
      genre: R_sel(doc, 'li.category p.detail-info a').map(function (a) { return a.text(); }).join(', '),
      status: R_status(R_selFirst(doc, 'li.status p.detail-info span') ? R_selFirst(doc, 'li.status p.detail-info span').text() : '')
    };
  }
  var info = R_selFirst(doc, 'article#item-detail');
  var author = '', status = '', genre = '', cover = '', desc = '';
  if (info) {
    var aEl = R_selFirst(info, 'li.author p.col-xs-8, li.author p.col-sm-8');
    if (aEl) { author = aEl.text(); }
    var sEl = R_selFirst(info, 'li.status p.col-xs-8, li.status p.detail-info span');
    if (sEl) { status = R_status(sEl.text()); }
    var genres = R_sel(info, 'li.kind p.col-xs-8 a, li.category p.detail-info a');
    var g = [];
    for (var gi = 0; gi < genres.length; gi++) { g.push(genres[gi].text()); }
    genre = g.join(', ');
    cover = imageOrNull(R_selFirst(info, 'div.col-image img'));
    // nettruyen family overrides use .shortened children; base uses detail-content paragraphs
    var shorts = R_sel(info, 'div.detail-content div.shortened');
    var parts = [];
    if (shorts.length > 0) {
      for (var si = 0; si < shorts.length; si++) {
        var ps = R_sel(shorts[si], 'p, div');
        if (ps.length > 0) {
          for (var pi = 0; pi < ps.length; pi++) {
            var pt = ps[pi].text();
            if (pt) { parts.push(pt); }
          }
        } else if (shorts[si].text()) {
          parts.push(shorts[si].text());
        }
      }
      desc = parts.join('\\n\\n');
    } else {
      var pel = R_sel(info, 'div.detail-content p');
      for (var pj = 0; pj < pel.length; pj++) {
        if (pel[pj].text()) { parts.push(pel[pj].text()); }
      }
      desc = parts.join('\\n');
    }
    var other = R_selFirst(info, 'h2.other-name');
    if (other && other.text()) {
      desc += (desc ? '\\n\\n' : '') + 'Tên khác: ' + other.text();
    }
  }
  var title = '';
  var tEl = R_selFirst(doc, 'h1.title-detail, h1.title-manga, h1');
  if (tEl) { title = tEl.text(); }
  if (!title) {
    var og = R_selFirst(doc, 'meta[property="og:title"]');
    if (og) { title = og.attr('content'); }
  }
  return {
    key: key,
    title: title,
    coverUrl: cover,
    author: author,
    description: desc,
    genre: genre,
    status: status
  };
}

function parseChaptersHtml(doc) {
  var out = [];
  var els = R_sel(doc, CFG.chapterListSelector);
  for (var i = 0; i < els.length; i++) {
    var link = R_selFirst(els[i], 'a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var dEl = R_selFirst(els[i], 'div.col-xs-4, .chapters + div');
    out.push({
      key: R_path(href),
      name: link.text(),
      chapterNumber: -1,
      dateUpload: parseWpDate(dEl ? dEl.text() : ''),
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

async function parseChaptersAsmx(mangaKey) {
  var seg = String(mangaKey).replace(/\\/+$/, '').split('/').pop() || '';
  var comicId = '', slug = seg;
  var dash = seg.lastIndexOf('-');
  if (dash > 0 && /^\\d+$/.test(seg.slice(dash + 1))) {
    comicId = seg.slice(dash + 1);
    slug = seg.slice(0, dash);
  }
  var url = BASE + '/Comic/Services/ComicService.asmx/ChapterList?slug=' + encodeURIComponent(slug);
  if (CFG.asmxComicId && comicId) {
    url += '&comicId=' + encodeURIComponent(comicId);
  }
  var text = await $.http.get(url);
  var json = JSON.parse(text);
  var list = json.data || [];
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var c = list[i];
    var key = '/truyen-tranh/' + slug + '/' + c.chapter_slug;
    if (c.chapter_id) { key += '/' + c.chapter_id; }
    out.push({
      key: key,
      name: c.chapter_name || ('Chapter ' + (c.chapter_num || '')),
      chapterNumber: typeof c.chapter_num === 'number' ? c.chapter_num : -1,
      dateUpload: parseWpDate(c.updated_at || ''),
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    var url = BASE + '/' + CFG.popularPath + (page > 1 ? '?page=' + page : '');
    var doc = $.html.parse(await $.http.get(url));
    var out = parseList(doc);
    return { mangas: out, hasNextPage: hasNextPage(doc) };
  },

  getSearchManga: async function (page, query) {
    var url = BASE + '/' + CFG.searchPath + '?' + CFG.queryParam + '=' + encodeURIComponent(query || '') +
      '&page=' + page + '&sort=0';
    var doc = $.html.parse(await $.http.get(url));
    var out = parseList(doc);
    return { mangas: out, hasNextPage: hasNextPage(doc) };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey)));
    return parseDetail(doc, mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var chapters;
    if (CFG.chapterApi === 'asmx') {
      chapters = await parseChaptersAsmx(mangaKey);
    } else {
      var doc = $.html.parse(await $.http.get(R_abs(mangaKey)));
      chapters = parseChaptersHtml(doc);
    }
    // site lists newest first; normalize to oldest-first
    chapters.reverse();
    for (var i = 0; i < chapters.length; i++) { chapters[i].sortOrder = i; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var url = R_abs(chapterKey);
    if (CFG.pageListAll) { url = url.replace(/\\/+$/, '') + '/all'; }
    var doc = $.html.parse(await $.http.get(url));
    var els = R_sel(doc, CFG.pageSelector);
    var pages = [];
    var seen = {};
    for (var i = 0; i < els.length; i++) {
      var u = imageOrNull(els[i]);
      if (u && !seen[u]) {
        seen[u] = true;
        pages.push({ index: pages.length, url: u });
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
