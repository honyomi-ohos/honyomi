// Shared Next.js RSC / flight-payload parsing snippet for bespoke engines.
// NOT an engine (leading underscore => skipped by preloadStandalone).
// Usage inside an engine's generate():
//   import { RSC_SRC } from './_nextjs.mjs';
//   return `...${RSC_SRC}...`;   // inserts: var RSC = (function () { ... })();
// API exposed in the generated script:
//   RSC.parse(text)        -> array of resolved flight rows (works for raw RSC bodies
//                             and HTML pages containing self.__next_f.push chunks)
//   RSC.find(rows, [keys]) -> first object (deep, BFS, row order) containing ALL keys
//   RSC.arr(rows, key)     -> first array stored under `key` on any walked object
//   RSC.walk(rows, fn)     -> first value for which fn(v) is truthy
function __rscFactory() {
  function flightText(text) {
    if (text.indexOf('__next_f.push') === -1) { return text; }
    var re = /self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]/g;
    var out = [];
    var m;
    while ((m = re.exec(text)) !== null) {
      try { out.push(JSON.parse(m[1])); } catch (e) { /* skip bad chunk */ }
    }
    return out.join('');
  }
  function parseRows(flight) {
    var rows = [];
    var i = 0;
    var n = flight.length;
    while (i < n) {
      var colon = flight.indexOf(':', i);
      if (colon < 0) { break; }
      var len = parseInt(flight.substring(i, colon), 16);
      if (isNaN(len) || len <= 0) { break; }
      var rest = flight.substr(colon + 1, len);
      if (rest.length < len) { break; }
      var c2 = rest.indexOf(':');
      if (c2 > 0) {
        rows.push({ id: rest.substring(0, c2), payload: rest.substring(c2 + 1) });
      }
      i = colon + 1 + len;
      while (i < n && (flight.charAt(i) === '\n' || flight.charAt(i) === '\r')) { i++; }
    }
    return rows;
  }
  function resolve(v, map, depth) {
    if (depth > 6) { return v; }
    if (typeof v === 'string') {
      if (v === '$$') { return '$'; }
      if (v === '$undefined') { return undefined; }
      if (v.length > 1 && v.charAt(0) === '$') {
        var ref = (v.charAt(1) === 'L' || v.charAt(1) === '@') ? v.substring(2) : v.substring(1);
        if (/^[0-9a-fA-F]+$/.test(ref) && Object.prototype.hasOwnProperty.call(map, ref)) {
          return resolve(map[ref], map, depth + 1);
        }
      }
      return v;
    }
    if (v && typeof v === 'object') {
      if (Array.isArray(v)) {
        var a = new Array(v.length);
        for (var i = 0; i < v.length; i++) { a[i] = resolve(v[i], map, depth + 1); }
        return a;
      }
      var o = {};
      for (var k in v) { o[k] = resolve(v[k], map, depth + 1); }
      return o;
    }
    return v;
  }
  function parse(text) {
    var rows = parseRows(flightText(text));
    var map = {};
    var roots = [];
    for (var r = 0; r < rows.length; r++) {
      var p;
      try { p = JSON.parse(rows[r].payload); } catch (e) { continue; }
      if (p === null || p === undefined) { continue; }
      map[rows[r].id] = p;
      roots.push(p);
    }
    var out = [];
    for (var i = 0; i < roots.length; i++) { out.push(resolve(roots[i], map, 0)); }
    return out;
  }
  function hasKeys(obj, keys) {
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) { return false; }
    for (var i = 0; i < keys.length; i++) {
      if (!Object.prototype.hasOwnProperty.call(obj, keys[i])) { return false; }
    }
    return true;
  }
  function visit(rows, fn) {
    var list = [];
    for (var i = 0; i < rows.length; i++) { list.push(rows[i]); }
    var idx = 0;
    while (idx < list.length && idx < 60000) {
      var v = list[idx++];
      if (fn(v)) { return v; }
      if (v && typeof v === 'object') {
        for (var k in v) { list.push(v[k]); }
      }
    }
    return null;
  }
  return {
    parse: parse,
    find: function (rows, keys) {
      return visit(rows, function (v) { return hasKeys(v, keys); });
    },
    arr: function (rows, key) {
      var obj = visit(rows, function (v) {
        return !!v && typeof v === 'object' && !Array.isArray(v) &&
          Object.prototype.hasOwnProperty.call(v, key) && Array.isArray(v[key]);
      });
      return obj ? obj[key] : null;
    },
    walk: function (rows, fn) { return visit(rows, fn); }
  };
}

export const RSC_SRC = 'var RSC = (' + __rscFactory.toString() + ')();';
