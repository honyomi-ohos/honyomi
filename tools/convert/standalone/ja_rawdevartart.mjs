// ja/rawdevartart — Rawdevart (JSON SPA API)
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
function toManga(it) {
  return { key: String(it.manga_id), title: it.manga_name || '', coverUrl: it.manga_cover_img || '' };
}

function toPage(json) {
  var d = json || {};
  var list = d.manga_list || [];
  var btn = (d.pagi || {}).button;
  return { mangas: list.map(toManga), hasNextPage: !!(btn && btn.next) };
}

module.exports = {
  getPopularManga: async function (page) {
    return toPage($.json.parse(await H_get(BASE + '/spa?page=' + page)));
  },

  getLatestManga: async function (page) {
    return toPage($.json.parse(await H_get(BASE + '/spa/latest-manga?page=' + page)));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/spa/search?page=' + page + '&query=' + encodeURIComponent(query);
    return toPage($.json.parse(await H_get(u)));
  },

  getMangaDetail: async function (mangaKey) {
    var json = $.json.parse(await H_get(BASE + '/spa/manga/' + mangaKey));
    var d = json.detail || {};
    var parts = [];
    if (d.manga_date_published) {
      var ts = Date.parse(d.manga_date_published);
      if (!isNaN(ts)) {
        var dt = new Date(ts);
        parts.push('**Published:** ' + dt.getFullYear() + '/' + (dt.getMonth() + 1) + '/' + dt.getDate());
      }
    }
    if (d.manga_views > 0) { parts.push('**Views:** ' + d.manga_views); }
    if (d.manga_description) { parts.push('**Summary:**\n' + d.manga_description); }
    if (d.manga_others_name) { parts.push('**Alternative Titles:**\n' + d.manga_others_name); }
    var authors = [];
    var tags = [];
    var a = json.authors || [];
    var t = json.tags || [];
    for (var i = 0; i < a.length; i++) { if (a[i].author_name) authors.push(a[i].author_name); }
    for (var j = 0; j < t.length; j++) { if (t[j].tag_name) tags.push(t[j].tag_name); }
    return {
      key: String(d.manga_id || mangaKey),
      title: d.manga_name || String(mangaKey),
      coverUrl: d.manga_cover_img_full || d.manga_cover_img || '',
      author: authors.join(', '),
      description: parts.join('\n\n'),
      genre: tags.join(', '),
      status: d.manga_status ? 'completed' : 'ongoing'
    };
  },

  getChapterList: async function (mangaKey) {
    var json = $.json.parse(await H_get(BASE + '/spa/manga/' + mangaKey));
    var chapters = json.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var num = c.chapter_number || 0;
      var nr = String(num).replace(/\.0$/, '');
      var name = 'Chapter ' + nr + (c.chapter_title ? ': ' + c.chapter_title : '');
      var ts = c.chapter_date_published ? Date.parse(c.chapter_date_published) : NaN;
      out.push({
        key: 'spa/manga/' + mangaKey + '/' + nr,
        name: name,
        chapterNumber: num,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0
      });
    }
    out.sort(function (x, y) { return x.chapterNumber - y.chapterNumber; });
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var json = $.json.parse(await H_get(BASE + '/' + chapterKey));
    var d = (json.chapter_detail || {});
    var server = d.server || BASE;
    var html = d.chapter_content || '';
    var doc = $.html.parse(html);
    var imgs = R_sel(doc, 'img[data-src]');
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].attr('data-src') || '';
      if (!src) { continue; }
      var u = /^https?:\/\//.test(src) ? src : server.replace(/\/$/, '') + (src.charAt(0) === '/' ? src : '/' + src);
      out.push({ index: out.length, url: u });
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
