// ja/rawuwu — RawUwU (JSON SPA API)
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
function toPage(json) {
  var d = json || {};
  var list = d.manga_list || [];
  var btn = (d.pagi || {}).button;
  return { mangas: list.map(function (m) {
    return { key: String(m.manga_id), title: m.manga_name || '', coverUrl: m.manga_cover_img || '' };
  }), hasNextPage: !!(btn && btn.next > 0) };
}

function fmtNum(num) {
  return num % 1 === 0 ? String(num) : String(num);
}

module.exports = {
  getPopularManga: async function (page) {
    return toPage($.json.parse(await H_get(BASE + '/spa/genre/all?sort=most_viewed&page=' + page)));
  },

  getLatestManga: async function (page) {
    return toPage($.json.parse(await H_get(BASE + '/spa/latest-manga?page=' + page)));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/spa/search?query=' + encodeURIComponent(query) + '&page=' + page;
    return toPage($.json.parse(await H_get(u)));
  },

  getMangaDetail: async function (mangaKey) {
    var json = $.json.parse(await H_get(BASE + '/spa/manga/' + mangaKey));
    var d = json.detail;
    if (!d) { throw new Error('Could not find manga details'); }
    var desc = d.manga_description || '';
    var alt = d.manga_others_name;
    if (alt) {
      var names = String(alt).split(',');
      desc += (desc ? '\n\n' : '') + 'Alternative Names:';
      for (var i = 0; i < names.length; i++) { desc += '\n - ' + names[i].trim(); }
    }
    var authors = [];
    var tags = [];
    var a = json.authors || [];
    var t = json.tags || [];
    for (var x = 0; x < a.length; x++) { if (a[x].author_name) authors.push(a[x].author_name); }
    for (var y = 0; y < t.length; y++) { if (t[y].tag_name) tags.push(t[y].tag_name); }
    return {
      key: String(d.manga_id || mangaKey),
      title: d.manga_name || String(mangaKey),
      coverUrl: d.manga_cover_img_full || d.manga_cover_img || '',
      author: authors.join(', '),
      description: desc,
      genre: tags.join(', '),
      status: d.manga_status === true ? 'completed' : (d.manga_status === false ? 'ongoing' : 'unknown')
    };
  },

  getChapterList: async function (mangaKey) {
    var json = $.json.parse(await H_get(BASE + '/spa/manga/' + mangaKey));
    var d = json.detail;
    if (!d) { throw new Error('Could not find chapters'); }
    var chapters = json.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var num = c.chapter_number;
      if (num === null || num === undefined) { continue; }
      var nr = fmtNum(num);
      var title = (c.chapter_title || '').trim();
      var ts = c.chapter_date_published ? Date.parse(c.chapter_date_published + (String(c.chapter_date_published).charAt(10) === 'T' ? '' : 'T00:00:00Z')) : NaN;
      out.push({
        key: '/read/' + d.manga_id + '/chapter-' + nr,
        name: title ? 'Ch. ' + nr + ' - ' + title : 'Chapter ' + nr,
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
    var m = String(chapterKey).match(/\/read\/([^\/]+)\/chapter-(.+)$/);
    if (!m) { throw new Error('bad chapter key: ' + chapterKey); }
    var json = $.json.parse(await H_get(BASE + '/spa/manga/' + m[1] + '/' + m[2]));
    var d = json.chapter_detail;
    if (!d) { throw new Error('Could not find chapter detail'); }
    var server = d.server;
    if (!server) { throw new Error('Could not find server url'); }
    var doc = $.html.parse(d.chapter_content || '');
    var imgs = R_sel(doc, 'img');
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      var raw = (imgs[i].attr('data-src') || '').replace(/^\//, '');
      if (!raw) { continue; }
      out.push({ index: out.length, url: server.replace(/\/$/, '') + '/' + raw });
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
