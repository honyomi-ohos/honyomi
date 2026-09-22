// ja/twi4 — TWI4 (sai-zen-sen Jsoup scraper; single-page chapters)
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
var HOST = (BASE.match(/^(https?:\/\/[^\/]+)/) || [ '', BASE ])[1];

function isCompletedEntry(sec) {
  var lis = R_sel(sec, 'ul li');
  var last = lis.length ? lis[lis.length - 1] : null;
  return !!(last && R_selFirst(last, 'em.is-completed'));
}

// #lineup_recent > div > section, plus #lineup > div > section minus .zadankai / [id]
function catalogSections(doc) {
  var secs = R_sel(doc, '#lineup_recent > div > section');
  var lineup = R_sel(doc, '#lineup > div > section');
  for (var i = 0; i < lineup.length; i++) {
    var el = lineup[i];
    var cls = el.attr('class') || '';
    if (cls.indexOf('zadankai') >= 0) { continue; }
    if (el.attr('id')) { continue; }
    secs.push(el);
  }
  return secs;
}

function parseCatalog(doc) {
  var secs = catalogSections(doc);
  var out = [];
  for (var i = 0; i < secs.length; i++) {
    var sec = secs[i];
    var a = R_selFirst(sec, 'div.hgroup > h3 > a');
    if (!a) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(sec, 'div.figgroup > figure > a > img');
    out.push({
      key: R_path(href),
      title: a.text(),
      coverUrl: img ? img.absUrl('src') : '',
      author: H_firstText(sec, 'div.hgroup > p'),
      completed: isCompletedEntry(sec),
      hrefAttr: a.attr('href') || ''
    });
  }
  return out;
}

function parseDetails(raw, doc, mangaKey) {
  var tm = raw.match(/<title>([\s\S]*?)<\/title>/);
  var pageTitle = tm ? tm[1].trim() : '';
  var m = pageTitle.match(/^『(.+)』.+ \| ツイ４ \| 最前線$/);
  var title = m ? m[1] : pageTitle;
  var cover = R_selFirst(doc, '#introduction > header > div > h2 > img');
  var author = '';
  var artist = '';
  var staffs = R_sel(doc, '#introduction > div > section > header > div > h3');
  for (var i = 0; i < staffs.length; i++) {
    var small = R_selFirst(staffs[i], 'small');
    var span = R_selFirst(staffs[i], 'span');
    if (!small || !span) { continue; }
    var role = String(small.text()).replace('：', '').trim();
    var name = span.text();
    if (role === '作者') { author = name; artist = name; }
    else if (role === '原作') { author = name; }
    else if (role === '漫画') { artist = name; }
  }
  return {
    key: String(mangaKey),
    title: title,
    coverUrl: cover ? cover.absUrl('src') : '',
    author: author,
    artist: artist,
    description: H_firstText(doc, '#introduction > div > div > p'),
    genre: '',
    status: 'unknown'
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var doc = await H_doc(BASE);
    var out = parseCatalog(doc);
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var q = String(query || '');
    if (q.indexOf('https://') === 0) {
      var u = q.replace(/\/+$/, '') + '/';
      var mm = u.match(/^https?:\/\/([^\/]+)(\/.*)$/);
      if (!mm || mm[1].indexOf('sai-zen-sen.jp') < 0) { throw new Error('Unsupported url'); }
      var segs = mm[2].replace(/^\//, '').split('/');
      q = 'SLUG:' + (segs[2] || '');
    }
    if (q.indexOf('SLUG:') === 0) {
      var slug = q.slice(5);
      if (/html$/.test(slug) || slug.indexOf('zadankai') === 0 || slug.indexOf('others') === 0) {
        return { mangas: [], hasNextPage: false };
      }
      var searchUrl = BASE + '/' + slug + '/';
      var raw = await H_get(searchUrl);
      var doc = $.html.parse(raw);
      var details = parseDetails(raw, doc, R_path(searchUrl));
      return { mangas: [details], hasNextPage: false };
    }
    var doc2 = await H_doc(BASE);
    var all = parseCatalog(doc2);
    var lower = q.toLowerCase();
    var filtered = [];
    for (var i = 0; i < all.length; i++) {
      if (all[i].title.toLowerCase().indexOf(lower) >= 0) { filtered.push(all[i]); }
    }
    return { mangas: filtered, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var raw = await H_get(R_abs(mangaKey));
    var doc = $.html.parse(raw);
    var details = parseDetails(raw, doc, mangaKey);
    var home = await H_doc(BASE);
    var all = parseCatalog(home);
    var status = 'ongoing';
    for (var i = 0; i < all.length; i++) {
      if (all[i].hrefAttr === mangaKey) {
        status = all[i].completed ? 'completed' : 'ongoing';
        break;
      }
    }
    details.status = status;
    return details;
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey));
    var items = R_sel(doc, '#backnumbers > div > ul > li');
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var a = R_selFirst(items[i], 'a');
      if (!a) { continue; }
      var href = a.absUrl('href');
      if (!href) { continue; }
      var text = a.text();
      var m = text.match(/^(.+)『(.+)』 #(\d+)$/);
      var chap = {
        key: R_path(href),
        name: text,
        chapterNumber: 0,
        dateUpload: 0,
        pages: 1,
        sortOrder: 0
      };
      if (m) {
        chap.chapterNumber = parseFloat(m[3]);
        chap.name = parseInt(m[3], 10) + ' - ' + m[2];
      }
      out.push(chap);
    }
    out.sort(function (x, y) { return x.chapterNumber - y.chapterNumber; });
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(R_abs(chapterKey));
    var page = R_selFirst(doc, 'article.comic');
    if (!page) { return []; }
    var img = R_selFirst(page, 'div > div > p > img');
    if (!img) { return []; }
    var u = img.absUrl('src');
    return u ? [{ index: 0, url: u }] : [];
  },

  imageHeaders: function () { return { Referer: HOST + '/' }; }
};
`;
  return wrap(manifest, body);
}
