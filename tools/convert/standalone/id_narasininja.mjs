// id/narasininja — narasininja.com MangaStream-style WordPress + CSRF filter API (bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['filters not supported; plain search only'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var csrfCache = { token: '', at: 0 };
async function csrfToken() {
  if (csrfCache.token && Date.now() - csrfCache.at < 600000) { return csrfCache.token; }
  var doc = await H_doc(BASE + '/komik');
  var el = R_selFirst(doc, 'meta[name=csrf-token]');
  if (!el || !el.attr('content')) { throw new Error('CSRF token not found'); }
  csrfCache.token = el.attr('content');
  csrfCache.at = Date.now();
  return csrfCache.token;
}
function toStatus(v) {
  v = String(v || '').toLowerCase();
  if (/ongoing/.test(v)) { return 'ongoing'; }
  if (/completed|finished|tamat/.test(v)) { return 'completed'; }
  if (/hiatus|on.hold/.test(v)) { return 'hiatus'; }
  if (/cancelled|canceled|dropped/.test(v)) { return 'cancelled'; }
  return '';
}
async function filterQuery(page, query) {
  var token = await csrfToken();
  var body = 'search=' + encodeURIComponent(query || '') + '&status=&type=&order=update';
  var text = await $.http.post(BASE + '/komik/filter?page=' + page, body, {
    'X-CSRF-TOKEN': token,
    'X-Requested-With': 'XMLHttpRequest',
    'Content-Type': 'application/x-www-form-urlencoded',
    Referer: BASE + '/komik'
  });
  var d = JSON.parse(text);
  var out = [];
  var data = d.data || [];
  for (var i = 0; i < data.length; i++) {
    var m = data[i];
    out.push({
      key: '/komik/' + m.slug,
      title: m.title || '',
      coverUrl: BASE + '/storage/comic/image-bg/' + m.slug + '.jpg'
    });
  }
  return { mangas: out, hasNextPage: d.meta ? d.meta['current_page'] < d.meta['last_page'] : false };
}
function parseChapterNumber(raw) {
  var m = String(raw || '').trim().match(/(\\d+)(?:[._-](\\d+))?/);
  if (!m) { return -1; }
  return parseFloat(m[1] + (m[2] ? '.' + m[2] : ''));
}
function parseDate(text) {
  var v = String(text || '').trim();
  if (!v) { return 0; }
  var t = Date.parse(v);
  return isNaN(t) ? R_date(v) : t;
}
module.exports = {
  getPopularManga: async function (page) {
    var doc = await H_doc(BASE + '/');
    var links = R_sel(doc, '.listupd.popularslider .bs .bsx a');
    var out = [];
    for (var i = 0; i < links.length; i++) {
      var a = links[i];
      var href = a.absUrl('href');
      if (!href) { continue; }
      var img = R_selFirst(a, 'img');
      out.push({ key: R_path(href), title: a.attr('title') || '', coverUrl: img ? img.absUrl('src') : '' });
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) { return filterQuery(page, query); },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var thumb = R_selFirst(doc, '.thumb img');
    var desc = R_selFirst(doc, '.entry-content.entry-content-single p');
    var status = '';
    var author = '';
    var artist = '';
    var rows = R_sel(doc, '.infotable tr');
    for (var i = 0; i < rows.length; i++) {
      var t = rows[i].text();
      var tds = R_sel(rows[i], 'td');
      var val = tds.length ? tds[tds.length - 1].text() : '';
      if (t.indexOf('Status') >= 0) { status = toStatus(val); }
      else if (t.indexOf('Author') >= 0 && val && val !== '-') { author = val; }
      else if (t.indexOf('Artist') >= 0 && val && val !== '-') { artist = val; }
    }
    return {
      key: mangaKey,
      title: H_firstText(doc, 'h1.entry-title'),
      coverUrl: thumb ? thumb.absUrl('src') : '',
      author: author,
      description: desc ? desc.text() : '',
      genre: H_texts(doc, '.seriestugenre a'),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var lis = R_sel(doc, '#chapterlist li, .eplister li');
    var out = [];
    var seen = {};
    for (var i = 0; i < lis.length; i++) {
      var li = lis[i];
      var a = R_selFirst(li, 'a');
      if (!a) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      var numEl = R_selFirst(li, '.chapternum');
      var name = numEl ? numEl.text() : a.text();
      var dateEl = R_selFirst(li, '.chapterdate');
      var num = parseChapterNumber(li.attr('data-num') || name.substring(name.lastIndexOf(' ') + 1));
      var id = String(num);
      if (seen[id]) { continue; }
      seen[id] = true;
      out.push({
        key: R_path(href),
        name: name,
        chapterNumber: num,
        dateUpload: dateEl ? parseDate(dateEl.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.sort(function (x, y) { return y.chapterNumber - x.chapterNumber; }); // newest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey));
    var imgs = R_sel(doc, '#readerarea img.ts-main-image');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
