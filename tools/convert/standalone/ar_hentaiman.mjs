// ar/hentaiman — bespoke scraper
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};

// "dd/MM/yy"
function parseDate(s) {
  if (!s) { return 0; }
  var m = /^(\\d{1,2})\\/(\\d{1,2})\\/(\\d{2,4})$/.exec(String(s).trim());
  if (!m) { return 0; }
  var day = parseInt(m[1], 10);
  var mon = parseInt(m[2], 10);
  var year = parseInt(m[3], 10);
  if (year < 100) { year += 2000; }
  return Date.parse(year + '-' + (mon < 10 ? '0' + mon : mon) + '-' + (day < 10 ? '0' + day : day) + 'T00:00:00Z');
}

async function parseListing(url) {
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var cards = R_sel(doc, '#manga-grid > div');
  var out = [];
  var seen = {};
  for (var i = 0; i < cards.length; i++) {
    var card = cards[i];
    var link = R_selFirst(card, 'a[href*=/manga/]');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var key = R_path(href);
    if (seen[key]) { continue; }
    var h3 = R_selFirst(card, 'h3');
    if (!h3) { continue; }
    var img = R_selFirst(card, 'img[src*=storage/covers]');
    var imgSrc = '';
    if (img) {
      imgSrc = img.attr('src') || '';
      if (!imgSrc) { imgSrc = img.attr('data-src') || ''; }
    }
    seen[key] = true;
    out.push({ key: key, title: h3.text().trim(), coverUrl: imgSrc ? R_abs(imgSrc) : '' });
  }
  return { mangas: out, hasNextPage: out.length > 0 };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseListing(BASE + '/manga?page=' + page);
  },

  getSearchManga: async function (page, query) {
    return parseListing(BASE + '/manga?page=' + page + '&search=' + encodeURIComponent(query));
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var h1 = R_selFirst(doc, 'h1');
    var cover = R_selFirst(doc, 'img[src*=storage/covers/lg], img[src*=storage/covers/md]');
    var alt = R_selFirst(doc, '[aria-label=Alternative Title]');
    var description = alt ? alt.text().trim() : '';
    if (!description) {
      var dd = R_selFirst(doc, 'dl dd');
      description = dd ? dd.text().trim() : '';
    }
    var genreEls = R_sel(doc, 'a[href*=list/genre]');
    var genres = [];
    for (var g = 0; g < genreEls.length; g++) {
      var gt = genreEls[g].text().trim();
      if (gt) { genres.push(gt); }
    }
    var status = '';
    if (R_selFirst(doc, 'span.status-completed')) { status = 'completed'; }
    else if (R_selFirst(doc, 'span.status-on-going')) { status = 'ongoing'; }
    else if (R_selFirst(doc, 'span.status-hiatus')) { status = 'hiatus'; }
    else if (R_selFirst(doc, 'span.status-canceled')) { status = 'cancelled'; }
    return {
      key: mangaKey,
      title: h1 ? h1.text().trim() : '',
      coverUrl: cover ? (cover.attr('src') || '') : '',
      author: '',
      artist: '',
      description: description,
      genre: genres.join(', '),
      status: status,
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var items = R_sel(doc, 'li.chapter-item');
    var out = [];
    var seen = {};
    for (var i = 0; i < items.length; i++) {
      var item = items[i];
      var link = R_selFirst(item, 'a[href]');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var key = R_path(href);
      if (seen[key]) { continue; }
      seen[key] = true;
      // chapter number from path after the manga path
      var after = href.substring(href.indexOf(R_path(mangaKey)) + R_path(mangaKey).length + 1);
      var lastSeg = after.split('/').filter(Boolean).pop() || '';
      var num = parseFloat(lastSeg);
      var name = '';
      var spans = R_sel(link, 'span');
      for (var s = 0; s < spans.length; s++) {
        if (!spans[s].attr('class')) { name = spans[s].text().trim(); break; }
      }
      var dateEl = R_selFirst(link, 'p.text-gray-400');
      out.push({
        key: key,
        name: 'الفصل ' + (isNaN(num) ? '?' : (num % 1 === 0 ? num : num)) + ' - ' + name,
        chapterNumber: isNaN(num) ? 0 : num,
        dateUpload: parseDate(dateEl ? dateEl.text() : ''),
        pages: 0,
        sortOrder: 0,
      });
    }
    // newest-first (sorted by number desc); host convention is oldest-first
    out.sort(function (a, b) { return b.chapterNumber - a.chapterNumber; });
    var unique = [];
    var seenUrl = {};
    for (var u = 0; u < out.length; u++) {
      if (seenUrl[out[u].key]) { continue; }
      seenUrl[out[u].key] = true;
      unique.push(out[u]);
    }
    unique.reverse();
    for (var j = 0; j < unique.length; j++) { unique[j].sortOrder = j; }
    return unique;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, '#reader img.reader-page');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].attr('src') || imgs[i].attr('data-src') || '';
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
