// all/pawchive — bespoke JSON-API engine (kemono-style creator archive)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: [
      'preferences (max posts, low-res images, favorites filter) not portable; loading up to 1000 posts, full-res images',
    ],
  };
}

export function generate(manifest, config) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (standalone JSON API)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = BASE + '/api/v1';
var FILE_BASE = BASE.replace('//', '//file.');
var IMG_BASE = BASE.replace('//', '//img.');
var API_HEADERS = { 'Accept': 'text/css' };
var IMG_HEADERS = {
  'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
  'Sec-Fetch-Dest': 'image',
  'Sec-Fetch-Mode': 'no-cors',
  'Sec-Fetch-Site': 'same-site',
};
var PAGE_LIMIT = 50;
var MAX_POST_PAGES = 20;
var IMG_EXTS = ['png', 'jpg', 'gif', 'jpeg', 'webp'];
var PROMPT = 'You can change how many posts to load in the extension preferences.';

function serviceName(s) {
  if (s === 'fanbox') { return 'Pixiv Fanbox'; }
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : s;
}
function parseKey(key) {
  var m = String(key).match(/^\\/([^/]+)\\/user\\/([^/]+)/);
  return m ? { service: m[1], user: m[2] } : null;
}
function creatorToManga(c) {
  return {
    key: '/' + c.service + '/user/' + c.id,
    title: c.name,
    coverUrl: BASE + '/icons/' + c.service + '/' + c.id,
  };
}
async function fetchCreators() {
  var text = await $.http.get(API + '/creators', API_HEADERS);
  return JSON.parse(text);
}
async function listManga(page, query) {
  var all = await fetchCreators();
  var filtered = all;
  if (query) {
    var q = query.toLowerCase();
    filtered = all.filter(function (c) { return String(c.name || '').toLowerCase().indexOf(q) >= 0; });
  }
  var sorted = filtered.slice().sort(function (a, b) { return (b.favorited || 0) - (a.favorited || 0); });
  var start = (page - 1) * PAGE_LIMIT;
  var items = sorted.slice(start, start + PAGE_LIMIT);
  return { mangas: items.map(creatorToManga), hasNextPage: start + PAGE_LIMIT < sorted.length };
}
function postImages(post) {
  var files = [];
  if (post.file && post.file.path) { files.push(post.file); }
  if (Array.isArray(post.attachments)) {
    for (var i = 0; i < post.attachments.length; i++) {
      if (post.attachments[i] && post.attachments[i].path) { files.push(post.attachments[i]); }
    }
  }
  var seen = {};
  var out = [];
  for (var j = 0; j < files.length; j++) {
    var p = files[j].path;
    var ext = p.substring(p.lastIndexOf('.') + 1).toLowerCase();
    if (!p || seen[p] || IMG_EXTS.indexOf(ext) < 0) { continue; }
    seen[p] = true;
    out.push(p);
  }
  return out;
}
function postDate(post) {
  var dateStr = post.published || post.added || post.edited || '';
  if (!dateStr) { return 0; }
  var withTz = dateStr;
  if (!/Z$|[+]/.test(dateStr)) {
    withTz = dateStr + (post.service === 'fanbox' ? '+09:00' : 'Z');
  }
  var t = Date.parse(withTz);
  return isNaN(t) ? 0 : t;
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga(page, '');
  },

  getSearchManga: async function (page, query) {
    return listManga(page, query);
  },

  getMangaDetail: async function (mangaKey) {
    var info = parseKey(mangaKey);
    if (!info) { throw new Error('bad key: ' + mangaKey); }
    var all = await fetchCreators();
    var c = null;
    for (var i = 0; i < all.length; i++) {
      if (all[i].service === info.service && String(all[i].id) === info.user) { c = all[i]; break; }
    }
    if (!c) { throw new Error('creator not found: ' + mangaKey); }
    return {
      key: mangaKey,
      title: c.name,
      coverUrl: BASE + '/icons/' + c.service + '/' + c.id,
      author: serviceName(c.service),
      description: PROMPT,
      genre: '',
      status: '',
    };
  },

  getChapterList: async function (mangaKey) {
    var info = parseKey(mangaKey);
    if (!info) { throw new Error('bad key: ' + mangaKey); }
    var out = [];
    var offset = 0;
    for (var p = 0; p < MAX_POST_PAGES; p++) {
      var text = await $.http.get(API + mangaKey + '/posts?o=' + offset, API_HEADERS);
      var page = JSON.parse(text);
      if (!Array.isArray(page) || page.length === 0) { break; }
      for (var i = 0; i < page.length; i++) {
        var post = page[i];
        if (postImages(post).length === 0) { continue; }
        var title = post.title || '';
        if (!title) {
          var ds = post.published || post.added || post.edited;
          var dateText = ds ? String(ds).split('+')[0].split('Z')[0].replace('T', ' at ') : 'unknown date';
          title = 'Post from ' + dateText;
        }
        out.push({
          key: '/' + post.service + '/user/' + post.user + '/post/' + post.id,
          name: title,
          chapterNumber: -1,
          dateUpload: postDate(post),
          pages: 0,
          sortOrder: 0,
        });
      }
      if (page.length < PAGE_LIMIT) { break; }
      offset += PAGE_LIMIT;
    }
    // site returns newest-first; contract wants oldest-first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(API + chapterKey, API_HEADERS);
    var post = JSON.parse(text);
    var paths = postImages(post);
    var pages = [];
    for (var i = 0; i < paths.length; i++) {
      pages.push({ index: i, url: FILE_BASE + '/data' + paths[i] });
    }
    return pages;
  },

  imageHeaders: function () {
    var h = { Referer: BASE + '/' };
    for (var k in IMG_HEADERS) { h[k] = IMG_HEADERS[k]; }
    return h;
  },
};
`;
}
