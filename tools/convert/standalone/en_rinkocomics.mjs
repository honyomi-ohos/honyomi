// en/rinkocomics — bespoke WP scraper (pinned popular, ajax chapter pagination)
export const runtime = 'wp';

export function extract(ctx) {
  return { ok: true, config: {}, warnings: ['locked/paid chapters are listed with a lock marker and cannot be read'] };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function imgFrom(el) {
  if (!el) { return ''; }
  var v = el.attr('data-src') || el.attr('data-lazy-src') || el.attr('src') || '';
  return v ? R_abs(v) : '';
}

function parseComicsPage(text) {
  var doc = $.html.parse(text);
  var items = R_sel(doc, 'article.ac-card');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var card = items[i];
    var a = R_selFirst(card, '.ac-title a');
    if (!a) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    out.push({
      key: R_path(href),
      title: a.text().trim(),
      coverUrl: imgFrom(R_selFirst(card, '.ac-thumb img'))
    });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, '.ac-pagination a.next') };
}

function parseChapterElements(els) {
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var permalink = String(el.attr('data-permalink') || '').trim();
    var a = R_selFirst(el, 'a');
    var href = permalink || (a ? a.absUrl('href') : '') || '';
    if (!href) { continue; }
    var nameEl = R_selFirst(el, '.chapter-number');
    var name = nameEl ? nameEl.text() : String(el.attr('data-title') || '');
    var dateEl = R_selFirst(el, '.chapter-date');
    var reason = String(el.attr('data-reason') || '').toLowerCase();
    var locked = (reason && reason !== 'free') ||
      String(el.attr('class') || '').indexOf('locked-chapter') >= 0 ||
      (a && (!a.attr('href') || a.attr('href') === '#')) ||
      !!R_selFirst(el, '.chapter_price');
    var key = R_path(href);
    if (locked) {
      name = '🔒 ' + name;
      key = key + '#lock';
    }
    out.push({
      key: key,
      name: String(name || '').trim(),
      chapterNumber: -1,
      dateUpload: dateEl ? R_date(dateEl.text()) : 0,
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

module.exports = {
  getPopularManga: async function () {
    var doc = $.html.parse(await $.http.get(BASE + '/', HDRS));
    var cards = R_sel(doc, '.comics-flex-pinned a.pinned-comic-card');
    var out = [];
    for (var i = 0; i < cards.length; i++) {
      var card = cards[i];
      var href = String(card.attr('href') || '').trim();
      if (!href) { continue; }
      var tEl = R_selFirst(card, '.pinned-comic-title');
      if (!tEl) { continue; }
      out.push({
        key: R_path(R_abs(href)),
        title: tEl.text().trim(),
        coverUrl: imgFrom(R_selFirst(card, '.comic-thumbnail img'))
      });
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var u = page > 1 ? BASE + '/comic/page/' + page + '/?post_type=comic' : BASE + '/comic/?post_type=comic';
    if (query && query.trim()) { u += '&s=' + encodeURIComponent(query.trim()); }
    return parseComicsPage(await $.http.get(u, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var title = '';
    var t1 = R_selFirst(doc, '.comic-info-upper h1');
    var t2 = R_selFirst(doc, 'h1');
    title = t1 ? t1.text().trim() : (t2 ? t2.text().trim() : '');
    var cover = '';
    var og = R_selFirst(doc, 'meta[property="og:image"]');
    if (og) { cover = R_abs(og.attr('content') || ''); }
    var authors = [];
    var spans = R_sel(doc, '.comic-graph > span');
    for (var i = 0; i < spans.length; i++) {
      var t = spans[i].text().trim();
      if (!t || t === '•') { continue; }
      if (authors.indexOf(t) < 0) { authors.push(t); }
    }
    var statusEl = R_selFirst(doc, '.comic-status span:last-child');
    var sv = statusEl ? statusEl.text().trim().toLowerCase() : '';
    var status = '';
    if (sv === 'ongoing') { status = 'ongoing'; }
    else if (sv === 'completed') { status = 'completed'; }
    else if (sv === 'cancelled' || sv === 'canceled') { status = 'cancelled'; }
    var genres = [];
    var gels = R_sel(doc, '.comic-genres .genres .genre');
    for (var j = 0; j < gels.length; j++) { genres.push(gels[j].text()); }
    var descEl = R_selFirst(doc, '.comic-synopsis');
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: authors[0] || '',
      artist: authors[1] || '',
      description: descEl ? String(descEl.text() || '').trim() : '',
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var chapters = [];
    var seen = {};
    function addAll(items) {
      for (var i = 0; i < items.length; i++) {
        if (!seen[items[i].key]) {
          seen[items[i].key] = true;
          chapters.push(items[i]);
        }
      }
    }
    addAll(parseChapterElements(R_sel(doc, 'li.chapter')));

    var btn = R_selFirst(doc, '#loadMoreChaptersBtn');
    var comicId = btn ? String(btn.attr('data-comic-id') || '') : '';
    var nonce = '';
    var nm = /comicworld_ajax\\s*=\\s*\\{[^}]*"nonce"\\s*:\\s*"([^"]+)"/.exec(text);
    if (nm) { nonce = nm[1]; }
    var offset = btn ? (parseInt(btn.attr('data-offset') || '0', 10) || 0) : 0;
    if (offset <= 0) { offset = chapters.length; }
    else if (chapters.length > 0 && offset > chapters.length) { offset = chapters.length; }

    if (comicId && nonce) {
      var guard = 0;
      while (guard < 200) {
        guard++;
        var items = [];
        try {
          var body = R_form([['action', 'load_more_chapters'], ['nonce', nonce], ['comic_id', comicId], ['offset', String(offset)]]);
          var ajaxText = await $.http.post(BASE + '/wp-admin/admin-ajax.php', body, R_xhr({ Referer: BASE + '/' }));
          var data = $.json.parse(ajaxText);
          if (!data || !data.success || !data.data || !data.data.html) { break; }
          var frag = $.html.parse(String(data.data.html));
          items = parseChapterElements(R_sel(frag, 'li.chapter'));
        } catch (e) { break; }
        if (items.length === 0) { break; }
        addAll(items);
        offset += 10;
      }
    }
    chapters.reverse();
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    if (String(chapterKey).indexOf('#lock') >= 0) { return []; }
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var imgs = R_sel(doc, 'img.chapter-image');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var img = imgs[i];
      var u = R_abs(img.attr('data-src') || img.attr('src') || '');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
