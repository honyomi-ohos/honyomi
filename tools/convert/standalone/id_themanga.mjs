// id/themanga — themanga.site custom HTML (bespoke)
// NOTE: site sits behind Cloudflare which serves a JS challenge to datacenter IPs;
// upstream ships no WebView/CF handling, so it is expected to work from normal
// residential/mobile networks but may be challenged in some environments.
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: [
      'Cloudflare JS challenge observed from datacenter IPs; may be blocked in some networks',
      'filters not supported; plain search only',
    ],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var HDRS = { Referer: BASE + '/' };
function statusMap(v) {
  v = String(v || '').trim().toLowerCase();
  if (v === 'ongoing') { return 'ongoing'; }
  if (v === 'completed') { return 'completed'; }
  return '';
}
function metaValue(doc, label) {
  var labels = R_sel(doc, '.meta-item-label');
  var values = R_sel(doc, '.meta-item-label + .meta-item-value');
  for (var i = 0; i < labels.length && i < values.length; i++) {
    if (R_ownText(labels[i]).trim() === label) { return values[i].text(); }
  }
  return '';
}
module.exports = {
  getPopularManga: async function (page) {
    var doc = await H_doc(BASE + '/?q=&sort=popular&page=' + page, HDRS);
    var els = R_sel(doc, 'a.card');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var t = R_selFirst(els[i], '.card-title');
      if (!t) { continue; }
      var img = R_selFirst(els[i], '.card-cover img');
      out.push({ key: R_path(els[i].absUrl('href')), title: t.text(), coverUrl: img ? img.absUrl('src') : '' });
    }
    return { mangas: out, hasNextPage: !!R_selFirst(doc, '.explore-pagination__btn[rel=next]') };
  },

  getSearchManga: async function (page, query) {
    var doc = await H_doc(BASE + '/explore?q=' + encodeURIComponent(query) + '&page=' + page, HDRS);
    var els = R_sel(doc, 'a.manga-card');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var t = R_selFirst(els[i], '.card-title');
      if (!t) { continue; }
      var img = R_selFirst(els[i], '.cover img');
      out.push({ key: R_path(els[i].absUrl('href')), title: t.text(), coverUrl: img ? img.absUrl('src') : '' });
    }
    return { mangas: out, hasNextPage: !!R_selFirst(doc, 'a[rel=next]') };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var img = R_selFirst(doc, '.hero-cover img');
    var genres = [];
    var pills = R_sel(doc, '.meta-pill-row .meta-pill');
    for (var i = 0; i < pills.length; i++) { genres.push(pills[i].text()); }
    var type = metaValue(doc, 'Type');
    if (type) { genres.push(type); }
    return {
      key: mangaKey,
      title: H_firstText(doc, '.hero-title'),
      coverUrl: img ? img.absUrl('src') : '',
      author: metaValue(doc, 'Author'),
      artist: metaValue(doc, 'Artist'),
      description: H_firstText(doc, '.synopsis-text'),
      genre: genres.join(', '),
      status: statusMap(H_firstText(doc, '.hero-status-badge'))
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey) + '?all=1', HDRS);
    var els = R_sel(doc, '.chapter-row');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var t = R_selFirst(el, '.chapter-title');
      var d = R_selFirst(el, '[data-local-time]');
      out.push({
        key: R_path(el.absUrl('data-href')),
        name: t ? t.text() : '',
        chapterNumber: -1,
        dateUpload: d ? (Date.parse(d.attr('data-local-time')) || 0) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey), HDRS);
    var els = R_sel(doc, 'img.page-img');
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      pages.push({ index: i, url: els[i].absUrl('src') });
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
