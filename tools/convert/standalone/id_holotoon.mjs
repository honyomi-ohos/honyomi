// id/holotoon — holotoon.com HTML site with scraper honeypots (bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['filters not supported; browse popular/latest/search only'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
function parseRelativeDate(text) {
  var v = String(text || '').trim().toLowerCase();
  if (!v) { return 0; }
  if (v === 'baru saja' || v === 'just now') { return Date.now(); }
  var m = v.match(/\\d+/);
  if (!m) { return 0; }
  var amount = parseInt(m[0], 10);
  var unit = 0;
  if (v.indexOf('detik') >= 0 || v.indexOf('second') >= 0) { unit = 1000; }
  else if (v.indexOf('menit') >= 0 || v.indexOf('minute') >= 0) { unit = 60000; }
  else if (v.indexOf('jam') >= 0 || v.indexOf('hour') >= 0) { unit = 3600000; }
  else if (v.indexOf('hari') >= 0 || v.indexOf('day') >= 0) { unit = 86400000; }
  else if (v.indexOf('minggu') >= 0 || v.indexOf('week') >= 0) { unit = 604800000; }
  else if (v.indexOf('bulan') >= 0 || v.indexOf('month') >= 0) { unit = 2592000000; }
  else if (v.indexOf('tahun') >= 0 || v.indexOf('year') >= 0) { unit = 31536000000; }
  else { return 0; }
  return Date.now() - amount * unit;
}
async function browse(page, sort, query) {
  var u = BASE + '/browse?sort=' + sort + '&media=comic';
  if (query) { u += '&q=' + encodeURIComponent(query); }
  if (page > 1) { u += '&page=' + page; }
  var doc = await H_doc(u);
  // honeypot protection: only parse the real catalogue grid
  var grids = R_sel(doc, "div.grid:has(a[href^='/comic/'])");
  if (!grids.length) { return { mangas: [], hasNextPage: false }; }
  var container = grids[grids.length - 1];
  var cards = R_sel(container, "a.group[href^='/comic/']");
  var mangas = [];
  var seen = {};
  for (var i = 0; i < cards.length; i++) {
    var card = cards[i];
    var href = card.attr('href');
    var segs = href.split('/').filter(function (s) { return s.length > 0; });
    if (segs[0] !== 'comic' || !segs[1]) { continue; }
    var path = '/' + segs.join('/');
    var title = H_firstText(card, 'h3');
    if (!title || seen[path]) { continue; }
    seen[path] = true;
    mangas.push({ key: path, title: title, coverUrl: R_img(R_selFirst(card, 'img')) });
  }
  var hasNext = false;
  var links = R_sel(doc, "a[href*='page=']");
  for (var j = 0; j < links.length; j++) {
    if (links[j].attr('href').indexOf('page=' + (page + 1)) >= 0) { hasNext = true; break; }
  }
  return { mangas: mangas, hasNextPage: hasNext };
}
async function loadMangaDoc(mangaKey) {
  var path = String(mangaKey);
  if (path.indexOf('/komik/') === 0) { path = path.replace('/komik/', '/comic/'); }
  return H_doc(BASE + path);
}
function findDetailsRoot(doc) {
  // innermost div containing both the h1 title and genre links
  var candidates = R_sel(doc, "div:has(a[href*='genre='])");
  for (var i = candidates.length - 1; i >= 0; i--) {
    if (R_selFirst(candidates[i], 'h1') && R_selFirst(candidates[i], "a[href*='genre=']")) {
      return candidates[i];
    }
  }
  return null;
}
async function parseDetails(doc, path) {
  var titleEl = R_selFirst(doc, 'h1');
  var title = titleEl ? titleEl.text() : '';
  var root = findDetailsRoot(doc);
  var metadata = root ? root.text() : (titleEl ? titleEl.text() : '');
  var descEl = R_selFirst(doc, '#synopsis-wrapper div[data-sr], div[data-sr][class*=synopsis], div.prose, div[class*=description]');
  var description = '';
  if (descEl) {
    var enc = descEl.attr('data-sr');
    if (enc) {
      try { description = $.crypto.base64Decode(enc); } catch (e) { description = ''; }
    }
    if (!description) { description = descEl.text(); }
  }
  var authorM = metadata.match(/Author:\\s*(.*?)\\s+Artist:/i);
  var artistM = metadata.match(/Artist:\\s*(.*?)(?:\\s+Year:|\\s+Views:|\\s+Uploaded by:)/i);
  var genres = [];
  if (root) {
    var gels = R_sel(root, "a[href*='genre=']");
    for (var g = 0; g < gels.length; g++) {
      var t = gels[g].text();
      if (t && genres.indexOf(t) < 0) { genres.push(t); }
    }
  }
  var status = '';
  if (root) {
    var spans = R_sel(root, 'span');
    for (var s = 0; s < spans.length; s++) {
      var v = spans[s].text().toLowerCase();
      if (v === 'ongoing') { status = 'ongoing'; break; }
      if (v === 'completed') { status = 'completed'; break; }
      if (v === 'hiatus') { status = 'hiatus'; break; }
      if (v === 'dropped') { status = 'cancelled'; break; }
    }
  }
  var cover = '';
  var imgs = R_sel(doc, 'img');
  for (var m = 0; m < imgs.length; m++) {
    if (imgs[m].attr('alt').trim().toLowerCase() === title.toLowerCase()) {
      cover = R_img(imgs[m]);
      break;
    }
  }
  return {
    key: path,
    title: title,
    coverUrl: cover,
    author: authorM ? authorM[1].trim() : '',
    description: description,
    genre: genres.join(', '),
    status: status
  };
}
module.exports = {
  getPopularManga: async function (page) { return browse(page, 'popular', ''); },
  getSearchManga: async function (page, query) { return browse(page, 'latest', query); },

  getMangaDetail: async function (mangaKey) {
    var path = String(mangaKey);
    var doc = await loadMangaDoc(path);
    return parseDetails(doc, path);
  },

  getChapterList: async function (mangaKey) {
    var doc = await loadMangaDoc(mangaKey);
    var els = R_sel(doc, "a[href^='/read/'][data-chapter]");
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var path = el.attr('href').split('#')[0].split('?')[0];
      if (!path) { continue; }
      var raw = el.attr('data-chapter');
      var numM = raw.match(/\\d+(?:\\.\\d+)?/);
      var num = numM ? parseFloat(numM[0]) : -1;
      var label = H_firstText(el, 'span.font-semibold');
      var subtitle = H_firstText(el, 'span.truncate').replace(/^—/, '').trim();
      var name;
      if (label && subtitle) { name = label + ' - ' + subtitle; }
      else if (label) { name = label; }
      else if (subtitle) { name = subtitle; }
      else if (num >= 0) { name = 'Chapter ' + String(num).replace(/\\.0$/, ''); }
      else { name = raw || 'Chapter'; }
      var dateEl = R_selFirst(el, 'span.text-right, span[class*=tabular-nums]:last-child');
      out.push({
        key: path,
        name: name,
        chapterNumber: num,
        dateUpload: parseRelativeDate(dateEl ? dateEl.text() : ''),
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var path = String(chapterKey);
    if (path.indexOf('/komik/') === 0) {
      var parts = path.replace(/^\\/+/, '').split('/');
      if (parts.length >= 3) { path = '/read/' + parts[1] + '/' + parts.slice(2).join('/'); }
    }
    var doc = await H_doc(BASE + path);
    var images = R_sel(doc, '#reader-pages img');
    if (!images.length) {
      images = R_sel(doc, "main img[src*='/image/comic/'], main img[data-src*='/image/comic/']");
    }
    var pages = [];
    var seen = {};
    for (var i = 0; i < images.length; i++) {
      var img = images[i];
      var u = img.absUrl('src') || img.absUrl('data-src');
      if (!u || u.indexOf('/chapter-header/') >= 0 || u.indexOf('/chapter-footer/') >= 0 || seen[u]) { continue; }
      seen[u] = true;
      pages.push({ index: pages.length, url: u });
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
