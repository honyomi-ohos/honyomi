// UzayManga theme engine (SvelteKit sites: uzaymanga, serilmanga, tempesmanga, ...)
// All data comes from SvelteKit __data.json endpoints (devalue-index navigation).
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { cdnUrl: '' };

  const m = kt.match(/cdnUrl\s*(?::\s*String\??\s*)?=\s*"([^"]+)"/);
  if (m) { config.cdnUrl = m[1]; }

  if (/rateLimit\(/.test(kt)) {
    warnings.push('source uses rate limiting; requests may be slow');
  }
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: uzaymanga)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

// ---------------- uzaymanga engine ----------------
function baseImg() {
  return (CFG.cdnUrl || BASE).replace(/\\/+$/, '');
}

function img(path) {
  if (!path) { return ''; }
  if (path.indexOf('http') === 0) { return path; }
  return baseImg() + '/' + path.replace(/^\\/+/, '');
}

// SvelteKit devalue navigation over the data array
function SvelteData(array) {
  this.a = array;
}
SvelteData.prototype.get = function (i) {
  var v = this.a[i];
  if (v === undefined || v === null || typeof v !== 'object') { return null; }
  return v;
};
SvelteData.prototype.getObject = function (i) {
  var v = this.get(i);
  return v && !Array.isArray(v) ? v : null;
};
SvelteData.prototype.getArray = function (i) {
  var v = this.get(i);
  return v && Array.isArray(v) ? v : null;
};
SvelteData.prototype.getString = function (i) {
  var v = this.a[i];
  if (v === undefined || v === null || typeof v === 'object') { return null; }
  return String(v);
};
SvelteData.prototype.getInt = function (i) {
  var v = this.a[i];
  if (typeof v !== 'number' || Math.floor(v) !== v) { return null; }
  return v;
};
SvelteData.prototype.resolveIndex = function (node, key) {
  var v = node ? node[key] : undefined;
  return (typeof v === 'number' && Math.floor(v) === v) ? v : null;
};
SvelteData.prototype.resolveObject = function (node, key) {
  var i = this.resolveIndex(node, key);
  return i === null ? null : this.getObject(i);
};
SvelteData.prototype.resolveArray = function (node, key) {
  var i = this.resolveIndex(node, key);
  return i === null ? null : this.getArray(i);
};
SvelteData.prototype.resolveString = function (node, key) {
  var i = this.resolveIndex(node, key);
  return i === null ? null : this.getString(i);
};
SvelteData.prototype.resolveInt = function (node, key) {
  var i = this.resolveIndex(node, key);
  return i === null ? null : this.getInt(i);
};
SvelteData.prototype.resolveDate = function (node, key) {
  var arr = this.resolveArray(node, key);
  if (!arr || arr.length < 2) { return 0; }
  var s = arr[1];
  if (s === null || typeof s === 'object') { return 0; }
  var t = Date.parse(String(s));
  return isNaN(t) ? 0 : t;
};

function parseData(text) {
  var json = JSON.parse(text);
  var nodes = json.nodes || [];
  var data = null;
  for (var i = 0; i < nodes.length; i++) {
    if (nodes[i].type === 'data') { data = nodes[i].data; }
  }
  return data ? new SvelteData(data) : null;
}

function seriesRoot(svelte) {
  if (!svelte) { return null; }
  var root = svelte.getObject(0);
  if (!root) { return null; }
  var seriesIdx = svelte.resolveIndex(root, 'series');
  if (seriesIdx === null) { return null; }
  return svelte.getObject(seriesIdx);
}

async function fetchSvelte(url) {
  var text = await $.http.get(url, { Referer: BASE + '/' });
  return parseData(text);
}

module.exports = {
  getPopularManga: async function (page) {
    var url = BASE + '/manga/__data.json?sort=popular&page=' + page + '&x-sveltekit-invalidated=001';
    var svelte = await fetchSvelte(url);
    var root = svelte ? svelte.getObject(0) : null;
    if (!root) { return { mangas: [], hasNextPage: false }; }
    var seriesArr = svelte.resolveArray(root, 'series');
    var out = [];
    if (seriesArr) {
      for (var i = 0; i < seriesArr.length; i++) {
        var mObj = svelte.getObject(seriesArr[i]);
        if (!mObj) { continue; }
        var name = svelte.resolveString(mObj, 'name');
        var slug = svelte.resolveString(mObj, 'slug');
        if (!name || !slug) { continue; }
        out.push({
          key: '/manga/' + slug,
          title: name,
          coverUrl: img(svelte.resolveString(mObj, 'image') || '')
        });
      }
    }
    var cur = svelte.resolveInt(root, 'currentPage') || 1;
    var total = svelte.resolveInt(root, 'totalPages') || 1;
    return { mangas: out, hasNextPage: cur < total };
  },

  getSearchManga: async function (page, query) {
    var url = BASE + '/manga/__data.json?page=' + page + '&x-sveltekit-invalidated=001';
    if (query) {
      url += '&search=' + encodeURIComponent(query);
    } else {
      url += '&sort=new';
    }
    var svelte = await fetchSvelte(url);
    var root = svelte ? svelte.getObject(0) : null;
    if (!root) { return { mangas: [], hasNextPage: false }; }
    var seriesArr = svelte.resolveArray(root, 'series');
    var out = [];
    if (seriesArr) {
      for (var i = 0; i < seriesArr.length; i++) {
        var mObj = svelte.getObject(seriesArr[i]);
        if (!mObj) { continue; }
        var name = svelte.resolveString(mObj, 'name');
        var slug = svelte.resolveString(mObj, 'slug');
        if (!name || !slug) { continue; }
        out.push({
          key: '/manga/' + slug,
          title: name,
          coverUrl: img(svelte.resolveString(mObj, 'image') || '')
        });
      }
    }
    var cur = svelte.resolveInt(root, 'currentPage') || 1;
    var total = svelte.resolveInt(root, 'totalPages') || 1;
    return { mangas: out, hasNextPage: cur < total };
  },

  getMangaDetail: async function (mangaKey) {
    var url = R_abs(mangaKey).replace(/\\/+$/, '') + '/__data.json?x-sveltekit-invalidated=001';
    var svelte = await fetchSvelte(url);
    var series = seriesRoot(svelte);
    if (!series) {
      return { key: mangaKey, title: '', coverUrl: '', author: '', description: '', genre: '', status: '' };
    }
    var status = svelte.resolveInt(series, 'status');
    var statusStr = '';
    if (status === 1) { statusStr = 'ongoing'; }
    else if (status === 2) { statusStr = 'completed'; }
    else if (status === 3) { statusStr = 'hiatus'; }
    var genres = [];
    var cats = svelte.resolveArray(series, 'resolvedCategories');
    if (cats) {
      for (var i = 0; i < cats.length; i++) {
        var cat = svelte.getObject(cats[i]);
        var t = cat ? svelte.resolveString(cat, 'title') : null;
        if (t) { genres.push(t); }
      }
    }
    return {
      key: mangaKey,
      title: svelte.resolveString(series, 'name') || '',
      coverUrl: img(svelte.resolveString(series, 'image') || ''),
      author: '',
      description: svelte.resolveString(series, 'description') || '',
      genre: genres.join(', '),
      status: statusStr
    };
  },

  getChapterList: async function (mangaKey) {
    var url = R_abs(mangaKey).replace(/\\/+$/, '') + '/__data.json?x-sveltekit-invalidated=001';
    var svelte = await fetchSvelte(url);
    var series = seriesRoot(svelte);
    if (!series) { return []; }
    var seriesSlug = svelte.resolveString(series, 'slug');
    if (!seriesSlug) { return []; }
    var chaptersArr = svelte.resolveArray(series, 'SeriesEpisode');
    var out = [];
    if (chaptersArr) {
      for (var i = 0; i < chaptersArr.length; i++) {
        var ch = svelte.getObject(chaptersArr[i]);
        if (!ch) { continue; }
        var slug = svelte.resolveString(ch, 'slug');
        if (!slug) { continue; }
        var chapName = svelte.resolveString(ch, 'name');
        var chapOrder = svelte.resolveString(ch, 'order');
        if (chapOrder) { chapOrder = chapOrder.replace(/\\.0$/, ''); }
        var name = '';
        if (chapOrder) { name += 'B\\u00F6l\\u00FCm ' + chapOrder; }
        if (chapName && chapName !== chapOrder) {
          name += (name ? ' - ' : '') + chapName;
        }
        if (!name) { name = 'B\\u00F6l\\u00FCm'; }
        var orderNum = parseFloat(chapOrder);
        out.push({
          key: '/manga/' + seriesSlug + '/' + slug,
          name: name,
          chapterNumber: isNaN(orderNum) ? -1 : orderNum,
          dateUpload: svelte.resolveDate(ch, 'createdDate'),
          pages: 0,
          sortOrder: 0
        });
      }
    }
    // API returns newest first; normalize to oldest-first
    out.reverse();
    for (var c = 0; c < out.length; c++) { out[c].sortOrder = c; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var url = R_abs(chapterKey).replace(/\\/+$/, '') + '/__data.json?x-sveltekit-invalidated=001';
    var svelte = await fetchSvelte(url);
    var root = svelte ? svelte.getObject(0) : null;
    if (!root) { return []; }
    var epIdx = svelte.resolveIndex(root, 'episode');
    if (epIdx === null) { return []; }
    var episode = svelte.getObject(epIdx);
    if (!episode) { return []; }
    var images = svelte.resolveArray(episode, 'images');
    var pages = [];
    if (images) {
      for (var i = 0; i < images.length; i++) {
        var p = svelte.getString(images[i]);
        if (p) { pages.push({ index: pages.length, url: img(p) }); }
      }
    }
    return pages;
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
}
