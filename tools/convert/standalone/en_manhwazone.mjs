// en/manhwazone (manhwazone.org) — /series listing + Livewire bootLoad chapters + __RS_CONF__ pages
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'sort/status/genre filters not ported; text search only',
      'chapters need Livewire /livewire/update with session cookies (CSRF): works on-device via host CookieJar; offline probe harness has no cookie jar so probe shows HTTP 419',
    ],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HOST = ${JSON.stringify(new URL(manifest.baseUrl).host)};

function parseDate(s) {
  var m = /(\\d{4})-(\\d{2})-(\\d{2})[ T](\\d{2}):(\\d{2}):(\\d{2})/.exec(String(s || '').trim());
  if (!m) { return 0; }
  return new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10), parseInt(m[4], 10), parseInt(m[5], 10), parseInt(m[6], 10)).getTime();
}

function parseMangaList(doc) {
  var els = R_sel(doc, 'article.group');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var t = R_selFirst(el, '.min-w-0 > a.font-semibold');
    var a = R_selFirst(el, 'a');
    if (!t || !a) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, 'img');
    out.push({ key: R_path(href), title: t.text(), coverUrl: img ? img.absUrl('src') : '' });
  }
  var hasNext = !!R_selFirst(doc, 'a[rel=next]') || out.length >= 24;
  return { mangas: out, hasNextPage: hasNext };
}

function pad3(n) {
  var s = '' + n;
  while (s.length < 3) { s = '0' + s; }
  return s;
}

module.exports = {
  getPopularManga: async function (page) {
    return parseMangaList($.html.parse(await $.http.get(BASE + '/series?sortBy=popularity&page=' + page, {})));
  },

  getSearchManga: async function (page, query) {
    var q = (query || '').trim();
    if (q.indexOf('https://') === 0 && q.indexOf(HOST) >= 0) {
      var text = await $.http.get(q, {});
      var doc = $.html.parse(text);
      var u = new URL(q);
      if (u.pathname.indexOf('/series/') === 0) {
        var d = parseMangaDetails(doc, text);
        d.key = u.pathname;
        return { mangas: [d], hasNextPage: false };
      }
      return parseMangaList(doc);
    }
    return parseMangaList($.html.parse(await $.http.get(BASE + '/series?page=' + page + '&keyword=' + encodeURIComponent(q), {})));
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), {});
    return parseMangaDetails($.html.parse(text), text, mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), {});
    var doc = $.html.parse(text);
    var wireDiv = R_selFirst(doc, 'div[wire\\\\:snapshot][wire\\\\:id][wire\\\\:init=bootLoad]');
    if (!wireDiv) { return []; }
    var csrfMeta = R_selFirst(doc, 'meta[name=csrf-token]');
    var csrf = csrfMeta ? (csrfMeta.attr('content') || '') : '';
    var snapshot = wireDiv.attr('wire:snapshot') || '';
    var payload = {
      _token: csrf,
      components: [{
        snapshot: snapshot,
        updates: {},
        calls: [{ path: '', method: 'bootLoad', params: [] }]
      }]
    };
    var respText = await $.http.post(BASE + '/livewire/update', JSON.stringify(payload), {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    });
    var resp = JSON.parse(respText);
    var snapStr = resp.components && resp.components[0] && resp.components[0].snapshot;
    if (!snapStr) { return []; }
    var snap = JSON.parse(snapStr);
    var chaptersArr = snap.data && snap.data.chapters;
    if (!chaptersArr || !chaptersArr.length) { return []; }
    var actual = chaptersArr[0];
    var out = [];
    for (var i = 0; i < actual.length; i++) {
      var item = actual[i];
      if (!Array.isArray(item) || !item.length) { continue; }
      var ch = item[0];
      if (!ch || !ch.web_url) { continue; }
      out.push({
        key: ch.web_url,
        name: ch.name || 'Chapter',
        chapterNumber: -1,
        dateUpload: parseDate(ch.published),
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), {});
    var doc = $.html.parse(text);
    var scripts = R_sel(doc, 'script');
    for (var s = 0; s < scripts.length; s++) {
      var data = scripts[s].html() || '';
      if (data.indexOf('__RS_CONF__') < 0) { continue; }
      var m = /__RS_CONF__\\s*=\\s*(\\{.*?\\})\\s*;/.exec(data);
      if (!m) { break; }
      try {
        var conf = JSON.parse(m[1]);
        if (conf.p && conf.expire && conf.signature && conf.tt > 0) {
          var out = [];
          for (var i = 1; i <= conf.tt; i++) {
            out.push({
              index: i - 1,
              url: 'https://img.mangalaxy.net/_img/' + conf.p + '/' + pad3(i) + '.webp?e=' + conf.expire + '&s=' + conf.signature
            });
          }
          return out;
        }
      } catch (e) { }
      break;
    }
    var els = R_sel(doc, 'img.lazy-image[data-src]');
    var fallback = [];
    for (var f = 0; f < els.length; f++) {
      var src = els[f].absUrl('data-src');
      if (src) { fallback.push({ index: fallback.length, url: src }); }
    }
    return fallback;
  },

  imageHeaders: function () {
    return {};
  }
};

function parseMangaDetails(doc, text, mangaKey) {
  var title = '';
  var tEl = R_selFirst(doc, 'h1.page-title');
  if (tEl) { title = tEl.text(); }
  var status = '';
  var sEl = R_selFirst(doc, 'span.badge-sm');
  if (sEl) {
    var sv = (sEl.text() || '').trim().toLowerCase();
    if (sv === 'on going' || sv === 'ongoing' || sv === 'currently publishing') { status = 'ongoing'; }
    else if (sv === 'completed' || sv === 'finished') { status = 'completed'; }
    else if (sv === 'on hiatus') { status = 'on hiatus'; }
    else if (sv === 'discontinued' || sv === 'cancelled') { status = 'cancelled'; }
  }
  var author = '';
  if (text) {
    var am = /"author":\\s*\\[\\s*\\{"@type":"Person","name":"([^"]+)"/.exec(text);
    if (am && am[1].toLowerCase() !== 'unknown') { author = am[1]; }
  }
  var genres = [];
  var gas = R_sel(doc, 'a.badge-genre');
  for (var g = 0; g < gas.length; g++) { genres.push(gas[g].text()); }
  var coverEl = R_selFirst(doc, 'img.aspect-\\\\[7\\\\/10\\\\]') || R_selFirst(doc, 'figure.relative img');
  return {
    key: mangaKey || '',
    title: title,
    coverUrl: coverEl ? coverEl.absUrl('src') : '',
    author: author,
    description: (R_selFirst(doc, 'p.page-subtitle') || { text: function () { return ''; } }).text(),
    genre: genres.join(', '),
    status: status
  };
}
`;
}
