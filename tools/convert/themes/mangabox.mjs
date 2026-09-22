// MangaBox theme engine (en: mangabat, mangakakalot, manganelo) — classic mangabox with JSON chapter API
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText || '';
  const warnings = [];
  const config = { fixIdSlug: false };
  const src = (ctx.gradle && ctx.gradle.sources && ctx.gradle.sources[0]) || {};
  const base = String(src.baseUrl || '');
  if (/mangakakalot/i.test(base) || /titleToSlug/.test(kt)) config.fixIdSlug = true;
  warnings.push('genre/sort/status browse filters not supported by host; text search only');
  warnings.push('merge-split-images preference not supported (host cannot stitch images)');
  warnings.push('alternate-CDN fallback interceptor not supported; first CDN used');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mangabox)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function titleToSlug(title) {
  return String(title || '')
    .toLowerCase()
    .replace(/[^a-z0-9\\s-]/g, '')
    .trim()
    .replace(/[\\s-]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function mangaSlugFromKey(mangaKey, title) {
  var slug = String(mangaKey).split('/').pop() || '';
  if (CFG.fixIdSlug && /^[a-z]{2}\\d+$/.test(slug)) {
    return titleToSlug(title) || slug;
  }
  return slug;
}

function normalizeSearchQuery(query) {
  var str = String(query || '').toLowerCase();
  str = str.replace(/[àáạảãâầấậẩẫăằắặẳẵ]/g, 'a');
  str = str.replace(/[èéẹẻẽêềếệểễ]/g, 'e');
  str = str.replace(/[ìíịỉĩ]/g, 'i');
  str = str.replace(/[òóọỏõôồốộổỗơờớợởỡ]/g, 'o');
  str = str.replace(/[ùúụủũưừứựửữ]/g, 'u');
  str = str.replace(/[ỳýỵỷỹ]/g, 'y');
  str = str.replace(/đ/g, 'd');
  str = str.replace(/[!@%^*()+=<>?\\/,.:;' "&#\\[\\]~$|-]/g, '_');
  str = str.replace(/_+/g, '_');
  str = str.replace(/^_+|_+$/g, '');
  return str;
}

function extractArray(content, re) {
  var m = re.exec(content);
  if (!m) { return []; }
  var parts = m[1].split(',');
  var out = [];
  for (var i = 0; i < parts.length; i++) {
    var v = parts[i].trim().replace(/^"|"$/g, '').replace(/\\\\\\//g, '/').replace(/\\/+$/, '');
    if (v) { out.push(v); }
  }
  return out;
}

function parseEntries(doc, selector) {
  var items = R_sel(doc, selector);
  var mangas = [];
  for (var i = 0; i < items.length; i++) {
    var link = R_selFirst(items[i], 'h3 a');
    var img = R_selFirst(items[i], 'img');
    if (!link) { continue; }
    var href = link.absUrl('href') || link.attr('href') || '';
    var key = R_path(href);
    var slug = key.split('/').pop() || '';
    var title = link.text();
    if (CFG.fixIdSlug && /^[a-z]{2}\\d+$/.test(slug)) {
      slug = titleToSlug(title) || slug;
    }
    mangas.push({
      key: '/manga/' + slug,
      title: title,
      coverUrl: img ? (img.absUrl('src') || img.attr('src') || '') : ''
    });
  }
  return mangas;
}

function hasNextPageGroup(doc) {
  if (R_selFirst(doc, 'div.group_page')) { return true; }
  var next = R_selFirst(doc, 'div.group-page a:not([href]) + a');
  if (!next) { return false; }
  return next.text().indexOf('Last') < 0;
}

function findLabeledContainer(info, label) {
  var lis = R_sel(info, 'li');
  for (var i = 0; i < lis.length; i++) {
    if (lis[i].text().toLowerCase().indexOf(label) >= 0) { return lis[i]; }
  }
  var tds = R_sel(info, 'td');
  for (var t = 0; t < tds.length; t++) {
    if (R_ownText(tds[t]).toLowerCase().indexOf(label) >= 0) {
      var next = R_selFirst(tds[t], ':scope + td');
      if (next) { return next; }
    }
  }
  return null;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/manga-list/hot-manga?page=' + page);
    var doc = $.html.parse(text);
    var mangas = parseEntries(doc, 'div.truyen-list > div.list-truyen-item-wrap:has(a[data-id]), div.comic-list > .list-comic-item-wrap:has(a[data-id])');
    return { mangas: mangas, hasNextPage: hasNextPageGroup(doc) };
  },

  getSearchManga: async function (page, query) {
    var url = BASE + '/search/story/' + normalizeSearchQuery(query) + '?page=' + page;
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    var mangas = parseEntries(doc, '.panel_story_list .story_item, div.list-truyen-item-wrap, div.list-comic-item-wrap');
    var hasNextPage = !!R_selFirst(doc, 'a.page_select + a:not(.page_last), a.page-select + a:not(.page-last)');
    return { mangas: mangas, hasNextPage: hasNextPage };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/manga\\//, '').replace(/^\\/+/, '');
    var text = await $.http.get(BASE + '/manga/' + slug);
    var doc = $.html.parse(text);
    var info = R_selFirst(doc, 'div.manga-info-top, div.panel-story-info');
    var title = '', author = '', genre = '', status = 'UNKNOWN', cover = '';
    if (info) {
      var titleEl = R_selFirst(info, 'h1, h2');
      title = titleEl ? titleEl.text() : '';
      if (CFG.fixIdSlug && /^[a-z]{2}\\d+$/.test(slug)) {
        var fixed = titleToSlug(title);
        if (fixed) { slug = fixed; }
      }
      var authorContainer = findLabeledContainer(info, 'author');
      if (authorContainer) {
        var authorLinks = R_sel(authorContainer, 'a');
        var names = [];
        for (var a = 0; a < authorLinks.length; a++) { names.push(authorLinks[a].text()); }
        author = names.join(', ');
      }
      var statusContainer = findLabeledContainer(info, 'status');
      if (statusContainer) {
        var st = statusContainer.text();
        if (st.indexOf('Ongoing') >= 0) { status = 'ONGOING'; }
        else if (st.indexOf('Completed') >= 0) { status = 'COMPLETED'; }
      }
      var genreContainer = findLabeledContainer(info, 'genres');
      if (genreContainer) {
        var genreLinks = R_sel(genreContainer, 'a');
        var gs = [];
        for (var g = 0; g < genreLinks.length; g++) { gs.push(genreLinks[g].text()); }
        genre = gs.join(', ');
      }
    }
    var desc = '';
    var descEl = R_selFirst(doc, 'div#noidungm, div#panel-story-info-description, div#contentBox');
    if (descEl) {
      desc = R_ownText(descEl);
      if (title) {
        desc = desc.replace(new RegExp('^' + title.replace(/[.*+?^\${}()|[\\]\\\\]/g, '\\\\$&') + ' summary\\\\s*:?\\\\s*'), '');
      }
    }
    var coverEl = R_selFirst(doc, 'div.manga-info-pic img, span.info-image img');
    if (coverEl) { cover = coverEl.absUrl('src') || coverEl.attr('src') || ''; }
    var altEl = R_selFirst(doc, '.story-alternative, tr:has(.info-alternative) h2');
    if (altEl) {
      var alt = R_ownText(altEl);
      if (alt) {
        desc = desc ? desc + '\\n\\nAlternative Name: ' + alt : 'Alternative Name: ' + alt;
      }
    }
    return {
      key: '/manga/' + slug,
      title: title,
      coverUrl: cover,
      author: author,
      description: desc,
      genre: genre,
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = mangaSlugFromKey(mangaKey, '');
    var text = await $.http.get(BASE + '/api/manga/' + encodeURIComponent(slug) + '/chapters?limit=-1');
    var api = JSON.parse(text);
    if (!api.success || !api.data || !api.data.chapters) { return []; }
    var chapters = [];
    var list = api.data.chapters;
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      if (!c.chapterSlug) { continue; }
      var date = 0;
      if (c.updatedAt) {
        var v = Date.parse(c.updatedAt);
        if (!isNaN(v)) { date = Math.floor(v / 1000); }
      }
      chapters.push({
        key: '/manga/' + slug + '/' + c.chapterSlug,
        name: c.chapterName || 'Chapter',
        dateUpload: date
      });
    }
    // API returns newest first; host expects oldest first
    chapters.reverse();
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(BASE + chapterKey);
    var doc = $.html.parse(text);
    var scripts = R_sel(doc, 'script');
    var content = '';
    for (var i = 0; i < scripts.length; i++) {
      var body = scripts[i].html();
      if (body && body.indexOf('cdns =') >= 0) { content += body + '\\n'; }
    }
    var cdns = extractArray(content, /cdns\\s*=\\s*\\[([^\\]]+)\\]/)
      .concat(extractArray(content, /backupImage\\s*=\\s*\\[([^\\]]+)\\]/));
    var chapterImages = extractArray(content, /chapterImages\\s*=\\s*\\[([^\\]]+)\\]/);
    var pages = [];
    if (chapterImages.length > 0 && cdns.length > 0) {
      for (var p = 0; p < chapterImages.length; p++) {
        var path = '/' + chapterImages[p];
        while (path.indexOf('//') >= 0) { path = path.replace('//', '/'); }
        pages.push(cdns[0] + path);
      }
      return pages;
    }
    var imgs = R_sel(doc, 'div.container-chapter-reader > img');
    for (var j = 0; j < imgs.length; j++) {
      var src = imgs[j].absUrl('src') || imgs[j].attr('src') || '';
      if (src) { pages.push(src); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { 'Referer': BASE + '/' };
  }
};
`;
}
