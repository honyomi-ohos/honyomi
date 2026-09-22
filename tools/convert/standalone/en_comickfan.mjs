// en/comickfan — comick.fan HTML search + JSON chapter API
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return { ok: true, config: {}, warnings: ['filters not supported; popular=Rating sort, latest=Last Updated sort'] };
}

export function generate(manifest) {
  return wrap(manifest, `
var HDRS = { Referer: BASE + '/' };
function parseList(doc) {
  var out = [];
  var items = R_sel(doc, 'div:has(> form) + div.grid > a');
  if (!items.length) { items = R_sel(doc, 'div.grid > a'); }
  for (var i = 0; i < items.length; i++) {
    var img = R_selFirst(items[i], 'img');
    if (!img) { continue; }
    var href = items[i].absUrl('href') || items[i].attr('href');
    if (!href) { continue; }
    out.push({ key: R_path(href), title: img.attr('alt'), coverUrl: img.absUrl('src') });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, 'img[alt=Next]') };
}
function searchUrl(page, query, sort) {
  return BASE + '/advanced-search?page=' + page + '&name=' + encodeURIComponent(query) + (sort ? '&sort=' + sort : '');
}
function getValue(root, label) {
  var rows = R_sel(root, 'div.flex-row.gap-4');
  for (var i = 0; i < rows.length; i++) {
    var first = R_selFirst(rows[i], 'div.text-sm');
    if (first && first.text() === label) {
      var all = R_sel(rows[i], 'div.text-sm');
      var v = all.length > 1 ? all[all.length - 1].text() : '';
      if (v !== '' && v !== '-' && v !== '_') { return v; }
    }
  }
  return '';
}
module.exports = {
  getPopularManga: async function (page) {
    var doc = await H_doc(searchUrl(page, '', 'rating'), HDRS);
    return parseList(doc);
  },
  getSearchManga: async function (page, query) {
    if (query.indexOf('https://') === 0) {
      var seg = query.replace(/^https?:\\/\\//, '').split('/')[1];
      if (!seg) { throw new Error('Invalid URL'); }
      var d = await module.exports.getMangaDetail('/manga/' + seg);
      return { mangas: [d], hasNextPage: false };
    }
    var doc = await H_doc(searchUrl(page, query, ''), HDRS);
    return parseList(doc);
  },
  getMangaDetail: async function (key) {
    var doc = await H_doc(R_abs(key), HDRS);
    var info = R_selFirst(doc, 'div[class=bg-card-section]');
    var author = '', artist = '', statusRaw = '', genre = '', cover = '';
    if (info) {
      author = getValue(info, 'Author').split(',').map(function (s) { return s.trim(); }).filter(Boolean).join(', ');
      artist = getValue(info, 'Artist').split(',').map(function (s) { return s.trim(); }).filter(Boolean).join(', ');
      statusRaw = getValue(info, 'Status').toLowerCase();
      var genreEls = R_sel(info, 'div.font-medium + div a');
      var parts = [];
      for (var i = 0; i < genreEls.length; i++) { if (genreEls[i].text()) { parts.push(genreEls[i].text()); } }
      genre = parts.join(', ');
      var thumb = R_selFirst(info, 'div.thumb-cover img');
      cover = thumb ? thumb.absUrl('src') : '';
    }
    var status = statusRaw === 'ongoing' ? 'ongoing' : (statusRaw === 'completed' ? 'completed' : (statusRaw === 'hiatus' ? 'hiatus' : ''));
    return {
      key: key,
      title: H_firstText(doc, 'h1'),
      coverUrl: cover,
      author: author,
      description: H_firstText(doc, 'div.comic-content.desk'),
      genre: genre,
      status: status
    };
  },
  getChapterList: async function (key) {
    var slug = key.replace(/^\\/+/, '').split('/')[1];
    if (!slug) { throw new Error('Invalid manga URL: ' + key); }
    var text = await H_get(BASE + '/api/comics/' + slug + '/chapter-list?translation_group_id=', HDRS);
    var data = JSON.parse(text).data || [];
    var out = [];
    for (var i = 0; i < data.length; i++) {
      var c = data[i];
      var nr = parseFloat(c.chapter);
      var ds = (c.created_at || c.published_at || '').replace(/(\\.)\\d{3}\\d+/, '$1');
      var dv = Date.parse(ds);
      out.push({
        key: '/manga/' + slug + '/chapter-' + c.chapter + '-' + c.hash_id,
        name: 'Chapter ' + c.chapter,
        chapterNumber: isNaN(nr) ? -1 : nr,
        dateUpload: isNaN(dv) ? 0 : dv,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), HDRS);
    var imgs = R_sel(doc, 'div.w-full > img[loading=lazy]');
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
