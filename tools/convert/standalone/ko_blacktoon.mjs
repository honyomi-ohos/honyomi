// ko/blacktoon — BlackToon (data-script JSON catalog)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: [
      'site rotates domains via redirect; this port relies on the runtime following redirects automatically (native ext read the Location header to rewrite hosts) — browsing may fail during a rotation',
      'manga status is encoded in the key suffix (|N) since list items cannot carry status',
    ],
  };
}

export function generate(manifest) {
  const body = String.raw`
var CDN = 'https://blacktoonimg.com/';

var PLATFORMS = { 1: '네이버', 2: '다음', 3: '카카오', 4: '레진', 5: '투믹스', 6: '탑툰', 7: '코미카', 8: '배틀코믹', 9: '코믹GT', 10: '케이툰', 11: '애니툰', 12: '폭스툰', 13: '피너툰', 14: '봄툰', 15: '코미코', 16: '무툰', 17: '지존신마', 99: '기타' };
var TAGS = { 1: '학원', 2: '액션', 3: 'SF', 4: '스토리', 5: '판타지', 6: 'BL/백합', 7: '개그/코미디', 8: '연애/순정', 9: '드라마', 10: '로맨스', 11: '시대극', 12: '스포츠', 13: '일상', 14: '추리/미스터리', 15: '공포/스릴러', 16: '성인', 17: '옴니버스', 18: '에피소드', 19: '무협', 20: '소년', 99: '기타' };
var DAYS = { 1: '월', 2: '화', 3: '수', 4: '목', 5: '금', 6: '토', 7: '일', 10: '열흘' };

function HDRS() { return { Referer: BASE + '/', Origin: BASE }; }

function splitKey(key) {
  var parts = String(key).split('|');
  return { id: parts[0], status: parts.length > 1 ? parts[1] : '' };
}

async function getDb() {
  var doc = await H_doc(BASE, HDRS());
  var scripts = R_sel(doc, 'script[src*=data/webtoon]');
  var all = [];
  for (var i = 0; i < scripts.length; i++) {
    var src = scripts[i].attr('src') || '';
    if (!src) { continue; }
    var u = src.charAt(0) === '/' ? BASE + src : BASE + '/' + src;
    var text = await H_get(u, HDRS());
    var eq = text.indexOf(' = ');
    if (eq < 0) { continue; }
    var head = text.substring(0, eq);
    var di = head.indexOf('data');
    if (di < 0) { continue; }
    var listIndex = parseInt(head.substring(di + 4).replace(/[^0-9].*$/, ''), 10);
    if (isNaN(listIndex)) { listIndex = -1; }
    var body = text.substring(eq + 3).replace(/;\s*$/, '');
    var arr;
    try { arr = $.json.parse(body); } catch (e) { continue; }
    if (!arr) { continue; }
    for (var j = 0; j < arr.length; j++) {
      arr[j].__listIndex = listIndex;
      all.push(arr[j]);
    }
  }
  return all;
}

function toManga(it) {
  var poster = it.p || '';
  var cover = poster ? CDN + String(poster).replace(/_x4/, '').replace(/_x3/, '') : '';
  var genres = [];
  if (PLATFORMS[parseInt(it.c, 10)]) { genres.push(PLATFORMS[parseInt(it.c, 10)]); }
  if (DAYS[parseInt(it.d, 10)]) { genres.push(DAYS[parseInt(it.d, 10)]); }
  var tagIds = String(it.tag || '').split(',');
  for (var i = 0; i < tagIds.length; i++) {
    if (!tagIds[i]) { continue; }
    var tg = TAGS[parseInt(tagIds[i], 10)];
    if (tg) { genres.push(tg); }
  }
  var status = it.__listIndex === 0 ? 'completed' : (it.__listIndex === 1 ? 'ongoing' : 'unknown');
  var statusChar = it.__listIndex === 0 ? '0' : (it.__listIndex === 1 ? '1' : 'n');
  return {
    key: it.x + '|' + statusChar,
    title: it.t || '',
    coverUrl: cover,
    author: it.au || '',
    genre: genres.join(', '),
    status: status
  };
}

function chunk(list, page) {
  var start = (page - 1) * 24;
  var end = Math.min(page * 24, list.length);
  return { mangas: list.slice(start, end), hasNextPage: (page + 1) * 24 <= list.length };
}

module.exports = {
  getPopularManga: async function (page) {
    var db = await getDb();
    db.sort(function (a, b) { return (b.h || 0) - (a.h || 0); });
    var out = [];
    var slice = db.slice((page - 1) * 24, Math.min(page * 24, db.length));
    for (var i = 0; i < slice.length; i++) { out.push(toManga(slice[i])); }
    return { mangas: out, hasNextPage: (page + 1) * 24 <= db.length };
  },

  getLatestManga: async function (page) {
    var db = await getDb();
    db.sort(function (a, b) { return (b.g || 0) - (a.g || 0); });
    var out = [];
    var slice = db.slice((page - 1) * 24, Math.min(page * 24, db.length));
    for (var i = 0; i < slice.length; i++) { out.push(toManga(slice[i])); }
    return { mangas: out, hasNextPage: (page + 1) * 24 <= db.length };
  },

  getSearchManga: async function (page, query) {
    var db = await getDb();
    var q = String(query || '').trim().toLowerCase();
    var filtered = [];
    for (var i = 0; i < db.length; i++) {
      if (!q) { filtered.push(db[i]); continue; }
      if (String(db[i].t || '').toLowerCase().indexOf(q) >= 0 ||
          String(db[i].au || '').toLowerCase().indexOf(q) >= 0) {
        filtered.push(db[i]);
      }
    }
    return chunk(filtered.map(toManga), page);
  },

  getMangaDetail: async function (mangaKey) {
    var k = splitKey(mangaKey);
    var doc = await H_doc(BASE + '/webtoon/' + k.id + '.html', HDRS());
    var descEls = R_sel(doc, 'p.mt-2');
    var description = descEls.length ? descEls[descEls.length - 1].text() : '';
    var cover = '';
    var scripts = R_sel(doc, 'script');
    for (var i = 0; i < scripts.length; i++) {
      var data = scripts[i].html ? scripts[i].html() : '';
      if (data && data.indexOf('+img_domain+') >= 0) {
        var after = data.substring(data.indexOf("+'") + 3);
        cover = CDN + after.substring(0, after.indexOf("'+"));
        break;
      }
    }
    var status = 'unknown';
    if (k.status === '0') { status = 'completed'; }
    else if (k.status === '1') { status = 'ongoing'; }
    return {
      key: mangaKey,
      title: '',
      coverUrl: cover,
      description: description,
      genre: '',
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var k = splitKey(mangaKey);
    var u = BASE + '/data/toonlist/' + k.id + '.js?v=' + Math.random().toFixed(17);
    var text = await H_get(u, HDRS());
    var eq = text.indexOf(' = ');
    if (eq < 0) { return []; }
    var body = text.substring(eq + 3).replace(/;\s*$/, '');
    var arr = $.json.parse(body) || [];
    var out = [];
    for (var i = 0; i < arr.length; i++) {
      var c = arr[i];
      if (!c.id) { continue; }
      var ts = c.d ? Date.parse(c.d) : NaN;
      out.push({
        key: k.id + '/' + c.id,
        name: c.t || c.id,
        chapterNumber: -1,
        dateUpload: isNaN(ts) ? 0 : ts,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var doc = await H_doc(BASE + '/webtoons/' + chapterKey + '.html', HDRS());
    var imgs = R_sel(doc, '#toon_content_imgs img');
    var out = [];
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].attr('o_src') || '';
      if (src) { out.push({ index: out.length, url: CDN + src }); }
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/', Origin: BASE }; }
};
`;
  return wrap(manifest, body);
}
