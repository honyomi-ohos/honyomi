// InkStory theme engine (ru: inktstory, puremanga) — JSON API v2 with XOR-protected images
export const runtime = 'wp';

export function extract(ctx) {
  const warnings = [];
  const config = {};
  warnings.push('images with XOR-encrypted storage (36-char filename, mode char s/x at index 14) cannot be decrypted by the plugin host; SEC-mode urls are kept unconverted and may fail to render');
  warnings.push('branch preference settings not supported; all branches returned');
  warnings.push('catalogue filters not supported; text search only');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: inktstory)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var API = 'https://api.' + BASE.replace(/^https?:\\/\\//, '').split('/')[0] + '/v2';
var API_HEADERS = {
  'User-Agent': 'Tachiyomi (+https://github.com/keiyoushi/extensions-source)',
  'Accept': 'application/json, text/plain, */*'
};
var PAGE_SIZE = 30;

function resolveTitle(name, fallback) {
  if (!name) { return fallback; }
  if (name.ru && String(name.ru).trim()) { return name.ru; }
  if (name.en && String(name.en).trim()) { return name.en; }
  if (name.original && String(name.original).trim()) { return name.original; }
  return fallback;
}

function formatInt(v) {
  if (v >= 1000000) { return (v / 1000000).toFixed(1) + 'M'; }
  if (v >= 1000) { return (v / 1000).toFixed(1) + 'k'; }
  return String(v);
}

function parseIso(s) {
  if (!s) { return 0; }
  var v = Date.parse(s);
  return isNaN(v) ? 0 : Math.floor(v / 1000);
}

function bookToManga(b) {
  return {
    key: '/content/' + b.slug,
    title: resolveTitle(b.name, b.slug),
    coverUrl: b.poster || ''
  };
}

async function fetchBookId(mangaKey) {
  var slug = String(mangaKey).replace(/^\\/content\\//, '').replace(/^\\/+/, '');
  var text = await $.http.get(API + '/books/' + slug, API_HEADERS);
  var book = JSON.parse(text);
  return { slug: slug, id: book.id };
}

module.exports = {
  getPopularManga: async function (page) {
    var url = API + '/books?page=' + (page - 1) + '&size=' + PAGE_SIZE + '&sort=viewsCount,desc';
    var text = await $.http.get(url, API_HEADERS);
    var books = JSON.parse(text);
    var mangas = [];
    for (var i = 0; i < books.length; i++) { mangas.push(bookToManga(books[i])); }
    return { mangas: mangas, hasNextPage: mangas.length >= PAGE_SIZE };
  },

  getSearchManga: async function (page, query) {
    var url = API + '/books?page=' + (page - 1) + '&size=' + PAGE_SIZE + '&sort=viewsCount,desc';
    if (query) { url += '&search=' + encodeURIComponent(query); }
    var text = await $.http.get(url, API_HEADERS);
    var books = JSON.parse(text);
    var mangas = [];
    for (var i = 0; i < books.length; i++) { mangas.push(bookToManga(books[i])); }
    return { mangas: mangas, hasNextPage: mangas.length >= PAGE_SIZE };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).replace(/^\\/content\\//, '').replace(/^\\/+/, '');
    var text = await $.http.get(API + '/books/' + slug, API_HEADERS);
    var b = JSON.parse(text);
    var descParts = [];
    if (b.description && String(b.description).trim()) { descParts.push(String(b.description).trim()); }
    if (typeof b.averageRating === 'number') {
      var line = '**Рейтинг**: ' + b.averageRating.toFixed(2);
      if (typeof b.ratingVotesCount === 'number') { line += ' (оценок: ' + b.ratingVotesCount + ')'; }
      descParts.push(line);
    }
    if (typeof b.viewsCount === 'number') { descParts.push('**Просмотры**: ' + formatInt(b.viewsCount)); }
    if (typeof b.likesCount === 'number') { descParts.push('**Лайки**: ' + formatInt(b.likesCount)); }
    if (typeof b.bookmarksCount === 'number') { descParts.push('**Закладки**: ' + formatInt(b.bookmarksCount)); }
    if (Array.isArray(b.externalLinks) && b.externalLinks.length > 0) {
      descParts.push('**Внешние ссылки**:\\n' + b.externalLinks.map(function (l) {
        return '- ' + l;
      }).join('\\n'));
    }
    var authors = [];
    var artists = [];
    if (Array.isArray(b.relations)) {
      for (var r = 0; r < b.relations.length; r++) {
        var rel = b.relations[r];
        var pname = rel && rel.publisher && rel.publisher.name ? rel.publisher.name.trim() : '';
        if (!pname) { continue; }
        if (rel.type === 'AUTHOR' && authors.indexOf(pname) < 0) { authors.push(pname); }
        if (rel.type === 'ARTIST' && artists.indexOf(pname) < 0) { artists.push(pname); }
      }
    }
    var status = 'UNKNOWN';
    if (b.status === 'ONGOING') { status = 'ONGOING'; }
    else if (b.status === 'DONE') { status = 'COMPLETED'; }
    else if (b.status === 'FROZEN') { status = 'ON_HIATUS'; }
    var genres = [];
    if (Array.isArray(b.labels)) {
      for (var l = 0; l < b.labels.length; l++) {
        var ln = b.labels[l] && b.labels[l].name ? b.labels[l].name.trim() : '';
        if (ln) { genres.push(ln); }
      }
    }
    if (Array.isArray(b.formats)) {
      for (var f = 0; f < b.formats.length; f++) {
        genres.push(String(b.formats[f]).toLowerCase().replace(/_/g, ' '));
      }
    }
    return {
      key: mangaKey,
      title: resolveTitle(b.name, slug),
      coverUrl: b.poster || '',
      author: authors.join(', '),
      artist: artists.join(', '),
      description: descParts.join('\\n'),
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var info = await fetchBookId(mangaKey);
    var branchesText = await $.http.get(API + '/branches?bookId=' + encodeURIComponent(info.id) + '&moderationStatus=APPROVED', API_HEADERS);
    var branches = {};
    var branchList = JSON.parse(branchesText);
    for (var b = 0; b < branchList.length; b++) {
      var names = [];
      if (Array.isArray(branchList[b].publishers)) {
        for (var p = 0; p < branchList[b].publishers.length; p++) {
          var pn = branchList[b].publishers[p] && branchList[b].publishers[p].name ? branchList[b].publishers[p].name.trim() : '';
          if (pn && names.indexOf(pn) < 0) { names.push(pn); }
        }
      }
      branches[branchList[b].id] = names.join(', ');
    }
    var chText = await $.http.get(API + '/chapters?bookId=' + encodeURIComponent(info.id) + '&moderationStatus=APPROVED', API_HEADERS);
    var list = JSON.parse(chText);
    var chapters = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var vol = (c.volume !== undefined && c.volume !== null) ? String(c.volume).replace(/\\.0$/, '') : '';
      var num = (c.number !== undefined && c.number !== null) ? String(c.number).replace(/\\.0$/, '') : '';
      var baseName;
      if (vol && num) { baseName = 'Том ' + vol + ' Глава ' + num; }
      else if (num) { baseName = 'Глава ' + num; }
      else if (vol) { baseName = 'Том ' + vol; }
      else { baseName = 'Глава'; }
      var subtitle = '';
      if (c.name && String(c.name).trim()) { subtitle = String(c.name).trim(); }
      else if (c.title && String(c.title).trim()) { subtitle = String(c.title).trim(); }
      var name = (subtitle && subtitle.toLowerCase() !== baseName.toLowerCase())
        ? baseName + ' - ' + subtitle
        : baseName;
      chapters.push({
        key: '/content/' + info.slug + '/' + c.id,
        name: name,
        dateUpload: parseIso(c.createdAt),
        scanlator: c.branchId ? (branches[c.branchId] || '') : '',
        sortNum: (typeof c.number === 'number') ? c.number : Infinity
      });
    }
    // normalize to oldest-first by chapter number when available
    chapters.sort(function (a, b2) { return a.sortNum - b2.sortNum; });
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).split('/').pop();
    var text = await $.http.get(API + '/chapters/' + encodeURIComponent(id), API_HEADERS);
    var data = JSON.parse(text);
    var pagesArr = Array.isArray(data.pages) ? data.pages.slice() : [];
    pagesArr.sort(function (a, b) {
      var ai = typeof a.index === 'number' ? a.index : Number.MAX_SAFE_INTEGER;
      var bi = typeof b.index === 'number' ? b.index : Number.MAX_SAFE_INTEGER;
      return ai - bi;
    });
    var pages = [];
    for (var i = 0; i < pagesArr.length; i++) {
      if (pagesArr[i].image && String(pagesArr[i].image).trim()) {
        pages.push(pagesArr[i].image);
      }
    }
    return pages;
  },

  imageHeaders: function () {
    return {
      'User-Agent': 'Tachiyomi (+https://github.com/keiyoushi/extensions-source)',
      'Referer': BASE + '/'
    };
  }
};
`;
}
