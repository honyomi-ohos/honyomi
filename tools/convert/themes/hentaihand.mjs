// HentaiHand theme engine (all: hentaihand, nhentaicom) — JSON API
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { chapters: false, hhLangId: [] };
  const cm = kt.match(/override val chapters\s*=\s*(true|false)/);
  if (cm) config.chapters = cm[1] === 'true';
  const lang = ctx.gradle && ctx.gradle.sources && ctx.gradle.sources[0] ? ctx.gradle.sources[0].lang : '';
  if (lang && lang !== 'all') {
    const re = new RegExp(`"${lang}"\\s*->\\s*listOf\\(([\\d,\\s]*)\\)`);
    const lm = kt.match(re);
    if (lm) {
      config.hhLangId = lm[1].split(',').map(s => s.trim()).filter(Boolean);
    }
  }
  warnings.push('optional account login not supported');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: hentaihand)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function langParams() {
  var s = '';
  for (var i = 0; i < CFG.hhLangId.length; i++) {
    s += '&languages[' + (-i - 1) + ']=' + CFG.hhLangId[i];
  }
  return s;
}

async function listComics(page, sort, order, query) {
  var url = BASE + '/api/comics?page=' + page +
    (sort ? '&sort=' + sort : '') +
    (order ? '&order=' + order : '') +
    (sort ? '&duration=all' : '') +
    (query ? '&q=' + encodeURIComponent(query) : '') +
    langParams();
  var text = await $.http.get(url, { Referer: BASE + '/' });
  var dto = JSON.parse(text);
  var rows = dto.data || [];
  var mangas = [];
  for (var i = 0; i < rows.length; i++) {
    mangas.push({
      key: '/en/comic/' + rows[i].slug,
      title: rows[i].title || '',
      coverUrl: rows[i].image_url || ''
    });
  }
  return { mangas: mangas, hasNextPage: !!dto.next_page_url };
}

function names(list) {
  var out = [];
  for (var i = 0; i < (list || []).length; i++) {
    if (list[i].name) { out.push(list[i].name); }
  }
  return out.join(', ');
}

function slugOf(key) {
  return String(key).replace(/^\\/en\\/comic\\//, '');
}

module.exports = {
  getPopularManga: async function (page) {
    return listComics(page, 'popularity', 'desc', '');
  },

  getSearchManga: async function (page, query) {
    return listComics(page, '', '', query);
  },

  getMangaDetail: async function (mangaKey) {
    var slug = slugOf(mangaKey);
    var text = await $.http.get(BASE + '/api/comics/' + slug, { Referer: BASE + '/' });
    var d = JSON.parse(text);
    var genres = [];
    var tags = d.tags || [];
    var rels = d.relationships || [];
    for (var i = 0; i < tags.length; i++) { if (tags[i].name) { genres.push(tags[i].name); } }
    for (var j = 0; j < rels.length; j++) { if (rels[j].name) { genres.push(rels[j].name); } }
    var status = 'completed';
    if (d.status === 'ongoing' || d.status === 'onhold') { status = 'ongoing'; }
    var parts = [];
    if (d.alternative_title) { parts.push('Alternative Title: ' + d.alternative_title); }
    var groups = names(d.groups);
    if (groups) { parts.push('Groups: ' + groups); }
    if (d.description) { parts.push('Description: ' + d.description); }
    if (d.pages) { parts.push('Pages: ' + d.pages); }
    if (d.category && d.category.name) { parts.push('Category: ' + d.category.name); }
    if (d.language && d.language.name) { parts.push('Language: ' + d.language.name); }
    var parodies = names(d.parodies);
    if (parodies) { parts.push('Parodies: ' + parodies); }
    var chars = names(d.characters);
    if (chars) { parts.push('Characters: ' + chars); }
    return {
      key: mangaKey,
      title: d.title || '',
      coverUrl: d.image_url || '',
      author: names(d.authors) || names(d.artists),
      description: parts.join('\\n\\n'),
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = slugOf(mangaKey);
    if (!CFG.chapters) {
      var text = await $.http.get(BASE + '/api/comics/' + slug, { Referer: BASE + '/' });
      var d = JSON.parse(text);
      var dateStr = d.updated_at || '';
      var t = Date.parse(dateStr);
      return [{
        key: slug,
        name: 'Chapter',
        chapterNumber: 1,
        dateUpload: isNaN(t) ? 0 : t,
        pages: 0,
        sortOrder: 0
      }];
    }
    var text2 = await $.http.get(BASE + '/api/comics/' + slug + '/chapters', { Referer: BASE + '/' });
    var rows = JSON.parse(text2);
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var c = rows[i];
      var date = c.added_at || '';
      var du = 0;
      if (date && date.indexOf('day') >= 0) {
        var days = parseInt(String(date).replace(/[^\\d]/g, ''), 10) || 0;
        du = Date.now() - days * 86400000;
      } else {
        var t2 = Date.parse(date);
        du = isNaN(t2) ? 0 : t2;
      }
      out.push({
        key: slug + '/' + c.slug,
        name: c.name || 'Chapter',
        chapterNumber: -1,
        dateUpload: du,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(BASE + '/api/comics/' + chapterKey + '/images', { Referer: BASE + '/' });
    var images = JSON.parse(text).images || [];
    var pages = [];
    for (var i = 0; i < images.length; i++) {
      pages.push({ index: images[i].page, url: images[i].source_url });
    }
    pages.sort(function (a, b) { return a.index - b.index; });
    for (var j = 0; j < pages.length; j++) { pages[j].index = j; }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
