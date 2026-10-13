import { fileIo as fs } from '@kit.CoreFileKit';
import zlib from '@ohos.zlib';
import { SChapter, SPage, ContentType } from '../model/Models';
import { LocalFolderManager } from './LocalFolderManager';
import { LocalFsSource } from './LocalFsSource';

// 本地漫画源：扫描固定本地源文件夹的同步副本（filesDir/local_root，未设置时回退 filesDir/local）
// 目录结构：<系列名>/<章节名>.zip|.cbz 或 <章节名>/图片；
// 支持子目录分层（卷/章），章节名按相对路径显示为“卷 / 章”
export class LocalSource extends LocalFsSource {
  readonly key = 'local';
  readonly name = '本地漫画';
  readonly contentType = ContentType.MANGA;

  private readonly cacheDir: string;
  private readonly imageExts: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'];

  constructor(filesDir: string, cacheDir: string) {
    super(filesDir, 'local');
    this.cacheDir = cacheDir;
  }

  protected syncSubDir(): string {
    return LocalFolderManager.COMIC_SUBDIR;
  }

  protected contentExts(): string[] {
    return this.imageExts.concat(['.zip', '.cbz']);
  }

  protected mangaDescription(): string {
    return '本地导入的漫画';
  }

  async getChapterList(mangaKey: string): Promise<SChapter[]> {
    // 递归收集章节条目相对路径（含卷级子目录），按层级自然排序
    const relEntries: string[] = [];
    this.collectChapterEntries(`${this.rootDir()}/${mangaKey}`, '', relEntries);
    return this.entriesToChapters(mangaKey, relEntries);
  }

  async getPageList(chapterKey: string): Promise<SPage[]> {
    const entryPath = this.entryPath(chapterKey);
    if (entryPath === '' || !fs.accessSync(entryPath)) {
      throw new Error('章节文件不存在');
    }
    const sepIdx = chapterKey.indexOf('::');
    const mangaDir = chapterKey.substring(0, sepIdx);
    const entry = chapterKey.substring(sepIdx + 2);
    if (this.isArchive(entry)) {
      const files = await this.extractArchive(mangaDir, entry);
      return this.urlsToPages(files);
    }
    if (fs.statSync(entryPath).isDirectory()) {
      return this.urlsToPages(this.listImages(entryPath));
    }
    throw new Error('不支持的章节格式');
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
