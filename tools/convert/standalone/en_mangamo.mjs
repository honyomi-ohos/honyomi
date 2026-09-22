// en/mangamo — Firebase-backed official app source. Auth chain (all plain JSON over HTTPS):
// anonymous identitytoolkit signUp -> cloudfunctions v3/login -> signInWithCustomToken,
// then Firestore REST runQuery/getDocument with Bearer idToken; pages via cloudfunctions /page.
// Tokens are cached in module scope (host prefs are not persistent).
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: true,
    config: {},
    warnings: [
      'Google/Firebase endpoints (identitytoolkit, firestore, cloudfunctions) are unreachable from the converter region: live probe unavailable, port untested',
      'hide-coin / exclusives-only preferences not ported (all series and coin chapters shown, coin chapters marked with a coin emoji)',
      'tokens are re-acquired per plugin session (host has no persistent prefs)',
    ],
  };
}

export function generate(manifest) {
  const name = manifest.name;
  return `// ${name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
var FB_KEY = 'AIzaSyCU00GBJ4BPSK5owyaXvHZIXwMJ5Rq5F8c';
var FN = 'https://us-central1-mangamoapp1.cloudfunctions.net/api';
var FS = 'https://firestore.googleapis.com/v1/projects/mangamoapp1/databases/(default)/documents';
var PAGE_SIZE = 50;
var JSONH = { 'Content-Type': 'application/json', Accept: 'application/json' };

var AUTH = { userToken: '', idToken: '', refreshToken: '', expirationTime: 0 };

async function authPost(url, body) {
  return $.json.parse(await $.http.post(url, $.json.stringify(body), JSONH));
}

async function obtainInitialToken() {
  if (!AUTH.userToken) {
    var reg = await authPost('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=' + FB_KEY, { returnSecureToken: true });
    AUTH.userToken = reg.localId;
  }
  var login = await authPost(FN + '/v3/login', { purchaserInfo: { originalAppUserId: AUTH.userToken } });
  var tokenInfo = await authPost('https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=' + FB_KEY, { token: login.accessToken, returnSecureToken: true });
  AUTH.idToken = tokenInfo.idToken;
  AUTH.refreshToken = tokenInfo.refreshToken;
  AUTH.expirationTime = Date.now() + (tokenInfo.expiresIn - 1) * 1000;
}

async function refreshToken() {
  var body = 'grant_type=refresh_token&refresh_token=' + encodeURIComponent(AUTH.refreshToken);
  var text = await $.http.post('https://securetoken.googleapis.com/v1/token?key=' + FB_KEY, body, { 'Content-Type': 'application/x-www-form-urlencoded' });
  var info = $.json.parse(text);
  AUTH.idToken = info.id_token;
  AUTH.refreshToken = info.refresh_token;
  AUTH.expirationTime = Date.now() + (info.expires_in - 1) * 1000;
}

async function getIdToken() {
  if (AUTH.idToken && Date.now() < AUTH.expirationTime) { return AUTH.idToken; }
  if (AUTH.refreshToken) {
    try { await refreshToken(); return AUTH.idToken; } catch (e) { /* fall through */ }
  }
  await obtainInitialToken();
  return AUTH.idToken;
}

function reduceField(el) {
  if (!el || typeof el !== 'object') { return null; }
  var keys = Object.keys(el);
  if (keys.length === 0) { return null; }
  var k = keys[0];
  var v = el[k];
  if (k === 'arrayValue') {
    var vals = (v && v.values) || [];
    var out = [];
    for (var i = 0; i < vals.length; i++) { out.push(reduceField(vals[i])); }
    return out;
  }
  if (k === 'mapValue') { return reduceFields(v && v.fields); }
  return v;
}

function reduceFields(fields) {
  var out = {};
  if (fields) {
    for (var key in fields) {
      if (Object.prototype.hasOwnProperty.call(fields, key)) { out[key] = reduceField(fields[key]); }
    }
  }
  return out;
}

async function fsRunQuery(path, structuredQuery) {
  var token = await getIdToken();
  var text = await $.http.post(FS + '/' + path + ':runQuery', $.json.stringify({ structuredQuery: structuredQuery }),
    { 'Content-Type': 'application/json', Accept: 'application/json', Authorization: 'Bearer ' + token });
  var rows = $.json.parse(text);
  var out = [];
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].document) { out.push(reduceFields(rows[i].document.fields)); }
  }
  return out;
}

async function fsGetDocument(path, fieldList) {
  var token = await getIdToken();
  var u = FS + '/' + path;
  if (fieldList && fieldList.length) {
    var qs = [];
    for (var i = 0; i < fieldList.length; i++) { qs.push('mask.fieldPaths=' + encodeURIComponent(fieldList[i])); }
    u += '?' + qs.join('&');
  }
  var text = await $.http.get(u, { Accept: 'application/json', Authorization: 'Bearer ' + token });
  var doc = $.json.parse(text);
  return reduceFields(doc.fields);
}

var SERIES_FIELDS = ['id', 'name', 'name_lowercase', 'description', 'authors', 'genres', 'ongoing', 'releaseStatusTag', 'titleArt'];

function seriesQuery(offset, extra) {
  var q = {
    from: { collectionId: 'Series' },
    select: { fields: SERIES_FIELDS.map(function (f) { return { fieldPath: f }; }) },
    offset: offset,
    limit: PAGE_SIZE
  };
  if (extra && extra.where) { q.where = extra.where; }
  if (extra && extra.orderBy) { q.orderBy = extra.orderBy; }
  return q;
}

function eqFilter(field, value) {
  return { fieldFilter: { op: 'EQUAL', field: { fieldPath: field }, value: { booleanValue: value } } };
}

function andFilter(filters) {
  return { compositeFilter: { op: 'AND', filters: filters } };
}

function seriesStatus(s) {
  var tag = s.releaseStatusTag || '';
  if (tag === 'Ongoing') { return 'ongoing'; }
  if (tag === 'series-complete' || tag === 'Completed') { return 'completed'; }
  if (tag === 'Paused') { return 'on hiatus'; }
  return s.ongoing === true ? 'ongoing' : '';
}

function seriesToManga(s) {
  var authors = s.authors || [];
  var genres = s.genres || [];
  var anames = [];
  for (var i = 0; i < authors.length; i++) { anames.push(authors[i].name); }
  var gnames = [];
  for (var j = 0; j < genres.length; j++) { gnames.push(genres[j].name); }
  var slug = String(s.name_lowercase || '').replace(/ /g, '-');
  return {
    key: '/catalog/' + encodeURIComponent(slug) + '?series=' + s.id,
    title: s.name || '',
    coverUrl: s.titleArt || '',
    author: anames.join(', '),
    description: s.description || '',
    genre: gnames.join(', '),
    status: seriesStatus(s)
  };
}

function qp(key, name) {
  var m = new RegExp('[?&]' + name + '=([^&]+)').exec(String(key));
  return m ? decodeURIComponent(m[1]) : '';
}

async function getUserIsSubscribed() {
  try {
    var user = await fsGetDocument('Users/' + AUTH.userToken, ['isSubscribed']);
    return user.isSubscribed === true;
  } catch (e) { return false; }
}

module.exports = {
  getPopularManga: async function (page) {
    var q = seriesQuery((page - 1) * PAGE_SIZE, { where: andFilter([eqFilter('enabled', true)]) });
    var list = await fsRunQuery('Series', q);
    return { mangas: list.map(seriesToManga), hasNextPage: list.length < PAGE_SIZE ? false : true };
  },

  getSearchManga: async function (page, query) {
    var lower = String(query || '').toLowerCase();
    var where = andFilter([
      eqFilter('enabled', true),
      { fieldFilter: { op: 'GREATER_THAN_OR_EQUAL', field: { fieldPath: 'name_lowercase' }, value: { stringValue: lower } } },
      { fieldFilter: { op: 'LESS_THAN_OR_EQUAL', field: { fieldPath: 'name_lowercase' }, value: { stringValue: lower + '\\uf8ff' } } }
    ]);
    var q = seriesQuery((page - 1) * PAGE_SIZE, { where: where });
    var list = await fsRunQuery('Series', q);
    return { mangas: list.map(seriesToManga), hasNextPage: list.length < PAGE_SIZE ? false : true };
  },

  getMangaDetail: async function (mangaKey) {
    var seriesId = qp(mangaKey, 'series');
    var s = await fsGetDocument('Series/' + seriesId, SERIES_FIELDS);
    var m = seriesToManga(s);
    m.key = mangaKey;
    return m;
  },

  getChapterList: async function (mangaKey) {
    var seriesId = qp(mangaKey, 'series');
    var series = await fsGetDocument('Series/' + seriesId, ['maxFreeChapterNumber', 'maxMeteredReadingChapterNumber', 'onlyTransactional']);
    var chFields = ['alwaysFree', 'enabled', 'id', 'seriesId', 'chapterNumber', 'name', 'createdAt', 'onlyTransactional', 'type'];
    var q = {
      from: { collectionId: 'chapters' },
      select: { fields: chFields.map(function (f) { return { fieldPath: f }; }) },
      orderBy: [{ direction: 'DESCENDING', field: { fieldPath: 'chapterNumber' } }]
    };
    var list = await fsRunQuery('Series/' + seriesId + '/chapters', q);
    var isSubscribed = await getUserIsSubscribed();
    var maxFree = series.maxFreeChapterNumber || 0;
    var maxMetered = parseFloat(series.maxMeteredReadingChapterNumber) || 0;
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var ch = list[i];
      if (ch.enabled !== true) { continue; }
      var num = ch.chapterNumber;
      var isFree = ch.alwaysFree === true || (typeof num === 'number' && num <= maxFree);
      var isMetered = typeof num === 'number' && num <= maxMetered;
      var isCoin = ch.onlyTransactional === true ||
        (series.onlyTransactional === true && ch.type === 'volume' && !isFree);
      var marker = '';
      if (isCoin) { marker = ' \\uD83E\\uDE99'; }
      else if (isFree || isSubscribed) { marker = ''; }
      else if (isMetered) { marker = ' \\uD83D\\uDD52'; }
      else { marker = ' \\uD83D\\uDD12'; }
      out.push({
        key: '/read?series=' + ch.seriesId + '&chapter=' + ch.id,
        name: (ch.name || '') + marker,
        chapterNumber: typeof num === 'number' ? num : -1,
        dateUpload: ch.createdAt || 0,
        pages: 0,
        sortOrder: 0
      });
    }
    // site order is chapterNumber descending; contract wants oldest first
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var seriesId = qp(chapterKey, 'series');
    var chapterId = qp(chapterKey, 'chapter');
    var token = await getIdToken();
    var text = await $.http.post(FN + '/page/' + seriesId + '/' + chapterId, $.json.stringify({ idToken: token }), JSONH);
    var data = $.json.parse(text);
    data.sort(function (a, b) { return (a.pageNumber || 0) - (b.pageNumber || 0); });
    var out = [];
    for (var i = 0; i < data.length; i++) {
      if (data[i].uri) { out.push({ index: out.length, url: data[i].uri }); }
    }
    return out;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
