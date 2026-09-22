// Shared emitted-JS snippets for bespoke standalone engines (not an engine itself).
export const HELPERS = `
function H_doc(url, headers) { return $.http.get(url, headers).then(function (t) { return $.html.parse(t); }); }
function H_get(url, headers) { return $.http.get(url, headers); }
function H_pairs(root, sel, label) {
  var els = R_sel(root, sel);
  for (var i = 0; i < els.length; i++) {
    if (els[i].text().toLowerCase().indexOf(String(label).toLowerCase()) >= 0 && els[i + 1]) {
      return els[i + 1].text();
    }
  }
  return '';
}
function H_monthDate(v) {
  var m = String(v || '').trim().match(/^(\\d{1,2})-([A-Za-z]{3})-(\\d{4})$/);
  if (!m) { return R_date(v); }
  var mons = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };
  var mo = mons[m[2].toLowerCase()];
  if (mo === undefined) { return 0; }
  return Date.UTC(parseInt(m[3], 10), mo, parseInt(m[1], 10));
}
function H_firstText(root, sel) { var el = R_selFirst(root, sel); return el ? el.text() : ''; }
function H_texts(root, sel) {
  var els = R_sel(root, sel); var parts = [];
  for (var i = 0; i < els.length; i++) { var t = els[i].text(); if (t) parts.push(t); }
  return parts.join(', ');
}
`;

export function wrap(manifest, body, opts = {}) {
  return `// ${manifest.name} — auto-generated from keiyoushi/extensions-source (bespoke standalone)
// ${manifest.baseUrl}
var BASE = ${JSON.stringify(manifest.baseUrl)};
${opts.vars ? opts.vars + '\n' : ''}${HELPERS}
${body}
`;
}
