// Hiper theme engine (tRPC: hiperdex / hipercool / hipertoon)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

const DEFAULTS = {
  mangaPath: 'manga',
  headers: {},
};

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  const mp = kt.match(/override\s+val\s+mangaPath\s*:\s*String\s*=\s*"([^"]*)"/);
  if (mp) { config.mangaPath = mp[1]; }

  // custom headers from Headers.Builder.configureHeaders
  const re = /\.set\("([^"]+)",\s*"([^"]+)"\)/g;
  let m;
  while ((m = re.exec(kt)) !== null) {
    config.headers[m[1]] = m[2];
  }

  if (/runWebView/.test(kt)) {
    warnings.push('WebView header fallback not portable; using warmup-request retry instead');
  }
  if (/rateLimit\s*\(/.test(kt)) {
    warnings.push('rateLimit not portable; requests may be throttled by site');
  }
  if (/cleanTitleIfNeeded/.test(kt)) {
    warnings.push('title-cleaning preferences not portable; raw titles kept');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: hiper)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_sel)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- hiper engine ----------------
var idCache = {};

function baseHeaders(extra) {
  var h = {};
  for (var k in CFG.headers) { h[k] = CFG.headers[k]; }
  if (extra) { for (var k2 in extra) { h[k2] = extra[k2]; } }
  return h;
}

function hasError(list) {
  if (!Array.isArray(list)) { return true; }
  for (var i = 0; i < list.length; i++) {
    if (list[i] && typeof list[i] === 'object' && list[i].error !== undefined) { return true; }
  }
  return false;
}

async function trpcGet(procedure, input) {
  var url = BASE + '/api/trpc/' + procedure + '?batch=1&input=' + encodeURIComponent(JSON.stringify(input));
  var text = null;
  var list = null;
  try {
    text = await $.http.get(url, baseHeaders());
    try { list = JSON.parse(text); } catch (e) { list = null; }
  } catch (e) {
    list = null;
  }
  if (hasError(list)) {
    // mimic auth interceptor: warm up the site root (sets the __st auth cookie
    // in the host CookieJar), then retry once
    try { await $.http.get(BASE + '/', baseHeaders({ Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' })); } catch (e2) { /* ignore */ }
    try {
      text = await $.http.get(url, baseHeaders());
      try { list = JSON.parse(text); } catch (e3) { list = null; }
    } catch (e4) {
      list = null;
    }
  }
  return hasError(list) ? null : list;
}

function searchInput(page, query, sort) {
  var input = {
    '0': {
      json: {
        q: query || '',
        filters: { genres: null, type: null, status: null, contentRating: null, author: null, artist: null, year: null },
        limit: 30,
        offset: (page - 1) * 30,
        maxRating: 'pornographic'
      },
      meta: {
        values: {
          'filters.genres': ['undefined'], 'filters.type': ['undefined'], 'filters.status': ['undefined'],
          'filters.contentRating': ['undefined'], 'filters.author': ['undefined'], 'filters.artist': ['undefined'], 'filters.year': ['undefined']
        }
      }
    }
  };
  if (sort) { input['0'].json.sort = sort; }
  return input;
}

function mangaFromDto(dto) {
  var status = String(dto.status || '').toLowerCase();
  var statusOut = '';
  if (status === 'ongoing') { statusOut = 'ongoing'; }
  else if (status === 'hiatus') { statusOut = 'hiatus'; }
  else if (status === 'cancelled') { statusOut = 'cancelled'; }
  else if (status === 'completed') { statusOut = 'completed'; }
  var genres = (dto.genres || []).slice();
  if (dto.type) { genres.push(dto.type); }
  if (dto.contentRating) { genres.push(dto.contentRating); }
  return {
    key: '/' + CFG.mangaPath + '/' + dto.slug,
    title: dto.title || '',
    coverUrl: dto.coverUrl || '',
    author: (dto.authors || []).join(', '),
    artist: (dto.artists || []).join(', '),
    description: dto.synopsis || '',
    genre: genres.join(', '),
    status: statusOut
  };
}

function numToStr(n) {
  if (n === Math.floor(n)) { return String(Math.floor(n)); }
  return String(n);
}

async function fetchDetailsBySlug(slug) {
  var input = {
    '0': { json: null, meta: { values: ['undefined'] } },
    '1': { json: { slug: slug } }
  };
  var list = await trpcGet('auth.me,series.bySlugWithGenres', input);
  if (!list) { return null; }
  var last = list[list.length - 1];
  var dto = last && last.result && last.result.data && last.result.data.json;
  return dto || null;
}

function parseChapterKey(chapterKey) {
  // /manga/{slug}/{number}[~{id}]
  var parts = String(chapterKey).split('/').filter(function (p) { return p.length > 0; });
  var seg = parts[parts.length - 1] || '';
  var tilde = seg.indexOf('~');
  return {
    slug: parts[parts.length - 2] || '',
    number: tilde >= 0 ? seg.substring(0, tilde) : seg
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var list = await trpcGet('search.query', searchInput(page, '', 'popular'));
    if (!list) { return { mangas: [], hasNextPage: false }; }
    var dto = list[0] && list[0].result && list[0].result.data && list[0].result.data.json;
    var hits = dto ? (dto.hits || []) : [];
    var out = [];
    for (var i = 0; i < hits.length; i++) { out.push(mangaFromDto(hits[i])); }
    return { mangas: out, hasNextPage: hits.length > 0 };
  },

  getSearchManga: async function (page, query) {
    var list = await trpcGet('search.query', searchInput(page, query || '', null));
    if (!list) { return { mangas: [], hasNextPage: false }; }
    var dto = list[0] && list[0].result && list[0].result.data && list[0].result.data.json;
    var hits = dto ? (dto.hits || []) : [];
    var out = [];
    for (var i = 0; i < hits.length; i++) { out.push(mangaFromDto(hits[i])); }
    return { mangas: out, hasNextPage: hits.length > 0 };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).split('/').filter(function (p) { return p.length > 0; }).pop() || '';
    var dto = await fetchDetailsBySlug(slug);
    if (!dto) { throw new Error('Manga not found: ' + slug); }
    idCache[slug] = dto.id;
    return mangaFromDto(dto);
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).split('/').filter(function (p) { return p.length > 0; }).pop() || '';
    var seriesId = idCache[slug];
    if (!seriesId) {
      var dto = await fetchDetailsBySlug(slug);
      if (!dto) { return []; }
      seriesId = dto.id;
    }
    var input = {
      '0': { json: { values: ['undefined'] } },
      '1': {
        json: { seriesId: Number(seriesId), chapterId: null, sort: 'best', page: 1, limit: 20 },
        meta: { values: { chapterId: ['undefined'] } }
      },
      '2': { json: { seriesId: Number(seriesId) } }
    };
    var list = await trpcGet('auth.me,series.chapters', input);
    if (!list) { return []; }
    var last = list[list.length - 1];
    var chapters = (last && last.result && last.result.data && last.result.data.json) || [];
    var out = [];
    var seen = {};
    for (var i = 0; i < chapters.length; i++) {
      var ch = chapters[i];
      var numStr = numToStr(Number(ch.number));
      var dup = seen[ch.number] === true;
      seen[ch.number] = true;
      var title = ch.title || '';
      var name = /\\d/.test(title) ? title : ('Chapter ' + numStr + (title ? ' ' + title : ''));
      var ts = ch.createdAt ? Date.parse(ch.createdAt) : 0;
      out.push({
        key: '/' + CFG.mangaPath + '/' + slug + '/' + numStr + (dup ? '~' + ch.id : ''),
        name: name,
        chapterNumber: Number(ch.number) || -1,
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
    var ref = parseChapterKey(chapterKey);
    var input = {
      '0': { json: null, meta: { values: ['undefined'] } },
      '1': { json: { slug: ref.slug } },
      '2': { json: { seriesSlug: ref.slug, chapterNumber: Number(ref.number) } },
      '3': { json: { position: 'footer_bottom' } }
    };
    var list = await trpcGet('auth.me,series.bySlug,reader.chapterPages', input);
    if (!list) { return []; }
    var last = list[list.length - 1];
    var pages = (last && last.result && last.result.data && last.result.data.json) || [];
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      var url = pages[i].avifUrl || pages[i].webpUrl || '';
      if (url) { out.push({ index: pages[i].pageOrder, url: url }); }
    }
    out.sort(function (a, b) { return a.index - b.index; });
    for (var k = 0; k < out.length; k++) { out[k].index = k; }
    return out;
  },

  imageHeaders: function () {
    return baseHeaders({ Referer: BASE + '/' });
  }
};
`;
}
