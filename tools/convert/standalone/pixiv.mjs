// all/pixiv — bespoke engine over public /touch/ajax + /ajax endpoints (no OAuth needed)
// Multi-source ext (per-language); converter emits one plugin from the first baseUrl.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'multi-language ext collapsed to single plugin (lang=en); filters/smart-search/user-search approximated; image quality fixed to original',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone JSON API)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API_HEADERS = { 'Accept': 'application/json', 'Referer': BASE + '/' };

async function apiGet(path) {
  var text = await $.http.get(BASE + path + (path.indexOf('?') >= 0 ? '&' : '?') + 'lang=en', API_HEADERS);
  var j = JSON.parse(text);
  if (j.error) { throw new Error(j.message || 'pixiv api error'); }
  return j.body;
}
function illustToManga(illust) {
  var series = illust.series;
  if (series && series.id) {
    var uid = series.userId || (illust.author_details && illust.author_details.user_id);
    return {
      key: '/user/' + uid + '/series/' + series.id,
      title: series.title || illust.title || '(null)',
      coverUrl: (typeof series.coverImage === 'string' ? series.coverImage : '') || illust.url || '',
    };
  }
  return { key: '/artworks/' + illust.id, title: illust.title || '(null)', coverUrl: illust.url || '' };
}
function dedupe(list) {
  var seen = {};
  var out = [];
  for (var i = 0; i < list.length; i++) {
    if (!seen[list[i].key]) { seen[list[i].key] = 1; out.push(list[i]); }
  }
  return out;
}
async function seriesContents(seriesId) {
  var out = [];
  var lastOrder = 0;
  for (var i = 0; i < 50; i++) {
    var j = await apiGet('/touch/ajax/illust/series_content/' + seriesId + '?last_order=' + lastOrder);
    var contents = j.series_contents || [];
    if (contents.length === 0) { break; }
    out = out.concat(contents);
    lastOrder += contents.length;
  }
  return out;
}
async function userIllusts(userId) {
  var out = [];
  for (var p = 1; p <= 50; p++) {
    var j = await apiGet('/touch/ajax/user/illusts?id=' + userId + '&p=' + p);
    var illusts = j.illusts || [];
    if (illusts.length === 0) { break; }
    out = out.concat(illusts);
  }
  return out;
}
function illustToChapter(illust, total, idxFromEnd) {
  return {
    key: '/artworks/' + illust.id,
    name: illust.title || '(null)',
    chapterNumber: idxFromEnd,
    dateUpload: (illust.upload_timestamp || 0) * 1000,
    pages: 0,
    sortOrder: 0,
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var ranking = await apiGet('/touch/ajax/ranking/illust?mode=daily&type=manga&page=' + page);
    var entries = ranking.ranking || [];
    if (entries.length === 0) { return { mangas: [], hasNextPage: false }; }
    var qs = [];
    for (var i = 0; i < entries.length; i++) {
      qs.push('illust_ids[]=' + encodeURIComponent(entries[i].illustId));
    }
    var details = await apiGet('/touch/ajax/illust/details/many?' + qs.join('&'));
    var list = details.illust_details || [];
    var mangas = dedupe(list.map(illustToManga));
    return { mangas: mangas, hasNextPage: mangas.length > 0 };
  },

  getSearchManga: async function (page, query) {
    var j = await apiGet('/touch/ajax/search/illusts?word=' + encodeURIComponent(query) + '&s_mode=s_tc&p=' + page);
    var illusts = j.illusts || [];
    var filtered = [];
    for (var i = 0; i < illusts.length; i++) {
      if (illusts[i].is_ad_container === 1 || illusts[i].type === '2') { continue; }
      filtered.push(illusts[i]);
    }
    var mangas = dedupe(filtered.map(illustToManga));
    return { mangas: mangas, hasNextPage: illusts.length > 0 };
  },

  getMangaDetail: async function (mangaKey) {
    var key = String(mangaKey);
    var m;
    if (key.indexOf('/artworks/') === 0) {
      var id = key.substring('/artworks/'.length);
      var j = await apiGet('/touch/ajax/illust/details?illust_id=' + id);
      var illust = j.illust_details;
      if (!illust) { throw new Error('illust not found: ' + key); }
      m = {
        key: key,
        title: illust.title || '(null)',
        coverUrl: illust.url || '',
        author: (illust.author_details && illust.author_details.user_name) || '',
        description: illust.comment || '',
        genre: (illust.tags || []).join(', '),
        status: '',
      };
    } else if (key.indexOf('/series/') >= 0) {
      var mm = key.match(/\\/user\\/([^/]+)\\/series\\/([^/]+)/);
      if (!mm) { throw new Error('bad key: ' + key); }
      var sj = await apiGet('/touch/ajax/illust/series/' + mm[2]);
      var series = sj.series || {};
      var illusts = await seriesContents(mm[2]);
      var author = '';
      var tags = {};
      for (var i = 0; i < illusts.length; i++) {
        if (!author && illusts[i].author_details) { author = illusts[i].author_details.user_name || ''; }
        var t = illusts[i].tags || [];
        for (var k = 0; k < t.length; k++) { tags[t[k]] = 1; }
      }
      var cover = typeof series.coverImage === 'string' ? series.coverImage : '';
      if (!cover && illusts.length > 0) { cover = illusts[0].url || ''; }
      m = {
        key: key,
        title: series.title || '(null)',
        coverUrl: cover,
        author: author,
        description: series.caption || '',
        genre: Object.keys(tags).join(', '),
        status: '',
      };
    } else if (key.indexOf('/users/') === 0) {
      var um = key.match(/\\/users\\/([^/]+)/);
      if (!um) { throw new Error('bad key: ' + key); }
      var uj = await apiGet('/ajax/user/' + um[1] + '?full=1');
      m = {
        key: key,
        title: uj.name || ('User ' + um[1]),
        coverUrl: uj.imageBig || '',
        author: uj.name || '',
        description: uj.comment || '',
        genre: '',
        status: '',
      };
    } else {
      throw new Error('bad key: ' + key);
    }
    return m;
  },

  getChapterList: async function (mangaKey) {
    var key = String(mangaKey);
    var illusts;
    if (key.indexOf('/artworks/') === 0) {
      var id = key.substring('/artworks/'.length);
      var j = await apiGet('/touch/ajax/illust/details?illust_id=' + id);
      illusts = j.illust_details ? [j.illust_details] : [];
    } else if (key.indexOf('/series/') >= 0) {
      var mm = key.match(/\\/series\\/([^/]+)/);
      illusts = await seriesContents(mm[1]);
    } else if (key.indexOf('/users/') === 0) {
      var um = key.match(/\\/users\\/([^/]+)/);
      illusts = await userIllusts(um[1]);
    } else {
      illusts = [];
    }
    var n = illusts.length;
    var chapters = [];
    for (var i = 0; i < n; i++) {
      chapters.push(illustToChapter(illusts[i], n, n - i));
    }
    // API returns newest-first; normalize to oldest-first
    chapters.reverse();
    for (var c = 0; c < chapters.length; c++) { chapters[c].sortOrder = c; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).split('/').pop();
    var pages = await apiGet('/ajax/illust/' + id + '/pages');
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      var urls = pages[i].urls || {};
      var u = urls.original || urls.regular || urls.small || urls.thumb_mini;
      if (u) { out.push({ index: out.length, url: u }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: 'https://app.pixiv.net/' };
  },
};
`;
}
