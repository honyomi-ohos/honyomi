// MangoTheme engine (JSON API + optional AES-CBC body encryption: bladetoons / imperiodabritannia)
// mangotoons is skipped: requiresLogin=true (Bearer auth with user credentials).
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  apiUrl: '', // '' => BASE + '/api'; '__HOST_API__' => https://api.{host}/api; else literal
  cdnUrl: '', // '' => BASE
  needsApiToken: false,
  headers: {},
  latestPageSize: 24,
  searchPageSize: 20,
};

export function extract(ctx) {
  const kt = ctx.ktText;
  if (/requiresLogin\s*=\s*true/.test(kt)) {
    return { ok: false, reason: 'requires user login (Bearer auth); not supported' };
  }
  const warnings = [];
  const base = (ctx.gradle.sources && ctx.gradle.sources[0] && ctx.gradle.sources[0].baseUrl) || '';
  if (/bladetoons\.com/.test(base)) {
    // API moved to api.bladetoons.com and now requires X-API-Token; the frontend that
    // supplied the token is gone (every bladetoons.com host returns 404), so the token
    // cannot be obtained. Details/chapters/search all return 401.
    return { ok: false, reason: 'API requires X-API-Token but frontend is gone; token unobtainable (upstream ext unreleased, versionCode=0)' };
  }
  const keyM = kt.match(/override\s+val\s+encryptionKey\s*=\s*"([^"]+)"/);
  if (!keyM) {
    return { ok: false, reason: 'encryptionKey not found in source' };
  }
  const config = { ...DEFAULTS, encryptionKey: keyM[1] };

  const cdnM = kt.match(/override\s+val\s+cdnUrl\s*=\s*"([^"]+)"/);
  if (cdnM) { config.cdnUrl = cdnM[1]; }

  const apiM = kt.match(/override\s+val\s+apiUrl\s*=\s*"([^"]+)"/);
  if (apiM) {
    config.apiUrl = apiM[1].indexOf('substringAfterLast') >= 0 ? '__HOST_API__' : apiM[1];
  }

  if (/X-API-Token/.test(kt)) { config.needsApiToken = true; }
  if (/X-Brit-Cache/.test(kt)) { config.headers['X-Brit-Cache'] = 'true'; }
  if (/X-Noencryptionbritta/.test(kt)) { config.headers['X-Noencryptionbritta'] = '1'; }

  if (/rateLimit\s*\(/.test(kt)) {
    warnings.push('rateLimit not portable; requests may be throttled by site');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mangotheme)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};
var API = CFG.apiUrl ? (CFG.apiUrl === '__HOST_API__' ? 'https://api.' + BASE.replace(/^https?:\\/\\//, '') + '/api' : CFG.apiUrl) : BASE + '/api';
var CDN = CFG.cdnUrl || BASE;
var LANG = ${JSON.stringify(manifest.lang || 'pt-BR')};

// ---------------- mangotheme engine ----------------
var apiTokenCache = null;

function absoluteUrl(u, base) {
  if (!u || String(u).trim() === '') { return ''; }
  var s = String(u).trim();
  if (/^https?:\\/\\//.test(s)) { return s; }
  return base.replace(/\\/+$/, '') + '/' + s.replace(/^\\/+/, '');
}

function field(dto, names) {
  for (var i = 0; i < names.length; i++) {
    if (dto[names[i]] !== undefined && dto[names[i]] !== null) { return dto[names[i]]; }
  }
  return null;
}

function hexToBytes(hex) {
  var out = new Uint8Array(hex.length / 2);
  for (var i = 0; i < out.length; i++) { out[i] = parseInt(hex.substr(i * 2, 2), 16); }
  return out;
}

// Mirrors MangoThemeDecrypt: pass through plain JSON, decrypt "ivhex:cthex" otherwise.
async function mangoMaybeDecrypt(text) {
  var t = String(text || '').trim();
  if (t.charAt(0) === '{' || t.charAt(0) === '[') { return t; }
  var ci = t.indexOf(':');
  if (ci <= 0) { return t; }
  var ivHex = t.substring(0, ci);
  var ctHex = t.substring(ci + 1);
  if (!/^[0-9a-fA-F]+$/.test(ivHex) || ivHex.length % 2 !== 0 ||
    !/^[0-9a-fA-F]+$/.test(ctHex) || ctHex.length % 2 !== 0) { return t; }
  try {
    var keyBytes = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(CFG.encryptionKey + 'salt')));
    var key = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-CBC' }, false, ['decrypt']);
    var plain = await crypto.subtle.decrypt({ name: 'AES-CBC', iv: hexToBytes(ivHex) }, key, hexToBytes(ctHex));
    return new TextDecoder('utf-8').decode(plain);
  } catch (e) {
    return t;
  }
}

// ImperioDaBritannia: scrape the API token from the frontend env script (cached per session).
async function getApiToken() {
  if (apiTokenCache !== null) { return apiTokenCache; }
  try {
    var home = await $.http.get(BASE + '/', { Referer: BASE + '/' });
    var doc = $.html.parse(home);
    var link = doc.selectFirst('link[href*=env]');
    var href = link ? link.absUrl('href') : '';
    if (href) {
      var js = await $.http.get(href, { Referer: BASE + '/' });
      var m = /apiToken:.([^\`]+)/.exec(js);
      apiTokenCache = m ? m[1] : '';
    } else {
      apiTokenCache = '';
    }
  } catch (e) {
    apiTokenCache = '';
  }
  return apiTokenCache;
}

async function apiGet(path, extraHeaders) {
  var h = { Referer: BASE + '/', 'Accept-Language': LANG + ', en-US;q=0.8, en;q=0.7' };
  for (var k in CFG.headers) { h[k] = CFG.headers[k]; }
  if (extraHeaders) { for (var k2 in extraHeaders) { h[k2] = extraHeaders[k2]; } }
  if (CFG.needsApiToken) {
    var tok = await getApiToken();
    if (tok) { h['X-API-Token'] = tok; }
  }
  var text = await $.http.get(API + path, h);
  return mangoMaybeDecrypt(text);
}

// Response envelope: {sucesso, dados|obras|obra|data|capitulos|capitulo|..., pagination}
function envelopeItems(j) {
  if (!j || typeof j !== 'object') { return null; }
  var keys = ['dados', 'obras', 'obra', 'data', 'capitulos', 'capitulo', 'formatos', 'status', 'tags'];
  for (var i = 0; i < keys.length; i++) {
    if (keys[i] in j) { return j[keys[i]]; }
  }
  return null;
}

function asArray(items) {
  if (Array.isArray(items)) { return items; }
  if (items && typeof items === 'object') { return [items]; }
  return [];
}

function toStoredSlug(s) {
  var t = String(s || '').trim();
  if (!t) { return ''; }
  t = t.split('?')[0].replace(/\\/+$/, '');
  var segs = t.split('/');
  return segs[segs.length - 1] || '';
}

function parseStatus(name, id) {
  var n = String(name || '').trim();
  if (n === 'Ativo' || n === 'Em Andamento') { return 'ongoing'; }
  if (n === 'Concluído') { return 'completed'; }
  if (n === 'Hiato' || n === 'Pausado') { return 'hiatus'; }
  if (n === 'Cancelado') { return 'cancelled'; }
  switch (id) {
    case 1: case 6: return 'ongoing';
    case 2: case 5: return 'hiatus';
    case 3: return 'completed';
    case 4: return 'cancelled';
    default: return '';
  }
}

function dtoSlug(dto) {
  return toStoredSlug(field(dto, ['slug', 'nome_url', 'permalink', 'url']));
}

function toManga(dto, fallbackSlug) {
  var id = field(dto, ['id']);
  var slug = dtoSlug(dto) || toStoredSlug(fallbackSlug || '');
  var cover = field(dto, ['coverImage', 'imagem']) || field(dto, ['banner_imagem']);
  var tags = field(dto, ['tags']) || [];
  var genres = [];
  for (var i = 0; i < tags.length; i++) {
    var nm = String((tags[i] && tags[i].name) || '').trim();
    if (nm) { genres.push(nm); }
  }
  var desc = field(dto, ['descricao', 'description']);
  return {
    key: '/obra/' + id + (slug ? '/' + encodeURIComponent(slug) : ''),
    title: String(field(dto, ['title', 'nome']) || ''),
    coverUrl: absoluteUrl(cover, CDN),
    author: '',
    artist: '',
    description: desc && String(desc).trim() ? String(desc) : '',
    genre: genres.join(', '),
    status: parseStatus(field(dto, ['status_nome', 'statusName']), field(dto, ['status_id', 'statusId']))
  };
}

function formatChapterNumber(n) {
  var s = String(n);
  var f = parseFloat(s);
  if (isNaN(f)) { return s; }
  return String(f);
}

// "yyyy-MM-ddTHH:mm:ss(.fff)?(XXX)?" with 24:xx midnight-overflow normalization
function parseApiDate(s) {
  if (!s) { return 0; }
  var t = String(s).trim();
  if (t === '') { return 0; }
  var m = /^(\\d{4}-\\d{2}-\\d{2})T24:(\\d{2}:\\d{2}(?:\\.\\d{1,3})?)(.*)$/.exec(t);
  if (m) {
    var base = Date.parse(m[1] + 'T00:00:00' + (m[3] || ''));
    var extra = Date.parse('1970-01-01T00:' + m[2] + 'Z');
    if (!isNaN(base) && !isNaN(extra)) {
      return base + 86400000 + extra;
    }
  }
  var ts = Date.parse(t);
  return isNaN(ts) ? 0 : ts;
}

// manga key: /obra/{id}[/slug]
function parseMangaKey(mangaKey) {
  var segs = String(mangaKey).split('/').filter(function (p) { return p.length > 0; });
  var slug = '';
  if (segs.length > 2) {
    try { slug = decodeURIComponent(segs[2]); } catch (e) { slug = segs[2]; }
  }
  return { id: segs[1] || '', slug: slug };
}

// chapter key: /obra/{id}[/slug]/capitulo/{num}
function parseChapterKey(chapterKey) {
  var segs = String(chapterKey).split('/').filter(function (p) { return p.length > 0; });
  var capIdx = segs.indexOf('capitulo');
  var slug = '';
  if (capIdx === 3) {
    try { slug = decodeURIComponent(segs[2]); } catch (e) { slug = segs[2]; }
  }
  return { id: segs[1] || '', num: capIdx >= 0 ? (segs[capIdx + 1] || '') : (segs[segs.length - 1] || ''), slug: slug };
}

function mangaKeyOf(id, slug) {
  return '/obra/' + id + (slug ? '/' + encodeURIComponent(slug) : '');
}

async function fetchMangaDto(mangaKey) {
  var ref = parseMangaKey(mangaKey);
  var extra = {};
  if (ref.slug) { extra['X-MangoTheme-Stored-Slug'] = ref.slug; }
  var text = await apiGet('/obras/' + ref.id, extra);
  var j;
  try { j = JSON.parse(text); } catch (e) { j = null; }
  var item = envelopeItems(j);
  if (!item || typeof item !== 'object') { throw new Error('Manga not found: ' + ref.id); }
  return { dto: item, slug: ref.slug };
}

module.exports = {
  getPopularManga: async function () {
    var text = await apiGet('/obras/top10/views?periodo=total');
    var j;
    try { j = JSON.parse(text); } catch (e) { j = null; }
    var arr = asArray(envelopeItems(j));
    var out = [];
    for (var i = 0; i < arr.length; i++) {
      if (arr[i] && arr[i].id !== undefined && arr[i].id !== null) { out.push(toManga(arr[i])); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var path = '/obras?pagina=' + page + '&limite=' + CFG.searchPageSize;
    if (query) { path += '&busca=' + encodeURIComponent(query); }
    var text = await apiGet(path);
    var j;
    try { j = JSON.parse(text); } catch (e) { j = null; }
    var arr = asArray(envelopeItems(j));
    var out = [];
    for (var i = 0; i < arr.length; i++) {
      if (arr[i] && arr[i].id !== undefined && arr[i].id !== null) { out.push(toManga(arr[i])); }
    }
    return { mangas: out, hasNextPage: !!(j && j.pagination && j.pagination.hasNextPage) };
  },

  getMangaDetail: async function (mangaKey) {
    var got = await fetchMangaDto(mangaKey);
    return toManga(got.dto, got.slug);
  },

  getChapterList: async function (mangaKey) {
    var got;
    try {
      got = await fetchMangaDto(mangaKey);
    } catch (e) {
      return [];
    }
    var fallbackSlug = dtoSlug(got.dto) || toStoredSlug(got.slug || '');
    var list = field(got.dto, ['capitulos', 'chapters']) || [];
    var chapters = [];
    for (var i = 0; i < list.length; i++) {
      var ch = list[i];
      var mangaId = field(ch, ['obra_id', 'mangaId']);
      if (mangaId === null || mangaId === undefined) { continue; }
      var numStr = formatChapterNumber(field(ch, ['numero', 'number']));
      var created = field(ch, ['criado_em', 'createdAt']);
      var updated = field(ch, ['atualizado_em', 'updatedAt']);
      chapters.push({
        key: mangaKeyOf(mangaId, fallbackSlug) + '/capitulo/' + numStr,
        name: 'Capitulo ' + numStr,
        chapterNumber: parseFloat(numStr) || -1,
        dateUpload: parseApiDate(created || updated),
        pages: 0,
        sortOrder: 0
      });
    }
    // site lists newest first (sortedByDescending); normalize to oldest-first
    chapters.sort(function (a, b) { return b.chapterNumber - a.chapterNumber; });
    for (var j2 = 0; j2 < chapters.length; j2++) { chapters[j2].sortOrder = chapters.length - 1 - j2; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var ref = parseChapterKey(chapterKey);
    var text = await apiGet('/obras/' + ref.id + '/capitulos/' + ref.num);
    var j;
    try { j = JSON.parse(text); } catch (e) { j = null; }
    var item = envelopeItems(j);
    var pages = (item && (field(item, ['paginas', 'pages']))) || [];
    var sorted = pages.slice().sort(function (a, b) {
      return (field(a, ['numero', 'number']) || 0) - (field(b, ['numero', 'number']) || 0);
    });
    var out = [];
    for (var i = 0; i < sorted.length; i++) {
      var u = field(sorted[i], ['cdn_id', 'imagem', 'image', 'src', 'link', 'path', 'arquivo']);
      if (u && String(u).trim() !== '') {
        out.push({ index: out.length, url: absoluteUrl(u, CDN) });
      }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
