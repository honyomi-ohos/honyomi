// Batch converter: keiyoushi/extensions-source -> MihonHarmony .mihonplug plugins
// Usage: node tools/convert/convert_ext.mjs [--lang=zh] [--theme=madara] [--out=plugins/gen] [--src=D:\project\reference\extensions-source-main]
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, statSync, copyFileSync, unlinkSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { makeZip } from './zip.mjs';
import { parseGradle, readText, sanitizeKey, pluginKey, findIcon, RUNTIME_JS, TOOLS_DIR } from './lib.mjs';

const PROJECT_ROOT = join(TOOLS_DIR, '..', '..');
const args = new Map(process.argv.slice(2).map(a => {
  const m = a.match(/^--([^=]+)=(.*)$/);
  return m ? [m[1], m[2]] : [a.replace(/^--/, ''), true];
}));
const SRC = args.get('src') ?? 'D:\\project\\reference\\extensions-source-main\\src';
const OUT = join(PROJECT_ROOT, args.get('out') ?? 'plugins\\gen');
const ONLY_LANG = args.get('lang') ?? null;
const ONLY_THEME = args.get('theme') ?? null;
const ONLY_EXT = args.get('ext') ?? null;
const NO_CHECK = args.get('no-check') === true;
const EXCLUDE_EXT = new Set(['all/mangadex']);
const STANDALONE_DIR = join(TOOLS_DIR, 'standalone');
const standaloneModules = new Map();

// standalone extensions get per-source engines from tools/convert/standalone/<key>.mjs
// (key = pluginKey style: <lang>_<ext>, or bare <ext> for multi/'all' sources)
async function preloadStandalone() {
  if (!existsSync(STANDALONE_DIR)) return;
  for (const f of readdirSync(STANDALONE_DIR)) {
    if (!f.endsWith('.mjs') || f.startsWith('_')) continue;
    const p = join(STANDALONE_DIR, f);
    try {
      standaloneModules.set(f.slice(0, -4), await import(pathToFileURL(p).href));
    } catch (e) {
      console.error(`standalone import failed: ${f}: ${e.message}`);
    }
  }
}

function standaloneModule(lang, ext) {
  const candidates = [pluginKey(lang, ext), sanitizeKey(ext), pluginKey(ext, ext)];
  for (const name of candidates) {
    const mod = standaloneModules.get(name);
    if (mod) return mod;
  }
  return null;
}

// pre-load all theme modules (dynamic import at top level)
const preloadedThemes = new Map();
async function preloadThemes() {
  const dir = join(TOOLS_DIR, 'themes');
  for (const f of readdirSync(dir)) {
    if (f.endsWith('.mjs') && !f.startsWith('_')) {
      const p = join(dir, f);
      try {
        preloadedThemes.set(pathToFileURL(p).href, await import(pathToFileURL(p).href));
      } catch (e) {
        console.error(`theme import failed: ${f}: ${e.message}`);
      }
    }
  }
}
const themeNameToFile = new Map();
function themeModule(name) {
  if (themeNameToFile.has(name)) return preloadedThemes.get(themeNameToFile.get(name)) ?? null;
  return null;
}

function readKtSources(extDir) {
  const srcDir = join(extDir, 'src');
  if (!existsSync(srcDir)) return '';
  let out = '';
  const walk = (d) => {
    for (const name of readdirSync(d)) {
      const p = join(d, name);
      if (statSync(p).isDirectory()) walk(p);
      else if (name.endsWith('.kt')) out += readText(p) + '\n';
    }
  };
  walk(srcDir);
  return out;
}

function nodeSyntaxCheck(js, key) {
  const tmp = join(TOOLS_DIR, `_check_${key}.js`);
  writeFileSync(tmp, js);
  try {
    const r = spawnSync('node', ['--check', tmp], { encoding: 'utf8' });
    return r.status === 0 ? null : (r.stderr || 'syntax error').slice(0, 500);
  } finally {
    unlinkSync(tmp);
  }
}

async function main() {
  await preloadThemes();
  await preloadStandalone();
  const themesDir = join(TOOLS_DIR, 'themes');
  for (const f of readdirSync(themesDir)) {
    if (f.endsWith('.mjs') && !f.startsWith('_')) {
      themeNameToFile.set(f.slice(0, -4), pathToFileURL(join(themesDir, f)).href);
    }
  }

  if (!existsSync(OUT)) mkdirSync(OUT, { recursive: true });
  // cleanup legacy flat zips from older converter runs (zips now live in OUT/dist)
  for (const f of readdirSync(OUT)) {
    if (f.endsWith('.mihonplug')) unlinkSync(join(OUT, f));
  }
  const runtimesUsed = new Set();
  const srcRoot = SRC;
  const langs = readdirSync(srcRoot).filter(d => {
    const p = join(srcRoot, d);
    return statSync(p).isDirectory() && d !== '.git' && /^[a-z]{2}(-[a-zA-Z0-9]+)?$|^[a-z]{3}$/.test(d);
  });
  const indexEntries = [];
  const report = { converted: [], skipped: [] };
  let dupGuard = new Set();

  for (const lang of langs) {
    if (ONLY_LANG && lang !== ONLY_LANG) continue;
    const langDir = join(srcRoot, lang);
    for (const ext of readdirSync(langDir)) {
      const extDir = join(langDir, ext);
      if (!statSync(extDir).isDirectory()) continue;
      const gradlePath = join(extDir, 'build.gradle.kts');
      if (!existsSync(gradlePath)) { report.skipped.push({ ext: `${lang}/${ext}`, reason: 'no build.gradle.kts' }); continue; }
      let meta;
      try {
        meta = parseGradle(readText(gradlePath));
      } catch (e) {
        report.skipped.push({ ext: `${lang}/${ext}`, reason: `gradle parse: ${e.message}` });
        continue;
      }
      meta.extName = ext;
      if (ONLY_EXT && `${lang}/${ext}` !== ONLY_EXT) continue;
      // hand-written plugin exists; never auto-convert its upstream ext
      if (EXCLUDE_EXT.has(`${lang}/${ext}`)) {
        report.skipped.push({ ext: `${lang}/${ext}`, reason: 'excluded (hand-written plugin exists)' });
        continue;
      }
      const sources = meta.sources;
      if (sources.length === 0 || sources[0].baseUrl === '') {
        report.skipped.push({ ext: `${lang}/${ext}`, reason: 'no source baseUrl' });
        continue;
      }
      const theme = meta.theme;
      if (ONLY_THEME && theme !== ONLY_THEME) continue;
      const mod = theme ? themeModule(theme) : standaloneModule(lang, ext);
      if (!mod) {
        report.skipped.push({ ext: `${lang}/${ext}`, theme: theme || '(standalone)', reason: 'no engine for theme' });
        continue;
      }

      const forEachMulti = /forEach\s*\{[\s\S]*?source\s*\{/.test(readText(gradlePath));
      const multi = sources.length > 1 || forEachMulti;
      const src0 = sources[0];
      const manifestLang = multi ? 'multi' : (src0.lang || lang);
      const dispName = src0.name || meta.name || ext;
      let key = multi ? sanitizeKey(ext) : pluginKey(manifestLang === 'multi' ? lang : manifestLang, ext);
      if (dupGuard.has(key)) key = `${key}_${sanitizeKey(lang)}`;
      if (dupGuard.has(key)) continue;
      dupGuard.add(key);

      const ktText = readKtSources(extDir);
      let ex;
      try {
        ex = mod.extract({ gradle: meta, ktText, theme, extName: ext, extDir });
      } catch (e) {
        report.skipped.push({ ext: `${lang}/${ext}`, theme, reason: `extract: ${e.message}` });
        continue;
      }
      if (!ex || ex.ok !== true) {
        report.skipped.push({ ext: `${lang}/${ext}`, theme, reason: ex && ex.reason ? ex.reason : 'extract failed' });
        continue;
      }

      const versionCode = Math.max(1, meta.versionCode || 1);
      const manifest = {
        key,
        name: dispName,
        lang: manifestLang,
        version: `1.0.${versionCode}`,
        versionCode,
        baseUrl: src0.baseUrl,
        nsfw: meta.contentWarning === 'NSFW',
        supportsLatest: true,
        minAppVersion: 1,
        dslVersion: 1,
      };
      if (mod.runtime) { manifest.runtime = mod.runtime; runtimesUsed.add(mod.runtime); }
      const iconPath = findIcon(extDir);
      if (iconPath) manifest.icon = 'icon.png';

      let mainJs;
      try {
        mainJs = mod.generate(manifest, ex.config);
      } catch (e) {
        report.skipped.push({ ext: `${lang}/${ext}`, theme, reason: `generate: ${e.message}` });
        continue;
      }
      if (!NO_CHECK) {
        const err = nodeSyntaxCheck(mainJs, key);
        if (err) {
          report.skipped.push({ ext: `${lang}/${ext}`, theme, reason: `syntax: ${err}` });
          continue;
        }
      }

      // maintainable source folder (like plugins/mangadex/) + packaged zip in dist/
      const pluginDir = join(OUT, key);
      mkdirSync(pluginDir, { recursive: true });
      writeFileSync(join(pluginDir, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
      writeFileSync(join(pluginDir, 'main.js'), mainJs);
      const files = [
        { name: 'manifest.json', data: Buffer.from(JSON.stringify(manifest, null, 2), 'utf8') },
        { name: 'main.js', data: Buffer.from(mainJs, 'utf8') },
      ];
      if (iconPath) {
        copyFileSync(iconPath, join(pluginDir, 'icon.png'));
        files.push({ name: 'icon.png', data: readFileSync(iconPath) });
      }
      const distDir = join(OUT, 'dist');
      if (!existsSync(distDir)) mkdirSync(distDir, { recursive: true });
      writeFileSync(join(distDir, `${key}.mihonplug`), makeZip(files));
      indexEntries.push({
        key, name: dispName, lang: manifestLang, version: manifest.version,
        versionCode, file: `gen/dist/${key}.mihonplug`, nsfw: manifest.nsfw,
      });
      report.converted.push({ key, ext: `${lang}/${ext}`, theme, warnings: ex.warnings ?? [] });
    }
  }

  // sync shared runtimes into app rawfile (single source of truth: lib.mjs RUNTIME_JS)
  for (const name of runtimesUsed) {
    if (name !== 'wp') continue;
    const rawfile = join(PROJECT_ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', `plugin_runtime_${name}.js`);
    writeFileSync(rawfile, RUNTIME_JS.trim() + '\n');
    console.log(`runtime synced: plugin_runtime_${name}.js -> entry/src/main/resources/rawfile/`);
  }

  // merge with existing hand-written plugins (mangadex) into repo root index
  const repoIndex = { plugins: [] };
  const mdDir = join(PROJECT_ROOT, 'plugins', 'mangadex');
  if (existsSync(mdDir)) {
    const mdManifest = JSON.parse(readText(join(mdDir, 'manifest.json')));
    const mdIconRef = 'D:\\project\\reference\\extensions-source-main\\src\\all\\mangadex\\res\\mipmap-xxxhdpi\\ic_launcher.png';
    const mdFiles = [
      { name: 'manifest.json', data: Buffer.from(readText(join(mdDir, 'manifest.json')), 'utf8') },
      { name: 'main.js', data: Buffer.from(readText(join(mdDir, 'main.js')), 'utf8') },
    ];
    if (existsSync(mdIconRef)) {
      mdFiles.push({ name: 'icon.png', data: readFileSync(mdIconRef) });
      const m = JSON.parse(readText(join(mdDir, 'manifest.json')));
      m.icon = 'icon.png';
      mdFiles[0] = { name: 'manifest.json', data: Buffer.from(JSON.stringify(m, null, 2), 'utf8') };
      mdManifest.icon = 'icon.png';
    }
    writeFileSync(join(PROJECT_ROOT, 'plugins', 'mangadex.mihonplug'), makeZip(mdFiles));
    repoIndex.plugins.push({
      key: mdManifest.key, name: mdManifest.name, lang: mdManifest.lang,
      version: mdManifest.version, versionCode: mdManifest.versionCode,
      file: 'mangadex.mihonplug', nsfw: mdManifest.nsfw === true,
    });
  }
  repoIndex.plugins = repoIndex.plugins.concat(indexEntries);
  writeFileSync(join(PROJECT_ROOT, 'plugins', 'index.json'), JSON.stringify(repoIndex, null, 2));
  writeFileSync(join(TOOLS_DIR, 'report.json'), JSON.stringify(report, null, 2));

  const themeCount = {};
  for (const c of report.converted) themeCount[c.theme] = (themeCount[c.theme] ?? 0) + 1;
  console.log(`converted: ${report.converted.length}`);
  for (const t of Object.keys(themeCount).sort((a, b) => themeCount[b] - themeCount[a])) {
    console.log(`  ${t}: ${themeCount[t]}`);
  }
  const skipByReason = {};
  for (const s of report.skipped) {
    const r = s.theme ? `${s.theme}: ${s.reason}` : s.reason;
    skipByReason[r] = (skipByReason[r] ?? 0) + 1;
  }
  console.log(`skipped: ${report.skipped.length}`);
  for (const r of Object.keys(skipByReason).sort((a, b) => skipByReason[b] - skipByReason[a]).slice(0, 30)) {
    console.log(`  ${skipByReason[r]}x ${r}`);
  }
}

main().catch(e => { console.error(e); process.exit(1); });
