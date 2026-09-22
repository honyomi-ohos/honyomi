// en/buttsmithy — InCase comics; Alfie chapters exposed as separate manga from buttsmithy.com
import { wrap } from './_emit.mjs';

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: true,
    config: {},
    warnings: [
      'chapter date for non-Alfie comics not persisted (upstream used SharedPreferences timestamps)',
      'thumbnail text-interceptor placeholders dropped',
    ],
  };
}

export function generate(manifest) {
  return wrap(manifest, `
var ALFIE = 'https://buttsmithy.com';
var INC = 'InCase';
function chapSlug(t) { return t === 'chapter 1' ? 'chapter-1v2' : t.replace(/ /g, '-').replace(/\\./g, '-'); }
module.exports = {
  getPopularManga: async function (page) {
    var mangas = [];
    var homeDoc = await H_doc(BASE + '/', { Referer: BASE + '/' });
    var alfieDoc = await H_doc(ALFIE + '/', { Referer: ALFIE + '/' });
    var opts = R_sel(alfieDoc, '#chapter option.level-0');
    for (var i = 0; i < opts.length; i++) {
      var t = opts[i].text().toLowerCase();
      mangas.push({ key: ALFIE + '/archives/chapter/' + chapSlug(t), title: 'Alfie - ' + opts[i].text(), coverUrl: '' });
    }
    var menuSel = ['#menu-item-331', '#menu-item-38'];
    for (var m = 0; m < menuSel.length; m++) {
      var links = R_sel(homeDoc, menuSel[m] + ' .menu-item-type-custom a[href]');
      for (var l = 0; l < links.length; l++) {
        var title = links[l].text();
        if (title.toLowerCase().indexOf('alfie') >= 0) { continue; }
        var href = links[l].absUrl('href') || links[l].attr('href');
        if (href) { mangas.push({ key: href, title: title, coverUrl: '' }); }
      }
    }
    return { mangas: mangas, hasNextPage: false };
  },
  getSearchManga: async function (page, query) {
    return { mangas: [], hasNextPage: false };
  },
  getMangaDetail: async function (key) {
    if (key.indexOf(ALFIE) === 0) {
      var doc = await H_doc(ALFIE + '/', {});
      var rEl = R_selFirst(doc, '.comic-chapter a');
      var recent = rEl ? rEl.text().toLowerCase() : '';
      var chapTitle = key.substring(key.lastIndexOf('/') + 1).replace(/-/g, ' ').toLowerCase();
      return {
        key: key, title: 'Alfie - ' + chapTitle, coverUrl: '', author: INC,
        description: '', genre: 'fantasy, NSFW', status: chapTitle === recent ? '' : 'completed',
      };
    }
    var doc2 = await H_doc(key.indexOf('http') === 0 ? key : R_abs(key), {});
    var img = R_selFirst(doc2, '#comic img');
    return { key: key, title: img ? img.attr('alt') : '', coverUrl: '', author: INC, description: '', genre: 'NSFW', status: 'completed' };
  },
  getChapterList: async function (key) {
    var out = [];
    if (key.indexOf(ALFIE) === 0) {
      var url = key;
      var lastNr = 0;
      while (url) {
        var doc = await H_doc(url, { Referer: ALFIE + '/' });
        var posts = R_sel(doc, 'article.has-post-thumbnail .post-content');
        for (var i = 0; i < posts.length; i++) {
          var a = R_selFirst(posts[i], '.post-info .post-title a');
          if (!a) { continue; }
          var href = a.absUrl('href') || a.attr('href');
          var title = a.text();
          var nr = /^p\\d+$/.test(title) ? parseFloat(title.substring(1)) : (i + lastNr);
          var ds = R_selFirst(posts[i], '.post-info .post-date');
          var ts = R_selFirst(posts[i], '.post-info .post-time');
          var dv = Date.parse(((ts ? ts.text() + ' ' : '') + (ds ? ds.text() : '')).trim());
          out.push({ key: href, name: title, chapterNumber: nr, dateUpload: isNaN(dv) ? 0 : dv, pages: 0, sortOrder: 0 });
        }
        lastNr += posts.length;
        var next = R_selFirst(doc, '.paginav-next a');
        var nh = next ? (next.absUrl('href') || next.attr('href')) : '';
        url = nh && nh !== url ? nh : null;
      }
    } else {
      var url2 = key.indexOf('http') === 0 ? key : R_abs(key);
      var nr2 = 0;
      while (url2) {
        var doc2 = await H_doc(url2, { Referer: BASE + '/' });
        var img = R_selFirst(doc2, '#comic img');
        out.push({ key: url2, name: img ? img.attr('alt') : ('Page ' + (nr2 + 1)), chapterNumber: nr2, dateUpload: 0, pages: 0, sortOrder: 0 });
        nr2++;
        var n2 = R_selFirst(doc2, '.comic-nav-next');
        var h2 = n2 ? (n2.absUrl('href') || n2.attr('href')) : '';
        url2 = h2 && h2 !== url2 ? h2 : null;
      }
    }
    for (var j = 0; j < out.length; j++) { out[j].sortOrder = j; }
    return out;
  },
  getPageList: async function (chapterKey) {
    var doc = await H_doc(chapterKey.indexOf('http') === 0 ? chapterKey : R_abs(chapterKey), { Referer: BASE + '/' });
    var img = R_selFirst(doc, '#comic img');
    var src = img ? (img.attr('src') || '') : '';
    return src ? [{ index: 0, url: R_abs(src) }] : [];
  },
  imageHeaders: function () { return { Referer: BASE + '/' }; }
};
`);
}
