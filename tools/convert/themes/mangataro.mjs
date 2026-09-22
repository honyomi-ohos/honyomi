// MangaTaro theme engine (en: mangataro, roliascan) — WP-based JSON API
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    rolia: /fetchMultiplePages/.test(kt),
    lang: 'en'
  };
  const src = (ctx.gradle && ctx.gradle.sources && ctx.gradle.sources[0]) || {};
  if (src.lang) config.lang = src.lang;
  if (config.rolia) warnings.push('rolia multi-page aggregation ported (5 API pages per browse page)');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mangataro)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function unescapeHtml(s) {
  var el = R_selFirst($.html.parse('<i>' + String(s || '') + '</i>'), 'i');
  return el ? el.text() : String(s || '');
}

function statusMap(s) {
  switch (s) {
    case 'Ongoing': return 'ongoing';
    case 'Completed': return 'completed';
    default: return '';
  }
}

function browseToManga(m) {
  return {
    key: '/m/' + m.id + '/' + m.url,
    title: unescapeHtml(m.title),
    coverUrl: m.cover || '',
    description: unescapeHtml(m.description),
    status: statusMap(m.status)
  };
}

async function loadEndpoint(page, query, sort) {
  var payload = {
    page: page,
    search: query || '',
    years: '[]',
    genres: '[]',
    types: '[]',
    statuses: '[]',
    sort: sort || 'post_desc',
    genreMatchMode: 'any'
  };
  var text = await $.http.post(BASE + '/wp-json/manga/v1/load', JSON.stringify(payload));
  var rows = JSON.parse(text);
  var out = [];
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].type === 'Novel' || !rows[i].url) { continue; }
    out.push(browseToManga(rows[i]));
  }
  return { mangas: out, rawSize: rows.length };
}

function parseRelativeDate(s) {
  var m = String(s || '').match(/(\\d+)\\s+(second|minute|hour|day|week|month|year)s?\\s+ago/);
  if (!m) { return 0; }
  var n = parseInt(m[1], 10);
  var mult = { second: 1, minute: 60, hour: 3600, day: 86400, week: 604800, month: 2592000, year: 31536000 }[m[2]] || 0;
  return Math.floor(Date.now() / 1000) - n * mult;
}

function utcStamp() {
  var d = new Date();
  function p(n) { return (n < 10 ? '0' : '') + n; }
  return '' + d.getUTCFullYear() + p(d.getUTCMonth() + 1) + p(d.getUTCDate()) + p(d.getUTCHours());
}

module.exports = {
  getPopularManga: async function (page) {
    var res = await loadEndpoint(page, '', 'popular_desc');
    return { mangas: res.mangas, hasNextPage: res.rawSize === 24 };
  },

  getSearchManga: async function (page, query) {
    if (CFG.rolia) {
      var all = [];
      var seen = {};
      var lastRaw = 0;
      var start = (page - 1) * 5 + 1;
      for (var ap = start; ap < start + 5; ap++) {
        var res = await loadEndpoint(ap, query, 'post_desc');
        lastRaw = res.rawSize;
        for (var i = 0; i < res.mangas.length; i++) {
          if (!seen[res.mangas[i].key]) {
            seen[res.mangas[i].key] = true;
            all.push(res.mangas[i]);
          }
        }
        if (res.rawSize < 24) { break; }
      }
      return { mangas: all, hasNextPage: lastRaw === 24 };
    }
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    var payload = { limit: 25, query: String(query || '').trim() };
    var text = await $.http.post(BASE + '/auth/search', JSON.stringify(payload));
    var rows = JSON.parse(text).results || [];
    var out = [];
    for (var k = 0; k < rows.length; k++) {
      if (rows[k].type === 'Novel') { continue; }
      out.push({
        key: '/m/' + rows[k].id + '/' + rows[k].slug,
        title: unescapeHtml(rows[k].title),
        coverUrl: rows[k].thumbnail || '',
        description: unescapeHtml(rows[k].description),
        status: statusMap(rows[k].status)
      });
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var parts = String(mangaKey).split('/').filter(Boolean);
    var id = parts[1];
    var text = await $.http.get(BASE + '/wp-json/wp/v2/manga/' + id + '?_embed');
    var d = JSON.parse(text);
    var embedded = d._embedded || {};
    var genres = [];
    var author = [];
    var termLists = embedded['wp:term'] || [];
    for (var i = 0; i < termLists.length; i++) {
      var list = termLists[i] || [];
      if (!list.length) { continue; }
      if (list[0].taxonomy === 'post_tag') {
        for (var g = 0; g < list.length; g++) { genres.push(list[g].name); }
      }
      if (list[0].taxonomy === 'manga_author') {
        for (var a = 0; a < list.length; a++) { author.push(list[a].name); }
      }
    }
    if (['Manhwa', 'Manhua', 'Manga'].indexOf(d.type) < 0 || genres.indexOf('Manhwa') < 0 && genres.indexOf('Manhua') < 0 && genres.indexOf('Manga') < 0) {
      if (d.type) { genres.push(d.type); }
    }
    var cover = '';
    var media = embedded['wp:featuredmedia'] || [];
    if (media.length > 0) { cover = media[0].source_url || ''; }
    var descEl = R_selFirst($.html.parse('<div>' + ((d.content || {}).rendered || '') + '</div>'), 'div');
    return {
      key: mangaKey,
      title: unescapeHtml((d.title || {}).rendered || ''),
      coverUrl: cover,
      author: author.join(', '),
      description: descEl ? unescapeHtml(descEl.text()) : '',
      genre: genres.join(', '),
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var parts = String(mangaKey).split('/').filter(Boolean);
    var id = parts[1];
    var group = parts[3];
    var ts = Math.floor(Date.now() / 1000);
    var token = $.crypto.md5(ts + 'mng_ch_' + utcStamp()).substring(0, 16);
    var url = BASE + '/auth/manga-chapters?manga_id=' + id + '&offset=0&limit=9999&order=DESC&_t=' + token + '&_ts=' + ts;
    if (group) { url += '&group_id=' + group; }
    var text = await $.http.get(url);
    var rows = JSON.parse(text).chapters || [];
    var out = [];
    var placeholders = ['', 'N/A', '—'];
    for (var i = 0; i < rows.length; i++) {
      var c = rows[i];
      if (String(c.language || '').toLowerCase() !== String(CFG.lang).toLowerCase()) { continue; }
      var name = 'Chapter ' + c.chapter;
      if (c.title && placeholders.indexOf(c.title) < 0) { name += ': ' + unescapeHtml(c.title); }
      out.push({
        key: R_path(String(c.url || '').replace(/\\/$/, '')),
        name: name,
        chapterNumber: 0,
        dateUpload: parseRelativeDate(c.date),
        scanlator: c.group_name && placeholders.indexOf(c.group_name) < 0 ? c.group_name : '',
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var seg = String(chapterKey).split('/').filter(Boolean).pop() || '';
    var chapterId = seg.substring(seg.lastIndexOf('-') + 1);
    var text = await $.http.get(BASE + '/auth/chapter-content?chapter_id=' + chapterId);
    var images = JSON.parse(text).images || [];
    var pages = [];
    for (var i = 0; i < images.length; i++) {
      pages.push({ index: i, url: images[i] });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
