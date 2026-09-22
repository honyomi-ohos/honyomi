// id/ryukomik — ryukomik.web.id aggregator (api list + web details, bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['filters not supported; multi-source text search only'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var API = 'https://api.ryukomik.web.id';
var HDRS = { Referer: BASE + '/' };
function parseDate(dateStr) {
  var v = String(dateStr || '').trim().toLowerCase();
  if (!v) { return 0; }
  var units = { 'detik': 1000, 'menit': 60000, 'jam': 3600000, 'hari': 86400000, 'minggu': 604800000, 'bulan': 2592000000, 'tahun': 31536000000 };
  for (var u in units) {
    if (v.indexOf(u) >= 0) {
      var num = parseInt(v.substring(0, v.indexOf(u)).trim(), 10);
      if (isNaN(num)) { num = 1; }
      return Date.now() - num * units[u];
    }
  }
  var m = v.match(/^(\\d{1,2})\\/(\\d{1,2})\\/(\\d{4})$/);
  if (m) { return Date.UTC(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10)) - 7 * 3600000; }
  return 0;
}
function toManga(item, defaultSource) {
  var s = item.slug || (item['detail_link'] || '').replace(/\\/$/, '').split('/').pop() || (item.link || '').replace(/\\/$/, '').split('/').pop();
  if (!s) { return null; }
  var title = item.title;
  if (!title) { return null; }
  var src = item.source || defaultSource;
  return { key: '/komik/' + src + '/' + s, title: title, coverUrl: item.image || item['cover_url'] || '' };
}
function statusMap(v) {
  v = String(v || '').trim().toLowerCase();
  if (v === 'ongoing' || v === 'berjalan') { return 'ongoing'; }
  if (v === 'completed' || v === 'tamat' || v === 'complete') { return 'completed'; }
  if (v === 'hiatus') { return 'hiatus'; }
  if (v === 'dropped') { return 'cancelled'; }
  return '';
}
async function apiList(page) {
  var text = await H_get(API + '/komiku/list?page=' + page, HDRS);
  var d = JSON.parse(text);
  var out = [];
  for (var i = 0; i < (d.data || []).length; i++) {
    var m = toManga(d.data[i], 'komiku');
    if (m) { out.push(m); }
  }
  var meta = d.meta || {};
  var cur = meta['current_page'] || meta['currentPage'] || 1;
  var tot = meta['total_pages'] || meta['totalPages'] || 1;
  return { mangas: out, hasNextPage: cur < tot };
}
module.exports = {
  getPopularManga: async function (page) { return apiList(page); },

  getSearchManga: async function (page, query) {
    var sources = ['project', 'komiku', 'kiryuu', 'komikid', 'josei'];
    var results = [];
    var seen = {};
    for (var s = 0; s < sources.length; s++) {
      var src = sources[s];
      var u = src === 'project' ? BASE + '/api/project/search?q=' + encodeURIComponent(query) : API + '/' + src + '/search?q=' + encodeURIComponent(query);
      try {
        var text = await H_get(u, HDRS);
        var d = JSON.parse(text);
        for (var i = 0; i < (d.data || []).length; i++) {
          var m = toManga(d.data[i], src);
          if (m && !seen[m.key]) { seen[m.key] = true; results.push(m); }
        }
      } catch (e) { /* source unavailable */ }
    }
    return { mangas: results, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var cover = R_selFirst(doc, 'div.rk-shell img[alt=Poster], div.rk-shell div.flex-shrink-0 img');
    var author = R_selFirst(doc, 'div.rk-shell span[class*="text-white/60"][class*=truncate]');
    var desc = R_selFirst(doc, 'p[class*="leading-relaxed"]');
    var chip = R_selFirst(doc, 'span.rk-chip');
    var genres = [];
    if (chip && chip.text()) { genres.push(chip.text()); }
    var gels = R_sel(doc, "a[href*='/genre/']");
    for (var i = 0; i < gels.length; i++) {
      var g = gels[i].text();
      if (g && genres.indexOf(g) < 0) { genres.push(g); }
    }
    var statusText = '';
    var flex = R_selFirst(doc, 'div.rk-shell div.flex.gap-3');
    if (flex) {
      var spans = R_sel(flex, 'span');
      if (spans.length) { statusText = spans[spans.length - 1].text(); }
    }
    return {
      key: mangaKey,
      title: H_firstText(doc, 'h1'),
      coverUrl: cover ? cover.absUrl('src') : '',
      author: author && author.text() !== '-' ? author.text() : '',
      description: desc ? desc.text() : '',
      genre: genres.join(', '),
      status: statusMap(statusText)
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var els = R_sel(doc, "a[href*='/chapter/']");
    var out = [];
    var seen = {};
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var href = el.absUrl('href');
      if (!href || seen[href]) { continue; }
      seen[href] = true;
      var nameEl = R_selFirst(el, 'span[class*="13px"], span.font-medium');
      var name = nameEl ? nameEl.text() : (R_selFirst(el, 'div > div > span') ? R_selFirst(el, 'div > div > span').text() : el.text());
      var dateEl = R_selFirst(el, 'span[class*="11px"] > span:first-child');
      out.push({
        key: R_path(href),
        name: name,
        chapterNumber: -1,
        dateUpload: dateEl ? parseDate(dateEl.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var html = await H_get(R_abs(chapterKey), HDRS);
    var m = html.match(/\\\\?"images\\\\?"\\s*:\\s*(\\[[^\\]]+\\])/);
    if (!m) { return []; }
    var json = m[1].replace(/\\\\\\"/g, '"').replace(/\\\\\\\\/g, '\\\\');
    var images = JSON.parse(json);
    var pages = [];
    for (var i = 0; i < images.length; i++) {
      var u = images[i];
      if (u.indexOf('http://') !== 0 && u.indexOf('https://') !== 0) {
        u = BASE.replace(/\\/$/, '') + '/' + u.replace(/^\\//, '');
      }
      pages.push({ index: i, url: u });
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
