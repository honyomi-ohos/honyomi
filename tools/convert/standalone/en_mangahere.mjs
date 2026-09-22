// en/mangahere — fanfox-family site; page images via chapterfun.ashx with packer-unpacked key.
// NOTE: geo-blocked in the converter's region (app-landing page), so live probing is impossible;
// port is best-effort faithful to upstream.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'site geo-blocked in converter region: live probe unavailable, port untested',
      'eval(p,a,c,k,e,d) packer unpacked with a pure-JS implementation; two-stage key eval uses Function constructor with string-literal fallback',
    ],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/', Cookie: 'isAdult=1' };

// ---- eval packer (p,a,c,k,e,d) unpacker ----
function jsStringLiteral(raw) {
  try { return Function('return ' + raw)(); } catch (e) { return null; }
}

function unpackPacked(scriptText) {
  // scriptText starts with "eval(function(p,a,c,k,e,d){...}('payload',radix,count,'k1|k2'.split('|'),0,{}))"
  var start = scriptText.indexOf("}('");
  if (start < 0) { return null; }
  start += 2;
  // scan the string literal honoring escapes
  var i = start + 1;
  while (i < scriptText.length) {
    if (scriptText[i] === '\\\\') { i += 2; continue; }
    if (scriptText[i] === "'") { break; }
    i++;
  }
  var payloadLit = scriptText.substring(start, i + 1);
  var rest = scriptText.substring(i + 1);
  var m = /^\\s*,\\s*([0-9]+|parseInt\\([^)]*\\))\\s*,\\s*(\\d+)\\s*,\\s*'((?:[^'\\\\]|\\\\.)*)'\\s*\\.split/i.exec(rest);
  if (!m) { return null; }
  var radixExpr = m[1];
  var count = parseInt(m[2], 10);
  var keysRaw = m[3];
  var payload = jsStringLiteral(payloadLit);
  var radix = 62;
  if (/^\\d+$/.test(radixExpr)) { radix = parseInt(radixExpr, 10); }
  else { var r = jsStringLiteral(radixExpr.replace(/parseInt\\(\\s*'?([^',)]*)'?\\s*,\\s*\\d+\\s*\\)/, "'$1'")); radix = (r !== null && typeof r === 'number') ? r : 62; }
  var keys = jsStringLiteral("'" + keysRaw + "'").split('|');
  if (payload === null) { return null; }
  var e = function (c) {
    return (c < radix ? '' : e(Math.floor(c / radix))) + ((c = c % radix) > 35 ? String.fromCharCode(c + 29) : c.toString(36));
  };
  while (count--) {
    if (keys[count] !== undefined && keys[count] !== '') {
      payload = payload.replace(new RegExp('\\\\b' + e(count) + '\\\\b', 'g'), keys[count]);
    }
  }
  return payload;
}

function evalSmallExpr(expr) {
  var t = expr.trim();
  if (/^'[^']*'$/.test(t)) { return t.slice(1, -1); }
  if (/^"[^"]*"$/.test(t)) { return t.slice(1, -1); }
  try { return Function('return (' + t + ')')(); } catch (e) { return null; }
}

function parseListDoc(doc, itemSel, linkSel, imgSel) {
  var els = R_sel(doc, itemSel);
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var link = linkSel ? R_selFirst(el, linkSel) : R_selFirst(el, 'a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    out.push({
      key: R_path(href),
      title: link.attr('title') || link.text(),
      coverUrl: R_img(R_selFirst(el, imgSel))
    });
  }
  var hasNext = !!R_selFirst(doc, 'div.pager-list-left a:last-child');
  return { mangas: out, hasNextPage: hasNext };
}

function parseDate(s) {
  var v = String(s || '').trim();
  if (!v) { return 0; }
  if (v.indexOf('Today') >= 0 || v.indexOf('ago') >= 0) { return Date.now() - Date.now() % 86400000; }
  if (v.indexOf('Yesterday') >= 0) { return Date.now() - Date.now() % 86400000 - 86400000; }
  return Date.parse(v) || 0;
}

function parseImageUrlFromResponse(responseText) {
  var deob = responseText.indexOf('eval(function(p,a,c,k,e,d)') === 0 ? unpackPacked(responseText) : responseText;
  if (!deob) { return ''; }
  var pixStart = deob.indexOf('pix=');
  if (pixStart < 0) { return ''; }
  pixStart += 5;
  var pixEnd = deob.indexOf(';', pixStart);
  var pix = deob.substring(pixStart, pixEnd > pixStart ? pixEnd - 1 : pixStart + 200);
  var pvStart = deob.indexOf('pvalue=');
  if (pvStart < 0) { return ''; }
  pvStart = deob.indexOf('"', pvStart) + 1;
  var pvEnd = deob.indexOf('"', pvStart);
  var pvalue = deob.substring(pvStart, pvEnd);
  if (!pix || !pvalue) { return ''; }
  return 'https:' + pix + pvalue;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(BASE + '/directory/' + page + '.htm', HDRS);
    return parseListDoc($.html.parse(text), '.manga-list-1-list li', 'a', 'img.manga-list-1-cover');
  },

  getSearchManga: async function (page, query) {
    var u = BASE + '/search?page=' + page + '&title=' + encodeURIComponent(query || '') + '&stype=1';
    var text = await $.http.get(u, HDRS);
    return parseListDoc($.html.parse(text), '.manga-list-4-list > li', '.manga-list-4-item-title > a', 'img.manga-list-4-cover');
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var genres = [];
    var gels = R_sel(doc, '.detail-info-right-tag-list > a');
    for (var i = 0; i < gels.length; i++) { genres.push(gels[i].text()); }
    var statusEl = R_selFirst(doc, 'span.detail-info-right-title-tip');
    var status = '';
    if (statusEl) {
      var st = statusEl.text().toLowerCase();
      if (st.indexOf('ongoing') >= 0) { status = 'ongoing'; }
      else if (st.indexOf('completed') >= 0) { status = 'completed'; }
    }
    return {
      key: mangaKey,
      title: (R_selFirst(doc, '.detail-info-right-title') || { text: function () { return ''; } }).text(),
      coverUrl: R_img(R_selFirst(doc, 'img.detail-info-cover-img')),
      author: (R_selFirst(doc, '.detail-info-right-say > a') || { text: function () { return ''; } }).text(),
      description: (R_selFirst(doc, '.fullcontent') || { text: function () { return ''; } }).text(),
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(R_abs(mangaKey), HDRS);
    var doc = $.html.parse(text);
    var els = R_sel(doc, 'ul.detail-main-list > li');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var link = R_selFirst(el, 'a');
      if (!link) { continue; }
      var href = link.absUrl('href');
      if (!href) { continue; }
      var nameEl = R_selFirst(el, 'a p.title3');
      var dateEl = R_selFirst(el, 'a p.title2');
      out.push({
        key: R_path(href),
        name: nameEl ? nameEl.text() : link.text(),
        chapterNumber: -1,
        dateUpload: dateEl ? parseDate(dateEl.text()) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var chapterUrl = R_abs(chapterKey);
    var text = await $.http.get(chapterUrl, HDRS);
    var doc = $.html.parse(text);
    var bar = R_sel(doc, 'script[src*="chapter_bar"]');
    var pages = [];
    if (bar.length) {
      // webtoon reader: packed script with newImgs
      var scripts = R_sel(doc, 'script');
      var packed = null;
      for (var s = 0; s < scripts.length; s++) {
        var h = scripts[s].html ? scripts[s].html() : '';
        if (h.indexOf('function(p,a,c,k,e,d)') >= 0) { packed = h; break; }
      }
      if (!packed) { return []; }
      var deob = unpackPacked(packed.replace(/^\\s*eval/, ''));
      if (!deob) { return []; }
      var m = /newImgs=\\['(.+?)'\\]/.exec(deob);
      if (!m) { return []; }
      var urls = m[1].split("','");
      for (var i = 0; i < urls.length; i++) {
        pages.push({ index: i, url: 'https:' + urls[i] });
      }
      return pages;
    }
    // page-by-page: need secret key from packed script
    var html = text;
    var keyLoc = html.indexOf('eval(function(p,a,c,k,e,d)');
    if (keyLoc < 0) { return []; }
    var keyEnd = html.indexOf('</script>', keyLoc);
    var keyScript = html.substring(keyLoc, keyEnd).replace(/^\\s*eval/, '');
    var keyDeob = unpackPacked(keyScript);
    if (!keyDeob) { return []; }
    var q1 = keyDeob.indexOf("'");
    var semi = keyDeob.indexOf(';', q1);
    var keyExpr = keyDeob.substring(q1, semi);
    var secretKey = evalSmallExpr(keyExpr) || '';
    var cidLoc = html.indexOf('chapterid');
    if (cidLoc < 0) { return []; }
    var cid = html.substring(cidLoc + 11, html.indexOf(';', cidLoc)).trim();
    var spanEl = R_selFirst(doc, '.pager-list-left > span');
    if (!spanEl) { return []; }
    var pageLinks = R_sel(spanEl, 'a');
    if (pageLinks.length < 2) { return []; }
    var pagesNumber = parseInt(pageLinks[pageLinks.length - 2].attr('data-page'), 10) || 0;
    var pageBase = chapterUrl.substring(0, chapterUrl.lastIndexOf('/'));
    var reqHeaders = {
      Referer: chapterUrl,
      Accept: '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'X-Requested-With': 'XMLHttpRequest'
    };
    for (var p = 1; p <= pagesNumber; p++) {
      var base = pageBase + '/chapterfun.ashx?cid=' + encodeURIComponent(cid) + '&page=' + p;
      var imageUrl = '';
      var keys = [secretKey, ''];
      for (var k = 0; k < keys.length && !imageUrl; k++) {
        try {
          var resp = await $.http.get(base + '&key=' + encodeURIComponent(keys[k]), reqHeaders);
          if (resp) { imageUrl = parseImageUrlFromResponse(resp); }
        } catch (e) { /* try next */ }
      }
      if (imageUrl) { pages.push({ index: pages.length, url: imageUrl }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
