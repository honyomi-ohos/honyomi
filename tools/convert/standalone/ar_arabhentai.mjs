// ar/arabhentai — bespoke scraper
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'genre/status browse filters not portable; plain keyword search only',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};

function parseRelativeDate(s) {
  if (!s) { return 0; }
  var v = String(s).replace(/منذ/g, '')
    .replace(/ساعة/g, '1h').replace(/ساعه/g, '1h')
    .replace(/أيام/g, 'd').replace(/يوم/g, 'd')
    .replace(/أسبوع/g, '7d').replace(/اسبوع/g, '7d')
    .replace(/شهر/g, 'mo').replace(/سنة/g, 'y').replace(/عام/g, 'y');
  var m = /(\\d+)\\s*([hidwmsy])/.exec(v);
  if (!m) { return 0; }
  var amount = parseInt(m[1], 10);
  var mult;
  if (m[2] === 'h' || m[2] === 'i') { mult = 3600000; }
  else if (m[2] === 'd' || m[2] === 'w') { mult = 24 * 3600000; }
  else if (m[2] === 'm' && v.indexOf('mo') !== -1) { mult = 30 * 24 * 3600000; }
  else { mult = 365 * 24 * 3600000; }
  return Date.now() - amount * mult;
}

function parseStatus(s) {
  if (!s) { return ''; }
  var lower = s.toLowerCase();
  if (lower.indexOf('مستمر') !== -1) { return 'ongoing'; }
  if (lower.indexOf('مكتمل') !== -1 || lower.indexOf('النهاية') !== -1) { return 'completed'; }
  if (lower.indexOf('متوقف') !== -1) { return 'hiatus'; }
  return '';
}

async function parseListing(url) {
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var anchors = R_sel(doc, "a[href*='/manga/']:not([href*='/chapter-'])");
  var out = [];
  var seen = {};
  for (var i = 0; i < anchors.length; i++) {
    var el = anchors[i];
    var link = el.absUrl('href');
    if (!link) { continue; }
    var key = R_path(link);
    if (seen[key]) { continue; }
    var titleEl = R_selFirst(el, '.font-haffer, img[alt]');
    var title = '';
    if (titleEl) {
      title = R_ownText(titleEl) || titleEl.attr('alt') || '';
      title = title.trim();
    }
    if (!title) { continue; }
    seen[key] = true;
    var img = R_selFirst(el, 'img[data-original]');
    var cover = '';
    if (img) {
      cover = img.attr('data-original') || '';
    } else {
      var img2 = R_selFirst(el, 'img[src]');
      cover = img2 ? (img2.attr('src') || '') : '';
    }
    out.push({ key: key, title: title, coverUrl: cover ? R_abs(cover) : '' });
  }
  var hasNext = false;
  var pagers = R_sel(doc, "a[href*='page=']");
  for (var j = 0; j < pagers.length; j++) {
    if (pagers[j].text() === '›') { hasNext = true; break; }
  }
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    var url = BASE + '/search/manga?status=-1&sort=11' + (page > 1 ? '&page=' + page : '');
    return parseListing(url);
  },

  getSearchManga: async function (page, query) {
    var url = BASE + '/search/manga?keyword=' + encodeURIComponent(query.trim()) + (page > 1 ? '&page=' + page : '');
    return parseListing(url);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var h1 = R_selFirst(doc, 'h1.font-haffer, h1');
    var cover = R_selFirst(doc, "img[src*='mangaonl.com'], img[src*='covers/']");
    var coverUrl = cover ? (cover.attr('src') || '') : '';
    if (!coverUrl) {
      var og = R_selFirst(doc, "meta[property='og:image']");
      coverUrl = og ? (og.attr('content') || '') : '';
    }
    var status = '';
    var author = '';
    var paras = R_sel(doc, 'p');
    for (var i = 0; i < paras.length; i++) {
      var t = paras[i].text();
      if (!author && t.indexOf('المؤلف') !== -1) {
        var aSpan = R_selFirst(paras[i], 'span[class]');
        if (aSpan) { author = aSpan.text().trim(); }
      }
      if (!status && t.indexOf('الحالة') !== -1) {
        var sSpan = R_selFirst(paras[i], 'span[class]');
        if (sSpan) { status = parseStatus(sSpan.text()); }
      }
    }
    var genreEls = R_sel(doc, "a[href*='genre=']");
    var genres = [];
    for (var g = 0; g < genreEls.length; g++) {
      var gt = genreEls[g].text().trim();
      if (gt) { genres.push(gt); }
    }
    var descEl = R_selFirst(doc, "article[class*='bg-background-detail'], .description, .synopsis, .about");
    return {
      key: mangaKey,
      title: h1 ? h1.text() : '',
      coverUrl: coverUrl ? R_abs(coverUrl) : '',
      author: author,
      artist: '',
      description: descEl ? descEl.text() : '',
      genre: genres.join(', '),
      status: status,
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var anchors = R_sel(doc, "a[href*='/chapter-']:not([class*='rounded-2xl'])");
    var out = [];
    var seen = {};
    for (var i = 0; i < anchors.length; i++) {
      var el = anchors[i];
      var url = el.absUrl('href');
      if (!url) { continue; }
      var key = R_path(url);
      if (seen[key]) { continue; }
      seen[key] = true;
      var nameEl = R_selFirst(el, '.font-semibold');
      var pEl = R_selFirst(el, 'p');
      var name = nameEl ? nameEl.text() : (pEl ? pEl.text() : key.split('/').pop());
      var dateEl = R_selFirst(el, '.text-lightgray');
      out.push({
        key: key,
        name: name,
        chapterNumber: -1,
        dateUpload: parseRelativeDate(dateEl ? dateEl.text() : ''),
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
    var imgs = R_sel(doc, "img[alt^='Page'], img[src*='mangaonl.com']");
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].attr('src') || imgs[i].attr('data-original') || '';
      if (u) { pages.push({ index: pages.length, url: R_abs(u) }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
