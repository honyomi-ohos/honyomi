// GroupLe theme engine (readmanga, mintmanga, allhentai, selfmanga, seimanga, usagi)
// Catalog API + HTML detail/chapters + rm_h.readerInit page extraction.
export const runtime = 'wp';

const DEFAULTS = {
  tagsSelector: '.creation-element-tags .creation-element-tags__item:not(.creation-element-tags__item--misc) span:not(.text-secondary)',
};

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  const m = kt.match(/tagsSelector:\s*String\s*=\s*"((?:[^"\\]|\\.)*)"/);
  if (m) { config.tagsSelector = m[1]; }

  if (/usagi\.one|ahen\.me/.test(ctx.baseUrl || '')) {
    warnings.push('site cannot complete cross-auth; anonymous access only');
  }
  warnings.push('auth/remember_me cookies unavailable in this host; chapters requiring login will fail');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: grouple)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_sel/R_selFirst/R_ownText)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};
var USER_HASH = '';

// ---------------- grouple engine ----------------
function apiHeaders() {
  return { 'User-Agent': 'arora', 'Accept': 'application/json, text/plain, */*' };
}

function pageHeaders() {
  return { 'User-Agent': 'arora', 'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' };
}

async function catalogSearch(page, query) {
  var url = BASE + '/api/catalog/search?offset=' + (50 * (page - 1));
  if (query) { url += '&q=' + encodeURIComponent(query); }
  url += '&sortType=RATING';
  var text = await $.http.get(url, apiHeaders());
  var json = JSON.parse(text);
  var list = json.list || [];
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var it = list[i];
    var linkName = it.elementId && it.elementId.linkName ? it.elementId.linkName : '';
    if (!linkName) { continue; }
    out.push({
      key: '/' + linkName,
      title: it.name || '',
      coverUrl: it.picUrl || ''
    });
  }
  var hasNext = (json.offset || 0) + (json.limit || 0) < (json.total || 0);
  return { mangas: out, hasNextPage: hasNext };
}

function extractUserHash(doc) {
  var scripts = R_sel(doc, 'script');
  for (var i = 0; i < scripts.length; i++) {
    var data = scripts[i].html() || '';
    if (data.indexOf('user_hash') >= 0) {
      var m = data.match(/user_hash.+'(.+)'/);
      if (m) {
        USER_HASH = m[1];
        return USER_HASH;
      }
    }
  }
  return '';
}

function stars(r) {
  if (r > 9.5) { return '\\u2605\\u2605\\u2605\\u2605\\u2605'; }
  if (r > 8.5) { return '\\u2605\\u2605\\u2605\\u2605\\u272C'; }
  if (r > 7.5) { return '\\u2605\\u2605\\u2605\\u2605\\u2606'; }
  if (r > 6.5) { return '\\u2605\\u2605\\u2605\\u272C\\u2606'; }
  if (r > 5.5) { return '\\u2605\\u2605\\u2605\\u2606\\u2606'; }
  if (r > 4.5) { return '\\u2605\\u2605\\u272C\\u2606\\u2606'; }
  if (r > 3.5) { return '\\u2605\\u2605\\u2606\\u2606\\u2606'; }
  if (r > 2.5) { return '\\u2605\\u272C\\u2606\\u2606\\u2606'; }
  if (r > 1.5) { return '\\u2605\\u2606\\u2606\\u2606\\u2606'; }
  if (r > 0.5) { return '\\u272C\\u2606\\u2606\\u2606\\u2606'; }
  return '\\u2606\\u2606\\u2606\\u2606\\u2606';
}

function parseDetail(doc, key) {
  var title = '';
  var tEl = R_selFirst(doc, '.cr-hero-names__main');
  if (tEl) { title = tEl.text(); }
  if (!title) {
    var meta = R_selFirst(doc, 'meta[itemprop=name]');
    if (meta) { title = meta.attr('content') || ''; }
  }

  var details = {};
  var items = R_sel(doc, '.cr-info-details .cr-info-details-item');
  for (var i = 0; i < items.length; i++) {
    var tSub = R_selFirst(items[i], '.cr-info-details-item__title');
    var vSub = R_selFirst(items[i], '.cr-info-details-item__status');
    if (!tSub || !vSub) { continue; }
    var t = String(tSub.text() || '').toLowerCase();
    var v = String(vSub.text() || '').toLowerCase();
    if (t && v && !details[t]) { details[t] = v; }
  }
  var rel = details['\\u0432\\u044B\\u043F\\u0443\\u0441\\u043A'] || '';
  var tr = details['\\u043F\\u0435\\u0440\\u0435\\u0432\\u043E\\u0434'] || '';
  var status = '';
  if (rel.indexOf('\\u043F\\u0440\\u043E\\u0434\\u043E\\u043B\\u0436') >= 0 || rel.indexOf('\\u043D\\u0430\\u0447\\u0430\\u0442') >= 0) {
    status = 'ongoing';
  } else if (rel.indexOf('\\u0437\\u0430\\u0432\\u0435\\u0440\\u0448') >= 0) {
    status = tr.indexOf('\\u0437\\u0430\\u0432\\u0435\\u0440\\u0448') >= 0 ? 'completed' : 'publishing_finished';
  } else if (rel.indexOf('\\u043F\\u0440\\u0438\\u043E\\u0441\\u0442') >= 0 || rel.indexOf('\\u0437\\u0430\\u043C\\u043E\\u0440\\u043E\\u0436') >= 0) {
    status = 'hiatus';
  }

  var authors = [], artists = [];
  var persons = R_sel(doc, '.cr-main-person-item');
  for (var p = 0; p < persons.length; p++) {
    var roleEl = R_selFirst(persons[p], '.cr-main-person-item__role');
    var role = roleEl ? String(roleEl.text() || '').toLowerCase() : '';
    var nameEls = R_sel(persons[p], '.cr-main-person-item__name a, .cr-main-person-item__name');
    var names = [];
    for (var n = 0; n < nameEls.length; n++) {
      if (nameEls[n].text()) { names.push(nameEls[n].text()); }
    }
    if (names.length === 0) { continue; }
    if (role.indexOf('\\u0430\\u0432\\u0442\\u043E\\u0440') >= 0 || role.indexOf('\\u0441\\u0446\\u0435\\u043D\\u0430\\u0440') >= 0) {
      authors = authors.concat(names);
    } else if (role.indexOf('\\u0445\\u0443\\u0434\\u043E\\u0436') >= 0 || role.indexOf('\\u0438\\u043B\\u043B\\u044E\\u0441\\u0442') >= 0) {
      artists = artists.concat(names);
    }
  }
  var uniq = function (a) {
    var seen = {}, out = [];
    for (var i = 0; i < a.length; i++) {
      if (!seen[a[i]]) { seen[a[i]] = true; out.push(a[i]); }
    }
    return out;
  };

  var catEl = R_selFirst(doc, '.cr-hero-short-details a[href*="/list/category/"]');
  var category = catEl ? catEl.text() : '';
  var limEl = R_selFirst(doc, '.cr-hero-short-details a[href*="/list/limitation/"]');
  var rawAge = limEl ? limEl.text() : '';
  var age = rawAge;
  if (rawAge === 'NC-17' || rawAge === 'R18+') { age = '18+'; }
  else if (rawAge === 'R' || rawAge === 'G' || rawAge === 'PG') { age = '16+'; }
  else if (rawAge === 'PG-13') { age = '12+'; }

  var genreParts = [];
  if (category) { genreParts.push(String(category).toLowerCase()); }
  if (age) { genreParts.push(String(age).toLowerCase()); }
  var tags = R_sel(doc, CFG.tagsSelector);
  for (var g = 0; g < tags.length; g++) {
    var gt = String(tags[g].text() || '').toLowerCase();
    if (gt && genreParts.indexOf(gt) < 0) { genreParts.push(gt); }
  }

  var altEls = R_sel(doc, '#alt-names-dialog .modal-body .py-1');
  var altNames = [];
  for (var a = 0; a < altEls.length; a++) {
    var at = altEls[a].text();
    if (at && altNames.indexOf(at) < 0) { altNames.push(at); }
  }

  var descParts = [];
  var rvEl = R_selFirst(doc, '.cr-hero-rating .cr-hero-rating__value');
  if (rvEl) {
    var rating = parseFloat(rvEl.text());
    if (!isNaN(rating)) {
      var votesEl = R_selFirst(doc, '.cr-hero-rating__text');
      var digits = votesEl ? String(votesEl.text()).replace(/\\D/g, '') : '0';
      descParts.push(stars(rating) + ' ' + rating + ' (\\u0433\\u043E\\u043B\\u043E\\u0441\\u043E\\u0432: ' + (digits || '0') + ')');
    }
  }
  var dEl = R_selFirst(doc, '.cr-description__content');
  if (dEl && dEl.text()) { descParts.push(dEl.text()); }
  if (altNames.length > 0) {
    descParts.push('**\\u0410\\u043B\\u044C\\u0442\\u0435\\u0440\\u043D\\u0430\\u0442\\u0438\\u0432\\u043D\\u044B\\u0435 \\u043D\\u0430\\u0437\\u0432\\u0430\\u043D\\u0438\\u044F**:\\n' +
      altNames.map(function (n) { return '- ' + n; }).join('\\n'));
  }

  var cover = '';
  var thumb = R_selFirst(doc, '.cr-hero-poster__img') || R_selFirst(doc, '.cr-hero-overlay__bg');
  if (thumb) {
    var attrs = ['src', 'data-src', 'data-original', 'data-bg'];
    for (var c = 0; c < attrs.length && !cover; c++) {
      var v = thumb.attr(attrs[c]);
      if (v) { cover = thumb.absUrl(attrs[c]); }
    }
  }

  return {
    key: key,
    title: title,
    coverUrl: cover,
    author: uniq(authors).join(', '),
    description: descParts.join('\\n'),
    genre: genreParts.join(', '),
    status: status
  };
}

function parseGroupleDate(s) {
  var m = String(s || '').match(/(\\d{1,2})\\.(\\d{1,2})\\.(\\d{2})/);
  if (!m) { return 0; }
  var y = 2000 + (+m[3]);
  return new Date(y, +m[2] - 1, +m[1]).getTime();
}

function parseChapters(doc, mangaTitle) {
  var rows = R_sel(doc, 'tr.item-row');
  var out = [];
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    if (!R_selFirst(row, 'td a')) { continue; }
    var dateOk = false;
    var dateCells = R_sel(row, 'td.date');
    for (var d = 0; d < dateCells.length; d++) {
      if (String(dateCells[d].attr('class') || '').indexOf('text-info') < 0) { dateOk = true; }
    }
    if (!dateOk) { continue; }
    var link = R_selFirst(row, 'a.chapter-link');
    if (!link) { continue; }
    var href = link.absUrl('href');
    if (!href) { continue; }
    var titleCell = R_selFirst(row, 'td.item-title');
    var num = titleCell ? parseFloat(titleCell.attr('data-num')) / 10 : -1;
    if (isNaN(num)) { num = -1; }
    var name = String(R_ownText(link) || '').trim();
    if (mangaTitle && mangaTitle.length > 25) {
      var words = mangaTitle.split(' ');
      for (var w = 0; w < words.length; w++) {
        if (words[w] && name.indexOf(words[w]) === 0) {
          name = name.slice(words[w].length).trim();
        }
      }
    }
    var dots = name.indexOf('\\u2026');
    var numIdx = name.search(/[0-9]/);
    if (numIdx < 0) { numIdx = 0; }
    if (dots >= 0 && dots < numIdx) {
      name = name.slice(dots + 1).trim();
    }
    var dn = R_sel(row, 'td.d-none');
    var dateText = dn.length > 0 ? dn[dn.length - 1].text() : '';
    out.push({
      key: R_path(href),
      name: name,
      chapterNumber: num,
      dateUpload: parseGroupleDate(dateText),
      pages: 0,
      sortOrder: 0
    });
  }
  return out;
}

function parsePagesFromReader(text) {
  var readerMark = '';
  if (text.indexOf('rm_h.readerInit(') >= 0) { readerMark = 'rm_h.readerInit('; }
  else if (text.indexOf('rm_h.readerDoInit(') >= 0) { readerMark = 'rm_h.readerDoInit('; }
  else { throw new Error('Reader script not found (site design may have changed)'); }
  var begin = text.indexOf(readerMark);
  var end = text.indexOf(');', begin);
  var trimmed = text.slice(begin, end);
  var re = /\\[['"](.*?)['"],['"](.*?)['"],['"](.*?)['"].*?\\]/g;
  var pages = [];
  var m;
  while ((m = re.exec(trimmed)) !== null) {
    var host = m[1], middle = m[2], end2 = m[3];
    var u;
    if (!middle && end2.indexOf('/static/') === 0) {
      u = BASE + end2;
    } else if (middle.slice(-7) === '/manga/') {
      u = host + end2;
    } else {
      u = middle + host + end2;
    }
    if (u.indexOf('://') < 0) { u = 'https:' + u; }
    if (u.indexOf('one-way.work') >= 0) {
      u = u.split('?')[0];
    }
    u = u.replace(/\\/\\/resh/, '//h');
    if (u) { pages.push({ index: pages.length, url: u }); }
  }
  return pages;
}

module.exports = {
  getPopularManga: async function (page) {
    return catalogSearch(page, '');
  },

  getSearchManga: async function (page, query) {
    return catalogSearch(page, query || '');
  },

  getMangaDetail: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), pageHeaders()));
    return parseDetail(doc, mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var doc = $.html.parse(await $.http.get(R_abs(mangaKey), pageHeaders()));
    extractUserHash(doc);
    var alerts = R_sel(doc, '.alert.alert-warning');
    for (var i = 0; i < alerts.length; i++) {
      if (String(alerts[i].text()).indexOf('\\u0417\\u0430\\u043F\\u0440\\u0435\\u0449\\u0435\\u043D\\u0430 \\u043F\\u0443\\u0431\\u043B\\u0438\\u043A\\u0430\\u0446\\u0438\\u044F') >= 0) {
        throw new Error('Licensed - chapters removed by copyright holder request');
      }
    }
    var tEl = R_selFirst(doc, '.cr-hero-names__main');
    var mangaTitle = tEl ? tEl.text() : '';
    var chapters = parseChapters(doc, mangaTitle);
    // site lists newest first; normalize to oldest-first
    chapters.reverse();
    for (var c = 0; c < chapters.length; c++) { chapters[c].sortOrder = c; }
    return chapters;
  },

  getPageList: async function (chapterKey) {
    if (!USER_HASH) {
      // best effort: re-fetch the manga page to discover the user hash
      try {
        var slug = String(chapterKey).split('/')[1] || '';
        if (slug) {
          var mDoc = $.html.parse(await $.http.get(BASE + '/' + slug, pageHeaders()));
          extractUserHash(mDoc);
        }
      } catch (e) { /* anonymous */ }
    }
    var url = BASE + chapterKey + (USER_HASH ? '?d=' + USER_HASH + '&mtr=true' : '?mtr=true');
    var text;
    try {
      text = await $.http.get(url, pageHeaders());
    } catch (e0) {
      if (String(e0 && e0.message ? e0.message : e0).indexOf('404') >= 0) {
        throw new Error('Chapter requires authorization via WebView (error 404). Log in via WebView and refresh the manga.');
      }
      throw e0;
    }
    var doc = $.html.parse(text);
    var scripts = R_sel(doc, 'script');
    var readerHtml = '';
    for (var i = 0; i < scripts.length; i++) {
      var d = scripts[i].html() || '';
      if (d.indexOf('chapterInfo') >= 0) { readerHtml = d; break; }
    }
    // kt throws on any div.alert, but a region-dependent network-notice alert
    // appears even on free chapters; only treat alert as paid-blocker when the
    // reader script is missing or all images are deleted placeholders.
    var pages = readerHtml ? parsePagesFromReader(readerHtml) : [];
    var allDeleted = pages.length > 0;
    for (var p = 0; p < pages.length; p++) {
      if (String(pages[p].url).indexOf('/static/deleted') < 0) { allDeleted = false; break; }
    }
    if (!readerHtml || allDeleted) {
      if (R_selFirst(doc, 'div.alert') || R_selFirst(doc, 'form.purchase-form')) {
        throw new Error('This chapter is paid. Use the website to purchase and read it.');
      }
      var h1 = R_selFirst(doc, 'h1');
      if (h1 && String(h1.text()).indexOf('\\u0442\\u0440\\u0435\\u0431\\u0443\\u0435\\u0442\\u0441\\u044F \\u043F\\u0440\\u0435\\u043C\\u0438\\u0443\\u043C') >= 0) {
        throw new Error('Premium subscription required for this chapter');
      }
      if (!pages.length) { throw new Error('Reader script not found (login may be required)'); }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
