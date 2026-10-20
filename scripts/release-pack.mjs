#!/usr/bin/env node
/*
.release-pack.mjs — Build the release package with an arm64-only torrent HSP.

entry/libs/torrent-default.tgz ships both ABIs (arm64-v8a + x86_64) so other
developers can debug on x86_64 emulators. hvigor packs a prebuilt integrated
HSP verbatim (no abiFilters), so this script:
  1. derives an arm64-only copy of the tgz (drops libs/x86_64 and the HSP's
     libc++_shared.so, which is provided by the entry HAP)
  2. swaps it in and runs ohpm install
  3. builds release (devecocli or hvigorw, if found on PATH)
  4. restores the dual-ABI tgz and reinstalls (dev state)

Zero npm dependencies: tar/gzip/zip handled via Node built-ins.

Usage:
  node scripts/release-pack.mjs                 # full flow
  node scripts/release-pack.mjs --skip-build    # package ops only
  node scripts/release-pack.mjs --keep-stripped # leave arm64-only in place
                                                # (backup: entry/libs/torrent-default.tgz.bak)
  node scripts/release-pack.mjs --restore       # restore dual-ABI from backup

Only Node.js is required (bundled with the HarmonyOS SDK / DevEco Studio).
*/
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const TGZ = path.join(ROOT, 'entry', 'libs', 'torrent-default.tgz');
const BAK = TGZ + '.bak';

const args = new Set(process.argv.slice(2));
const SKIP_BUILD = args.has('--skip-build');
const KEEP_STRIPPED = args.has('--keep-stripped');
const RESTORE_ONLY = args.has('--restore');

// ---------------------------------------------------------------- tar (ustar)

function readStr(buf, off, len) {
  let end = off;
  const max = Math.min(off + len, buf.length);
  while (end < max && buf[end] !== 0) end++;
  return buf.toString('latin1', off, end);
}

function readOct(buf, off, len) {
  const s = readStr(buf, off, len).replace(/[\s]/g, '');
  return s === '' ? 0 : parseInt(s, 8);
}

function parseTar(buf) {
  const entries = [];
  let off = 0;
  let longName = null;
  let paxPath = null;
  while (off + 512 <= buf.length) {
    const h = buf.subarray(off, off + 512);
    if (h[0] === 0 && !h.some(b => b !== 0)) break;
    const name = readStr(h, 0, 100);
    const size = readOct(h, 124, 12);
    const mtime = readOct(h, 136, 12);
    const type = String.fromCharCode(h[156] || 0x30);
    const prefix = readStr(h, 345, 155);
    off += 512;
    const data = buf.subarray(off, off + size);
    off += Math.ceil(size / 512) * 512;
    if (type === 'L') { longName = readStr(data, 0, data.length); continue; }
    if (type === 'x' || type === 'g') {
      const m = /(^|\n)\d+ path=([^\n]*)/.exec(data.toString('utf8'));
      if (type === 'x' && m) paxPath = m[2];
      continue;
    }
    if (type === '0' || type === '\0') {
      const full = longName || paxPath || (prefix ? prefix + '/' + name : name);
      entries.push({ name: full, data: Buffer.from(data), mtime });
    }
    longName = null;
    paxPath = null;
  }
  return entries;
}

function oct(n, len) {
  return n.toString(8).padStart(len, '0');
}

function buildTar(entries) {
  const chunks = [];
  for (const e of entries) {
    if (e.name.length > 99) throw new Error(`tar name too long: ${e.name}`);
    const h = Buffer.alloc(512);
    h.write(e.name, 0, 'latin1');
    h.write(oct(0o644, 7) + '\0', 100, 'latin1');
    h.write('0000000\0', 108, 'latin1');
    h.write('0000000\0', 116, 'latin1');
    h.write(oct(e.data.length, 11) + '\0', 124, 'latin1');
    h.write(oct(Math.floor(e.mtime), 11) + '\0', 136, 'latin1');
    h.write('        ', 148, 'latin1');
    h.write('0', 156, 'latin1');
    h.write('ustar\0', 257, 'latin1');
    h.write('00', 263, 'latin1');
    const sum = h.reduce((a, b) => a + b, 0);
    h.write(oct(sum, 6) + '\0 ', 148, 'latin1');
    const pad = Math.ceil(e.data.length / 512) * 512 - e.data.length;
    chunks.push(h, e.data, Buffer.alloc(pad));
  }
  chunks.push(Buffer.alloc(1024));
  return Buffer.concat(chunks);
}

// ---------------------------------------------------------------- zip (store)

function parseZip(buf) {
  let eocd = -1;
  const min = Math.max(0, buf.length - 22 - 65536);
  for (let i = buf.length - 22; i >= min; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('zip: EOCD not found');
  const count = buf.readUInt16LE(eocd + 10);
  let off = buf.readUInt32LE(eocd + 16);
  const entries = [];
  for (let i = 0; i < count; i++) {
    if (buf.readUInt32LE(off) !== 0x02014b50) throw new Error('zip: bad central directory');
    const method = buf.readUInt16LE(off + 10);
    const time = buf.readUInt16LE(off + 12);
    const date = buf.readUInt16LE(off + 14);
    const crc = buf.readUInt32LE(off + 16);
    const csize = buf.readUInt32LE(off + 20);
    const nameLen = buf.readUInt16LE(off + 28);
    const extraLen = buf.readUInt16LE(off + 30);
    const commentLen = buf.readUInt16LE(off + 32);
    const lho = buf.readUInt32LE(off + 42);
    const name = buf.toString('utf8', off + 46, off + 46 + nameLen);
    const dataOff = lho + 30 + buf.readUInt16LE(lho + 26) + buf.readUInt16LE(lho + 28);
    const raw = buf.subarray(dataOff, dataOff + csize);
    const data = method === 0 ? Buffer.from(raw) : zlib.inflateRawSync(raw);
    entries.push({ name, data, crc, time, date });
    off += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

let CRC_TABLE = null;
function crc32(buf) {
  if (!CRC_TABLE) {
    CRC_TABLE = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      CRC_TABLE[n] = c;
    }
  }
  let crc = -1;
  for (let i = 0; i < buf.length; i++) crc = CRC_TABLE[(crc ^ buf[i]) & 0xFF] ^ (crc >>> 8);
  return (crc ^ -1) >>> 0;
}

function buildStoreZip(entries) {
  const parts = [];
  const central = [];
  let offset = 0;
  for (const e of entries) {
    const nameB = Buffer.from(e.name, 'utf8');
    const crc = e.crc !== undefined ? e.crc : crc32(e.data);
    const size = e.data.length;
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0);
    lh.writeUInt16LE(20, 4);
    lh.writeUInt16LE(0x0800, 6);
    lh.writeUInt16LE(0, 8);
    lh.writeUInt16LE(e.time ?? 0, 10);
    lh.writeUInt16LE(e.date ?? 0, 12);
    lh.writeUInt32LE(crc, 14);
    lh.writeUInt32LE(size, 18);
    lh.writeUInt32LE(size, 22);
    lh.writeUInt16LE(nameB.length, 26);
    lh.writeUInt16LE(0, 28);
    parts.push(lh, nameB, e.data);
    const ch = Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50, 0);
    ch.writeUInt16LE(20, 4);
    ch.writeUInt16LE(20, 6);
    ch.writeUInt16LE(0x0800, 8);
    ch.writeUInt16LE(0, 10);
    ch.writeUInt16LE(e.time ?? 0, 12);
    ch.writeUInt16LE(e.date ?? 0, 14);
    ch.writeUInt32LE(crc, 16);
    ch.writeUInt32LE(size, 20);
    ch.writeUInt32LE(size, 24);
    ch.writeUInt16LE(nameB.length, 28);
    ch.writeUInt32LE(offset, 42);
    central.push(ch, nameB);
    offset += 30 + nameB.length + size;
  }
  const cd = Buffer.concat(central);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(cd.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, cd, eocd]);
}

// ---------------------------------------------------------------- strip logic

function makeStrippedTgz(tgzBuf) {
  const tarEntries = parseTar(zlib.gunzipSync(tgzBuf));
  const out = [];
  let sawHsp = false;
  for (const entry of tarEntries) {
    if (entry.name === 'torrent-default.hsp') {
      sawHsp = true;
      const zipped = parseZip(entry.data).filter(e =>
        !e.name.startsWith('libs/x86_64/') && e.name !== 'libs/arm64-v8a/libc++_shared.so');
      out.push({ name: entry.name, data: buildStoreZip(zipped), mtime: entry.mtime });
    } else if (entry.name === 'torrent.har') {
      const har = parseTar(zlib.gunzipSync(entry.data)).filter(e =>
        !e.name.startsWith('package/libs/x86_64/') &&
        e.name !== 'package/libs/arm64-v8a/libc++_shared.so');
      out.push({ name: entry.name, data: zlib.gzipSync(buildTar(har)), mtime: entry.mtime });
    } else {
      out.push(entry);
    }
  }
  if (!sawHsp) throw new Error('torrent-default.hsp not found in tgz');
  return zlib.gzipSync(buildTar(out));
}

// ---------------------------------------------------------------- toolchain

function run(cmd, cwd) {
  const r = spawnSync(cmd, { cwd: cwd || ROOT, stdio: 'inherit', shell: true });
  return r.status === 0;
}

function onPath(cmd) {
  const probe = process.platform === 'win32' ? `where ${cmd}` : `command -v ${cmd}`;
  return spawnSync(probe, { shell: true, stdio: 'ignore' }).status === 0;
}

function findOhpm() {
  const isWin = process.platform === 'win32';
  const ext = isWin ? '.bat' : '';
  const candidates = [];
  if (process.env.DEVECO_HOME) {
    candidates.push(path.join(process.env.DEVECO_HOME, 'tools', 'ohpm', 'bin', 'ohpm' + ext));
  }
  if (isWin) {
    candidates.push('C:\\Program Files\\Huawei\\DevEco Studio\\tools\\ohpm\\bin\\ohpm.bat');
  } else {
    candidates.push('/Applications/DevEco Studio.app/Contents/tools/ohpm/bin/ohpm');
    candidates.push(process.env.HOME ? path.join(process.env.HOME, 'command-line-tools', 'tools', 'ohpm', 'bin', 'ohpm') : '');
  }
  for (const c of candidates) {
    if (c && fs.existsSync(c)) return c;
  }
  if (onPath('ohpm')) return 'ohpm';
  return null;
}

function findBuildCmd() {
  if (onPath('devecocli')) return 'devecocli build --build-mode release';
  if (onPath('hvigorw')) return 'hvigorw assembleHap --mode module -p product=default -p buildMode=release';
  return null;
}

const mb = b => (b.length / 1024 / 1024).toFixed(2);

// ---------------------------------------------------------------- main

function ohpmInstall(ohpm) {
  return run(`"${ohpm}" install --all`);
}

function restoreBackup() {
  if (!fs.existsSync(BAK)) {
    console.log('[restore] no backup found, nothing to do');
    return false;
  }
  fs.copyFileSync(BAK, TGZ);
  fs.rmSync(BAK);
  console.log('[restore] dual-ABI tgz restored');
  return true;
}

function main() {
  if (RESTORE_ONLY) {
    if (!restoreBackup()) return 0;
    const ohpm = findOhpm();
    if (!ohpm) throw new Error('ohpm not found (DEVECO_HOME / PATH)');
    if (!ohpmInstall(ohpm)) throw new Error('ohpm install failed');
    console.log('Done.');
    return 0;
  }
  if (!fs.existsSync(TGZ)) throw new Error(`not found: ${TGZ}`);

  const ohpm = findOhpm();
  if (!ohpm) throw new Error('ohpm not found (DEVECO_HOME / PATH)');

  const full = fs.readFileSync(TGZ);
  console.log('[1/4] Deriving arm64-only tgz ...');
  const stripped = makeStrippedTgz(full);
  console.log(`      ${mb(full)} MB -> ${mb(stripped)} MB`);

  fs.copyFileSync(TGZ, BAK);
  try {
    fs.writeFileSync(TGZ, stripped);
    console.log('[2/4] ohpm install (arm64-only) ...');
    if (!ohpmInstall(ohpm)) throw new Error('ohpm install failed');

    if (SKIP_BUILD) {
      console.log('[3/4] --skip-build set, skipping build');
    } else {
      const build = findBuildCmd();
      if (!build) {
        console.log('[3/4] no build command found (devecocli / hvigorw), skipping build.');
        console.log('      To build manually: rerun with --keep-stripped, build in DevEco Studio,');
        console.log('      then run: node scripts/release-pack.mjs --restore');
      } else {
        console.log(`[3/4] Building release (${build.split(' ')[0]}) ...`);
        if (!run(build)) throw new Error('release build failed');
      }
    }
  } catch (e) {
    if (!KEEP_STRIPPED) {
      console.log('[!] failed, restoring dual-ABI tgz ...');
      restoreBackup();
      ohpmInstall(ohpm);
    }
    throw e;
  }

  if (KEEP_STRIPPED) {
    console.log('[4/4] --keep-stripped: arm64-only tgz left in place.');
    console.log(`      Backup: ${BAK}`);
    console.log('      Restore later with: node scripts/release-pack.mjs --restore');
  } else {
    console.log('[4/4] Restoring dual-ABI tgz and reinstalling ...');
    restoreBackup();
    if (!ohpmInstall(ohpm)) throw new Error('ohpm install failed');
  }
  console.log('Done.');
  return 0;
}

try {
  process.exit(main());
} catch (e) {
  console.error(`ERROR: ${e.message}`);
  process.exit(1);
}
