// MCCMS theme engine (zh: manhuawu, miaoqu, sixmh) — 漫城CMS family (MCCMSWeb HTML flavor)
export const runtime = 'wp';

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  let variant = 'web';
  if (/#mangawrap/.test(kt)) variant = 'miaoqu';
  else if (/cy_list_mh/.test(kt)) variant = 'sixmh';
  const config = { variant };
  if (variant === 'miaoqu') {
    warnings.push('miaoqu XOR image decode ported; search may fail if server 404s');
  }
  if (variant === 'sixmh') {
    warnings.push('sixmh AES params decode ported (fixed site key)');
  }
  warnings.push('captcha (验证码) interstitial not supported; retry if search returns empty');
  return { ok: true, config, warnings };
}

export function generate(manifest, config) {
  const cfg = JSON.stringify(config, null, 2);
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mccms)
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp'
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${cfg};

function stripPrefix(p) {
  return String(p).replace(/^\\/index\\.php/, '');
}

function mobileBase() {
  return BASE.replace('//www.', '//m.');
}

function parseListing(doc, page) {
  var out = [];
  if (CFG.variant === 'miaoqu') {
    var wrap = R_selFirst(doc, '#mangawrap');
    if (!wrap) { return { mangas: [], hasNextPage: false }; }
    var items = R_sel(wrap, ':scope > *');
    for (var i = 0; i < items.length; i++) {
      var el = items[i];
      var a = R_selFirst(el, 'a');
      if (!a) { continue; }
      var style = a.attr('style') || '';
      var m = style.match(/background:\\s*url\\(([^)]+)\\)/);
      var tEl = R_selFirst(el, '.manga-name');
      var auEl = R_selFirst(el, '.manga-author');
      out.push({
        key: stripPrefix(a.attr('href')),
        title: tEl ? tEl.text() : '',
        coverUrl: m ? m[1] : ''
      });
      if (auEl) { out[out.length - 1].authorHint = auEl.text(); }
    }
    var hasNext = false;
    var next = R_selFirst(doc, '#next');
    if (next) {
      var seg = (next.attr('href') || '').split('/').pop();
      hasNext = String(seg) !== String(page);
    }
    return { mangas: out, hasNextPage: hasNext };
  }
  if (CFG.variant === 'sixmh') {
    var items2 = R_sel(doc, 'div.cy_list_mh ul');
    for (var j = 0; j < items2.length; j++) {
      var link = R_selFirst(items2[j], 'li.title > a');
      if (!link) { continue; }
      var img2 = R_selFirst(items2[j], 'img');
      out.push({
        key: stripPrefix(link.absUrl('href') || link.attr('href')),
        title: link.text(),
        coverUrl: img2 ? (img2.absUrl('src') || img2.attr('src')) : ''
      });
    }
  } else {
    var items3 = R_sel(doc, '.common-comic-item');
    for (var k = 0; k < items3.length; k++) {
      var tEl3 = R_selFirst(items3[k], '.comic__title a');
      if (!tEl3) { continue; }
      var img3 = R_selFirst(items3[k], 'img');
      out.push({
        key: stripPrefix(tEl3.attr('href')),
        title: R_ownText(tEl3),
        coverUrl: img3 ? (img3.attr('data-original') || R_img(img3)) : ''
      });
    }
  }
  var hasNext2 = false;
  var pag = R_selFirst(doc, '#Pagination, .NewPages');
  if (pag) {
    var btns = R_sel(pag, 'a');
    if (btns.length >= 2) {
      hasNext2 = btns[btns.length - 1].attr('href') !== btns[btns.length - 2].attr('href');
    }
  }
  return { mangas: out, hasNextPage: hasNext2 };
}

async function listManga(path, page, query) {
  var url;
  if (query) {
    url = BASE + '/search/' + encodeURIComponent(query) + '/' + page;
  } else {
    url = BASE + path + page;
  }
  var text = await $.http.get(url);
  var doc = $.html.parse(text);
  if (R_selFirst(doc, '#code-div')) {
    return { mangas: [], hasNextPage: false };
  }
  return parseListing(doc, page);
}

function parseChapters(doc, reverse) {
  var sel = CFG.variant === 'miaoqu' ? 'ul.list > li'
    : CFG.variant === 'sixmh' ? 'ul#mh-chapter-list-ol-0 li.chapter__item'
    : '.chapter__list-box > li';
  var els = R_sel(doc, sel);
  var out = [];
  for (var i = 0; i < els.length; i++) {
    var link = R_selFirst(els[i], 'a');
    if (!link) { continue; }
    var href = link.absUrl('href') || link.attr('href');
    if (!href) { continue; }
    out.push({
      key: stripPrefix(href),
      name: link.text(),
      chapterNumber: -1,
      dateUpload: 0,
      pages: 0,
      sortOrder: 0
    });
  }
  if (reverse) { out.reverse(); }
  for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
  return out;
}

async function sixDecode(b64) {
  var subtle = crypto.subtle;
  var raw = atob(b64);
  var iv = new Uint8Array(16);
  var ct = new Uint8Array(Math.max(0, raw.length - 16));
  for (var i = 0; i < 16 && i < raw.length; i++) { iv[i] = raw.charCodeAt(i); }
  for (var j = 16; j < raw.length; j++) { ct[j - 16] = raw.charCodeAt(j); }
  var k = await subtle.importKey('raw', new TextEncoder().encode('9S8$' + 'vJnU2ANeSRoF'), { name: 'AES-CBC' }, false, ['decrypt']);
  var buf = await subtle.decrypt({ name: 'AES-CBC', iv: iv }, k, ct);
  return new TextDecoder('utf-8').decode(buf);
}

function miaoDecode(dataB64, cid) {
  var keys = ['8-bXd9iN', '8-RXyjry', '8-oYvwVy', '8-4ZY57U', '8-mbJpU7',
    '8-6MM2Ei', '8-54TiQr', '8-Ph5xx9', '8-bYgePR', '8-Z9A3bW'];
  var key = keys[cid % 10];
  var bytes = atob(dataB64);
  var xored = '';
  for (var i = 0; i < bytes.length; i++) {
    xored += String.fromCharCode(bytes.charCodeAt(i) ^ key.charCodeAt(i & 7));
  }
  return atob(xored);
}

module.exports = {
  getPopularManga: async function (page) {
    return listManga('/category/order/hits/page/', page, '');
  },

  getSearchManga: async function (page, query) {
    return listManga('/category/order/addtime/page/', page, query);
  },

  getMangaDetail: async function (mangaKey) {
    if (CFG.variant === 'miaoqu') {
      var mtext = await $.http.get(mobileBase() + mangaKey);
      var mdoc = $.html.parse(mtext);
      var desc = '';
      var textEl = R_selFirst(mdoc, '.text');
      if (textEl) { desc = textEl.text(); }
      var box = R_selFirst(mdoc, '.infobox');
      var title = '';
      var cover = '';
      var author = '';
      var genre = '';
      if (box) {
        var tEl = R_selFirst(box, '.title');
        if (tEl) { title = tEl.text(); }
        var imgEl = R_selFirst(box, 'img');
        if (imgEl) { cover = imgEl.attr('src') || ''; }
        var tags = R_sel(box, '.tage');
        for (var i = 0; i < tags.length; i++) {
          var text = tags[i].text();
          if (text.indexOf('作者：') === 0) { author = text.substring(3).trim(); }
          else if (text.indexOf('类型：') === 0) {
            var as = R_sel(tags[i], 'a');
            var gs = [];
            for (var g = 0; g < as.length; g++) { gs.push(as[g].text()); }
            genre = gs.join(', ');
          } else if (text.indexOf('更新') === 0) { desc = text + '\\n\\n' + desc; }
        }
      }
      return {
        key: mangaKey, title: title, coverUrl: cover, author: author,
        description: desc, genre: genre, status: ''
      };
    }
    if (CFG.variant === 'sixmh') {
      var stext = await $.http.get(BASE + mangaKey);
      var sdoc = $.html.parse(stext);
      var el = R_selFirst(sdoc, 'div.cy_info');
      var title2 = '';
      var cover2 = '';
      var desc2 = '';
      var author2 = '';
      var genre2 = '';
      var status2 = '';
      if (el) {
        var t2 = R_selFirst(el, 'div.cy_title');
        if (t2) { title2 = t2.text(); }
        var c2 = R_selFirst(el, 'div.cy_info_cover > a > img.pic');
        if (c2) { cover2 = c2.absUrl('src') || c2.attr('src'); }
        var d2 = R_selFirst(el, 'div.cy_desc #comic-description');
        if (d2) { desc2 = d2.text(); }
        var infos = R_sel(el, 'div.cy_xinxi');
        if (infos.length > 0) {
          var au = R_selFirst(infos[0], 'span:first-child > a');
          if (au) { author2 = au.text(); }
          var st = R_selFirst(infos[0], 'span:nth-child(2)');
          if (st) {
            var stv = st.text();
            status2 = stv.indexOf('连载') >= 0 ? 'ongoing' : (stv.indexOf('完结') >= 0 ? 'completed' : '');
          }
        }
        if (infos.length > 1) {
          var gas = R_sel(infos[1], 'span:first-child > a');
          var gs2 = [];
          for (var q = 0; q < gas.length; q++) { gs2.push(gas[q].text()); }
          genre2 = gs2.join(', ');
        }
      }
      return {
        key: mangaKey, title: title2, coverUrl: cover2, author: author2,
        description: desc2, genre: genre2, status: status2
      };
    }
    var text3 = await $.http.get(BASE + mangaKey);
    var doc3 = $.html.parse(text3);
    var box3 = R_selFirst(doc3, '.de-info__box');
    var out = { key: mangaKey, title: '', coverUrl: '', author: '', description: '', genre: '', status: '' };
    if (box3) {
      var t3 = R_selFirst(box3, '.comic-title');
      if (t3) { out.title = R_ownText(t3); }
      var img3 = R_selFirst(box3, 'img');
      if (img3) { out.coverUrl = img3.attr('src') || R_img(img3); }
      var au3 = R_selFirst(box3, '.name');
      if (au3) { out.author = au3.text(); }
      var g3 = R_sel(box3, '.comic-status a');
      var gs3 = [];
      for (var w = 0; w < g3.length; w++) { gs3.push(R_ownText(g3[w])); }
      out.genre = gs3.join(', ');
      var d3 = R_selFirst(box3, '.intro-total');
      if (d3) { out.description = d3.text(); }
    }
    return out;
  },

  getChapterList: async function (mangaKey) {
    var url = CFG.variant === 'miaoqu' ? mobileBase() + mangaKey : BASE + mangaKey;
    var text = await $.http.get(url);
    var doc = $.html.parse(text);
    return parseChapters(doc, CFG.variant !== 'sixmh');
  },

  getPageList: async function (chapterKey) {
    var url = BASE + chapterKey;
    var text = await $.http.get(url);
    if (CFG.variant === 'sixmh') {
      var m = text.match(/params\\s*=\\s*'([A-Za-z0-9+\\/=]+)'/);
      if (!m) { return []; }
      var json = await sixDecode(m[1]);
      var images = JSON.parse(json).images || [];
      var pages = [];
      for (var i = 0; i < images.length; i++) {
        pages.push({ index: i, url: images[i] });
      }
      return pages;
    }
    if (CFG.variant === 'miaoqu') {
      var dm = text.indexOf("var DATA='");
      if (dm < 0) { return []; }
      var start = dm + 10;
      var end = text.indexOf("'", start);
      var dataB64 = text.substring(start, end);
      var cid = parseInt(String(chapterKey).split('/').pop().replace(/\\.html$/, ''), 10);
      var json2 = miaoDecode(dataB64, cid);
      var list = JSON.parse(json2);
      var pages2 = [];
      for (var j = 0; j < list.length; j++) {
        pages2.push({ index: j, url: list[j].url });
      }
      return pages2;
    }
    var doc = $.html.parse(text);
    var els = R_sel(doc, 'img[data-original]');
    var pages3 = [];
    for (var k = 0; k < els.length; k++) {
      var u = els[k].attr('data-original');
      if (u) { pages3.push({ index: pages3.length, url: u }); }
    }
    return pages3;
  },

  imageHeaders: function () {
    return {};
  }
};
`;
}
