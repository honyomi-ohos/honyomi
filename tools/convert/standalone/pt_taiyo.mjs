// pt/taiyo — Next.js site + meilisearch multi-search + trpc chapters (token scraped from chunks)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: ['alt-title language names shown as raw codes'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var IMG_CDN = 'https://cdn.taiyo.moe/medias';
var SEARCH = 'https://meilisearch.' + BASE.replace(/^https?:\\/\\//, '') + '/multi-search';
var TOKEN_RE = /NEXT_PUBLIC_MEILISEARCH_PUBLIC_KEY:(\\s+)?"([^"]+)/;
var CHAPTER_RE = /(\\{"chapters".+"totalPages":\\d+\\})/;
var GENRE_MAP = {
  ACTION: 'Ação', ADVENTURE: 'Aventura', COMEDY: 'Comédia', DRAMA: 'Drama',
  ECCHI: 'Ecchi', FANTASY: 'Fantasia', HENTAI: 'Hentai', HORROR: 'Horror',
  MAHOU_SHOUJO: 'Mahou Shoujo', MECHA: 'Mecha', MUSIC: 'Música', MYSTERY: 'Mistério',
  PSYCHOLOGICAL: 'Psicológico', ROMANCE: 'Romance', SCI_FI: 'Sci-fi',
  SLICE_OF_LIFE: 'Slice of Life', SPORTS: 'Esportes', SUPERNATURAL: 'Sobrenatural',
  THRILLER: 'Thriller'
};

var bearerToken = null;

async function fetchToken() {
  var doc = $.html.parse(await $.http.get(BASE));
  var scripts = R_sel(doc, 'script[src*="next"]');
  for (var i = scripts.length - 1; i >= 0; i--) {
    var el = scripts[i];
    if (el.attr('nomodule') !== null && el.attr('nomodule') !== undefined && el.attr('nomodule') !== '') { continue; }
    var src = el.attr('src') || '';
    if (src.indexOf('/app') >= 0) { continue; }
    var text = await $.http.get(R_abs(src));
    var m = TOKEN_RE.exec(text);
    if (m) {
      bearerToken = m[2];
      return bearerToken;
    }
  }
  throw new Error('Não foi possivel localizar o token');
}

async function searchPost(bodyStr, retry) {
  var token = bearerToken || (await fetchToken());
  var hdrs = {
    'Content-Type': 'application/json',
    Authorization: 'Bearer ' + token
  };
  try {
    return await $.http.post(SEARCH, bodyStr, hdrs);
  } catch (e) {
    if (retry) { throw e; }
    bearerToken = null;
    return searchPost(bodyStr, true);
  }
}

function pickTitle(titles) {
  var best = null;
  var bestPriority = -1;
  for (var i = 0; i < titles.length; i++) {
    var t = titles[i];
    if (String(t.language || '').indexOf('en') >= 0) { return t.title; }
    if ((t.priority || 0) > bestPriority) {
      bestPriority = t.priority || 0;
      best = t;
    }
  }
  return best ? best.title : '';
}

function parseSearch(text) {
  var j = $.json.parse(text);
  var hits = (j.results && j.results[0] && j.results[0].hits) || [];
  var out = [];
  for (var i = 0; i < hits.length; i++) {
    var h = hits[i];
    var cover = '';
    if (h.mainCoverId) {
      cover = BASE + '/_next/image?url=' + encodeURIComponent(IMG_CDN + '/' + h.id + '/covers/' + h.mainCoverId + '.jpg') + '&w=256&q=75';
    }
    out.push({
      key: '/media/' + h.id,
      title: pickTitle(h.titles || []),
      coverUrl: cover
    });
  }
  return { mangas: out, hasNextPage: out.length > 0 };
}

function findScriptJson(doc, key) {
  var marker = key + '\\\\":';
  var scripts = R_sel(doc, 'script');
  for (var i = 0; i < scripts.length; i++) {
    var data = scripts[i].text();
    if (data.indexOf('6:[') < 0) { continue; }
    var idx = data.indexOf(marker);
    if (idx < 0) { continue; }
    var start = data.indexOf('{', idx + marker.length - 1);
    if (start < 0) { continue; }
    var depth = 0;
    for (var j = start; j < data.length; j++) {
      var ch = data.charAt(j);
      if (ch === '\\\\') { j++; continue; }
      if (ch === '{') { depth++; } else if (ch === '}') {
        depth--;
        if (depth === 0) {
          return data.substring(start, j + 1).replace(/\\\\/g, '');
        }
      }
    }
  }
  return null;
}

module.exports = {
  getPopularManga: async function (page) {
    var body = JSON.stringify({
      queries: [{
        indexUid: 'medias',
        q: '',
        filter: ['deletedAt IS NULL'],
        limit: 21,
        offset: 21 * (page - 1)
      }]
    });
    return parseSearch(await searchPost(body));
  },

  getSearchManga: async function (page, query) {
    var body = JSON.stringify({
      queries: [{
        indexUid: 'medias',
        q: query || '',
        filter: ['deletedAt IS NULL'],
        limit: 21,
        offset: 21 * (page - 1)
      }]
    });
    return parseSearch(await searchPost(body));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey)));
    var title = R_ownText(R_selFirst(doc, 'p.media-title')) || '';
    var img = R_selFirst(doc, 'section img');
    var cover = '';
    if (img) {
      var srcset = img.attr('srcset') || img.attr('src') || '';
      cover = R_abs(srcset.split(' ')[0]);
    }
    var info = null;
    var raw = findScriptJson(doc, 'media');
    if (raw) {
      try { info = $.json.parse(raw); } catch (e) { info = null; }
    }
    var genres = [];
    if (info && info.genres) {
      for (var g = 0; g < info.genres.length; g++) {
        genres.push(GENRE_MAP[info.genres[g]] || info.genres[g]);
      }
    }
    var status = '';
    if (info && info.status === 'FINISHED') { status = 'completed'; }
    else if (info && info.status === 'RELEASING') { status = 'ongoing'; }
    var desc = '';
    var synopsis = R_ownText(R_selFirst(doc, 'section > div.flex + div p')) || (info ? info.synopsis : '') || '';
    if (synopsis) { desc = synopsis + '\\n\\n'; }
    if (info && info.titles && info.titles.length > 0) {
      desc += 'Títulos alternativos:';
      for (var t = 0; t < info.titles.length; t++) {
        var lang = String(info.titles[t].language || '').split('_')[0];
        desc += '\\n\\t' + lang + ': ' + info.titles[t].title;
      }
    }
    return {
      key: mangaKey,
      title: title,
      coverUrl: cover,
      genre: genres.join(', '),
      status: status,
      description: desc.trim()
    };
  },

  getChapterList: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var all = [];
    var page = 1;
    var totalPages = 1;
    do {
      var input = JSON.stringify({ '0': { json: { mediaId: id, page: page, perPage: 50 } } });
      var u = BASE + '/api/trpc/chapters.getByMediaId?batch=1&input=' + encodeURIComponent(input);
      var text = await $.http.get(u);
      var m = CHAPTER_RE.exec(text);
      if (!m) { break; }
      var parsed = $.json.parse(m[1]);
      totalPages = parsed.totalPages || 1;
      for (var i = 0; i < parsed.chapters.length; i++) {
        var c = parsed.chapters[i];
        var name = (c.title && String(c.title).trim())
          ? c.title
          : 'Capítulo ' + String(c.number).replace(/\\.0$/, '');
        all.push({
          key: '/chapter/' + c.id + '/1',
          name: name,
          chapterNumber: c.number,
          dateUpload: c.createdAt ? Date.parse(c.createdAt) || 0 : 0,
          pages: 0
        });
      }
      page++;
    } while (page <= totalPages);
    all.sort(function (a, b) { return b.chapterNumber - a.chapterNumber; });
    all.reverse();
    for (var k = 0; k < all.length; k++) { all[k].sortOrder = k; }
    return all;
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey)));
    var chapterObj = null;
    var raw = findScriptJson(doc, 'mediaChapter');
    if (raw) {
      try { chapterObj = $.json.parse(raw); } catch (e) { chapterObj = null; }
    }
    if (!chapterObj) { throw new Error('Chapter data not found'); }
    var base = IMG_CDN + '/' + chapterObj.media.id + '/chapters/' + chapterObj.id;
    var out = [];
    var pages = chapterObj.pages || [];
    for (var i = 0; i < pages.length; i++) {
      out.push({ index: i, url: base + '/' + pages[i].id + '.jpg' });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
