// Gattsu theme engine (pt hentai one-shot galleries: hentaiseason, hentaitokyo, universohentai)
// Simple WP-family scraper; each "manga" is a single-gallery post.
export const runtime = 'wp';

function strOverride(kt, name) {
  const re = new RegExp(`(?:override\\s+)?(?:open\\s+)?(?:fun|val)\\s+${name}\\s*(?:\\(\\))?\\s*(?::\\s*String\\??\\s*)?=\\s*("([^"]*)"((?:\\s*\\+\\s*"[^"]*")*))`, 'm');
  const m = kt.match(re);
  if (!m) return undefined;
  const parts = m[1].match(/"([^"]*)"/g) || [];
  let v = parts.map(p => p.slice(1, -1)).join('');
  // strip jsoup-only bits the host selector engine can't handle
  v = v.replace(/\[href\^=\$baseUrl\]/g, '');
  v = v.replace(/:not\(:has\([^)]*\)\)/g, '');
  v = v.replace(/:has\([^)]*\)/g, '');
  return v;
}

function fnSelect(kt, fnName, assignRe) {
  // extract first select("...") argument matching assignRe within fnName body
  const idx = kt.indexOf(`fun ${fnName}`);
  if (idx < 0) return undefined;
  const body = kt.slice(idx, idx + 2500);
  const m = body.match(assignRe);
  return m ? m[1] : undefined;
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    latestSelector: 'div.meio div.lista ul li a',
    latestTitleSel: 'span.thumb-titulo',
    latestImgSel: 'span.thumb-imagem img.wp-post-image',
    detailBoxSel: 'div.meio div.post-box',
    detailTitleSel: 'h1.post-titulo',
    detailAuthorSel: 'ul.post-itens li:contains(Artista) a',
    detailGenreSel: 'ul.post-itens li:contains(Tags) a',
    detailDescSel: 'div.post-texto p',
    detailCoverSel: 'div.post-capa > img.wp-post-image',
    chapterSel: 'div.meio div.post-box:first-of-type',
    chapterLinkSel: '',
    pageSel: 'div.meio div.post-box ul.post-fotos li a > img, div.meio div.post-box.listaImagens div.galeriaHtml img',
  };

  const latest = strOverride(kt, 'latestUpdatesSelector');
  if (latest) config.latestSelector = latest;
  const titleSel = fnSelect(kt, 'latestUpdatesFromElement', /title\s*=\s*element\.select\("([^"]+)"\)/);
  if (titleSel) config.latestTitleSel = titleSel;
  const imgSel = fnSelect(kt, 'latestUpdatesFromElement', /thumbnail_url\s*=\s*element\.select\("([^"]+)"\)/);
  if (imgSel) config.latestImgSel = imgSel;

  const box = fnSelect(kt, 'mangaDetailsParse', /postBox\s*=\s*document\.select\("([^"]+)"\)/);
  if (box) config.detailBoxSel = box;
  const author = fnSelect(kt, 'mangaDetailsParse', /author\s*=\s*postBox\.select\("([^"]+)"\)/);
  if (author) config.detailAuthorSel = author;
  const genre = fnSelect(kt, 'mangaDetailsParse', /genre\s*=\s*postBox\.select\("([^"]+)"\)/);
  if (genre) config.detailGenreSel = genre;
  const desc = fnSelect(kt, 'mangaDetailsParse', /description\s*=\s*postBox\.select\("([^"]+)"\)/);
  if (desc) config.detailDescSel = desc;
  const cover = fnSelect(kt, 'mangaDetailsParse', /thumbnail_url\s*=\s*postBox\.select\("([^"]+)"\)/);
  if (cover) config.detailCoverSel = cover;

  const chSel = strOverride(kt, 'chapterListSelector');
  if (chSel) config.chapterSel = chSel;
  const chIdx = kt.indexOf('fun chapterFromElement');
  if (chIdx >= 0) {
    const m = kt.slice(chIdx, chIdx + 1500).match(/setUrlWithoutDomain\(element\.selectFirst\("([^"]+)"\)/);
    if (m) config.chapterLinkSel = m[1];
  }
  const pageSel = strOverride(kt, 'pageListSelector');
  if (pageSel) config.pageSel = pageSel;

  if (/rateLimit\(/.test(kt)) warnings.push('rateLimit approximated (no throttling in plugin)');
  if (/:has\(/.test(kt)) warnings.push(':has() selectors stripped for host compatibility');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: gattsu)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function withoutSize(u) {
  return String(u || '').replace(/-\\d+x\\d+\\./g, '.');
}

function parseList(doc) {
  var items = R_sel(doc, CFG.latestSelector);
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var tEl = R_selFirst(el, CFG.latestTitleSel);
    if (!tEl) { continue; }
    var href = el.attr('href') || el.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, CFG.latestImgSel);
    out.push({
      key: R_path(href),
      title: tEl.text(),
      coverUrl: withoutSize(R_img(img))
    });
  }
  return out;
}

async function listManga(page, query) {
  var url;
  if (query) {
    url = BASE + '/page/' + page + '/?s=' + encodeURIComponent(query) + '&post_type=post';
  } else {
    url = page > 1 ? BASE + '/page/' + page : BASE + '/';
  }
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var out = parseList(doc);
  var hasNext = !!R_selFirst(doc, 'ul.paginacao li.next > a, .pagination .next a, a.next');
  return { mangas: out, hasNextPage: hasNext };
}

function metaDate(doc) {
  var m = R_selFirst(doc, 'meta[property=article:published_time]');
  return m ? R_date(m.attr('content')) : 0;
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga(page, '');
  },

  getSearchManga: async function (page, query) {
    return listManga(page, query || ' ');
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var box = R_selFirst(doc, CFG.detailBoxSel);
    var title = '';
    if (box) {
      var t = R_selFirst(box, CFG.detailTitleSel);
      if (t) { title = t.text(); }
    }
    function joinTexts(sel) {
      var els = R_sel(box || doc, sel);
      var out = [];
      for (var i = 0; i < els.length; i++) {
        var t2 = els[i].text();
        if (t2) { out.push(t2); }
      }
      return out.join(', ');
    }
    var desc = '';
    var descEls = R_sel(box || doc, CFG.detailDescSel);
    var parts = [];
    for (var i = 0; i < descEls.length; i++) {
      var pt = descEls[i].text();
      if (pt) { parts.push(pt); }
    }
    desc = parts.join('\\n\\n').replace('Sinopse :', '').trim();
    var cover = withoutSize(R_img(R_selFirst(box || doc, CFG.detailCoverSel)));
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: joinTexts(CFG.detailAuthorSel),
      description: desc,
      genre: joinTexts(CFG.detailGenreSel),
      status: 'completed'
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var date = metaDate(doc);
    var els = R_sel(doc, CFG.chapterSel);
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var href = mangaKey;
      if (CFG.chapterLinkSel) {
        var link = R_selFirst(els[i], CFG.chapterLinkSel);
        if (link) { href = link.absUrl('href') || link.attr('href'); }
      }
      out.push({
        key: R_path(href),
        name: 'Capítulo único',
        chapterNumber: -1,
        dateUpload: date,
        pages: 0,
        sortOrder: 0
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, CFG.pageSel);
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var node = els[i];
      var img = node.attr('src') || node.attr('data-src') ? node : R_selFirst(node, 'img');
      if (!img) { continue; }
      var u = withoutSize(R_img(img));
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
