// ja/mangano — GraphQL API with anonymous Firebase auth
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) {
    return { ok: false, reason: 'multi-source ext needs bespoke engine' };
  }
  return {
    ok: true,
    config: {},
    warnings: ['anonymous Firebase token (no login); paid chapters stay locked'],
  };
}

export function generate(manifest) {
  const body = String.raw`
var LOGIN_KEY = 'AIzaSyASnOvvLWrECQKNRI0R_82droxO1QMd4O8';
var bearerToken = null;

async function getToken() {
  if (bearerToken) { return bearerToken; }
  var body = await $.http.post(
    'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=' + LOGIN_KEY,
    '{"returnSecureToken":true}',
    { 'Content-Type': 'application/json' }
  );
  var json = $.json.parse(body);
  bearerToken = json.idToken || json.id_token || '';
  return bearerToken;
}

async function gql(query, variables) {
  var token = await getToken();
  var payload = { query: query, variables: variables || {} };
  var text = await $.http.post(BASE + '/query', $.json.stringify(payload), {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token
  });
  return $.json.parse(text);
}

function imgLast(url) {
  if (!url) { return ''; }
  var parts = String(url).split('?')[0].split('/');
  return R_abs(parts[parts.length - 1]);
}

function workToManga(node) {
  return {
    key: '/works/' + node.id,
    title: node.title || node.id,
    coverUrl: node.coverImage ? imgLast(node.coverImage.url) : ''
  };
}

var searchCursor = null;

module.exports = {
  getPopularManga: async function () {
    var r = await gql('query RankingsMonthly { ranking { monthly2(first: 100) { edges { node { id title coverImage { url } } } } } }');
    var edges = (((r.data || {}).ranking || {}).monthly2 || {}).edges || [];
    var out = [];
    for (var i = 0; i < edges.length; i++) { out.push(workToManga(edges[i].node)); }
    return { mangas: out, hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    if (page === 1) { searchCursor = null; }
    var r = await gql(
      'query Search($keyword: String!, $after: String) { search(keyword: $keyword, first: 50, after: $after) { edges { cursor node { ... on Work { id title coverImage { url } } } } pageInfo { endCursor hasNextPage } } }',
      { keyword: query, after: searchCursor }
    );
    var search = ((r.data || {}).search) || {};
    var edges = search.edges || [];
    var out = [];
    for (var i = 0; i < edges.length; i++) { out.push(workToManga(edges[i].node)); }
    var pi = search.pageInfo || {};
    searchCursor = pi.endCursor || null;
    return { mangas: out, hasNextPage: !!pi.hasNextPage };
  },

  getMangaDetail: async function (mangaKey) {
    var id = String(mangaKey).split('/').pop();
    var r = await gql(
      'query MangaDetails($id: ID!) { node(id: $id) { ... on Work { id title description isCompleted coverImage { url } user { displayName } tags { title } } } }',
      { id: id }
    );
    var node = ((r.data || {}).node) || {};
    return {
      key: mangaKey,
      title: node.title || id,
      coverUrl: node.coverImage ? imgLast(node.coverImage.url) : '',
      author: node.user ? (node.user.displayName || '') : '',
      description: node.description || '',
      genre: (node.tags || []).map(function (t) { return t.title; }).join(', '),
      status: node.isCompleted === true ? 'completed' : 'ongoing'
    };
  },

  getChapterList: async function (mangaKey) {
    var id = String(mangaKey).split('/').pop();
    var r = await gql(
      'query ChapterList($id: ID!) { node(id: $id) { ... on Work { episodes(first: 1000) { edges { node { id title number publishedAt salesInfo { pagesChargedFrom } purchasedByViewer canViewerSkipPaywall } } } } } }',
      { id: id }
    );
    var node = ((r.data || {}).node) || {};
    var edges = ((node.episodes || {}).edges) || [];
    var out = [];
    for (var i = 0; i < edges.length; i++) {
      var e = edges[i].node;
      var si = e.salesInfo || null;
      var charged = si ? si.pagesChargedFrom : null;
      var isPaid = e.purchasedByViewer !== true && e.canViewerSkipPaywall !== true;
      var isLocked = isPaid && charged === 0;
      var isPreview = isPaid && charged !== 0;
      var prefix = isLocked ? '🔒 ' : (isPreview ? '🔒 (Preview) ' : '');
      out.push({
        key: '/episodes/' + e.id,
        name: prefix + (e.title || ''),
        chapterNumber: e.number !== undefined && e.number !== null ? e.number : -1,
        dateUpload: e.publishedAt ? Date.parse(e.publishedAt) : 0,
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var id = String(chapterKey).split('/').pop();
    var r = await gql(
      'query GetEpisode($id: ID!) { node(id: $id) { ... on Episode { allPagesConnection: pages(first: 2000) { edges { node { image { url } } } } } } }',
      { id: id }
    );
    var node = ((r.data || {}).node) || {};
    var edges = ((node.allPagesConnection || {}).edges) || [];
    var out = [];
    for (var i = 0; i < edges.length; i++) {
      var img = edges[i].node.image ? edges[i].node.image.url : '';
      if (img) { out.push({ index: out.length, url: imgLast(img) }); }
    }
    return out;
  },

  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`;
  return wrap(manifest, body);
}
