// pt/mangadash — HTML + JSON API (mangadash.org)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['PDF-only chapters not supported (images only); login/CSRF +18 flow not ported; filters not ported'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API+HTML)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Accept: 'application/json, text/plain, */*', Referer: BASE + '/' };

function parseList(text) {
  var j = $.json.parse(text);
  var list = j.items || [];
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var it = list[i];
    out.push({
      key: '/manga/' + it.id + '-' + it.slug,
      title: it.nome || '',
      coverUrl: it.capa || ''
    });
  }
  return { mangas: out, hasNextPage: !!(j.pagination && j.pagination.has_next) };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/api/mangas/list?page=' + page + '&q=&sort=populares&categoria=&status=&ano=&plus18=', HDRS);
    return parseList(text);
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/api/mangas/list?page=' + page + '&q=' + encodeURIComponent(query || '') + '&sort=recentes&categoria=&status=&ano=&plus18=';
    var text = await $.http.get(u, HDRS);
    return parseList(text);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var stats = '';
    var statEls = R_sel(doc, '.stats-row .stat-item');
    for (var i = 0; i < statEls.length; i++) { stats += ' ' + statEls[i].text(); }
    var status = '';
    if (/lançamento/i.test(stats)) { status = 'ongoing'; }
    else if (/concluído/i.test(stats)) { status = 'completed'; }
    else if (/hiato/i.test(stats)) { status = 'hiatus'; }
    var genres = [];
    var gels = R_sel(doc, '.manga-tags a.tag');
    for (var g = 0; g < gels.length; g++) {
      var authorEl = R_selFirst(gels[g], '.tag-author');
      if (gels[g].selectFirst('.tag-author')) { continue; }
      genres.push(gels[g].text());
    }
    return {
      key: mangaKey,
      title: R_ownText(R_selFirst(doc, '.neon-title')) || '',
      coverUrl: '',
      author: R_ownText(R_selFirst(doc, '.tag-author')) || '',
      description: R_ownText(R_selFirst(doc, '.manga-description')) || '',
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var rows = R_sel(doc, '.chapters-scroll-container .chapter-row');
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var el = rows[i];
      var href = el.absUrl('href');
      if (!href) { href = R_abs(el.attr('href')); }
      if (!href) { continue; }
      var nameEl = R_selFirst(el, '.chapter-title-group h4');
      var name = nameEl ? nameEl.text() : '';
      var dateText = '';
      var metas = R_sel(el, '.chapter-meta-info');
      for (var m = 0; m < metas.length; m++) {
        if (metas[m].selectFirst('.fa-calendar')) { dateText = metas[m].text(); break; }
      }
      var t = 0;
      var dm = dateText.match(/(\\d{2})\\/(\\d{2})\\/(\\d{4})/);
      if (dm) { t = Date.parse(dm[3] + '-' + dm[2] + '-' + dm[1]) || 0; }
      var numMatch = name.split('Capítulo').pop().trim();
      var num = parseFloat(numMatch);
      out.push({
        key: R_path(href),
        name: name,
        chapterNumber: isNaN(num) ? -1 : num,
        dateUpload: t,
        pages: 0,
        sortOrder: 0,
        _num: isNaN(num) ? -1 : num
      });
    }
    out.sort(function (a, b) { return (b._num - a._num) || (b.name < a.name ? -1 : 1); });
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; delete out[j]._num; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey), HDRS);
    var doc = $.html.parse(text);
    var script = R_selFirst(doc, 'script#chapterViewerData');
    if (!script) { return []; }
    var dto = $.json.parse(script.html());
    var images = dto.images || dto.imagens || dto.pages || [];
    var out = [];
    for (var i = 0; i < images.length; i++) {
      if (images[i]) { out.push({ index: out.length, url: images[i] }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
