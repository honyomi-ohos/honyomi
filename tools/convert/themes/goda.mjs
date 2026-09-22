// GoDa theme engine (en: goda, zh: baozimhorg, eighteenmanhua)
// HTML scraping by default; baozimhorg uses a JSON API with an obfuscated
// chapter image list (client-side decoder ported below).
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    jsonApi: false,
    zhLang: ((ctx.gradle && ctx.gradle.sources && ctx.gradle.sources[0]) || {}).lang === 'zh'
  };
  if (/api-get-v3\.mgsearcher\.com/.test(kt)) {
    config.jsonApi = true;
    const am = kt.match(/client\.get\("(https:[^"]*)\/api\/manga\/get/);
    if (am) config.apiBase = am[1];
    const im = kt.match(/"(https:[^"]*)\$url"/);
    if (im) config.imgCdn = im[1];
    warnings.push('baozimhorg JSON API + obfuscated image decoder ported; 404-migration interceptor dropped');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: goda)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var NEXT_LABEL = CFG.zhLang ? '下一頁' : 'NEXT';

function getKeyFromLink(link) {
  var s = String(link);
  var i = s.indexOf('/manga/');
  if (i >= 0) { s = s.substring(i + 7); }
  if (s.charAt(s.length - 1) === '/') { s = s.substring(0, s.length - 1); }
  return s;
}

function parseCards(doc) {
  var cards = R_sel(doc, '.cardlist .pb-2 a');
  if (cards.length === 0) { cards = R_sel(doc, '.container > .cardlist .pb-2 a'); }
  var out = [];
  for (var i = 0; i < cards.length; i++) {
    var el = cards[i];
    var href = el.absUrl('href') || el.attr('href') || '';
    if (!href) { continue; }
    var img = R_selFirst(el, 'img');
    var imgSrc = img ? (img.attr('src') || '') : '';
    var cover = imgSrc;
    var qi = imgSrc.indexOf('url=');
    if (qi >= 0) { cover = decodeURIComponent(imgSrc.substring(qi + 4).split('&')[0]); }
    var h3 = R_selFirst(el, 'h3');
    out.push({
      key: '/' + getKeyFromLink(href),
      title: h3 ? R_ownText(h3) : el.text(),
      coverUrl: cover
    });
  }
  return out;
}

function hasNext(doc) {
  var links = R_sel(doc, 'a');
  for (var i = 0; i < links.length; i++) {
    if (links[i].attr('aria-label') === NEXT_LABEL) { return true; }
  }
  return false;
}

function statusMapZh(s) {
  var v = String(s || '').trim();
  if (v === '連載中' || v === '连载中' || v === 'Ongoing') { return 'ongoing'; }
  if (v === '完結' || v === '完结') { return 'completed'; }
  if (v === '停止更新') { return 'cancelled'; }
  if (v === '休刊') { return 'on_hiatus'; }
  return '';
}

function decodeImages(input) {
  var PREFIX = 'J7r', SUFFIX = 'nQ', M1 = 'kD', M2 = 'W4s', GROUP = 7;
  var STD = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  var CUSTOM = '_-9876543210abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  var body = input.substring(PREFIX.length, input.length - SUFFIX.length);
  var payloadLen = body.length - M1.length - M2.length;
  var aLen = Math.floor(payloadLen / 3);
  var bLen = Math.floor((payloadLen - aLen) / 2);
  var cLen = payloadLen - aLen - bLen;
  var part1 = body.substring(0, bLen);
  var part2 = body.substring(bLen + M1.length, bLen + M1.length + cLen);
  var part3 = body.substring(bLen + M1.length + cLen + M2.length);
  var reordered = part3 + part1 + part2;
  var unzig = '';
  var i = 0, block = 0;
  while (i < reordered.length) {
    var chunk = reordered.substring(i, Math.min(i + GROUP, reordered.length));
    unzig += (block % 2 === 1) ? chunk.split('').reverse().join('') : chunk;
    i += GROUP;
    block++;
  }
  var std = '';
  for (var k = 0; k < unzig.length; k++) {
    var idx = CUSTOM.indexOf(unzig.charAt(k));
    if (idx < 0) { throw new Error('Invalid chapter data character'); }
    std += STD.charAt(idx);
  }
  var b = std.replace(/-/g, '+').replace(/_/g, '/');
  while (b.length % 4 !== 0) { b += '='; }
  var bin = atob(b);
  var bytes = new Uint8Array(bin.length);
  for (var n = 0; n < bin.length; n++) { bytes[n] = bin.charCodeAt(n); }
  return new TextDecoder('utf-8').decode(bytes);
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/hots/page/' + page);
    var doc = $.html.parse(text);
    return { mangas: parseCards(doc), hasNextPage: hasNext(doc) };
  },

  getSearchManga: async function (page, query) {
    var url = BASE + '/s/' + encodeURIComponent(query) + '?page=' + page;
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    return { mangas: parseCards(doc), hasNextPage: hasNext(doc) };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/+/, '');
    var text = await $.http.get(BASE + '/manga/' + slug);
    var doc = $.html.parse(text);
    var main = R_selFirst(doc, 'main');
    var h1 = main ? R_selFirst(main, 'h1') : null;
    var title = '', status = '', author = '', genre = '', desc = '', cover = '';
    var mangaId = '';
    var midEl = R_selFirst(doc, '#mangachapters');
    if (midEl) { mangaId = midEl.attr('data-mid') || ''; }
    if (h1) {
      title = R_ownText(h1);
      var h1kid = R_selFirst(h1, ':scope > *');
      if (h1kid) { status = statusMapZh(h1kid.text()); }
      var wrap = main ? R_selFirst(main, 'div:has(> div > h1)') : null;
      if (wrap) {
        var els = R_sel(wrap, ':scope > *');
        if (els && els.length > 4) {
          var authorKids = R_sel(els[1], ':scope > *');
          var names = [];
          for (var i = 1; i < authorKids.length; i++) {
            var t = authorKids[i].text();
            if (t) { names.push(t.replace(/ ,$/, '')); }
          }
          author = names.join(', ');
          var gKids = R_sel(els[2], ':scope > *');
          var genres = [];
          for (var g = 1; g < gKids.length; g++) {
            var gt = gKids[g].text();
            if (gt) { genres.push(gt.replace(/ ,$/, '')); }
          }
          var tKids = R_sel(els[3], ':scope > *');
          for (var t2 = 0; t2 < tKids.length; t2++) {
            var tt = tKids[t2].text();
            if (tt) { genres.push(tt.replace(/^#/, '')); }
          }
          genre = genres.join(', ');
          desc = (els[4].text() + (mangaId ? '\\n\\nID: ' + mangaId : '')).trim();
        }
      }
    }
    var coverEl = main ? R_selFirst(main, 'img.object-cover') : null;
    if (coverEl) { cover = coverEl.attr('src') || ''; }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      author: author,
      description: desc,
      genre: genre,
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/+/, '');
    var text = await $.http.get(BASE + '/manga/' + slug);
    var doc = $.html.parse(text);
    var midEl = R_selFirst(doc, '#mangachapters');
    var mangaId = midEl ? (midEl.attr('data-mid') || '') : '';
    var out = [];

    if (CFG.jsonApi) {
      var api = CFG.apiBase || 'https://api-get-v3.mgsearcher.com';
      var jtext = await $.http.get(api + '/api/manga/get?mid=' + mangaId + '&mode=all');
      var data = JSON.parse(jtext).data;
      var rows = (data.chapters || []).slice().reverse();
      for (var i = 0; i < rows.length; i++) {
        var c = rows[i];
        out.push({
          key: '/' + [data.slug, c.attributes.slug, data.id, c.id].join('/'),
          name: c.attributes.title || '',
          chapterNumber: 0,
          dateUpload: c.attributes.updatedAt ? Math.floor(new Date(c.attributes.updatedAt).getTime() / 1000) : 0,
          pages: 0,
          sortOrder: 0
        });
      }
    } else {
      var ctext = await $.http.get(BASE + '/manga/get?mid=' + mangaId + '&mode=all');
      var cdoc = $.html.parse(ctext);
      var items = R_sel(cdoc, '.chapteritem').slice().reverse();
      for (var j = 0; j < items.length; j++) {
        var anchor = R_selFirst(items[j], 'a');
        if (!anchor) { continue; }
        var chKey = getKeyFromLink(anchor.attr('href') || '');
        out.push({
          key: '/' + [chKey, mangaId, anchor.attr('data-cs') || ''].join('/'),
          name: anchor.attr('data-ct') || '',
          chapterNumber: 0,
          dateUpload: 0,
          pages: 0,
          sortOrder: 0
        });
      }
    }
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = String(chapterKey).split('/').filter(Boolean);
    var pages = [];
    if (CFG.jsonApi) {
      var api = CFG.apiBase || 'https://api-get-v3.mgsearcher.com';
      var text = await $.http.get(api + '/api/v2/chapter/getinfo?m=' + parts[2] + '&c=' + parts[3]);
      var info = JSON.parse(text).data.info;
      var decoded = decodeImages(info.images.images);
      var imgs = JSON.parse(decoded);
      var cdn = CFG.imgCdn || 'https://c-nd2-1.6wm.top';
      for (var i = 0; i < imgs.length; i++) {
        pages.push({ index: imgs[i].order, url: cdn + imgs[i].url });
      }
    } else {
      var html = await $.http.get(BASE + '/chapter/getcontent?m=' + parts[1] + '&c=' + parts[2]);
      var doc = $.html.parse(html);
      var els = R_sel(doc, '#chapcontent img');
      for (var j = 0; j < els.length; j++) {
        var u = els[j].attr('data-src') || els[j].attr('src') || '';
        if (u) { pages.push({ index: pages.length, url: u }); }
      }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
