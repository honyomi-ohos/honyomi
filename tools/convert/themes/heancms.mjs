// HeanCms theme engine (en: luascans, omegascans) — JSON API
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { latestSortBy: 'desc' };
  const lm = kt.match(/override val latestSortBy[^=]*=\s*"([^"]*)"/);
  if (lm) config.latestSortBy = lm[1];
  if (/enableLogin\s*=\s*true/.test(kt)) warnings.push('login/paid chapters not supported; only free chapters listed');
  warnings.push('paid chapters hidden by default');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: heancms)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var API = BASE.replace('://', '://api.');
var SUB_DIR = 'series';

function statusMap(s) {
  switch (s) {
    case 'Ongoing': return 'ongoing';
    case 'Hiatus': return 'on_hiatus';
    case 'Dropped': return 'cancelled';
    case 'Completed': case 'Finished': return 'completed';
    default: return '';
  }
}

function descFromHtml(html) {
  if (!html) { return ''; }
  var doc = $.html.parse('<div>' + html + '</div>');
  var ps = R_sel(doc, 'p');
  var parts = [];
  for (var i = 0; i < ps.length; i++) {
    var t = ps[i].text();
    if (t) { parts.push(t); }
  }
  if (parts.length > 0) { return parts.join('\\n\\n'); }
  var whole = R_selFirst(doc, 'div');
  return whole ? String(whole.text()).replace(/\\n/g, '\\n\\n') : '';
}

function mapManga(j) {
  var genres = [];
  var tags = (j.tags || []).slice().sort(function (a, b) { return a.name < b.name ? -1 : 1; });
  for (var i = 0; i < tags.length; i++) { genres.push(tags[i].name); }
  genres.push('Manhwa');
  var thumb = j.thumbnail || '';
  if (thumb && thumb.indexOf('http') !== 0) { thumb = API + '/' + thumb; }
  return {
    key: '/' + j.series_slug + '@' + j.id,
    title: j.title || '',
    coverUrl: thumb,
    author: (j.author || '').trim(),
    artist: (j.studio || '').trim(),
    description: descFromHtml(j.description),
    genre: genres.join(', '),
    status: statusMap(j.status)
  };
}

async function query(page, queryString, order, orderBy) {
  var url = API + '/query?query_string=' + encodeURIComponent(queryString) +
    '&status=All&order=' + order + '&orderBy=' + orderBy +
    '&series_type=Comic&page=' + page + '&perPage=12&tags_ids=[]&adult=true';
  var text = await $.http.get(url);
  var j = JSON.parse(text);
  var rows = j.data || [];
  var out = [];
  for (var i = 0; i < rows.length; i++) { out.push(mapManga(rows[i])); }
  var hasNext = false;
  if (j.meta) { hasNext = j.meta.current_page < j.meta.last_page; }
  return { mangas: out, hasNextPage: hasNext };
}

module.exports = {
  getPopularManga: async function (page) {
    return query(page, '', 'desc', 'total_views');
  },

  getSearchManga: async function (page, query) {
    return query(page, query || '', 'desc', 'total_views');
  },

  getMangaDetail: async function (mangaKey) {
    var slug = String(mangaKey).split('@')[0].replace(/^\\/+/, '');
    var text = await $.http.get(API + '/series/' + slug);
    var m = mapManga(JSON.parse(text));
    m.key = mangaKey;
    return m;
  },

  getChapterList: async function (mangaKey) {
    var seriesId = String(mangaKey).split('@')[1] || '';
    var slug = String(mangaKey).split('@')[0].replace(/^\\/+/, '');
    var all = [];
    var page = 1;
    while (true) {
      var text = await $.http.get(API + '/chapter/query?page=' + page + '&perPage=1000&series_id=' + seriesId);
      var j = JSON.parse(text);
      var rows = j.data || [];
      for (var i = 0; i < rows.length; i++) { all.push(rows[i]); }
      var hasNext = j.meta ? j.meta.current_page < j.meta.last_page : false;
      if (!hasNext) { break; }
      page++;
    }
    var out = [];
    for (var k = 0; k < all.length; k++) {
      var c = all[k];
      if (c.price) { continue; }
      var name = String(c.chapter_name || '').trim();
      if (c.chapter_title) { name += ' - ' + String(c.chapter_title).trim(); }
      out.push({
        key: '/' + SUB_DIR + '/' + slug + '/' + c.chapter_slug + '@' + c.id,
        name: name,
        chapterNumber: 0,
        dateUpload: c.created_at ? Math.floor(new Date(c.created_at).getTime() / 1000) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var n = 0; n < out.length; n++) { out[n].sortOrder = n; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var urlPart = String(chapterKey).split('@')[0];
    var url = API + urlPart.replace('/' + SUB_DIR + '/', '/chapter/');
    var text = await $.http.get(url);
    var j = JSON.parse(text);
    var data = j.chapter && j.chapter.chapter_data ? j.chapter.chapter_data : null;
    var imgs = data && data.images ? data.images : [];
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i];
      if (u.indexOf('http') !== 0) { u = API + '/' + u; }
      pages.push({ index: i, url: u });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
