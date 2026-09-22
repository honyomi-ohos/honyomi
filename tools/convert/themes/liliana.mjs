// Liliana theme engine (+ dokiraw custom variant)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  usesPostSearch: false,
  dokirawMode: false,
  popularUrl: '/ranking/week/{page}',
  popularSelector: 'div#main div.grid > div',
  popularLinkSelector: '.text-center a',
  nextPageSelector: '.blog-pager > span.pagecurrent + span',
  titleSelector: '.a2 header h1',
  descSelector: 'div#syn-target',
  thumbSelector: '.a1 > figure img',
  genreSelector: ".a2 div > a[rel='tag'].label",
  chapterSelector: 'ul > li.chapter',
  dokirawOngoing: '進行中',
  dokirawCompleted: '完結',
};

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  config.usesPostSearch = /override\s+val\s+usesPostSearch\s*(?::\s*Boolean)?\s*=\s*true/.test(kt);

  if (/div\[class\*=manga-item_item\]/.test(kt)) {
    config.dokirawMode = true;
    const m1 = kt.match(/div:contains\(([^)]+)\)[\s\S]{0,120}?SManga\.ONGOING/);
    const m2 = kt.match(/div:contains\(([^)]+)\)[\s\S]{0,120}?SManga\.COMPLETED/);
    if (m1) { config.dokirawOngoing = m1[1].replace(/^['"]|['"]$/g, ''); }
    if (m2) { config.dokirawCompleted = m2[1].replace(/^['"]|['"]$/g, ''); }
    warnings.push('dokiraw uses fully custom parsing; Japanese relative dates approximated');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: liliana)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_status/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- liliana engine ----------------

function imgAttr(el) {
  if (!el) { return ''; }
  var names = ['data-lazy-src', 'data-src'];
  for (var i = 0; i < names.length; i++) {
    var v = el.attr(names[i]);
    if (v) { return R_abs(v); }
  }
  return el.attr('src') ? R_abs(el.attr('src')) : '';
}

function parseCards(doc) {
  var items = R_sel(doc, CFG.popularSelector);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = R_selFirst(el, CFG.popularLinkSelector);
    if (!link) { continue; }
    var href = link.attr('abs:href') || link.attr('href');
    if (!href) { continue; }
    out.push({
      key: R_path(href),
      title: link.text(),
      coverUrl: imgAttr(R_selFirst(el, 'img'))
    });
  }
  return out;
}

function parseStatusText(v) {
  var low = String(v || '').toLowerCase();
  if (!low) { return ''; }
  if (low === 'ongoing' || low.indexOf('đang tiến hành') >= 0 || low.indexOf('進行中') >= 0) { return 'ongoing'; }
  if (low === 'completed' || low.indexOf('hoàn thành') >= 0 || low.indexOf('完结') >= 0) { return 'completed'; }
  if (low === 'on-hold' || low.indexOf('tạm ngừng') >= 0 || low.indexOf('保留') >= 0) { return 'hiatus'; }
  if (low === 'canceled' || low.indexOf('đã hủy') >= 0 || low.indexOf('キャンセル') >= 0) { return 'cancelled'; }
  return '';
}

// ------- dokiraw (ja) custom parsing -------
function dokirawCards(doc) {
  var items = R_sel(doc, 'div[class*=manga-item_item]');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var anchor = R_selFirst(el, 'a[href*="/manga/"]');
    if (!anchor) { continue; }
    var href = anchor.attr('abs:href') || anchor.attr('href');
    if (!href) { continue; }
    var h3 = R_selFirst(el, 'h3');
    var img = R_selFirst(el, 'img');
    var thumb = '';
    if (img) {
      thumb = img.attr('data-original') || img.attr('src') || '';
      thumb = R_abs(thumb);
    }
    out.push({ key: R_path(href), title: h3 ? h3.text() : '', coverUrl: thumb });
  }
  return out;
}

function dokirawParseDate(s) {
  var v = String(s || '');
  if (!v) { return 0; }
  if (v.indexOf('昨日') >= 0) { return Date.now() - 86400000; }
  var m = v.match(/(\\d+)/);
  if (!m) { return R_date(v); }
  var amount = parseInt(m[1], 10);
  var now = Date.now();
  if (v.indexOf('年') >= 0 && v.indexOf('月') < 0) { return now - amount * 31536000000; }
  if (v.indexOf('月') >= 0) { return now - amount * 2592000000; }
  if (v.indexOf('週') >= 0) { return now - amount * 604800000; }
  if (v.indexOf('日') >= 0) { return now - amount * 86400000; }
  if (v.indexOf('時間') >= 0) { return now - amount * 3600000; }
  if (v.indexOf('分') >= 0) { return now - amount * 60000; }
  if (v.indexOf('秒') >= 0) { return now - amount * 1000; }
  return 0;
}

function dokirawChapters(doc) {
  // equivalent of "a:has(div[class*=manga-detail_chapter])" without :has
  var anchors = R_sel(doc, 'a');
  var out = [];
  for (var i = 0; i < anchors.length; i++) {
    var a = anchors[i];
    var container = R_selFirst(a, 'div[class*=manga-detail_chapter]');
    if (!container) { continue; }
    var spans = R_sel(container, 'span');
    var name = spans.length > 0 ? spans[0].text() : '';
    var dateText = spans.length > 1 ? spans[1].text() : '';
    var href = a.attr('abs:href') || a.attr('href');
    if (!href) { continue; }
    out.push({
      key: R_path(href),
      name: name,
      chapterNumber: -1,
      dateUpload: dokirawParseDate(dateText),
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    if (CFG.dokirawMode) {
      var hotText = await $.http.get(BASE + '/hot?page=' + page);
      var hotDoc = $.html.parse(hotText);
      var hotCards = dokirawCards(hotDoc);
      return { mangas: hotCards, hasNextPage: hotCards.length === 36 };
    }
    var text = await $.http.get(BASE + CFG.popularUrl.replace('{page}', String(page)));
    var doc = $.html.parse(text);
    return { mangas: parseCards(doc), hasNextPage: !!R_selFirst(doc, CFG.nextPageSelector) };
  },

  getSearchManga: async function (page, query) {
    if (!query) { return module.exports.getPopularManga(page); }
    if (CFG.dokirawMode) {
      var st = await $.http.get(BASE + '/search/manga?keyword=' + encodeURIComponent(query) + '&page=' + page);
      var sd = $.html.parse(st);
      var cards = dokirawCards(sd);
      return { mangas: cards, hasNextPage: cards.length === 20 };
    }
    if (CFG.usesPostSearch) {
      var body = R_form([['search', query]]);
      var text = await $.http.post(BASE + '/ajax/search', body, R_xhr({ Accept: 'application/json, text/javascript, */*; q=0.01', Origin: BASE }));
      var data;
      try { data = JSON.parse(text); } catch (e) { data = null; }
      var mangas = [];
      if (data && Array.isArray(data.list)) {
        for (var i = 0; i < data.list.length; i++) {
          var it = data.list[i];
          mangas.push({
            key: R_path(it.url),
            title: it.name || '',
            coverUrl: it.cover ? R_abs(it.cover) : ''
          });
        }
      }
      return { mangas: mangas, hasNextPage: false };
    }
    var gText = await $.http.get(BASE + '/search/' + page + '/?keyword=' + encodeURIComponent(query));
    var gDoc = $.html.parse(gText);
    return { mangas: parseCards(gDoc), hasNextPage: !!R_selFirst(gDoc, CFG.nextPageSelector) };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    if (CFG.dokirawMode) {
      var dTitle = '';
      var dTitleEl = R_selFirst(doc, 'div[class*=manga-detail_boxInfo] h1');
      if (dTitleEl) { dTitle = dTitleEl.text(); }
      var dDesc = '';
      var ps = R_sel(doc, 'div.work-break p');
      if (ps.length > 0) { dDesc = ps[ps.length - 1].text(); }
      var dStatus = '';
      var divs = R_sel(doc, 'div');
      var found = false;
      for (var di = 0; di < divs.length && !found; di++) {
        if (divs[di].text().indexOf(CFG.dokirawOngoing) >= 0) { dStatus = 'ongoing'; found = true; }
      }
      for (var dc = 0; dc < divs.length && !found; dc++) {
        if (divs[dc].text().indexOf(CFG.dokirawCompleted) >= 0) { dStatus = 'completed'; found = true; }
      }
      var coverEl = R_selFirst(doc, 'img[src*=cover]');
      return {
        key: mangaKey,
        title: dTitle,
        coverUrl: coverEl ? R_abs(coverEl.attr('src')) : '',
        author: '',
        description: dDesc,
        genre: '',
        status: dStatus
      };
    }
    var title = '';
    var titleEl = R_selFirst(doc, CFG.titleSelector);
    if (titleEl) { title = titleEl.text(); }
    var desc = '';
    var descEl = R_selFirst(doc, CFG.descSelector);
    if (descEl) { desc = descEl.text(); }
    var genres = [];
    var genreEls = R_sel(doc, CFG.genreSelector);
    for (var g = 0; g < genreEls.length; g++) { genres.push(genreEls[g].text()); }
    var author = '';
    var userIcons = R_sel(doc, 'div.y6x11p i.fas.fa-user');
    if (userIcons.length > 0) {
      var aSib = userIcons[0].nextElementSibling;
      var aText = aSib ? aSib.text() : '';
      if (aText && aText.toLowerCase() !== 'updating') { author = aText; }
    }
    var status = '';
    var rssIcons = R_sel(doc, 'div.y6x11p i.fas.fa-rss');
    if (rssIcons.length > 0) {
      var rSib = rssIcons[0].nextElementSibling;
      status = parseStatusText(rSib ? rSib.text() : '');
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: imgAttr(R_selFirst(doc, CFG.thumbSelector)),
      author: author,
      description: desc,
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var out;
    if (CFG.dokirawMode) {
      out = dokirawChapters(doc);
    } else {
      out = [];
      var els = R_sel(doc, CFG.chapterSelector);
      for (var i = 0; i < els.length; i++) {
        var a = R_selFirst(els[i], 'a');
        if (!a) { continue; }
        var href = a.attr('abs:href') || a.attr('href');
        if (!href) { continue; }
        var time = R_selFirst(els[i], 'time[datetime]');
        var ts = time ? parseInt(time.attr('datetime'), 10) : 0;
        out.push({
          key: R_path(href),
          name: a.text(),
          chapterNumber: -1,
          dateUpload: ts ? ts * 1000 : 0,
          pages: 0,
          sortOrder: 0
        });
      }
    }
    // newest first on site; normalize to oldest-first
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = out.length - 1 - j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var chapterUrl = R_abs(chapterKey);
    var text = await $.http.get(chapterUrl);
    var doc = $.html.parse(text);
    if (CFG.dokirawMode) {
      var imgs = R_sel(doc, 'div.page-chapter img');
      var dPages = [];
      for (var di = 0; di < imgs.length; di++) {
        var im = imgs[di];
        var u = im.attr('data-cdn') || im.attr('data-original') || im.attr('src') || '';
        if (u) { dPages.push({ index: dPages.length, url: R_abs(u) }); }
      }
      return dPages;
    }
    var scripts = R_sel(doc, 'script');
    var chapterId = '';
    for (var i = 0; i < scripts.length; i++) {
      var c = scripts[i].html() || scripts[i].text() || '';
      if (c.indexOf('const CHAPTER_ID') >= 0) {
        var idx = c.indexOf('const CHAPTER_ID = ');
        if (idx >= 0) {
          chapterId = c.substring(idx + 'const CHAPTER_ID = '.length).split(';')[0].trim();
        }
        break;
      }
    }
    if (!chapterId) { return []; }
    var ajaxText = await $.http.get(BASE + '/ajax/image/list/chap/' + chapterId,
      R_xhr({ Accept: 'application/json, text/javascript, */*; q=0.01', Referer: chapterUrl }));
    var data;
    try { data = JSON.parse(ajaxText); } catch (e) { return []; }
    if (!data || !data.status || !data.html) { return []; }
    var frag = $.html.parse(data.html);
    var separators = R_sel(frag, 'div.separator');
    var indexed = R_selFirst(frag, 'div.separator[data-index]') !== null;
    var pages = [];
    for (var j = 0; j < separators.length; j++) {
      var a = R_selFirst(separators[j], 'a');
      if (!a) { continue; }
      var url = a.attr('abs:href') || a.attr('href');
      if (!url) { continue; }
      var lower = url.toLowerCase().split('?')[0].split('#')[0];
      if (lower.endsWith('.svg') || url.toLowerCase().indexOf('loading_comments') >= 0) { continue; }
      var index = indexed ? parseInt(separators[j].attr('data-index'), 10) : pages.length;
      if (isNaN(index)) { index = pages.length; }
      pages.push({ index: index, url: R_abs(url) });
    }
    pages.sort(function (a2, b2) { return a2.index - b2.index; });
    for (var k = 0; k < pages.length; k++) { pages[k].index = k; }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
