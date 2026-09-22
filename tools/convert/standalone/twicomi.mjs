// all/twicomi — bespoke JSON-API engine (api.twicomi.com; tweet data encoded in key fragments)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['author/tweet search-type and sort filters not portable (text search over manga only)'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone JSON API)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.twicomi.com/api/v2';

function parseTokyoDate(s) {
  if (!s) { return 0; }
  var ts = Date.parse(String(s).replace(' ', 'T') + '+09:00');
  return isNaN(ts) ? 0 : ts;
}
function tweetKey(item) {
  var t = item.tweet;
  var ts = parseTokyoDate(t.tweet_create_time);
  var urls = (t.attach_image_urls || []).join(',');
  return '/manga/' + item.author.screen_name + '/' + t.tweet_id + '#' + ts + ',' + urls;
}
function tweetTitle(t) {
  return String(t.tweet_text || '').split('\\n')[0];
}
function tweetToManga(item) {
  var t = item.tweet;
  return {
    key: tweetKey(item),
    title: tweetTitle(t),
    coverUrl: (t.attach_image_urls || [])[0] || '',
  };
}
async function authorTweets(screenName) {
  var results = [];
  var page = 1;
  var totalCount = 0;
  for (var guard = 0; guard < 50; guard++) {
    var text = await $.http.get(API + '/author/manga/list?screen_name=' + encodeURIComponent(screenName) +
      '&order_by=create_time&order=asc&page_no=' + page + '&page_limit=500');
    var data = JSON.parse(text).response;
    totalCount = data.total_count;
    var list = data.manga_list || [];
    for (var i = 0; i < list.length; i++) { results.push(list[i]); }
    if (page * 500 >= totalCount || list.length === 0) { break; }
    page++;
  }
  return results;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(API + '/manga/featured/list?page_no=' + page + '&page_limit=24');
    var data = JSON.parse(text).response;
    var list = data.manga_list || [];
    return { mangas: list.map(tweetToManga), hasNextPage: page * 24 < data.total_count };
  },

  getSearchManga: async function (page, query) {
    var url = API + '/manga/list?page_no=' + page + '&page_limit=12';
    if (query) { url += '&query=' + encodeURIComponent(query); }
    var text = await $.http.get(url);
    var data = JSON.parse(text).response;
    var list = data.manga_list || [];
    return { mangas: list.map(tweetToManga), hasNextPage: page * 12 < data.total_count };
  },

  getMangaDetail: async function (mangaKey) {
    var parts = String(mangaKey).split('/');
    var type = parts[1];
    if (type === 'author') {
      var screenName = parts[2] || '';
      var author = { screen_name: screenName, name: screenName };
      try {
        var text = await $.http.get(API + '/author/manga/list?screen_name=' + encodeURIComponent(screenName) +
          '&order_by=create_time&order=asc&page_no=1&page_limit=1');
        var list = JSON.parse(text).response.manga_list || [];
        if (list.length) { author = list[0].author; }
      } catch (e) { /* minimal details */ }
      return {
        key: mangaKey,
        title: author.name || screenName,
        coverUrl: author.profile_image || '',
        author: author.screen_name || '',
        description: author.description || '',
        genre: '',
        status: '',
      };
    }
    // tweet manga: locate the tweet via the author listing
    var screenName2 = parts[2];
    var tweetId = String(mangaKey).split('#')[0].split('/')[3];
    var tweets = await authorTweets(screenName2);
    for (var i = 0; i < tweets.length; i++) {
      if (String(tweets[i].tweet.tweet_id) === String(tweetId)) {
        var t = tweets[i].tweet;
        var genres = (t.hash_tags || []).concat(t.tags || []);
        return {
          key: mangaKey,
          title: tweetTitle(t),
          coverUrl: (t.attach_image_urls || [])[0] || '',
          author: tweets[i].author.name + ' (@' + tweets[i].author.screen_name + ')',
          description: t.tweet_text || '',
          genre: genres.join(', '),
          status: 'completed',
        };
      }
    }
    throw new Error('tweet not found: ' + mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var parts = String(mangaKey).split('/');
    if (parts[1] !== 'author') {
      // single tweet: one dummy chapter carrying its own data
      var frag = String(mangaKey).split('#')[1] || '';
      var ts = parseInt(frag.split(',')[0], 10) || 0;
      return [{
        key: mangaKey,
        name: 'Tweet',
        chapterNumber: 1,
        dateUpload: ts,
        pages: 0,
        sortOrder: 0,
      }];
    }
    var tweets = await authorTweets(parts[2]);
    var out = [];
    for (var i = 0; i < tweets.length; i++) {
      var item = tweets[i];
      var frag2 = tweetKey(item).split('#')[1] || '';
      var ts2 = parseInt(frag2.split(',')[0], 10) || 0;
      out.push({
        key: tweetKey(item),
        name: tweetTitle(item.tweet),
        chapterNumber: i + 1,
        dateUpload: ts2,
        pages: 0,
        sortOrder: i,
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var frag = String(chapterKey).split('#')[1] || '';
    var urls = frag.split(',').slice(1);
    var pages = [];
    for (var i = 0; i < urls.length; i++) {
      if (urls[i]) { pages.push({ index: pages.length, url: urls[i] }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
