// Live-probe N generated plugins: getPopularManga -> detail -> chapters -> pages
// Usage: node tools/convert/probe.mjs <key1> [key2 ...]
import { loadPlugin } from './test_harness.mjs';

async function probe(key) {
  try {
    const { manifest, plugin } = loadPlugin(key);
    const t0 = Date.now();
    const page = await plugin.getPopularManga(1);
    const n = (page.mangas ?? []).length;
    if (n === 0) return `${key}: EMPTY (hasNext=${page.hasNextPage})`;
    let line = `${key}: OK ${n} mangas, hasNext=${page.hasNextPage}`;
    // deep probe first manga
    const m = page.mangas[0];
    const detail = await plugin.getMangaDetail(m.key);
    const chapters = await plugin.getChapterList(m.key);
    line += ` | detail(title=${detail.title ? 'y' : 'n'}) chapters=${(chapters ?? []).length}`;
    if ((chapters ?? []).length > 0) {
      const pages = await plugin.getPageList(chapters[chapters.length - 1].key);
      line += ` pages=${(pages ?? []).length}`;
    }
    return `${line} [${Date.now() - t0}ms]`;
  } catch (e) {
    return `${key}: FAIL ${e.message.slice(0, 120)}`;
  }
}

const keys = process.argv.slice(2);
for (const k of keys) {
  console.log(await probe(k));
}
