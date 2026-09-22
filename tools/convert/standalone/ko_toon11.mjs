// ko/toon11 — Toon11 (11toon.com GNU-board scraper)
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
var HDRS = { Referer: BASE + '/' };

function styleThumb(el) {
  var style = el.attr('style') || '';
  var m = style.match(/url\('([^']+)'\)/);
  return m ? 'https:' + m[1] : '';
}

function pathQ(href) {
  return String(href).replace(/^https?:\/\/[^\/]+/, '');
}

function parseItems(doc, mode) {
  var items = R_sel(doc, 'li[data-id]');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var titleEl = R_selFirst(el, '.homelist-title');
    if (!titleEl) { continue; }
    var title = titleEl.text();
    if (!title) { continue; }
    var thumbEl = R_selFirst(el, '.homelist-thumb');
    var cover = '';
    if (thumbEl) {
      cover = mode === 'popular'
        ? (thumbEl.absUrl('data-mobile-image') || '')
        : styleThumb(thumbEl);
    }
    if (mode === 'search') {
      out.push({
        key: '/bbs/board.php?bo_table=toons&stx=' + encodeURIComponent(title) + '&is=' + el.attr('data-id'),
        title: title,
        coverUrl: cover
      });
    } else {
      var a = R_selFirst(el, 'a');
      if (!a) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      out.push({ key: pathQ(href), title: title, coverUrl: cover });
    }
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, '.pg_end') };
}

function afterLabeledSpan(doc, label) {
  var spans = R_sel(doc, 'span');
  for (var i = 0; i < spans.length; i++) {
    if (spans[i].text().indexOf(label) >= 0 && spans[i + 1]) {
      return spans[i + 1].text();
    }
  }
  return '';
}

function parseStatus(v) {
  if (v.indexOf('완결') >= 0) { return 'completed'; }
  if (v.indexOf('주간') >= 0 || v.indexOf('월간') >= 0 || v.indexOf('연재') >= 0 || v.indexOf('격주') >= 0) { return 'ongoing'; }
  return 'unknown';
}

function parseChapterEl(el, out) {
  var btn = R_selFirst(el, 'button');
  if (!btn) { return; }
  var onclick = btn.attr('onclick') || '';
  var idx = onclick.indexOf("location.href='.");
  if (idx < 0) { return; }
  var rest = onclick.substring(idx + "location.href='.".length);
  var path = rest.substring(0, rest.indexOf("'"));
  var titleEl = R_selFirst(btn, '.episode-title');
  if (!titleEl) { return; }
  var dateEl = R_selFirst(el, '.free-date');
  var ts = 0;
  if (dateEl) {
    var m = dateEl.text().match(/^(\d{2})\.(\d{2})\.(\d{2})$/);
    if (m) { ts = Date.parse('20' + m[1] + '-' + m[2] + '-' + m[3] + 'T00:00:00+09:00'); }
  }
  out.push({
    key: path,
    name: titleEl.text(),
    chapterNumber: -1,
    dateUpload: isNaN(ts) ? 0 : ts,
    pages: 0,
    sortOrder: 0
  });
}

module.exports = {
  getPopularManga: async function (page) {
    return parseItems(await H_doc(BASE + '/bbs/board.php?bo_table=toon_c&is_over=0', HDRS), 'popular');
  },

  getLatestManga: async function (page) {
    return parseItems(await H_doc(BASE + '/bbs/board.php?bo_table=toon_c&sord=&type=upd&page=' + page, HDRS), 'latest');
  },

  getSearchManga: async function (page, query) {
    var q = String(query || '');
    if (q) {
      return parseItems(await H_doc(BASE + '/bbs/search_stx.php?stx=' + encodeURIComponent(q), HDRS), 'search');
    }
    var u = BASE + '/bbs/board.php?bo_table=toon_c&is_over=' + (page > 1 ? '&page=' + page : '');
    return parseItems(await H_doc(u, HDRS), 'popular');
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var titleEl = R_selFirst(doc, 'h2.title');
    var banner = R_selFirst(doc, 'img.banner');
    var genreRaw = afterLabeledSpan(doc, '장르');
    var genres = [];
    var parts = genreRaw.split(',');
    for (var i = 0; i < parts.length; i++) {
      var t = parts[i].trim();
      if (t) { genres.push(t); }
    }
    return {
      key: mangaKey,
      title: titleEl ? titleEl.text() : '',
      coverUrl: banner ? (banner.absUrl('src') || '') : '',
      author: afterLabeledSpan(doc, '작가'),
      description: afterLabeledSpan(doc, '소개'),
      genre: genres.join(', '),
      status: parseStatus(afterLabeledSpan(doc, '분류'))
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var out = [];
    var items = R_sel(doc, '#comic-episode-list > li');
    for (var i = 0; i < items.length; i++) {
      parseChapterEl(items[i], out);
    }
    // follow pagination: .pg_current ~ .pg_page next link
    var visited = {};
    var next = null;
    var nav = R_selFirst(doc, 'span.pg');
    if (nav) {
      var pgLinks = R_sel(nav, '.pg_page');
      for (var p = 0; p < pgLinks.length; p++) {
        if (pgLinks[p].attr('class').indexOf('pg_current') >= 0 && pgLinks[p + 1]) {
          next = pgLinks[p + 1].absUrl('href');
          break;
        }
      }
    }
    var guard = 0;
    while (next && !visited[next] && guard < 100) {
      visited[next] = 1;
      guard++;
      var pageDoc = await H_doc(next, HDRS);
      var pageItems = R_sel(pageDoc, '#comic-episode-list > li');
      for (var j = 0; j < pageItems.length; j++) {
        parseChapterEl(pageItems[j], out);
      }
      next = '';
      var nav2 = R_selFirst(pageDoc, 'span.pg');
      if (nav2) {
        var links2 = R_sel(nav2, '.pg_page');
        for (var q = 0; q < links2.length; q++) {
          if (links2[q].attr('class').indexOf('pg_current') >= 0 && links2[q + 1]) {
            next = links2[q + 1].absUrl('href');
            break;
          }
        }
      }
    }
    // list is newest-first on site; contract wants oldest first
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(BASE + '/bbs' + chapterKey, HDRS);
    var scripts = R_sel(doc, 'script[type^=text/javascript]');
    var out = [];
    for (var i = 0; i < scripts.length; i++) {
      if (scripts[i].attr('src')) { continue; }
      var data = scripts[i].html ? scripts[i].html() : '';
      var m = data.match(/img_list\s*=\s*(\[[\s\S]*?\])/);
      if (!m) { continue; }
      var imgs = $.json.parse(m[1]) || [];
      for (var j = 0; j < imgs.length; j++) {
        if (imgs[j]) { out.push({ index: out.length, url: 'https:' + imgs[j] }); }
      }
      break;
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
