// InitManga theme engine (korelimanga, merlinscans, orimanga, paradoxscans, ragnarscans, siyahmelek)
// HTML lists + wp-json search + AES-CBC(PBKDF2-SHA512) encrypted chapter pages.
export const runtime = 'wp';

const DEFAULTS = {
  mangaUrlDirectory: 'seri',
  popularUrlSlug: '',
  latestUrlSlug: 'son-guncellemeler',
  popularSelector: 'div.manga-item-grid > div.uk-panel, div.uk-panel.uk-position-relative',
  popularStyle: 'base',       // 'base' | 'simple' | 'paradox'
  detailsStyle: 'base',       // 'base' | 'simple'
  chapterPageSlug: 'bolum',   // 'bolum' | 'chapter'
  chapterStyle: 'html',       // 'html' | 'api'
  ragnarStyle: false,
  merlinLock: false,
};

function extractStr(kt, name) {
  const m = kt.match(new RegExp(`${name}\\s*(?::\\s*String\\s*)?=\\s*"((?:[^"\\\\]|\\\\.)*)"`));
  return m ? m[1] : undefined;
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  const dir = extractStr(kt, 'mangaUrlDirectory');
  if (dir !== undefined) { config.mangaUrlDirectory = dir; }
  config.popularUrlSlug = config.mangaUrlDirectory;

  const pop = extractStr(kt, 'popularUrlSlug');
  if (pop !== undefined) { config.popularUrlSlug = pop; }

  const lat = extractStr(kt, 'latestUrlSlug');
  if (lat !== undefined) { config.latestUrlSlug = lat; }

  if (/selectFirst\("h2 a"\)/.test(kt)) {
    config.popularStyle = 'simple';
  } else if (/popularMangaSelector\(\)\s*=\s*"div\.manga-item-grid > div\.uk-panel"/.test(kt)) {
    config.popularStyle = 'paradox';
    config.popularSelector = 'div.manga-item-grid > div.uk-panel';
  }

  if (/div#manga-description p/.test(kt)) {
    config.detailsStyle = 'simple';
  }

  if (/addPathSegment\("chapter"\)/.test(kt)) {
    config.chapterPageSlug = 'chapter';
  }

  if (/wp-json\/wp\/v2\/manga/.test(kt)) {
    config.chapterStyle = 'api';
  }

  if (/uk-tooltip/.test(kt)) {
    config.ragnarStyle = true;
  }

  if (/lock-card/.test(kt)) {
    config.merlinLock = true;
  }

  warnings.push('chapter pages use PBKDF2/AES decryption via crypto.subtle');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: initmanga)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_sel/R_selFirst/R_img)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- initmanga engine ----------------
function initHeaders() {
  return { Referer: BASE + '/' };
}

function hasNextPageManual(doc) {
  if (R_selFirst(doc, 'link[rel=next]')) { return true; }
  var links = R_sel(doc, 'ul.uk-pagination a');
  for (var i = 0; i < links.length; i++) {
    var href = links[i].attr('href') || '';
    if (href.indexOf('http') === 0 && !String(links[i].text() || '').trim()) { return true; }
  }
  return false;
}

function itemLink(el) {
  return R_selFirst(el, 'h2 a') || R_selFirst(el, 'h3 a') ||
    R_selFirst(el, 'div.uk-overflow-hidden a') || R_selFirst(el, 'a');
}

function itemTitle(el, link) {
  var h = R_selFirst(el, 'h2 a') || R_selFirst(el, 'h3 a');
  if (h && h.text()) { return h.text(); }
  var h3 = R_selFirst(el, 'h3');
  if (h3 && h3.text()) { return h3.text(); }
  var h2 = R_selFirst(el, 'h2');
  if (h2 && h2.text()) { return h2.text(); }
  return link ? link.text() : '';
}

function itemCover(el) {
  var img = R_selFirst(el, 'img');
  if (!img) { return ''; }
  var v = img.attr('data-src');
  if (v) { return img.absUrl('data-src'); }
  return img.absUrl('src');
}

function parseList(doc) {
  var out = [];
  var seen = {};
  var els = R_sel(doc, CFG.popularSelector);
  for (var i = 0; i < els.length; i++) {
    var link = itemLink(els[i]);
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var key = R_path(href);
    if (!key || seen[key]) { continue; }
    seen[key] = true;
    out.push({
      key: key,
      title: itemTitle(els[i], link),
      coverUrl: itemCover(els[i])
    });
  }
  return out;
}

// "Label: <a|span>value</a|span><br>" repeated inside div.manga-info-details
function parseInfoLabels(doc) {
  var out = {};
  var info = R_selFirst(doc, 'div.manga-info-details');
  if (!info) { return out; }
  var parts = String(info.html() || '').split(/<br\\s*\\/?>/i);
  for (var i = 0; i < parts.length; i++) {
    var text = parts[i].replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').trim();
    var m = text.match(/^([^:]{1,40}):\\s*(.+)$/);
    if (m && !out[m[1].trim()]) { out[m[1].trim()] = m[2].trim(); }
  }
  return out;
}

function initStatus(statusText) {
  var s = String(statusText || '').toLowerCase();
  if (!s) { return ''; }
  if (s.indexOf('g\\u00FCncel') >= 0 || s.indexOf('devam') >= 0 || s.indexOf('ongoing') >= 0) { return 'ongoing'; }
  if (s.indexOf('tamamland') >= 0 || s.indexOf('bitti') >= 0 || s.indexOf('completed') >= 0 ||
    (s.indexOf('final') >= 0 && s.indexOf('sezon') < 0)) { return 'completed'; }
  if (s.indexOf('ara ver') >= 0 || s.indexOf('sezon') >= 0 || s.indexOf('hiatus') >= 0) { return 'hiatus'; }
  if (s.indexOf('b\\u0131rak\\u0131ld\\u0131') >= 0 || s.indexOf('iptal') >= 0 || s.indexOf('dropped') >= 0 || s.indexOf('cancel') >= 0) { return 'cancelled'; }
  return '';
}

function parseDetail(doc, key) {
  var desc = '';
  var alt = R_selFirst(doc, 'span#comic-othername');
  var altName = alt ? alt.text() : '';

  if (CFG.detailsStyle === 'simple') {
    var ps = R_sel(doc, 'div#manga-description > p');
    var parts = [];
    for (var i = 0; i < ps.length; i++) {
      if (ps[i].text()) { parts.push(ps[i].text()); }
    }
    desc = parts.join('\\n\\n');
  } else {
    var dEl = R_selFirst(doc, 'div#manga-description');
    if (dEl) { desc = dEl.text(); }
  }
  if (altName) {
    desc += (desc ? '\\n\\n' : '') + 'Alternatif Ba\\u015Fl\\u0131k: ' + altName;
  }

  var genre = '';
  var gEls;
  if (CFG.detailsStyle === 'simple') {
    gEls = R_sel(doc, 'div#genre-tags a[href*="/tur/"]');
    var g = [];
    for (var gi = 0; gi < gEls.length; gi++) { g.push(gEls[gi].text()); }
    genre = g.join(', ');
  } else {
    gEls = R_sel(doc, 'div.uk-flex.uk-flex-nowrap.uk-flex-left.uk-grid-small.uk-grid span.uk-label-contest');
    var g2 = [];
    for (var gj = 0; gj < gEls.length; gj++) {
      var t = String(gEls[gj].text() || '').replace(/^#/, '').trim();
      if (t) { g2.push(t); }
    }
    genre = g2.join(', ');
    if (!genre) {
      gEls = R_sel(doc, 'div#genre-tags a');
      var g3 = [];
      for (var gk = 0; gk < gEls.length; gk++) { g3.push(gEls[gk].text()); }
      genre = g3.join(', ');
    }
  }

  var info = parseInfoLabels(doc);
  var author = info['Yazar'] || '';
  var artist = info['\\u00C7izer'] || '';

  var statusText = '';
  var stEl = R_selFirst(doc, 'span#manga-status') || R_selFirst(doc, 'div.manga-status-ribbons span.manga-status-ribbon__text');
  if (stEl) { statusText = stEl.text(); }
  if (!statusText && info['Durum']) { statusText = info['Durum']; }

  var cover = '';
  var coverEl = R_selFirst(doc, 'div.story-cover-wrap img') || R_selFirst(doc, 'div.single-thumb img') ||
    R_selFirst(doc, 'a.story-cover img');
  if (coverEl) { cover = coverEl.absUrl('src'); }

  var title = '';
  var h1 = R_selFirst(doc, 'h1');
  if (h1 && h1.text()) { title = h1.text(); }
  if (!title) {
    var h2 = R_selFirst(doc, 'h2.uk-h3');
    if (h2) { title = h2.text(); }
  }

  return {
    key: key,
    title: title,
    coverUrl: cover,
    author: author,
    description: desc,
    genre: genre,
    status: initStatus(statusText)
  };
}

var TR_MONTHS = {
  'ocak': 0, '\\u015Fubat': 1, 'mart': 2, 'nisan': 3, 'may\\u0131s': 4, 'haziran': 5,
  'temmuz': 6, 'a\\u011Fustos': 7, 'eyl\\u00FCl': 8, 'ekim': 9, 'kas\\u0131m': 10, 'aral\\u0131k': 11
};

function parseRagnarDate(s) {
  var m = String(s || '').match(/(\\d{1,2})\\s+(\\S+)\\s+(\\d{4})\\s+(\\d{2}):(\\d{2})/);
  if (!m) { return 0; }
  var mon = TR_MONTHS[String(m[2]).toLowerCase()];
  if (mon === undefined) { return 0; }
  return new Date(+m[3], mon, +m[1], +m[4], +m[5], 0).getTime();
}

function parseChapterEls(doc) {
  var out = [];
  var sel = CFG.ragnarStyle ? 'div.chapter-list > div.chapter-item' : 'div.chapter-item';
  var els = R_sel(doc, sel);
  for (var i = 0; i < els.length; i++) {
    var link = R_selFirst(els[i], 'a');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var name = '';
    var date = 0;
    if (CFG.ragnarStyle) {
      var h3 = R_selFirst(els[i], 'h3.uk-link-heading');
      name = h3 ? String(h3.text()).split('\\u2013').pop().trim() : link.text();
      var tip = R_selFirst(els[i], 'div.uk-article-meta span[uk-tooltip]');
      if (tip) {
        var tv = String(tip.attr('uk-tooltip') || '');
        tv = tv.slice(tv.indexOf('title: ') >= 0 ? tv.indexOf('title: ') + 7 : 0);
        tv = tv.split(';')[0];
        date = parseRagnarDate(tv);
      }
    } else {
      var h3b = R_selFirst(els[i], 'h3');
      var raw = h3b ? h3b.text() : link.text();
      name = String(raw).split('\\u2013').pop().split('-').pop().trim();
      if (!name) { name = raw; }
      var time = R_selFirst(els[i], 'time');
      if (time) {
        var dt = Date.parse(String(time.attr('datetime') || '').replace(' ', 'T'));
        date = isNaN(dt) ? 0 : dt;
      }
    }
    out.push({
      key: R_path(href),
      name: name,
      chapterNumber: -1,
      dateUpload: date,
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

async function fetchChaptersHtml(mangaKey) {
  var chapters = [];
  var url = R_abs(mangaKey);
  var page = 2;
  var guard = 0;
  while (guard++ < 50) {
    var doc = $.html.parse(await $.http.get(url, initHeaders()));
    var items = parseChapterEls(doc);
    if (items.length === 0) { break; }
    chapters = chapters.concat(items);
    if (!hasNextPageManual(doc)) { break; }
    url = R_abs(mangaKey).replace(/\\/+$/, '') + '/' + CFG.chapterPageSlug + '/page/' + page + '/';
    page++;
  }
  return chapters;
}

async function fetchChaptersApi(mangaKey) {
  var slug = String(mangaKey).replace(/\\/+$/, '').split('/').pop() || '';
  var text = await $.http.get(BASE + '/wp-json/wp/v2/manga?slug=' + encodeURIComponent(slug) + '&_fields=id,link', initHeaders());
  var arr = JSON.parse(text);
  if (!arr || !arr.length) { return []; }
  var manga = arr[0];
  var mangaPath = R_path(manga.link || (BASE + mangaKey));
  var chapters = [];
  var page = 1;
  var totalPages = 1;
  while (page <= totalPages && page <= 50) {
    var cText = await $.http.get(BASE + '/wp-json/initmanga/v1/chapters?manga_id=' + manga.id +
      '&per_page=50&paged=' + page, initHeaders());
    var result = JSON.parse(cText);
    totalPages = result.totalPages || 1;
    var items = result.items || [];
    for (var i = 0; i < items.length; i++) {
      var ch = items[i];
      var num = String(ch.number || '').replace(/\\.0$/, '');
      var name = 'B\\u00F6l\\u00FCm ' + num;
      if (ch.title) { name += ' - ' + ch.title; }
      var dt = Date.parse(String(ch.createdAt || '').replace(' ', 'T'));
      chapters.push({
        key: mangaPath.replace(/\\/+$/, '') + '/' + ch.slug + '/',
        name: name,
        chapterNumber: parseFloat(ch.number) || -1,
        dateUpload: isNaN(dt) ? 0 : dt,
        pages: 0,
        sortOrder: 0
      });
    }
    page++;
  }
  return chapters;
}

// ---------- decryption ----------
function utf8Bytes(s) {
  var out = [];
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i);
    if (c < 0x80) { out.push(c); }
    else if (c < 0x800) { out.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F)); }
    else { out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F)); }
  }
  return new Uint8Array(out);
}

function utf8Str(bytes) {
  var s = '', i = 0;
  while (i < bytes.length) {
    var b = bytes[i];
    if (b < 0x80) { s += String.fromCharCode(b); i += 1; }
    else if (b < 0xE0) { s += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F)); i += 2; }
    else if (b < 0xF0) { s += String.fromCharCode(((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F)); i += 3; }
    else {
      var cp = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
      cp -= 0x10000;
      s += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
      i += 4;
    }
  }
  return s;
}

function b64Bytes(b64) {
  var bin = atob(String(b64).replace(/\\s/g, ''));
  var out = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) { out[i] = bin.charCodeAt(i); }
  return out;
}

function hexBytes(hex) {
  var h = String(hex || '');
  if (h.length % 2 !== 0) { return new Uint8Array(0); }
  var out = new Uint8Array(h.length / 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = parseInt(h.substr(i * 2, 2), 16);
  }
  return out;
}

async function aesDecrypt(ciphertextB64, passphrase, saltHex, ivHex) {
  var baseKey = await crypto.subtle.importKey('raw', utf8Bytes(passphrase), { name: 'PBKDF2' }, false, ['deriveBits']);
  var bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: hexBytes(saltHex), iterations: 999, hash: 'SHA-512' }, baseKey, 256);
  var aesKey = await crypto.subtle.importKey('raw', bits, { name: 'AES-CBC' }, false, ['decrypt']);
  var plain = await crypto.subtle.decrypt({ name: 'AES-CBC', iv: hexBytes(ivHex) }, aesKey, b64Bytes(ciphertextB64));
  return utf8Str(new Uint8Array(plain));
}

async function decryptLayered(html, ciphertext, ivHex, saltHex) {
  var rawKey = null;
  var extra = R_sel(html, 'script#init-main-js-extra');
  if (extra.length > 0) {
    var src = String(extra[0].attr('src') || '');
    if (src.indexOf('base64,') >= 0) {
      try {
        var decoded = $.crypto.base64Decode(src.slice(src.indexOf('base64,') + 7));
        var km = decoded.match(/["']?decryption_key["']?\\s*[:=]\\s*["']([^"']+)["']/);
        if (km) { rawKey = km[1]; }
      } catch (e) { /* ignore */ }
    }
  }
  if (!rawKey) {
    var sm = String(html).match(/InitMangaData[\\s\\S]*?decryption_key["']?\\s*[:=]\\s*["']([^"']+)["']/);
    if (sm) { rawKey = sm[1]; }
  }
  if (!rawKey) { return null; }
  try {
    var passphrase = $.crypto.base64Decode(rawKey);
    var result = await aesDecrypt(ciphertext, passphrase, saltHex, ivHex);
    var t = result.trim();
    if (t && (t.charAt(0) === '<' || t.charAt(0) === '[')) { return result; }
  } catch (e) { /* ignore */ }
  return null;
}

function pageSrc(el) {
  var attrs = ['data-original-src', 'data-src', 'src', 'data-lazy-src'];
  for (var i = 0; i < attrs.length; i++) {
    var v = el.attr(attrs[i]);
    if (!v) { continue; }
    if (/^https?:\\/\\//.test(v)) { return v; }
    if (v.indexOf('//') === 0) { return 'https:' + v; }
    if (v.charAt(0) === '/') { return BASE.replace(/\\/+$/, '') + v; }
    var abs = el.absUrl(attrs[i]);
    if (/^https?:\\/\\//.test(abs)) { return abs; }
  }
  return '';
}

function parseDecryptedPages(content) {
  var t = String(content).trim();
  var pages = [];
  if (t.charAt(0) === '<') {
    var doc = $.html.parse(t);
    var imgs = R_sel(doc, 'img');
    for (var i = 0; i < imgs.length; i++) {
      var u = pageSrc(imgs[i]);
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
  } else if (t.charAt(0) === '[') {
    try {
      var arr = JSON.parse(t);
      for (var j = 0; j < arr.length; j++) {
        var src = String(arr[j]);
        var u2;
        if (src.indexOf('//') === 0) { u2 = 'https:' + src; }
        else if (src.charAt(0) === '/') { u2 = BASE.replace(/\\/+$/, '') + src; }
        else { u2 = src; }
        if (u2) { pages.push({ index: pages.length, url: u2 }); }
      }
    } catch (e) { /* ignore */ }
  }
  return pages;
}

function fallbackPages(doc) {
  var pages = [];
  var els = R_sel(doc, 'div#chapter-content img[src]');
  for (var i = 0; i < els.length; i++) {
    var u = els[i].absUrl('src');
    if (!u) { u = els[i].absUrl('data-src'); }
    if (u) { pages.push({ index: pages.length, url: u }); }
  }
  return pages;
}

async function parsePages(doc) {
  var encryptedB64 = '';
  var scriptEl = R_selFirst(doc, 'script[src*=dmFyIElua]');
  if (scriptEl) {
    var src = String(scriptEl.attr('src') || '');
    if (src.indexOf('base64,') >= 0) {
      encryptedB64 = src.slice(src.indexOf('base64,') + 7);
    }
  }

  var html = '';
  var reEncrypted = /var\\s+InitMangaEncryptedChapter\\s*=\\s*(\\{[\\s\\S]*?\\});/;
  if (encryptedB64) {
    try {
      var decodedStr = $.crypto.base64Decode(encryptedB64);
      var m = decodedStr.match(/InitMangaEncryptedChapter\\s*=\\s*(\\{[\\s\\S]*?\\})/);
      var jsonString = m ? m[1] : null;
      if (!jsonString) {
        var after = decodedStr.slice(decodedStr.indexOf('InitMangaEncryptedChapter='));
        if (after) { jsonString = after.slice(after.indexOf('=') + 1).split(';').slice(0, -1).join(';'); }
      }
      if (jsonString) {
        html = wholeHtml(doc);
        var enc = JSON.parse(jsonString);
        var dec = await decryptLayered(html, enc.ciphertext, enc.iv, enc.salt);
        if (dec) { return parseDecryptedPages(dec); }
      }
    } catch (e) { /* fall through */ }
  } else {
    // RagnarScans variant: encrypted object embedded directly in page HTML
    html = wholeHtml(doc);
    var m2 = html.match(reEncrypted);
    if (m2) {
      try {
        var enc2 = JSON.parse(m2[1]);
        var dec2 = await decryptLayered(html, enc2.ciphertext, enc2.iv, enc2.salt);
        if (dec2) { return parseDecryptedPages(dec2); }
      } catch (e2) { /* fall through */ }
    }
  }
  return fallbackPages(doc);
}

function wholeHtml(doc) {
  var scripts = R_sel(doc, 'script');
  var parts = [];
  for (var i = 0; i < scripts.length; i++) {
    parts.push(scripts[i].html() || '');
  }
  return parts.join('\\n');
}

module.exports = {
  getPopularManga: async function (page) {
    var path = page === 1 ? '' : 'page/' + page + '/';
    var doc = $.html.parse(await $.http.get(BASE + '/' + CFG.popularUrlSlug + '/' + path, initHeaders()));
    return { mangas: parseList(doc), hasNextPage: hasNextPageManual(doc) };
  },

  getSearchManga: async function (page, query) {
    var url = BASE + '/wp-json/initlise/v1/search?term=' + encodeURIComponent(query || '') + '&page=' + page;
    var text = await $.http.get(url, initHeaders());
    var trimmed = String(text).replace(/^\\s+/, '');
    if (trimmed.charAt(0) === '<') {
      var doc = $.html.parse(text);
      return { mangas: parseList(doc), hasNextPage: hasNextPageManual(doc) };
    }
    var list = JSON.parse(text);
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var it = list[i];
      var cleanUrl = String(it.url || '').trim();
      if (!cleanUrl) { continue; }
      out.push({
        key: R_path(cleanUrl),
        title: String(it.title || '').replace(/<[^>]*>/g, ''),
        coverUrl: it.thumb || ''
      });
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), initHeaders()));
    return parseDetail(doc, mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var chapters;
    if (CFG.chapterStyle === 'api') {
      chapters = await fetchChaptersApi(mangaKey);
    } else {
      chapters = await fetchChaptersHtml(mangaKey);
    }
    // site lists newest first; normalize to oldest-first
    chapters.reverse();
    for (var i = 0; i < chapters.length; i++) { chapters[i].sortOrder = i; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), initHeaders()));
    if (CFG.merlinLock && R_selFirst(doc, 'div#chapter-content div.lock-card')) {
      throw new Error('Locked chapter: login on the website is required');
    }
    return await parsePages(doc);
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
