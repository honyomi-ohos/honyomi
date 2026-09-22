// MultiChan theme engine (ru: achan-style imageboard sites: henchan, mangachan, yaoichan)
// HTML scraping; henchan has a related-chapters model handled specially.
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    latestPath: 'manga/new',
    henchan: false,
    hqThumb: false,
  };
  const lm = kt.match(/latestUpdatesRequest\(page: Int\): Request = GET\("\$baseUrl\/([^"?]*)/);
  if (lm) config.latestPath = lm[1];
  config.henchan = /похожий на|\/related\//.test(kt);
  config.hqThumb = /getHQThumbnail/.test(kt);
  if (/rateLimit\(/.test(kt)) warnings.push('rateLimit approximated (no throttling in plugin)');
  if (config.henchan) warnings.push('henchan related-chapter model approximated (first branch, no default-branch API)');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: multichan)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var CH_NUM_RE = /(глава\\s|часть\\s)([0-9]+\\.?[0-9]*)/i;

function hq(u) {
  if (!CFG.hqThumb || !u) { return u; }
  return String(u).replace(/manganew_thumbs\\w*?(?=\\/)/gi, 'showfull_retina/manga');
}

function parseCards(doc) {
  var items = R_sel(doc, 'div.content_row');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = R_selFirst(el, 'h2 > a');
    if (!link) { continue; }
    var href = link.absUrl('href') || link.attr('href');
    if (!href) { continue; }
    var img = R_selFirst(el, 'img');
    out.push({
      key: R_path(href),
      title: el.attr('title') || link.text(),
      coverUrl: hq(img ? R_img(img) : '')
    });
  }
  return out;
}

async function listManga(page, query) {
  var offset = 20 * (page - 1);
  var url;
  if (query) {
    url = BASE + '/?do=search&subaction=search&story=' + encodeURIComponent(query) + '&search_start=' + page;
  } else {
    url = BASE + '/' + CFG.latestPath + '?offset=' + offset;
  }
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var out = parseCards(doc);
  var hasNext = !!R_selFirst(doc, query ? 'a:contains(Далее)' : 'a:contains(Вперед)');
  return { mangas: out, hasNextPage: hasNext };
}

function infoRow(doc, label) {
  var els = R_sel(doc, '#info_wrap tr, #info_wrap > div');
  for (var i = 0; i < els.length; i++) {
    if (els[i].text().indexOf(label) >= 0) { return els[i]; }
  }
  return null;
}

function rowLinksText(row) {
  if (!row) { return ''; }
  var els = R_sel(row, 'a');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var t = els[i].text();
    if (t) { out.push(t); }
  }
  return out.join(', ');
}

function chapterNum(name) {
  var m = String(name || '').match(CH_NUM_RE);
  return m ? parseFloat(m[2]) : -1;
}

async function chaptersBase(mangaKey) {
  var text = await $.http.get(R_abs(mangaKey));
  var doc = $.html.parse(text);
  var rows = R_sel(doc, 'table.table_cha tr');
  var out = [];
  for (var i = 2; i < rows.length; i++) {
    var a = R_selFirst(rows[i], 'a');
    if (!a) { continue; }
    var href = a.absUrl('href') || a.attr('href');
    if (!href) { continue; }
    var dEl = R_selFirst(rows[i], 'div.date');
    out.push({
      key: R_path(href),
      name: a.text(),
      chapterNumber: chapterNum(a.text()),
      dateUpload: dEl ? R_date(dEl.text()) : 0,
      pages: 0,
      sortOrder: 0
    });
  }
  out.reverse();
  for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
  return out;
}

async function chaptersHenchan(mangaKey) {
  var out = [];
  var relatedUrl = R_abs(String(mangaKey).replace('/manga/', '/related/'));
  var text = '';
  try { text = await $.http.get(relatedUrl); } catch (e0) { text = ''; }
  var doc = text ? $.html.parse(text) : null;

  if (doc) {
    // single related chapter
    var relEl = R_selFirst(doc, '#right > div:nth-child(4)');
    var relText = relEl ? relEl.text() : '';
    if (relText.indexOf(' похожий на ') >= 0) {
      var oneLink = R_selFirst(doc, '#left > div > a');
      out.push({
        key: R_path(oneLink ? (oneLink.absUrl('href') || oneLink.attr('href')) : mangaKey),
        name: relText.split(' похожий на ')[1].replace(/\\"/g, '"').replace(/\\'/g, "'"),
        chapterNumber: 1,
        dateUpload: 0,
        pages: 0,
        sortOrder: 0
      });
      return out;
    }

    // related chapter list (may paginate)
    var guard = 0;
    while (doc && guard < 20) {
      guard++;
      var els = R_sel(doc, '.related');
      for (var i = 0; i < els.length; i++) {
        var a = R_selFirst(els[i], 'h2 a');
        if (!a) { continue; }
        var href = a.absUrl('href') || a.attr('href');
        if (!href) { continue; }
        var nm = a.attr('title') || a.text();
        out.push({
          key: R_path(href),
          name: nm,
          chapterNumber: chapterNum(nm),
          dateUpload: 0,
          pages: 0,
          sortOrder: 0
        });
      }
      var next = R_selFirst(doc, 'div#pagination_related a:contains(Вперед)');
      if (!next) { break; }
      var nurl = next.absUrl('href');
      if (!nurl) { break; }
      try {
        var ntext = await $.http.get(nurl);
        doc = $.html.parse(ntext);
      } catch (e1) { break; }
    }
  }

  if (out.length === 0) {
    // one-shot: chapter is the manga page itself
    var mtext = '';
    try { mtext = await $.http.get(R_abs(mangaKey)); } catch (e2) { mtext = ''; }
    if (mtext) {
      var mdoc = $.html.parse(mtext);
      var tEl = R_selFirst(mdoc, 'a.title_top_a');
      var dEl2 = R_selFirst(mdoc, 'div.row4_right b');
      out.push({
        key: R_path(mangaKey),
        name: tEl ? tEl.text() : 'Chapter',
        chapterNumber: 1,
        dateUpload: dEl2 ? R_date(dEl2.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
  }
  out.reverse();
  for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    var offset = 20 * (page - 1);
    var text = await $.http.get(BASE + '/mostfavorites?offset=' + offset);
    var doc = $.html.parse(text);
    var out = parseCards(doc);
    var hasNext = !!R_selFirst(doc, 'a:contains(Вперед)');
    return { mangas: out, hasNextPage: hasNext };
  },

  getSearchManga: async function (page, query) {
    return listManga(page, query);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var titleEl = R_selFirst(doc, 'title');
    var title = titleEl ? titleEl.text().split(' »')[0] : '';
    var authorRow = infoRow(doc, 'Автор');
    var author = '';
    if (authorRow) {
      var aEls = R_sel(authorRow, '.item2');
      var names = [];
      for (var i = 0; i < aEls.length; i++) { names.push(aEls[i].text()); }
      author = names.join(', ');
    }
    var typeRow = infoRow(doc, 'Тип');
    var genres = [];
    if (typeRow) { genres.push(rowLinksText(typeRow)); }
    var sideTags = R_sel(doc, '.sidetags ul a');
    for (var j = 0; j < sideTags.length; j++) {
      if (sideTags[j].text()) { genres.push(sideTags[j].text()); }
    }
    var statusRow = infoRow(doc, 'Загружено');
    var status = '';
    var statusText = statusRow ? statusRow.text() : '';
    if (statusText.indexOf('перевод завершен') >= 0) { status = 'completed'; }
    else if (statusText.indexOf('перевод продолжается') >= 0) { status = 'ongoing'; }
    var descEl = R_selFirst(doc, 'div#description');
    var coverEl = R_selFirst(doc, 'img#cover');
    return {
      key: mangaKey,
      title: title,
      coverUrl: hq(coverEl ? (coverEl.absUrl('src') || coverEl.attr('src')) : ''),
      author: author,
      description: descEl ? descEl.text() : '',
      genre: genres.filter(Boolean).join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    if (CFG.henchan) { return chaptersHenchan(mangaKey); }
    return chaptersBase(mangaKey);
  },

  getPageList: async function (chapterKey) {
    var url = R_abs(chapterKey);
    if (CFG.henchan && String(chapterKey).indexOf('/manga/') >= 0) {
      url = R_abs(String(chapterKey).replace('/manga/', '/online/'));
    }
    var html = await $.http.get(url);
    var idx = html.indexOf('fullimg');
    if (idx < 0) { return []; }
    var open = html.indexOf('[', idx);
    var close = html.indexOf(']', open);
    if (open < 0 || close < 0) { return []; }
    var inner = html.substring(open + 1, close).replace(/"/g, '').replace(/'/g, '');
    var parts = inner.split(',');
    var pages = [];
    for (var i = 0; i < parts.length; i++) {
      var u = parts[i].trim();
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
