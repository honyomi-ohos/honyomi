// all/yskcomics — bespoke JSON-API engine (multi-lang collapsed to en)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'multi-language ext (ar/en) collapsed to single plugin using English (x-localization: en, /en/ keys)',
      'URL-as-query search shortcut not portable; plain name search only',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = 'https://api.ysk-comics.com';
var LANG = 'en';

function headers() {
  return { Referer: BASE + '/', 'x-localization': LANG };
}

function ratingString(rate, rateCount) {
  var v = parseFloat(rate);
  if (isNaN(v) || v <= 0) { return ''; }
  var star;
  if (v >= 4.75) { star = '★★★★★'; }
  else if (v >= 4.25) { star = '★★★★✬'; }
  else if (v >= 3.75) { star = '★★★★☆'; }
  else if (v >= 3.25) { star = '★★★✬☆'; }
  else if (v >= 2.75) { star = '★★★☆☆'; }
  else if (v >= 2.25) { star = '★★✬☆☆'; }
  else if (v >= 1.75) { star = '★★☆☆☆'; }
  else if (v >= 1.25) { star = '★✬☆☆☆'; }
  else if (v >= 0.75) { star = '★☆☆☆☆'; }
  else if (v >= 0.25) { star = '✬☆☆☆☆'; }
  else { star = '☆☆☆☆☆'; }
  var out = star + ' ' + rate;
  if (rateCount > 0) { out += ' (' + rateCount + ')'; }
  return out;
}

function plainText(html) {
  if (!html) { return ''; }
  var doc = $.html.parse('<body>' + html + '</body>');
  return doc.body ? doc.body.text().trim() : html.trim();
}

function slugFromKey(key) {
  var parts = String(key).split('/').filter(Boolean);
  var slug = parts.length ? parts[parts.length - 1] : '';
  if (!slug) { throw new Error('Unable to parse URL: ' + key); }
  return slug;
}

function names(list) {
  var out = [];
  for (var i = 0; i < (list || []).length; i++) { out.push(list[i].name); }
  return out.join(', ');
}

module.exports = {
  getPopularManga: async function (page) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    var text = await $.http.get(BASE + '/api/home/best-comics', headers());
    var data = JSON.parse(text).data || [];
    var out = [];
    for (var i = 0; i < data.length; i++) {
      out.push({
        key: '/' + LANG + '/comic/' + data[i].slug,
        title: data[i].full_name,
        coverUrl: data[i].image || '',
      });
    }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    if (page > 1) { return { mangas: [], hasNextPage: false }; }
    var text = await $.http.get(API + '/api/v1/search-comics-home?name=' + encodeURIComponent(query), headers());
    var data = JSON.parse(text).data || [];
    var out = [];
    for (var i = 0; i < data.length; i++) {
      out.push({
        key: '/' + LANG + '/comic/' + data[i].slug,
        title: data[i].full_name,
        coverUrl: data[i].image || '',
      });
    }
    return { mangas: out, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var slug = slugFromKey(mangaKey);
    var text = await $.http.get(BASE + '/api/comic/' + slug, headers());
    var d = JSON.parse(text).data;
    var desc = [];
    if (d.language_code && LANG !== d.language_code) {
      desc.push('**Sorry, this content is not available in ' + LANG + '.**\\n');
    }
    var rating = ratingString(d.rate || '0', d.rate_count || 0);
    if (rating) { desc.push(rating); }
    desc.push('Publisher: ' + (d.publisher ? d.publisher.name : ''));
    if (d.published_at) { desc.push('Published at: ' + d.published_at); }
    var body = plainText(d.description);
    var description = desc.join('\\n') + '\\n\\n' + body;
    var status = '';
    if (d.status === 'ongoing') { status = 'ongoing'; }
    else if (d.status === 'completed') { status = 'completed'; }
    return {
      key: '/' + LANG + '/comic/' + d.slug,
      title: d.full_name,
      coverUrl: d.image || '',
      author: d.writer ? d.writer.name : '',
      artist: names(d.artists),
      description: description,
      genre: names(d.genres),
      status: status,
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = slugFromKey(mangaKey);
    var out = [];
    var page = 1;
    while (true) {
      var text = await $.http.get(BASE + '/api/comic/chapter/' + slug + '?page=' + page, headers());
      var data = JSON.parse(text).data || {};
      var msgs = data.data_messages || [];
      for (var i = 0; i < msgs.length; i++) {
        out.push({
          key: '/' + LANG + '/chapter/' + msgs[i].slug,
          name: '#' + msgs[i].rank,
          chapterNumber: -1,
          dateUpload: 0,
          pages: 0,
          sortOrder: 0,
        });
      }
      var meta = data.meta || {};
      if (!meta.link_next || msgs.length === 0) { break; }
      page++;
      if (page > 50) { break; }
    }
    // API returns oldest-first already; host convention is oldest-first
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var slug = slugFromKey(chapterKey);
    var text = await $.http.get(BASE + '/api/chapters/images/' + slug, headers());
    var data = JSON.parse(text).data || [];
    var pages = [];
    for (var i = 0; i < data.length; i++) {
      pages.push({ index: i, url: data[i] });
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
