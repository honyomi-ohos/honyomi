// Guya theme engine (JSON API reader: guya / danke / hachirumi / magicaltranslators)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    // magicaltranslators splits one catalog into per-language sources by slug suffix
    langFilter: '',
  };

  if (/endsWith\("-ES"\)|endsWith\("-PL"\)/.test(kt)) {
    const lang = ctx.gradle && ctx.gradle.sources && ctx.gradle.sources[0] ? ctx.gradle.sources[0].lang : '';
    config.langFilter = lang; // 'en' | 'es' | 'pl'
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: guya)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_sel)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- guya engine ----------------
// manga key:    /reader/series/{slug}/
// chapter key:  /read/manga/{slug}/{num dashed}/1/

function slugFromKey(mangaKey) {
  var m = String(mangaKey).match(/^\\/reader\\/series\\/([^/]+)\\//);
  return m ? m[1] : String(mangaKey).replace(/^\\/+|\\/+$/g, '');
}

function seriesKeyFromChapter(chapterKey) {
  var parts = String(chapterKey).split('/').filter(function (p) { return p.length > 0; });
  // [read, manga, slug, num]
  return { slug: parts[2] || '', num: (parts[3] || '').replace(/-/g, '.') };
}

function langAllows(slug) {
  if (!CFG.langFilter) { return true; }
  if (CFG.langFilter === 'en') { return !/-(ES|PL)$/.test(slug); }
  var suffix = '-' + CFG.langFilter.toUpperCase();
  return slug.indexOf(suffix, slug.length - suffix.length) >= 0;
}

async function fetchAllSeries() {
  var text = await $.http.get(BASE + '/api/get_all_series/');
  return JSON.parse(text);
}

function coverOf(json) {
  var cover = String(json.cover || '');
  if (!cover) { return ''; }
  if (cover.indexOf('http') === 0) { return cover; }
  return BASE + '/' + cover;
}

async function fetchSeries(slug) {
  var text = await $.http.get(BASE + '/api/series/' + slug + '/');
  return JSON.parse(text);
}

function bestGroup(chapterObj, seriesSort) {
  var groups = chapterObj.groups || {};
  var sort = null;
  if (chapterObj.preferred_sort) { sort = chapterObj.preferred_sort; }
  else if (seriesSort) { sort = seriesSort; }
  if (sort && sort.length) {
    for (var i = 0; i < sort.length; i++) {
      if (groups[String(sort[i])] !== undefined) { return String(sort[i]); }
    }
  }
  for (var k in groups) { return String(k); }
  return '';
}

function parseChapters(series) {
  var chapters = series.chapters || {};
  var seriesSort = series.preferred_sort || null;
  var out = [];
  for (var num in chapters) {
    var ch = chapters[num];
    var gid = bestGroup(ch, seriesSort);
    var date = 0;
    if (ch.release_date && ch.release_date[gid]) {
      date = Number(ch.release_date[gid]) * 1000;
    }
    out.push({
      key: '/read/manga/' + series.slug + '/' + String(num).replace(/\\./g, '-') + '/1/',
      name: num + ' - ' + String(ch.title || ''),
      chapterNumber: parseFloat(num) || -1,
      dateUpload: date,
      pages: 0,
      sortOrder: parseFloat(num) || 0
    });
  }
  out.sort(function (a, b) { return a.sortOrder - b.sortOrder; });
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    var payload = await fetchAllSeries();
    var out = [];
    for (var title in payload) {
      var json = payload[title];
      var slug = String(json.slug || '');
      if (!slug || !langAllows(slug)) { continue; }
      out.push({
        key: '/reader/series/' + slug + '/',
        title: title,
        coverUrl: coverOf(json)
      });
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var payload = await fetchAllSeries();
    var q = String(query || '').toLowerCase();
    var out = [];
    for (var title in payload) {
      if (q && title.toLowerCase().indexOf(q) < 0) { continue; }
      var json = payload[title];
      var slug = String(json.slug || '');
      if (!slug || !langAllows(slug)) { continue; }
      out.push({
        key: '/reader/series/' + slug + '/',
        title: title,
        coverUrl: coverOf(json)
      });
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = slugFromKey(mangaKey);
    var series = await fetchSeries(slug);
    var desc = String(series.description || '');
    if (desc.indexOf('<') >= 0) {
      var doc = $.html.parse(desc);
      desc = doc.text();
      if (!desc) {
        // some DOM impls return null textContent on the Document node itself
        var body = R_selFirst(doc, 'body');
        if (body) { desc = body.text(); }
      }
    }
    return {
      key: mangaKey,
      title: String(series.title || slug),
      coverUrl: coverOf(series),
      author: String(series.author || ''),
      artist: String(series.artist || ''),
      description: desc,
      genre: '',
      status: ''
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = slugFromKey(mangaKey);
    var series = await fetchSeries(slug);
    return parseChapters(series);
  },

  getPageList: async function (chapterKey) {
    var ref = seriesKeyFromChapter(chapterKey);
    var series = await fetchSeries(ref.slug);
    var ch = (series.chapters || {})[ref.num];
    if (!ch) { return []; }
    var gid = bestGroup(ch, series.preferred_sort || null);
    var files = (ch.groups || {})[gid] || [];
    var folder = String(ch.folder || '');
    var pages = [];
    for (var i = 0; i < files.length; i++) {
      var url = BASE + '/media/manga/' + ref.slug + '/chapters/' + folder + '/' + gid + '/' + files[i];
      pages.push({ index: pages.length, url: url });
    }
    return pages;
  },

  imageHeaders: function () {
    return {};
  }
};
`;
}
