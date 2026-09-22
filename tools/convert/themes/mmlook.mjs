// MMLook theme engine (zh: dumanwu, rumanhua) — mobile/desktop hybrid with packed+XOR page data
export const runtime = 'wp';

export function extract(ctx) {
  const warnings = [];
  const config = {};
  warnings.push('category/ranking browse filters not supported; text search + default ranking only');
  warnings.push('followRedirects(false)/hostnameVerifier TLS bypass not replicable; https downgraded to http for chapter pages like upstream');
  warnings.push('packed script unpacked by executing it with a captured eval');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mmlook)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var DESKTOP = BASE.replace('https://m.', 'https://www.');
var HTTP_BASE = BASE.replace('https:', 'http:');

var KEYS = ['smkhy258', 'smkd95fv', 'md496952', 'cdcsdwq', 'vbfsa256', 'cawf151c', 'cd56cvda', '8kihnt9', 'dso15tlo', '5ko6plhy'];

function stripSlash(s) {
  return String(s || '').replace(/^\\/+/, '').replace(/\\/+$/, '');
}

function mmDecrypt(data, index) {
  var key = KEYS[index];
  if (!key) { throw new Error('Unknown index: ' + index); }
  var s = atob(data);
  var out = '';
  for (var i = 0; i < s.length; i++) {
    out += String.fromCharCode(s.charCodeAt(i) ^ key.charCodeAt(i % key.length));
  }
  return atob(out);
}

function unpackEval(code) {
  var out = String(code);
  for (var iter = 0; iter < 5; iter++) {
    if (out.indexOf('eval') < 0) { break; }
    var captured = null;
    try {
      var fn = new Function('eval', out + '\\n;');
      fn(function (c) {
        captured = String(c);
        throw { mmlookStop: true };
      });
    } catch (e) { /* aborted at eval call, or script error */ }
    if (captured === null || captured === out) { break; }
    out = captured;
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(DESKTOP + '/rank/1');
    var doc = $.html.parse(text);
    var entries = R_sel(doc, '.likedata');
    var mangas = [];
    for (var i = 0; i < entries.length; i++) {
      var a = R_selFirst(entries[i], 'a');
      var tEl = R_selFirst(entries[i], '.le-t');
      if (!a || !tEl) { continue; }
      var auEl = R_selFirst(entries[i], '.likeinfo > p');
      var descEl = R_selFirst(entries[i], '.le-j');
      var img = R_selFirst(entries[i], 'img');
      mangas.push({
        key: '/' + stripSlash(a.attr('href')),
        title: tEl.text(),
        coverUrl: img ? (img.attr('data-src') || '') : '',
        authorHint: auEl ? String(auEl.text()).replace(/^作者：/, '') : '',
        descHint: descEl ? descEl.text() : ''
      });
    }
    return { mangas: mangas, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var body = 'k=' + encodeURIComponent(String(query || '').substring(0, 12));
    var text = await $.http.post(DESKTOP + '/s', body, {
      'Content-Type': 'application/x-www-form-urlencoded'
    });
    var doc = $.html.parse(text);
    var entries = R_sel(doc, '.item-data > div');
    var mangas = [];
    for (var i = 0; i < entries.length; i++) {
      var a = R_selFirst(entries[i], 'a');
      var tEl = R_selFirst(entries[i], '.e-title, .title');
      if (!a || !tEl) { continue; }
      var auEl = R_selFirst(entries[i], '.tip');
      var img = R_selFirst(entries[i], 'img');
      mangas.push({
        key: '/' + stripSlash(a.attr('href')),
        title: tEl.text(),
        coverUrl: img ? (img.attr('data-src') || '') : '',
        authorHint: auEl ? auEl.text() : ''
      });
    }
    return { mangas: mangas, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var id = stripSlash(mangaKey);
    var text = await $.http.get(DESKTOP + '/' + id + '/');
    var doc = $.html.parse(text);
    var info = R_selFirst(doc, '.comicInfo');
    var container = info ? R_selFirst(info, '.detinfo') : null;
    var title = '', cover = '', author = '', genre = '', status = 'UNKNOWN', desc = '';
    if (info) {
      var img = R_selFirst(info, 'img');
      cover = img ? (img.attr('data-src') || '') : '';
    }
    if (container) {
      var h1 = R_selFirst(container, 'h1');
      title = h1 ? h1.text() : '';
      var updated = '';
      var spans = R_sel(container, 'span');
      for (var i = 0; i < spans.length; i++) {
        var t = R_ownText(spans[i]);
        if (!t || t.length < 4) { continue; }
        var key = t.substring(0, 4);
        var value = t.substring(4).replace(/^\\s+/, '');
        if (key === '作 者：') { author = value; }
        else if (key === '更新时间') { updated = t + '\\n\\n'; }
        else if (key === '标 签：') { genre = value.replace(/ /g, ', '); }
        else if (key === '状 态：') {
          if (value === '连载中') { status = 'ONGOING'; }
          else if (value === '已完结') { status = 'COMPLETED'; }
        }
      }
      var contentEl = R_selFirst(container, '.content');
      desc = updated + (contentEl ? contentEl.text() : '');
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: author,
      description: desc,
      genre: genre,
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var id = stripSlash(mangaKey);
    var text = await $.http.get(DESKTOP + '/' + id + '/');
    var doc = $.html.parse(text);
    var container = R_selFirst(doc, '.chapterlistload');
    if (!container) { return []; }
    var chapters = [];
    var firstChild = R_selFirst(container, ':scope > *');
    if (firstChild) {
      var anchors = R_sel(firstChild, ':scope > a');
      for (var i = 0; i < anchors.length; i++) {
        var href = stripSlash(anchors[i].attr('href')).replace(/\\.html$/, '');
        if (!href) { continue; }
        chapters.push({ key: '/' + href, name: anchors[i].text() });
      }
    }
    if (R_selFirst(container, '.chaplist-more')) {
      var body = 'id=' + encodeURIComponent(id);
      var moreText = await $.http.post(DESKTOP + '/morechapter', body, {
        'Content-Type': 'application/x-www-form-urlencoded'
      });
      var data = JSON.parse(moreText).data || [];
      for (var m = 0; m < data.length; m++) {
        chapters.push({ key: '/' + id + '/' + data[m].chapterid, name: data[m].chaptername });
      }
    }
    // site lists newest first; host expects oldest first
    chapters.reverse();
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var path = stripSlash(chapterKey);
    var text = await $.http.get(HTTP_BASE + '/' + path + '.html');
    var doc = $.html.parse(text);
    var reader = R_selFirst(doc, '.readerContainer');
    if (!reader) { return []; }
    var index = parseInt(reader.attr('data-id'), 10);
    if (isNaN(index)) { return []; }
    var scripts = R_sel(doc, 'script');
    var packed = null;
    for (var i = 0; i < scripts.length; i++) {
      var body = scripts[i].html();
      if (body && body.indexOf('eval') >= 0) { packed = body; break; }
    }
    if (!packed) { return []; }
    var unpacked = unpackEval(packed);
    var m = /__c0rst96\\s*=\\s*"([^"]*)"/.exec(unpacked);
    if (!m) { return []; }
    var decrypted = mmDecrypt(m[1], index);
    var urls = JSON.parse(decrypted);
    var pages = [];
    for (var u = 0; u < urls.length; u++) { pages.push(urls[u]); }
    return pages;
  },

  imageHeaders: function () {
    return { 'Referer': HTTP_BASE + '/' };
  }
};
`;
}
