// rebuild standalone batch lists directly from the source repo
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { parseGradle } from './lib.mjs';

const SRC = 'D:\\project\\reference\\extensions-source-main\\src';
const langs = readdirSync(SRC).filter(d => statSync(join(SRC, d)).isDirectory() && /^[a-z]{2}(-[a-zA-Z0-9]+)?$|^[a-z]{3}$/.test(d));
const standalone = [];
const themeNoEngine = {};
for (const lang of langs) {
  const langDir = join(SRC, lang);
  for (const ext of readdirSync(langDir)) {
    const extDir = join(langDir, ext);
    if (!statSync(extDir).isDirectory()) continue;
    const g = join(extDir, 'build.gradle.kts');
    if (!existsSync(g)) continue;
    const meta = parseGradle(readFileSync(g, 'utf8'));
    if (meta.sources.length === 0 || meta.sources[0].baseUrl === '') continue;
    if (`${lang}/${ext}` === 'all/mangadex') continue;
    if (meta.theme === '') standalone.push(`${lang}/${ext}`);
    else if (!existsSync(join('D:/project/mihon/tools/convert/themes', `${meta.theme}.mjs`))) {
      themeNoEngine[meta.theme] = (themeNoEngine[meta.theme] ?? 0) + 1;
    }
  }
}
standalone.sort();
console.log('standalone (no theme):', standalone.length);
console.log('themes still without engine:', JSON.stringify(themeNoEngine));
const B = 11;
const per = Math.ceil(standalone.length / B);
for (let i = 0; i < B; i++) {
  const batch = standalone.slice(i * per, (i + 1) * per);
  if (!batch.length) continue;
  writeFileSync(`D:/project/mihon/tools/convert/standalone_batch_${i + 1}.txt`, batch.join('\n'));
  console.log(`batch ${i + 1}: ${batch.length} (${batch[0]} .. ${batch[batch.length - 1]})`);
}
