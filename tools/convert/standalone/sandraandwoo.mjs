// all/sandraandwoo — bespoke single-manga webcomic engine (multi-lang ext collapsed to first)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['multi-language ext collapsed to single plugin (English synopsis/archive)'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var THUMB = 'https://www.sandraandwoo.com/images/fanart/fanart-contest-2014/pictures/zheng-qu-01-color-corrected.jpg';
var SYNOPSIS = 'Sandra and Woo is a comedy comic strip featuring the 13-year-old girl Sandra North and her mischievous pet raccoon Woo. While most strips are just supposed to be funny or tell an exciting story, some also deal with more serious topics. We also want to show what growing up means for Sandra and her best friends in middle school, Cloud and Larisa. Another regular feature of the comic are Woo\\u2019s trips to the forest to meet his furry friends Shadow (a fox) and Sid (a squirrel) and his love interest Lily.';
var DATE_RE = /^.*\\/(\\d+)\\/(\\d+)\\/(\\d+)\\/[^/]*\\//;
var TITLE_RE = /^Permanent Link:\\s*((?:\\[(\\d{4})])?\\s*(?:\\[[^]]*(\\d{4})])?.*)/;

module.exports = {
  getPopularManga: async function (page) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    return { mangas: [{ key: '/archive', title: ${JSON.stringify(manifest.name)}, coverUrl: THUMB }], hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    return { mangas: [], hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    return {
      key: mangaKey,
      title: ${JSON.stringify(manifest.name)},
      coverUrl: THUMB,
      author: 'Oliver Kn\\u00F6rzer',
      description: SYNOPSIS,
      genre: 'Comedy',
      status: 'hiatus',
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(BASE + '/archive');
    var doc = $.html.parse(text);
    var links = R_sel(doc, '#column a');
    // document lists newest-first; normalize to oldest-first
    var out = [];
    var lastNum = 0;
    for (var i = links.length - 1; i >= 0; i--) {
      var el = links[i];
      var path = el.attr('href').replace(/^https?:\\/\\/[^\\/]+/, '');
      var m = path.match(DATE_RE);
      var date = m ? Date.parse(m[1] + '-' + m[2] + '-' + m[3] + 'T00:00:00Z') : 0;
      var hover = el.attr('title');
      var tm = hover.match(TITLE_RE);
      var title = tm ? tm[1] : hover;
      var num = 0;
      if (tm) {
        if (tm[2]) { num = parseFloat(tm[2]); }
        else if (tm[3]) { num = parseFloat(tm[3]); }
      }
      if (!num) { num = Math.round((lastNum + Math.floor(lastNum + 1)) / 2); }
      lastNum = num;
      out.push({
        key: path,
        name: title,
        chapterNumber: num,
        dateUpload: isNaN(date) ? 0 : date,
        pages: 0,
        sortOrder: 0,
      });
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var img = R_selFirst(doc, '#comic img');
    return [{ index: 0, url: img ? img.absUrl('src') : '' }];
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
