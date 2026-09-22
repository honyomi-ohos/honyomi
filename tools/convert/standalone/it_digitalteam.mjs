// it/digitalteam — dgtread.com custom PHP reader (bespoke)
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: ['text search disabled upstream; client-side title filter over the full series list instead'],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var HDRS = { Referer: BASE + '/' };
function parseDateIt(v) {
  var m = String(v || '').match(/(\\d{1,2})-(\\d{1,2})-(\\d{4})/);
  if (m) { return Date.UTC(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10)); }
  var h = String(v || '').match(/^\\s*(\\d{1,2})\\s*$/);
  if (h) {
    var d = new Date();
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), parseInt(h[1], 10)).getTime();
  }
  return 0;
}
async function seriesMangas(query) {
  var doc = await H_doc(BASE + '/reader/series', HDRS);
  var els = R_sel(doc, 'ul li.manga_block');
  var out = [];
  var q = (query || '').toLowerCase();
  for (var i = 0; i < els.length; i++) {
    var a = R_selFirst(els[i], '.manga_title a');
    if (!a) { continue; }
    var title = a.text().trim();
    if (q && title.toLowerCase().indexOf(q) < 0) { continue; }
    var img = R_selFirst(els[i], 'img');
    out.push({ key: R_path(a.absUrl('href')), title: title, coverUrl: img ? img.absUrl('src') : '' });
  }
  return out;
}
function infoValue(doc, label) {
  var labels = R_sel(doc, '#manga_left .info_name');
  var values = R_sel(doc, '#manga_left .info_name + *');
  for (var i = 0; i < labels.length && i < values.length; i++) {
    if (labels[i].text().indexOf(label) === 0) { return values[i].text().trim(); }
  }
  return '';
}
module.exports = {
  getPopularManga: async function () {
    return { mangas: await seriesMangas(''), hasNextPage: false };
  },

  getSearchManga: async function (page, query) {
    return { mangas: await seriesMangas(query), hasNextPage: false };
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var statusText = infoValue(doc, 'Status').toLowerCase();
    var status = '';
    if (statusText.indexOf('in corso') >= 0) { status = 'ongoing'; }
    else if (statusText.indexOf('completo') >= 0) { status = 'completed'; }
    var cover = R_selFirst(doc, '#manga_left .cover img');
    return {
      key: mangaKey,
      title: H_firstText(doc, '#manga_left .info_content'),
      coverUrl: cover ? cover.absUrl('src') : '',
      author: infoValue(doc, 'Autore'),
      artist: infoValue(doc, 'Artista'),
      description: H_firstText(doc, 'div.plot'),
      genre: infoValue(doc, 'Genere'),
      status: status
    };
  },

  getChapterList: async function (mangaKey) {
    var doc = await H_doc(R_abs(mangaKey), HDRS);
    var els = R_sel(doc, '.chapter_list ul li');
    var out = [];
    for (var i = 0; i < els.length; i++) {
      var a = R_selFirst(els[i], 'a');
      if (!a) { continue; }
      var bottom = R_selFirst(els[i], '.ch_bottom');
      var dateStr = bottom ? bottom.text().replace('Pubblicato il ', '') : '';
      out.push({
        key: R_path(a.absUrl('href')),
        name: a.text().trim(),
        chapterNumber: -1,
        dateUpload: parseDateIt(dateStr),
        pages: 0,
        sortOrder: 0
      });
    }
    out.reverse();
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },

  getPageList: async function (chapterKey) {
    var html = await H_get(R_abs(chapterKey), HDRS);
    var cp = html.indexOf('current_page=');
    if (cp < 0) { throw new Error('chapter script not found'); }
    var script = html.substring(cp, html.indexOf(';', cp));
    var m = script.match(/m='([^']*)'/);
    var ch = script.match(/ch='([^']*)'/);
    var chs = script.match(/chs='([^']*)'/);
    if (!m || !ch || !chs) { throw new Error('chapter info not found'); }
    var titleMatch = html.match(/<title>([^<]*)<\\/title>/);
    var title = titleMatch ? titleMatch[1].trim() : '';
    var external = /jq_rext\\.js/.test(html);

    var params = 'info[manga]=' + encodeURIComponent(m[1]) +
      '&info[chapter]=' + encodeURIComponent(ch[1]) +
      '&info[ch_sub]=' + encodeURIComponent(chs[1]) +
      '&info[title]=' + encodeURIComponent(title);
    if (external) { params += '&info[external]=1'; }
    var raw = await $.http.post(BASE + '/reader/c_i', params, {
      'Content-Type': 'application/x-www-form-urlencoded',
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': R_abs(chapterKey)
    });
    var cleaned = String(raw).replace(/\\\\/g, '');
    if (cleaned.charAt(0) === '"' && cleaned.charAt(cleaned.length - 1) === '"') {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    var json = JSON.parse(cleaned);
    var imageDatas = json[0] || [];
    var pages = [];
    if (external) {
      var imageBases = json[1] || [];
      for (var i = 0; i < imageDatas.length && i < imageBases.length; i++) {
        pages.push({ index: i, url: imageBases[i] + imageDatas[i].name + (imageDatas[i].ex || '') });
      }
    } else {
      var suffixes = json[1] || [];
      var base = json[2] || '';
      for (var k = 0; k < imageDatas.length; k++) {
        pages.push({ index: k, url: BASE + '/reader' + base + imageDatas[k].name + (suffixes[k] || '') + (imageDatas[k].ex || '') });
      }
    }
    return pages;
  },

  imageHeaders: function () { return { Referer: BASE }; }
};
`);
}
