// all/webtoons — bespoke engine for webtoons.com (multi-lang collapsed to en)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'multi-language ext (7 langs) collapsed to single plugin (lang=en)',
      'author-notes TextInterceptor pages and max-quality/sequential-numbering preferences not portable',
      'id:/URL search prefixes not portable',
    ],
  };
}

export function generate(manifest) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (standalone)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var MOBILE = 'https://m.webtoons.com';
var LANG = 'en';
var RANKINGS = ['trending', 'popular', 'originals', 'canvas'];
var EP_RE = /(?:(s(eason)?|saison|part|vol(ume)?)\\s*\\.?\\s*(\\d+).*?)?(.*?(mini|bonus|special).*?)?(e(p(isode)?)?|ch(apter)?)\\s*\\.?\\s*(\\d+(\\.\\d+)?)/i;

function hdrs() {
  return {
    'Referer': BASE + '/',
    'Cookie': 'ageGatePass=true; locale=' + LANG + '; needGDPR=false',
  };
}
function mobileHdrs() {
  return {
    'Referer': MOBILE + '/',
    'Cookie': 'ageGatePass=true; locale=' + LANG + '; needGDPR=false',
  };
}
function seg(key, i) { return String(key).split('/')[i] || ''; }
function unescapeEntities(s) {
  return String(s || '')
    .replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&#x([0-9A-Fa-f]+);/g, function (m, h) { return String.fromCharCode(parseInt(h, 16)); })
    .replace(/&#(\\d+);/g, function (m, d) { return String.fromCharCode(parseInt(d, 10)); });
}
function mangaFromAnchor(el) {
  var href = el.absUrl('href');
  var titleEl = R_selFirst(el, '.title');
  if (!href || !titleEl) { return null; }
  var path = R_path(href);
  var titleNoMatch = href.match(/[?&]title_no=(\\d+)/);
  var parts = path.split('/');
  // canonical: /<lang>/<type>/<slug>/list?title_no=N  ->  key /<lang>/<type>/<slug>/list/<titleNo>
  if (parts.length >= 5 && titleNoMatch) {
    var img = R_selFirst(el, 'img');
    return {
      key: '/' + parts[1] + '/' + parts[2] + '/' + parts[3] + '/list/' + titleNoMatch[1],
      title: titleEl.text(),
      coverUrl: img ? img.absUrl('src') : '',
    };
  }
  return null;
}
function listUrlFromKey(key) {
  return BASE + '/' + seg(key, 1) + '/' + seg(key, 2) + '/' + seg(key, 3) + '/list?title_no=' + seg(key, 5);
}

module.exports = {
  getPopularManga: async function (page) {
    if (page < 1 || page > RANKINGS.length) { return { mangas: [], hasNextPage: false }; }
    var ranking = RANKINGS[page - 1];
    var text = await $.http.get(BASE + '/' + LANG + '/ranking/' + ranking, hdrs());
    var doc = $.html.parse(text);
    var anchors = R_sel(doc, '.webtoon_list li a');
    var out = [];
    for (var i = 0; i < anchors.length; i++) {
      var m = mangaFromAnchor(anchors[i]);
      if (m) { out.push(m); }
    }
    return { mangas: out, hasNextPage: ranking !== 'canvas' };
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(BASE + '/' + LANG + '/search?keyword=' + encodeURIComponent(query || ''), hdrs());
    var doc = $.html.parse(text);
    var anchors = R_sel(doc, '.webtoon_list li a');
    var out = [];
    for (var i = 0; i < anchors.length; i++) {
      var m = mangaFromAnchor(anchors[i]);
      if (m) { out.push(m); }
    }
    return { mangas: out, hasNextPage: !!R_selFirst(doc, 'a.pagination[aria-current=true] + a') };
  },

  getMangaDetail: async function (mangaKey) {
    var text = await $.http.get(listUrlFromKey(mangaKey), hdrs());
    var doc = $.html.parse(text);
    var titleEl = R_selFirst(doc, 'h1.subj, h3.subj');
    var detail = R_selFirst(doc, '.detail_header .info');
    var info = R_selFirst(doc, '#_asideDetail');
    var author = '';
    var artist = '';
    if (detail) {
      var a1 = R_selFirst(detail, '.author:nth-of-type(1)');
      var area = R_selFirst(detail, '.author_area');
      author = a1 ? R_ownText(a1) : (area ? R_ownText(area) : '');
      var a2 = R_selFirst(detail, '.author:nth-of-type(2)');
      artist = a2 ? R_ownText(a2) : (area ? R_ownText(area) : author);
    }
    var genres = [];
    if (detail) {
      var gs = R_sel(detail, '.genre');
      for (var g = 0; g < gs.length; g++) { genres.push(gs[g].text()); }
    }
    var desc = info ? R_selFirst(info, 'p.summary') : null;
    var dayInfo = info ? R_selFirst(info, 'p.day_info') : null;
    var status = '';
    if (dayInfo) {
      var t = dayInfo.text();
      if (/UP|EVERY|NOUVEAU/.test(t)) { status = 'ongoing'; }
      else if (/END|COMPLETED|TERMIN\\u00C9/.test(t)) { status = 'completed'; }
    }
    var og = R_selFirst(doc, 'head meta[property="og:image"]');
    return {
      key: mangaKey,
      title: titleEl ? titleEl.text() : '',
      coverUrl: og ? og.attr('content') : '',
      author: author,
      artist: artist,
      description: desc ? desc.text() : '',
      genre: genres.join(', '),
      status: status,
    };
  },

  getChapterList: async function (mangaKey) {
    var type = seg(mangaKey, 2) === 'canvas' ? 'canvas' : 'webtoon';
    var titleNo = seg(mangaKey, 5);
    var url = MOBILE + '/api/v1/' + type + '/' + titleNo + '/episodes?pageSize=99999' +
      (type === 'canvas' ? '&readingLanguageCode=' + LANG : '');
    var text = await $.http.get(url, mobileHdrs());
    var episodes = (JSON.parse(text).result || {}).episodeList || [];

    var recognized = 0;
    var unrecognized = 0;
    var parsed = [];
    for (var i = 0; i < episodes.length; i++) {
      var ep = episodes[i];
      var m = ep.episodeTitle.match(EP_RE);
      var chapterNumber = -1;
      var seasonNumber = 1;
      if (m && m[6]) { m = null; } // skip mini/bonus/special episodes numbering
      if (m && m[11] !== undefined) {
        chapterNumber = parseFloat(m[11]);
        seasonNumber = m[4] ? parseInt(m[4], 10) : 1;
      }
      if (chapterNumber === -1) { unrecognized++; } else { recognized++; }
      parsed.push({ ep: ep, chapterNumber: chapterNumber, seasonNumber: seasonNumber });
    }

    if (unrecognized > recognized) {
      for (var s = 0; s < parsed.length; s++) { parsed[s].chapterNumber = s + 1; }
    } else {
      var maxChapterNumber = 0;
      var currentSeason = 1;
      var seasonOffset = 0;
      for (var k = 0; k < parsed.length; k++) {
        var p = parsed[k];
        if (p.chapterNumber !== -1) {
          var originalNumber = p.chapterNumber;
          if (p.seasonNumber > currentSeason) {
            currentSeason = p.seasonNumber;
            if (originalNumber <= maxChapterNumber) { seasonOffset = maxChapterNumber; }
          }
          p.chapterNumber = seasonOffset + originalNumber;
          if (p.chapterNumber > maxChapterNumber) { maxChapterNumber = p.chapterNumber; }
        } else {
          var prev = k > 0 ? parsed[k - 1].chapterNumber : 0;
          p.chapterNumber = (prev === -1 ? 0 : prev) + 0.01;
        }
      }
    }

    var out = [];
    for (var j = 0; j < parsed.length; j++) {
      var item = parsed[j];
      var link = item.ep.viewerLink || '';
      var tn = link.match(/[?&]title_no=(\\d+)/);
      var en = link.match(/[?&]episode_no=(\\d+)/);
      var titleNo2 = tn ? tn[1] : titleNo;
      var epNo = en ? en[1] : String(j + 1);
      var num = Math.round(item.chapterNumber * 100) / 100;
      var name = unescapeEntities(item.ep.episodeTitle) + ' (ch. ' + num + ')';
      if (item.ep.hasBgm) { name += ' \\u266B'; }
      out.push({
        key: '/' + seg(mangaKey, 1) + '/' + seg(mangaKey, 2) + '/' + seg(mangaKey, 3) + '/viewer/' + titleNo2 + '/' + epNo,
        name: name,
        chapterNumber: item.chapterNumber,
        dateUpload: item.ep.exposureDateMillis || 0,
        pages: 0,
        sortOrder: 0,
      });
    }
    // API lists newest-first; host convention is oldest-first
    out.reverse();
    for (var q = 0; q < out.length; q++) { out[q].sortOrder = q; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var url = BASE + '/' + seg(chapterKey, 1) + '/' + seg(chapterKey, 2) + '/' + seg(chapterKey, 3) +
      '/viewer?title_no=' + seg(chapterKey, 5) + '&episode_no=' + seg(chapterKey, 6);
    var text = await $.http.get(url, hdrs());
    var doc = $.html.parse(text);
    var imgs = R_sel(doc, 'div#_imageList > img');
    var pages = [];
    for (var i = 0; i < imgs.length; i++) {
      var u = imgs[i].attr('data-url');
      if (u) { pages.push({ index: pages.length, url: u }); }
    }
    if (pages.length === 0) {
      // motion toon: assets JSON referenced from the document
      var docUrlM = text.match(/documentURL:.*?'(.*?)'/);
      var pathM = text.match(/jpg:.*?'(.*?)\\{/);
      if (docUrlM && pathM) {
        var assetText = await $.http.get(docUrlM[1], hdrs());
        var images = (JSON.parse(assetText).assets || {}).images || {};
        for (var key in images) {
          if (key.indexOf('layer') >= 0) {
            pages.push({ index: pages.length, url: pathM[1] + images[key] });
          }
        }
      }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  },
};
`;
}
