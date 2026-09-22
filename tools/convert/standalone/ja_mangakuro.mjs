// ja/mangakuro — bespoke scraper (page list via CHAPTER_ID + ajax endpoint)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return { ok: true, config: {}, warnings: ['details title/status selectors approximated'] };
}

export function generate(manifest) {
  const body = String.raw`
async function listManga(page, sort, query) {
  var u = query !== undefined
    ? BASE + '/search/' + page + '?keyword=' + encodeURIComponent(query)
    : BASE + '/all-manga/' + page + '?sort=' + sort;
  var doc = await H_doc(u);
  var items = R_sel(doc, '.story_item');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var a = R_selFirst(items[i], 'a');
    if (!a) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    out.push({
      key: R_path(href),
      title: H_firstText(items[i], '.mg_name a') || a.text(),
      coverUrl: R_img(R_selFirst(items[i], 'img'))
    });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, "a[title='Last Page']") };
}

module.exports = {
  getPopularManga: function (page) { return listManga(page, 'views'); },

  getSearchManga: function (page, query) { return listManga(page, '', query); },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var status = H_firstText(doc, 'div:has(.lnr-leaf) + .info_value');
    return {
      key: mangaKey,
      title: H_firstText(doc, 'h1') || H_firstText(doc, '.mg_name a'),
      coverUrl: R_img(R_selFirst(doc, '.detail_avatar img')),
      author: H_firstText(doc, 'div:has(.lnr-user) + .info_value'),
      description: H_firstText(doc, '.detail_reviewContent'),
      genre: '',
      status: status.indexOf('進行中') >= 0 ? 'ongoing' : ''
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var items = R_sel(doc, '.chapter_box .item');
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var a = R_selFirst(items[i], 'a');
      if (!a) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      var name = a.text();
      var hashIdx = name.indexOf('# ');
      if (hashIdx >= 0) { name = name.substring(hashIdx + 2); }
      out.push({ key: R_path(href), name: name, chapterNumber: -1, dateUpload: 0, pages: 0, sortOrder: 0 });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var html = await H_get(R_abs(chapterKey));
    var m = html.match(/CHAPTER_ID\s*=\s*(\d+);/);
    if (!m) { return []; }
    var api = await H_get(BASE + '/ajax/image/list/chap/' + m[1]);
    var pages = [];
    var re = /src=\\"([^"\\]+)\\"/g;
    var mm;
    while ((mm = re.exec(api)) !== null) {
      pages.push({ index: pages.length, url: R_abs(mm[1]) });
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
