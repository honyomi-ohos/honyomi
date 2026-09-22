// all/thelibraryofohara — bespoke engine (WordPress category archive; multi-lang collapsed to en)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['multi-language ext collapsed to single plugin (English category set and Reverie language filter)'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var POPULAR_SELECTOR = '#categories-7 ul li.cat-item-589813936, #categories-7 ul li.cat-item-607613583, ' +
  '#categories-7 ul li.cat-item-43972770, #categories-7 ul li.cat-item-9363667, #categories-7 ul li.cat-item-634609261, ' +
  '#categories-7 ul li.cat-item-699200615, #categories-7 ul li.cat-item-139757, #categories-7 ul li.cat-item-22695, ' +
  '#categories-7 ul li.cat-item-648324575';

async function fetchPopular() {
  var text = await $.http.get(BASE);
  var doc = $.html.parse(text);
  var items = R_sel(doc, POPULAR_SELECTOR);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var a = R_selFirst(items[i], 'a');
    if (!a) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    out.push({ key: R_path(href), title: a.text(), coverUrl: '' });
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    return { mangas: await fetchPopular(), hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    var all = await fetchPopular();
    var q = query.toLowerCase();
    return { mangas: all.filter(function (m) { return m.title.toLowerCase().indexOf(q) >= 0; }), hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var titleEl = R_selFirst(doc, 'h1.page-title');
    var title = titleEl ? titleEl.text().replace('Category: ', '') : '';
    var cover = '';
    var art = R_selFirst(doc, 'article');
    if (art) {
      var img = R_selFirst(art, 'img');
      if (img) { cover = img.absUrl('src'); }
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: '',
      description: '',
      genre: '',
      status: 'ongoing',
    };
  },

  getChapterList: async function (mangaKey) {
    var all = [];
    var url = R_abs(mangaKey);
    for (var guard = 0; guard < 200; guard++) {
      var text = await $.http.get(url);
      var doc = $.html.parse(text);
      var arts = R_sel(doc, 'article');
      if (arts.length === 0) { break; }
      for (var i = 0; i < arts.length; i++) {
        var link = R_selFirst(arts[i], 'a.entry-thumbnail');
        var titleEl = R_selFirst(arts[i], 'h2.entry-title a');
        var timeEl = R_selFirst(arts[i], 'span.posted-on time');
        var href = link ? link.absUrl('href') : (titleEl ? titleEl.absUrl('href') : '');
        if (!href) { continue; }
        var dt = timeEl ? timeEl.attr('datetime').replace('+00:00', '+0000') : '';
        var ts = dt ? Date.parse(dt) : 0;
        all.push({
          key: R_path(href),
          name: titleEl ? titleEl.text() : '',
          chapterNumber: -1,
          dateUpload: isNaN(ts) ? 0 : ts,
          pages: 0,
          sortOrder: 0,
        });
      }
      var next = R_selFirst(doc, 'div.nav-previous a');
      if (!next) { break; }
      url = next.absUrl('href');
      if (!url) { break; }
    }
    if (all.length > 0 && all[0].name.indexOf('Reverie') >= 0) {
      all = all.filter(function (c) {
        return !/French|Arabic|Italian|Indonesia|Spanish/.test(c.name);
      });
    }
    for (var j = 0; j < all.length; j++) { all[j].sortOrder = j; }
    return all;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var content = R_selFirst(doc, 'div.entry-content');
    var imgs = content ? R_sel(content, 'a img, img.size-full') : [];
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].attr('data-orig-file');
      if (u) { pages.push({ index: pages.length, url: R_abs(u) }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
