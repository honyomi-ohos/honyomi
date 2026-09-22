// en/randowiz — bespoke scraper (3 hardcoded categories, paginated chapter crawl)
export const runtime = 'wp';

export function extract(ctx) {
  return { ok: true, config: {}, warnings: [] };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = { Referer: BASE + '/' };

var MANGAS = [
  {
    key: '/category/we-live-in-an-mmo/',
    title: 'Randowiz: We live in an MMO!?',
    author: 'Randowiz',
    artist: 'Randowiz',
    description: "The world of 'Mamuon' where players and NPC's live together in harmony. Or do they? DO THEY?",
    cover: 'https://i0.wp.com/randowis.com/wp-content/uploads/2016/02/MMO_CHP_001_CSP_000.jpg?resize=800%2C800&ssl=1'
  },
  {
    key: '/category/short-comics/',
    title: 'Randowiz: Short comics',
    author: 'Randowiz',
    artist: 'Randowiz',
    description: 'So short that i have to compensate..',
    cover: 'https://i0.wp.com/randowis.com/wp-content/uploads/2021/10/Images_PNGs_Site_BOT-SUPPORT.png'
  },
  {
    key: '/category/art/',
    title: 'Randowiz: Illustations',
    author: 'Randowiz',
    artist: 'Randowiz',
    description: 'You like draw? I give you draw.',
    cover: 'https://i0.wp.com/randowis.com/wp-content/uploads/2021/05/colour-studies-021-post.jpg'
  }
];

function findByKey(key) {
  for (var i = 0; i < MANGAS.length; i++) {
    if (MANGAS[i].key === key) { return MANGAS[i]; }
  }
  return null;
}

function parseDmY(s) {
  var m = /(\\d{1,2})\\/(\\d{1,2})\\/(\\d{4})/.exec(String(s || ''));
  if (!m) { return 0; }
  return new Date(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10)).getTime();
}

module.exports = {
  getPopularManga: async function () {
    return {
      mangas: MANGAS.map(function (m) {
        return { key: m.key, title: m.title, coverUrl: m.cover };
      }),
      hasNextPage: false
    };
  },

  getSearchManga: async function (page, query) {
    var q = (query || '').toLowerCase();
    var out = [];
    for (var i = 0; i < MANGAS.length; i++) {
      if (!q || MANGAS[i].title.toLowerCase().indexOf(q) >= 0) {
        out.push({ key: MANGAS[i].key, title: MANGAS[i].title, coverUrl: MANGAS[i].cover });
      }
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var m = findByKey(mangaKey) || MANGAS[0];
    return {
      key: m.key,
      title: m.title,
      coverUrl: m.cover,
      author: m.author,
      artist: m.artist,
      description: m.description,
      genre: '',
      status: 'ongoing'
    };
  },

  getChapterList: async function (mangaKey) {
    var m = findByKey(mangaKey) || MANGAS[0];
    var chapters = [];
    var currentUrl = BASE + m.key;
    var guard = 0;
    while (currentUrl && guard < 50) {
      guard++;
      var doc = $.html.parse(await $.http.get(currentUrl, HDRS));
      var items = R_sel(doc, '.has-post-thumbnail');
      for (var i = 0; i < items.length; i++) {
        var el = items[i];
        var linkTag = R_selFirst(el, '.elementor-post__title a');
        if (!linkTag) { continue; }
        var href = linkTag.absUrl('href');
        if (!href) { continue; }
        var dateEl = R_selFirst(el, '.elementor-post-date');
        chapters.push({
          key: R_path(href),
          name: linkTag.text(),
          chapterNumber: -1,
          dateUpload: dateEl ? parseDmY(dateEl.text()) : 0,
          pages: 0,
          sortOrder: 0
        });
      }
      var next = R_selFirst(doc, '.next');
      currentUrl = next ? next.absUrl('href') : '';
    }
    chapters.reverse();
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var imgs = R_sel(doc, '.elementor-widget-theme-post-content img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = R_abs(imgs[i].attr('src'));
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
