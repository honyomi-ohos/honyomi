// ColorlibAnime theme engine (id: komikzoid, sektekomik) — anime-style WP theme
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText || '';
  const warnings = [];
  const config = {};
  if (/rateLimit\(/.test(kt)) warnings.push('rateLimit(3) not enforced in plugin');
  warnings.push('Order By filter not supported by host; popular=A-Z order (faithful to upstream), search=views order');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: colorlibanime)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function thumbOf(scope) {
  var el = R_selFirst(scope, '.set-bg');
  if (!el) { return ''; }
  var u = el.attr('data-setbg') || '';
  var q = u.lastIndexOf('?');
  if (q >= 0) { u = u.substring(0, q); }
  if (u && u.indexOf('http') !== 0) { u = R_abs(u); }
  return u;
}

function parseList(doc) {
  var items = R_sel(doc, '.product__page__content > [style]:has(.col-6) .product__item');
  var mangas = [];
  for (var i = 0; i < items.length; i++) {
    var link = R_selFirst(items[i], 'a.img-link');
    var h5 = R_selFirst(items[i], 'h5');
    if (!link || !h5) { continue; }
    mangas.push({
      key: R_path(link.absUrl('href') || link.attr('href')),
      title: h5.text(),
      coverUrl: thumbOf(items[i])
    });
  }
  var hasNextPage = !!R_selFirst(doc, '.fa-angle-right');
  return { mangas: mangas, hasNextPage: hasNextPage };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/manga?page=' + page + '&sort=default&search=');
    return parseList($.html.parse(text));
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/manga?page=' + page + '&sort=view&search=' + encodeURIComponent(query));
    return parseList($.html.parse(text));
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(BASE + mangaKey);
    var doc = $.html.parse(text);
    var el = R_selFirst(doc, '.anime__details__content');
    if (!el) {
      return { key: mangaKey, title: '', coverUrl: '', description: '', status: 'UNKNOWN' };
    }
    var titleEl = R_selFirst(el, 'h3');
    var authorEl = R_selFirst(el, 'h3 + span');
    var ps = R_sel(el, 'p');
    var desc = [];
    for (var i = 0; i < ps.length; i++) { desc.push(ps[i].text()); }
    var status = 'UNKNOWN';
    var lis = R_sel(el, 'li');
    for (var l = 0; l < lis.length; l++) {
      var lt = lis[l].text();
      if (lt.toLowerCase().indexOf('status') >= 0) {
        var val = lt.substring(lt.indexOf(' ') + 1).trim();
        if (val === 'Ongoing') { status = 'ONGOING'; }
        else if (val === 'Complete') { status = 'COMPLETED'; }
        break;
      }
    }
    return {
      key: mangaKey,
      title: titleEl ? titleEl.text() : '',
      author: authorEl ? authorEl.text() : '',
      coverUrl: thumbOf(el),
      description: desc.join(' '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(BASE + mangaKey);
    var doc = $.html.parse(text);
    var time = 0;
    var scripts = R_sel(doc, 'script');
    for (var s = 0; s < scripts.length; s++) {
      var body = scripts[s].html();
      if (body.indexOf('lastUpdated') >= 0) {
        var m = /Date\\((\\d+)\\)/.exec(body);
        if (m) { time = Math.floor(parseInt(m[1], 10) / 1000); }
        break;
      }
    }
    var anchors = R_sel(doc, '.anime__details__episodes a');
    var chapters = [];
    for (var i = 0; i < anchors.length; i++) {
      chapters.push({
        key: R_path(anchors[i].absUrl('href') || anchors[i].attr('href')),
        name: anchors[i].text(),
        dateUpload: i === 0 ? time : 0
      });
    }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(BASE + chapterKey);
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, '.container .read-img > img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].absUrl('src') || imgs[i].attr('src') || '';
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
