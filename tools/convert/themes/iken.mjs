// Iken theme engine (Node/Express "Iken" — JSON API based)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    apiReplace: 'https://api.',
    perPage: 18,
    sortPagesByFilename: false,
    popularOrderBy: 'totalViews',
  };

  const am = kt.match(/apiUrl\s*(?::\s*String)?\s*(?:get\s*)?=\s*"([^"]*)"/);
  if (am && am[1]) {
    config.apiReplace = '';
    config.apiUrl = am[1];
    warnings.push('custom apiUrl');
  }

  const pp = kt.match(/perPage\s*(?::\s*Int)?\s*(?:get\s*)?=\s*(\d+)/);
  if (pp) { config.perPage = parseInt(pp[1], 10); }

  if (/sortPagesByFilename\s*(?::\s*Boolean)?\s*(?:get\s*)?=\s*true/.test(kt)) {
    config.sortPagesByFilename = true;
  }

  const so = kt.match(/sortOptions[\s\S]{0,400}?"[^"]*"\s*to\s*"(\w+)"/);
  // popular uses sortOptions[1]; keep default unless overridden list found
  const opts = [...kt.matchAll(/to\s*"(\w+)"/g)].map(m => m[1]);
  if (opts.length >= 2) { config.popularOrderBy = opts[1]; }

  if (/sendUpdateViews\s*(?::\s*Boolean)?\s*(?:get\s*)?=\s*false/.test(kt)) {
    // view tracking disabled by source; we never send analytics anyway
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: iken)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_* helpers)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- iken engine ----------------
var API = CFG.apiUrl || BASE.replace(/^https:\\/\\//, CFG.apiReplace);

function apiUrl(path) {
  return API + path;
}

function stripHtml(s) {
  var v = String(s || '');
  v = v.replace(/\\r?\\n/g, '<br>');
  v = v.replace(/<[^>]*>/g, ' ');
  v = v.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>');
  return v.replace(/\\s+/g, ' ').trim();
}

function isNovel(post) {
  if (!post) { return false; }
  if (post.isNovel === true) { return true; }
  return String(post.seriesType || '').toLowerCase() === 'novel';
}

function statusFrom(seriesStatus) {
  switch (seriesStatus) {
    case 'ONGOING':
    case 'COMING_SOON':
    case 'MASS_RELEASED': return 'ongoing';
    case 'COMPLETED': return 'completed';
    case 'CANCELLED':
    case 'DROPPED': return 'cancelled';
    default: return '';
  }
}

function genresFrom(post) {
  var out = [];
  var t = post.seriesType;
  if (t === 'MANGA' || t === 'MANHUA' || t === 'MANHWA') { out.push(t.charAt(0) + t.slice(1).toLowerCase()); }
  var gs = post.genres || [];
  for (var i = 0; i < gs.length; i++) {
    if (gs[i] && gs[i].name) { out.push(gs[i].name); }
  }
  var seen = {};
  var uniq = [];
  for (var j = 0; j < out.length; j++) {
    if (!seen[out[j]]) { seen[out[j]] = 1; uniq.push(out[j]); }
  }
  return uniq.join(', ');
}

function postToListItem(post) {
  return {
    key: '/series/' + post.slug,
    title: post.postTitle || '',
    coverUrl: R_abs(post.featuredImage || '')
  };
}

function postToDetail(post, key) {
  var desc = stripHtml(post.postContent);
  if (post.alternativeTitles) {
    if (desc) { desc += '\\n\\n'; }
    desc += 'Alternative Names: ' + post.alternativeTitles;
  }
  return {
    key: key,
    title: post.postTitle || '',
    coverUrl: R_abs(post.featuredImage || ''),
    author: post.author || '',
    artist: post.artist || '',
    description: desc,
    genre: genresFrom(post),
    status: statusFrom(post.seriesStatus)
  };
}

function chapterLocked(ch) {
  if (ch.isLocked === true) { return true; }
  if (ch.isTimeLocked === true) { return true; }
  if (ch.chapterPurchased === false && ch.price !== 0 && ch.price != null) { return true; }
  return false;
}

function chapterToItem(ch, seriesSlug) {
  var slug = seriesSlug || (ch.mangaPost ? ch.mangaPost.slug : '') || '';
  var name = 'Chapter ' + (ch.number != null ? ch.number : '?');
  if (ch.title && String(ch.title).trim()) { name += ' - ' + ch.title; }
  var num = -1;
  var n = parseFloat(ch.number);
  if (!isNaN(n)) { num = n; }
  return {
    key: '/series/' + slug + '/' + ch.slug + '/' + ch.id,
    name: name,
    chapterNumber: num,
    dateUpload: ch.createdAt ? R_date(ch.createdAt) : 0,
    pages: 0,
    sortOrder: 0
  };
}

async function fetchPost(slug) {
  var text = await $.http.get(apiUrl('/api/post?postSlug=' + encodeURIComponent(slug)));
  var data;
  try { data = JSON.parse(text); } catch (e) { throw new Error('iken api parse failed'); }
  if (!data || !data.post) { throw new Error('post not found'); }
  if (isNovel(data.post)) { throw new Error('novels are unsupported'); }
  return data;
}

function slugFromKey(mangaKey) {
  return String(mangaKey).replace(/^\\/series\\//, '').replace(/\\/+$/, '');
}

function sortChapters(list) {
  // normalize to oldest-first: sort by chapter number when parseable, else by date
  var numbered = 0;
  for (var i = 0; i < list.length; i++) {
    if (list[i].chapterNumber >= 0) { numbered++; }
  }
  if (list.length > 0 && numbered >= list.length / 2) {
    list.sort(function (a, b) {
      if (a.chapterNumber !== b.chapterNumber) { return a.chapterNumber - b.chapterNumber; }
      return a.dateUpload - b.dateUpload;
    });
  } else {
    list.sort(function (a, b) { return a.dateUpload - b.dateUpload; });
  }
  for (var k = 0; k < list.length; k++) { list[k].sortOrder = k; }
  return list;
}

async function queryList(page, query, orderBy) {
  var url = apiUrl('/api/query?page=' + page + '&perPage=' + CFG.perPage +
    '&searchTerm=' + encodeURIComponent(query || ''));
  if (orderBy) { url += '&orderBy=' + encodeURIComponent(orderBy); }
  var text = await $.http.get(url);
  var data;
  try { data = JSON.parse(text); } catch (e) { throw new Error('iken api parse failed'); }
  var posts = (data && data.posts) ? data.posts : [];
  var out = [];
  for (var i = 0; i < posts.length; i++) {
    if (isNovel(posts[i])) { continue; }
    var it = postToListItem(posts[i]);
    if (it.key && it.title) { out.push(it); }
  }
  var total = (data && data.totalCount) ? data.totalCount : out.length;
  return { mangas: out, hasNextPage: total > page * CFG.perPage };
}

function filenameNumber(url) {
  var m = String(url).substring(String(url).lastIndexOf('/') + 1).match(/\\d+/);
  return m ? parseInt(m[0], 10) : 2147483647;
}

module.exports = {
  getPopularManga: async function (page) {
    return queryList(page, '', CFG.popularOrderBy);
  },

  getSearchManga: async function (page, query) {
    return queryList(page, query || '', '');
  },

  getMangaDetail: async function (mangaKey) {
    var slug = slugFromKey(mangaKey);
    var data = await fetchPost(slug);
    return postToDetail(data.post, '/series/' + slug);
  },

  getChapterList: async function (mangaKey) {
    var slug = slugFromKey(mangaKey);
    var data = await fetchPost(slug);
    var chapters = data.post.chapters || [];
    // some sources only expose chapters via the dedicated endpoint
    if (chapters.length === 0 || (data.totalChapterCount != null && data.totalChapterCount > chapters.length)) {
      try {
        var chText = await $.http.get(apiUrl('/api/chapters?postId=' + data.post.id));
        var chData = JSON.parse(chText);
        var apiChapters = chData && chData.post ? (chData.post.chapters || []) : [];
        if (apiChapters.length > chapters.length) { chapters = apiChapters; }
      } catch (e) { /* keep embedded list */ }
    }
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var ch = chapters[i];
      if (!ch || !ch.id || !ch.slug) { continue; }
      if (chapterLocked(ch)) { continue; }
      out.push(chapterToItem(ch, data.post.slug));
    }
    return sortChapters(out);
  },

  getPageList: async function (chapterKey) {
    var parts = String(chapterKey).split('/');
    var id = parts[parts.length - 1];
    var text = await $.http.get(apiUrl('/api/chapter?chapterId=' + encodeURIComponent(id)));
    var data;
    try { data = JSON.parse(text); } catch (e) { throw new Error('iken api parse failed'); }
    var ch = data && data.chapter ? data.chapter : null;
    if (!ch) { throw new Error('chapter not found'); }
    if (ch.isShortLinkLocked) { throw new Error('chapter locked (short link)'); }
    if (ch.isLockedByCoins) { throw new Error('chapter locked (coins required)'); }
    if (ch.isPermanentlyLocked) { throw new Error('chapter permanently locked'); }
    var imgs = ch.images || [];
    var sorted = imgs.slice(0);
    if (CFG.sortPagesByFilename) {
      sorted.sort(function (a, b) { return filenameNumber(a.url) - filenameNumber(b.url); });
    } else {
      sorted.sort(function (a, b) {
        var ao = a.order == null ? 2147483647 : a.order;
        var bo = b.order == null ? 2147483647 : b.order;
        return ao - bo;
      });
    }
    var pages = [];
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i] && sorted[i].url) {
        pages.push({ index: pages.length, url: String(sorted[i].url).replace(/ /g, '%20') });
      }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
