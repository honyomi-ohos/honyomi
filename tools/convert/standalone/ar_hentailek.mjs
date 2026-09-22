// ar/hentailek — bespoke scraper
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'site search does not paginate beyond page 1 (upstream behavior preserved)',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};

var AR_MONTHS = {
  'يناير': 1, 'فبراير': 2, 'مارس': 3, 'أبريل': 4, 'ابريل': 4, 'مايو': 5, 'يونيو': 6,
  'يوليو': 7, 'أغسطس': 8, 'اغسطس': 8, 'سبتمبر': 9, 'أكتوبر': 10, 'اكتوبر': 10,
  'نوفمبر': 11, 'ديسمبر': 12,
};

// "d MMMM yyyy" Arabic, Asia/Riyadh (+03:00)
function parseDate(s) {
  if (!s) { return 0; }
  var m = /(\\d{1,2})\\s*([^\\d\\s]+)\\s*(\\d{4})/.exec(String(s).trim());
  if (!m) { return 0; }
  var day = parseInt(m[1], 10);
  var mon = AR_MONTHS[m[2]] || 0;
  var year = parseInt(m[3], 10);
  if (!mon) { return 0; }
  return Date.UTC(year, mon - 1, day) - 3 * 3600000;
}

function parseStatus(s) {
  if (!s) { return ''; }
  var lower = s.toLowerCase();
  if (lower.indexOf('مكتمل') !== -1) { return 'completed'; }
  if (lower.indexOf('مستمر') !== -1) { return 'ongoing'; }
  if (lower.indexOf('متوقف') !== -1) { return 'hiatus'; }
  return '';
}

// dt:contains(key) + dd pairing (no sibling traversal in host selector engine)
function infoValue(doc, key) {
  var dts = R_sel(doc, 'dt');
  var dds = R_sel(doc, 'dd');
  for (var i = 0; i < dts.length; i++) {
    if (dts[i].text().indexOf(key) === -1) { continue; }
    if (i < dds.length) {
      var t = dds[i].text().trim();
      if (t) { return t; }
    }
    break;
  }
  return '';
}

async function parseListing(url, page) {
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var anchors = R_sel(doc, "a[href*='/manga/']:not([href*='/chapter-'])");
  var out = [];
  var seen = {};
  for (var i = 0; i < anchors.length; i++) {
    var el = anchors[i];
    var link = el.absUrl('href');
    if (!link || link.indexOf('/manga/') === -1 || link.indexOf('/chapter-') !== -1) { continue; }
    var key = R_path(link);
    if (seen[key]) { continue; }
    var img = R_selFirst(el, 'img[src]');
    var h3 = R_selFirst(el, 'h3');
    var title = h3 ? h3.text() : (el.attr('aria-label') || (img ? (img.attr('alt') || '') : ''));
    if (!title) { continue; }
    seen[key] = true;
    out.push({
      key: key,
      title: title.trim(),
      coverUrl: img ? (img.attr('src') || '') : '',
    });
  }
  var hasNext = false;
  var pagers = R_sel(doc, "a[href*='page=']");
  for (var j = 0; j < pagers.length; j++) {
    var m = /page=(\\d+)/.exec(pagers[j].attr('href') || '');
    if (m && parseInt(m[1], 10) === page + 1) { hasNext = true; break; }
  }
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    var url = BASE + '/library?sort=popular' + (page > 1 ? '&page=' + page : '');
    return parseListing(url, page);
  },

  getSearchManga: async function (page, query) {
    return parseListing(BASE + '/search?q=' + encodeURIComponent(query.trim()), page);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var h1 = R_selFirst(doc, 'h1');
    var cover = R_selFirst(doc, "img[src*='cover']");
    var coverUrl = cover ? (cover.attr('src') || '') : '';
    if (!coverUrl) {
      var og = R_selFirst(doc, "meta[property='og:image']");
      coverUrl = og ? (og.attr('content') || '') : '';
    }
    var descParas = R_sel(doc, 'p.border-t.text-sm.leading-relaxed');
    var description = '';
    for (var i = 0; i < descParas.length; i++) {
      var t = descParas[i].text();
      if (t.length > description.length) { description = t; }
    }
    return {
      key: mangaKey,
      title: h1 ? h1.text() : '',
      coverUrl: coverUrl,
      author: infoValue(doc, 'المؤلف'),
      artist: infoValue(doc, 'الرسم'),
      description: description,
      genre: infoValue(doc, 'التصنيفات'),
      status: parseStatus(infoValue(doc, 'الحالة')),
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var anchors = R_sel(doc, "a[href*='/chapter-'][class*='group']");
    var out = [];
    var seen = {};
    for (var i = 0; i < anchors.length; i++) {
      var el = anchors[i];
      var url = el.absUrl('href');
      if (!url) { continue; }
      var key = R_path(url);
      if (seen[key]) { continue; }
      seen[key] = true;
      var name = '';
      var spans = R_sel(el, 'span');
      for (var s = 0; s < spans.length; s++) {
        if (spans[s].text().indexOf('الفصل') !== -1) {
          name = R_ownText(spans[s]).trim();
          break;
        }
      }
      if (!name) { name = key.split('/').pop(); }
      var dateEl = R_selFirst(el, 'span.text-xs.text-muted');
      out.push({
        key: key,
        name: name,
        chapterNumber: -1,
        dateUpload: parseDate(dateEl ? dateEl.text() : ''),
        pages: 0,
        sortOrder: 0,
      });
    }
    // page lists newest-first; host convention is oldest-first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, '.reader-page img[src], .reader-page img[data-src], .on-canvas img');
    var pages = [];
    var seen = {};
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].attr('src') || imgs[i].attr('data-src') || '';
      if (!u || seen[u]) { continue; }
      seen[u] = true;
      pages.push({ index: pages.length, url: R_abs(u) });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
