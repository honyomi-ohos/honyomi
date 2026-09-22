// all/webcomics — bespoke engine (NUXT list pages + official-website-api JSON POSTs; multi-lang collapsed to en)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'multi-language ext (en/fr/pt/es/id) collapsed to single plugin (English site paths)',
      'genre/status/sort browse filters not portable (popular uses All/All/Hottest)',
      'random desktop UA pool approximated with default UA',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://official-website-api.webcomicsapp.com/api/web/v4/book';
var LANG = 'en';

function pathSeg(key, i) {
  return String(key).split('/')[i] || '';
}
function mangaId(key) { return pathSeg(key, 4); }
async function apiPost(path, body) {
  var text = await $.http.post(API + path, JSON.stringify(body), {
    'Content-Type': 'application/json',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Referer': BASE + '/',
  });
  return JSON.parse(text).data;
}

async function parseMangaPage(url) {
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  var nuxtEl = R_selFirst(doc, 'script#__NUXT_DATA__');
  var nuxtData = nuxtEl ? nuxtEl.text() : '';
  var items = R_sel(doc, '.grid > a');
  var out = [];
  for (var i = 0; i < items.length; i++) {
    var el = items[i];
    var url2 = el.absUrl('href');
    if (!url2) { continue; }
    var titleEl = R_selFirst(el, 'p.text-ink, span[class*=text]');
    if (!titleEl) { continue; }
    var img = R_selFirst(el, 'img[src]');
    var thumb = img ? img.absUrl('src') : '';
    if (thumb.indexOf('http') !== 0) {
      thumb = '';
      var slug = url2.substring(url2.lastIndexOf('/') + 1);
      var re = new RegExp('"' + slug + '"[^"]*"[^"]*"[^"]*"(https[^"]+)"');
      var m = nuxtData ? nuxtData.match(re) : null;
      if (m) { thumb = m[1]; }
    }
    var seg = R_path(url2).split('/');
    // path: /<lang>/<slug>/<name>/<bookId>
    out.push({
      key: '/' + seg[1] + '/' + seg[2] + '/' + seg[3] + '/' + seg[4],
      title: titleEl.text(),
      coverUrl: thumb,
    });
  }
  return { mangas: out, hasNextPage: !!R_selFirst(doc, 'div > span.cursor-default.bg-primary + a') };
}

module.exports = {
  getPopularManga: async function (page) {
    return parseMangaPage(BASE + '/' + LANG + '/genres/all/all/hottest/' + page);
  },

  getSearchManga: async function (page, query) {
    return parseMangaPage(BASE + '/' + LANG + '/search?q=' + encodeURIComponent(query || ''));
  },

  getMangaDetail: async function (mangaKey) {
    var dto = await apiPost('/info', { book_id: mangaId(mangaKey) });
    return {
      key: mangaKey,
      title: dto.name || '',
      coverUrl: dto.cover || '',
      author: dto.author || '',
      description: dto.description || '',
      genre: (dto.category || []).join(', '),
      status: dto.status === 'Ongoing' ? 'ongoing' : 'completed',
    };
  },

  getChapterList: async function (mangaKey) {
    var id = mangaId(mangaKey);
    var dto = await apiPost('/chapter/list', { book_id: id, page: 1, size: 9999, sort: 'desc' });
    var list = dto.list || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var ch = list[i];
      out.push({
        key: mangaKey + '/' + ch.chapter_id + '/' + ch.index,
        name: ch.is_pay ? '\\uD83D\\uDD12 ' + ch.name : ch.name,
        chapterNumber: ch.index,
        dateUpload: (ch.update_time || 0) * 1000,
        pages: 0,
        sortOrder: 0,
      });
    }
    // API returns newest-first; host convention is oldest-first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var parts = String(chapterKey).split('/');
    var bookId = parts[4];
    var chapterId = parts[5];
    var index = parseInt(parts[6], 10) || 0;
    var dto = await apiPost('/chapter/detail', { book_id: bookId, chapter_id: chapterId, index: index });
    var out = [];
    var imgs = dto.images || [];
    for (var i = 0; i < imgs.length; i++) {
      out.push({ index: i, url: dto.base_url + imgs[i].url });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
