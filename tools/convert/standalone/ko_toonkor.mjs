// ko/toonkor — Toonkor (tkor scraper; base64 page list)
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
var WEBTOONS = '/%EC%9B%B9%ED%88%B0';
var ALL_STATUS = '/%EC%97%B0%EC%9E%AC';
var SORT_POPULAR = '?fil=%EC%9D%B8%EA%B8%B0';

function parseList(doc) {
  var items = R_sel(doc, 'div.section-item-inner');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var link = R_selFirst(el, 'div.section-item-title a');
    if (!link) { continue; }
    var h3 = R_selFirst(link, 'h3');
    if (!h3 || !h3.text()) { continue; }
    var href = link.attr('href') || '';
    if (!href) { continue; }
    var img = R_selFirst(el, 'img');
    out.push({ key: R_path(href), title: h3.text(), coverUrl: img ? (img.absUrl('src') || '') : '' });
  }
  return { mangas: out, hasNextPage: false };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await H_doc(BASE + WEBTOONS + ALL_STATUS + SORT_POPULAR));
  },

  getLatestManga: async function (page) {
    return parseList(await H_doc(BASE + WEBTOONS + ALL_STATUS));
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/bbs/search.php?sfl=wr_subject%7C%7Cwr_content&stx=' + encodeURIComponent(query);
    return parseList(await H_doc(u));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var title = H_firstText(doc, 'table.bt_view1 td.bt_title');
    var author = H_firstText(doc, 'table.bt_view1 td.bt_label span.bt_data');
    var description = H_firstText(doc, 'table.bt_view1 td.bt_over');
    var thumb = R_selFirst(doc, 'table.bt_view1 td.bt_thumb img');
    return {
      key: mangaKey,
      title: title,
      coverUrl: thumb ? (thumb.absUrl('src') || '') : '',
      author: author,
      description: description,
      genre: '',
      status: 'unknown'
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var rows = R_sel(doc, 'table.web_list tr');
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var tr = rows[i];
      var td = R_selFirst(tr, 'td.content__title');
      if (!td) { continue; }
      var url = td.attr('data-role') || '';
      var name = td.text();
      if (!url || !name) { continue; }
      var dateTd = R_selFirst(tr, 'td.episode__index');
      var ts = dateTd ? Date.parse(dateTd.text().trim()) : NaN;
      out.push({
        key: url,
        name: name,
        chapterNumber: -1,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0
      });
    }
    // site lists newest first; plugin contract wants oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey));
    var scripts = R_sel(doc, 'script');
    var encoded = '';
    for (var i = 0; i < scripts.length; i++) {
      var data = scripts[i].html ? scripts[i].html() : '';
      if (data.indexOf('toon_img') >= 0) {
        var after = data.substring(data.indexOf("'") + 1);
        encoded = after.substring(0, after.indexOf("'"));
        break;
      }
    }
    if (!encoded) { return []; }
    var decoded = $.crypto.base64Decode(encoded);
    var out = [];
    var re = /src="([^"]*)"/g;
    var m;
    while ((m = re.exec(decoded)) !== null) {
      var u = m[1];
      if (!u) { continue; }
      if (u.indexOf('http') !== 0) { u = BASE + u; }
      out.push({ index: out.length, url: u });
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
