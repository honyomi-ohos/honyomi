// ---------------- shared runtime ----------------
function R_abs(u) { try { return new URL(String(u), BASE).href; } catch (e) { return /^https?:\/\//.test(String(u)) ? String(u) : ''; } }
function R_path(u) { try { return new URL(String(u), BASE).pathname; } catch (e) { return ''; } }
function R_img(el) {
  if (!el) { return ''; }
  var names = ['data-src', 'data-lazy-src', 'data-cfsrc', 'data-manga-src', 'data-original'];
  for (var i = 0; i < names.length; i++) {
    var v = el.attr(names[i]);
    if (v) { return R_abs(v); }
  }
  var ss = el.attr('srcset');
  if (ss) {
    var best = '', bestW = -1;
    var parts = ss.split(',');
    for (var j = 0; j < parts.length; j++) {
      var seg = parts[j].trim().split(/\s+/);
      if (!seg[0]) { continue; }
      var w = seg[1] ? parseFloat(seg[1]) : 0;
      if (w > bestW) { bestW = isNaN(w) ? 0 : w; best = seg[0]; }
    }
    if (best) { return R_abs(best); }
  }
  var src = el.attr('src');
  return src ? R_abs(src) : '';
}
// querySelector wrapper tolerant of Jsoup-only pseudo classes (:contains etc.)
function R_sel(node, css) {
  if (!css) { return []; }
  try { return node.select(css); } catch (e) { /* fallthrough */ }
  // pass 2: convert Jsoup :eq(N) and strip :contains/:matches
  var cleaned = css.replace(/:eq\((\d+)\)/g, function (m, n) { return ':nth-of-type(' + (parseInt(n, 10) + 1) + ')'; })
    .replace(/:contains(?:Own)?\([^)]*\)/g, '').replace(/:matches(?:Own)?\([^)]*\)/g, '');
  try { return node.select(cleaned); } catch (e2) { /* fallthrough */ }
  // pass 3: strip :has() as last resort (native support exists in modern WebView)
  var noHas = cleaned.replace(/:has\(([^()]*)\)/g, '');
  try { return node.select(noHas); } catch (e3) { return []; }
}
function R_selFirst(node, css) {
  var list = R_sel(node, css);
  return list.length > 0 ? list[0] : null;
}
function R_ownText(el) {
  if (!el) { return ''; }
  var h = el.html();
  if (!h) { return el.text(); }
  return h.replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').trim();
}
var R_STATUS = {
  completed: ['completed', 'completo', 'completado', 'concluído', 'concluido', 'finalizado', 'achevé', 'terminé', 'hoàn thành', '已完结', 'tamamlandı', 'đã hoàn thành', 'завершено', 'complété', '完结'],
  ongoing: ['ongoing', 'on going', 'updating', 'продолжается', 'em lançamento', 'em andamento', 'en cours', 'ativo', 'lançando', 'đang tiến hành', 'còn nữa', 'devam ediyor', 'in corso', 'in arrivo', 'en curso', 'emision', 'en marcha', 'publicandose', 'en emision', '连载中', '连载', 'đang làm', 'em postagem', 'devam eden', 'em progresso', 'updating'],
  hiatus: ['on hold', 'hiatus', 'pausado', 'en espera', 'durduruldu', 'beklemede', 'đang chờ', 'en pause', 'заморожено', 'en attente'],
  cancelled: ['canceled', 'cancelled', 'cancelado', 'iptal edildi', 'đã hủy', 'abandonné', 'заброшено', 'annulé']
};
function R_status(s) {
  var v = String(s || '').toLowerCase();
  for (var k in R_STATUS) {
    var arr = R_STATUS[k];
    for (var i = 0; i < arr.length; i++) {
      if (v.indexOf(arr[i]) >= 0) { return k; }
    }
  }
  return '';
}
var R_UNITS = [
  ['year', 'año', 'ano', 'năm', 'yıl', '年'], ['month', 'mes', 'tháng', 'ay'],
  ['week', 'semana', 'tuần', 'hafta', '周'], ['day', 'día', 'dia', 'jour', 'hari', 'gün', 'ngày', 'giorni', '天'],
  ['hour', 'hora', 'heure', 'jam', 'saat', 'giờ', 'ore', '小时'],
  ['minute', 'minuto', 'min', 'menit', 'dakika', 'phút', '分钟'], ['second', 'segundo', 'sec', 'detik', 'giây', '秒']
];
var R_UNIT_MS = [31536000000, 2592000000, 604800000, 86400000, 3600000, 60000, 1000];
function R_date(s) {
  var v = String(s || '').trim();
  if (!v) { return 0; }
  var low = v.toLowerCase();
  if (/^(today|hoje|hoy|今天|今日)/.test(low)) { return Date.now() - Date.now() % 86400000; }
  if (/^(yesterday|ontem|ayer|昨天|昨日)/.test(low)) { return Date.now() - 86400000; }
  var num = low.match(/(\d+)\s*(\S+)/);
  if (num) {
    var amount = parseInt(num[1], 10);
    var rest = num[2];
    if (/s$/.test(rest)) { rest = rest.slice(0, -1); }
    for (var u = 0; u < R_UNITS.length; u++) {
      for (var w = 0; w < R_UNITS[u].length; w++) {
        if (rest === R_UNITS[u][w] || rest.indexOf(R_UNITS[u][w]) === 0) {
          return Date.now() - amount * R_UNIT_MS[u];
        }
      }
    }
  }
  var cn = v.match(/(\d+)\s*年\s*(\d+)\s*月\s*(\d+)\s*日?/);
  if (cn) { return new Date(parseInt(cn[1], 10), parseInt(cn[2], 10) - 1, parseInt(cn[3], 10)).getTime(); }
  var t = Date.parse(v);
  return isNaN(t) ? 0 : t;
}
function R_form(pairs) {
  var out = [];
  for (var i = 0; i < pairs.length; i++) {
    out.push(encodeURIComponent(pairs[i][0]) + '=' + encodeURIComponent(pairs[i][1]));
  }
  return out.join('&');
}
function R_xhr(extra) {
  var h = { 'X-Requested-With': 'XMLHttpRequest', 'Content-Type': 'application/x-www-form-urlencoded' };
  if (extra) { for (var k in extra) { h[k] = extra[k]; } }
  return h;
}
// Madara chapter-protector: AES-CBC(EVP_BytesToKey(md5)) decrypt -> image url list
var R_md5bin = (function () {
  // Joseph Myers md5 core, operating on byte arrays
  function add32(a, b) { return (a + b) & 0xFFFFFFFF; }
  function cmn(q, a, b, x, s, t) { a = add32(add32(a, q), add32(x, t)); return add32((a << s) | (a >>> (32 - s)), b); }
  function ff(a, b, c, d, x, s, t) { return cmn((b & c) | ((~b) & d), a, b, x, s, t); }
  function gg(a, b, c, d, x, s, t) { return cmn((b & d) | (c & (~d)), a, b, x, s, t); }
  function hh(a, b, c, d, x, s, t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
  function ii(a, b, c, d, x, s, t) { return cmn(c ^ (b | (~d)), a, b, x, s, t); }
  function md5cycle(x, k) {
    var a = x[0], b = x[1], c = x[2], d = x[3];
    a = ff(a, b, c, d, k[0], 7, -680876936); d = ff(d, a, b, c, k[1], 12, -389564586);
    c = ff(c, d, a, b, k[2], 17, 606105819); b = ff(b, c, d, a, k[3], 22, -1044525330);
    a = ff(a, b, c, d, k[4], 7, -176418897); d = ff(d, a, b, c, k[5], 12, 1200080426);
    c = ff(c, d, a, b, k[6], 17, -1473231341); b = ff(b, c, d, a, k[7], 22, -45705983);
    a = ff(a, b, c, d, k[8], 7, 1770035416); d = ff(d, a, b, c, k[9], 12, -1958414417);
    c = ff(c, d, a, b, k[10], 17, -42063); b = ff(b, c, d, a, k[11], 22, -1990404162);
    a = ff(a, b, c, d, k[12], 7, 1804603682); d = ff(d, a, b, c, k[13], 12, -40341101);
    c = ff(c, d, a, b, k[14], 17, -1502002990); b = ff(b, c, d, a, k[15], 22, 1236535329);
    a = gg(a, b, c, d, k[1], 5, -165796510); d = gg(d, a, b, c, k[6], 9, -1069501632);
    c = gg(c, d, a, b, k[11], 14, 643717713); b = gg(b, c, d, a, k[0], 20, -373897302);
    a = gg(a, b, c, d, k[5], 5, -701558691); d = gg(d, a, b, c, k[10], 9, 38016083);
    c = gg(c, d, a, b, k[15], 14, -660478335); b = gg(b, c, d, a, k[4], 20, -405537848);
    a = gg(a, b, c, d, k[9], 5, 568446438); d = gg(d, a, b, c, k[14], 9, -1019803690);
    c = gg(c, d, a, b, k[3], 14, -187363961); b = gg(b, c, d, a, k[8], 20, 1163531501);
    a = gg(a, b, c, d, k[13], 5, -1444681467); d = gg(d, a, b, c, k[2], 9, -51403784);
    c = gg(c, d, a, b, k[7], 14, 1735328473); b = gg(b, c, d, a, k[12], 20, -1926607734);
    a = hh(a, b, c, d, k[5], 4, -378558); d = hh(d, a, b, c, k[8], 11, -2022574463);
    c = hh(c, d, a, b, k[11], 16, 1839030562); b = hh(b, c, d, a, k[14], 23, -35309556);
    a = hh(a, b, c, d, k[1], 4, -1530992060); d = hh(d, a, b, c, k[4], 11, 1272893353);
    c = hh(c, d, a, b, k[7], 16, -155497632); b = hh(b, c, d, a, k[10], 23, -1094730640);
    a = hh(a, b, c, d, k[13], 4, 681279174); d = hh(d, a, b, c, k[0], 11, -358537222);
    c = hh(c, d, a, b, k[3], 16, -722521979); b = hh(b, c, d, a, k[6], 23, 76029189);
    a = hh(a, b, c, d, k[9], 4, -640364487); d = hh(d, a, b, c, k[12], 11, -421815835);
    c = hh(c, d, a, b, k[15], 16, 530742520); b = hh(b, c, d, a, k[2], 23, -995338651);
    a = ii(a, b, c, d, k[0], 6, -198630844); d = ii(d, a, b, c, k[7], 10, 1126891415);
    c = ii(c, d, a, b, k[14], 15, -1416354905); b = ii(b, c, d, a, k[5], 21, -57434055);
    a = ii(a, b, c, d, k[12], 6, 1700485571); d = ii(d, a, b, c, k[3], 10, -1894986606);
    c = ii(c, d, a, b, k[10], 15, -1051523); b = ii(b, c, d, a, k[1], 21, -2054922799);
    a = ii(a, b, c, d, k[8], 6, 1873313359); d = ii(d, a, b, c, k[15], 10, -30611744);
    c = ii(c, d, a, b, k[6], 15, -1560198380); b = ii(b, c, d, a, k[13], 21, 1309151649);
    a = ii(a, b, c, d, k[4], 6, -145523070); d = ii(d, a, b, c, k[11], 10, -1120210379);
    c = ii(c, d, a, b, k[2], 15, 718787259); b = ii(b, c, d, a, k[9], 21, -343485551);
    x[0] = add32(x[0], a); x[1] = add32(x[1], b); x[2] = add32(x[2], c); x[3] = add32(x[3], d);
  }
  function md5blk(bytes, off) {
    var md5blks = [];
    for (var i = 0; i < 16; i++) {
      md5blks[i] = bytes[off + i * 4] + (bytes[off + i * 4 + 1] << 8) + (bytes[off + i * 4 + 2] << 16) + (bytes[off + i * 4 + 3] << 24);
    }
    return md5blks;
  }
  return function (bytes) {
    var n = bytes.length;
    var state = [1732584193, -271733879, -1732584194, 271733878];
    var i;
    var padded = new Uint8Array((((n + 8) >> 6) + 1) << 6);
    padded.set(bytes);
    padded[n] = 0x80;
    var bitLen = n * 8;
    padded[padded.length - 8] = bitLen & 0xFF;
    padded[padded.length - 7] = (bitLen >>> 8) & 0xFF;
    padded[padded.length - 6] = (bitLen >>> 16) & 0xFF;
    padded[padded.length - 5] = (bitLen >>> 24) & 0xFF;
    for (i = 0; i < padded.length; i += 64) { md5cycle(state, md5blk(padded, i)); }
    var out = new Uint8Array(16);
    for (i = 0; i < 4; i++) {
      out[i * 4] = state[i] & 0xFF;
      out[i * 4 + 1] = (state[i] >>> 8) & 0xFF;
      out[i * 4 + 2] = (state[i] >>> 16) & 0xFF;
      out[i * 4 + 3] = (state[i] >>> 24) & 0xFF;
    }
    return out;
  };
})();
function R_hexBytes(hex) {
  var out = new Uint8Array(hex.length / 2);
  for (var i = 0; i < out.length; i++) { out[i] = parseInt(hex.substr(i * 2, 2), 16); }
  return out;
}
function R_concatBytes() {
  var total = 0;
  for (var i = 0; i < arguments.length; i++) { total += arguments[i].length; }
  var out = new Uint8Array(total);
  var off = 0;
  for (var j = 0; j < arguments.length; j++) { out.set(arguments[j], off); off += arguments[j].length; }
  return out;
}
function R_bytesToStr(bytes) {
  var s = '';
  for (var i = 0; i < bytes.length; i++) { s += String.fromCharCode(bytes[i]); }
  try { return decodeURIComponent(escape(s)); } catch (e) { return s; }
}
async function R_wpProtector(protectorEl) {
  var script = '';
  var src = protectorEl.attr('src');
  if (src && src.indexOf('data:text/javascript;base64,') === 0) {
    try { script = $.crypto.base64Decode(src.substring(src.indexOf(',') + 1)); } catch (e) { script = protectorEl.html(); }
  } else {
    script = protectorEl.html();
  }
  var mPass = script.match(/wpmangaprotectornonce\s*=\s*'([^']*)'/);
  var mData = script.match(/chapter_data\s*=\s*'([^']*)'/);
  if (!mPass || !mData) { return []; }
  var data;
  try { data = JSON.parse(mData[1].replace(/\\\//g, '/')); } catch (e2) { return []; }
  var salt = R_hexBytes(data.salt || '');
  var pw = new TextEncoder().encode(mPass[1]);
  var keyMaterial = [];
  var prev = new Uint8Array(0);
  while (keyMaterial.reduce(function (s, b) { return s + b.length; }, 0) < 48) {
    prev = R_md5bin(R_concatBytes(prev, pw, salt));
    keyMaterial.push(prev);
  }
  var keyIv = R_concatBytes.apply(null, keyMaterial).subarray(0, 48);
  var key = keyIv.subarray(0, 32);
  var iv = keyIv.subarray(32, 48);
  try {
    var subtle = crypto.subtle;
    var k = await subtle.importKey('raw', key, { name: 'AES-CBC' }, false, ['decrypt']);
    var b64 = atob(data.ciphertext);
    var enc = new Uint8Array(b64.length);
    for (var i = 0; i < b64.length; i++) { enc[i] = b64.charCodeAt(i); }
    var buf = await subtle.decrypt({ name: 'AES-CBC', iv: iv }, k, enc);
    var raw = R_bytesToStr(new Uint8Array(buf));
    var list = JSON.parse(raw);
    if (typeof list === 'string') { list = JSON.parse(list); }
    return Array.isArray(list) ? list : [];
  } catch (e3) { return []; }
}
// ---------------- end shared runtime ----------------

;
// Mihon JSVM theme factories. Prepended after plugin_runtime_wp.js helpers (R_*).
// Used by generated catalog plugins: module.exports = MihonTheme.create(CFG);
(function (g) {
  'use strict';

  function trimSlash(u) {
    return String(u || '').replace(/\/+$/, '');
  }

  function joinUrl(base, path) {
    if (!path) { return base; }
    if (/^https?:\/\//i.test(path)) { return path; }
    var b = trimSlash(base);
    var p = String(path);
    if (p.charAt(0) !== '/') { p = '/' + p; }
    return b + p;
  }

  function hdr(base) {
    return { Referer: trimSlash(base) + '/' };
  }

  function xhr(base) {
    return R_xhr({ Referer: trimSlash(base) + '/' });
  }

  function docOf(html) {
    return $.html(html || '');
  }

  function mangaOf(url, title, cover) {
    var key = url || '';
    return {
      key: key,
      url: key,
      title: title || '',
      coverUrl: cover || '',
      thumbnailUrl: cover || ''
    };
  }

  function chapterOf(url, name, dateUpload, i) {
    return {
      key: url,
      url: url,
      name: name || '',
      dateUpload: dateUpload || 0,
      sortOrder: i || 0
    };
  }

  function pagesOf(urls, pageUrl) {
    var out = [];
    for (var i = 0; i < urls.length; i++) {
      if (!urls[i]) { continue; }
      out.push({ index: out.length, url: pageUrl || '', imageUrl: urls[i] });
    }
    return out;
  }

  function parseCards(html, cardCss, linkCss, imgCss, base) {
    var cards = docOf(html).select(cardCss);
    var mangas = [];
    for (var i = 0; i < cards.length; i++) {
      var card = cards[i];
      var a = linkCss ? R_selFirst(card, linkCss) : (R_selFirst(card, 'a') || card);
      if (!a) { continue; }
      var href = a.attr('href') || '';
      if (!href) { continue; }
      var title = a.attr('title') || a.text() || '';
      var img = imgCss ? R_selFirst(card, imgCss) : R_selFirst(card, 'img');
      mangas.push(mangaOf(R_path(R_abs(href)) || R_abs(href), title, img ? R_img(img) : ''));
    }
    return mangas;
  }

  function hasNext(html, css) {
    if (!css) { return false; }
    try { return docOf(html).select(css).length > 0; } catch (e) { return false; }
  }

  function parseChapterList(html, base, selector) {
    var items = docOf(html).select(selector);
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      var a = R_selFirst(el, 'a');
      if (!a) { continue; }
      var href = a.attr('href') || '';
      if (!href) { continue; }
      var name = '';
      var named = R_selFirst(el, '.lch a, .chapternum, a');
      name = named ? named.text() : a.text();
      var dateEl = R_selFirst(el, 'span.chapter-release-date, .chapterdate, div.col-xs-4, .chapter-time, time');
      var dateTxt = '';
      if (dateEl) { dateTxt = dateEl.attr('datetime') || dateEl.attr('title') || dateEl.text(); }
      if (!dateTxt) {
        var imgAlt = R_selFirst(el, 'img:not(.thumb)');
        if (imgAlt) { dateTxt = imgAlt.attr('alt'); }
      }
      out.push(chapterOf(R_abs(href), name, R_date(dateTxt), i));
    }
    return out;
  }

  function parseImgs(html, selector, pageUrl) {
    var imgs = docOf(html).select(selector);
    var urls = [];
    var seen = {};
    for (var i = 0; i < imgs.length; i++) {
      var u = R_img(imgs[i]);
      if (!u || seen[u]) { continue; }
      seen[u] = true;
      urls.push(u);
    }
    return pagesOf(urls, pageUrl);
  }

  async function parseMadaraPages(html, pageUrl) {
    var protector = docOf(html).select('#chapter-protector-data')[0];
    if (protector) {
      var list = await R_wpProtector(protector);
      if (list && list.length) { return pagesOf(list, pageUrl); }
    }
    var pages = parseImgs(html,
      'div.page-break img, li.blocks-gallery-item img, .reading-content img, div.page-chapter > img',
      pageUrl);
    if (pages.length) { return pages; }
    return parseTsReader(html, pageUrl);
  }

  function parseTsReader(html, pageUrl) {
    var decoded = String(html || '');
    var m64 = decoded.match(/src=["']data:text\/javascript;base64,([^"']+)["']/);
    if (m64) {
      try { decoded += '\n' + atob(m64[1]); } catch (e) { /* ignore */ }
    }
    var m = decoded.match(/["']images["']\s*:\s*(\[[^\]]*])/);
    if (!m) { return []; }
    try {
      var list = JSON.parse(m[1].replace(/'/g, '"'));
      return pagesOf(Array.isArray(list) ? list : [], pageUrl);
    } catch (e2) { return []; }
  }

  function detailText(root, css) {
    var el = R_selFirst(root, css);
    return el ? el.text() : '';
  }

  function exportApi(cfg, impl) {
    var BASE = trimSlash(cfg.baseUrl);
    var api = {
      metadata: {
        id: cfg.key || cfg.name || 'src',
        name: cfg.name || '',
        lang: cfg.lang || '',
        baseUrl: BASE
      },
      getPopularManga: impl.getPopularManga,
      getLatestManga: impl.getLatestManga,
      getSearchManga: impl.getSearchManga,
      getMangaDetail: impl.getMangaDetail,
      getChapterList: impl.getChapterList,
      getPageList: impl.getPageList,
      getHeaders: function () { return hdr(BASE); }
    };
    return api;
  }

  function makeMadara(cfg) {
    var BASE = trimSlash(cfg.baseUrl);
    var sub = cfg.mangaSubString || 'manga';
    var useAjax = cfg.useAjax !== false;
    var PAGE = 25;

    function absManga(url) {
      if (/^https?:\/\//i.test(url)) { return url; }
      return joinUrl(BASE, url);
    }

    function parseArchive(html) {
      var cards = docOf(html).select('div.page-item-detail, .manga__item, .c-tabs-item__content, .listupd .bs .bsx');
      var mangas = [];
      for (var i = 0; i < cards.length; i++) {
        var card = cards[i];
        var a = R_selFirst(card, '.post-title a, h3 a, h5 a, a');
        if (!a) { continue; }
        var href = a.attr('href') || '';
        if (!href) { continue; }
        var img = R_selFirst(card, 'img');
        mangas.push(mangaOf(R_path(R_abs(href)) || R_abs(href), a.text() || a.attr('title'), img ? R_img(img) : ''));
      }
      return mangas;
    }

    function ajaxList(page, mode, query) {
      var pairs = [
        ['action', 'madara_load_more'],
        ['page', String(page - 1)],
        ['template', 'madara-core/content/content-archive'],
        ['vars[paged]', '1'],
        ['vars[template]', 'archive'],
        ['vars[posts_per_page]', String(PAGE)],
        ['vars[post_type]', 'wp-manga'],
        ['vars[post_status]', 'publish'],
        ['vars[manga_archives_item_layout]', 'big_thumbnail']
      ];
      if (mode === 'popular') {
        pairs.push(['vars[orderby]', 'meta_value_num'], ['vars[meta_key]', '_wp_manga_views'], ['vars[order]', 'DESC']);
      } else if (mode === 'latest') {
        pairs.push(['vars[orderby]', 'meta_value_num'], ['vars[meta_key]', '_latest_update'], ['vars[order]', 'DESC']);
      } else if (query) {
        pairs.push(['vars[s]', query]);
      }
      var html = $.http.post(BASE + '/wp-admin/admin-ajax.php', R_form(pairs), xhr(BASE));
      return parseArchive(html);
    }

    function htmlList(page, order, query) {
      var url = BASE + '/' + sub + '/';
      if (page > 1) { url += 'page/' + page + '/'; }
      var q = [];
      if (order) { q.push('m_orderby=' + encodeURIComponent(order)); }
      if (query) { q.push('s=' + encodeURIComponent(query)); }
      if (q.length) { url += (url.indexOf('?') >= 0 ? '&' : '?') + q.join('&'); }
      return parseArchive($.http.get(url, hdr(BASE)));
    }

    function listPage(page, mode, query) {
      var mangas = [];
      if (useAjax) {
        try { mangas = ajaxList(page, mode, query); } catch (e) { mangas = []; }
      }
      if (!mangas.length) {
        var order = mode === 'latest' ? 'latest' : (mode === 'search' ? '' : 'views');
        try { mangas = htmlList(page, order, query); } catch (e2) { mangas = []; }
      }
      if (!mangas.length && query) {
        try {
          mangas = parseArchive($.http.get(BASE + '/?s=' + encodeURIComponent(query) + '&post_type=wp-manga', hdr(BASE)));
        } catch (e3) { mangas = []; }
      }
      return { mangas: mangas, hasNextPage: mangas.length >= PAGE };
    }

    return exportApi(cfg, {
      getPopularManga: function (page) { return listPage(page || 1, 'popular'); },
      getLatestManga: function (page) { return listPage(page || 1, 'latest'); },
      getSearchManga: function (page, query) { return listPage(page || 1, 'search', query || ''); },
      getMangaDetail: function (url) {
        var html = $.http.get(absManga(url), hdr(BASE));
        var root = docOf(html);
        var titleEl = R_selFirst(root, 'div.post-title h1, div.post-title h3, #manga-title > h1, h1');
        var descEl = R_selFirst(root, 'div.description-summary div.summary__content, div.summary_content div.manga-excerpt, .description-summary');
        var thumb = R_selFirst(root, 'div.summary_image img, .summary_image img');
        var statusEl = R_selFirst(root, 'div.post-content_item:contains(Status) .summary-content, div.summary-content, .post-status .summary-content');
        var authors = root.select('div.author-content > a, div.manga-authors > a');
        var author = [];
        for (var i = 0; i < authors.length; i++) { author.push(authors[i].text()); }
        var genres = root.select('div.genres-content a, div.tags-content a');
        var genre = [];
        for (var gix = 0; gix < genres.length; gix++) { genre.push(genres[gix].text()); }
        return {
          key: url,
          url: url,
          title: titleEl ? (R_ownText(titleEl) || titleEl.text()) : '',
          coverUrl: thumb ? R_img(thumb) : '',
          thumbnailUrl: thumb ? R_img(thumb) : '',
          author: author.join(', '),
          description: descEl ? descEl.text() : '',
          genre: genre,
          status: R_status(statusEl ? statusEl.text() : '')
        };
      },
      getChapterList: function (url) {
        var mangaUrl = absManga(url);
        var html = $.http.get(mangaUrl, hdr(BASE));
        var ch = parseChapterList(html, BASE, 'li.wp-manga-chapter, li.wp-manga-chapter-nsfw, .listing-chapters_wrap li');
        if (!ch.length) {
          try {
            var ajaxHtml = $.http.post(mangaUrl.replace(/\/?$/, '/') + 'ajax/chapters/', '', xhr(BASE));
            ch = parseChapterList(ajaxHtml, BASE, 'li.wp-manga-chapter, li.wp-manga-chapter-nsfw, li');
          } catch (e) { /* ignore */ }
        }
        if (!ch.length) {
          var idEl = R_selFirst(docOf(html), '[id^=manga-chapters-holder], input.rating-post-id, a[data-post]');
          var id = '';
          if (idEl) { id = idEl.attr('data-id') || idEl.attr('value') || idEl.attr('data-post') || ''; }
          if (id) {
            try {
              var body = R_form([['action', 'manga_get_chapters'], ['manga', id]]);
              ch = parseChapterList($.http.post(BASE + '/wp-admin/admin-ajax.php', body, xhr(BASE)), BASE, 'li.wp-manga-chapter, li');
            } catch (e2) { /* ignore */ }
          }
        }
        return ch;
      },
      getPageList: async function (url) {
        var chapterUrl = absManga(url);
        var html = $.http.get(chapterUrl, hdr(BASE));
        if (docOf(html).select('#single-pager').length) {
          html = $.http.get(chapterUrl + (chapterUrl.indexOf('?') >= 0 ? '&' : '?') + 'style=list', hdr(BASE));
        }
        return parseMadaraPages(html, chapterUrl);
      }
    });
  }

  function makeMangaThemesia(cfg) {
    var BASE = trimSlash(cfg.baseUrl);
    var dir = cfg.mangaUrlDirectory || '/manga';
    if (dir.charAt(0) !== '/') { dir = '/' + dir; }

    function listUrl(page, query, order) {
      var url = BASE + dir + '/?page=' + (page || 1);
      if (query) { url += '&title=' + encodeURIComponent(query); }
      if (order) { url += '&order=' + encodeURIComponent(order); }
      return url;
    }

    function parseList(html) {
      var mangas = parseCards(html, '.utao .uta .imgu, .listupd .bs .bsx, .listo .bs .bsx, .listupd .bs', 'a', 'img', BASE);
      return { mangas: mangas, hasNextPage: hasNext(html, 'div.pagination .next, div.hpage .r, a.next') };
    }

    return exportApi(cfg, {
      getPopularManga: function (page) { return parseList($.http.get(listUrl(page, '', 'popular'), hdr(BASE))); },
      getLatestManga: function (page) { return parseList($.http.get(listUrl(page, '', 'update'), hdr(BASE))); },
      getSearchManga: function (page, query) { return parseList($.http.get(listUrl(page, query || '', ''), hdr(BASE))); },
      getMangaDetail: function (url) {
        var pageUrl = /^https?:\/\//i.test(url) ? url : joinUrl(BASE, url);
        var html = $.http.get(pageUrl, hdr(BASE));
        var root = docOf(html);
        var box = R_selFirst(root, 'div.bigcontent, div.animefull, div.main-info, div.postbody') || root;
        var titleEl = R_selFirst(box, '.entry-title, h1');
        var descEl = R_selFirst(box, '.desc, .entry-content[itemprop=description], .entry-content');
        var thumb = R_selFirst(box, '.infomanga img, .thumb img, img[itemprop=image]');
        var statusEl = R_selFirst(box, '.tsinfo .imptdt i, .infotable tr td');
        var authorEl = R_selFirst(box, '.fmed b + span, .tsinfo .imptdt i');
        var genres = box.select('div.gnr a, .mgen a, .seriestugenre a');
        var genre = [];
        for (var i = 0; i < genres.length; i++) { genre.push(genres[i].text()); }
        return {
          key: url,
          url: url,
          title: titleEl ? titleEl.text() : '',
          coverUrl: thumb ? R_img(thumb) : '',
          thumbnailUrl: thumb ? R_img(thumb) : '',
          author: authorEl ? R_ownText(authorEl) : '',
          description: descEl ? descEl.text() : '',
          genre: genre,
          status: R_status(statusEl ? statusEl.text() : detailText(box, '.tsinfo .imptdt'))
        };
      },
      getChapterList: function (url) {
        var pageUrl = /^https?:\/\//i.test(url) ? url : joinUrl(BASE, url);
        var html = $.http.get(pageUrl, hdr(BASE));
        return parseChapterList(html, BASE, 'div.bxcl li, div.cl li, #chapterlist li, ul li:has(div.chbox), #chapterlist ul li');
      },
      getPageList: async function (url) {
        var chapterUrl = /^https?:\/\//i.test(url) ? url : joinUrl(BASE, url);
        var html = $.http.get(chapterUrl, hdr(BASE));
        var pages = parseImgs(html, cfg.pageSelector || 'div#readerarea img, #readerarea img, .rd-chapter-imgs img', chapterUrl);
        if (pages.length) { return pages; }
        pages = parseTsReader(html, chapterUrl);
        if (pages.length) { return pages; }
        return parseMadaraPages(html, chapterUrl);
      }
    });
  }

  function makeWpcomics(cfg) {
    var BASE = trimSlash(cfg.baseUrl);
    var popularPath = cfg.popularPath || 'hot';
    var searchPath = cfg.searchPath || 'tim-truyen';
    var queryParam = cfg.queryParam || 'keyword';

    function parseList(html) {
      var mangas = parseCards(html, 'div.items div.item, .items .item', 'h3 a, a', 'div.image img, img', BASE);
      return { mangas: mangas, hasNextPage: hasNext(html, 'a.next-page, a[rel=next]') };
    }

    return exportApi(cfg, {
      getPopularManga: function (page) {
        var url = BASE + '/' + popularPath + (page > 1 ? '?page=' + page : '');
        return parseList($.http.get(url, hdr(BASE)));
      },
      getLatestManga: function (page) {
        var url = BASE + (page > 1 ? '/?page=' + page : '/');
        return parseList($.http.get(url, hdr(BASE)));
      },
      getSearchManga: function (page, query) {
        var url = BASE + '/' + searchPath + '?' + queryParam + '=' + encodeURIComponent(query || '') + '&page=' + (page || 1);
        return parseList($.http.get(url, hdr(BASE)));
      },
      getMangaDetail: function (url) {
        var pageUrl = /^https?:\/\//i.test(url) ? url : joinUrl(BASE, url);
        var html = $.http.get(pageUrl, hdr(BASE));
        var info = R_selFirst(docOf(html), 'article#item-detail, .detail-info') || docOf(html);
        var thumb = R_selFirst(info, 'div.col-image img, .col-image img, img');
        var genres = info.select('li.kind p.col-xs-8 a, .kind a');
        var genre = [];
        for (var i = 0; i < genres.length; i++) { genre.push(genres[i].text()); }
        var descEls = info.select('div.detail-content p, .detail-content');
        var desc = [];
        for (var d = 0; d < descEls.length; d++) { desc.push(descEls[d].text()); }
        return {
          key: url,
          url: url,
          title: detailText(info, 'h1, .title-detail'),
          coverUrl: thumb ? R_img(thumb) : '',
          thumbnailUrl: thumb ? R_img(thumb) : '',
          author: detailText(info, 'li.author p.col-xs-8, .author'),
          description: desc.join('\n'),
          genre: genre,
          status: R_status(detailText(info, 'li.status p.col-xs-8, .status'))
        };
      },
      getChapterList: function (url) {
        var pageUrl = /^https?:\/\//i.test(url) ? url : joinUrl(BASE, url);
        var html = $.http.get(pageUrl, hdr(BASE));
        return parseChapterList(html, BASE, 'div.list-chapter li.row:not(.heading), .list-chapter li, #nt_listchapter li');
      },
      getPageList: async function (url) {
        var chapterUrl = /^https?:\/\//i.test(url) ? url : joinUrl(BASE, url);
        var html = $.http.get(chapterUrl, hdr(BASE));
        return parseImgs(html, 'div.page-chapter > img, li.blocks-gallery-item img, .page-chapter img', chapterUrl);
      }
    });
  }

  function makeGeneric(cfg) {
    var BASE = trimSlash(cfg.baseUrl);
    var dir = cfg.mangaUrlDirectory || cfg.mangaSubString || 'manga';
    if (dir.charAt(0) !== '/') { dir = '/' + dir; }

    var CARD_SETS = [
      '.listupd .bs .bsx',
      'div.page-item-detail',
      'div.items div.item',
      '.page-item-detail',
      '#slide-top > .item',
      'div.item, .series-item, article.item, .manga-item'
    ];

    function bestCards(html) {
      var best = [];
      for (var i = 0; i < CARD_SETS.length; i++) {
        var mangas = parseCards(html, CARD_SETS[i], 'h3 a, .post-title a, .info-item a, a', 'img', BASE);
        if (mangas.length > best.length) { best = mangas; }
      }
      return best;
    }

    function listAt(url) {
      var html = $.http.get(url, hdr(BASE));
      return { mangas: bestCards(html), hasNextPage: hasNext(html, 'a.next, a.next-page, a[rel=next], div.pagination .next, .hpage .r') };
    }

    return exportApi(cfg, {
      getPopularManga: function (page) {
        var tries = [
          BASE + dir + '/?page=' + (page || 1) + '&order=popular',
          BASE + '/hot' + (page > 1 ? '?page=' + page : ''),
          BASE + (page > 1 ? '/?page=' + page : '/')
        ];
        for (var i = 0; i < tries.length; i++) {
          try {
            var r = listAt(tries[i]);
            if (r.mangas.length) { return r; }
          } catch (e) { /* try next */ }
        }
        return { mangas: [], hasNextPage: false };
      },
      getLatestManga: function (page) {
        var tries = [
          BASE + dir + '/?page=' + (page || 1) + '&order=update',
          BASE + (page > 1 ? '/?page=' + page : '/')
        ];
        for (var i = 0; i < tries.length; i++) {
          try {
            var r = listAt(tries[i]);
            if (r.mangas.length) { return r; }
          } catch (e) { /* try next */ }
        }
        return { mangas: [], hasNextPage: false };
      },
      getSearchManga: function (page, query) {
        var q = query || '';
        var tries = [
          BASE + dir + '/?title=' + encodeURIComponent(q) + '&page=' + (page || 1),
          BASE + '/?s=' + encodeURIComponent(q) + '&page=' + (page || 1),
          BASE + '/search?s=' + encodeURIComponent(q) + '&page=' + (page || 1),
          BASE + '/tim-truyen?keyword=' + encodeURIComponent(q) + '&page=' + (page || 1)
        ];
        for (var i = 0; i < tries.length; i++) {
          try {
            var r = listAt(tries[i]);
            if (r.mangas.length) { return r; }
          } catch (e) { /* try next */ }
        }
        return { mangas: [], hasNextPage: false };
      },
      getMangaDetail: function (url) {
        var pageUrl = /^https?:\/\//i.test(url) ? url : joinUrl(BASE, url);
        var html = $.http.get(pageUrl, hdr(BASE));
        var root = docOf(html);
        var titleEl = R_selFirst(root, 'h1, .entry-title, div.post-title h1, .title-detail');
        var descEl = R_selFirst(root, '.desc, .summary__content, .detail-content, .entry-content, .description');
        var thumb = R_selFirst(root, '.thumb img, .summary_image img, .col-image img, img[itemprop=image]');
        return {
          key: url,
          url: url,
          title: titleEl ? titleEl.text() : '',
          coverUrl: thumb ? R_img(thumb) : '',
          thumbnailUrl: thumb ? R_img(thumb) : '',
          author: detailText(root, '.author-content a, li.author p.col-xs-8, .fmed span'),
          description: descEl ? descEl.text() : '',
          genre: (function () {
            var els = root.select('.mgen a, .genres-content a, li.kind a, .seriestugenre a');
            var g = [];
            for (var i = 0; i < els.length; i++) { g.push(els[i].text()); }
            return g;
          })(),
          status: R_status(detailText(root, '.post-status, li.status p.col-xs-8, .tsinfo .imptdt'))
        };
      },
      getChapterList: function (url) {
        var pageUrl = /^https?:\/\//i.test(url) ? url : joinUrl(BASE, url);
        var html = $.http.get(pageUrl, hdr(BASE));
        var selectors = [
          'li.wp-manga-chapter',
          '#chapterlist li',
          'div.list-chapter li',
          'div.bxcl li, div.cl li',
          'ul.chapter-list li, .chapter-list li, #nt_listchapter li'
        ];
        for (var i = 0; i < selectors.length; i++) {
          var ch = parseChapterList(html, BASE, selectors[i]);
          if (ch.length) { return ch; }
        }
        try {
          var ajaxHtml = $.http.post(pageUrl.replace(/\/?$/, '/') + 'ajax/chapters/', '', xhr(BASE));
          var ch2 = parseChapterList(ajaxHtml, BASE, 'li.wp-manga-chapter, li');
          if (ch2.length) { return ch2; }
        } catch (e) { /* ignore */ }
        return [];
      },
      getPageList: async function (url) {
        var chapterUrl = /^https?:\/\//i.test(url) ? url : joinUrl(BASE, url);
        var html = $.http.get(chapterUrl, hdr(BASE));
        var pages = await parseMadaraPages(html, chapterUrl);
        if (pages.length) { return pages; }
        return parseImgs(html, '#readerarea img, .reading-content img, .page-chapter img, #chapter-images img, img.chapter-img', chapterUrl);
      }
    });
  }

  var THEME_MAP = {
    madara: makeMadara,
    madaralegacy: makeMadara,
    mangathemesia: makeMangaThemesia,
    wpcomics: makeWpcomics,
    manhwaz: makeGeneric,
    generic: makeGeneric
  };

  g.MihonTheme = {
    create: function (cfg) {
      cfg = cfg || {};
      g.BASE = trimSlash(cfg.baseUrl || '');
      var theme = String(cfg.theme || 'generic').toLowerCase();
      var fn = THEME_MAP[theme] || makeGeneric;
      return fn(cfg);
    }
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);

