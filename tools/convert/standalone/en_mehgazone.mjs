// en/mehgazone (bodysuit23.mehgazone.com) — single-title WordPress REST source
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'single-title source (Bodysuit 23)',
      'WordPress Basic-auth login not supported: Patreon/locked chapters are filtered out (as upstream does without credentials)',
      'text-only "excerpt" page (TextInterceptor) not portable: skipped',
      'chapter pagination falls back to 100-per-page heuristic (host cannot read X-Wp-Totalpages)',
    ],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};

function unescapeHtml(s) {
  return String(s || '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'");
}

function parseIso(s) {
  var m = /(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})/.exec(String(s || ''));
  if (!m) { return 0; }
  return new Date(Date.UTC(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10), parseInt(m[4], 10), parseInt(m[5], 10), parseInt(m[6], 10))).getTime();
}

module.exports = {
  getPopularManga: async function (page) {
    var doc = $.html.parse(await $.http.get(BASE + '/', {}));
    var group = R_selFirst(doc, '#main aside.primary-sidebar .sidebar-group');
    if (!group) { return { mangas: [], hasNextPage: false }; }
    var h2s = R_sel(group, 'h2');
    var feedA = R_selFirst(group, "a[href*='/feed']");
    var img = R_selFirst(group, 'img');
    var out = [];
    for (var i = 0; i < h2s.length; i++) {
      var t = h2s[i].text() || '';
      if (t.toLowerCase().indexOf('latest') < 0) { continue; }
      var parts = t.split('"');
      if (parts.length < 2) { continue; }
      var rootUrl = '';
      if (feedA) {
        try { rootUrl = new URL(feedA.attr('href'), BASE).origin + '/'; } catch (e) { rootUrl = BASE + '/'; }
      } else { rootUrl = BASE + '/'; }
      out.push({
        key: rootUrl,
        title: unescapeHtml(parts[1]),
        coverUrl: img ? (img.attr('src') || '') : ''
      });
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var list = await module.exports.getPopularManga(page);
    var q = (query || '').toLowerCase();
    var filtered = [];
    for (var i = 0; i < list.mangas.length; i++) {
      if (list.mangas[i].title.toLowerCase().indexOf(q) >= 0) { filtered.push(list.mangas[i]); }
    }
    return { mangas: filtered, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var rootUrl = mangaKey.indexOf('http') === 0 ? mangaKey : BASE + '/';
    var text = await $.http.get(rootUrl, {});
    var doc = $.html.parse(text);
    var title = '';
    var tEl = R_selFirst(doc, 'head title');
    if (tEl) { title = unescapeHtml(tEl.text()); }
    var cover = '';
    var imgs = R_sel(doc, '#content img');
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].attr('src') || '';
      if (/\\/[^\\/]+-([0-9]+\\.png)$/i.test(src)) {
        cover = src.replace(/\\/[^\\/]+-([0-9]+\\.png)$/i, '/$1');
        break;
      }
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: 'Patricia Barton',
      description: '',
      genre: '',
      status: 'ongoing'
    };
  },

  getChapterList: async function (mangaKey) {
    var rootUrl = mangaKey.indexOf('http') === 0 ? mangaKey : BASE + '/';
    var api = rootUrl.replace(/\\/$/, '') + '/wp-json/wp/v2/posts?per_page=100&page=';
    var all = [];
    var pageNum = 1;
    while (true) {
      var batch = JSON.parse(await $.http.get(api + pageNum + '&_fields=id,title,date_gmt,excerpt', {}));
      for (var i = 0; i < batch.length; i++) { all.push(batch[i]); }
      if (batch.length < 100) { break; }
      pageNum++;
    }
    var seen = {};
    var filtered = [];
    for (var f = 0; f < all.length; f++) {
      var ch = all[f];
      var exc = ch.excerpt && ch.excerpt.rendered ? ch.excerpt.rendered : '';
      if (exc.indexOf('Unlock with Patreon') >= 0) { continue; }
      if (seen[ch.id]) { continue; }
      seen[ch.id] = true;
      filtered.push(ch);
    }
    filtered.sort(function (a, b) {
      var da = a.date_gmt || '', db = b.date_gmt || '';
      return da < db ? -1 : da > db ? 1 : 0;
    });
    var out = [];
    for (var k = 0; k < filtered.length; k++) {
      var c = filtered[k];
      var nm = c.title && c.title.rendered ? unescapeHtml(c.title.rendered) : '';
      if (!nm) { nm = (c.date_gmt || '').split('T')[0]; }
      out.push({
        key: rootUrl + '?p=' + c.id,
        name: nm,
        chapterNumber: k,
        dateUpload: parseIso(c.date_gmt),
        pages: 0,
        sortOrder: k
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var u = new URL(chapterKey);
    var p = u.searchParams.get('p');
    var rootUrl = chapterKey.substring(0, chapterKey.indexOf('/?p='));
    if (p === null || !rootUrl) {
      rootUrl = u.origin;
      if (p === null) { p = ''; }
    }
    var api = rootUrl.replace(/\\/$/, '') + '/wp-json/wp/v2/posts?per_page=1&_fields=link,content,excerpt,date,title&include=' + p;
    var arr = JSON.parse(await $.http.get(api, {}));
    if (!arr.length) { return []; }
    var post = arr[0];
    var content = post.content && post.content.rendered ? post.content.rendered : '';
    var doc = $.html.parse(content);
    var imgs = R_sel(doc, 'img');
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].attr('src') || '';
      if (src) { out.push({ index: out.length, url: src }); }
    }
    return out;
  },

  imageHeaders: function () {
    return {};
  }
};
`;
}
