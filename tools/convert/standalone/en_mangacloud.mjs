// en/mangacloud — JSON API (api.mangacloud.org) with JSON POST search payloads
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['filters (tags) not ported; popular = today/week/month view then library pages', 'site currently behind Cloudflare Turnstile: API returns 409 until challenge solved (upstream ext equally affected)'],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke JSON API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.mangacloud.org';
var CDN = 'https://pika.mangacloud.org';
var HDRS = { Referer: BASE + '/' };

function coverUrl(id, cover) {
  if (!cover) { return ''; }
  return CDN + '/' + id + '/' + cover.id + '.' + cover.f;
}

function fromBrowse(d) {
  return { key: '/' + d.id, title: d.title || '', coverUrl: coverUrl(d.id, d.cover) };
}

async function searchLibrary(page, query) {
  var payload = { title: query || null, page: page };
  var text = await $.http.post(API + '/comic/library', $.json.stringify(payload), {
    'Content-Type': 'application/json',
    Referer: BASE + '/'
  });
  var r = $.json.parse(text);
  var data = (r && r.data) || [];
  var mangas = [];
  for (var i = 0; i < data.length; i++) { mangas.push(fromBrowse(data[i])); }
  return { mangas: mangas, hasNextPage: data.length >= 10 };
}

async function fetchComic(mangaKey) {
  var id = mangaKey.replace(/^\\//, '').split('/')[0];
  var text = await $.http.get(API + '/comic/' + id, HDRS);
  return $.json.parse(text).data;
}

function statusMap(s) {
  switch (s) {
    case 'Ongoing': return 'ongoing';
    case 'Completed': return 'completed';
    case 'Cancelled': return 'cancelled';
    case 'Hiatus': return 'hiatus';
    default: return '';
  }
}

module.exports = {
  getPopularManga: async function (page) {
    if (page > 3) {
      return searchLibrary(page - 3, '');
    }
    var time = page === 1 ? 'today' : (page === 2 ? 'week' : 'month');
    var text = await $.http.get(API + '/comic-popular-view/' + time, HDRS);
    var r = $.json.parse(text);
    var list = (r && r.data && r.data.list) || [];
    var mangas = [];
    for (var i = 0; i < list.length; i++) { mangas.push(fromBrowse(list[i])); }
    return { mangas: mangas, hasNextPage: true };
  },

  getSearchManga: async function (page, query) {
    if (query && query.length < 3) {
      throw new Error('Search query must be more than 3 characters!');
    }
    return searchLibrary(page, query);
  },

  getMangaDetail: async function (mangaKey) {
    var d = await fetchComic(mangaKey);
    var desc = (d.description || '').trim();
    if (d.start_year) {
      desc += '\\n\\nYear: ' + d.start_year + (d.end_year ? ' - ' + d.end_year : '') + '\\n\\n';
    }
    var alts = [];
    if (d.alt_titles) {
      d.alt_titles.split('\\u2013').forEach(function (s) { if (s.trim()) { alts.push(s.trim()); } });
    }
    if (d.nat_titles) {
      d.nat_titles.split('\\u3001').forEach(function (s) { if (s.trim()) { alts.push(s.trim()); } });
    }
    if (alts.length) {
      desc += 'Alternative Name(s):\\n' + alts.map(function (a) { return '- ' + a; }).join('\\n') + '\\n';
    }
    var genres = [];
    if (d.type) { genres.push(d.type); }
    var tags = d.tags || [];
    for (var i = 0; i < tags.length; i++) { genres.push(tags[i].name); }
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: coverUrl(d.id, d.cover),
      author: d.authors || '',
      artist: d.artists || '',
      description: desc.trim(),
      genre: genres.join(', '),
      status: statusMap(d.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var d = await fetchComic(mangaKey);
    var chapters = d.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var numStr = String(c.number).replace(/\\.0$/, '');
      var nm = 'Chapter ' + numStr + (c.name ? ' - ' + c.name : '');
      out.push({
        key: '/' + d.id + '/' + c.id,
        name: nm,
        chapterNumber: typeof c.number === 'number' ? c.number : -1,
        dateUpload: c.created_date ? Date.parse(c.created_date) || 0 : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // API returns newest first; sort ascending by number -> oldest first
    out.sort(function (a, b) { return a.chapterNumber - b.chapterNumber; });
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var segs = chapterKey.replace(/^\\//, '').split('/');
    var chapterId = segs[segs.length - 1];
    var text = await $.http.get(API + '/chapters/' + chapterId, HDRS);
    var d = $.json.parse(text).data;
    var imgs = (d && d.images) || [];
    var pages = [];
    var base = CDN + '/' + d.comic_id + '/' + d.id + '/';
    for (var i = 0; i < imgs.length; i++) {
      pages.push({ index: i, url: base + imgs[i].id + '.' + imgs[i].f });
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
