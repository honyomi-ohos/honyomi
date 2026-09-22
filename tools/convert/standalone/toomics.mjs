// all/toomics — bespoke scraper engine (multi-lang collapsed to en; free chapters only)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'multi-language ext (9 langs) collapsed to single plugin (site lang en)',
      'extension intentionally exposes only free chapters ("Only free chapters")',
      'per-page Referer from og:url not portable; fixed Referer used instead',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone scraper)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var LANG = 'en';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/81.0.4044.122 Safari/537.36';

function hdrs() {
  return { 'Referer': BASE + '/' + LANG, 'User-Agent': UA };
}
function unescapeContent(s) {
  return String(s || '')
    .replace(/\\\\u([0-9A-Fa-f]{4})/g, function (m, h) { return String.fromCharCode(parseInt(h, 16)); })
    .replace(/\\\\U([0-9A-Fa-f]{8})/g, function (m, h) { return String.fromCharCode(parseInt(h, 16)); })
    .replace(/\\\\n|\\\\r/g, '');
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/' + LANG + '/webtoon/ranking', hdrs());
    var doc = $.html.parse(text);
    var anchors = R_sel(doc, 'li div.visual a');
    var out = [];
    for (var i = 0; i < anchors.length; i++) {
      var el = anchors[i];
      var img = R_selFirst(el, 'img');
      if (!img) { continue; }
      var h4 = R_selFirst(el, 'h4[class$=title]');
      if (!h4) { continue; }
      var href = el.absUrl('href');
      if (!href) { continue; }
      var thumb = img.attr('data-original') || img.attr('src') || '';
      out.push({ key: R_path(href) + '/search/Y', title: R_ownText(h4), coverUrl: R_abs(thumb) });
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var body = R_form([['toonData', query]]);
    var text = await $.http.post(BASE + '/' + LANG + '/webtoon/ajax_search', body, R_xhr(hdrs()));
    var dto = JSON.parse(text);
    var doc = $.html.parse(unescapeContent(dto.content));
    var items = R_sel(doc, '#search-list-items li');
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      var strong = R_selFirst(el, 'strong');
      var anchor = R_selFirst(el, 'a.relative');
      if (!strong || !anchor) { continue; }
      var onclick = anchor.attr('href');
      var m = onclick.indexOf("Base.setFamilyMode('N', '");
      if (m < 0) { continue; }
      var href = onclick.substring(m + "Base.setFamilyMode('N', '".length).split("'")[0];
      href = decodeURIComponent(href);
      var tm = href.match(/[?&]toon=([^&']+)/);
      if (!tm) { continue; }
      var img = R_selFirst(el, 'img');
      out.push({
        key: '/' + LANG + '/webtoon/episode/toon/' + tm[1] + '/search/Y',
        title: strong.text(),
        coverUrl: img ? img.absUrl('src') : '',
      });
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), hdrs());
    var doc = $.html.parse(text);
    var sections = R_sel(doc, '#glo_contents section.relative');
    var header = null;
    for (var i = 0; i < sections.length; i++) {
      if (R_selFirst(sections[i], 'img[src*=thumb]')) { header = sections[i]; break; }
    }
    if (!header) { throw new Error('Could not find manga details header'); }
    var h2 = R_selFirst(header, 'h2');
    if (!h2) { throw new Error('Could not find manga title'); }
    var artist = '';
    var author = '';
    var info = R_selFirst(header, '.mb-0.text-xs.font-normal');
    if (info) {
      var parts = info.text().split('|');
      artist = (parts[0] || '').trim();
      author = (parts[parts.length - 1] || '').trim();
    }
    var genre = '';
    var dts = R_sel(header, 'dt');
    var dds = R_sel(header, 'dd');
    for (var d = 0; d < dts.length; d++) {
      if (/genre/i.test(dts[d].text()) && dds[d]) {
        genre = dds[d].text().replace(/\\//g, ', ');
        break;
      }
    }
    var desc = R_selFirst(header, '.break-noraml.text-xs');
    var og = R_selFirst(doc, "head meta[property='og:image']");
    return {
      key: mangaKey,
      title: h2.text(),
      coverUrl: og ? og.attr('content') : '',
      author: author,
      artist: artist,
      description: desc ? desc.text() : '',
      genre: genre,
      status: '',
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), hdrs());
    var doc = $.html.parse(text);
    var items = R_sel(doc, 'li.normal_ep');
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      if (!R_selFirst(el, '.coin-type1, .coin-type6')) { continue; }
      var onclick = R_selFirst(el, 'a');
      if (!onclick) { continue; }
      var link = onclick.attr('onclick');
      var m = link.indexOf("href='");
      if (m < 0) { continue; }
      var href = link.substring(m + 6).split("'")[0];
      var key = /^https?:/.test(href) ? R_path(href) : href;
      var numEl = R_selFirst(el, 'div.cell-num');
      var num = numEl ? numEl.text().trim() : '';
      var numText = num ? num + ' - ' : '';
      var titleEl = R_selFirst(el, 'div.cell-title strong');
      var title = titleEl ? R_ownText(titleEl) : '';
      var timeEl = R_selFirst(el, 'div.cell-time time');
      var numFloat = parseFloat(num);
      out.push({
        key: key,
        name: numText + title,
        chapterNumber: isNaN(numFloat) ? -1 : numFloat,
        dateUpload: timeEl ? R_date(timeEl.text()) : 0,
        pages: 0,
        sortOrder: 0,
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), hdrs());
    var doc = $.html.parse(text);
    if (R_selFirst(doc, 'div.section_age_verif')) {
      throw new Error('Verify age via WebView');
    }
    var imgs = R_sel(doc, 'div[id^=load_image_] img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].attr('data-src');
      if (u) { pages.push({ index: pages.length, url: R_abs(u) }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { 'Referer': BASE + '/' + LANG + '/', 'User-Agent': UA };
  },
};
`;
}
