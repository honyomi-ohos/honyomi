// all/projectsuki — bespoke engine (anchor-pattern book scan + callpage API pages)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: [
      'smart search approximated by simple word-count search over /api/book/search; language black/white-list prefs and missing-chapter-number inference not portable',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var BOOK_RE = /^https?:\\/\\/[^\\/]*projectsuki\\.com\\/book\\/([^\\/?#]+)/i;
var READ_RE = /^https?:\\/\\/[^\\/]*projectsuki\\.com\\/read\\/([^\\/]+)\\/([^\\/?#]+)/i;
var CH_NUM_RE = /(?:chapter|ch\\.?)\\s*(\\d+)(?:\\s*[.,-]\\s*(\\d+)?)?/i;
var REL_DATE_RE = /(\\d+)\\s+(years?|months?|weeks?|days?|hours?|mins?|minutes?|seconds?|sec)\\s+ago/i;

function parseDate(s) {
  var v = String(s || '').trim();
  if (!v) { return 0; }
  var m = v.match(REL_DATE_RE);
  if (m) { return R_date(v); }
  var t = Date.parse(v);
  return isNaN(t) ? 0 : t;
}
function imgSrc(el) {
  var names = ['src', 'data-src', 'data-lazy-src'];
  for (var i = 0; i < names.length; i++) {
    var v = el.attr(names[i]);
    if (v) { return R_abs(v.split(' ')[0]); }
  }
  var ss = el.attr('srcset');
  if (ss) { return R_abs(ss.split(' ')[0]); }
  return '';
}
function thumbExtFromUrl(u) {
  var m = String(u).split('?')[0].match(/thumb\\.([a-z0-9]+)$/i);
  return m ? '.' + m[1] : '';
}
// scan all anchors matching /book/<id> and build book entries
function scanBooks(doc) {
  var anchors = R_sel(doc, 'a[href]');
  var order = [];
  var byId = {};
  for (var i = 0; i < anchors.length; i++) {
    var a = anchors[i];
    var href = a.absUrl('href');
    var m = href.match(BOOK_RE);
    if (!m) { continue; }
    var id = m[1];
    if (!byId[id]) {
      byId[id] = { id: id, title: '', ext: '' };
      order.push(id);
    }
    var entry = byId[id];
    if (!entry.title) {
      var imgs = R_sel(a, 'img');
      if (imgs.length === 0) {
        var txt = R_ownText(a) || a.text();
        if (txt && txt.toLowerCase() !== 'show more') { entry.title = txt; }
      }
    }
    if (!entry.ext) {
      var allImgs = R_sel(a, 'img');
      for (var k = 0; k < allImgs.length; k++) {
        var src = imgSrc(allImgs[k]);
        if (src.indexOf('/images/gallery/') >= 0) {
          entry.ext = thumbExtFromUrl(src);
          if (entry.ext) { break; }
        }
      }
    }
  }
  var out = [];
  for (var j = 0; j < order.length; j++) {
    var e = byId[order[j]];
    out.push({
      key: '/book/' + e.id,
      title: e.title || ('Book ' + e.id),
      coverUrl: BASE + '/images/gallery/' + e.id + '/thumb' + e.ext,
    });
  }
  return out;
}
function originGenre(origin) {
  if (/^kr|korea\\s*(\\(south\\))?$/i.test(origin)) { return 'Manhwa'; }
  if (/^cn|china?$/i.test(origin)) { return 'Manhua'; }
  if (/^jp|japan?$/i.test(origin)) { return 'Manga'; }
  return '';
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/browse/' + (page - 1));
    var mangas = scanBooks($.html.parse(text));
    return { mangas: mangas, hasNextPage: mangas.length >= 30 };
  },

  getSearchManga: async function (page, query) {
    // simple word-count search over the server book index (ProjectSukiAPI)
    var body = JSON.stringify({ hash: null });
    var text = await $.http.post(BASE + '/api/book/search', body, {
      'X-Requested-With': 'XMLHttpRequest',
      'Content-Type': 'application/json',
      'Referer': BASE + '/browse',
    });
    var dto = JSON.parse(text);
    var data = dto.data || {};
    var words = String(query).match(/[a-z0-9]+/gi) || [];
    var matches = [];
    for (var id in data) {
      var title = (data[id] && data[id].value) || '';
      var count = 0;
      for (var w = 0; w < words.length; w++) {
        var word = words[w];
        var idx = 0;
        while (true) {
          var found = title.toLowerCase().indexOf(word.toLowerCase(), idx);
          if (found < 0) { break; }
          idx = found + 1;
          count++;
        }
      }
      if (count > 0) { matches.push({ id: id, title: title, count: count }); }
    }
    matches.sort(function (a, b) { return b.count - a.count || (a.title < b.title ? -1 : a.title > b.title ? 1 : 0); });
    var mangas = matches.map(function (m2) {
      return { key: '/book/' + m2.id, title: m2.title, coverUrl: BASE + '/images/gallery/' + m2.id + '/thumb' };
    });
    return { mangas: mangas, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var title = '';
    var h2 = R_selFirst(doc, 'h2[itemprop=title]') || R_selFirst(doc, 'h2');
    if (h2) { title = h2.text(); }
    var desc = '';
    var descEl = R_selFirst(doc, '#descriptionCollapse');
    if (descEl) {
      desc = descEl.text();
    } else {
      var ds = R_sel(doc, '.description');
      var parts = [];
      for (var i = 0; i < ds.length; i++) { parts.push(ds[i].text()); }
      desc = parts.join('\\n\\n');
    }
    // details table rows: label -> value
    var details = {};
    var rows = R_sel(doc, 'tr');
    for (var r = 0; r < rows.length; r++) {
      var cells = R_sel(rows[r], 'td, th');
      if (cells.length < 2) { continue; }
      var label = cells[0].text().trim().toLowerCase().replace(/:$/, '');
      details[label] = cells[1].text().trim();
    }
    var genre = details['genre'] || details['genre(s)'] || '';
    var og = originGenre(details['origin'] || '');
    if (og) { genre = genre ? genre + ', ' + og : og; }
    var statusRaw = (details['status'] || '').toLowerCase();
    var status = '';
    if (statusRaw === 'ongoing') { status = 'ongoing'; }
    else if (statusRaw === 'completed') { status = 'completed'; }
    else if (statusRaw === 'hiatus') { status = 'hiatus'; }
    else if (statusRaw === 'cancelled') { status = 'cancelled'; }
    var cover = '';
    var imgs = R_sel(doc, 'img');
    for (var k = 0; k < imgs.length; k++) {
      var src = imgSrc(imgs[k]);
      if (src.indexOf('/images/gallery/') >= 0) {
        var ext = thumbExtFromUrl(src);
        cover = BASE + '/images/gallery/' + String(mangaKey).split('/').pop() + '/thumb' + ext;
        break;
      }
    }
    return {
      key: mangaKey,
      title: title || 'Book ' + String(mangaKey).split('/').pop(),
      coverUrl: cover,
      author: details['author'] || details['authors'] || '',
      description: desc,
      genre: genre,
      status: status,
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var chapters = [];
    var tables = R_sel(doc, 'table');
    for (var t = 0; t < tables.length; t++) {
      var thead = R_selFirst(tables[t], 'thead');
      var tbody = R_selFirst(tables[t], 'tbody');
      if (!thead || !tbody) { continue; }
      var headerRows = R_sel(thead, 'tr');
      var colMap = null;
      for (var hr = 0; hr < headerRows.length; hr++) {
        var headers = R_sel(headerRows[hr], 'td');
        var map = {};
        for (var c = 0; c < headers.length; c++) {
          var h = headers[c].text().trim().toLowerCase();
          if (/^chapters?$/.test(h)) { map.chapter = c; }
          else if (/^groups?$/.test(h)) { map.group = c; }
          else if (/^(added|date)$/.test(h)) { map.added = c; }
          else if (/^language$/.test(h)) { map.language = c; }
          else if (/^views?(\\s*count)?$/.test(h)) { map.views = c; }
        }
        if (map.chapter !== undefined && map.group !== undefined && map.added !== undefined) {
          colMap = map;
          break;
        }
      }
      if (!colMap) { continue; }
      var maxCol = 0;
      for (var mk in colMap) { if (colMap[mk] > maxCol) { maxCol = colMap[mk]; } }
      var dataRows = R_sel(tbody, 'tr');
      for (var dr = 0; dr < dataRows.length; dr++) {
        var cells = R_sel(dataRows[dr], 'td');
        if (cells.length <= maxCol) { continue; }
        var chapterCell = cells[colMap.chapter];
        var link = R_selFirst(chapterCell, 'a[href]');
        if (!link) { continue; }
        var href = link.absUrl('href');
        var rm = href.match(READ_RE);
        if (!rm) { continue; }
        var titleText = chapterCell.text().trim();
        var numMatch = titleText.match(CH_NUM_RE);
        var num = -1;
        if (numMatch) {
          num = parseInt(numMatch[1], 10);
          if (numMatch[2]) { num = parseFloat(num + '.' + numMatch[2]); }
        }
        var language = colMap.language !== undefined ? cells[colMap.language].text().trim().toLowerCase() : 'unknown';
        var group = cells[colMap.group].text().trim();
        chapters.push({
          key: '/read/' + rm[1] + '/' + rm[2] + '/1',
          name: titleText,
          chapterNumber: num,
          dateUpload: parseDate(cells[colMap.added].text()),
          pages: 0,
          sortOrder: 0,
          _group: group,
          _lang: language,
        });
      }
    }
    // site order: newest first (chapterNumber desc, group, language); normalize to oldest-first
    chapters.sort(function (a, b) {
      return (b.chapterNumber - a.chapterNumber) || (a._group < b._group ? -1 : a._group > b._group ? 1 : 0) ||
        (a._lang < b._lang ? -1 : a._lang > b._lang ? 1 : 0);
    });
    chapters.reverse();
    for (var i = 0; i < chapters.length; i++) {
      chapters[i].sortOrder = i;
      delete chapters[i]._group;
      delete chapters[i]._lang;
    }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var m = String(chapterKey).match(/^\\/read\\/([^/]+)\\/([^/]+)/);
    if (!m) { throw new Error('bad chapter key: ' + chapterKey); }
    var body = JSON.stringify({ bookid: m[1], chapterid: m[2], first: 'true' });
    var text = await $.http.post(BASE + '/callpage', body, {
      'X-Requested-With': 'XMLHttpRequest',
      'Content-Type': 'application/json',
      'Referer': R_abs(chapterKey),
    });
    var dto = JSON.parse(text);
    var doc = $.html.parse('<html><body>' + (dto.src || '') + '</body></html>');
    var imgs = R_sel(doc, 'img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var src = imgSrc(imgs[i]);
      var pm = src.split('?')[0].match(/\\/images\\/gallery\\/[^/]+\\/[^/]+\\/(\\d+)$/);
      if (!pm) { continue; }
      pages.push({ index: pages.length, url: src, _n: parseInt(pm[1], 10) });
    }
    pages.sort(function (a, b) { return a._n - b._n; });
    for (var j = 0; j < pages.length; j++) {
      pages[j].index = j;
      delete pages[j]._n;
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
