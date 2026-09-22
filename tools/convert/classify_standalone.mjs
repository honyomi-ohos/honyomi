// classify standalone by the class that implements popularManga*
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
const SRC = 'D:/project/reference/extensions-source-main/src';
const r = JSON.parse(readFileSync('D:/project/mihon/tools/convert/report.json', 'utf8'));
const standalone = r.skipped.filter(s => s.theme === '(standalone)').map(s => s.ext);
const classes = {};
const byClass = {};
for (const ext of standalone) {
  const extDir = join(SRC, ext);
  const files = [];
  const walk = (d) => {
    for (const n of readdirSync(d)) {
      const p = join(d, n);
      if (statSync(p).isDirectory()) walk(p);
      else if (n.endsWith('.kt')) files.push(p);
    }
  };
  try { walk(join(extDir, 'src')); } catch { continue; }
  let cls = '(no-src)';
  for (const f of files) {
    const t = readFileSync(f, 'utf8');
    if (!/popularManga(Request|Parse|1)?\s*\(|override\s+val\s+id/.test(t)) continue;
    const cm = t.match(/(?:^|\n)(?:\w+\s+)?class\s+\w+(?:\([^)]*\))?\s*:\s*([\w.]+)/);
    if (cm) { cls = cm[1].split('.').pop(); break; }
    if (/ParsedHttpSource\s*\(/.test(t)) { cls = 'ParsedHttpSource'; break; }
    if (/HttpSource\s*\(/.test(t)) { cls = 'HttpSource'; break; }
  }
  classes[cls] = (classes[cls] ?? 0) + 1;
  (byClass[cls] ??= []).push(ext);
}
for (const [k, v] of Object.entries(classes).sort((a, b) => b[1] - a[1])) {
  console.log(`${v}\t${k}`);
  console.log('   ', (byClass[k] ?? []).slice(0, 18).join(' '));
}
