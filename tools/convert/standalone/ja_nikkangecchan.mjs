// ja/nikkangecchan — Nikkangecchan (Akita Publishing) — bespoke scraper
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
async function parseList(query) {
  var doc = await H_doc(BASE);
  var out = [];
  var items = R_sel(doc, '.contentInner > figure');
  for (var i = 0; i < items.length; i++) {
    var imgBox = R_selFirst(items[i], '.imgBox');
    var detailBoxes = R_sel(items[i], '.detailBox');
    var detailBox = detailBoxes.length > 0 ? detailBoxes[detailBoxes.length - 1] : null;
    if (!imgBox || !detailBox) { continue; }
    var link = R_selFirst(imgBox, 'a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    var title = H_firstText(detailBox, 'h3');
    if (!href || !title) { continue; }
    if (query && title.toLowerCase().indexOf(String(query).toLowerCase()) < 0) { continue; }
    out.push({
      key: R_path(href),
      title: title,
      coverUrl: R_img(R_selFirst(imgBox, 'a > img'))
    });
  }
  return { mangas: out, hasNextPage: false };
}

module.exports = {
  getPopularManga: function () { return parseList(''); },

  getSearchManga: function (page, query) { return parseList(query); },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var detailBox = R_selFirst(doc, '#comicDetail .detailBox');
    var author = detailBox ? H_firstText(detailBox, '.author') : '';
    return {
      key: mangaKey,
      title: detailBox ? H_firstText(detailBox, 'h3') : '',
      coverUrl: '',
      author: author,
      description: H_firstText(doc, '.description'),
      genre: '',
      status: 'ongoing'
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var items = R_sel(doc, '.episodeBox');
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var episodePage = R_selFirst(items[i], '.episode-page');
      var titleEl = R_selFirst(items[i], 'h4.episodeTitle');
      if (!episodePage || !titleEl) { continue; }
      var title = titleEl.text();
      var dataTitle = String(episodePage.attr('data-title') || '').split('|')[0].trim();
      var dataSrc = episodePage.attr('abs:data-src') || (BASE + episodePage.attr('data-src'));
      if (!dataSrc) { continue; }
      var path = R_path(dataSrc.substring(0, dataSrc.lastIndexOf('/')));
      out.push({
        key: path,
        name: dataTitle ? title + ' - ' + dataTitle : title,
        chapterNumber: parseFloat(title) || -1,
        dateUpload: 0,
        pages: 1,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    return [{ index: 0, url: R_abs(chapterKey) + '/image' }];
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
  return wrap(manifest, body);
}
