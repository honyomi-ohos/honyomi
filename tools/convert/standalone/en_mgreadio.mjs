// en/mgreadio (mgread.io) — WordPress manga site with initmanga/initlise REST endpoints
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['type/status/rating/genre filters not ported; text search only', 'related-mangas section not ported'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};

function isAnimeEntry(m) {
  var t = (m.title || '').toLowerCase();
  return t.indexOf('anime -') === 0 || t.indexOf('anime \\u2014') === 0 || (m.key + '').indexOf('/anime-') >= 0;
}

function stripTags(s) {
  return String(s || '').replace(/<[^>]*>/g, '');
}

function imgUrl(el) {
  if (!el) { return ''; }
  var v = el.absUrl('data-src') || el.absUrl('data-lazy-src') || el.absUrl('src');
  return v || '';
}

function parseStatus(s) {
  var v = String(s || '').toLowerCase().trim();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  if (v === 'season end' || v === 'source hiatus' || v === 'caught up') { return 'on hiatus'; }
  if (v === 'dropped') { return 'cancelled'; }
  return '';
}

function parseDate(s) {
  var m = /(\\d{4})-(\\d{2})-(\\d{2}) (\\d{2}):(\\d{2}):(\\d{2})/.exec(String(s || '').trim());
  if (!m) { return 0; }
  return new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10), parseInt(m[4], 10), parseInt(m[5], 10), parseInt(m[6], 10)).getTime();
}

function gridMangas(doc) {
  var els = R_sel(doc, '.manga-item-grid, .manga-item-details');
  var out = [];
  var seen = {};
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var t = R_selFirst(el, "h2 a[href*='/manga/']") || R_selFirst(el, "a[href*='/manga/']:not([href*='/chapter-'])");
    if (!t) { continue; }
    var href = t.absUrl('href');
    if (!href) { continue; }
    var path;
    try { path = new URL(href).pathname; } catch (e) { continue; }
    if (seen[path]) { continue; }
    seen[path] = true;
    out.push({ key: path, title: t.text(), coverUrl: imgUrl(R_selFirst(el, 'img')) });
  }
  var mangas = [];
  for (var f = 0; f < out.length; f++) { if (!isAnimeEntry(out[f])) { mangas.push(out[f]); } }
  return mangas;
}

function hasNext(doc) {
  return !!R_selFirst(doc, "li:not(.uk-disabled) > a[aria-label='Next page']");
}

module.exports = {
  getPopularManga: async function (page) {
    var u = page <= 1 ? BASE + '/manga-ranking/' : BASE + '/manga-ranking/page/' + page + '/';
    var doc = $.html.parse(await $.http.get(u, {}));
    return { mangas: gridMangas(doc), hasNextPage: hasNext(doc) };
  },

  getSearchManga: async function (page, query) {
    var q = (query || '').trim();
    if (q) {
      var arr = JSON.parse(await $.http.get(BASE + '/wp-json/initlise/v1/search?term=' + encodeURIComponent(q) + '&page=' + page, {}));
      var out = [];
      for (var i = 0; i < arr.length; i++) {
        var d = arr[i];
        var cleanUrl = (d.url || '').trim();
        if (!cleanUrl) { continue; }
        var path;
        try { path = new URL(cleanUrl, BASE).pathname; } catch (e) { continue; }
        var m = { key: path, title: stripTags(d.title), coverUrl: d.thumb || '' };
        if (!isAnimeEntry(m)) { out.push(m); }
      }
      return { mangas: out, hasNextPage: false };
    }
    var u = BASE + '/advanced-filter/';
    if (page > 1) { u = BASE + '/advanced-filter/page/' + page + '/'; }
    var doc = $.html.parse(await $.http.get(u, {}));
    return { mangas: gridMangas(doc), hasNextPage: hasNext(doc) };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), {});
    var doc = $.html.parse(text);
    var title = '';
    var tEl = R_selFirst(doc, '#manga-title');
    if (tEl) { title = tEl.text(); }
    if (!title) {
      var og = R_selFirst(doc, 'meta[property=og:title]');
      if (og) { title = (og.attr('content') || '').split(' [Ch.')[0].trim(); }
    }
    var coverEl = R_selFirst(doc, '.story-cover img');
    var cover = coverEl ? imgUrl(coverEl) : '';
    if (!cover) {
      var ogi = R_selFirst(doc, 'meta[property=og:image]');
      cover = ogi ? (ogi.attr('content') || '') : '';
    }
    var descText = '';
    var descEl = R_selFirst(doc, '#manga-description');
    if (descEl) { descText = (descEl.html() || '').trim(); }
    if (!descText) {
      var md = R_selFirst(doc, 'meta[name=description]');
      descText = md ? (md.attr('content') || '').trim() : '';
    }
    var genres = [];
    var gas = R_sel(doc, "#genre-tags a[href*='/genre/']");
    for (var g = 0; g < gas.length; g++) { genres.push(gas[g].text()); }
    var status = parseStatus(R_selFirst(doc, '#manga-status') ? R_selFirst(doc, '#manga-status').text() : '');
    var meta = [];
    var metaRow = R_selFirst(doc, '#manga-title + div');
    if (metaRow) {
      var before = (metaRow.html() || '').split('Chapters')[0];
      var count = stripTags(before).trim();
      if (count) { meta.push('Chapters: ' + count); }
      var viewsEl = R_selFirst(metaRow, '.init-plugin-suite-view-count-number');
      if (viewsEl && viewsEl.text()) { meta.push('Views: ' + viewsEl.text()); }
    }
    var altEl = R_selFirst(doc, '#comic-othername');
    if (altEl && altEl.text()) { meta.push('Alternative title: ' + altEl.text()); }
    var revEl = R_selFirst(doc, '.init-review-info');
    if (revEl && revEl.text()) { meta.push('Rating: ' + revEl.text()); }
    var luEl = R_selFirst(doc, '#last-updated');
    if (luEl && luEl.text()) { meta.push('Last updated: ' + luEl.text()); }
    var desc = descText;
    if (meta.length) { desc = (desc ? desc + '\\n\\n' : '') + meta.join('\\n'); }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: '',
      description: desc,
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), {});
    var doc = $.html.parse(text);
    var mangaId = '';
    var idEl = R_selFirst(doc, '#manga-title[data-id]');
    if (idEl && idEl.attr('data-id')) { mangaId = idEl.attr('data-id'); }
    if (!mangaId) {
      var csEl = R_selFirst(doc, '#chapter-search-input[data-manga-id]');
      if (csEl) { mangaId = csEl.attr('data-manga-id') || ''; }
    }
    if (!mangaId) { return []; }
    var cleanPath = mangaKey.replace(/\\/chapter\\//, '').replace(/\\/+$/, '');
    var all = [];
    var pageNum = 1;
    var totalPages = 1;
    while (pageNum <= totalPages) {
      var dto = JSON.parse(await $.http.get(BASE + '/wp-json/initmanga/v1/chapters?manga_id=' + mangaId + '&paged=' + pageNum + '&per_page=50', {}));
      var items = dto.items || [];
      for (var i = 0; i < items.length; i++) { all.push(items[i]); }
      totalPages = dto.total_pages || 1;
      pageNum++;
    }
    var out = [];
    for (var k = 0; k < all.length; k++) {
      var ch = all[k];
      var num = ch.number;
      var chName = (num % 1 === 0) ? String(parseInt(num, 10)) : String(num);
      var nm = ch.title ? 'Chapter ' + chName + ' - ' + ch.title : 'Chapter ' + chName;
      out.push({
        key: cleanPath + '/' + ch.slug + '/',
        name: nm,
        chapterNumber: num,
        dateUpload: parseDate(ch.created_at),
        pages: 0,
        sortOrder: 0
      });
    }
    out.sort(function (a, b) { return a.chapterNumber - b.chapterNumber; });
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), {}));
    var els = R_sel(doc, '#chapter-content img');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var img = els[i];
      var src = img.absUrl('data-original-src') || img.absUrl('src');
      if (src) { out.push({ index: out.length, url: src }); }
    }
    return out;
  },

  imageHeaders: function () {
    return {};
  }
};
`;
}
