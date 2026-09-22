// pt/taosect — WordPress JSON API (wp-json/wp/v2), images hosted on Google Drive
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'filters not ported',
      'Google Drive view-limit pre-check not ported (pages may fail when GD rate-limits)',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone WP API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = BASE + '/wp-json/wp/v2';
var HDRS = { Accept: 'application/json', Origin: BASE, Referer: BASE };

function unescapeHtml(s) {
  return String(s || '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&nbsp;/g, ' ');
}

function stripHtml(s) {
  var doc = $.html.parse(String(s || ''));
  return doc.text().trim();
}

function toStatus(name) {
  var v = String(name || '');
  if (v === 'Ativos') { return 'ongoing'; }
  if (v === 'Finalizados' || v === 'Oneshots') { return 'completed'; }
  if (v === 'Cancelados') { return 'cancelled'; }
  return '';
}

function parseList(text) {
  var list = $.json.parse(text);
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var link = list[i].link || '';
    if (!link) { continue; }
    out.push({
      key: R_path(link),
      title: unescapeHtml(list[i].title && list[i].title.rendered),
      coverUrl: list[i].thumbnail || ''
    });
  }
  return { mangas: out, hasNextPage: out.length >= 18 };
}

async function countViews(projectId, chapterId) {
  try {
    var body = 'action=update_views_v2&projeto=' + encodeURIComponent(projectId);
    if (chapterId) { body += '&capitulo=' + encodeURIComponent(chapterId); }
    await $.http.post(BASE + '/wp-admin/admin-ajax.php', body, {
      'Content-Type': 'application/x-www-form-urlencoded'
    });
  } catch (e) { /* best effort */ }
}

module.exports = {
  getPopularManga: async function (page) {
    var u = API + '/projetos?order=desc&orderby=views&page=' + page + '&per_page=18&_fields=title,thumbnail,link';
    return parseList(await $.http.get(u, HDRS));
  },

  getSearchManga: async function (page, query) {
    var u = API + '/projetos?page=' + page + '&per_page=18&_fields=title,thumbnail,link';
    var q = (query || '').trim();
    if (q) { u += '&search=' + encodeURIComponent(q); }
    return parseList(await $.http.get(u, HDRS));
  },

  getMangaDetail: async function (mangaKey) {
    var slug = mangaKey.split('/').pop() || mangaKey.split('/')[2];
    var u = API + '/projetos?per_page=1&slug=' + encodeURIComponent(slug) + '&_fields=title,informacoes,content,thumbnail,link';
    var list = $.json.parse(await $.http.get(u, HDRS));
    if (!list || list.length === 0) { throw new Error('Projeto não encontrado.'); }
    var p = list[0];
    var info = p.informacoes || {};
    var genres = [];
    (info.generos || []).forEach(function (g) { genres.push(g.nome); });
    var desc = stripHtml(p.content && p.content.rendered);
    desc += '\\n\\nTítulo original: ' + (info.titulo_pais_origem || '');
    desc += '\\nSerialização: ' + (info.serializacao || '');
    return {
      key: mangaKey,
      title: unescapeHtml(p.title && p.title.rendered),
      coverUrl: p.thumbnail || '',
      author: info.roteiro || '',
      artist: info.arte || '',
      genre: genres.join(', '),
      status: toStatus(info.status_scan && info.status_scan.nome),
      description: desc
    };
  },

  getChapterList: async function (mangaKey) {
    var slug = mangaKey.split('/').pop() || mangaKey.split('/')[2];
    var u = API + '/capitulos?projeto=' + encodeURIComponent(slug) + '&per_page=1000&order=desc&orderby=sequencia&_fields=nome_capitulo,post_id,slug,data_insercao';
    var list = $.json.parse(await $.http.get(u, HDRS));
    if (!list || list.length === 0) { throw new Error('Capítulos não encontrados.'); }
    countViews(list[0].post_id || '');
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var ts = 0;
      if (c.data_insercao) {
        ts = Date.parse(String(c.data_insercao).replace(' ', 'T')) || 0;
      }
      out.push({
        key: '/leitor-online/projeto/' + slug + '/' + c.slug + '/',
        name: c.nome_capitulo || '',
        chapterNumber: -1,
        dateUpload: ts,
        pages: 0
      });
    }
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var m = /projeto\\/([^\\/]+)\\/([^\\/]+)/.exec(chapterKey);
    if (!m) { throw new Error('Invalid chapter key'); }
    var projectSlug = m[1];
    var chapterSlug = m[2];
    var u = API + '/capitulos/' + encodeURIComponent(projectSlug) + '/' + encodeURIComponent(chapterSlug) + '?_fields=id_capitulo,paginas,post_id';
    var d = $.json.parse(await $.http.get(u, HDRS));
    countViews(d.post_id || '', d.id_capitulo || '');
    var out = [];
    var pages = d.paginas || [];
    for (var i = 0; i < pages.length; i++) {
      out.push({ index: i, url: pages[i] });
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/', Origin: BASE };
  }
};
`;
}
