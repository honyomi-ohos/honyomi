// End-to-end smoke test for generated plugins outside the app.
// Simulates the app sandbox ($ DSL) using linkedom + fetch, runs plugin entry points live.
// Usage: node tools/convert/test_harness.mjs <key> [method] [argsJson]
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inflateRawSync } from 'node:zlib';
import { createHash, createHmac, createCipheriv, createDecipheriv, randomUUID as nodeRandomUUID } from 'node:crypto';
import { parseHTML, DOMParser } from 'linkedom';
import { RUNTIME_JS } from './lib.mjs';

const TOOLS_DIR = dirname(fileURLToPath(import.meta.url));
const GEN_DIR = join(TOOLS_DIR, '..', '..', 'plugins', 'gen', 'dist');

export function unzipOne(zipPath, name) {
  const buf = readFileSync(zipPath);
  // find EOCD
  let eocd = -1;
  for (let i = buf.length - 22; i >= 0; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('bad zip');
  const count = buf.readUInt16LE(eocd + 10);
  let off = buf.readUInt32LE(eocd + 16);
  for (let i = 0; i < count; i++) {
    const nameLen = buf.readUInt16LE(off + 28);
    const extraLen = buf.readUInt16LE(off + 30);
    const commentLen = buf.readUInt16LE(off + 32);
    const lho = buf.readUInt32LE(off + 42);
    const entryName = buf.toString('utf8', off + 46, off + 46 + nameLen);
    if (entryName === name) {
      const method = buf.readUInt16LE(lho + 8);
      const size = buf.readUInt32LE(lho + 18);
      const lNameLen = buf.readUInt16LE(lho + 26);
      const lExtraLen = buf.readUInt16LE(lho + 28);
      const dataStart = lho + 30 + lNameLen + lExtraLen;
      const data = buf.subarray(dataStart, dataStart + buf.readUInt32LE(lho + 18));
      return method === 8 ? inflateRawSync(data) : data;
    }
    off += 46 + nameLen + extraLen + commentLen;
  }
  throw new Error(`entry not found: ${name}`);
}

export function makeDollar(manifest) {
  const base = manifest.baseUrl;
  async function doFetch(url, opts) {
    const res = await fetch(url, opts);
    const text = await res.text();
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    return text;
  }
  function wrapNode(node) {
    if (!node) return null;
    return {
      select: (css) => Array.from(node.querySelectorAll(css)).map(wrapNode),
      selectFirst: (css) => wrapNode(node.querySelector(css)),
      attr: (name) => {
        const v = node.getAttribute && node.getAttribute(name);
        return v === null || v === undefined ? '' : String(v);
      },
      text: () => (node.textContent ? String(node.textContent).trim() : ''),
      html: () => (node.innerHTML ? String(node.innerHTML) : ''),
      absUrl: (name) => {
        const v = node.getAttribute && node.getAttribute(name);
        if (!v) return '';
        try { return new URL(v, base).href; } catch (e) { return /^https?:\/\//.test(v) ? v : ''; }
      },
    };
  }
  return {
    http: {
      get: (url, headers) => doFetch(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36', ...(headers ?? {}) } }),
      post: (url, body, headers) => doFetch(url, {
        method: 'POST',
        body,
        headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36', ...(headers ?? {}) },
      }),
    },
    html: {
      parse: (text, b) => {
        const doc = new DOMParser().parseFromString(String(text), 'text/html');
        return wrapNode(doc);
      },
    },
    json: JSON,
    log: { info: (m) => console.log('[plug]', m), error: (m) => console.error('[plug]', m) },
    prefs: { get: async () => '', set: async () => {} },
    crypto: {
      // signatures mirror plugin_host.html cryptoApi
      md5: (s) => createHash('md5').update(s, 'utf8').digest('hex'),
      sha1: async (s) => createHash('sha1').update(s, 'utf8').digest('hex'),
      sha256: async (s) => createHash('sha256').update(s, 'utf8').digest('hex'),
      sha512: async (s) => createHash('sha512').update(s, 'utf8').digest('hex'),
      hmacSha256: async (key, msg) => createHmac('sha256', Buffer.from(key, 'utf8')).update(msg, 'utf8').digest('hex'),
      aesCbcEncrypt: async (key, iv, plain) => {
        const kb = Buffer.from(key, 'utf8');
        const c = createCipheriv(`aes-${kb.length * 8}-cbc`, kb, Buffer.from(iv, 'utf8'));
        return Buffer.concat([c.update(Buffer.from(plain, 'utf8')), c.final()]).toString('base64');
      },
      aesCbcDecrypt: async (key, iv, dataB64) => {
        const kb = Buffer.from(key, 'utf8');
        const c = createDecipheriv(`aes-${kb.length * 8}-cbc`, kb, Buffer.from(iv, 'utf8'));
        return Buffer.concat([c.update(Buffer.from(dataB64, 'base64')), c.final()]).toString('utf8');
      },
      base64Encode: (s) => Buffer.from(s, 'utf8').toString('base64'),
      base64Decode: (b) => Buffer.from(b, 'base64').toString('utf8'),
      randomUUID: () => nodeRandomUUID(),
    },
    manifest,
  };
}

export function loadPlugin(key) {
  const zipPath = join(GEN_DIR, `${key}.mihonplug`);
  if (!existsSync(zipPath)) throw new Error(`no such plugin: ${key}`);
  const manifest = JSON.parse(unzipOne(zipPath, 'manifest.json').toString('utf8'));
  let mainJs = unzipOne(zipPath, 'main.js').toString('utf8');
  // simulate app-side composeScript: prepend shared runtime when declared
  if (manifest.runtime) mainJs = RUNTIME_JS.trim() + '\n;\n' + mainJs;
  const sandbox = {
    module: { exports: {} },
    console,
    TextEncoder, TextDecoder,
    URL, Date, JSON, RegExp, encodeURIComponent, decodeURIComponent, parseInt, parseFloat, isNaN, Array, Object, String, Number, Boolean, Math, Error, Promise, atob: (b) => Buffer.from(b, 'base64').toString('binary'),
    btoa: (s) => Buffer.from(s, 'binary').toString('base64'),
    // NOTE: keep $ (and $.crypto with base64Decode etc.) — bare `crypto` global is
    // passed to the script as a separate Function argument (mirrors WebView)
    ...makeDollar(manifest),
  };
  const fn = new Function('$', 'module', 'crypto', 'TextEncoder', 'TextDecoder', 'URL', 'atob', 'btoa', 'console', mainJs);
  fn(sandbox, sandbox.module, globalThis.crypto, TextEncoder, TextDecoder, URL, sandbox.atob, sandbox.btoa, console);
  return { manifest, plugin: sandbox.module.exports };
}

async function main() {
  const [key, method = 'getPopularManga', argsJson = '[1]'] = process.argv.slice(2);
  const { manifest, plugin } = loadPlugin(key);
  console.log(`plugin: ${manifest.name} (${manifest.key}) base=${manifest.baseUrl}`);
  const args = JSON.parse(argsJson);
  const t0 = Date.now();
  const result = await plugin[method](...args);
  console.log(`-> ${method}(${args.join(', ')}) in ${Date.now() - t0}ms`);
  console.log(JSON.stringify(result, null, 1).slice(0, 3000));
}

if (process.argv[1] && process.argv[1].endsWith('test_harness.mjs')) {
  main().catch(e => { console.error('FAIL:', e.message); process.exit(1); });
}
