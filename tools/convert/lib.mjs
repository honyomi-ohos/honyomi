// Shared converter utilities + embedded plugin runtime helpers
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const TOOLS_DIR = dirname(fileURLToPath(import.meta.url));

export function readText(p) {
  return readFileSync(p, 'utf8');
}

export function listDir(p) {
  return readdirSync(p);
}

export function isDir(p) {
  return statSync(p).isDirectory();
}

// ---------- gradle metadata parsing ----------

function matchBlock(text, startIdx) {
  // returns [content, endIdx] of the brace block starting at first '{' at/after startIdx
  const open = text.indexOf('{', startIdx);
  if (open < 0) return null;
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === '{') depth++;
    else if (text[i] === '}') {
      depth--;
      if (depth === 0) return [text.slice(open + 1, i), i];
    }
  }
  return null;
}

function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
}

function reStr(re, text, group = 1) {
  const m = text.match(re);
  return m ? m[group] : undefined;
}

// parse keiyoushi { ... } block from build.gradle.kts
export function parseGradle(gradleText) {
  const text = stripComments(gradleText);
  const meta = {
    name: '', versionCode: 0, contentWarning: 'SAFE', theme: '', libVersion: '',
    sources: [], extName: '', hasDeeplink: false,
  };
  const kMatch = text.match(/\bkeiyoushi\s*\{/);
  if (!kMatch || kMatch.index === undefined) return meta;
  const block = matchBlock(text, kMatch.index + kMatch[0].length - 1);
  if (!block) return meta;
  let body = block[0];

  meta.name = reStr(/\bname\s*=\s*"((?:[^"\\]|\\.)*)"/, body) ?? '';
  meta.versionCode = parseInt(reStr(/\bversionCode\s*=\s*(\d+)/, body) ?? '0', 10);
  const cw = reStr(/\bcontentWarning\s*=\s*ContentWarning\.(\w+)/, body);
  meta.contentWarning = cw ?? 'SAFE';
  meta.theme = reStr(/\btheme\s*=\s*"(\w+)"/, body) ?? '';
  meta.libVersion = reStr(/\blibVersion\s*=\s*"([^"]*)"/, body) ?? '';
  meta.hasDeeplink = /\bdeeplink\s*\{/.test(body);

  // extract source blocks
  const sourceRe = /(^|[\s{])source\s*\{/g;
  let sm;
  while ((sm = sourceRe.exec(body)) !== null) {
    const braceStart = sm.index + sm[0].length - 1;
    const sb = matchBlock(body, braceStart);
    if (!sb) break;
    const sBody = sb[0];
    let baseUrl = reStr(/\bbaseUrl\s*=\s*"((?:[^"\\]|\\.)*)"/, sBody) ?? '';
    if (baseUrl === '') {
      const custom = sBody.match(/baseUrl\s*\{[\s\S]*?custom\(\s*"((?:[^"\\]|\\.)*)"/);
      if (custom) baseUrl = custom[1];
    }
    meta.sources.push({
      name: reStr(/\bname\s*=\s*"((?:[^"\\]|\\.)*)"/, sBody) ?? '',
      lang: reStr(/\blang\s*=\s*"([^"]*)"/, sBody) ?? '',
      baseUrl,
    });
    sourceRe.lastIndex = sb[1] + 1;
  }
  return meta;
}

// ---------- key/name helpers ----------

export function sanitizeKey(s) {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 48);
}

export function pluginKey(lang, extName) {
  const l = sanitizeKey(lang || 'all');
  const e = sanitizeKey(extName);
  return l === 'all' ? e : `${l}_${e}`;
}

// ---------- icon ----------

const ICON_DPI = ['mipmap-xxxhdpi', 'mipmap-xxhdpi', 'mipmap-xhdpi', 'mipmap-hdpi', 'mipmap-mdpi'];

export function findIcon(extDir) {
  const resDir = join(extDir, 'res');
  if (!existsSync(resDir)) return null;
  for (const dpi of ICON_DPI) {
    const p = join(resDir, dpi, 'ic_launcher.png');
    if (existsSync(p)) return p;
  }
  for (const dpi of ICON_DPI) {
    const p = join(resDir, dpi, 'ic_launcher-web.png');
    if (existsSync(p)) return p;
  }
  return null;
}

// ---------- shared plugin runtime (injected into every generated main.js) ----------

// Runs inside the plugin sandbox; $ is the host DSL. BASE is defined per-plugin.
export const RUNTIME_JS = String.raw`
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
`;
