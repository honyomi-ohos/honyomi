// ja/momonga — MomonGA — bespoke scraper (list items are <a> roots)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return { ok: true, config: {}, warnings: ['search filters (category paths) not supported; text search only'] };
}

export function generate(manifest) {
  const body = String.raw`
async function parseList(url) {
  var doc = await H_doc(url);
  var out = [];
  var items = R_sel(doc, 'div.post-list > a');
  for (var i = 0; i < items.length; i++) {
    var href = items[i].absUrl('href');
    if (!href) { continue; }
    out.push({
      key: R_path(href),
      title: H_firstText(items[i], 'span') || items[i].text(),
      coverUrl: R_img(R_selFirst(items[i], 'div.post-list-image > img'))
    });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, 'div.wp-pagenavi > a.nextpostslink') };
}

function jpDate(v) {
  var m = String(v || '').match(/(\d{4})年(\d{1,2})月(\d{1,2})日(\d{1,2})時/);
  if (!m) { return R_date(v); }
  return new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10), parseInt(m[4], 10), 0, 0, 0).getTime();
}

module.exports = {
  getPopularManga: function (page) {
    return parseList(page > 1 ? BASE + '/popularity/page/' + page + '/' : BASE + '/popularity/');
  },

  getSearchManga: function (page, query) {
    var u = page > 1
      ? BASE + '/page/' + page + '/?s=' + encodeURIComponent(query)
      : BASE + '/?s=' + encodeURIComponent(query);
    return parseList(u);
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var author = '';
    var artist = '';
    var genre = '';
    var rows = R_sel(doc, '#post-tag > div.post-tag-table');
    for (var i = 0; i < rows.length; i++) {
      var label = H_firstText(rows[i], 'div.post-tag-title');
      if (label === 'サークル') { artist = H_texts(rows[i], 'div.post-tags > a'); }
      else if (label === '作者') { author = H_texts(rows[i], 'div.post-tags > a'); }
      else if (label === '内容') { genre = H_texts(rows[i], 'div.post-tags > a'); }
    }
    return {
      key: mangaKey,
      title: H_firstText(doc, '#post-data > h1'),
      coverUrl: R_img(R_selFirst(doc, '#post-hentai > img')),
      author: author,
      description: '',
      genre: genre,
      status: 'completed'
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    return [{
      key: mangaKey,
      name: '単一章',
      chapterNumber: 1,
      dateUpload: jpDate(H_firstText(doc, '#post-time')),
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey));
    var imgs = R_sel(doc, '#post-hentai > img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].attr('src');
      if (src) { pages.push({ index: pages.length, url: R_abs(src) }); }
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
