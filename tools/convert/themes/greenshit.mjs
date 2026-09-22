// GreenShit theme engine (pt: maidscan, vegitoons, verdinha) — JSON API
export const runtime = 'wp';

function propOverride(kt, name) {
  const re = new RegExp(`override\\s+val\\s+${name}\\s*=\\s*"([^"]*)"`);
  const m = kt.match(re);
  return m ? m[1] : undefined;
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    apiUrl: propOverride(kt, 'apiUrl') ?? '',
    cdnUrl: propOverride(kt, 'cdnUrl') ?? '',
    cdnApiUrl: propOverride(kt, 'cdnApiUrl') ?? '',
    scanId: propOverride(kt, 'scanId') ?? '1',
    defaultGenreId: propOverride(kt, 'defaultGenreId') ?? '1',
    limitPerPage: '26',
  };
  if (!config.apiUrl || !config.cdnUrl) {
    return { ok: false, reason: 'apiUrl/cdnUrl not found in Kotlin source' };
  }
  warnings.push('optional account login not supported; locked (🔒) chapters unavailable');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: greenshit)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function apiHeaders() {
  return {
    'Accept': 'application/json',
    'Referer': BASE + '/',
    'Origin': BASE,
    'scan-id': CFG.scanId
  };
}

function normSlash(u) {
  return String(u).replace(/([^:])\\/{2,}/g, '$1/');
}

function imgUrl(path, src, width, mime) {
  if (!src) { return ''; }
  if (/^https?:\\/\\//.test(src)) { return src; }
  var base = CFG.cdnUrl;
  var u;
  if (/^(uploads\\/|wp-content\\/|manga_|WP-manga)/.test(src) || mime) {
    if (src.indexOf('manga_') === 0) {
      u = base + '/wp-content/uploads/WP-manga/data/' + src;
    } else if (src.indexOf('WP-manga') === 0) {
      u = base + '/wp-content/uploads/' + src;
    } else if (src.indexOf('uploads/') === 0) {
      u = base + '/wp-content/' + src;
    } else if (src.indexOf('wp-content/') === 0) {
      u = base + '/' + src;
    } else {
      u = base + '/wp-content/uploads/WP-manga/data/' + src.replace(/^\\/+/, '');
    }
  } else {
    u = base + '/' + path + '/' + src + (width ? '?width=' + width : '');
  }
  return normSlash(u);
}

function dtoGenres(dto) {
  var genre = [];
  if (dto.genero && dto.genero.gen_nome) { genre.push(dto.genero.gen_nome); }
  if (dto.tags) {
    for (var i = 0; i < dto.tags.length; i++) {
      if (dto.tags[i].tag_nome) { genre.push(dto.tags[i].tag_nome); }
    }
  }
  return genre;
}

function mapManga(dto) {
  return {
    key: '/obra/' + dto.obr_id,
    title: dto.obr_nome || '',
    coverUrl: imgUrl('/scans/' + (dto.scan_id || CFG.scanId) + '/obras/' + dto.obr_id + '/', dto.obr_imagem || '', 300)
  };
}

function listHasNext(dto) {
  var cur = dto.currentPage ?? dto.pagina_atual ?? dto.pagina ?? 0;
  var tot = dto.totalPages ?? dto.paginas ?? dto.totalPaginas ?? 0;
  return tot > cur;
}

async function listManga(path, page, query, extra) {
  var url = CFG.apiUrl + path +
    '?limite=' + CFG.limitPerPage +
    '&pagina=' + page +
    (extra ? '&' + extra : '') +
    (query ? '&obr_nome=' + encodeURIComponent(query) : '') +
    (query ? '&todos_generos=1' : '&gen_id=' + CFG.defaultGenreId);
  var text = await $.http.get(url, apiHeaders());
  var dto = JSON.parse(text);
  var obras = dto.obras || [];
  var mangas = [];
  for (var i = 0; i < obras.length; i++) { mangas.push(mapManga(obras[i])); }
  return { mangas: mangas, hasNextPage: listHasNext(dto) };
}

function statusMap(name) {
  var v = String(name || '').toLowerCase();
  if (v === 'em andamento' || v === 'ativo') { return 'ongoing'; }
  if (v === 'concluído' || v === 'concluido') { return 'completed'; }
  if (v === 'hiato') { return 'hiatus'; }
  if (v === 'cancelado') { return 'cancelled'; }
  return '';
}

function stripHtml(s) {
  return String(s || '').replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\\s+/g, ' ').trim();
}

async function fetchDetails(mangaKey) {
  var id = String(mangaKey).split('/obra/')[1] || '';
  id = id.split('/')[0];
  var text = await $.http.get(CFG.apiUrl + '/obras/' + id, apiHeaders());
  return JSON.parse(text);
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga('/obras/ranking', page, '', 'tipo=visualizacoes_geral');
  },

  getSearchManga: async function (page, query) {
    return listManga('/obras/buscar', page, query);
  },

  getMangaDetail: async function (mangaKey) {
    var dto = await fetchDetails(mangaKey);
    var m = mapManga(dto);
    return {
      key: mangaKey,
      title: m.title,
      coverUrl: m.coverUrl,
      author: '',
      description: stripHtml(dto.obr_descricao),
      genre: dtoGenres(dto).join(', '),
      status: dto.status ? statusMap(dto.status.stt_nome) : ''
    };
  },

  getChapterList: async function (mangaKey) {
    var dto = await fetchDetails(mangaKey);
    var caps = dto.capitulos || [];
    var out = [];
    var seen = {};
    for (var i = 0; i < caps.length; i++) {
      var c = caps[i];
      var key = '/capitulo/' + c.cap_id;
      if (seen[key]) { continue; }
      seen[key] = true;
      out.push({
        key: key,
        name: (c.cap_liberado === false ? '🔒 ' : '') + (c.cap_nome || ''),
        chapterNumber: c.cap_numero ?? 0,
        dateUpload: R_date(c.cap_criado_em),
        pages: 0,
        sortOrder: 0
      });
    }
    out.sort(function (a, b) { return a.chapterNumber - b.chapterNumber; });
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).split('/capitulo/')[1] || '';
    var text = await $.http.get(CFG.apiUrl + '/capitulos/' + id, apiHeaders());
    var dto = JSON.parse(text);
    var obraId = dto.obra ? dto.obra.obr_id : 0;
    var scanId = dto.obra ? dto.obra.scan_id : CFG.scanId;
    var num = dto.cap_numero != null ? String(dto.cap_numero).replace(/\\.0$/, '') : '0';
    var path = '/scans/' + scanId + '/obras/' + obraId + '/capitulos/' + num + '/';
    var rawPages = dto.cap_paginas || [];
    var pages = [];
    for (var i = 0; i < rawPages.length; i++) {
      var p = rawPages[i];
      var src, mime;
      if (typeof p === 'string') { src = p; mime = null; }
      else { src = p.src; mime = p.mime; }
      var u = imgUrl(path, src, null, mime);
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
