// all/yellownote — bespoke engine (xchina.co photo albums; multi-lang collapsed to first source)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'multi-language ext collapsed to single plugin (zh-Hans https://xchina.co)',
      'category/sort browse filters not portable; plain keyword search only',
      'image-quality preference not portable; uses original (JPG) variant',
      'site unreachable from this network — probe may fail environmentally',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};

var STYLE_URL_RE = /background-image\\s*:\\s*url\\('([^']+)'\\)/;
var MEDIA_COUNT_RE = /^\\d+P( \\+ \\d+V)?$/;
var DATE_RE = /\\d{4}\\.\\d{2}\\.\\d{2}/;

function styleUrl(el) {
  if (!el) { return ''; }
  var m = STYLE_URL_RE.exec(el.attr('style') || '');
  return m ? m[1] : '';
}

function infoItems(infoCard, iconClass) {
  var items = R_sel(infoCard, 'div.item');
  for (var i = 0; i < items.length; i++) {
    var icon = R_selFirst(items[i], '.icon > ' + iconClass);
    if (icon) { return items[i]; }
  }
  return null;
}

function infoText(infoCard, iconClass) {
  var item = infoItems(infoCard, iconClass);
  if (!item) { return null; }
  var text = R_selFirst(item, 'div.text');
  return text ? text.text() : null;
}

function infoChildren(infoCard, iconClass) {
  var item = infoItems(infoCard, iconClass);
  if (!item) { return null; }
  var text = R_selFirst(item, 'div.text');
  if (!text) { return null; }
  var kids = R_sel(text, '*');
  var out = [];
  for (var i = 0; i < kids.length; i++) {
    var t = kids[i].text();
    if (t) { out.push(t); }
  }
  return out;
}

function parseDate(s) {
  if (!s) { return 0; }
  var ts = Date.parse(s + 'T00:00:00Z');
  return isNaN(ts) ? 0 : ts;
}

async function listMangas(url) {
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var items = R_sel(doc, 'div.list.photo-list > div.item.photo');
  var items2 = R_sel(doc, 'div.list.amateur-list > div.item.amateur');
  var all = items.concat(items2);
  var out = [];
  for (var i = 0; i < all.length; i++) {
    var el = all[i];
    var a = R_selFirst(el, 'a');
    if (!a) { continue; }
    var href = a.absUrl('href');
    var titleAttr = a.attr('title') || '';
    if (!href || !titleAttr) { continue; }
    var count = '';
    var tags = R_sel(el, 'div.tags > div');
    for (var j = 0; j < tags.length; j++) {
      var t = tags[j].text();
      if (MEDIA_COUNT_RE.test(t)) { count = '(' + t + ')'; break; }
    }
    out.push({
      key: R_path(href),
      title: titleAttr + count,
      coverUrl: styleUrl(R_selFirst(a, 'div.img')),
    });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, 'div.pager:first-of-type > a.pager-next') };
}

module.exports = {
  getPopularManga: async function (page) {
    return listMangas(BASE + '/photos/sort-hot/' + page + '.html');
  },

  getSearchManga: async function (page, query) {
    if (!query) { return listMangas(BASE + '/photos/sort-hot/' + page + '.html'); }
    return listMangas(BASE + '/photos/keyword-' + encodeURIComponent(query) + '/' + page + '.html');
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var infoCard = R_selFirst(doc, 'div.info-card.photo-detail');
    if (!infoCard) { throw new Error('Could not find info card'); }
    var name = infoText(infoCard, 'i.fa-address-card');
    if (!name) { throw new Error('Could not find name'); }
    var mediaCount = infoText(infoCard, 'i.fa-image');
    if (!mediaCount) { throw new Error('Could not find media count'); }
    var no = infoText(infoCard, 'i.fa-file');
    var noPart = no ? ' ' + no : '';
    var categories = infoChildren(infoCard, 'i.fa-video-camera');
    if (categories) {
      categories = categories.filter(function (c) { return c !== '-'; });
    }
    var filters = infoChildren(infoCard, 'i.fa-filter');
    var tags = infoChildren(infoCard, 'i.fa-tags');
    var genreParts = [];
    [categories, filters, tags].forEach(function (list) {
      if (list) { genreParts = genreParts.concat(list); }
    });
    var author = '';
    var floating = R_selFirst(infoCard, 'div.item.floating');
    if (floating) {
      author = floating.text();
    } else {
      author = infoText(infoCard, 'i.fa-circle-user') || '';
    }
    return {
      key: mangaKey,
      title: name + noPart + '(' + mediaCount + ')',
      coverUrl: '',
      author: author,
      artist: '',
      description: '',
      genre: genreParts.join(', '),
      status: 'completed',
    };
  },

  getChapterList: async function (mangaKey) {
    var url = R_abs(mangaKey);
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    var infoCard = R_selFirst(doc, 'div.info-card.photo-detail');
    var uploadAt = 0;
    if (infoCard) {
      var cal = infoText(infoCard, 'i.fa-calendar-days');
      if (cal) {
        uploadAt = parseDate(cal);
      }
    }
    if (!uploadAt) {
      var infos = R_sel(doc, 'div.tab-content > div.info-card div.text');
      for (var i = 0; i < infos.length; i++) {
        var m = DATE_RE.exec(infos[i].text());
        if (m) { uploadAt = parseDate(m[0]); break; }
      }
    }
    var nums = R_sel(doc, 'div.pager:first-of-type a.pager-num');
    var maxPage = 1;
    if (nums.length) {
      var last = parseInt(nums[nums.length - 1].text(), 10);
      if (!isNaN(last)) { maxPage = last; }
    }
    var basePageUrl = url.replace(/\\.html$/, '');
    var out = [];
    for (var p = maxPage; p >= 1; p--) {
      out.push({
        key: R_path(basePageUrl + '/' + p + '.html'),
        name: 'Page ' + p,
        chapterNumber: -1,
        dateUpload: uploadAt,
        pages: 0,
        sortOrder: out.length,
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, 'div.list.photo-items > div.item.photo-image');
    var imgs2 = R_sel(doc, 'div.list.amateur-items > div.item.amateur-image');
    var all = imgs.concat(imgs2);
    var pages = [];
    for (var i = 0; i < all.length; i++) {
      var u = styleUrl(R_selFirst(all[i], 'div.img'));
      if (!u) { continue; }
      if (u.indexOf('_600x0.webp') !== -1) {
        u = u.replace('_600x0.webp', '.jpg');
      }
      pages.push({ index: pages.length, url: u });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
