// ko/wolfdotcom — 늑대닷컴 (wfwf scraper; 3 flavors share one site, only 웹툰 flavor)
// NOTE: upstream Kotlin selectors are outdated; this engine targets the current markup
// (a.t-card browse grid, h1.w-title detail, a.ep-item chapters, img[data-src] reader).
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return {
      ok: true,
      config: {},
      warnings: [
        'multi-source ext (웹툰/만화책/포토툰 flavors of the same site): only the first source (웹툰) is converted; 만화책 and 포토툰 flavors are excluded',
        'site rotates its domain frequently; the plugin resolves the current domain at runtime by following the notice page link when the manifest baseUrl is stale',
        'site search requires EUC-KR query encoding which the JS runtime cannot produce; text search is downgraded to local title filtering of the browse list',
        'site serves pages in EUC-KR while the runtime decodes UTF-8; Korean titles/chapter names may appear garbled',
      ],
    };
  }
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  const body = String.raw`
var HOST = null; // resolved current domain (manifest baseUrl may be stale)

// fetch a path on the current host, following the domain-rotation notice page if hit
async function W_doc(path) {
  var body = await $.http.get((HOST || BASE) + path);
  if (body.indexOf('main-btn') >= 0) {
    var m = /href="(https?:\/\/[^"]+)"[^>]*class="main-btn"|class="main-btn"[^>]*href="(https?:\/\/[^"]+)"/.exec(body);
    var nd = m ? (m[1] || m[2]) : '';
    if (nd) {
      HOST = nd.replace(/\/+$/, '');
      body = await $.http.get(HOST + path);
    }
  }
  return $.html.parse(body);
}

function W_base() { return HOST || BASE; }

function parseBrowse(doc, page) {
  var cards = R_sel(doc, 'a.t-card');
  var out = [];
  for (var i = 0; i < cards.length; i++) {
    var a = cards[i];
    var href = a.absUrl('href') || '';
    var m = /[?&]toon=([^&]+)/.exec(href);
    if (!m) { continue; }
    var title = H_firstText(a, '.t-title');
    var img = R_selFirst(a, '.t-img img');
    out.push({ key: m[1], title: title, coverUrl: img ? (img.absUrl('data-src') || img.absUrl('src') || '') : '' });
  }
  var hasNext = false;
  var btns = R_sel(doc, 'a.pg-btn');
  for (var j = 0; j < btns.length; j++) {
    if ((btns[j].attr('href') || '').indexOf('pg=' + (page + 1)) >= 0) { hasNext = true; break; }
  }
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseBrowse(await W_doc('/ing?o=f&pg=' + page), page);
  },

  getLatestManga: async function (page) {
    return parseBrowse(await W_doc('/ing?o=n&pg=' + page), page);
  },

  getSearchManga: async function (page, query) {
    // site search needs EUC-KR encoding; fall back to local title filtering
    var q = (query || '').trim().toLowerCase();
    if (q.length < 2) { return { mangas: [], hasNextPage: false }; }
    var res = await parseBrowse(await W_doc('/ing?o=f&pg=1'), 1);
    var filtered = [];
    for (var i = 0; i < res.mangas.length; i++) {
      if (res.mangas[i].title.toLowerCase().indexOf(q) >= 0) {
        filtered.push(res.mangas[i]);
      }
    }
    return { mangas: filtered, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await W_doc('/list?toon=' + encodeURIComponent(mangaKey));
    var title = H_firstText(doc, 'h1.w-title');
    var thumb = R_selFirst(doc, '.thumb-wrap img');
    var description = H_firstText(doc, '.summary');
    var genres = [];
    var tags = R_sel(doc, '.genre-tags a.gtag');
    for (var i = 0; i < tags.length; i++) {
      var g = tags[i].text().replace(/^#/, '').trim();
      if (g) { genres.push(g); }
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: thumb ? (thumb.absUrl('src') || '') : '',
      author: '',
      description: description,
      genre: genres.join(', '),
      status: 'unknown'
    };
  },

  getChapterList: async function (mangaKey) {
    var out = [];
    // s=o = oldest first; chapters are paginated 100 per page
    for (var pg = 1; pg <= 50; pg++) {
      var doc = await W_doc('/list?toon=' + encodeURIComponent(mangaKey) + '&s=o&pg=' + pg);
      var items = R_sel(doc, 'a.ep-item');
      if (!items.length) { break; }
      for (var i = 0; i < items.length; i++) {
        var a = items[i];
        var href = a.absUrl('href') || '';
        var mToon = /[?&]toon=([^&]+)/.exec(href);
        var mNum = /[?&]num=([^&]+)/.exec(href);
        if (!mToon || !mNum) { continue; }
        var name = H_firstText(a, '.ep-title');
        if (!name) { name = R_ownText(a); }
        var dateEl = R_selFirst(a, '.ep-date');
        var ts = dateEl ? Date.parse(dateEl.text().trim()) : NaN;
        out.push({
          key: 'toon=' + mToon[1] + '&num=' + mNum[1],
          name: name,
          chapterNumber: -1,
          dateUpload: isNaN(ts) ? 0 : ts,
          pages: 0,
          sortOrder: 0
        });
      }
      var more = false;
      var btns = R_sel(doc, 'a.pg-btn');
      for (var k = 0; k < btns.length; k++) {
        if ((btns[k].attr('href') || '').indexOf('pg=' + (pg + 1)) >= 0) { more = true; break; }
      }
      if (!more) { break; }
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await W_doc('/view?' + chapterKey);
    var imgs = R_sel(doc, 'img[data-src]');
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('data-src') || '';
      if (!u) { continue; }
      out.push({ index: out.length, url: u });
    }
    return out;
  },

  imageHeaders: function () { return { Referer: W_base() + '/' }; }
};
`;
  return wrap(manifest, body);
}
