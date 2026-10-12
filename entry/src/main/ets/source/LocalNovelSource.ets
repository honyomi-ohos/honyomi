import { fileIo as fs } from '@kit.CoreFileKit';
import { SManga, SChapter, SPage, SVideo, MangasPage, ContentType } from '../model/Models';
import { Source } from './Source';

// 本地小说：filesDir/local_novel/<书名>/*.txt，一个文件一章
export class LocalNovelSource implements Source {
  readonly key = 'local_novel';
  readonly name = '本地小说';
  readonly lang = 'zh';
  readonly supportsLatest = false;
  readonly contentType = ContentType.NOVEL;

  private readonly rootDir: string;

  constructor(filesDir: string) {
    this.rootDir = `${filesDir}/local_novel`;
    if (!fs.accessSync(this.rootDir)) {
      fs.mkdirSync(this.rootDir, true);
    }
  }

  async getPopularManga(page: number): Promise<MangasPage> {
    const names = page === 1 ? this.listDirs() : [];
    const mangas: SManga[] = [];
    for (const name of names) {
      mangas.push(this.buildManga(name));
    }
    const result: MangasPage = { mangas: mangas, hasNextPage: false };
    return result;
  }

  async getLatestManga(page: number): Promise<MangasPage> {
    return this.getPopularManga(page);
  }

  async getSearchManga(_page: number, query: string): Promise<MangasPage> {
    const names = this.listDirs().filter((n: string): boolean => n.includes(query));
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

  async getChapterList(mangaKey: string): Promise<SChapter[]> {
    return this.chaptersIn(`${this.rootDir}/${mangaKey}`, mangaKey);
  }

  async getPageList(_chapterKey: string): Promise<SPage[]> {
    return [];
  }

  async getChapterText(chapterKey: string): Promise<string> {
    const path = this.entryPath(chapterKey);
    if (path === '' || !fs.accessSync(path)) {
      throw new Error('章节文件不存在');
    }
    return fs.readTextSync(path);
  }

  async getVideoList(_chapterKey: string): Promise<SVideo[]> {
    return [];
  }

  imageRequestHeaders(): Record<string, string> | undefined {
    return undefined;
  }

  async importFiles(uris: string[], title: string): Promise<number> {
    const destDir = `${this.rootDir}/${title}`;
    if (!fs.accessSync(destDir)) {
      fs.mkdirSync(destDir, true);
    }
    let count = 0;
    for (const uri of uris) {
      const segs = uri.split('/');
      const rawName = segs.length > 0 ? segs[segs.length - 1] : `chapter_${count}.txt`;
      const fileName = decodeURIComponent(rawName);
      if (!fileName.toLowerCase().endsWith('.txt')) {
        continue;
      }
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

  private listDirs(): string[] {
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

  private chaptersIn(dir: string, mangaKey: string): SChapter[] {
    const chapters: SChapter[] = [];
    if (!fs.accessSync(dir)) {
      return chapters;
    }
    const entries = fs.listFileSync(dir).filter((name: string): boolean => name.toLowerCase().endsWith('.txt'));
    const sorted = entries.sort((a: string, b: string): number => a.localeCompare(b, 'zh', { numeric: true }));
    for (let i = 0; i < sorted.length; i++) {
      chapters.push(this.buildChapter(mangaKey, sorted[i], i));
    }
    return chapters;
  }

  private buildManga(dirName: string): SManga {
    const manga: SManga = {
      key: dirName,
      title: dirName,
      coverUrl: '',
      author: '',
      description: '本地导入的小说',
      genre: '本地',
      status: 'local',
    };
    return manga;
  }

  private buildChapter(mangaDir: string, entry: string, order: number): SChapter {
    let dateUpload = 0;
    try {
      dateUpload = fs.statSync(`${this.rootDir}/${mangaDir}/${entry}`).mtime * 1000;
    } catch (e) {
      dateUpload = 0;
    }
    const dotIdx = entry.lastIndexOf('.');
    const name = dotIdx > 0 ? entry.substring(0, dotIdx) : entry;
    const chapter: SChapter = {
      key: `${mangaDir}::${entry}`,
      name: name,
      chapterNumber: -1,
      dateUpload: dateUpload,
      pages: 0,
      sortOrder: order,
    };
    return chapter;
  }

  private entryPath(chapterKey: string): string {
    const sepIdx = chapterKey.indexOf('::');
    if (sepIdx < 0) {
      return '';
    }
    const mangaDir = chapterKey.substring(0, sepIdx);
    const entry = chapterKey.substring(sepIdx + 2);
    return `${this.rootDir}/${mangaDir}/${entry}`;
  }
}
