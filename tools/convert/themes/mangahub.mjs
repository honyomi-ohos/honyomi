// MangaHub theme engine (mangakakalotfun, mangafoxfun, mangapandaonl, mangareadersite, ...)
// GraphQL API at api.mghcdn.com guarded by the mhub_access key.
// NOTE: the key is normally issued via the Set-Cookie response header, which this
// host's HTTP bridge cannot read; the engine tries a best-effort body scan and
// reports an informative error when the key is unavailable.
export const runtime = 'wp';

const API_URL = 'https://api.mghcdn.com/graphql';
const CDN_URL = 'https://imgx.mghcdn.com';
const THUMB_URL = 'https://thumb.mghcdn.com';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { mangaSource: '' };

  const m = kt.match(/mangaSource(?::\s*String)?\s*=\s*"([^"]+)"/);
  if (m) {
    config.mangaSource = m[1];
  } else {
    return { ok: false, reason: 'mangaSource code not found in source' };
  }

  warnings.push('api.mghcdn.com is behind a Cloudflare managed challenge; non-browser clients are blocked even with a valid key');
  warnings.push('mhub_access key is issued via Set-Cookie which this host cannot read; key is recovered from HTML body only when present (usually absent)');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mangahub)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};
var API = ${JSON.stringify(API_URL)};
var CDN = ${JSON.stringify(CDN_URL)};
var THUMB = ${JSON.stringify(THUMB_URL)};
var ACCESS_KEY = '';

// ---------------- mangahub engine ----------------
function graphqlHeaders() {
  return {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'x-mhub-access': ACCESS_KEY
  };
}

async function tryRefreshKey(refreshUrl) {
  if (ACCESS_KEY) { return; }
  try {
    var url = refreshUrl || (BASE + '/chapter/martial-peak/chapter-' + Math.floor(1000 + Math.random() * 2000));
    var text = await $.http.get(url, { Referer: BASE + '/manga/' });
    var m = text.match(/mhub_access=([^;"'\\s]+)/);
    if (m) { ACCESS_KEY = m[1]; }
  } catch (e) { /* key unavailable */ }
}

async function fetchGraphQL(query, refreshUrl) {
  if (!ACCESS_KEY) {
    await tryRefreshKey(refreshUrl);
  }
  if (!ACCESS_KEY) {
    throw new Error('mhub_access API key unavailable: the site issues it via a Set-Cookie header ' +
      'and api.mghcdn.com is Cloudflare-protected; browse ' + BASE + ' in a browser-based client instead');
  }
  var body = JSON.stringify({ query: query });
  var text = await $.http.post(API, body, graphqlHeaders());
  var json = JSON.parse(text);
  if (json.errors && json.errors.length && !json.data) {
    var msg = json.errors[0].message || 'GraphQL error';
    if (/rate\\s*limit|api\\s*key/i.test(msg)) {
      ACCESS_KEY = '';
      throw new Error('MangaHub API rejected the key (' + msg + '); the key cannot be renewed in this host');
    }
    throw new Error('MangaHub API error: ' + msg);
  }
  return json.data || {};
}

function searchQuery(order, query, page) {
  var q = String(query || '').replace(/\\\\/g, '\\\\\\\\').replace(/"/g, '\\\\"');
  return '{ search(x: ' + CFG.mangaSource + ', q: "' + q + '", genre: "all", mod: ' + order +
    ', offset: ' + ((page - 1) * 30) + ') { rows { title, slug, image } } }';
}

function mangaQuery(slug) {
  return '{ manga(x: ' + CFG.mangaSource + ', slug: "' + slug + '") { title, slug, status, image, author, artist, genres, description, alternativeTitle, chapters { number, title, date } } }';
}

function pagesQuery(slug, number) {
  return '{ chapter(x: ' + CFG.mangaSource + ', slug: "' + slug + '", number: ' + number + ') { pages, mangaID, number } }';
}

async function mangaList(page, order, query) {
  var data = await fetchGraphQL(searchQuery(order, query, page), null);
  var rows = (data.search && data.search.rows) || [];
  var out = [];
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i];
    if (!r.slug) { continue; }
    out.push({
      key: '/manga/' + r.slug,
      title: r.title || '',
      coverUrl: r.image ? THUMB + '/' + r.image : ''
    });
  }
  return { mangas: out, hasNextPage: rows.length === 30 };
}

function chapterName(title, numberStr) {
  title = String(title || '').trim().replace(/\\s+/g, ' ');
  if (title.indexOf(numberStr) >= 0) { return title; }
  if (title) { return 'Chapter ' + numberStr + ' - ' + title; }
  return 'Chapter ' + numberStr;
}

async function fetchMangaData(mangaKey) {
  var slug = String(mangaKey).replace(/^\\/manga\\//, '').replace(/\\/+$/, '');
  var data = await fetchGraphQL(mangaQuery(slug), BASE + '/manga/' + slug);
  if (!data.manga) { throw new Error('Manga not found: ' + slug); }
  return data.manga;
}

module.exports = {
  getPopularManga: async function (page) {
    return mangaList(page, 'POPULAR', '');
  },

  getSearchManga: async function (page, query) {
    return mangaList(page, 'POPULAR', query || '');
  },

  getMangaDetail: async function (mangaKey) {
    var m = await fetchMangaData(mangaKey);
    var status = '';
    if (m.status === 'ongoing') { status = 'ongoing'; }
    else if (m.status === 'completed') { status = 'completed'; }
    var desc = m.description || '';
    var altTitles = String(m.alternativeTitle || '').split(';')
      .map(function (t) { return t.trim(); })
      .filter(function (t) { return t; });
    if (altTitles.length > 0) {
      desc += (desc ? '\\n\\n' : '') + 'Alternative Names:\\n' +
        altTitles.map(function (t) { return '- ' + t; }).join('\\n');
    }
    return {
      key: mangaKey,
      title: m.title || '',
      coverUrl: m.image ? THUMB + '/' + m.image : '',
      author: m.author || '',
      description: desc,
      genre: m.genres || '',
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var m = await fetchMangaData(mangaKey);
    var slug = m.slug || String(mangaKey).replace(/^\\/manga\\//, '').replace(/\\/+$/, '');
    var chapters = m.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var numStr = String(c.number).replace(/\\.0$/, '');
      var dt = Date.parse(c.date || '');
      out.push({
        key: '/' + slug + '/chapter-' + c.number,
        name: chapterName(c.title, numStr),
        chapterNumber: typeof c.number === 'number' ? c.number : -1,
        dateUpload: isNaN(dt) ? 0 : dt,
        pages: 0,
        sortOrder: 0
      });
    }
    // API returns newest first; normalize to oldest-first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var segs = String(chapterKey).split('/');
    var slug = segs[1] || '';
    var number = parseFloat(String(segs[2] || '').split('-').pop());
    if (!slug || isNaN(number)) { throw new Error('Invalid chapter key: ' + chapterKey); }
    var data = await fetchGraphQL(pagesQuery(slug, number), BASE + '/chapter/' + slug + '/chapter-' + number);
    var ch = data.chapter;
    if (!ch) { throw new Error('Chapter not found: ' + chapterKey); }
    var pages = JSON.parse(ch.pages);
    var prefix = CDN + '/' + (pages.p || '');
    var images = pages.i || [];
    var out = [];
    for (var i = 0; i < images.length; i++) {
      out.push({ index: i, url: prefix + images[i] });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
