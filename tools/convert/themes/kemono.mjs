// Kemono theme engine (all: kemono, coomer) — kemono.su/coomer.su API (creators as "manga", posts as "chapters")
export const runtime = 'wp';

const POST_PAGES = 1; // matches upstream default preference (50 posts per load)
const PAGE_LIMIT = 50;

export function extract(ctx) {
  const warnings = [];
  warnings.push('account features (favorites filter) unavailable without login; loads first ' + (POST_PAGES * PAGE_LIMIT) + ' posts only');
  return { ok: true, config: { postPages: POST_PAGES, pageLimit: PAGE_LIMIT }, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: kemono)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var API = BASE + '/api/v1';
var IMG_CDN = BASE.replace('//', '//img.');
var creatorsCache = null;

function apiHeaders() {
  return { 'Accept': 'text/css', 'Referer': BASE + '/' };
}

function serviceName(s) {
  if (s === 'fanbox') { return 'Pixiv Fanbox'; }
  if (s === 'subscribestar') { return 'SubscribeStar'; }
  if (s === 'dlsite') { return 'DLsite'; }
  if (s === 'onlyfans') { return 'OnlyFans'; }
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : '';
}

async function getCreators() {
  if (creatorsCache) { return creatorsCache; }
  var text = await $.http.get(API + '/creators', apiHeaders());
  var all = JSON.parse(text);
  var out = [];
  for (var i = 0; i < all.length; i++) {
    var c = all[i];
    if (String(c.service || '').toLowerCase() === 'discord') { continue; }
    c._updated = typeof c.updated === 'string'
      ? (Date.parse(c.updated) || 0)
      : ((c.updated || 0) * 1000);
    out.push(c);
  }
  creatorsCache = out;
  return out;
}

async function listManga(page, sortBy, query) {
  var creators = await getCreators();
  if (query) {
    var q = query.toLowerCase();
    creators = creators.filter(function (c) {
      return String(c.name || '').toLowerCase().indexOf(q) >= 0;
    });
  }
  creators.sort(function (a, b) {
    if (sortBy === 'pop') { return (b.favorited || 0) - (a.favorited || 0); }
    return (b._updated || 0) - (a._updated || 0);
  });
  var from = (page - 1) * CFG.pageLimit;
  var to = Math.min(creators.length, from + CFG.pageLimit);
  var mangas = [];
  for (var i = from; i < to; i++) {
    var c = creators[i];
    mangas.push({
      key: '/' + c.service + '/user/' + c.id,
      title: c.name || '',
      coverUrl: IMG_CDN + '/icons/' + c.service + '/' + c.id
    });
  }
  return { mangas: mangas, hasNextPage: to < creators.length };
}

function postImages(post) {
  var items = [];
  if (post.file && post.file.path) {
    items.push({ name: post.file.name || null, path: post.file.path });
  }
  var atts = post.attachments || [];
  for (var i = 0; i < atts.length; i++) {
    items.push({ name: atts[i].name || null, path: atts[i].path });
  }
  var seen = {};
  var out = [];
  for (var j = 0; j < items.length; j++) {
    var p = items[j].path;
    var ext = String(p).split('.').pop().toLowerCase();
    if (['png', 'jpg', 'gif', 'jpeg', 'webp'].indexOf(ext) < 0) { continue; }
    if (seen[p]) { continue; }
    seen[p] = true;
    out.push(p + (items[j].name ? '?f=' + items[j].name : ''));
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga(page, 'pop', '');
  },

  getSearchManga: async function (page, query) {
    return listManga(page, 'lat', query);
  },

  getMangaDetail: async function (mangaKey) {
    var m = String(mangaKey).match(/^\\/(\\w+)\\/user\\/(\\d+)$/);
    var title = '';
    if (m) {
      var creators = await getCreators();
      for (var i = 0; i < creators.length; i++) {
        if (String(creators[i].id) === m[2] && creators[i].service === m[1]) {
          title = creators[i].name || '';
          break;
        }
      }
      return {
        key: mangaKey,
        title: title,
        coverUrl: IMG_CDN + '/icons/' + m[1] + '/' + m[2],
        author: serviceName(m[1]),
        description: 'Post archive of this creator.',
        genre: serviceName(m[1]),
        status: 'ongoing'
      };
    }
    return { key: mangaKey, title: title, coverUrl: '', author: '', description: '', genre: '', status: '' };
  },

  getChapterList: async function (mangaKey) {
    var out = [];
    var offset = 0;
    var hasNext = true;
    var maxPosts = CFG.postPages * CFG.pageLimit;
    while (offset < maxPosts && hasNext) {
      var text = await $.http.get(API + mangaKey + '/posts?o=' + offset, apiHeaders());
      var page = JSON.parse(text);
      for (var i = 0; i < page.length; i++) {
        var post = page[i];
        if (postImages(post).length === 0) { continue; }
        var dateStr = post.edited || post.published || post.added || '';
        var name = post.title || '';
        if (!name) {
          var d = Date.parse(dateStr);
          name = 'Post from ' + (isNaN(d) ? 'unknown date' : new Date(d).toISOString().replace('T', ' ').substring(0, 19));
        }
        out.push({
          key: '/' + post.service + '/user/' + post.user + '/post/' + post.id,
          name: name,
          chapterNumber: -1,
          dateUpload: R_date(dateStr),
          pages: 0,
          sortOrder: 0
        });
      }
      offset += CFG.pageLimit;
      hasNext = page.length === CFG.pageLimit;
    }
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(API + chapterKey, apiHeaders());
    var post = JSON.parse(text).post;
    var paths = postImages(post);
    var pages = [];
    for (var i = 0; i < paths.length; i++) {
      pages.push({ index: i, url: BASE + '/data' + paths[i] });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
