// LibGroup theme engine (ru: mangalib, hentailib, slashlib) — JSON API (MangaLib v2 API)
// Auth (Bearer token) only needed for 18+/bookmarks; anonymous API works otherwise.
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = {
    apiDomain: 'https://api.cdnlibs.org',
    siteId: '1',
  };
  const sid = kt.match(/override val siteId: Int = (\d+)/);
  if (sid) config.siteId = sid[1];
  const dom = kt.match(/API_DOMAIN_DEFAULT\s*=\s*"([^"]*)"/);
  if (dom) config.apiDomain = dom[1];
  warnings.push('account features (18+ content, bookmarks) unavailable without login; using first translation branch');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: libgroup)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

var imgServer = null;

function apiHeaders() {
  return {
    'Accept': 'application/json',
    'Referer': BASE,
    'Site-Id': CFG.siteId
  };
}

async function getImgServer() {
  if (imgServer) { return imgServer; }
  try {
    var text = await $.http.get(CFG.apiDomain + '/api/constants?fields[]=imageServers', apiHeaders());
    var dto = JSON.parse(text);
    var servers = (dto.data && dto.data.imageServers) || [];
    var pick = null;
    var first = null;
    for (var i = 0; i < servers.length; i++) {
      var s = servers[i];
      if (s.site_ids && s.site_ids.indexOf(parseInt(CFG.siteId, 10)) >= 0) {
        if (!first) { first = s; }
        if (s.id === 'compress') { pick = s; }
      }
    }
    imgServer = (pick || first || { url: '' }).url;
  } catch (e) {
    imgServer = '';
  }
  return imgServer;
}

function pickTitle(m) {
  return m.eng_name || m.rus_name || m.name || '';
}

function mapShort(m) {
  return {
    key: '/' + m.slug_url,
    title: m.eng_name || m.rus_name || m.name || '',
    coverUrl: (m.cover && m.cover.default) || ''
  };
}

async function listManga(page, query) {
  var url = CFG.apiDomain + '/api/manga?site_id[]=' + CFG.siteId + '&page=' + page;
  if (query) { url += '&q=' + encodeURIComponent(query); }
  var text = await $.http.get(url, apiHeaders());
  var dto = JSON.parse(text);
  var rows = dto.data || [];
  var mangas = [];
  for (var i = 0; i < rows.length; i++) { mangas.push(mapShort(rows[i])); }
  var hasNext = !!(dto.meta && dto.meta.has_next_page);
  return { mangas: mangas, hasNextPage: hasNext };
}

function summaryText(node) {
  var out = '';
  function walk(n) {
    if (Array.isArray(n)) {
      for (var i = 0; i < n.length; i++) { walk(n[i]); }
      return;
    }
    if (!n || typeof n !== 'object') {
      if (typeof n === 'string') { out += n; }
      return;
    }
    var type = n.type;
    if (type === 'text' && typeof n.text === 'string') { out += n.text; return; }
    if (type === 'hardBreak') { out += '\\n'; return; }
    if (type === 'paragraph') {
      walk(n.content);
      out += '\\n';
      return;
    }
    walk(n.content);
  }
  walk(node);
  return out.trim();
}

function statusMap(isLicensed, scanlate, titleStatus) {
  if (isLicensed) { return 'cancelled'; }
  if (scanlate === 'Заморожен' || scanlate === 'Заброшен' || (scanlate === 'Завершён' && titleStatus === 'Приостановлен')) { return 'hiatus'; }
  if (scanlate === 'Завершён' && titleStatus === 'Выпуск прекращён') { return 'cancelled'; }
  if (scanlate === 'Продолжается' || scanlate === 'Выходит') { return 'ongoing'; }
  if (scanlate === 'Завершён') { return 'completed'; }
  if (titleStatus === 'Онгоинг' || titleStatus === 'Анонс') { return 'ongoing'; }
  if (titleStatus === 'Завершён') { return 'completed'; }
  if (titleStatus === 'Приостановлен') { return 'hiatus'; }
  if (titleStatus === 'Выпуск прекращён') { return 'cancelled'; }
  return '';
}

function joinNames(list) {
  var out = [];
  for (var i = 0; i < (list || []).length; i++) {
    if (list[i].name) { out.push(list[i].name.trim()); }
  }
  return out.join(', ');
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga(page, '');
  },

  getSearchManga: async function (page, query) {
    return listManga(page, query);
  },

  getMangaDetail: async function (mangaKey) {
    var url = CFG.apiDomain + '/api/manga' + mangaKey +
      '?fields[]=eng_name&fields[]=otherNames&fields[]=summary&fields[]=rate' +
      '&fields[]=genres&fields[]=tags&fields[]=authors&fields[]=publisher' +
      '&fields[]=manga_status_id&fields[]=status_id&fields[]=artists';
    var text = await $.http.get(url, apiHeaders());
    var d = JSON.parse(text).data;
    var genres = [];
    if (d.type && d.type.label) { genres.push(d.type.label); }
    if (d.ageRestriction && d.ageRestriction.label) { genres.push(d.ageRestriction.label); }
    if (d.genres) {
      for (var i = 0; i < d.genres.length; i++) { genres.push((d.genres[i].name || '').trim()); }
    }
    if (d.tags) {
      for (var j = 0; j < d.tags.length; j++) { genres.push((d.tags[j].name || '').trim()); }
    }
    var desc = '';
    var alt = (d.rus_name && d.eng_name !== d.rus_name) ? d.rus_name + '\\n' : '';
    var rating = d.rating ? d.rating.average : 0;
    desc = alt + (rating ? rating + ' (голосов: ' + (d.rating ? d.rating.votes : 0) + ')\\n' : '');
    if (d.otherNames && d.otherNames.length > 0) {
      desc += 'Альтернативные названия:\\n' + d.otherNames.join(' / ') + '\\n\\n';
    }
    desc += summaryText(d.summary);
    return {
      key: mangaKey,
      title: pickTitle(d),
      coverUrl: (d.cover && d.cover.default) || '',
      author: joinNames(d.authors),
      description: desc.trim(),
      genre: genres.filter(Boolean).join(', '),
      status: statusMap(d.is_licensed, d.scanlateStatus ? d.scanlateStatus.label : '', d.status ? d.status.label : '')
    };
  },

  getChapterList: async function (mangaKey) {
    var text = await $.http.get(CFG.apiDomain + '/api/manga' + mangaKey + '/chapters', apiHeaders());
    var rows = JSON.parse(text).data || [];
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var c = rows[i];
      var branch = (c.branches && c.branches.length > 0) ? c.branches[0] : null;
      if (!branch) { continue; }
      var isOpen = branch.restricted_view ? branch.restricted_view.is_open : true;
      if (!isOpen) { continue; }
      var vol = c.volume || '1';
      var num = c.number || '0';
      var baseName = 'Том ' + vol + '. Глава ' + num;
      var name = c.name ? baseName + ' - ' + c.name : baseName;
      var bid = branch.branch_id != null ? String(branch.branch_id) : '';
      out.push({
        key: mangaKey + '/chapter/' + encodeURIComponent(vol) + '/' + encodeURIComponent(num) + '/' + encodeURIComponent(bid),
        name: name,
        chapterNumber: parseFloat(num) || 0,
        dateUpload: R_date(branch.created_at),
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var m = String(chapterKey).match(/^(\\/[^\\/]+\\/.+?)\\/chapter\\/([^\\/]+)\\/([^\\/]+)\\/?([^\\/]*)$/);
    if (!m) { return []; }
    var slug = m[1];
    var vol = decodeURIComponent(m[2]);
    var num = decodeURIComponent(m[3]);
    var bid = m[4] ? decodeURIComponent(m[4]) : '';
    var url = CFG.apiDomain + '/api/manga' + slug + '/chapter?volume=' + encodeURIComponent(vol) +
      '&number=' + encodeURIComponent(num) +
      (bid ? '&branch_id=' + encodeURIComponent(bid) : '');
    var text = await $.http.get(url, apiHeaders());
    var pages = (JSON.parse(text).data || {}).pages || [];
    var server = await getImgServer();
    var out = [];
    for (var i = 0; i < pages.length; i++) {
      var u = server + pages[i].url;
      out.push({ index: pages[i].slug, url: u });
    }
    out.sort(function (a, b) { return a.index - b.index; });
    for (var j = 0; j < out.length; j++) { out[j].index = j; }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
