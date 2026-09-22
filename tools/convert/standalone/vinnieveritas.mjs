// all/vinnieVeritas — bespoke single-manga webcomic engine (multi-lang collapsed to en)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['multi-language ext (en/es) collapsed to single plugin using English content'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var THUMB = BASE + '/comics/CCCr000E.jpg';
var SYNOPSIS = 'Almost 7 years ago I started working on a project where I would put everything I had drawn, characters, concepts and nonsense that came up while I was growing up .. it was so much I chose a city to put it all in. Like all people who draw, I abandoned many comics and concepts that I thought, sucked.. but I promised myself when I was around 19 years old that I would not abandon this one; because my ability to draw was less than today\\u2019s, the first two volumes of CCC: The city of the opportunities are\\u2026 umm, ugly. When I was around 21-22 years old I began to animate in flash, so I decided to animate the world embodied in the comic and continue with the comic this time drawn in flash, therefore Volume 3 has color.\\n\\nIn this period I had a lot of animation and illustration work would not let me continue the story of CCC: The city of opportunities, the hiatus lasted about 5 years, while I still did animations I did not carried on with the story in the comic .. Now new comics every Thursday.\\n\\nCCC is the name of the second largest city there is, is not an acronym or an abbreviation for something, CCC: The city of opportunies tells the story of Lucio Vasalle and his misadventures as a newcomer to CCC, comics, drawings and animations are related, they all have bits of story about the characters and their past, you are welcome to explore all this and draw your own conclusions, if you look closely you may find something that someone hasn\\u2019t noticed yet (:';
var ONCLICK_RE = /changeToComic\\("(.+?)"\\)/;

module.exports = {
  getPopularManga: async function (page) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    return {
      mangas: [{ key: '/archiveIndex.php', title: 'CCC: The city of opportunities', coverUrl: THUMB }],
      hasNextPage: false,
    };
  },

  getSearchManga: async function (page, query) {
    return { mangas: [], hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    return {
      key: mangaKey,
      title: 'CCC: The city of opportunities',
      coverUrl: THUMB,
      author: 'Vinnie Veritas',
      artist: 'Vinnie Veritas',
      description: SYNOPSIS,
      genre: 'webcomic',
      status: 'ongoing',
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(BASE + '/archiveIndex.php');
    var doc = $.html.parse(text);
    var entries = R_sel(doc, '.cccLeftInd .cccArchiveEntry[onclick]');
    var out = [];
    for (var i = 0; i < entries.length; i++) {
      var m = entries[i].attr('onclick').match(ONCLICK_RE);
      var comicName = m ? m[1] : '';
      if (!comicName) { continue; }
      out.push({
        key: '/' + comicName + '.php',
        name: entries[i].text(),
        chapterNumber: -1,
        dateUpload: 0,
        pages: 0,
        sortOrder: i,
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, 'img.cccComic.crazylan-en');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].absUrl('src');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
