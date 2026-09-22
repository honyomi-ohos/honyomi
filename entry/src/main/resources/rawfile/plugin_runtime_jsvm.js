// JSVM host runtime — polyfills + original Mihon $ DSL.
// Prepended in front of every extension main.js (see PluginService.composeScript).
(function (g) {
  'use strict';

  if (typeof g.global === 'undefined') { g.global = g; }
  if (typeof g.module === 'undefined') {
    g.module = { exports: {} };
    g.exports = g.module.exports;
  }

  // ---- atob / btoa ---------------------------------------------------------
  if (typeof g.atob !== 'function' || typeof g.btoa !== 'function') {
    var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    g.btoa = g.btoa || function (s) {
      s = String(s);
      var out = '', i = 0;
      while (i < s.length) {
        var a = s.charCodeAt(i++);
        var b = i < s.length ? s.charCodeAt(i++) : NaN;
        var c = i < s.length ? s.charCodeAt(i++) : NaN;
        var t = (a << 16) | ((b & 255) << 8) | (c & 255);
        out += B64[(t >> 18) & 63] + B64[(t >> 12) & 63];
        out += isNaN(b) ? '=' : B64[(t >> 6) & 63];
        out += isNaN(c) ? '=' : B64[t & 63];
      }
      return out;
    };
    g.atob = g.atob || function (s) {
      s = String(s).replace(/[^A-Za-z0-9+/=]/g, '');
      var out = '', i = 0;
      while (i < s.length) {
        var e1 = B64.indexOf(s.charAt(i++));
        var e2 = B64.indexOf(s.charAt(i++));
        var e3 = B64.indexOf(s.charAt(i++));
        var e4 = B64.indexOf(s.charAt(i++));
        var t = (e1 << 18) | (e2 << 12) | ((e3 & 63) << 6) | (e4 & 63);
        out += String.fromCharCode((t >> 16) & 255);
        if (e3 !== 64 && e3 !== -1) { out += String.fromCharCode((t >> 8) & 255); }
        if (e4 !== 64 && e4 !== -1) { out += String.fromCharCode(t & 255); }
      }
      return out;
    };
  }

  // ---- TextEncoder / TextDecoder ------------------------------------------
  if (typeof g.TextEncoder !== 'function') {
    g.TextEncoder = function () {};
    g.TextEncoder.prototype.encode = function (str) {
      str = String(str == null ? '' : str);
      var out = [];
      for (var i = 0; i < str.length; i++) {
        var c = str.charCodeAt(i);
        if (c < 0x80) { out.push(c); }
        else if (c < 0x800) { out.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F)); }
        else if (c >= 0xD800 && c <= 0xDBFF) {
          var c2 = str.charCodeAt(++i);
          var cp = 0x10000 + ((c & 0x3FF) << 10) + (c2 & 0x3FF);
          out.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F),
            0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
        } else {
          out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
        }
      }
      return new Uint8Array(out);
    };
  }
  if (typeof g.TextDecoder !== 'function') {
    g.TextDecoder = function () {};
    g.TextDecoder.prototype.decode = function (buf) {
      var u8 = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
      var s = '', i = 0;
      while (i < u8.length) {
        var c = u8[i++];
        if (c < 0x80) { s += String.fromCharCode(c); }
        else if (c < 0xE0) { s += String.fromCharCode(((c & 0x1F) << 6) | (u8[i++] & 0x3F)); }
        else if (c < 0xF0) {
          s += String.fromCharCode(((c & 0x0F) << 12) | ((u8[i++] & 0x3F) << 6) | (u8[i++] & 0x3F));
        } else {
          var cp = ((c & 0x07) << 18) | ((u8[i++] & 0x3F) << 12) |
            ((u8[i++] & 0x3F) << 6) | (u8[i++] & 0x3F);
          cp -= 0x10000;
          s += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
        }
      }
      return s;
    };
  }

  // ---- URL / URLSearchParams ----------------------------------------------
  if (typeof g.URLSearchParams !== 'function') {
    g.URLSearchParams = function (init) {
      this._p = [];
      var src = init == null ? '' : String(init);
      if (src.charAt(0) === '?') { src = src.substring(1); }
      if (src) {
        var parts = src.split('&');
        for (var i = 0; i < parts.length; i++) {
          if (!parts[i]) { continue; }
          var eq = parts[i].indexOf('=');
          if (eq < 0) { this._p.push([decodeURIComponent(parts[i]), '']); }
          else {
            this._p.push([decodeURIComponent(parts[i].substring(0, eq)),
              decodeURIComponent(parts[i].substring(eq + 1))]);
          }
        }
      }
    };
    g.URLSearchParams.prototype.append = function (k, v) { this._p.push([String(k), String(v)]); };
    g.URLSearchParams.prototype.set = function (k, v) {
      this.delete(k); this.append(k, v);
    };
    g.URLSearchParams.prototype.get = function (k) {
      k = String(k);
      for (var i = 0; i < this._p.length; i++) {
        if (this._p[i][0] === k) { return this._p[i][1]; }
      }
      return null;
    };
    g.URLSearchParams.prototype.delete = function (k) {
      k = String(k);
      var next = [];
      for (var i = 0; i < this._p.length; i++) {
        if (this._p[i][0] !== k) { next.push(this._p[i]); }
      }
      this._p = next;
    };
    g.URLSearchParams.prototype.toString = function () {
      var out = [];
      for (var i = 0; i < this._p.length; i++) {
        out.push(encodeURIComponent(this._p[i][0]) + '=' + encodeURIComponent(this._p[i][1]));
      }
      return out.join('&');
    };
  }
  if (typeof g.URL !== 'function') {
    g.URL = function (path, base) {
      var href = String(path);
      if (base && !/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(href)) {
        var b = String(base);
        if (href.charAt(0) === '/') {
          var origin = b.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^/]*/);
          href = (origin ? origin[0] : b) + href;
        } else {
          href = b.replace(/[?#].*$/, '').replace(/\/[^/]*$/, '/') + href;
        }
      }
      this.href = href;
      var m = href.match(/^([a-zA-Z][a-zA-Z0-9+.-]*:)\/\/([^/?#]+)(\/[^?#]*)?(\?[^#]*)?(#.*)?$/);
      this.protocol = m ? m[1] : '';
      this.host = m ? m[2] : '';
      this.hostname = this.host.split(':')[0];
      this.pathname = m && m[3] ? m[3] : '/';
      this.search = m && m[4] ? m[4] : '';
      this.hash = m && m[5] ? m[5] : '';
      this.origin = this.protocol + '//' + this.host;
      this.searchParams = new g.URLSearchParams(this.search.charAt(0) === '?' ? this.search.substring(1) : this.search);
    };
  }

  // ---- SharedPreferences host bridge (in-memory + seed from ArkTS) --------
  if (typeof g.__PREFS_STORE__ !== 'object' || g.__PREFS_STORE__ == null) {
    g.__PREFS_STORE__ = {};
  }
  function prefsBucket(name) {
    if (!g.__PREFS_STORE__[name] || typeof g.__PREFS_STORE__[name] !== 'object') {
      g.__PREFS_STORE__[name] = {};
    }
    return g.__PREFS_STORE__[name];
  }
  g.__prefs_get = function (name, key) {
    var b = prefsBucket(String(name));
    return Object.prototype.hasOwnProperty.call(b, key) ? b[key] : undefined;
  };
  g.__prefs_set = function (name, key, value) {
    prefsBucket(String(name))[key] = value;
  };
  g.__prefs_remove = function (name, key) {
    delete prefsBucket(String(name))[key];
  };
  g.__prefs_clear = function (name) {
    g.__PREFS_STORE__[String(name)] = {};
  };
  g.__prefs_getAll = function (name) {
    var src = prefsBucket(String(name));
    var out = {};
    for (var k in src) {
      if (Object.prototype.hasOwnProperty.call(src, k)) { out[k] = src[k]; }
    }
    return out;
  };
  g.__prefsDump = function () { return g.__PREFS_STORE__; };

  // ---- crypto.subtle AES-CBC (Madara chapter-protector + tachiyomi Cipher) -
  function toU8(x) {
    if (x instanceof Uint8Array) { return x; }
    if (x instanceof ArrayBuffer) { return new Uint8Array(x); }
    if (ArrayBuffer.isView && ArrayBuffer.isView(x)) {
      return new Uint8Array(x.buffer, x.byteOffset, x.byteLength);
    }
    return new Uint8Array(0);
  }
  function md5bin(bytes) {
    function add32(a, b) { return (a + b) & 0xFFFFFFFF; }
    function cmn(q, a, b, x, s, t) {
      a = add32(add32(a, q), add32(x, t));
      return add32((a << s) | (a >>> (32 - s)), b);
    }
    function ff(a, b, c, d, x, s, t) { return cmn((b & c) | ((~b) & d), a, b, x, s, t); }
    function gg(a, b, c, d, x, s, t) { return cmn((b & d) | (c & (~d)), a, b, x, s, t); }
    function hh(a, b, c, d, x, s, t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
    function ii(a, b, c, d, x, s, t) { return cmn(c ^ (b | (~d)), a, b, x, s, t); }
    function md5cycle(st, k) {
      var a = st[0], b = st[1], c = st[2], d = st[3];
      a = ff(a, b, c, d, k[0], 7, -680876936); d = ff(d, a, b, c, k[1], 12, -389564586);
      c = ff(c, d, a, b, k[2], 17, 606105819); b = ff(b, c, d, a, k[3], 22, -1044525330);
      a = ff(a, b, c, d, k[4], 7, -176418897); d = ff(d, a, b, c, k[5], 12, 1200080426);
      c = ff(c, d, a, b, k[6], 17, -1473231341); b = ff(b, c, d, a, k[7], 22, -45705983);
      a = ff(a, b, c, d, k[8], 7, 1770035416); d = ff(d, a, b, c, k[9], 12, -1958414417);
      c = ff(c, d, a, b, k[10], 17, -42063); b = ff(b, c, d, a, k[11], 22, -1990404162);
      a = ff(a, b, c, d, k[12], 7, 1804603682); d = ff(d, a, b, c, k[13], 12, -40341101);
      c = ff(c, d, a, b, k[14], 17, -1502002990); b = ff(b, c, d, a, k[15], 22, 1236535329);
      a = gg(a, b, c, d, k[1], 5, -165796510); d = gg(d, a, b, c, k[6], 9, -1069501632);
      c = gg(c, d, a, b, k[11], 14, 643717713); b = gg(b, c, d, a, k[0], 20, -373897302);
      a = gg(a, b, c, d, k[5], 5, -701558691); d = gg(d, a, b, c, k[10], 9, 38016083);
      c = gg(c, d, a, b, k[15], 14, -660478335); b = gg(b, c, d, a, k[4], 20, -405537848);
      a = gg(a, b, c, d, k[9], 5, 568446438); d = gg(d, a, b, c, k[14], 9, -1019803690);
      c = gg(c, d, a, b, k[3], 14, -187363961); b = gg(b, c, d, a, k[8], 20, 1163531501);
      a = gg(a, b, c, d, k[13], 5, -1444681467); d = gg(d, a, b, c, k[2], 9, -51403784);
      c = gg(c, d, a, b, k[7], 14, 1735328473); b = gg(b, c, d, a, k[12], 20, -1926607734);
      a = hh(a, b, c, d, k[5], 4, -378558); d = hh(d, a, b, c, k[8], 11, -2022574463);
      c = hh(c, d, a, b, k[11], 16, 1839030562); b = hh(b, c, d, a, k[14], 23, -35309556);
      a = hh(a, b, c, d, k[1], 4, -1530992060); d = hh(d, a, b, c, k[4], 11, 1272893353);
      c = hh(c, d, a, b, k[7], 16, -155497632); b = hh(b, c, d, a, k[10], 23, -1094730640);
      a = hh(a, b, c, d, k[13], 4, 681279174); d = hh(d, a, b, c, k[0], 11, -358537222);
      c = hh(c, d, a, b, k[3], 16, -722521979); b = hh(b, c, d, a, k[6], 23, 76029189);
      a = hh(a, b, c, d, k[9], 4, -640364487); d = hh(d, a, b, c, k[12], 11, -421815835);
      c = hh(c, d, a, b, k[15], 16, 530742520); b = hh(b, c, d, a, k[2], 23, -995338651);
      a = ii(a, b, c, d, k[0], 6, -198630844); d = ii(d, a, b, c, k[7], 10, 1126891415);
      c = ii(c, d, a, b, k[14], 15, -1416354905); b = ii(b, c, d, a, k[5], 21, -57434055);
      a = ii(a, b, c, d, k[12], 6, 1700485571); d = ii(d, a, b, c, k[3], 10, -1894986606);
      c = ii(c, d, a, b, k[10], 15, -1051523); b = ii(b, c, d, a, k[1], 21, -2054922799);
      a = ii(a, b, c, d, k[8], 6, 1873313359); d = ii(d, a, b, c, k[15], 10, -30611744);
      c = ii(c, d, a, b, k[6], 15, -1560198380); b = ii(b, c, d, a, k[13], 21, 1309151649);
      a = ii(a, b, c, d, k[4], 6, -145523070); d = ii(d, a, b, c, k[11], 10, -1120210379);
      c = ii(c, d, a, b, k[2], 15, 718787259); b = ii(b, c, d, a, k[9], 21, -343485551);
      st[0] = add32(st[0], a); st[1] = add32(st[1], b); st[2] = add32(st[2], c); st[3] = add32(st[3], d);
    }
    function md5blk(src, off) {
      var blks = [];
      for (var i = 0; i < 16; i++) {
        blks[i] = src[off + i * 4] + (src[off + i * 4 + 1] << 8) +
          (src[off + i * 4 + 2] << 16) + (src[off + i * 4 + 3] << 24);
      }
      return blks;
    }
    var n = bytes.length;
    var state = [1732584193, -271733879, -1732584194, 271733878];
    var padded = new Uint8Array((((n + 8) >> 6) + 1) << 6);
    padded.set(bytes);
    padded[n] = 0x80;
    var bitLen = n * 8;
    padded[padded.length - 8] = bitLen & 0xFF;
    padded[padded.length - 7] = (bitLen >>> 8) & 0xFF;
    padded[padded.length - 6] = (bitLen >>> 16) & 0xFF;
    padded[padded.length - 5] = (bitLen >>> 24) & 0xFF;
    for (var i = 0; i < padded.length; i += 64) { md5cycle(state, md5blk(padded, i)); }
    var out = new Uint8Array(16);
    for (var i2 = 0; i2 < 4; i2++) {
      out[i2 * 4] = state[i2] & 0xFF;
      out[i2 * 4 + 1] = (state[i2] >>> 8) & 0xFF;
      out[i2 * 4 + 2] = (state[i2] >>> 16) & 0xFF;
      out[i2 * 4 + 3] = (state[i2] >>> 24) & 0xFF;
    }
    return out;
  }
  function md5hex(s) {
    var u8 = typeof s === 'string' ? new g.TextEncoder().encode(s) : toU8(s);
    var bin = md5bin(u8);
    var hex = '';
    for (var i = 0; i < bin.length; i++) {
      var h = bin[i].toString(16);
      hex += h.length < 2 ? ('0' + h) : h;
    }
    return hex;
  }
  var SBOX = [
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
  ];
  var ISBOX = [
    0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
    0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
    0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
    0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
    0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
    0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
    0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
    0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
    0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
    0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
    0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
    0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
    0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
    0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
    0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
    0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d
  ];
  var RCON = [0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36];
  function gmul(a, b) {
    var r = 0;
    while (a) {
      if (a & 1) { r ^= b; }
      var hi = b & 0x80;
      b = (b << 1) & 0xFF;
      if (hi) { b ^= 0x1b; }
      a >>= 1;
    }
    return r;
  }
  function expandKey(key) {
    var nk = key.length / 4, nr = nk + 6, n = 4 * (nr + 1);
    var w = new Array(n), i;
    for (i = 0; i < nk; i++) {
      w[i] = ((key[4 * i] << 24) | (key[4 * i + 1] << 16) | (key[4 * i + 2] << 8) | key[4 * i + 3]) >>> 0;
    }
    for (i = nk; i < n; i++) {
      var t = w[i - 1];
      if (i % nk === 0) {
        t = ((t << 8) | (t >>> 24)) >>> 0;
        t = ((SBOX[(t >>> 24) & 255] << 24) | (SBOX[(t >>> 16) & 255] << 16) |
          (SBOX[(t >>> 8) & 255] << 8) | SBOX[t & 255]) >>> 0;
        t = (t ^ (RCON[i / nk - 1] << 24)) >>> 0;
      } else if (nk > 6 && i % nk === 4) {
        t = ((SBOX[(t >>> 24) & 255] << 24) | (SBOX[(t >>> 16) & 255] << 16) |
          (SBOX[(t >>> 8) & 255] << 8) | SBOX[t & 255]) >>> 0;
      }
      w[i] = (w[i - nk] ^ t) >>> 0;
    }
    return w;
  }
  function addRound(state, w, round) {
    for (var c = 0; c < 4; c++) {
      var word = w[round * 4 + c];
      state[0][c] ^= (word >>> 24) & 255;
      state[1][c] ^= (word >>> 16) & 255;
      state[2][c] ^= (word >>> 8) & 255;
      state[3][c] ^= word & 255;
    }
  }
  function subBytes(state, box) {
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) { state[r][c] = box[state[r][c]]; }
    }
  }
  function shiftRows(state, inv) {
    var t;
    if (!inv) {
      t = state[1][0]; state[1][0] = state[1][1]; state[1][1] = state[1][2]; state[1][2] = state[1][3]; state[1][3] = t;
      t = state[2][0]; state[2][0] = state[2][2]; state[2][2] = t; t = state[2][1]; state[2][1] = state[2][3]; state[2][3] = t;
      t = state[3][3]; state[3][3] = state[3][2]; state[3][2] = state[3][1]; state[3][1] = state[3][0]; state[3][0] = t;
    } else {
      t = state[1][3]; state[1][3] = state[1][2]; state[1][2] = state[1][1]; state[1][1] = state[1][0]; state[1][0] = t;
      t = state[2][0]; state[2][0] = state[2][2]; state[2][2] = t; t = state[2][1]; state[2][1] = state[2][3]; state[2][3] = t;
      t = state[3][0]; state[3][0] = state[3][1]; state[3][1] = state[3][2]; state[3][2] = state[3][3]; state[3][3] = t;
    }
  }
  function mixColumns(state, inv) {
    for (var c = 0; c < 4; c++) {
      var a0 = state[0][c], a1 = state[1][c], a2 = state[2][c], a3 = state[3][c];
      if (!inv) {
        state[0][c] = gmul(2, a0) ^ gmul(3, a1) ^ a2 ^ a3;
        state[1][c] = a0 ^ gmul(2, a1) ^ gmul(3, a2) ^ a3;
        state[2][c] = a0 ^ a1 ^ gmul(2, a2) ^ gmul(3, a3);
        state[3][c] = gmul(3, a0) ^ a1 ^ a2 ^ gmul(2, a3);
      } else {
        state[0][c] = gmul(0x0e, a0) ^ gmul(0x0b, a1) ^ gmul(0x0d, a2) ^ gmul(0x09, a3);
        state[1][c] = gmul(0x09, a0) ^ gmul(0x0e, a1) ^ gmul(0x0b, a2) ^ gmul(0x0d, a3);
        state[2][c] = gmul(0x0d, a0) ^ gmul(0x09, a1) ^ gmul(0x0e, a2) ^ gmul(0x0b, a3);
        state[3][c] = gmul(0x0b, a0) ^ gmul(0x0d, a1) ^ gmul(0x09, a2) ^ gmul(0x0e, a3);
      }
    }
  }
  function cryptBlock(block, w, decrypt) {
    var state = [[], [], [], []], r, c;
    for (r = 0; r < 4; r++) {
      for (c = 0; c < 4; c++) { state[r][c] = block[r + 4 * c]; }
    }
    var nr = w.length / 4 - 1;
    if (!decrypt) {
      addRound(state, w, 0);
      for (r = 1; r < nr; r++) { subBytes(state, SBOX); shiftRows(state, false); mixColumns(state, false); addRound(state, w, r); }
      subBytes(state, SBOX); shiftRows(state, false); addRound(state, w, nr);
    } else {
      addRound(state, w, nr);
      for (r = nr - 1; r >= 1; r--) { shiftRows(state, true); subBytes(state, ISBOX); addRound(state, w, r); mixColumns(state, true); }
      shiftRows(state, true); subBytes(state, ISBOX); addRound(state, w, 0);
    }
    var out = new Uint8Array(16);
    for (r = 0; r < 4; r++) {
      for (c = 0; c < 4; c++) { out[r + 4 * c] = state[r][c]; }
    }
    return out;
  }
  function pkcs7Unpad(data) {
    if (!data.length) { return data; }
    var n = data[data.length - 1];
    if (n === 0 || n > 16) { return data; }
    return data.subarray(0, data.length - n);
  }
  function pkcs7Pad(data) {
    var n = 16 - (data.length % 16);
    var out = new Uint8Array(data.length + n);
    out.set(data);
    for (var i = data.length; i < out.length; i++) { out[i] = n; }
    return out;
  }
  function aesCbc(data, key, iv, decrypt) {
    var w = expandKey(toU8(key));
    var src = toU8(data);
    var prev = toU8(iv).slice(0, 16);
    if (prev.length < 16) {
      var ivp = new Uint8Array(16);
      ivp.set(prev);
      prev = ivp;
    }
    if (!decrypt) { src = pkcs7Pad(src); }
    var out = new Uint8Array(src.length);
    for (var off = 0; off < src.length; off += 16) {
      var block = src.subarray(off, off + 16);
      var work = new Uint8Array(16);
      if (!decrypt) {
        for (var i = 0; i < 16; i++) { work[i] = block[i] ^ prev[i]; }
        var enc = cryptBlock(work, w, false);
        out.set(enc, off);
        prev = enc;
      } else {
        var dec = cryptBlock(block, w, true);
        for (var j = 0; j < 16; j++) { out[off + j] = dec[j] ^ prev[j]; }
        prev = block.slice ? block.slice() : new Uint8Array(block);
      }
    }
    return decrypt ? pkcs7Unpad(out) : out;
  }
  if (!g.crypto) { g.crypto = {}; }
  if (!g.crypto.subtle) {
    g.crypto.subtle = {
      importKey: function (_fmt, keyData, algo) {
        return Promise.resolve({ _k: toU8(keyData), _a: algo });
      },
      decrypt: function (algo, key, data) {
        return Promise.resolve(aesCbc(data, key._k, algo.iv, true).buffer);
      },
      encrypt: function (algo, key, data) {
        return Promise.resolve(aesCbc(data, key._k, algo.iv, false).buffer);
      }
    };
  }
  if (typeof g.crypto.getRandomValues !== 'function') {
    g.crypto.getRandomValues = function (arr) {
      for (var i = 0; i < arr.length; i++) { arr[i] = Math.floor(Math.random() * 256); }
      return arr;
    };
  }

  // ---- Jsoup-ish node wrapper over nativeSelector JSON --------------------
  function absUrl(u, base) {
    try { return new g.URL(String(u), base || undefined).href; } catch (e) {
      return /^https?:\/\//i.test(String(u)) ? String(u) : '';
    }
  }
  function unquoteJsoup(t) {
    t = String(t || '').trim();
    if (t.length >= 2) {
      var a = t.charAt(0), b = t.charAt(t.length - 1);
      if ((a === '"' && b === '"') || (a === "'" && b === "'")) { return t.slice(1, -1); }
    }
    return t;
  }
  function splitCommaSelectors(sel) {
    var parts = [], buf = '', depth = 0;
    for (var i = 0; i < sel.length; i++) {
      var c = sel.charAt(i);
      if (c === '(') { depth++; }
      else if (c === ')') { depth--; }
      else if (c === ',' && depth === 0) {
        if (buf.trim()) { parts.push(buf.trim()); }
        buf = '';
        continue;
      }
      buf += c;
    }
    if (buf.trim()) { parts.push(buf.trim()); }
    return parts;
  }
  function extractJsoupPseudos(simple) {
    var contains = [], containsOwn = [];
    var eq = -1;
    var css = String(simple || '');
    css = css.replace(/:containsOwn\(([^)]*)\)/gi, function (_m, t) {
      containsOwn.push(unquoteJsoup(t));
      return '';
    });
    css = css.replace(/:contains\(([^)]*)\)/gi, function (_m, t) {
      contains.push(unquoteJsoup(t));
      return '';
    });
    css = css.replace(/:eq\((\d+)\)/g, function (_m, n) {
      eq = parseInt(n, 10);
      return '';
    });
    css = css.replace(/:matches(?:Own)?\([^)]*\)/gi, '');
    css = css.replace(/\s{2,}/g, ' ').trim();
    return { css: css || '*', contains: contains, containsOwn: containsOwn, eq: eq };
  }
  function parseSimple(simple) {
    var x = extractJsoupPseudos(simple);
    var bare = x.css.replace(/\[[^\]]*]/g, '');
    var tag = '*';
    var tm = bare.match(/^([a-zA-Z][\w:-]*)/);
    if (tm) { tag = tm[1].toLowerCase(); }
    var id = '';
    var idm = bare.match(/#([a-zA-Z][\w-]*)/);
    if (idm) { id = idm[1]; }
    var classes = [];
    var cre = /\.([a-zA-Z][\w-]*)/g, cm;
    while ((cm = cre.exec(bare))) { classes.push(cm[1]); }
    return {
      css: x.css, tag: tag, id: id, classes: classes, eq: x.eq,
      contains: x.contains, containsOwn: x.containsOwn,
      hasJsoup: x.contains.length > 0 || x.containsOwn.length > 0 || x.eq >= 0
    };
  }
  function tokenizeSelector(sel) {
    var tokens = [];
    var buf = '';
    var depth = 0;
    var comb = null;
    function pushSimple() {
      var s = buf.trim();
      buf = '';
      if (!s) { return; }
      tokens.push({ comb: comb, spec: parseSimple(s) });
    }
    for (var i = 0; i < sel.length; i++) {
      var c = sel.charAt(i);
      if (c === '(') { depth++; buf += c; continue; }
      if (c === ')') { depth--; buf += c; continue; }
      if (depth === 0 && (c === '+' || c === '>' || c === '~')) {
        pushSimple();
        comb = c;
        while (i + 1 < sel.length && sel.charAt(i + 1) === ' ') { i++; }
        continue;
      }
      if (depth === 0 && c === ' ') {
        while (i + 1 < sel.length && sel.charAt(i + 1) === ' ') { i++; }
        var next = i + 1 < sel.length ? sel.charAt(i + 1) : '';
        if (next === '+' || next === '>' || next === '~') { continue; }
        pushSimple();
        comb = ' ';
        continue;
      }
      buf += c;
    }
    pushSimple();
    return tokens;
  }
  function infoClass(info) {
    if (!info) { return ''; }
    if (info.className) { return String(info.className); }
    return info.attrs && info.attrs['class'] ? String(info.attrs['class']) : '';
  }
  function infoId(info) {
    if (!info) { return ''; }
    if (info.id) { return String(info.id); }
    return info.attrs && info.attrs.id ? String(info.attrs.id) : '';
  }
  function matchSimple(info, spec) {
    if (!info || !spec) { return false; }
    var tag = String(info.tag || '').toLowerCase();
    if (spec.tag && spec.tag !== '*' && tag !== spec.tag) { return false; }
    if (spec.id && infoId(info) !== spec.id) { return false; }
    var cls = ' ' + infoClass(info) + ' ';
    for (var i = 0; i < spec.classes.length; i++) {
      if (cls.indexOf(' ' + spec.classes[i] + ' ') < 0) { return false; }
    }
    var text = String(info.text || '').toLowerCase();
    for (var c = 0; c < spec.contains.length; c++) {
      if (text.indexOf(String(spec.contains[c]).toLowerCase()) < 0) { return false; }
    }
    var own = String(info.ownText || '').toLowerCase();
    for (var o = 0; o < spec.containsOwn.length; o++) {
      if (own.indexOf(String(spec.containsOwn[o]).toLowerCase()) < 0) { return false; }
    }
    return true;
  }
  function chainNeedsJsoup(tokens) {
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].spec.hasJsoup) { return true; }
    }
    return false;
  }
  function matchesChain(raw, tokens) {
    if (!tokens.length) { return true; }
    if (!chainNeedsJsoup(tokens)) { return true; }
    var parents = raw.parents || [];
    var parentIdx = 0;
    var ti = tokens.length - 1;
    if (!matchSimple(raw, tokens[ti].spec)) { return false; }
    while (ti > 0) {
      var comb = tokens[ti].comb;
      var want = tokens[ti - 1].spec;
      ti--;
      if (comb === '+' || comb === '~') {
        if (!matchSimple(raw.prev, want)) { return false; }
        continue;
      }
      var found = -1;
      var limit = comb === '>' ? Math.min(parentIdx + 1, parents.length) : parents.length;
      for (var p = parentIdx; p < limit; p++) {
        if (matchSimple(parents[p], want)) { found = p; break; }
      }
      if (found < 0) { return false; }
      parentIdx = found + 1;
    }
    return true;
  }
  function nativeCssFromTokens(tokens) {
    var out = '';
    for (var i = 0; i < tokens.length; i++) {
      if (i > 0) {
        var c = tokens[i].comb;
        out += (c === ' ' || !c) ? ' ' : (' ' + c + ' ');
      }
      out += tokens[i].spec.css;
    }
    return out.trim() || '*';
  }
  function attachListApi(list) {
    list.first = function () { return list.length ? list[0] : null; };
    list.last = function () { return list.length ? list[list.length - 1] : null; };
    list.isEmpty = function () { return list.length === 0; };
    return list;
  }
  function jsoupSelect(html, selector, baseUrl) {
    var parts = splitCommaSelectors(String(selector || ''));
    var out = [];
    for (var p = 0; p < parts.length; p++) {
      var tokens = tokenizeSelector(parts[p]);
      if (!tokens.length) { continue; }
      var css = nativeCssFromTokens(tokens);
      var hits = [];
      try { hits = g.querySelectorAll(String(html), css) || []; } catch (e) { hits = []; }
      var matched = [];
      for (var i = 0; i < hits.length; i++) {
        if (!matchesChain(hits[i], tokens)) { continue; }
        matched.push(wrapNode(hits[i], html, baseUrl, false));
      }
      var eq = tokens[tokens.length - 1].spec.eq;
      if (eq >= 0) {
        if (eq < matched.length) { out.push(matched[eq]); }
      } else {
        for (var m = 0; m < matched.length; m++) { out.push(matched[m]); }
      }
    }
    return attachListApi(out);
  }
  function wrapNode(raw, rootHtml, baseUrl, isDoc) {
    raw = raw || {};
    var base = baseUrl || '';
    return {
      attr: function (name) {
        name = String(name || '');
        if (name.indexOf('abs:') === 0) {
          return absUrl(this.attr(name.substring(4)), base);
        }
        if (!raw.attrs) { return ''; }
        var v = raw.attrs[name];
        if (v == null && name === 'src') {
          v = raw.attrs['data-src'] || raw.attrs['data-lazy-src'] || raw.attrs['data-cfsrc'] ||
            raw.attrs['data-manga-src'] || raw.attrs['data-original'] || '';
        }
        return v == null ? '' : String(v);
      },
      text: function () { return raw.text ? String(raw.text) : ''; },
      ownText: function () {
        if (raw.ownText != null && raw.ownText !== '') { return String(raw.ownText); }
        var h = raw.innerHtml ? String(raw.innerHtml) : '';
        return h.replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').trim();
      },
      html: function () { return raw.innerHtml ? String(raw.innerHtml) : ''; },
      outerHtml: function () { return raw.outerHtml ? String(raw.outerHtml) : ''; },
      tag: function () { return raw.tag ? String(raw.tag) : ''; },
      location: function () { return base; },
      absUrl: function (name) { return this.attr('abs:' + String(name || '')); },
      select: function (css) {
        var scope = isDoc ? String(rootHtml || '') : String(raw.outerHtml || '');
        return jsoupSelect(scope, css, base);
      },
      selectFirst: function (css) {
        var list = this.select(css);
        return list.length ? list[0] : null;
      }
    };
  }
  function wrapList(hits, rootHtml, baseUrl) {
    var out = [];
    if (!hits || !hits.length) { return attachListApi(out); }
    for (var i = 0; i < hits.length; i++) { out.push(wrapNode(hits[i], rootHtml, baseUrl, false)); }
    return attachListApi(out);
  }
  function wrapDocument(html, baseUrl) {
    var loc = String(baseUrl || '');
    var link = String(html || '').match(/<link\b[^>]*rel\s*=\s*["']canonical["'][^>]*>/i);
    if (link) {
      var href = link[0].match(/href\s*=\s*["']([^"']+)["']/i);
      if (href) { loc = absUrl(href[1], loc) || loc; }
    }
    return wrapNode({
      outerHtml: html, innerHtml: html, text: '', ownText: '', tag: '#root',
      attrs: {}, prev: {}, parents: []
    }, html, loc, true);
  }

  // ---- $ host DSL (original MihonHarmony plugin contract) -----------------
  function hasHeader(headers, name) {
    name = String(name).toLowerCase();
    for (var k in headers) {
      if (Object.prototype.hasOwnProperty.call(headers, k) && k.toLowerCase() === name) { return true; }
    }
    return false;
  }
  function httpRequest(url, options) {
    options = options || {};
    var method = String(options.method || 'GET').toUpperCase();
    var headers = {};
    var src = options.headers || {};
    for (var k in src) {
      if (Object.prototype.hasOwnProperty.call(src, k)) { headers[k] = src[k]; }
    }
    var body = options.body == null ? '' : String(options.body);
    if ((method === 'POST' || method === 'PUT') && body && !hasHeader(headers, 'Content-Type')) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    var r = g.fetch(url, { method: method, headers: headers, body: body });
    return {
      ok: r.ok,
      status: r.status,
      statusText: r.statusText,
      headers: r.headers || {},
      body: typeof r.text === 'function' ? r.text() : String(r.body == null ? '' : r.body),
      url: r.url || url
    };
  }
  g.$ = {
    http: {
      get: function (url, headers) {
        var r = httpRequest(url, { method: 'GET', headers: headers || {} });
        return r.body;
      },
      post: function (url, body, headers) {
        var r = httpRequest(url, { method: 'POST', headers: headers || {}, body: body == null ? '' : String(body) });
        return r.body;
      },
      request: function (url, options) {
        return httpRequest(url, options || {});
      },
      enqueue: function (url, options) {
        try { httpRequest(url, options || {}); } catch (e) { /* fire-and-forget */ }
      },
      getBytes: function (url, headers) {
        var r = g.fetchBytes(url, { method: 'GET', headers: headers || {} });
        return r.bytes;
      }
    },
    html: function (html, baseUrl) {
      return wrapDocument(html, baseUrl);
    },
    crypto: {
      base64Encode: function (s) { return g.btoa(s); },
      base64Decode: function (s) { return g.atob(s); },
      aesCbcDecrypt: function (data, key, iv) { return aesCbc(data, key, iv, true); },
      md5: function (s) { return md5hex(s); },
      md5Bytes: function (bytes) { return md5bin(toU8(bytes)); }
    }
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
