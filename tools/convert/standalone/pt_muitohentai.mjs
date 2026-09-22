// pt/muitohentai — HTML scraper (muitohentai.com)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: [':contains selectors approximated manually'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone scraper)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};

function hasNextPage(doc) {
  var links = R_sel(doc, '#paginacao a');
  if (links.length === 0) { return false; }
  var last = links[links.length - 1];
  return last.text().indexOf('»') >= 0;
}

function parseArchive(doc) {
  var out = [];
  var items = R_sel(doc, '#archive-content article.tvshows');
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var t = R_selFirst(el, 'div.data h3 a');
    var link = R_selFirst(el, 'a');
    if (!t || !link) { continue; }
    var href = link.absUrl('href') || t.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, 'div.poster img');
    out.push({ key: R_path(href), title: t.text(), coverUrl: img ? img.absUrl('src') : '' });
  }
  return { mangas: out, hasNextPage: hasNextPage(doc) };
}

function findBackground(doc, needle) {
  var els = R_sel(doc, 'div.backgroundpost');
  for (var i = 0; i < els.length; i++) {
    if (els[i].text().indexOf(needle) >= 0) { return els[i]; }
  }
  return null;
}

module.exports = {
  getPopularManga: async function (page) {
    var u = page === 1 ? BASE + '/mangas/' : BASE + '/mangas/' + (page - 1);
    var text = await $.http.get(u, { Referer: page === 1 ? BASE : BASE + '/mangas/' + (page - 1) });
    return parseArchive($.html.parse(text));
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/buscar-manga/?q=' + encodeURIComponent(query));
    return parseArchive($.html.parse(text));
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), { Referer: BASE + '/' });
    var doc = $.html.parse(text);
    var author = '';
    var divs = R_sel(doc, 'div');
    for (var i = 0; i < divs.length; i++) {
      var strongs = R_sel(divs[i], 'strong');
      var hasAutor = false;
      for (var s = 0; s < strongs.length; s++) {
        if (strongs[s].text().indexOf('Autor') >= 0) { hasAutor = true; break; }
      }
      if (hasAutor) { author = R_ownText(divs[i]) || ''; break; }
    }
    var genres = [];
    var gels = R_sel(doc, 'a.genero_btn');
    for (var g = 0; g < gels.length; g++) {
      var gt = gels[g].text();
      if (gt) { genres.push(gt.charAt(0).toUpperCase() + gt.slice(1)); }
    }
    var desc = '';
    var sinopse = findBackground(doc, 'Sinopse');
    if (sinopse) { desc = R_ownText(sinopse) || ''; }
    var img = R_selFirst(doc, '#capaAnime img');
    return {
      key: mangaKey,
      title: '',
      coverUrl: img ? img.absUrl('src') : '',
      author: author,
      description: desc,
      genre: genres.join(', '),
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), { Referer: BASE + '/' });
    var doc = $.html.parse(text);
    var holder = findBackground(doc, 'Capítulos de');
    var out = [];
    if (holder) {
      var links = R_sel(holder, 'h3 > a');
      for (var i = 0; i < links.length; i++) {
        var href = links[i].absUrl('href');
        if (!href) { continue; }
        out.push({
          key: R_path(href),
          name: R_ownText(links[i]) || links[i].text(),
          chapterNumber: -1,
          dateUpload: 0,
          pages: 0,
          sortOrder: i
        });
      }
    }
    return out.reverse();
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), { Referer: R_abs(chapterKey).split('/').slice(0, -1).join('/') });
    var m = text.match(/var arr = ([\\s\\S]*?);/);
    var out = [];
    if (m) {
      try {
        var arr = $.json.parse(m[1]);
        for (var i = 0; i < arr.length; i++) {
          if (arr[i]) { out.push({ index: out.length, url: R_abs(String(arr[i])) }); }
        }
      } catch (e) { /* ignore */ }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
