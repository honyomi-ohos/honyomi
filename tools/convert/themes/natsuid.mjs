// NatsuId theme engine (WordPress natsu_id: ikiru / kiryuu / natsu / rawkuma)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    chapterListPage: '777',
  };

  const pm = kt.match(/chapterListUrl[\s\S]{0,400}?setQueryParameter\("page",\s*"(\d+)"\)/);
  if (pm) { config.chapterListPage = pm[1]; }

  if (/rateLimit\s*\(/.test(kt)) {
    warnings.push('rateLimit not portable; requests may be throttled by site');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: natsuid)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_status/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- natsuid engine ----------------
// manga key: /manga/{slug}/

var nonceCache = '';
var idCache = {};

function slugFromKey(mangaKey) {
  var parts = String(mangaKey).split('/').filter(function (p) { return p.length > 0; });
  return parts[1] || parts[0] || '';
}

function jsonOf(text) {
  // some hosts emit leading junk before the JSON payload
  var idx = -1;
  for (var i = 0; i < text.length; i++) {
    if (text[i] === '{' || text[i] === '[') { idx = i; break; }
  }
  return idx >= 0 ? JSON.parse(text.substring(idx)) : JSON.parse(text);
}

async function getNonce() {
  if (nonceCache) { return nonceCache; }
  var text = await $.http.get(BASE + '/wp-admin/admin-ajax.php?type=search_form&action=get_nonce');
  var doc = $.html.parse(text);
  var el = R_selFirst(doc, 'input[name=search_nonce]');
  if (!el) { throw new Error('Unable to get nonce'); }
  nonceCache = el.attr('value');
  return nonceCache;
}

function multipart(fields) {
  var boundary = '----mihonform' + String(Math.random()).replace(/0\\./, '');
  var parts = [];
  for (var i = 0; i < fields.length; i++) {
    parts.push('--' + boundary + '\\r\\nContent-Disposition: form-data; name="' + fields[i][0] + '"\\r\\n\\r\\n' + fields[i][1] + '\\r\\n');
  }
  parts.push('--' + boundary + '--\\r\\n');
  return { body: parts.join(''), contentType: 'multipart/form-data; boundary=' + boundary };
}

function terms(manga, taxonomy) {
  var embedded = manga._embedded || {};
  var lists = embedded['wp:term'] || [];
  for (var i = 0; i < lists.length; i++) {
    var list = lists[i];
    if (list && list[0] && list[0].taxonomy === taxonomy) {
      var names = [];
      for (var j = 0; j < list.length; j++) { names.push(list[j].name); }
      return names;
    }
  }
  return [];
}

function decodeEntities(s) {
  return String(s)
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&#x2F;/gi, '/')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&');
}

function htmlToText(html) {
  var s = String(html || '');
  if (!s) { return ''; }
  if (s.indexOf('<') < 0) { return decodeEntities(s).trim(); }
  var doc = $.html.parse(s);
  var t = doc.text();
  if (!t) {
    // some DOM impls return null textContent on the Document node itself
    var body = R_selFirst(doc, 'body');
    if (body) { t = body.text(); }
  }
  if (!t) { t = decodeEntities(s.replace(/<[^>]*>/g, ' ')).replace(/\\s+/g, ' '); }
  return t.trim();
}

function mangaFromWp(manga) {
  var typeTerms = terms(manga, 'type');
  if (typeTerms.indexOf('Novel') >= 0) { return null; }
  var title = htmlToText(manga.title && manga.title.rendered);
  var desc = htmlToText(manga.content && manga.content.rendered);
  var alt = '';
  try {
    alt = (manga.meta && manga.meta.meta && manga.meta.meta.alternative_title) || (manga.metadata && manga.metadata.meta && manga.metadata.meta.alternative_title) || '';
  } catch (e) { alt = ''; }
  if (alt) {
    var alts = String(alt).split(',').map(function (s) { return s.trim(); })
      .filter(function (s) { return s && s.toLowerCase() !== title.toLowerCase(); });
    if (alts.length > 0) {
      desc = (desc ? desc + '\\n\\n' : '') + 'Alternative Names:\\n' + alts.map(function (s) { return '- ' + s; }).join('\\n');
    }
  }
  var cover = '';
  var fm = manga._embedded && manga._embedded['wp:featuredmedia'];
  if (fm && fm[0] && fm[0].source_url) { cover = fm[0].source_url; }
  var statusTerms = terms(manga, 'status');
  var status = '';
  if (statusTerms.indexOf('Ongoing') >= 0) { status = 'ongoing'; }
  else if (statusTerms.indexOf('Completed') >= 0) { status = 'completed'; }
  else if (statusTerms.indexOf('Cancelled') >= 0) { status = 'cancelled'; }
  else if (statusTerms.indexOf('On Hiatus') >= 0) { status = 'hiatus'; }
  var genres = terms(manga, 'genre').concat(typeTerms);
  return {
    key: '/manga/' + manga.slug + '/',
    title: title,
    coverUrl: cover,
    author: terms(manga, 'series-author').join(', '),
    artist: terms(manga, 'artist').join(', '),
    description: desc,
    genre: genres.join(', '),
    status: status,
    _id: String(manga.id)
  };
}

async function fetchWpBySlugs(slugs) {
  var url = BASE + '/wp-json/wp/v2/manga';
  var qs = [];
  for (var i = 0; i < slugs.length; i++) { qs.push('slug[]=' + encodeURIComponent(slugs[i])); }
  qs.push('per_page=' + String(slugs.length + 1));
  qs.push('_embed');
  var text = await $.http.get(url + '?' + qs.join('&'));
  var list = jsonOf(text);
  var bySlug = {};
  for (var j = 0; j < list.length; j++) { bySlug[list[j].slug] = list[j]; }
  return bySlug;
}

async function searchList(page, query, orderby) {
  var nonce = await getNonce();
  var mp = multipart([
    ['nonce', nonce],
    ['inclusion', 'OR'],
    ['exclusion', 'OR'],
    ['page', String(page)],
    ['genre', '[]'],
    ['genre_exclude', '[]'],
    ['author', '[]'],
    ['artist', '[]'],
    ['project', '0'],
    ['type', '[]'],
    ['status', '[]'],
    ['order', 'desc'],
    ['orderby', orderby],
    ['query', String(query || '').trim()]
  ]);
  var text = await $.http.post(BASE + '/wp-admin/admin-ajax.php?action=advanced_search', mp.body, {
    'Content-Type': mp.contentType
  });
  var doc = $.html.parse(text);
  // "div > a[href*=/manga/]:has(> img)" without :has
  var anchors = R_sel(doc, 'a[href*="/manga/"]');
  var slugs = [];
  var seen = {};
  for (var i = 0; i < anchors.length; i++) {
    var a = anchors[i];
    var img = R_selFirst(a, 'img');
    if (!img) { continue; }
    var href = a.attr('href') || a.absUrl('href');
    if (!href) { continue; }
    var segs = String(href).replace(/^https?:\\/\\/[^\\/]+/, '').split('/').filter(function (p) { return p.length > 0; });
    var slug = segs[0] === 'manga' ? segs[1] : segs[0];
    if (!slug || seen[slug]) { continue; }
    seen[slug] = true;
    slugs.push(slug);
  }
  if (slugs.length === 0) { return { mangas: [], hasNextPage: false }; }

  var bySlug = await fetchWpBySlugs(slugs);
  var mangas = [];
  for (var s = 0; s < slugs.length; s++) {
    var wp = bySlug[slugs[s]];
    if (!wp) { continue; }
    var m = mangaFromWp(wp);
    if (m) {
      idCache[slugs[s]] = m._id;
      delete m._id;
      mangas.push(m);
    }
  }
  // next page: a <button> containing an <svg>
  var hasNext = false;
  var buttons = R_sel(doc, 'button');
  for (var b = 0; b < buttons.length; b++) {
    if (R_selFirst(buttons[b], 'svg')) { hasNext = true; break; }
  }
  return { mangas: mangas, hasNextPage: hasNext };
}

async function fetchWpBySlug(slug, embed) {
  var url = BASE + '/wp-json/wp/v2/manga?slug[]=' + encodeURIComponent(slug) + (embed ? '&_embed' : '');
  var text = await $.http.get(url);
  var list = jsonOf(text);
  return list[0] || null;
}

module.exports = {
  getPopularManga: async function (page) {
    return searchList(page, '', 'popular');
  },

  getSearchManga: async function (page, query) {
    return searchList(page, query || '', 'popular');
  },

  getMangaDetail: async function (mangaKey) {
    var slug = slugFromKey(mangaKey);
    var wp = await fetchWpBySlug(slug, true);
    if (!wp) { throw new Error('Manga not found: ' + slug); }
    var m = mangaFromWp(wp);
    if (!m) { throw new Error('Novels are not supported'); }
    idCache[slug] = m._id;
    delete m._id;
    return m;
  },

  getChapterList: async function (mangaKey) {
    var slug = slugFromKey(mangaKey);
    var mangaId = idCache[slug];
    if (!mangaId) {
      var wp = await fetchWpBySlug(slug, false);
      mangaId = wp ? String(wp.id) : '';
    }
    if (!mangaId) {
      // fallback: scrape manga page for #gallery-list hx-get
      var pageText = await $.http.get(BASE + '/manga/' + slug + '/');
      var pageDoc = $.html.parse(pageText);
      var gallery = R_selFirst(pageDoc, '#gallery-list');
      if (gallery) {
        var hx = gallery.attr('hx-get') || '';
        var mm = hx.match(/manga_id=([^&]+)/);
        if (mm) { mangaId = mm[1]; }
      }
    }
    if (!mangaId) { return []; }

    var text = await $.http.get(BASE + '/wp-admin/admin-ajax.php?manga_id=' + mangaId + '&page=' + CFG.chapterListPage + '&action=chapter_list');
    var doc = $.html.parse(text);
    // "div a:has(time)" without :has
    var anchors = R_sel(doc, 'a');
    var out = [];
    var seen = {};
    for (var i = 0; i < anchors.length; i++) {
      var a = anchors[i];
      var time = R_selFirst(a, 'time');
      if (!time) { continue; }
      var href = a.attr('href') || a.absUrl('href');
      if (!href) { continue; }
      var key = R_path(R_abs(href));
      if (seen[key]) { continue; }
      seen[key] = true;
      var span = R_selFirst(a, 'span');
      var dt = time.attr('datetime') || '';
      var ts = dt ? Date.parse(dt) : 0;
      out.push({
        key: key,
        name: span ? (R_ownText(span) || span.text()) : a.text(),
        chapterNumber: -1,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0
      });
    }
    // newest first on site; normalize to oldest-first
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = out.length - 1 - j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var els = R_sel(doc, 'main .relative section > img');
    var pages = [];
    for (var i = 0; i < els.length; i++) {
      var src = els[i].attr('src') || '';
      if (src) { pages.push({ index: pages.length, url: R_abs(src) }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
