// EZManhwa theme engine (en: ezmanga, qiscans) — JSON API
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {};
  const am = kt.match(/override val apiUrl[^=]*=\s*"([^"]*)"/);
  if (am) config.apiUrl = am[1];
  if (/rateLimit\(/.test(kt)) warnings.push('rateLimit not enforced in plugin');
  warnings.push('locked (paid) chapters hidden; login not supported');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: ezmanhwa)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var API = CFG.apiUrl || BASE + '/api/v1';

function statusMap(s) {
  switch (s) {
    case 'ONGOING': case 'MASS_RELEASED': return 'ongoing';
    case 'COMPLETED': return 'completed';
    case 'DROPPED': return 'cancelled';
    case 'HIATUS': return 'on_hiatus';
    default: return '';
  }
}

function stripHtml(s) {
  return String(s || '').replace(/<[^>]*>/g, ' ').replace(/\\s+/g, ' ').trim();
}

function mapManga(j) {
  var desc = stripHtml(j.description);
  if (j.alternativeTitles) { desc += (desc ? '\\n\\n' : '') + 'Alternative Titles: ' + j.alternativeTitles; }
  var genres = [];
  var gs = j.genres || [];
  for (var i = 0; i < gs.length; i++) { genres.push(gs[i].name); }
  return {
    key: '/' + j.slug,
    title: j.title || '',
    coverUrl: j.cover || '',
    author: (j.author || '').trim(),
    artist: (j.artist || '').trim(),
    description: desc,
    genre: genres.join(', '),
    status: statusMap(j.status)
  };
}

async function listSeries(url) {
  var text = await $.http.get(url);
  var dto = JSON.parse(text);
  var out = [];
  var rows = dto.data || [];
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].type === 'NOVEL') { continue; }
    out.push(mapManga(rows[i]));
  }
  return { mangas: out, hasNextPage: dto.current < dto.totalPages };
}

function chapterName(num, title) {
  var numStr = '';
  if (num !== null && num !== undefined) {
    numStr = num % 1 === 0 ? String(num) : String(num);
  }
  var parsed = title && String(title).trim() ? String(title).trim() : null;
  if (!numStr) { return parsed || 'Chapter'; }
  if (parsed === null || parsed === numStr) { return 'Chapter ' + numStr; }
  if (parsed.indexOf(numStr) >= 0 && /^(chapter|ch\\.?|episode|ep\\.?)\\s/i.test(parsed)) { return parsed; }
  if (parsed.charAt(0) === '-' || parsed.charAt(0) === ':') { return 'Chapter ' + numStr + ' ' + parsed; }
  return 'Chapter ' + numStr + ' - ' + parsed;
}

module.exports = {
  getPopularManga: async function (page) {
    return listSeries(API + '/series?page=' + page + '&perPage=20&sort=popular');
  },

  getSearchManga: async function (page, query) {
    if (query) {
      return listSeries(API + '/series/search?page=' + page + '&perPage=20&q=' + encodeURIComponent(query));
    }
    return listSeries(API + '/series?page=' + page + '&perPage=20&sort=latest');
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).split('/').pop();
    var text = await $.http.get(API + '/series/' + slug);
    var m = mapManga(JSON.parse(text));
    m.key = mangaKey;
    return m;
  },

  getChapterList: async function (mangaKey) {
    var slug = String(mangaKey).split('/').pop();
    var url = API + '/series/' + slug + '/chapters?page=1&perPage=100&sort=desc';
    var text = await $.http.get(url);
    var dto = JSON.parse(text);
    var out = [];
    var rows = dto.data || [];
    for (var i = 0; i < rows.length; i++) {
      var c = rows[i];
      if (c.requiresPurchase === true) { continue; }
      out.push({
        key: '/series/' + slug + '/chapters/' + c.slug,
        name: chapterName(c.number, c.title),
        chapterNumber: c.number !== null && c.number !== undefined ? c.number : -1,
        dateUpload: c.createdAt ? Math.floor(new Date(c.createdAt).getTime() / 1000) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    var curr = dto.current || 1;
    var total = dto.totalPages || 1;
    while (curr < total) {
      curr++;
      var nextText = await $.http.get(API + '/series/' + slug + '/chapters?page=' + curr + '&perPage=100&sort=desc');
      var nd = JSON.parse(nextText);
      var nrows = nd.data || [];
      for (var k = 0; k < nrows.length; k++) {
        var c2 = nrows[k];
        if (c2.requiresPurchase === true) { continue; }
        out.push({
          key: '/series/' + slug + '/chapters/' + c2.slug,
          name: chapterName(c2.number, c2.title),
          chapterNumber: c2.number !== null && c2.number !== undefined ? c2.number : -1,
          dateUpload: c2.createdAt ? Math.floor(new Date(c2.createdAt).getTime() / 1000) : 0,
          pages: 0,
          sortOrder: 0
        });
      }
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(API + chapterKey);
    var data = JSON.parse(text);
    if (data.requiresPurchase === true) {
      throw new Error('Chapter requires purchase (' + (data.totalImages || 0) + ' pages).');
    }
    var imgs = data.images || [];
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      pages.push({ index: i, url: imgs[i].url });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
