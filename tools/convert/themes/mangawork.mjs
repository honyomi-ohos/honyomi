// MangaWork theme engine (pt: apecomics, pizzariascan) — WP + admin-ajax chapter pagination
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText || '';
  const warnings = [];
  const config = { seriesPath: 'series' };
  const src = (ctx.gradle && ctx.gradle.sources && ctx.gradle.sources[0]) || {};
  const base = String(src.baseUrl || '');
  if (/pizzariascan/i.test(base) || /todas-as-obras/.test(kt)) {
    config.seriesPath = 'todas-as-obras';
  }
  warnings.push('filters (order/status/type/genre/year) not supported by host; text search only');
  warnings.push('chapter ajax pagination sent as urlencoded instead of multipart');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mangawork)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var PT_MONTHS = {
  'janeiro': '01', 'fevereiro': '02', 'marco': '03', 'abril': '04', 'maio': '05', 'junho': '06',
  'julho': '07', 'agosto': '08', 'setembro': '09', 'outubro': '10', 'novembro': '11', 'dezembro': '12'
};

function stripDiacritics(s) {
  return String(s || '').normalize('NFD').replace(/[\\u0300-\\u036f]/g, '');
}

function parseChapterDate(s) {
  var t = String(s || '').trim();
  if (!t) { return 0; }
  var m = /(\\d{1,2})\\/(\\d{1,2})\\/(\\d{4})/.exec(t);
  if (m) {
    return Math.floor(Date.UTC(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10)) / 1000);
  }
  var n = stripDiacritics(t).toLowerCase().split(' de ');
  if (n.length === 3) {
    var day = parseInt(n[0], 10);
    var mo = PT_MONTHS[n[1]];
    var year = parseInt(n[2], 10);
    if (day && mo && year) {
      return Math.floor(Date.UTC(year, parseInt(mo, 10) - 1, day) / 1000);
    }
  }
  return 0;
}

function statusMap(s) {
  var t = String(s || '').toLowerCase();
  if (t === 'publishing' || t === 'ongoing' || t === 'em andamento') { return 'ONGOING'; }
  if (t === 'finished' || t === 'completed' || t === 'concluido' || t === 'finalizado') { return 'COMPLETED'; }
  if (t === 'on hold' || t === 'on-hold' || t === 'hiatus' || t === 'em hiato') { return 'ON_HIATUS'; }
  if (t === 'cancelled' || t === 'canceled' || t === 'cancelado') { return 'CANCELLED'; }
  return 'UNKNOWN';
}

function imgSrc(el) {
  if (!el) { return ''; }
  return el.absUrl('src') || el.absUrl('data-src') || el.absUrl('data-lazy-src') || el.attr('src') || '';
}

function parseList(doc) {
  var entries = R_sel(doc, 'div.w-full.h-full:has(a[href*="/manga/"])');
  var mangas = [];
  for (var i = 0; i < entries.length; i++) {
    var anchor = R_selFirst(entries[i], 'a[href*="/manga/"]');
    if (!anchor) { continue; }
    var title = anchor.attr('title') || '';
    if (!title) {
      var h1 = R_selFirst(entries[i], 'h1');
      title = h1 ? h1.text() : '';
    }
    mangas.push({
      key: R_path(anchor.absUrl('href') || anchor.attr('href')),
      title: title,
      coverUrl: imgSrc(R_selFirst(anchor, 'img'))
    });
  }
  var hasNextPage = !!R_selFirst(doc, '.pagination .page-numbers.current + a[href]');
  return { mangas: mangas, hasNextPage: hasNextPage };
}

function seriesUrl(page, order) {
  var url = BASE + '/' + CFG.seriesPath + '/';
  if (page > 1) { url += 'page/' + page + '/'; }
  url += '?title=&order=' + order + '&status=&type=';
  return url;
}

function chapterElements(doc) {
  var container = R_selFirst(doc, '#chapter_list.chapter_list_container');
  if (!container) { return []; }
  return R_sel(container, ':scope > li');
}

function chapterFromElement(el) {
  var anchor = R_selFirst(el, 'a[href]');
  if (!anchor) { return null; }
  var nameEl = R_selFirst(el, 'span.m-0, span.line-clamp-1');
  var name = nameEl ? (nameEl.text() || '') : anchor.text();
  var spans = R_sel(el, 'span');
  var dateStr = spans.length > 0 ? spans[spans.length - 1].text() : '';
  var key = R_path(anchor.absUrl('href') || anchor.attr('href'));
  if (!key) { return null; }
  return { key: key, name: name, dateUpload: parseChapterDate(dateStr) };
}

function findNextButton(doc, currentPage) {
  var buttons = R_sel(doc, 'button.load-chapters[data-paged]');
  for (var i = 0; i < buttons.length; i++) {
    var p = parseInt(buttons[i].attr('data-paged'), 10);
    if (!isNaN(p) && p > currentPage) { return buttons[i]; }
  }
  return null;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(seriesUrl(page, 'popular'));
    return parseList($.html.parse(text));
  },

  getSearchManga: async function (page, query) {
    var url = seriesUrl(page, 'title');
    if (query) { url = url.replace('?title=&', '?title=' + encodeURIComponent(query) + '&'); }
    var text = await $.http.get(url);
    return parseList($.html.parse(text));
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(BASE + mangaKey);
    var doc = $.html.parse(text);
    var titleEl = R_selFirst(doc, 'h1.text-4xl.font-bold.mb-2');
    var imgEl = R_selFirst(doc, 'img[itemprop=image], [itemprop=image] img');
    var descEl = R_selFirst(doc, 'div.text-base.leading-relaxed.mb-6.text-muted-foreground');
    var genreEls = R_sel(doc, '[itemprop=genre]');
    var genres = [];
    for (var g = 0; g < genreEls.length; g++) { genres.push(genreEls[g].text()); }
    var author = '';
    var items = R_sel(doc, 'div.grid.grid-cols-2.gap-4.text-sm.text-gray-600.mb-6 > div');
    for (var i = 0; i < items.length; i++) {
      var strong = R_selFirst(items[i], 'strong');
      if (strong && strong.text() === 'Autor(es)') {
        var p = R_selFirst(items[i], 'p');
        author = p ? p.text() : '';
        break;
      }
    }
    var status = 'UNKNOWN';
    var statusEl = R_selFirst(doc, '*:has(+ [itemprop=genre])');
    if (statusEl) { status = statusMap(statusEl.text()); }
    return {
      key: mangaKey,
      title: titleEl ? titleEl.text() : '',
      coverUrl: imgSrc(imgEl),
      author: author,
      description: descEl ? descEl.text() : '',
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(BASE + mangaKey);
    var doc = $.html.parse(text);
    var chapters = [];
    var els = chapterElements(doc);
    for (var i = 0; i < els.length; i++) {
      var c = chapterFromElement(els[i]);
      if (c) { chapters.push(c); }
    }
    var container = R_selFirst(doc, '#chapter_list.chapter_list_container');
    if (container) {
      var postId = container.attr('data-post-id') || '';
      var count = container.attr('data-count') || '1000';
      if (postId) {
        var requested = {};
        var currentPage = 1;
        var nextButton = findNextButton(doc, currentPage);
        while (nextButton) {
          var pageStr = nextButton.attr('data-paged') || '';
          if (!pageStr || requested[pageStr]) { break; }
          requested[pageStr] = true;
          var order = nextButton.attr('data-order') || 'DESC';
          var body = 'action=load_chapters&post_id=' + encodeURIComponent(postId)
            + '&count=' + encodeURIComponent(count)
            + '&paged=' + encodeURIComponent(pageStr)
            + '&order=' + encodeURIComponent(order);
          var pageText = await $.http.post(BASE + '/wp-admin/admin-ajax.php', body, {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': BASE + mangaKey,
            'Origin': BASE,
            'Accept': '*/*'
          });
          var pageDoc = $.html.parse(pageText);
          var pageEls = chapterElements(pageDoc);
          for (var j = 0; j < pageEls.length; j++) {
            var c2 = chapterFromElement(pageEls[j]);
            if (c2) { chapters.push(c2); }
          }
          var parsed = parseInt(pageStr, 10);
          if (!isNaN(parsed)) { currentPage = parsed; }
          nextButton = findNextButton(pageDoc, currentPage);
        }
      }
    }
    var seen = {};
    var unique = [];
    for (var k = 0; k < chapters.length; k++) {
      if (!seen[chapters[k].key]) {
        seen[chapters[k].key] = true;
        unique.push(chapters[k]);
      }
    }
    // site lists newest first (order DESC); host expects oldest first
    unique.reverse();
    return unique;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(BASE + chapterKey);
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, 'div.reader-area img#imagech, div.reader-area img[src*="/manga_auto_capitulos/"]');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var src = imgSrc(imgs[i]);
      if (src) { pages.push(src); }
    }
    if (pages.length > 0) { return pages; }
    var html = doc.html ? doc.html() : '';
    var re = /"image"\\s*:\\s*"([^"]+)"/g;
    var m;
    while ((m = re.exec(html)) !== null) {
      pages.push(m[1].replace(/\\\\\\//g, '/'));
    }
    return pages;
  },

  imageHeaders: function () {
    return { 'Referer': BASE + '/' };
  }
};
`;
}
