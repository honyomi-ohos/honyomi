// pt/kivaratoons — JSON API (kivaratoons.com/api)
export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['adult-content pref forced on for details/pages; filters not ported'],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone API)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var API = BASE + '/api';
var ADULT = '?mostrar_conteudo_adulto=true';

function abs(u) { return u ? R_abs(u) : ''; }

function toManga(it) {
  return {
    key: '/obra/' + it.id,
    title: it.nome || '',
    coverUrl: it.capa_url ? abs(it.capa_url) : ''
  };
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(API + '/obras?pagina=' + page + '&limite=24&ordem=views' + '&mostrar_conteudo_adulto=true');
    var j = $.json.parse(text);
    var out = [];
    var list = j.obras || [];
    for (var i = 0; i < list.length; i++) { out.push(toManga(list[i])); }
    return { mangas: out, hasNextPage: (j.pagina || 1) < (j.total_paginas || 1) };
  },

  getSearchManga: async function (page, query) {
    var u = API + '/obras?pagina=' + page + '&limite=24&ordem=recentes&mostrar_conteudo_adulto=true';
    if (query) { u += '&busca=' + encodeURIComponent(query); }
    var text = await $.http.get(u);
    var j = $.json.parse(text);
    var out = [];
    var list = j.obras || [];
    for (var i = 0; i < list.length; i++) { out.push(toManga(list[i])); }
    return { mangas: out, hasNextPage: (j.pagina || 1) < (j.total_paginas || 1) };
  },

  getMangaDetail: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var text = await $.http.get(API + '/obras/' + id + ADULT);
    var d = $.json.parse(text);
    var statusMap = { 1: 'ongoing', 2: 'completed', 3: 'hiatus', 4: 'cancelled' };
    var desc = d.descricao || '';
    if (d.nome_alternativo) { desc += (desc ? '\\n\\n' : '') + 'Título alternativo: ' + d.nome_alternativo; }
    return {
      key: mangaKey,
      title: d.nome || '',
      coverUrl: d.capa_url ? abs(d.capa_url) : '',
      author: d.autor || '',
      description: desc,
      genre: (d.tags || []).join(', '),
      status: statusMap[d.status_id] || ''
    };
  },

  getChapterList: async function (mangaKey) {
    var id = mangaKey.split('/').pop();
    var text = await $.http.get(API + '/obras/' + id + ADULT);
    var d = $.json.parse(text);
    var chapters = d.capitulos || [];
    var out = [];
    for (var i = 0; i < chapters.length; i++) {
      var c = chapters[i];
      var num = c.numero;
      var numStr = (num % 1 === 0) ? String(num) : String(num);
      out.push({
        key: '/reader/chapter/' + c.id,
        name: 'Capítulo ' + numStr,
        chapterNumber: num,
        dateUpload: c.data_publicacao ? Date.parse(c.data_publicacao) || 0 : 0,
        pages: 0,
        sortOrder: i
      });
    }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = chapterKey.split('/').pop();
    var text = await $.http.get(API + '/capitulos/' + id + ADULT);
    var j = $.json.parse(text);
    var pages = (j.paginas || []).slice().sort(function (a, b) { return (a.ordem || 0) - (b.ordem || 0); });
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      var u = abs(pages[i].url);
      if (u) { out.push({ index: out.length, url: u }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
