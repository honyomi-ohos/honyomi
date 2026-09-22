// all/peppercarrot — bespoke engine ( Pepper&Carrot multilingual webcomic, preference-driven)
// Language selection pref approximated to English; hi-res pref off (low-res default).
export const runtime = 'wp';

const ARTWORKS = [
  ['artworks', 'Artworks'], ['wallpapers', 'Wallpapers'], ['sketchbook', 'Sketchbook'], ['misc', 'Misc'],
  ['book-publishing', 'Book-publishing'], ['comissions', 'Commissions'], ['eshop', 'Shop'], ['framasoft', 'Framasoft'],
  ['press', 'Press'], ['references', 'References'], ['wiki', 'Wiki'],
];

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['language-selection preference approximated to English (en); hi-res image preference off'],
  };
}

export function generate(manifest) {
  const arts = JSON.stringify(ARTWORKS);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var ARTWORKS = ${arts};
var AUTHOR = 'David Revoy';
var TITLE = 'Pepper&Carrot';
var COVER_PC = BASE + '/0_sources/0ther/artworks/low-res/2016-02-24_vertical-cover_remake_by-David-Revoy.jpg';
var COVER_MFT = BASE + '/0_sources/0ther/artworks/low-res/2018-11-22_vertical-cover-book-three_by-David-Revoy.jpg';
var COVER_ART = BASE + '/0_sources/0ther/press/low-res/2015-10-12_logo_by-David-Revoy.jpg';

function langEntry(key) {
  return {
    key: key,
    title: key === 'en' ? TITLE : TITLE + ' (' + key.toUpperCase() + ')',
    coverUrl: COVER_PC,
  };
}
function mftEntry(key) {
  return {
    key: 'miniFantasyTheater#' + key,
    title: 'Mini Fantasy Theater' + (key !== 'en' ? ' (' + key.toUpperCase() + ')' : ''),
    coverUrl: COVER_MFT,
  };
}
function artEntry(key, title) {
  return { key: '#' + key, title: title, coverUrl: COVER_ART };
}
function popularList() {
  var out = [langEntry('en'), mftEntry('en')];
  for (var i = 0; i < ARTWORKS.length; i++) { out.push(artEntry(ARTWORKS[i][0], ARTWORKS[i][1])); }
  return out;
}
function parseFigures(doc) {
  var figures = R_sel(doc, 'figure');
  var out = [];
  var size = figures.length;
  for (var i = 0; i < figures.length; i++) {
    var fig = figures[i];
    var cls = fig.attr('class');
    if (cls.indexOf('translated') < 0) { continue; }
    var link = R_selFirst(fig, 'a');
    var img = R_selFirst(fig, 'img');
    if (!link || !img) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var name = img.attr('title');
    var idx = name.lastIndexOf('\\uFF08');
    if (idx >= 0) { name = name.substring(0, idx).trim(); }
    else { name = name.replace(/\\([^)]*\\)\\s*$/, '').trim(); }
    var dateText = '';
    var cap = R_selFirst(fig, 'figcaption');
    if (cap) {
      var m = cap.text().match(/\\d{4}-\\d{2}-\\d{2}/);
      if (m) { dateText = m[0]; }
    }
    out.push({
      key: R_path(href),
      name: name,
      chapterNumber: size - i,
      dateUpload: dateText ? Date.parse(dateText + 'T00:00:00Z') : 0,
      pages: 0,
      sortOrder: 0,
    });
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    return { mangas: popularList(), hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    if (query) { return { mangas: [], hasNextPage: false }; }
    return module.exports.getPopularManga(page);
  },

  getMangaDetail: async function (mangaKey) {
    var key = String(mangaKey);
    if (key.charAt(0) === '#') {
      var art = key.substring(1);
      var title = art.charAt(0).toUpperCase() + art.slice(1);
      for (var i = 0; i < ARTWORKS.length; i++) {
        if (ARTWORKS[i][0] === art) { title = ARTWORKS[i][1]; break; }
      }
      return {
        key: key, title: title, coverUrl: COVER_ART, author: AUTHOR,
        description: '', genre: '', status: 'ongoing',
      };
    }
    if (key.indexOf('miniFantasyTheater') === 0) {
      return {
        key: key,
        title: 'Mini Fantasy Theater' + (key.indexOf('#en') < 0 ? ' (' + key.split('#')[1].toUpperCase() + ')' : ''),
        coverUrl: COVER_MFT, author: AUTHOR,
        description: 'A webcomic series featuring short stories set in the enchanting world of Pepper&Carrot. With its playful humor and whimsical tales, this collection of gag strips is perfect for audiences of all ages.',
        genre: '', status: 'ongoing',
      };
    }
    var desc = '';
    try {
      var text = await $.http.get(BASE + '/0_sources/langs.json');
      var langs = JSON.parse(text);
      var entry = langs[key];
      if (entry) {
        desc = 'Language: ' + (entry.localName || key) + '\\nTranslators: ' + (entry.translators || []).join(', ');
      }
    } catch (e) { /* langs.json optional */ }
    return {
      key: key,
      title: key === 'en' ? TITLE : TITLE + ' (' + key.toUpperCase() + ')',
      coverUrl: COVER_PC, author: AUTHOR, description: desc, genre: '', status: 'ongoing',
    };
  },

  getChapterList: async function (mangaKey) {
    var key = String(mangaKey);
    var out = [];
    if (key.charAt(0) === '#') {
      var text = await $.http.get(BASE + '/0_sources/0ther/' + key.substring(1) + '/low-res/');
      var doc = $.html.parse(text);
      var links = R_sel(doc, 'a');
      for (var i = 0; i < links.length; i++) {
        var filename = links[i].attr('href');
        if (!filename || filename.substring(filename.length - 4) !== '.jpg') { continue; }
        var file = filename.substring(0, filename.length - 4).replace(/_by-David-Revoy$/, '');
        var date = 0;
        var fileStripped = file;
        if (file.length >= 10 && /^\\d{4}-\\d{2}-\\d{2}$/.test(file.substring(0, 10))) {
          fileStripped = file.substring(10);
          date = Date.parse(file.substring(0, 10) + 'T00:00:00Z');
        }
        var norm = fileStripped.replace(/_/g, ' ').replace(/-/g, ' ').trim();
        if (norm) { norm = norm.charAt(0).toUpperCase() + norm.slice(1); }
        out.push({
          key: '/0_sources/0ther/' + key.substring(1) + '/low-res/' + filename,
          name: norm,
          chapterNumber: -1,
          dateUpload: date,
          pages: 0,
          sortOrder: 0,
        });
      }
      out.reverse();
    } else {
      var url = key.indexOf('miniFantasyTheater') === 0
        ? BASE + '/' + key.split('#')[1] + '/webcomics/miniFantasyTheater.html'
        : BASE + '/' + key + '/webcomics/peppercarrot.html';
      var pageText = await $.http.get(url);
      out = parseFigures($.html.parse(pageText));
      out.reverse();
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var key = String(chapterKey);
    if (key.substring(key.length - 4) === '.jpg') {
      return [{ index: 0, url: BASE + key }];
    }
    var text = await $.http.get(BASE + key);
    var doc = $.html.parse(text);
    var urls = [];
    var els = R_sel(doc, '.webcomic-page img').concat(R_sel(doc, '.mft-cv-image img'));
    for (var i = 0; i < els.length; i++) {
      var src = els[i].attr('src');
      if (src) { urls.push(R_abs(src)); }
    }
    var all = [];
    if (urls.length > 0 && urls[0].toLowerCase().indexOf('minifantasytheater') < 0) {
      all.push(urls[0].replace('P00.jpg', '.jpg'));
    }
    all = all.concat(urls);
    var pages = [];
    for (var j = 0; j < all.length; j++) {
      pages.push({ index: j, url: all[j] });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
