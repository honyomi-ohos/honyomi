import { fileIo as fs } from '@kit.CoreFileKit';
import zlib from '@ohos.zlib';
import { SManga, SChapter, SPage, MangasPage } from '../model/Models';
import { Source } from './Source';

// 本地漫画源：扫描应用沙箱 local 目录下的漫画
// 目录结构：filesDir/local/<漫画名>/<章节名>.zip|.cbz 或 <章节名>/图片
export class LocalSource implements Source {
  readonly key = 'local';
  readonly name = '本地漫画';
  readonly lang = 'zh';
  readonly supportsLatest = false;

  private readonly rootDir: string;
  private readonly cacheDir: string;
  private readonly imageExts: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'];

  constructor(filesDir: string, cacheDir: string) {
    this.rootDir = `${filesDir}/local`;
    this.cacheDir = cacheDir;
    if (!fs.accessSync(this.rootDir)) {
      fs.mkdirSync(this.rootDir, true);
    }
  }

  async getPopularManga(page: number): Promise<MangasPage> {
    const names = this.listMangaDirs();
    const filtered = page === 1 ? names : [];
    const mangas: SManga[] = [];
    for (const name of filtered) {
      mangas.push(this.buildManga(name));
    }
    const result: MangasPage = { mangas: mangas, hasNextPage: false };
    return result;
  }

  async getSearchManga(page: number, query: string): Promise<MangasPage> {
    const names = this.listMangaDirs().filter((n: string): boolean => n.includes(query));
    const mangas: SManga[] = [];
    for (const name of names) {
      mangas.push(this.buildManga(name));
    }
    const result: MangasPage = { mangas: mangas, hasNextPage: false };
    return result;
  }

  async getMangaDetail(mangaKey: string): Promise<SManga> {
    return this.buildManga(mangaKey);
  }

  imageRequestHeaders(): Record<string, string> | undefined {
    return undefined;
  }

  async getChapterList(mangaKey: string): Promise<SChapter[]> {
    const dir = `${this.rootDir}/${mangaKey}`;
    const chapters: SChapter[] = [];
    if (!fs.accessSync(dir)) {
      return chapters;
    }
    const entries = fs.listFileSync(dir);
    let order = 0;
    const sorted = entries.sort((a: string, b: string): number => a.localeCompare(b, 'zh'));
    for (const entry of sorted) {
      const fullPath = `${dir}/${entry}`;
      if (this.isArchive(entry)) {
        chapters.push(this.buildChapter(mangaKey, entry, order));
        order += 1;
      } else if (fs.statSync(fullPath).isDirectory()) {
        const images = this.listImages(fullPath);
        if (images.length > 0) {
          chapters.push(this.buildChapter(mangaKey, entry, order));
          order += 1;
        }
      }
    }
    return chapters;
  }

  async getPageList(chapterKey: string): Promise<SPage[]> {
    // chapterKey 格式：<漫画目录名>::<章节条目名>
    const sepIdx = chapterKey.indexOf('::');
    if (sepIdx < 0) {
      throw new Error('章节标识无效');
    }
    const mangaDir = chapterKey.substring(0, sepIdx);
    const entry = chapterKey.substring(sepIdx + 2);
    const entryPath = `${this.rootDir}/${mangaDir}/${entry}`;
    if (!fs.accessSync(entryPath)) {
      throw new Error('章节文件不存在');
    }
    if (this.isArchive(entry)) {
      const files = await this.extractArchive(mangaDir, entry);
      return this.urlsToPages(files);
    }
    if (fs.statSync(entryPath).isDirectory()) {
      return this.urlsToPages(this.listImages(entryPath));
    }
    throw new Error('不支持的章节格式');
  }

  // 导入文件（来自文档选择器的 uri），复制进沙箱
  async importFiles(uris: string[], mangaTitle: string): Promise<number> {
    const destDir = `${this.rootDir}/${mangaTitle}`;
    if (!fs.accessSync(destDir)) {
      fs.mkdirSync(destDir, true);
    }
    let count = 0;
    for (const uri of uris) {
      const segs = uri.split('/');
      const rawName = segs.length > 0 ? segs[segs.length - 1] : `chapter_${count}.zip`;
      const fileName = decodeURIComponent(rawName);
      const destPath = `${destDir}/${fileName}`;
      if (fs.accessSync(destPath)) {
        continue;
      }
      const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        fs.copyFile(srcFile.fd, destPath);
        count += 1;
      } finally {
        fs.closeSync(srcFile);
      }
    }
    return count;
  }

  rootPath(): string {
    return this.rootDir;
  }

  private listMangaDirs(): string[] {
    if (!fs.accessSync(this.rootDir)) {
      return [];
    }
    const names: string[] = [];
    const entries = fs.listFileSync(this.rootDir);
    for (const entry of entries) {
      if (fs.statSync(`${this.rootDir}/${entry}`).isDirectory()) {
        names.push(entry);
      }
    }
    return names.sort((a: string, b: string): number => a.localeCompare(b, 'zh'));
  }

  private buildManga(dirName: string): SManga {
    const manga: SManga = {
      key: dirName,
      title: dirName,
      coverUrl: '',
      author: '',
      description: '本地导入的漫画',
      genre: '本地',
      status: 'local',
    };
    return manga;
  }

  private buildChapter(mangaDir: string, entry: string, order: number): SChapter {
    let dateUpload = 0;
    try {
      const stat = fs.statSync(`${this.rootDir}/${mangaDir}/${entry}`);
      dateUpload = stat.mtime * 1000;
    } catch (e) {
      dateUpload = 0;
    }
    let pages = 0;
    const dotIdx = entry.lastIndexOf('.');
    const name = dotIdx > 0 ? entry.substring(0, dotIdx) : entry;
    const chapter: SChapter = {
      key: `${mangaDir}::${entry}`,
      name: name,
      chapterNumber: -1,
      dateUpload: dateUpload,
      pages: pages,
      sortOrder: order,
    };
    return chapter;
  }

  private isArchive(name: string): boolean {
    const lower = name.toLowerCase();
    return lower.endsWith('.zip') || lower.endsWith('.cbz');
  }

  // 列出目录下的图片（自然排序）
  private listImages(dir: string): string[] {
    const files: string[] = [];
    const entries = fs.listFileSync(dir);
    for (const entry of entries) {
      const lower = entry.toLowerCase();
      if (this.imageExts.some((ext: string): boolean => lower.endsWith(ext))) {
        files.push(`${dir}/${entry}`);
      }
    }
    return files.sort((a: string, b: string): number => a.localeCompare(b, 'zh', { numeric: true }));
  }

  private async extractArchive(mangaDir: string, entry: string): Promise<string[]> {
    const zipPath = `${this.rootDir}/${mangaDir}/${entry}`;
    const safeEntry = entry.replace(new RegExp('\\.(zip|cbz)$', 'i'), '');
    const outDir = `${this.cacheDir}/local_extract/${mangaDir}/${safeEntry}`;
    if (!fs.accessSync(outDir)) {
      fs.mkdirSync(outDir, true);
    }
    // 已解压过则直接复用（通过标记文件判断）
    const doneFlag = `${outDir}/.extracted`;
    if (!fs.accessSync(doneFlag)) {
      await zlib.decompressFile(zipPath, outDir);
      const flagFile = fs.openSync(doneFlag, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(flagFile.fd, 'ok');
      fs.closeSync(flagFile);
    }
    // 递归收集图片
    const result: string[] = [];
    this.collectImages(outDir, result);
    return result.sort((a: string, b: string): number => a.localeCompare(b, 'zh', { numeric: true }));
  }

  private collectImages(dir: string, out: string[]): void {
    const entries = fs.listFileSync(dir);
    for (const entry of entries) {
      const fullPath = `${dir}/${entry}`;
      const lower = entry.toLowerCase();
      if (this.imageExts.some((ext: string): boolean => lower.endsWith(ext))) {
        out.push(fullPath);
      } else if (fs.statSync(fullPath).isDirectory() && entry !== '.extracted') {
        this.collectImages(fullPath, out);
      }
    }
  }

  private urlsToPages(files: string[]): SPage[] {
    const pages: SPage[] = [];
    for (let i = 0; i < files.length; i++) {
      const page: SPage = { index: i, url: `file://${files[i]}` };
      pages.push(page);
    }
    return pages;
  }
}
