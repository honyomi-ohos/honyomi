// ScanReader theme engine (fr: scanreader, hentaiscanreader) — WP with protected chapter ajax + base64 image array
export const runtime = 'wp';

export function extract(ctx) {
  const warnings = [];
  const config = {};
  warnings.push('chapter scanlator info approximated; chapter ajax sent as urlencoded instead of multipart');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: scanreader)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function parseFrDate(s) {
  var m = /(\\d{1,2})\\/(\\d{1,2})\\/(\\d{4})/.exec(String(s || ''));
  if (!m) { return 0; }
  return Math.floor(Date.UTC(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10)) / 1000);
}

function lazyImg(el) {
  if (!el) { return ''; }
  if (el.attr('data-lazy-src')) { return el.absUrl('data-lazy-src') || el.attr('data-lazy-src'); }
  var srcset = el.attr('data-lazy-srcset');
  if (srcset) { return srcset.split(',')[0].trim().split(' ')[0]; }
  var src = el.absUrl('src') || el.attr('src') || '';
  if (src.indexOf('data:') === 0) { return ''; }
  return src;
}

function coverFromOnClick(onclick) {
  var m = /addToHistory\\(\\d+\\s*,\\s*'[^']*'\\s*,\\s*'([^']+)'/.exec(String(onclick || ''));
  return m ? m[1] : '';
}

function mangaFromCard(el) {
  var link = R_selFirst(el, 'a');
  var h3 = R_selFirst(el, 'h3');
  if (!link || !h3) { return null; }
  var title = h3.text();
  if (title.indexOf('(Novel)') >= 0) { return null; }
  var cover = coverFromOnClick(link.attr('onclick')) || lazyImg(R_selFirst(el, 'img'));
  return { key: R_path(link.attr('href')), title: title, coverUrl: cover };
}

module.exports = {
  getPopularManga: async function (page) {
    var url;
    if (page > 2) {
      url = BASE + '/bibliotheque/page/' + (page - 1) + '/?sort=views';
    } else if (page === 2) {
      url = BASE + '/bibliotheque/?sort=views';
    } else {
      url = BASE + '/';
    }
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    var cards = page > 1 ? R_sel(doc, 'div.manga-card') : R_sel(doc, 'div.popular-section div.manga-card');
    var mangas = [];
    for (var i = 0; i < cards.length; i++) {
      var m = mangaFromCard(cards[i]);
      if (m) { mangas.push(m); }
    }
    var hasNextPage = page > 1 ? !!R_selFirst(doc, 'a.pagination-next') : mangas.length > 0;
    return { mangas: mangas, hasNextPage: hasNextPage };
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/?s=' + encodeURIComponent(query.trim()) + '&post_type=manga');
    var doc = $.html.parse(text);
    var cards = R_sel(doc, 'div.manga-card');
    var mangas = [];
    for (var i = 0; i < cards.length; i++) {
      var m = mangaFromCard(cards[i]);
      if (m) { mangas.push(m); }
    }
    return { mangas: mangas, hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(BASE + mangaKey);
    var doc = $.html.parse(text);
    var titleEl = R_selFirst(doc, 'h1.manga-title');
    var og = R_selFirst(doc, 'meta[property="og:image"]');
    var cover = og ? (og.attr('content') || '') : '';
    if (!cover) { cover = lazyImg(R_selFirst(doc, 'img.wp-post-image')); }
    if (cover && cover.indexOf('http') !== 0) { cover = R_abs(cover); }
    var descEl = R_selFirst(doc, 'div.manga-content div[style*="background: #333"] p');
    var author = '';
    var genre = '';
    var status = 'UNKNOWN';
    var rows = R_sel(doc, 'div.manga-info-grid > div');
    for (var i = 0; i < rows.length; i++) {
      var labelEl = R_selFirst(rows[i], ':scope > div:first-child');
      var valueEl = R_selFirst(rows[i], ':scope > div:last-child');
      if (!labelEl || !valueEl) { continue; }
      var label = labelEl.text().trim().toLowerCase();
      if (label.indexOf('auteur') >= 0) {
        author = valueEl.text().trim();
      } else if (label.indexOf('genres') >= 0) {
        var spans = R_sel(valueEl, 'span');
        var gs = [];
        for (var s = 0; s < spans.length; s++) { gs.push(spans[s].text()); }
        genre = gs.join(', ');
      } else if (label.indexOf('statut') >= 0) {
        var st = valueEl.text().trim().toLowerCase();
        if (st.indexOf('cours') >= 0) { status = 'ONGOING'; }
        else if (st.indexOf('termin') >= 0) { status = 'COMPLETED'; }
        else if (st.indexOf('hiatus') >= 0) { status = 'ON_HIATUS'; }
        else if (st.indexOf('licenci') >= 0) { status = 'LICENSED'; }
      }
    }
    return {
      key: mangaKey,
      title: titleEl ? titleEl.text() : '',
      coverUrl: cover,
      author: author,
      description: descEl ? descEl.text() : '',
      genre: genre,
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var mangaUrl = BASE + mangaKey;
    var text = await $.http.get(mangaUrl);
    var doc = $.html.parse(text);
    var container = R_selFirst(doc, '#secure-chapters-container');
    if (!container) { return []; }
    var mangaId = container.attr('data-manga-id') || '';
    var nonce = container.attr('data-nonce') || '';
    if (!mangaId || !nonce) { return []; }
    var body = 'action=load_protected_chapters_html&manga_id=' + encodeURIComponent(mangaId) + '&nonce=' + encodeURIComponent(nonce);
    var raw = await $.http.post(BASE + '/wp-admin/admin-ajax.php', body, {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Referer': mangaUrl,
      'X-Requested-With': 'XMLHttpRequest'
    });
    var html = raw;
    try {
      var parsed = JSON.parse(raw);
      if (parsed && parsed.data) { html = parsed.data; }
    } catch (e) { /* raw HTML */ }
    var trimmed = String(html).trim();
    if (trimmed === '0' || trimmed === '-1') { return []; }
    var cdoc = $.html.parse(trimmed);
    var chapters = [];
    var anchors = R_sel(cdoc, 'a[href*="/chapitre/"]');
    for (var i = 0; i < anchors.length; i++) {
      var a = anchors[i];
      // h4 may be nested inside the <a> (browser parser keeps it) or its next sibling (if markup closes the anchor)
      var h4 = R_selFirst(a, 'h4') || R_selFirst(a, ':scope + h4');
      if (!h4) { continue; }
      var key = R_path(a.attr('href'));
      if (!key) { continue; }
      var dateEl = R_selFirst(h4, ':scope + *');
      var team = R_selFirst(a, 'a[title*="Team"]');
      var scanlator = '';
      if (team) {
        scanlator = team.text();
      } else {
        var solo = R_selFirst(a, 'div');
        var soloTxt = solo ? solo.text() : '';
        if (soloTxt.indexOf('Solo') >= 0) { scanlator = 'Solo'; }
      }
      chapters.push({
        key: key,
        name: h4.text(),
        dateUpload: dateEl ? parseFrDate(dateEl.text()) : 0,
        scanlator: scanlator
      });
    }
    // site lists newest first; host expects oldest first
    chapters.reverse();
    return chapters;
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(BASE + chapterKey);
    var arrMatch = /(?:const|let|var)\\s+\\w+\\s*=\\s*\\[((?:\\s*"[A-Za-z0-9+/=]+"(?:\\s*,\\s*)?)+)\\s*]/.exec(text);
    if (!arrMatch) { return []; }
    var items = arrMatch[1].match(/"([A-Za-z0-9+/=]{20,})"/g) || [];
    var pages = [];
    for (var i = 0; i < items.length; i++) {
      var b64 = items[i].replace(/"/g, '');
      var decoded;
      try { decoded = atob(b64); } catch (e) { continue; }
      pages.push(decoded.split('').reverse().join(''));
    }
    return pages;
  },

  imageHeaders: function () {
    return { 'Referer': BASE + '/' };
  }
};
`;
}
