// en/reallifecomics — bespoke scraper (yearly archive mangas, calendar chapter lists)
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
var NAME = ${JSON.stringify(name)};

var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
var DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function yearFromKey(key) {
  var m = /year=(\\d{4})/.exec(String(key || ''));
  return m ? parseInt(m[1], 10) : 0;
}

function allMangas() {
  var now = new Date();
  var current = now.getFullYear();
  var out = [];
  for (var y = current; y >= 1999; y--) {
    if (y === 2016 || y === 2017) { continue; }
    out.push({
      key: '/archivepage.php?year=' + y,
      title: NAME + ' (' + y + ')',
      coverUrl: BASE + '/images/logo.png',
      author: 'Maelyn Dean',
      description: 'The normal daily lives of some abnormal people. This entry includes all the chapters published in ' + y,
      status: y === current ? 'ongoing' : 'completed'
    });
  }
  return out;
}

function findByKey(key) {
  var list = allMangas();
  for (var i = 0; i < list.length; i++) {
    if (list[i].key === key) { return list[i]; }
  }
  return null;
}

function parseCalDate(monthYear, dayText) {
  var m = /^([A-Za-z]+)\\s+(\\d{4})/.exec(String(monthYear || '').trim());
  var d = /^(\\d{1,2})$/.exec(String(dayText || '').trim());
  if (!m || !d) { return 0; }
  var mi = -1;
  for (var i = 0; i < MONTHS.length; i++) {
    if (MONTHS[i].toLowerCase() === m[1].toLowerCase()) { mi = i; break; }
  }
  if (mi < 0) { return 0; }
  return new Date(parseInt(m[2], 10), mi, parseInt(d[1], 10)).getTime();
}

function fmtName(t) {
  if (!t) { return ''; }
  var dt = new Date(t);
  return DAYS[dt.getDay()] + ', ' + MONTHS[dt.getMonth()].substring(0, 3) + ' ' +
    (dt.getDate() < 10 ? '0' : '') + dt.getDate() + ', ' + dt.getFullYear();
}

module.exports = {
  getPopularManga: async function () {
    var list = allMangas();
    return {
      mangas: list.map(function (m) { return { key: m.key, title: m.title, coverUrl: m.coverUrl }; }),
      hasNextPage: false
    };
  },

  getSearchManga: async function (page, query) {
    var q = (query || '').toLowerCase();
    var list = allMangas().filter(function (m) { return !q || m.title.toLowerCase().indexOf(q) >= 0; });
    return {
      mangas: list.map(function (m) { return { key: m.key, title: m.title, coverUrl: m.coverUrl }; }),
      hasNextPage: false
    };
  },

  getMangaDetail: async function (mangaKey) {
    var m = findByKey(mangaKey);
    if (!m) {
      m = { key: mangaKey, title: NAME, coverUrl: BASE + '/images/logo.png', author: 'Maelyn Dean', description: '', status: '' };
    }
    return {
      key: m.key,
      title: m.title,
      coverUrl: m.coverUrl,
      author: m.author,
      description: m.description,
      genre: '',
      status: m.status
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(BASE + mangaKey, HDRS));
    var items = R_sel(doc, '.calendar tbody tr td a');
    var seen = {};
    var chapters = [];
    for (var i = 0; i < items.length; i++) {
      var a = items[i];
      var href = a.absUrl ? a.absUrl('href') : R_abs(a.attr('href') || '');
      if (!href) { continue; }
      var key = R_path(href) + (href.indexOf('?') >= 0 ? '?' + href.split('?')[1].split('#')[0] : '');
      if (seen[key]) { continue; }
      seen[key] = true;
      var monthYear = '';
      try {
        var cal = typeof a.closest === 'function' ? a.closest('.calendar') : null;
        var prev = cal ? cal.previousElementSibling() : null;
        monthYear = prev ? prev.text() : '';
      } catch (e) { monthYear = ''; }
      var dayText = a.text();
      var t = parseCalDate(monthYear, dayText);
      chapters.push({
        key: key,
        name: t ? fmtName(t) : (monthYear + ' ' + dayText).trim(),
        chapterNumber: chapters.length,
        dateUpload: t,
        pages: 0,
        sortOrder: 0
      });
    }
    for (var j = 0; j < chapters.length; j++) { chapters[j].sortOrder = j; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(BASE + chapterKey, HDRS));
    var img = R_selFirst(doc, '.comic img');
    var u = img ? R_abs(img.attr('src') || '') : '';
    return u ? [{ index: 0, url: u }] : [];
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
