// ko/rawdex — RawDEX (custom rdx-* markup, ex-Madara)
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
function parseRelativeDate(v) {
  var m = String(v || '').trim().match(/(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago/);
  if (!m) { return 0; }
  var amount = parseInt(m[1], 10);
  var units = { second: 1000, minute: 60000, hour: 3600000, day: 86400000, week: 604800000, month: 2592000000, year: 31536000000 };
  return Date.now() - amount * units[m[2]];
}

function browsePage(doc) {
  var items = R_sel(doc, 'article.rdx-library-card');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = R_selFirst(el, '.rdx-library-card__body h2 a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    var title = link.text();
    if (!href || !title) { continue; }
    var img = R_selFirst(el, '.rdx-library-card__cover img');
    out.push({ key: R_path(href), title: title, coverUrl: img ? (img.absUrl('src') || '') : '' });
  }
  return { mangas: out, hasNextPage: out.length > 0 && !!R_selFirst(doc, 'a.next.page-numbers') };
}

module.exports = {
  getPopularManga: async function (page) {
    return browsePage(await H_doc(BASE + '/manga/page/' + page + '/?m_orderby=views'));
  },

  getLatestManga: async function (page) {
    return browsePage(await H_doc(BASE + '/manga/page/' + page + '/?m_orderby=latest'));
  },

  getSearchManga: async function (page, query) {
    var u = page > 1
      ? BASE + '/?s=' + encodeURIComponent(query) + '&spage=' + page
      : BASE + '/?s=' + encodeURIComponent(query);
    return browsePage(await H_doc(u));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var titleEl = R_selFirst(doc, '.rdx-manga-heading h1');
    if (!titleEl) { throw new Error('Failed to parse title'); }
    var cover = R_selFirst(doc, 'img.rdx-manga-cover');
    var statusRaw = (H_firstText(doc, '.rdx-manga-status') || '').toLowerCase();
    var status = 'unknown';
    if (statusRaw === 'on-going') { status = 'ongoing'; }
    else if (statusRaw === 'end') { status = 'completed'; }
    var author = '';
    var artist = '';
    var metas = R_sel(doc, 'dl.rdx-manga-meta div');
    for (var i = 0; i < metas.length; i++) {
      var dt = R_selFirst(metas[i], 'dt');
      var dd = R_selFirst(metas[i], 'dd');
      if (!dt || !dd) { continue; }
      var label = dt.text().toLowerCase();
      if (label === 'author') { author = dd.text(); }
      else if (label === 'artist') { artist = dd.text(); }
    }
    var desc = H_firstText(doc, '.rdx-manga-summary');
    var altEl = R_selFirst(doc, '.rdx-manga-alternative');
    if (altEl) {
      var alts = String(altEl.text()).split(/[\/;]/);
      var names = [];
      for (var a = 0; a < alts.length; a++) {
        var t = alts[a].trim();
        if (t) { names.push(t); }
      }
      if (names.length) {
        desc += (desc ? '\n\n' : '') + 'Alternative Names:\n' + names.map(function (n) { return '- ' + n; }).join('\n');
      }
    }
    return {
      key: mangaKey,
      title: titleEl.text(),
      coverUrl: cover ? (cover.absUrl('src') || '') : '',
      author: author,
      artist: artist,
      description: desc,
      genre: H_texts(doc, '.rdx-manga-tags a'),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var rows = R_sel(doc, '.rdx-chapter-list a.rdx-chapter-row');
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var el = rows[i];
      var label = R_selFirst(el, '.rdx-chapter-row__label');
      if (!label || !label.text()) { continue; }
      var href = el.absUrl('href');
      if (!href) { continue; }
      var name = label.text();
      var numMatch = name.match(/(\d+(?:\.\d+)?)/);
      var dateEl = R_selFirst(el, '.rdx-chapter-row__date');
      out.push({
        key: R_path(href),
        name: name,
        chapterNumber: numMatch ? parseFloat(numMatch[1]) : -1,
        dateUpload: dateEl ? parseRelativeDate(dateEl.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // site renders newest first; contract wants oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey));
    var imgs = R_sel(doc, '.rdx-reader-page img');
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src') || '';
      if (u) { out.push({ index: out.length, url: u }); }
    }
    if (!out.length) { throw new Error('No pages found'); }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
