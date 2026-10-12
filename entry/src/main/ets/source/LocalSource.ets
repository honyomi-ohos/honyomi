import { fileIo as fs } from '@kit.CoreFileKit';
import zlib from '@ohos.zlib';
import { SManga, SChapter, SPage, SVideo, MangasPage, ContentType } from '../model/Models';
import { Source } from './Source';
import { LocalFolderManager } from './LocalFolderManager';

// 本地漫画源：扫描固定本地源文件夹的同步副本（filesDir/local_root，未设置时回退 filesDir/local）
// 目录结构：<系列名>/<章节名>.zip|.cbz 或 <章节名>/图片；
// 支持子目录分层（卷/章），章节名按相对路径显示为“卷 / 章”
export class LocalSource implements Source {
  readonly key = 'local';
  readonly name = '本地漫画';
  readonly lang = 'zh';
  readonly supportsLatest = false;
  readonly contentType = ContentType.MANGA;

  private readonly legacyDir: string;
  private readonly syncRoot: string;
  private readonly cacheDir: string;
  private readonly imageExts: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'];

  constructor(filesDir: string, cacheDir: string) {
    this.legacyDir = `${filesDir}/local`;
    this.syncRoot = LocalFolderManager.syncedRootPath(filesDir);
    this.cacheDir = cacheDir;
    if (!fs.accessSync(this.legacyDir)) {
      fs.mkdirSync(this.legacyDir, true);
    }
  }

  // 扫描根：设置了本地源文件夹且已同步过则用同步副本下的 comic 子文件夹，否则回退旧导入目录
  private rootDir(): string {
    if (fs.accessSync(this.syncRoot)) {
      return `${this.syncRoot}/${LocalFolderManager.COMIC_SUBDIR}`;
    }
    return this.legacyDir;
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

  // 本地源不支持最新更新，回退为全部列表（接口要求实现，UI 不会触发）
  async getLatestManga(page: number): Promise<MangasPage> {
    return this.getPopularManga(page);
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

  async getChapterText(_chapterKey: string): Promise<string> {
    return '';
  }

  async getVideoList(_chapterKey: string): Promise<SVideo[]> {
    return [];
  }

  async getChapterList(mangaKey: string): Promise<SChapter[]> {
    // 递归收集章节条目相对路径（含卷级子目录），按层级自然排序
    const relEntries: string[] = [];
    this.collectChapterEntries(`${this.rootDir()}/${mangaKey}`, '', relEntries);
    const chapters: SChapter[] = [];
    for (let i = 0; i < relEntries.length; i++) {
      chapters.push(this.buildChapter(mangaKey, relEntries[i], i));
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
    const entryPath = `${this.rootDir()}/${mangaDir}/${entry}`;
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

  private listMangaDirs(): string[] {
    if (!fs.accessSync(this.rootDir())) {
      return [];
    }
    const exts: string[] = this.imageExts.concat(['.zip', '.cbz']);
    const names: string[] = [];
    const entries = fs.listFileSync(this.rootDir());
    for (const entry of entries) {
      if (entry.startsWith('.')) {
        continue;
      }
      const fullPath = `${this.rootDir()}/${entry}`;
      // 仅列出含图片/漫画归档的目录（本地源文件夹内小说、视频等自动排除）
      if (fs.statSync(fullPath).isDirectory() &&
        LocalFolderManager.hasFileWithExts(fullPath, exts)) {
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

  // 相对路径条目（可含“卷/章”层级）转章节，名称显示为“卷 / 章”
  private buildChapter(mangaDir: string, entry: string, order: number): SChapter {
    let dateUpload = 0;
    try {
      const stat = fs.statSync(`${this.rootDir()}/${mangaDir}/${entry}`);
      dateUpload = stat.mtime * 1000;
    } catch (e) {
      dateUpload = 0;
    }
    let pages = 0;
    const dotIdx = entry.lastIndexOf('.');
    const noExt = dotIdx > 0 ? entry.substring(0, dotIdx) : entry;
    const chapter: SChapter = {
      key: `${mangaDir}::${entry}`,
      name: noExt.split('/').join(' / '),
      chapterNumber: -1,
      dateUpload: dateUpload,
      pages: pages,
      sortOrder: order,
    };
    return chapter;
  }

  // 递归收集章节条目相对路径：归档文件与含图片的目录为章节，
  // 无图片的目录视为卷（继续向下收集其归档/图片目录）
  private collectChapterEntries(dir: string, prefix: string, out: string[]): void {
    if (!fs.accessSync(dir)) {
      return;
    }
    const entries = fs.listFileSync(dir).sort((a: string, b: string): number => a.localeCompare(b, 'zh', { numeric: true }));
    for (const entry of entries) {
      const rel = prefix === '' ? entry : `${prefix}/${entry}`;
      const fullPath = `${dir}/${entry}`;
      if (this.isArchive(entry)) {
        out.push(rel);
      } else if (fs.statSync(fullPath).isDirectory() && entry !== '.extracted') {
        if (this.listImages(fullPath).length > 0) {
          out.push(rel);
        } else {
          this.collectChapterEntries(fullPath, rel, out);
        }
      }
    }
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
    const zipPath = `${this.rootDir()}/${mangaDir}/${entry}`;
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
