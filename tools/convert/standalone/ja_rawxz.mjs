// ja/rawxz — RawXZ (WordPress Jsoup scraper + img-proxy)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  const body = String.raw`
var PROXY = BASE + '/wp-content/themes/manga-theme-MangaVerse/img-proxy.php?url=';

function cleanTitle(t) {
  return String(t || '').replace(/ \(Raw – Free\)$/, '');
}

function parseList(doc) {
  var items = R_sel(doc, '.manga-card');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = R_selFirst(el, 'a.manga-card-thumb');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, '.manga-card-thumb img');
    out.push({ key: R_path(href), title: cleanTitle(R_selFirst(el, '.manga-card-title') ? R_selFirst(el, '.manga-card-title').text() : ''), coverUrl: R_img(img) });
  }
  var hasNext = out.length >= 40 && !!R_selFirst(doc, '.pagination a i.fa-chevron-right');
  return { mangas: out, hasNextPage: hasNext };
}

function metaVal(doc, icon) {
  var rows = R_sel(doc, '.md-meta-row');
  for (var i = 0; i < rows.length; i++) {
    if (R_selFirst(rows[i], icon)) {
      var v = R_selFirst(rows[i], '.md-meta-val');
      return v ? v.text() : '';
    }
  }
  return '';
}

function parseStatus(s) {
  if (!s) { return 'unknown'; }
  if (s.indexOf('連載中') >= 0) { return 'ongoing'; }
  if (s.indexOf('完結') >= 0) { return 'completed'; }
  return 'unknown';
}

function parseRelativeDate(date) {
  var v = String(date || '').trim();
  if (!v) { return 0; }
  var m = v.split(' ')[0].match(/\d+/);
  if (!m) { return 0; }
  var amount = parseInt(m[0], 10);
  var now = Date.now();
  if (v.indexOf('秒前') >= 0) { return now - amount * 1000; }
  if (v.indexOf('分前') >= 0) { return now - amount * 60000; }
  if (v.indexOf('時間前') >= 0) { return now - amount * 3600000; }
  if (v.indexOf('日前') >= 0) { return now - amount * 86400000; }
  if (v.indexOf('週間前') >= 0) { return now - amount * 7 * 86400000; }
  if (v.indexOf('ヶ月前') >= 0) { return now - amount * 30 * 86400000; }
  if (v.indexOf('年前') >= 0) { return now - amount * 365 * 86400000; }
  return 0;
}

function toProxyUrl(u) {
  if (!u || u.indexOf('img-proxy.php?url=') >= 0) { return u; }
  return PROXY + encodeURIComponent(u);
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await H_doc(BASE + '/manga/page/' + page + '/?orderby=views'));
  },

  getLatestManga: async function (page) {
    return parseList(await H_doc(BASE + '/manga/page/' + page + '/?orderby=date'));
  },

  getSearchManga: async function (page, query) {
    var u = (page > 1 ? BASE + '/page/' + page + '/' : BASE + '/') + '?s=' + encodeURIComponent(query) + '&post_type=manga';
    return parseList(await H_doc(u));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var author = metaVal(doc, '.fa-user');
    if (author === '更新中') { author = ''; }
    var cover = R_selFirst(doc, '.md-cover img');
    return {
      key: mangaKey,
      title: cleanTitle(R_selFirst(doc, '.md-title') ? R_selFirst(doc, '.md-title').text() : ''),
      coverUrl: cover ? cover.absUrl('src') : '',
      author: author,
      description: R_selFirst(doc, '.md-desc-content') ? R_selFirst(doc, '.md-desc-content').text() : '',
      genre: H_texts(doc, '.md-tag'),
      status: parseStatus(metaVal(doc, '.fa-rss'))
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var rows = R_sel(doc, '.md-chapter-row');
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var link = R_selFirst(rows[i], '.md-chapter-name a');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var tEl = R_selFirst(rows[i], '.md-chapter-time');
      out.push({
        key: R_path(href),
        name: R_ownText(link),
        chapterNumber: -1,
        dateUpload: parseRelativeDate(tEl ? tEl.text() : ''),
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    if (String(chapterKey).indexOf('http') === 0) {
      throw new Error('この章のURLは古くなっています。マンガを更新してください。');
    }
    var doc = await H_doc(R_abs(chapterKey));
    var imgs = R_sel(doc, '.reader-page img');
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = toProxyUrl(imgs[i].absUrl('src'));
      if (u) { out.push({ index: out.length, url: u }); }
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
