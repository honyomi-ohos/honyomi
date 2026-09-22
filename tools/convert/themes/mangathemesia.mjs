// MangaThemesia theme engine (covers MangaThemesia + MangaThemesiaAlt, formerly WPMangaStream/WPMangaReader)
// 生成的 main.js 依赖 App 共享运行时 plugin_runtime_wp.js（R_* 帮助函数）
export const runtime = 'wp';

// ---------- month names for datePattern parsing (locale-aware, like the Kotlin base) ----------
const MONTHS = {
  en: {
    full: ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'],
    short: ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'],
  },
  id: {
    full: ['januari', 'februari', 'maret', 'april', 'mei', 'juni', 'juli', 'agustus', 'september', 'oktober', 'november', 'desember'],
    short: ['jan', 'feb', 'mar', 'apr', 'mei', 'jun', 'jul', 'agu', 'sep', 'okt', 'nov', 'des'],
  },
  fr: {
    full: ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'],
    short: ['janv', 'févr', 'mars', 'avr', 'mai', 'juin', 'juil', 'août', 'sept', 'oct', 'nov', 'déc'],
  },
  es: {
    full: ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'],
    short: ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'],
  },
  pt: {
    full: ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'],
    short: ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'],
  },
  tr: {
    full: ['ocak', 'şubat', 'mart', 'nisan', 'mayıs', 'haziran', 'temmuz', 'ağustos', 'eylül', 'ekim', 'kasım', 'aralık'],
    short: ['oca', 'şub', 'mar', 'nis', 'may', 'haz', 'tem', 'ağu', 'eyl', 'eki', 'kas', 'ara'],
  },
  ar: {
    full: ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'],
    short: [],
  },
  th: {
    full: ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'],
    short: ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'],
  },
  cs: {
    full: ['leden', 'únor', 'březen', 'duben', 'květen', 'červen', 'červenec', 'srpen', 'září', 'říjen', 'listopad', 'prosinec'],
    short: ['led', 'úno', 'bře', 'dub', 'kvě', 'čvn', 'čvc', 'srp', 'zář', 'říj', 'lis', 'pro'],
    gen: ['ledna', 'února', 'března', 'dubna', 'května', 'června', 'července', 'srpna', 'září', 'října', 'listopadu', 'prosince'],
  },
  it: {
    full: ['gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'],
    short: ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'],
  },
};

// ---------- default selectors expanded from the Kotlin base class ----------
function expand(pattern, words) {
  return words.map((w) => pattern.split('%s').join(w)).join(', ');
}

const ARTIST_WORDS = ['artist', 'Artiste', 'Artista', 'الرسام', 'الناشر', 'İllüstratör', 'Çizer', 'Sanatçı'];
const AUTHOR_WORDS = ['Author', 'Auteur', 'autor', 'المؤلف', 'Mangaka', 'seniman', 'Pengarang', 'Yazar'];
const TYPE_WORDS = ['type', 'ประเภท', 'النوع', 'tipe', 'Türü'];
const STATUS_WORDS = ['status', 'Statut', 'Durum', '連載状況', 'Estado', 'الحالة', 'حالة العمل', 'สถานะ', 'stato', 'Statüsü'];

const DEFAULTS = {
  mangaUrlDirectory: '/manga',
  datePattern: 'MMMM d, yyyy',
  searchSelector: '.utao .uta .imgu, .listupd .bs .bsx, .listo .bs .bsx',
  searchNextPageSelector: 'div.pagination .next, div.hpage .r',
  searchTitleSelector: '',
  seriesDetailsSelector: 'div.bigcontent, div.animefull, div.main-info, div.postbody',
  seriesTitleSelector: '.entry-title, .ts-breadcrumb li:last-child span',
  seriesAuthorSelector: expand('.infotable tr:contains(%s) td:last-child, .tsinfo .imptdt:contains(%s) i, .fmed b:contains(%s)+span, span:contains(%s)', AUTHOR_WORDS),
  seriesArtistSelector: expand('.infotable tr:contains(%s) td:last-child, .tsinfo .imptdt:contains(%s) i, .fmed b:contains(%s)+span, span:contains(%s)', ARTIST_WORDS),
  seriesDescriptionSelector: '.desc, .entry-content[itemprop=description]',
  seriesAltNameSelector: '.alternative, .wd-full:contains(alt) span, .alter, .seriestualt, ' +
    expand('.infotable tr:contains(%s) td:last-child', ['Alternative', 'Alternatif', 'الأسماء الثانوية']),
  seriesGenreSelector: 'div.gnr a, .mgen a, .seriestugenre a, span:contains(genre), span:contains(التصنيف)',
  seriesTypeSelector: expand('.infotable tr:contains(%s) td:last-child, .tsinfo .imptdt:contains(%s) i, .tsinfo .imptdt:contains(%s) a, .fmed b:contains(%s)+span, span:contains(%s) a', TYPE_WORDS) + ', a[href*=type\\=]',
  seriesStatusSelector: expand('.infotable tr:contains(%s) td:last-child, .tsinfo .imptdt:contains(%s) i, .fmed b:contains(%s)+span span:contains(%s)', STATUS_WORDS),
  seriesThumbnailSelector: '.infomanga > div[itemprop=image] img, .thumb img',
  altNamePrefix: 'Alternative Names',
  chapterListSelector: 'div.bxcl li, div.cl li, #chapterlist li, ul li:has(div.chbox):has(div.eph-num)',
  chapterNameSelector: '.lch a, .chapternum',
  chapterDateSelector: '.chapterdate',
  lockedChapterSelector: '',
  pageSelector: 'div#readerarea img',
};

// ---------- Kotlin override extraction ----------
function strOverride(kt, name) {
  const head = `(?:override|open)\\s+(?:open\\s+)?(?:val|fun)\\s+${name}\\s*(?:\\(\\s*\\))?\\s*(?::\\s*String\\s*\\??\\s*)?=\\s*`;
  let m = kt.match(new RegExp(head + '"""([\\s\\S]*?)"""'));
  if (m) return m[1];
  m = kt.match(new RegExp(head + '"((?:[^"\\\\]|\\\\.)*)"'));
  if (m) return m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  return undefined;
}

// text following an override fun declaration (for style classification)
function overrideBody(kt, name) {
  const m = kt.match(new RegExp(`override\\s+fun\\s+${name}\\s*\\([^)]*\\)[^{]*`));
  if (!m) return '';
  const rest = kt.slice(m.index + m[0].length);
  const stop = rest.search(/\n\s{0,4}(override|private|protected|companion|open |class |inner )/);
  return stop >= 0 ? rest.slice(0, stop) : rest.slice(0, 800);
}

export function extract(ctx) {
  const kt = ctx.ktText;
  const warnings = [];
  const config = { ...DEFAULTS };

  const lang0 = (ctx.gradle.sources[0]?.lang || '').trim();
  const lang = (lang0.split('-')[0] || 'en').toLowerCase();
  config.lang = (lang && lang !== 'all') ? lang : 'en';

  // base class variant
  config.isAlt = /:\s*MangaThemesiaAlt/.test(kt);

  // simple string overrides
  const aliases = [
    ['mangaUrlDirectory', 'mangaUrlDirectory'],
    ['datePattern', 'datePattern'],
    ['searchMangaSelector', 'searchSelector'],
    ['searchMangaNextPageSelector', 'searchNextPageSelector'],
    ['searchTitleSelector', 'searchTitleSelector'],
    ['seriesDetailsSelector', 'seriesDetailsSelector'],
    ['seriesTitleSelector', 'seriesTitleSelector'],
    ['seriesAuthorSelector', 'seriesAuthorSelector'],
    ['seriesArtistSelector', 'seriesArtistSelector'],
    ['seriesDescriptionSelector', 'seriesDescriptionSelector'],
    ['seriesAltNameSelector', 'seriesAltNameSelector'],
    ['seriesGenreSelector', 'seriesGenreSelector'],
    ['seriesTypeSelector', 'seriesTypeSelector'],
    ['seriesStatusSelector', 'seriesStatusSelector'],
    ['seriesThumbnailSelector', 'seriesThumbnailSelector'],
    ['altNamePrefix', 'altNamePrefix'],
    ['pageSelector', 'pageSelector'],
  ];
  for (const [ktName, cfgName] of aliases) {
    const v = strOverride(kt, ktName);
    if (v !== undefined) config[cfgName] = v;
  }

  // search URL style classification
  config.searchStyle = 'default';
  config.popularOrder = 'popular';
  const suBody = overrideBody(kt, 'searchMangaUrl');
  if (suBody) {
    if (/advanced-search/.test(suBody)) config.searchStyle = 'advancedsearch';
    else if (/addPathSegment\("title"\)/.test(suBody)) config.searchStyle = 'titlepath';
    else if (/addPathSegment\("page"\)|\$baseUrl\/page\/\$page/.test(suBody)) config.searchStyle = 'wpsearch';
    else if (/addPathSegment\(mangaUrlDirectory/.test(suBody)) config.searchStyle = 'dirsparam';
    else if (/"buscar"/.test(suBody)) config.searchStyle = 'starlight';
    else if (/"cari"/.test(suBody)) config.searchStyle = 'mangacan';
    else if (/addQueryParameter\("s",/.test(suBody)) config.searchStyle = 'sparam';
  }
  const pm = kt.match(/popularFilter[\s\S]{0,160}?OrderByFilter\(([^)]*)\)/);
  if (pm) {
    const strs = (pm[1].match(/"((?:[^"\\]|\\.)*)"/g) || []).filter((s) => s.length > 2).map((s) => s.slice(1, -1));
    if (strs.length) config.popularOrder = strs[strs.length - 1];
  }

  // chapter list selector (direct string, block with val base, or paid-chapter helper)
  const clDirect = strOverride(kt, 'chapterListSelector');
  if (clDirect !== undefined) {
    config.chapterListSelector = clDirect;
  } else {
    const bm = kt.match(/override\s+fun\s+chapterListSelector\s*\(\s*\)\s*(?::\s*String\s*)?\{([\s\S]*?)\n\s{4}\}/);
    if (bm) {
      const body = bm[1];
      const baseM = body.match(/val\s+base\s*=\s*"((?:[^"\\]|\\.)*)"/);
      if (baseM) config.chapterListSelector = baseM[1];
      if (/:not\(\.locked\)/.test(body)) config.lockedChapterSelector = '.locked';
    }
    const hm = kt.match(/getChapterListSelectorBasedOnHidePaidChaptersPref\(\s*"((?:[^"\\]|\\.)*)"/);
    if (hm) config.chapterListSelector = hm[1];
  }
  if (/MangaThemesiaPaidChapterHelper/.test(kt) && !config.lockedChapterSelector) {
    const lm = kt.match(/lockedChapterSelector\s*=\s*"((?:[^"\\]|\\.)*)"/);
    config.lockedChapterSelector = lm ? lm[1] : "a[data-bs-target='#lockedChapterModal']";
    warnings.push('paid-chapter filtering approximated (locked chapters hidden)');
  }

  // chapter name/date selectors from custom chapterFromElement bodies
  const cfm = kt.match(/override\s+fun\s+chapterFromElement\s*\([^)]*\)\s*(?::\s*SChapter\s*)?=\s*([\s\S]*?)(?=\n\s{0,4}(?:override|private|companion|protected|class )|\n\})/);
  if (cfm) {
    const selRe = /(\bname|\bchapterName|\bchTitle|\bdate_upload|\bdateElement|\bchapterDate|\bchDate)\s*=\s*(?:element|it)\.select(?:First)?\(\s*(?:"((?:[^"\\]|\\.)*)"|"""([\s\S]*?)""")\s*\)/g;
    let mm;
    while ((mm = selRe.exec(cfm[1])) !== null) {
      const sel = (mm[2] !== undefined ? mm[2] : mm[1]).trim();
      if (/date/i.test(mm[1])) config.chapterDateSelector = sel;
      else config.chapterNameSelector = sel;
    }
  }

  // MangaThemesiaAlt (random slug) settings
  config.slugRegex = '^(\\d+-)';
  config.altListMode = 'listmode';
  config.altListSelector = 'div#content div.soralist ul li a.series';
  const sr = kt.match(/override\s+val\s+slugRegex\s*=\s*Regex\("""([^"]*)"""\)/);
  if (sr) config.slugRegex = sr[1];
  if (/override\s+val\s+listUrl\s*(?:get\s*)?=\s*mangaUrlDirectory/.test(kt)) config.altListMode = 'dir';
  const ls = strOverride(kt, 'listSelector');
  if (ls !== undefined) config.altListSelector = ls;
  if (config.isAlt) warnings.push('random-url slug mapping approximated via list page lookup');

  // feature warnings
  if (/QuickJs|sucuri|CloudflareHelper|ClientHintsInterceptor|addCookie/.test(kt)) {
    warnings.push('anti-bot protection/cookies; may fail without WebView');
  }
  if (/imageDescrambler|ScramblingData|descrambl/i.test(kt)) {
    warnings.push('image scrambling not supported; pages may appear corrupted');
  }
  if (/override\s+suspend\s+fun\s+getSearchMangaList/.test(kt)) {
    warnings.push('custom search API not portable; approximated with theme default search');
  }
  if (/Base64\.decode\(url/.test(kt)) {
    warnings.push('custom page-url decoding approximated');
  }
  if (/Unpacker/.test(kt) && !/Descrambler|ScramblingData/i.test(kt)) {
    warnings.push('packed page scripts; using built-in JS unpacker');
  }
  if (/override\s+fun\s+mangaDetailsParse/.test(kt)) {
    warnings.push('custom mangaDetailsParse tweaks approximated');
  }
  if (/override\s+fun\s+chapterListParse/.test(kt)) {
    warnings.push('custom chapterListParse tweaks approximated');
  }
  if (/override\s+fun\s+pageListParse/.test(kt) && !/super\.pageListParse/.test(kt)) {
    warnings.push('custom pageListParse approximated');
  }

  return { ok: true, config, warnings };
}

// ---------- code generation ----------
export function generate(manifest, config) {
  const langs = Array.from(new Set([config.lang, 'en']));
  const monthTable = {};
  for (const l of langs) {
    if (MONTHS[l]) {
      const sets = [MONTHS[l].full, MONTHS[l].short];
      if (MONTHS[l].gen) sets.push(MONTHS[l].gen);
      monthTable[l] = sets;
    }
  }

  const header = `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (theme: mangathemesia${config.isAlt ? '/alt' : ''})
// ${manifest.baseUrl}
// Requires shared runtime: manifest.runtime = 'wp' (R_abs/R_path/R_img/R_sel/R_selFirst/R_ownText/R_status/R_date)
var BASE = ${JSON.stringify(manifest.baseUrl)};
var CFG = ${JSON.stringify(config, null, 2)};

var MT_MONTHS = ${JSON.stringify(monthTable)};
`;

  const body = String.raw`
// ---------------- mangathemesia engine ----------------

// multi-part tolerant select: query each top-level comma part separately,
// skip parts that fail (e.g. Jsoup-only pseudo classes) or contain Kotlin template leftovers
// Jsoup-style :contains(label) / :containsOwn(label) support: split into
// "prefix:contains(label) rest" -> query prefix, filter by text (case-insensitive),
// then resolve rest: descendant via scoped query, "+x" sibling via order correlation
function mtTryContains(node, p) {
  var idx = p.indexOf(':contains');
  if (idx < 0) { return null; }
  var own = p.indexOf(':containsOwn(') === idx;
  var open = p.indexOf('(', idx);
  if (open < 0) { return null; }
  var d = 1;
  var j = open + 1;
  while (j < p.length && d > 0) {
    var c = p.charAt(j);
    if (c === '(') { d++; }
    else if (c === ')') { d--; }
    j++;
  }
  if (d !== 0) { return null; }
  var label = p.substring(open + 1, j - 1).replace(/^['"]/, '').replace(/['"]$/, '').toLowerCase();
  var prefix = p.substring(0, idx);
  var rest = p.substring(j).trim();
  function labelOk(el) {
    var t = own ? R_ownText(el) : (typeof el.text === 'function' ? el.text() : R_ownText(el));
    return String(t || '').toLowerCase().indexOf(label) >= 0;
  }
  var cands = prefix ? R_sel(node, prefix) : [node];
  var out = [];
  if (rest === '') {
    for (var a = 0; a < cands.length; a++) {
      if (labelOk(cands[a])) { out.push(cands[a]); }
    }
    return out;
  }
  if (rest.charAt(0) === '+' || rest.charAt(0) === '~') {
    // sibling combinator: cannot scope querySelector to siblings; correlate by document order.
    // stripped query prefix+rest yields pairs in same order as prefix matches; if counts match, zip.
    var pairs = R_sel(node, (prefix ? prefix + ' ' : '') + rest);
    if (rest.charAt(0) === '+' && pairs.length === cands.length) {
      for (var b = 0; b < cands.length; b++) {
        if (labelOk(cands[b])) { out.push(pairs[b]); }
      }
      return out;
    }
    return pairs;
  }
  for (var e = 0; e < cands.length; e++) {
    if (!labelOk(cands[e])) { continue; }
    var sub = R_sel(cands[e], rest);
    for (var f = 0; f < sub.length; f++) { out.push(sub[f]); }
  }
  return out;
}
function mtSelAll(node, css) {
  if (!css) { return []; }
  var out = [];
  var parts = [];
  var depth = 0;
  var cur = '';
  for (var i = 0; i < css.length; i++) {
    var ch = css.charAt(i);
    if (ch === '(' || ch === '[') { depth++; }
    else if (ch === ')' || ch === ']') { depth--; }
    if (ch === ',' && depth === 0) { parts.push(cur); cur = ''; continue; }
    cur += ch;
  }
  if (cur.trim() !== '') { parts.push(cur); }
  for (var j = 0; j < parts.length; j++) {
    var p = parts[j].trim();
    if (!p || p.indexOf('$' + '{') >= 0) { continue; }
    var list = null;
    if (p.indexOf(':contains') >= 0) {
      list = mtTryContains(node, p);
      if (list === null) { list = R_sel(node, p); }
    } else {
      list = R_sel(node, p);
    }
    for (var k = 0; k < list.length; k++) { out.push(list[k]); }
  }
  return out;
}
function mtFirst(node, css) {
  var l = mtSelAll(node, css);
  return l.length > 0 ? l[0] : null;
}

// ---- locale-aware date parsing (datePattern tokens: MMMM MMM MM dd d yyyy 'lit') ----
function mtMonthIndex(name, lang) {
  var low = String(name || '').toLowerCase().replace(/\.$/, '').trim();
  if (!low) { return -1; }
  var sets = MT_MONTHS[lang] || [];
  for (var s = 0; s < sets.length; s++) {
    for (var i = 0; i < sets[s].length; i++) {
      var m0 = sets[s][i];
      if (low === m0) { return i; }
      if (low.length >= 3 && m0.indexOf(low) === 0) { return i; }
      if (m0.length >= 3 && low.indexOf(m0) === 0) { return i; }
    }
  }
  return -1;
}
function mtLitEsc(c) {
  if (c === ' ') { return '\\s+'; }
  if ('.,-/()[]'.indexOf(c) >= 0) { return '\\' + c; }
  return c;
}
function mtParsePattern(text, pattern, lang) {
  var s = String(text || '').trim().replace(/(\d)(st|nd|rd|th)\b/gi, '$1');
  var toks = [];
  var rx = '^';
  var i = 0;
  while (i < pattern.length) {
    if (pattern.substr(i, 4) === 'MMMM') { toks.push('M'); rx += '([^\\s\\d,]+)'; i += 4; }
    else if (pattern.substr(i, 3) === 'MMM') { toks.push('M'); rx += '([^\\s\\d,]+)'; i += 3; }
    else if (pattern.substr(i, 4) === 'yyyy') { toks.push('y'); rx += '(\\d{4})'; i += 4; }
    else if (pattern.substr(i, 2) === 'MM') { toks.push('m'); rx += '(\\d{1,2})'; i += 2; }
    else if (pattern.charAt(i) === 'd') { toks.push('d'); rx += '(\\d{1,2})'; i += 1; }
    else if (pattern.charAt(i) === "'") {
      var j = pattern.indexOf("'", i + 1);
      if (j < 0) { i++; } else { rx += mtLitEsc(pattern.substring(i + 1, j)); i = j + 1; }
    }
    else { rx += mtLitEsc(pattern.charAt(i)); i++; }
  }
  rx += '\\s*$';
  var m = s.match(new RegExp(rx, 'i'));
  if (!m) { return 0; }
  var day = -1, mon = -1, year = -1;
  var gi = 1;
  for (var t = 0; t < toks.length; t++) {
    var v = m[gi++];
    if (toks[t] === 'd') { day = parseInt(v, 10); }
    else if (toks[t] === 'm') { mon = parseInt(v, 10) - 1; }
    else if (toks[t] === 'y') { year = parseInt(v, 10); }
    else if (toks[t] === 'M') {
      mon = mtMonthIndex(v, lang);
      if (mon < 0 && lang !== 'en') { mon = mtMonthIndex(v, 'en'); }
    }
  }
  if (lang === 'th' && year > 2400) { year -= 543; }
  if (day < 1 || mon < 0 || mon > 11 || isNaN(year) || year < 1900 || year > 2200) { return 0; }
  var ms = new Date(year, mon, day).getTime();
  return isNaN(ms) ? 0 : ms;
}
function mtParseDate(s) {
  var v = String(s || '').trim();
  if (!v) { return 0; }
  var t = mtParsePattern(v, CFG.datePattern, CFG.lang);
  if (t) { return t; }
  if (CFG.lang !== 'en') {
    t = mtParsePattern(v, CFG.datePattern, 'en');
    if (t) { return t; }
  }
  return R_date(v);
}

// ---- status (base parseStatus + R_status) ----
function mtStatus(s) {
  var v = String(s || '').trim().toLowerCase();
  if (!v) { return ''; }
  if (/dropped|discontinued/.test(v)) { return 'cancelled'; }
  if (/season end|hiato/.test(v)) { return 'hiatus'; }
  if (/one-shot|bitti|tamat|finalizad|مكتمل/.test(v)) { return 'completed'; }
  if (/مستمرة|مستمر|publishing/.test(v)) { return 'ongoing'; }
  var r = R_status(v);
  if (r) { return r; }
  return '';
}

function mtChapterNo(name) {
  var m = String(name || '').match(/(?:chapter|chap|ch|bab|bölüm|capítulo|capitulo|cap|ep|episode|فصل|ตอนที่)\.?\s*[\d:#-]*\s*(\d+(?:\.\d+)?)/i);
  return m ? parseFloat(m[1]) : -1;
}

// ---- list URL builder (per searchMangaUrl override style) ----
function mtSearchUrl(page, order, query) {
  var dir = CFG.mangaUrlDirectory || '';
  var q = String(query || '').trim();
  if (CFG.searchStyle === 'advancedsearch') {
    return BASE + '/advanced-search?name=' + encodeURIComponent(q) + '&page=' + page + '&sort=' + (order || 'popular');
  }
  if (CFG.searchStyle === 'titlepath' && !q) {
    var base = page > 1 ? BASE + '/title/page/' + page + '/' : BASE + '/title/';
    return base + '?orderby=' + (order || 'popular');
  }
  if (q && CFG.searchStyle === 'wpsearch') {
    return BASE + '/page/' + page + '/?s=' + encodeURIComponent(q);
  }
  if (q && CFG.searchStyle === 'sparam') {
    return BASE + '/?s=' + encodeURIComponent(q) + '&page=' + page;
  }
  if (q && CFG.searchStyle === 'dirsparam') {
    return BASE + dir + '?s=' + encodeURIComponent(q) + '&page=' + page;
  }
  if (CFG.searchStyle === 'starlight') {
    if (q) { return BASE + '/buscar?search=' + encodeURIComponent(q) + '&page-current=' + page; }
    return BASE + dir + '?search=&page-current=' + page;
  }
  if (CFG.searchStyle === 'mangacan') {
    if (q) {
      var slug = encodeURIComponent(q).replace(/%20/g, '-').toLowerCase();
      return BASE + '/cari/' + slug + '/' + page + '.html';
    }
    return BASE + '/';
  }
  var parts = [];
  if (q) { parts.push('title=' + encodeURIComponent(q)); }
  parts.push('page=' + page);
  if (!q && order) { parts.push('order=' + order); }
  return BASE + dir + '/?' + parts.join('&');
}

// ---- MangaThemesiaAlt: permanent slug keys + list-page url map ----
var mtSlugRe = CFG.slugRegex ? new RegExp(CFG.slugRegex) : /^(\d+-)/;
function mtPermaKey(path) {
  var m = path.match(/^(.*\/)([^\/]+)\/?$/);
  if (!m) { return path; }
  return m[1] + m[2].replace(mtSlugRe, '') + '/';
}
var mtAltMap = null;
async function mtAltUrlMap() {
  if (mtAltMap) { return mtAltMap; }
  mtAltMap = {};
  try {
    var listUrl = CFG.altListMode === 'dir' ? (CFG.mangaUrlDirectory || '') : (CFG.mangaUrlDirectory || '') + '/list-mode/';
    var text = await $.http.get(BASE + listUrl);
    var doc = $.html.parse(text);
    var links = mtSelAll(doc, CFG.altListSelector);
    for (var i = 0; i < links.length; i++) {
      var href = links[i].absUrl('href') || links[i].attr('href');
      if (!href) { continue; }
      var p = R_path(href);
      var m = p.match(/^(.*\/)([^\/]+)\/?$/);
      if (!m) { continue; }
      mtAltMap[m[1] + m[2].replace(mtSlugRe, '') + '/'] = p;
    }
  } catch (e) { /* keep empty map */ }
  return mtAltMap;
}
async function mtResolveManga(key) {
  var text = await $.http.get(R_abs(key));
  var doc = $.html.parse(text);
  if (!CFG.isAlt) { return doc; }
  var hasContent = !!mtFirst(doc, CFG.seriesDetailsSelector) || mtSelAll(doc, CFG.chapterListSelector).length > 0;
  if (hasContent) { return doc; }
  var map = await mtAltUrlMap();
  var full = map[key];
  if (full && full !== key) {
    try {
      var t2 = await $.http.get(R_abs(full));
      return $.html.parse(t2);
    } catch (e2) { /* fall through */ }
  }
  return doc;
}

// ---- manga list parse ----
function mtListFromDoc(doc) {
  var els = mtSelAll(doc, CFG.searchSelector);
  var out = [];
  var seen = {};
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var link = mtFirst(el, 'a');
    if (!link) { continue; }
    var href = link.absUrl('href') || link.attr('href');
    if (!href) { continue; }
    var img = mtFirst(el, 'img');
    var title = link.attr('title');
    if (!title && img) { title = img.attr('title') || img.attr('alt'); }
    if (!title) { title = link.text(); }
    if (!title && CFG.searchTitleSelector) {
      var tEl = mtFirst(el, CFG.searchTitleSelector);
      if (tEl) { title = tEl.text(); }
    }
    var key = R_path(href);
    if (!key || key === '/') { continue; }
    if (CFG.isAlt) { key = mtPermaKey(key); }
    if (seen[key]) { continue; }
    seen[key] = 1;
    out.push({ key: key, title: String(title || '').trim(), coverUrl: R_img(img) });
  }
  var hasNext = false;
  if (CFG.searchNextPageSelector) { hasNext = !!mtFirst(doc, CFG.searchNextPageSelector); }
  return { mangas: out, hasNextPage: hasNext };
}

// ---- details parse ----
function mtDetails(doc, key) {
  var scope = mtFirst(doc, CFG.seriesDetailsSelector) || doc;
  var title = '';
  var tEl = mtFirst(scope, CFG.seriesTitleSelector);
  if (tEl) { title = tEl.text().trim(); }
  if (!title) {
    var h1 = mtFirst(doc, 'h1');
    if (h1) { title = h1.text().trim(); }
  }
  function cleanPerson(sel) {
    var el = mtFirst(scope, sel);
    if (!el) { return ''; }
    var t = R_ownText(el).trim();
    if (!t || t === '-' || /^(n\/a|unknown)$/i.test(t)) { return ''; }
    return t;
  }
  var author = cleanPerson(CFG.seriesAuthorSelector) || cleanPerson(CFG.seriesArtistSelector);
  var desc = '';
  var dEl = mtFirst(scope, CFG.seriesDescriptionSelector);
  if (dEl) { desc = dEl.text().trim(); }
  var altEl = mtFirst(scope, CFG.seriesAltNameSelector);
  if (altEl) {
    var alt = R_ownText(altEl).trim();
    if (alt) {
      var names = alt.split(/[|/•,;]/).map(function (x) { return x.trim(); }).filter(Boolean);
      if (names.length) {
        desc = (desc ? desc + '\n\n' : '') + CFG.altNamePrefix + '\n' + names.map(function (n) { return '- ' + n; }).join('\n');
      }
    }
  }
  var genres = [];
  var gEls = mtSelAll(scope, CFG.seriesGenreSelector);
  for (var i = 0; i < gEls.length; i++) {
    var g = gEls[i].text().trim();
    if (g && genres.indexOf(g) < 0) { genres.push(g); }
  }
  var typeEl = mtFirst(scope, CFG.seriesTypeSelector);
  if (typeEl) {
    var ty = R_ownText(typeEl).trim();
    if (ty && genres.indexOf(ty) < 0) { genres.push(ty); }
  }
  var genreStr = genres.map(function (x) { return x.charAt(0).toUpperCase() + x.slice(1).toLowerCase(); }).join(', ');
  var status = '';
  var sEl = mtFirst(scope, CFG.seriesStatusSelector);
  if (sEl) { status = mtStatus(sEl.text()); }
  var thEl = mtFirst(scope, CFG.seriesThumbnailSelector);
  var cover = thEl ? (R_img(thEl) || R_img(mtFirst(thEl, 'img'))) : '';
  return {
    key: key,
    title: title,
    coverUrl: cover,
    author: author,
    description: desc,
    genre: genreStr,
    status: status
  };
}

// ---- chapter list parse (doc order newest-first -> return oldest-first) ----
function mtChapters(doc) {
  var els = mtSelAll(doc, CFG.chapterListSelector);
  var out = [];
  var seen = {};
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    if (CFG.lockedChapterSelector && mtFirst(el, CFG.lockedChapterSelector)) { continue; }
    var link = mtFirst(el, 'a[href]');
    if (!link) { continue; }
    var href = link.absUrl('href') || link.attr('href');
    if (!href || href === '#') { continue; }
    var key = R_path(href);
    if (!key || key === '/' || seen[key]) { continue; }
    seen[key] = 1;
    var name = '';
    var nEl = mtFirst(el, CFG.chapterNameSelector);
    if (nEl) { name = nEl.text().trim(); }
    if (!name) { name = link.text().trim(); }
    var dateText = '';
    var dEl = mtFirst(el, CFG.chapterDateSelector);
    if (dEl) { dateText = dEl.text().trim(); }
    out.push({
      key: key,
      name: name,
      chapterNumber: mtChapterNo(name),
      dateUpload: mtParseDate(dateText),
      pages: 0,
      sortOrder: 0
    });
  }
  // "Updated On" date for the newest chapter when the list has no timestamps
  if (out.length > 0 && out[0].dateUpload === 0) {
    var tEls = mtSelAll(doc, '.listinfo time[itemprop=dateModified], .fmed:contains(update) time, span:contains(update) time');
    for (var j = 0; j < tEls.length; j++) {
      var dt = tEls[j].attr('datetime');
      if (dt) { out[0].dateUpload = R_date(dt); break; }
    }
  }
  out.reverse();
  for (var k = 0; k < out.length; k++) { out[k].sortOrder = k; }
  return out;
}

// ---- pages: readerarea imgs, ts_reader data-uri script, packed scripts, raw JSON ----
var MT_JSON_IMAGES = /["']?(?:images|imageUrls)["']?\s*[:=]\s*(\[[^\]]*\])/;
function mtImagesFromJson(text) {
  var m = String(text || '').match(MT_JSON_IMAGES);
  if (!m) { return []; }
  var raw = m[1].replace(/,\s*]/g, ']');
  var list;
  try { list = JSON.parse(raw); } catch (e) { return []; }
  if (typeof list === 'string') {
    try { list = JSON.parse(list); } catch (e2) { return []; }
  }
  if (!Array.isArray(list)) { return []; }
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var u = String(list[i] || '');
    if (/^https?:\/\//.test(u) || u.charAt(0) === '/') { out.push(R_abs(u)); }
  }
  return out;
}
function mtUnescapeStr(s) {
  var map = { n: '\n', t: '\t', r: '\r', '0': '\0' };
  var out = '';
  var i = 0;
  while (i < s.length) {
    var c = s.charAt(i);
    if (c === '\\' && i + 1 < s.length) {
      var d = s.charAt(i + 1);
      if (d === 'x' && i + 3 < s.length) { out += String.fromCharCode(parseInt(s.substr(i + 2, 2), 16)); i += 4; continue; }
      if (d === 'u' && i + 5 < s.length) { out += String.fromCharCode(parseInt(s.substr(i + 2, 4), 16)); i += 6; continue; }
      if (map[d] !== undefined) { out += map[d]; i += 2; continue; }
      out += d; i += 2; continue;
    }
    out += c; i++;
  }
  return out;
}
// p,a,c,k,e,d unpacker (no eval)
function mtUnpack(src) {
  var bi = src.indexOf('}(');
  if (bi < 0) { return ''; }
  var i = bi + 2;
  var q = src.charAt(i);
  if (q !== "'" && q !== '"') { return ''; }
  i++;
  var raw = '';
  while (i < src.length) {
    var c = src.charAt(i);
    if (c === '\\' && i + 1 < src.length) { raw += c + src.charAt(i + 1); i += 2; continue; }
    if (c === q) { break; }
    raw += c; i++;
  }
  var rest = src.substring(i + 1);
  var rm = rest.match(/^\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(['"])([\s\S]*?)\3\s*\.\s*split\s*\(\s*['"]\|['"]\s*\)/);
  if (!rm) { return ''; }
  var a = parseInt(rm[1], 10);
  var cCount = parseInt(rm[2], 10);
  var k = rm[4].split('|');
  var p = mtUnescapeStr(raw);
  if (!a || !cCount || !p) { return ''; }
  function base36(cn) {
    return (cn < a ? '' : base36(Math.floor(cn / a))) + ((cn = cn % a) > 35 ? String.fromCharCode(cn + 29) : cn.toString(36));
  }
  while (cCount--) {
    if (k[cCount]) {
      p = p.replace(new RegExp('\\b' + base36(cCount) + '\\b', 'g'), k[cCount]);
    }
  }
  return p;
}
function mtPagesFromDoc(doc) {
  var pages = [];
  var seen = {};
  function add(u) {
    if (!u || !/^https?:\/\//.test(u)) { return; }
    if (seen[u]) { return; }
    seen[u] = 1;
    pages.push({ index: pages.length, url: u });
  }
  var els = mtSelAll(doc, CFG.pageSelector);
  for (var i = 0; i < els.length; i++) {
    var u = R_img(els[i]);
    if (!u) {
      var inner = mtFirst(els[i], 'img');
      if (inner) { u = R_img(inner); }
    }
    if (u && /mihon/i.test(u)) { continue; }
    add(u);
  }
  if (pages.length > 0) { return pages; }
  var scripts = mtSelAll(doc, 'script');
  // ts_reader.run({...}) delivered as base64 data-uri script
  for (var s = 0; s < scripts.length; s++) {
    var src = scripts[s].attr('src');
    if (src && src.indexOf('data:text/javascript;base64,') === 0) {
      var dec = '';
      try { dec = $.crypto.base64Decode(src.substring(src.indexOf(',') + 1)); } catch (e) { dec = ''; }
      var list2 = mtImagesFromJson(dec);
      for (var x = 0; x < list2.length; x++) { add(list2[x]); }
      if (pages.length > 0) { return pages; }
    }
  }
  // inline ts_reader.run({...}) scripts
  for (var s2 = 0; s2 < scripts.length; s2++) {
    var body = scripts[s2].html() || '';
    if (body.indexOf('ts_reader') < 0) { continue; }
    var listB = mtImagesFromJson(body);
    for (var x2 = 0; x2 < listB.length; x2++) { add(listB[x2]); }
    if (pages.length > 0) { return pages; }
  }
  // p,a,c,k,e,d packed scripts
  for (var p2 = 0; p2 < scripts.length; p2++) {
    var data = scripts[p2].html() || '';
    if (data.indexOf('p,a,c,k,e,d') < 0) { continue; }
    var unpacked = mtUnpack(data);
    var list3 = mtImagesFromJson(unpacked);
    for (var y = 0; y < list3.length; y++) { add(list3[y]); }
  }
  if (pages.length > 0) { return pages; }
  // whole-document fallback: doc.html() is unreliable in some DOMs, join script bodies
  var whole = '';
  try { whole = doc.html ? (doc.html() || '') : ''; } catch (e0) { whole = ''; }
  if (!whole) {
    for (var s3 = 0; s3 < scripts.length; s3++) { whole += (scripts[s3].html() || '') + '\n'; }
  }
  var list4 = mtImagesFromJson(whole);
  for (var z = 0; z < list4.length; z++) { add(list4[z]); }
  return pages;
}

module.exports = {
  getPopularManga: async function (page) {
    var text = await $.http.get(mtSearchUrl(page, CFG.popularOrder || 'popular', ''));
    return mtListFromDoc($.html.parse(text));
  },

  getSearchManga: async function (page, query) {
    var text = await $.http.get(mtSearchUrl(page, '', query));
    return mtListFromDoc($.html.parse(text));
  },

  getMangaDetail: async function (mangaKey) {
    var doc = await mtResolveManga(mangaKey);
    return mtDetails(doc, mangaKey);
  },

  getChapterList: async function (mangaKey) {
    var doc = await mtResolveManga(mangaKey);
    return mtChapters(doc);
  },

  getPageList: async function (chapterKey) {
    var text = await $.http.get(R_abs(chapterKey));
    var doc = $.html.parse(text);
    return mtPagesFromDoc(doc);
  },

  imageHeaders: function () {
    return { Referer: BASE + '/' };
  }
};
`;
  return header + body;
}
