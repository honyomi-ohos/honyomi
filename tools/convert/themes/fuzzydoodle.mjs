// FuzzyDoodle theme engine (ar/hentaislayer, fr/lelscanvf) — Tailwind-styled reader
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    latestFromHomePage: /override val latestFromHomePage = true/.test(kt),
    latestPath: '/latest',
  };
  const lp = kt.match(/latestPageRequest\(page: Int\) = GET\("\$baseUrl\/([^"?]*)\?page=\$page"/);
  if (lp) config.latestPath = '/' + lp[1].replace(/\$\{getLatestTypes\(\)\}/, 'manga');
  if (/rateLimit\(/.test(kt)) warnings.push('rateLimit approximated');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: fuzzydoodle)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function imgAttr(el) {
  if (!el) { return ''; }
  if (el.attr('srcset')) { return R_abs(el.attr('srcset').split(' ')[0]); }
  var v = el.attr('data-cfsrc') || el.attr('data-src') || el.attr('data-lazy-src');
  if (v) { return R_abs(v); }
  return el.absUrl('src') || R_abs(el.attr('src'));
}

function parseCards(doc) {
  var items = R_sel(doc, 'div#card-real');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var a = R_selFirst(items[i], 'a');
    var t = R_selFirst(items[i], 'h2.text-sm');
    if (!a || !t) { continue; }
    var href = a.absUrl('href') || a.attr('href');
    if (!href) { continue; }
    out.push({
      key: R_path(href),
      title: t.text(),
      coverUrl: imgAttr(R_selFirst(items[i], 'img'))
    });
  }
  return out;
}

function hasNext(doc) {
  // ul.pagination > li:last-child:not(.pagination-disabled) — approximate with enabled next link
  var lis = R_sel(doc, 'ul.pagination li');
  if (lis.length === 0) { return false; }
  var last = lis[lis.length - 1];
  var cls = last.attr('class') || '';
  if (cls.indexOf('pagination-disabled') >= 0) { return false; }
  return !!R_selFirst(last, 'a');
}

async function listManga(page, query) {
  var url;
  if (query) {
    url = BASE + '/manga?title=' + encodeURIComponent(query.trim()) + (page > 1 ? '&page=' + page : '');
  } else {
    url = BASE + '/manga?page=' + page;
  }
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  return { mangas: parseCards(doc), hasNextPage: hasNext(doc) };
}

function infoVal(el, label) {
  var p = R_selFirst(el, 'p:has(span):has(span)');
  var ps = R_sel(el, 'p');
  for (var i = 0; i < ps.length; i++) {
    var spans = R_sel(ps[i], 'span');
    var labelText = '';
    for (var j = 0; j < spans.length; j++) { labelText += spans[j].text() + ' '; }
    if (labelText.indexOf(label) >= 0) {
      var cap = R_selFirst(ps[i], 'span.capitalize');
      if (cap) { return R_ownText(cap); }
    }
  }
  return '';
}

function parseStatus(s) {
  var v = String(s || '').toLowerCase();
  if (!v) { return ''; }
  if (/ongoing|مستمر|en cours/.test(v)) { return 'ongoing'; }
  if (/dropped|cancelled|متوقف/.test(v)) { return 'cancelled'; }
  if (/completed|مكتمل|terminé/.test(v)) { return 'completed'; }
  if (/hiatus/.test(v)) { return 'hiatus'; }
  return '';
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga(page, '');
  },

  getSearchManga: async function (page, query) {
    return listManga(page, query);
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey));
    var doc = $.html.parse(text);
    var main = R_selFirst(doc, 'main > section > div');
    var title = '';
    var cover = '';
    var genres = [];
    var desc = '';
    if (main) {
      cover = imgAttr(R_selFirst(main, 'div.relative img'));
      var tEl = R_selFirst(main, 'div.flex > h1') || R_selFirst(main, 'div.flex > h2');
      if (tEl) { title = R_ownText(tEl); }
      var gas = R_sel(main, 'div.flex > a.inline-block');
      for (var i = 0; i < gas.length; i++) { genres.push(gas[i].text()); }
      var descBox = R_selFirst(main, 'div');
      var descEl = R_selFirst(doc, 'p#description');
      var descParent = descEl ? R_selFirst(doc, 'div:has(> p#description)') : null;
      if (descParent) {
        desc = descParent.text();
      } else if (descEl) {
        desc = descEl.text();
      }
      var alt = R_selFirst(main, 'div.flex > h1 + div > span.text-sm') || R_selFirst(main, 'div.flex > h2 + div > span.text-sm');
      if (alt && alt.text()) {
        desc += (desc ? '\\n\\n' : '') + 'Alternative Title: ' + alt.text();
      }
    }
    var info = R_selFirst(doc, 'div#buttons + div.hidden') || R_selFirst(doc, 'div:has(> div#buttons) + div.flex');
    var status = '';
    var artist = '';
    var author = '';
    if (info) {
      status = parseStatus(infoVal(info, 'Status') || infoVal(info, 'Statut'));
      artist = infoVal(info, 'Artist') || infoVal(info, 'المؤلف') || infoVal(info, 'Artiste');
      author = infoVal(info, 'Author') || infoVal(info, 'الرسام') || infoVal(info, 'Auteur');
      var type = infoVal(info, 'Type') || infoVal(info, 'النوع');
      if (type && type !== '-') { genres.unshift(type); }
    }
    if (artist === '-') { artist = ''; }
    if (author === '-') { author = ''; }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: author,
      description: desc.trim(),
      genre: genres.filter(Boolean).join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var out = [];
    var page = 1;
    var guard = 0;
    while (guard < 50) {
      guard++;
      var url = R_abs(mangaKey) + '?page=' + page;
      var text = await $.http.get(url);
      var doc = $.html.parse(text);
      var els = R_sel(doc, 'div#chapters-list > a[href]');
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        var href = el.absUrl('href') || el.attr('href');
        if (!href) { continue; }
        var tEl = R_selFirst(el, '#item-title') || R_selFirst(el, 'span');
        var dEl = R_selFirst(el, 'span.text-gray-500');
        out.push({
          key: R_path(href),
          name: tEl ? R_ownText(tEl) : '',
          chapterNumber: -1,
          dateUpload: dEl ? R_date(dEl.text()) : 0,
          pages: 0,
          sortOrder: 0
        });
      }
      if (!hasNext(doc)) { break; }
      page++;
    }
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, 'div#chapter-container > img');
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var u = imgAttr(els[i]);
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
