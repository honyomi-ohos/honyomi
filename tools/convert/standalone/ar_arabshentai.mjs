// ar/arabshentai — bespoke WordPress manga scraper
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'genre/status browse filters not portable; plain keyword search only',
      'site currently 403 (Cloudflare bot block) from this network — probe may fail environmentally',
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

function parseChapterDate(s) {
  if (!s) { return 0; }
  var m = /(\\d{1,2})\\s*([^\\d\\s]+)\\D+(\\d{4})/.exec(String(s).trim());
  if (!m) { return 0; }
  var day = parseInt(m[1], 10);
  var mon = AR_MONTHS[m[2]] || 0;
  var year = parseInt(m[3], 10);
  if (!mon) { return 0; }
  return Date.parse(year + '-' + (mon < 10 ? '0' + mon : mon) + '-' + (day < 10 ? '0' + day : day) + 'T00:00:00Z');
}

function parseStatus(s) {
  if (!s) { return ''; }
  var lower = s.toLowerCase();
  if (lower.indexOf('مستمر') !== -1) { return 'ongoing'; }
  if (lower.indexOf('مكتمل') !== -1) { return 'completed'; }
  if (lower.indexOf('متوقف') !== -1) { return 'hiatus'; }
  if (lower.indexOf('ملغية') !== -1) { return 'cancelled'; }
  return '';
}

function imgAttr(img) {
  if (!img) { return ''; }
  var v;
  if ((v = img.attr('srcset'))) { return v.split(' ')[0]; }
  if ((v = img.attr('data-cfsrc'))) { return v; }
  if ((v = img.attr('data-src'))) { return v; }
  if ((v = img.attr('data-lazy-src'))) { return v; }
  if ((v = img.attr('bv-data-src'))) { return v; }
  return img.attr('src') || '';
}

function infoSpan(info, label) {
  var divs = R_sel(info, 'div');
  for (var i = 0; i < divs.length; i++) {
    var b = R_selFirst(divs[i], 'b');
    if (!b || b.text().indexOf(label) === -1) { continue; }
    var span = R_selFirst(divs[i], 'span');
    return span || null;
  }
  return null;
}

function spanText(info, label) {
  var span = infoSpan(info, label);
  return span ? span.text() : '';
}

async function parseListing(url) {
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var items = R_sel(doc, '#archive-content .wp-manga');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var link = R_selFirst(items[i], '.data h3 a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    out.push({
      key: R_path(href),
      title: link.text(),
      coverUrl: imgAttr(R_selFirst(items[i], 'a .poster img')),
    });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, '.pagination a.arrow_pag i#nextpagination') };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseListing(BASE + '/manga/page/' + page + '/?orderby=new-manga');
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/page/' + page + '/?s=' + encodeURIComponent(query));
    var doc = $.html.parse(text);
    var articles = R_sel(doc, '.search-page .result-item article');
    var out = [];
    for (var i = 0; i < articles.length; i++) {
      if (R_selFirst(articles[i], '.tvshows')) { continue; }
      var titleElement = R_selFirst(articles[i], '.details .title');
      if (!titleElement) { continue; }
      var link = R_selFirst(titleElement, 'a');
      if (!link || !link.absUrl('href')) { continue; }
      out.push({
        key: R_path(link.absUrl('href')),
        title: titleElement.text(),
        coverUrl: imgAttr(R_selFirst(articles[i], '.image .thumbnail a img')),
      });
    }
    var hasNext = false;
    var pag = R_selFirst(doc, '.pagination');
    if (pag) {
      var current = R_selFirst(pag, 'span.current');
      var anchors = R_sel(pag, 'a');
      if (current) {
        var n = parseInt(current.text(), 10);
        for (var j = 0; j < anchors.length; j++) {
          if (parseInt(anchors[j].text(), 10) === n + 1) { hasNext = true; break; }
        }
      }
    }
    return { mangas: out, hasNextPage: hasNext };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var content = R_selFirst(doc, '.content');
    if (!content) { throw new Error('Failed to parse manga details'); }
    var genres = [];
    var description = '';
    var status = '';
    var author = '';
    var artist = '';
    var info = R_selFirst(content, '#manga-info');
    if (info) {
      var ps = R_sel(info, '.wp-content p');
      var ptexts = [];
      for (var p = 0; p < ps.length; p++) { ptexts.push(ps[p].text()); }
      description = '\\u061C' + ptexts.join(' ') + '\\n' + 'أسماء أُخرى: ' + spanText(info, 'أسماء أُخرى');
      status = parseStatus(spanText(info, 'حالة المانجا'));
      var authorSpan = infoSpan(info, 'الكاتب');
      if (authorSpan) {
        var as = R_sel(authorSpan, 'a');
        var anames = [];
        for (var a = 0; a < as.length; a++) { anames.push(as[a].text()); }
        author = anames.join(' ');
      }
      var artistSpan = infoSpan(info, 'الرسام');
      if (artistSpan) {
        var arts = R_sel(artistSpan, 'a');
        var artnames = [];
        for (var r = 0; r < arts.length; r++) { artnames.push(arts[r].text()); }
        artist = artnames.join(' ');
      }
      var typeSpan = infoSpan(info, 'نوع العمل');
      if (typeSpan) {
        var ts = R_sel(typeSpan, 'a');
        for (var t = 0; t < ts.length; t++) {
          if (ts[t].text()) { genres.push(ts[t].text()); }
        }
      }
    }
    var sg = R_sel(content, '.data .sgeneros a');
    for (var g = 0; g < sg.length; g++) { genres.push(sg[g].text()); }
    return {
      key: mangaKey,
      title: (R_selFirst(content, '.sheader .data h1') || { text: function () { return ''; } }).text(),
      coverUrl: imgAttr(R_selFirst(content, '.sheader .poster img')),
      author: author,
      artist: artist,
      description: description,
      genre: genres.join(', '),
      status: status,
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var anchors = R_sel(doc, "#chapter-list a[href*='/manga/']");
    var oneshots = R_sel(doc, ".oneshot-reader .images .image-item a[href$='manga-paged=1']");
    var all = anchors.concat(oneshots);
    var out = [];
    var seen = {};
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      var url = el.absUrl('href');
      if (!url) { continue; }
      var key;
      var name;
      var date;
      if (url.indexOf('style=paged') !== -1) {
        key = R_path(url.substring(0, url.lastIndexOf('?')));
        name = 'ونشوت';
        date = 0;
      } else {
        key = R_path(url);
        var numEl = R_selFirst(el, '.chapternum');
        var dateEl = R_selFirst(el, '.chapterdate');
        name = numEl ? numEl.text() : el.text();
        date = parseChapterDate(dateEl ? dateEl.text() : '');
      }
      if (seen[key]) { continue; }
      seen[key] = true;
      out.push({
        key: key,
        name: name,
        chapterNumber: -1,
        dateUpload: date,
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
    var imgs = R_sel(doc, '.chapter_image img.wp-manga-chapter-img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgAttr(imgs[i]);
      if (u) { pages.push({ index: pages.length, url: R_abs(u) }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/', Origin: BASE };
  },
};
`;
}
