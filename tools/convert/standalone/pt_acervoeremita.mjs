// pt/acervoeremita — AcervoEremita (Next.js RSC + JSON chapters API)
import { wrap } from './_emit.mjs';
import { RSC_SRC } from './_nextjs.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['upstream applies a 3 req/s rate limit that this runtime cannot enforce; aggressive browsing may be throttled by the site'],
  };
}

export function generate(manifest) {
  const body = String.raw`
${RSC_SRC}

function parseList(html) {
  var rows = RSC.parse(html);
  var works = RSC.arr(rows, 'works');
  var pag = RSC.find(rows, ['pagination']);
  var hasNext = false;
  if (pag && pag.pagination) {
    hasNext = !!(pag.pagination.hasNext || pag.pagination.hasMore);
  }
  var out = [];
  if (works) {
    for (var i = 0; i < works.length; i++) {
      var w = works[i];
      if (!w || !w.workId) { continue; }
      out.push({
        key: String(w.workId) + '|' + String(w.slug || ''),
        title: w.title || '',
        coverUrl: w.coverUrl || ''
      });
    }
  }
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(BASE + '/explore?page=' + page));
  },

  getLatestManga: async function (page) {
    return parseList(await $.http.get(BASE + '/explore?page=' + page + '&sort=release&dir=desc'));
  },

  getSearchManga: async function (page, query) {
    return parseList(await $.http.get(BASE + '/explore?page=' + page + '&q=' + encodeURIComponent(query)));
  },

  getMangaDetail: async function (mangaKey) {
    var slug = mangaKey.split('|')[1] || '';
    var doc = await H_doc(BASE + '/work/' + slug);
    var title = H_firstText(doc, 'h1');
    var img = R_selFirst(doc, 'img[data-component*=cover]');
    var description = H_firstText(doc, 'p[data-component*=description]');
    var tags = R_sel(doc, '[data-component*=tags] > span');
    var genres = [];
    for (var i = 0; i < tags.length; i++) {
      var t = tags[i].text();
      if (t) { genres.push(t); }
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: img ? (img.absUrl('src') || '') : '',
      author: '',
      description: description,
      genre: genres.join(', '),
      status: 'unknown'
    };
  },

  getChapterList: async function (mangaKey) {
    var workId = mangaKey.split('|')[0];
    var slug = mangaKey.split('|')[1] || '';
    var out = [];
    var cursor = 0;
    for (var round = 0; round < 100; round++) {
      var dto = $.json.parse(await $.http.get(BASE + '/api/work/chapters?workId=' + workId + '&cursor=' + cursor + '&limit=30'));
      var chapters = dto.chapters || [];
      for (var i = 0; i < chapters.length; i++) {
        var c = chapters[i];
        var ts = c.releasedAt ? Date.parse(c.releasedAt) : NaN;
        out.push({
          key: slug + '|' + String(c.chapterNumber),
          name: c.name || ('Capítulo ' + c.chapterNumber),
          chapterNumber: parseFloat(c.chapterNumber) || -1,
          dateUpload: isNaN(ts) ? 0 : ts,
          pages: 0,
          sortOrder: 0
        });
      }
      var hasNext = dto.pagination && (dto.pagination.hasNext || dto.pagination.hasMore);
      if (!hasNext || !chapters.length) { break; }
      cursor += 30;
    }
    // API returns newest first; plugin contract wants oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = chapterKey.split('|');
    var doc = await H_doc(BASE + '/work/' + parts[0] + '/read?chapter=' + parts[1] + '&page=1');
    var imgs = R_sel(doc, '[data-component*=ReaderScreen] > img');
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src') || '';
      if (!u) { continue; }
      out.push({ index: out.length, url: u });
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
