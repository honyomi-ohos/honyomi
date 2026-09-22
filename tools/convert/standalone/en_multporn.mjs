// en/multporn (multporn.net) — NSFW Drupal galleries, single "Chapter" per entry
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'sort/type/tag filters not ported; text search only',
      'site unreachable from converter network (connect timeout); port untested live',
    ],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var HDRS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/81.0.4044.122 Safari/537.36',
  'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
};

function parseList(text) {
  var doc = $.html.parse(text);
  var els = R_sel(doc, '.masonry-item');
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var a = R_selFirst(el, '.views-field-title a');
    if (!a) { continue; }
    var href = a.absUrl('href');
    if (!href) { continue; }
    var img = R_selFirst(el, 'img');
    out.push({
      key: R_path(href),
      title: (R_selFirst(el, '.views-field-title') || { text: function () { return ''; } }).text(),
      coverUrl: img ? img.absUrl('src') : ''
    });
  }
  var hasNext = !!R_selFirst(doc, '.pager-next a');
  return { mangas: out, hasNextPage: hasNext };
}

function fieldLinks(doc, labelText) {
  var out = [];
  var fields = R_sel(doc, '.field');
  for (var i = 0; i < fields.length; i++) {
    var f = fields[i];
    var lbl = R_selFirst(f, '.field-label');
    if (!lbl) { continue; }
    if ((lbl.text() || '').indexOf(labelText + ':') !== 0) { continue; }
    var links = R_sel(f, '.links a');
    for (var l = 0; l < links.length; l++) { out.push(links[l].text()); }
  }
  return out;
}

module.exports = {
  getPopularManga: async function (page) {
    return parseList(await $.http.get(BASE + '/best?page=' + (page - 1), HDRS));
  },

  getSearchManga: async function (page, query) {
    return parseList(await $.http.get(BASE + '/search?page=' + (page - 1) + '&search_api_views_fulltext=' + encodeURIComponent(query || ''), HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), HDRS));
    var title = (R_selFirst(doc, 'h1#page-title') || { text: function () { return ''; } }).text();
    var sections = fieldLinks(doc, 'Section');
    var characters = fieldLinks(doc, 'Characters');
    var tags = fieldLinks(doc, 'Tags');
    var authors = fieldLinks(doc, 'Author');
    var unlabelled = [
      'field-name-field-author',
      'field-name-field-authors-gr',
      'field-name-field-img-group',
      'field-name-field-hentai-img-group',
      'field-name-field-rule-63-section'
    ];
    for (var u = 0; u < unlabelled.length; u++) {
      var as = R_sel(doc, '.' + unlabelled[u] + ' a');
      for (var a = 0; a < as.length; a++) { authors.push(as[a].text()); }
    }
    var seenA = {}, artist = [];
    for (var a2 = 0; a2 < authors.length; a2++) { if (!seenA[authors[a2]]) { seenA[authors[a2]] = true; artist.push(authors[a2]); } }
    var genres = [];
    var seenG = {};
    var allG = tags.concat(sections).concat(characters);
    for (var g = 0; g < allG.length; g++) { if (!seenG[allG[g]]) { seenG[allG[g]] = true; genres.push(allG[g]); } }
    var status = 'completed';
    for (var s = 0; s < sections.length; s++) { if (sections[s] === 'Ongoings') { status = 'ongoing'; } }
    var pageCount = R_sel(doc, '.jb-image img').length;
    var descParts = [];
    if (sections.length) { descParts.push('Section:\\n' + sections.join(', ')); }
    if (characters.length) { descParts.push('Characters:\\n' + characters.join(', ')); }
    descParts.push('Pages:\\n' + pageCount);
    return {
      key: mangaKey,
      title: title,
      coverUrl: '',
      author: artist.join(', '),
      description: descParts.join('\\n\\n'),
      genre: genres.join(', '),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    return [{
      key: mangaKey,
      name: 'Chapter',
      chapterNumber: 1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    }];
  },

  getPageList: async function (chapterKey) {
    var doc = $.html.parse(await $.http.get(R_abs(chapterKey), HDRS));
    var els = R_sel(doc, '.jb-image img');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var src = els[i].absUrl('src');
      if (!src) { continue; }
      src = src.replace('/styles/juicebox_2k/public', '').split('?')[0];
      out.push({ index: out.length, url: src });
    }
    return out;
  },

  imageHeaders: function () {
    return HDRS;
  }
};
`;
}
