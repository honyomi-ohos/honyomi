// PizzaReader theme engine (self-hosted PizzaReader — JSON APIs)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    apiPath: '/api',
  };

  const ap = kt.match(/apiPath\s*(?::\s*String)?\s*(?:get\s*)?=\s*"([^"]*)"/);
  if (ap && ap[1]) { config.apiPath = ap[1]; }

  const au = kt.match(/apiUrl\s*(?:get\s*)?=[\s\S]{0,80}?"([^"]*)"/);
  if (au && au[1] && !au[1].includes('$baseUrl')) {
    config.apiUrl = au[1];
  }

  if (/addInterceptor|rateLimit\(/.test(kt)) {
    warnings.push('client interceptors (https rewrite/rate limit) not portable');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: pizzareader)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_* helpers)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- pizzareader engine ----------------
var API = CFG.apiUrl || (BASE + CFG.apiPath);

function parseJson(text) {
  try { return JSON.parse(text); } catch (e) { throw new Error('pizza api parse failed'); }
}

function comicToListItem(comic) {
  var url = comic.url || '';
  if (!url) { return null; }
  return {
    key: R_path(url),
    title: comic.title || '',
    coverUrl: R_abs(comic.thumbnail || '')
  };
}

function statusFromRaw(s) {
  var v = String(s || '').substring(0, 7);
  if (v === 'In cors' || v === 'On goin') { return 'ongoing'; }
  if (v === 'Complet' || v === 'Conclus' || v === 'Conclud') { return 'completed'; }
  if (v === 'Licenzi' || v === 'License') { return 'cancelled'; }
  return '';
}

function chapterToItem(ch) {
  var num = -1;
  if (ch.chapter != null) {
    var sub = ch.subchapter != null ? parseFloat('0.' + ch.subchapter) : 0;
    num = (isNaN(sub) ? 0 : sub) + ch.chapter;
  }
  var teams = ch.teams || [];
  var teamNames = [];
  for (var t = 0; t < teams.length; t++) {
    if (teams[t] && teams[t].name) { teamNames.push(teams[t].name); }
  }
  return {
    key: R_path(ch.url || ''),
    name: ch.full_title || ('Chapter ' + (ch.chapter != null ? ch.chapter : '?')),
    chapterNumber: num,
    dateUpload: ch.published_on ? R_date(ch.published_on) : 0,
    pages: 0,
    sortOrder: 0,
    scanlator: teamNames.join(' & ')
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(API + '/comics');
    var data = parseJson(text);
    var comics = (data && data.comics) ? data.comics : [];
    var out = [];
    for (var i = 0; i < comics.length; i++) {
      var m = comicToListItem(comics[i]);
      if (m && m.key) { out.push(m); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(API + '/search/' + encodeURIComponent(query || ''));
    var data = parseJson(text);
    var comics = (data && data.comics) ? data.comics : [];
    var out = [];
    for (var i = 0; i < comics.length; i++) {
      var m = comicToListItem(comics[i]);
      if (m && m.key) { out.push(m); }
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(API + mangaKey);
    var data = parseJson(text);
    var comic = data && data.comic ? data.comic : null;
    if (!comic) { throw new Error('comic not found'); }
    var genres = comic.genres || [];
    var gn = [];
    for (var i = 0; i < genres.length; i++) {
      if (genres[i] && genres[i].name) { gn.push(genres[i].name); }
    }
    return {
      key: mangaKey,
      title: comic.title || '',
      coverUrl: R_abs(comic.thumbnail || ''),
      author: comic.author || '',
      artist: comic.artist || '',
      description: comic.description || '',
      genre: gn.join(', '),
      status: statusFromRaw(comic.status)
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(API + mangaKey);
    var data = parseJson(text);
    var comic = data && data.comic ? data.comic : null;
    if (!comic) { throw new Error('comic not found'); }
    var chapters = comic.chapters || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var ch = chapters[i];
      if (!ch || !ch.url) { continue; }
      out.push(chapterToItem(ch));
    }
    // normalize to oldest-first: sort by chapter number when parseable, keep order otherwise
    var numbered = 0;
    for (var n = 0; n < out.length; n++) {
      if (out[n].chapterNumber >= 0) { numbered++; }
    }
    if (out.length > 0 && numbered >= out.length / 2) {
      out.sort(function (a, b) {
        if (a.chapterNumber !== b.chapterNumber) { return a.chapterNumber - b.chapterNumber; }
        return a.dateUpload - b.dateUpload;
      });
    }
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(API + chapterKey);
    var data = parseJson(text);
    var ch = data && data.chapter ? data.chapter : null;
    if (!ch) { throw new Error('chapter not found'); }
    var imgs = ch.pages || [];
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      if (imgs[i]) { pages.push({ index: pages.length, url: R_abs(imgs[i]) }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
