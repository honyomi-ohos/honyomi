// pt/mundohentai — WordPress scraper (mundohentai.com)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['tag filter not ported; "Tufos"/Legendado exclusions approximated'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone WP scraper)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};

function parseList(doc, isSearch) {
  var out = [];
  var items = R_sel(doc, 'div.lista > ul > li div.thumb-conteudo');
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var txt = el.text();
    if (txt.indexOf('Tufos') >= 0) { continue; }
    if (isSearch) {
      var selo = R_selFirst(el, 'span.selo-tipo');
      if (selo && selo.text().indexOf('Legendado') >= 0) { continue; }
    }
    var link = R_selFirst(el, 'a:has(span.thumb-imagem)');
    if (!link) {
      var all = R_sel(el, 'a');
      for (var a = 0; a < all.length; a++) {
        if (all[a].selectFirst('span.thumb-imagem')) { link = all[a]; break; }
      }
    }
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href || href.indexOf(BASE) !== 0) { continue; }
    var title = R_selFirst(el, 'span.thumb-titulo');
    var img = R_selFirst(el, 'img.attachment-post-thumbnail');
    out.push({ key: R_path(href), title: title ? title.text() : '', coverUrl: img ? img.absUrl('src') : '' });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, 'ul.paginacao li.next') };
}

function findLi(doc, needle) {
  var lis = R_sel(doc, 'ul.post-itens li');
  for (var i = 0; i < lis.length; i++) {
    if (lis[i].text().indexOf(needle) >= 0) { return lis[i]; }
  }
  return null;
}

module.exports = {
  getPopularManga: async function (page) {
    var u = page === 1 ? BASE + '/category/doujinshi/' : BASE + '/category/doujinshi/page/' + page + '/';
    var referer = page === 1 ? BASE : BASE + '/category/doujinshi/page/' + (page - 1) + '/';
    var text = await $.http.get(u, { Referer: referer });
    return parseList($.html.parse(text), false);
  },

  getSearchManga: async function (page, query) {
    if (query) {
      var text = await $.http.get(BASE + '/?s=' + encodeURIComponent(query), { Referer: BASE });
      return parseList($.html.parse(text), true);
    }
    return module.exports.getPopularManga(page);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), { Referer: BASE });
    var doc = $.html.parse(text);
    var post = R_selFirst(doc, 'div.post-box');
    var author = '';
    var genres = [];
    var description = '';
    if (post) {
      var authorLi = findLi(post, 'Artista:');
      if (authorLi) {
        var aLinks = R_sel(authorLi, 'a');
        var names = [];
        for (var i = 0; i < aLinks.length; i++) { names.push(aLinks[i].text()); }
        author = names.join(', ');
      }
      var tagLi = findLi(post, 'Tags:');
      if (tagLi) {
        var tLinks = R_sel(tagLi, 'a');
        for (var t = 0; t < tLinks.length; t++) { genres.push(tLinks[t].text()); }
      }
      var corLi = findLi(post, 'Cor:');
      if (corLi) { description = corLi.text(); }
    }
    var img = R_selFirst(doc, 'div.post-capa img');
    return {
      key: mangaKey,
      title: '',
      coverUrl: img ? img.absUrl('src') : '',
      author: author,
      description: description,
      genre: genres.join(', '),
      status: 'completed'
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), { Referer: BASE });
    var doc = $.html.parse(text);
    var tabs = R_sel(doc, 'div.listaImagens div.galeriaTab');
    var out = [];
    if (tabs.length > 0) {
      for (var i = 0; i < tabs.length; i++) {
        var chapterId = tabs[i].attr('data-id');
        var titleEl = R_selFirst(tabs[i], 'div.galeriaTabTitulo');
        var title = titleEl ? titleEl.text() : '';
        out.push({
          key: mangaKey + '#' + chapterId,
          name: 'Capítulo ' + chapterId + (title ? ' - ' + title : ''),
          chapterNumber: parseFloat(chapterId) || -1,
          dateUpload: 0,
          pages: 0,
          sortOrder: i
        });
      }
      return out.reverse();
    }
    return [{
      key: mangaKey,
      name: 'Capítulo',
      chapterNumber: 1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var url = R_abs(chapterKey.split('#')[0]);
    var chapterId = chapterKey.indexOf('#') >= 0 ? chapterKey.split('#').pop() : '';
    var text = await $.http.get(url, { Referer: BASE });
    var doc = $.html.parse(text);
    var sel = chapterId ? 'div.listaImagens #galeria-' + chapterId + ' img' : 'div.listaImagens ul.post-fotos img';
    var imgs = R_sel(doc, sel);
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src') || R_abs(imgs[i].attr('src'));
      if (u) { out.push({ index: out.length, url: u }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
