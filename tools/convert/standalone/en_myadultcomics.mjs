// en/myadultcomics (myadultcomics.com) — NSFW gallery list, single-chapter entries
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['search-type (parody/character/tag/artist) filter not ported; title search only'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

function parseList(text) {
  var doc = $.html.parse(text);
  var els = R_sel(doc, 'td.list_container');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var link = R_selFirst(el, 'p.text_container > a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    var title = link.text();
    if (!href || !title) { continue; }
    var key;
    try { var hu = new URL(href); key = hu.pathname + hu.search; } catch (e) { key = href; }
    var img = R_selFirst(el, 'img.fon_pic_img');
    out.push({ key: key, title: title, coverUrl: img ? img.absUrl('src') : '' });
  }
  var hasNext = false;
  var pager = R_sel(doc, 'td.tbl_page a');
  for (var p = 0; p < pager.length; p++) {
    if ((pager[p].text() || '').indexOf('>>') >= 0) { hasNext = true; break; }
  }
  return { mangas: out, hasNextPage: hasNext };
}

function infoLinks(doc, prefix) {
  var out = [];
  var ps = R_sel(doc, 'p.text_info_book');
  for (var i = 0; i < ps.length; i++) {
    var t = (ps[i].text() || '').trim();
    if (t.indexOf(prefix) !== 0) { continue; }
    var as = R_sel(ps[i], 'a');
    for (var a = 0; a < as.length; a++) { out.push(as[a].text()); }
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(BASE + '/index.php?page=' + page, HDRS));
  },

  getSearchManga: async function (page, query) {
    return parseList(await $.http.get(BASE + '/index.php?name=' + encodeURIComponent(query || '') + '&search=yes&page=' + page, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var tags = infoLinks(doc, 'Tags:');
    var artists = infoLinks(doc, 'Artists:');
    return {
      key: mangaKey,
      title: (R_selFirst(doc, 'h1#TOP') || { text: function () { return ''; } }).text(),
      coverUrl: '',
      author: artists.join(', '),
      artist: artists.join(', '),
      description: '',
      genre: tags.join(', '),
      status: 'completed'
    };
  },

  getChapterList: async function (mangaKey) {
    return [{
      key: mangaKey,
      name: 'Gallery',
      chapterNumber: 1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), HDRS);
    var doc = $.html.parse(text);
    var scripts = R_sel(doc, 'script');
    var out = [];
    for (var s = 0; s < scripts.length; s++) {
      var data = scripts[s].html() || '';
      if (data.indexOf('let template') < 0) { continue; }
      var re = /src=["'](books\\/[^"']+)["']/g;
      var m;
      while ((m = re.exec(data)) !== null) {
        out.push({ index: out.length, url: BASE + '/' + m[1] });
      }
      break;
    }
    return out;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
