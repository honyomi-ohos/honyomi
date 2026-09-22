// en/mangack — WordPress REST (wp-json/wp/v2/manga) + HTML details/chapters
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['X-WP-TotalPages header unavailable (host returns text only); hasNext approximated by page size', 'filters not ported'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = BASE + '/wp-json/wp/v2/manga';
var PAGE_SIZE = 24;
var HDRS = { Referer: BASE + '/' };

function decodeEntities(s) {
  return String(s || '')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&(?:apos|#0?39);/g, "'")
    .replace(/&nbsp;/g, ' ').replace(/&hellip;/g, '\\u2026')
    .replace(/&mdash;/g, '\\u2014').replace(/&ndash;/g, '\\u2013')
    .replace(/&(?:rsquo|#8217);/g, "'").replace(/&(?:lsquo|#8216);/g, "'")
    .replace(/&(?:rdquo|#8221);/g, '"').replace(/&(?:ldquo|#8220);/g, '"')
    .replace(/&#(\\d+);/g, function (m, n) { return String.fromCharCode(parseInt(n, 10)); });
}

function listUrl(page, query) {
  var u = API + '?page=' + page + '&per_page=' + PAGE_SIZE + '&_embed=wp:featuredmedia&orderby=date&order=desc';
  if (query) { u += '&search=' + encodeURIComponent(query.trim()); }
  return u;
}

function parseList(text) {
  var list = $.json.parse(text);
  var mangas = [];
  for (var i = 0; i < list.length; i++) {
    var d = list[i];
    var cover = '';
    try { cover = (d._embedded['wp:featuredmedia'][0].source_url) || ''; } catch (e) { cover = ''; }
    mangas.push({ key: R_path(d.link), title: decodeEntities(d.title && d.title.rendered), coverUrl: cover });
  }
  return { mangas: mangas, hasNextPage: list.length >= PAGE_SIZE };
}

function meta(html, prop) {
  var m = new RegExp('<meta[^>]+property="' + prop + '"[^>]+content="([^"]*)"').exec(html) ||
    new RegExp('<meta[^>]+content="([^"]*)"[^>]+property="' + prop + '"').exec(html);
  return m ? m[1] : '';
}

function humanize(slug) {
  return String(slug || '').split('-').filter(Boolean).map(function (w) {
    return w.charAt(0).toUpperCase() + w.slice(1);
  }).join(' ');
}

function statusMap(slug) {
  var v = String(slug || '').toLowerCase();
  if (['ongoing', 'publishing', 'updating'].indexOf(v) >= 0) { return 'ongoing'; }
  if (['completed', 'complete', 'finished'].indexOf(v) >= 0) { return 'completed'; }
  if (['hiatus', 'on-hiatus', 'on-hold'].indexOf(v) >= 0) { return 'hiatus'; }
  if (['cancelled', 'canceled', 'dropped'].indexOf(v) >= 0) { return 'cancelled'; }
  return '';
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(listUrl(page, ''), HDRS));
  },

  getSearchManga: async function (page, query) {
    return parseList(await $.http.get(listUrl(page, query), HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var html = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(html);
    var article = R_selFirst(doc, 'article');
    var classes = article ? String(article.attr('class') || '').split(/\\s+/) : [];
    var type = '', statusSlug = '';
    var genreNames = [];
    for (var i = 0; i < classes.length; i++) {
      var c = classes[i];
      if (c.indexOf('comic-type-') === 0) { type = humanize(c.substring('comic-type-'.length)); }
      else if (c.indexOf('Genres-') === 0) { genreNames.push(humanize(c.substring('Genres-'.length))); }
      else if (c.indexOf('manga-status-') === 0) { statusSlug = c.substring('manga-status-'.length); }
    }
    var tEl = R_selFirst(doc, 'h1.entry-title');
    var title = tEl ? tEl.text() : meta(html, 'og:title').replace(/ mangack$/, '');
    var synopsis = meta(html, 'og:description');
    var desc = synopsis;
    if (article) {
      var rows = R_sel(article, 'table.infobox tr');
      for (var j = 0; j < rows.length; j++) {
        var cells = R_sel(rows[j], 'td, th');
        if (cells.length < 2) { continue; }
        var label = cells[0].text();
        var value = cells[1].text();
        if (value.indexOf('Warning') >= 0) { continue; }
        if (label === 'Alternative' && value) { desc += (desc ? '\\n\\n' : '') + 'Alternative: ' + value; }
        if (label === 'Realized in' && value) { desc += (desc ? '\\n\\n' : '') + 'Year: ' + value; }
      }
    }
    var genres = genreNames.slice();
    if (type) { genres.push(type); }
    return {
      key: mangaKey,
      title: title,
      coverUrl: meta(html, 'og:image') || R_img(article ? R_selFirst(article, 'figure img, .mediumthumbnail1 img') : null),
      author: '',
      description: desc,
      genre: genres.join(', '),
      status: statusMap(statusSlug)
    };
  },

  getChapterList: async function (mangaKey) {
    var html = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(html);
    var lis = R_sel(doc, 'ul.chapterslist li');
    var out = [];
    for (var i = 0; i < lis.length; i++) {
      var li = lis[i];
      var link = R_selFirst(li, 'a.title') || R_selFirst(li, 'a[href*="/chapter/"]');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var nm = R_ownText(link) || link.text();
      var dateEl = R_selFirst(li, '.entry-date');
      out.push({
        key: R_path(href),
        name: nm,
        chapterNumber: -1,
        dateUpload: dateEl ? R_date(dateEl.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // site lists newest first -> oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var slug = chapterKey.replace(/\\/$/, '').split('/').pop();
    var text = await $.http.get(BASE + '/wp-json/wp/v2/chapter?slug=' + encodeURIComponent(slug) + '&_fields=id,content', HDRS);
    var arr = $.json.parse(text);
    if (!arr || !arr.length) { return []; }
    var html = (arr[0].content && arr[0].content.rendered) || '';
    var skipRe = /(?:\\/wp-content\\/(?:themes|plugins)\\/|\\/(?:logo|icon|cropped|preroll|placeholder|loading|spinner|chainsaw)[^\\/]*\\.(?:png|jpe?g|webp|gif|svg))/i;
    var re = /<img[^>]+src=["']([^"']+)["']/g;
    var pages = [];
    var m;
    while ((m = re.exec(html)) !== null) {
      if (skipRe.test(m[1])) { continue; }
      pages.push({ index: pages.length, url: R_abs(m[1]) });
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
