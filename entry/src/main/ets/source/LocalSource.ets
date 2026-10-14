import { fileIo as fs } from '@kit.CoreFileKit';
import zlib from '@ohos.zlib';
import { SChapter, SPage, ContentType } from '../model/Models';
import { LocalFolderManager } from './LocalFolderManager';
import { LocalFsSource } from './LocalFsSource';
import { NaturalCompare } from '../common/NaturalCompare';

// local_extract 解压缓存条目（容量管理用）
interface ExtractCacheDir {
  path: string;
  mtime: number;
  size: number;
}

// 本地漫画源：扫描固定本地源文件夹的同步副本（filesDir/local_root，未设置时回退 filesDir/local）
// 目录结构：<系列名>/<章节名>.zip|.cbz 或 <章节名>/图片；
// 支持子目录分层（卷/章），章节名按相对路径显示为“卷 / 章”
export class LocalSource extends LocalFsSource {
  readonly key = 'local';
  readonly name = '本地漫画';
  readonly contentType = ContentType.MANGA;

  // 解压缓存总量上限：超限时按目录 mtime 淘汰最旧的解压目录
  private static readonly EXTRACT_CACHE_LIMIT: number = 256 * 1024 * 1024;

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
    const entries = fs.listFileSync(dir).sort((a: string, b: string): number => NaturalCompare.compare(a, b));
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
    return files.sort((a: string, b: string): number => NaturalCompare.compare(a, b));
  }

  private async extractArchive(mangaDir: string, entry: string): Promise<string[]> {
    const zipPath = `${this.rootDir()}/${mangaDir}/${entry}`;
    const safeEntry = entry.replace(new RegExp('\\.(zip|cbz)$', 'i'), '');
    const outDir = `${this.cacheDir}/local_extract/${mangaDir}/${safeEntry}`;
    // 已解压过则直接复用（通过标记文件判断）
    const doneFlag = `${outDir}/.extracted`;
    if (!fs.accessSync(doneFlag)) {
      // 先清理可能存在的半成品目录（doneFlag 未写成功即视为未完成）
      LocalSource.removeDirQuietly(outDir);
      // 写入前容量管理：解压缓存总量超限时按目录 mtime 淘汰最旧
      this.ensureExtractBudget();
      fs.mkdirSync(outDir, true);
      try {
        await zlib.decompressFile(zipPath, outDir);
        const flagFile = fs.openSync(doneFlag, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.writeSync(flagFile.fd, 'ok');
        fs.closeSync(flagFile);
      } catch (e) {
        // 解压失败：清理半成品目录，下次重新解压
        LocalSource.removeDirQuietly(outDir);
        throw new Error((e instanceof Error ? e.message : String(e)));
      }
    }
    // 递归收集图片
    const result: string[] = [];
    this.collectImages(outDir, result);
    return result.sort((a: string, b: string): number => NaturalCompare.compare(a, b));
  }

  // local_extract 解压缓存容量管理：总量超上限（256MB）时按目录 mtime 淘汰最旧的解压目录
  private ensureExtractBudget(): void {
    const root = `${this.cacheDir}/local_extract`;
    if (!fs.accessSync(root)) {
      return;
    }
    const dirs: ExtractCacheDir[] = [];
    const mangaDirs = fs.listFileSync(root);
    for (const mangaDir of mangaDirs) {
      const mangaPath = `${root}/${mangaDir}`;
      if (!fs.statSync(mangaPath).isDirectory()) {
        continue;
      }
      const entries = fs.listFileSync(mangaPath);
      for (const name of entries) {
        const p = `${mangaPath}/${name}`;
        if (!fs.statSync(p).isDirectory()) {
          continue;
        }
        const info: ExtractCacheDir = { path: p, mtime: fs.statSync(p).mtime, size: LocalSource.dirSize(p) };
        dirs.push(info);
      }
    }
    let total = 0;
    for (const d of dirs) {
      total += d.size;
    }
    if (total <= LocalSource.EXTRACT_CACHE_LIMIT) {
      return;
    }
    dirs.sort((a: ExtractCacheDir, b: ExtractCacheDir): number => a.mtime - b.mtime);
    let i = 0;
    while (total > LocalSource.EXTRACT_CACHE_LIMIT && i < dirs.length) {
      LocalSource.removeDirQuietly(dirs[i].path);
      total -= dirs[i].size;
      i += 1;
    }
  }

  private static dirSize(dir: string): number {
    let total = 0;
    const entries = fs.listFileSync(dir);
    for (const entry of entries) {
      const p = `${dir}/${entry}`;
      const st = fs.statSync(p);
      if (st.isDirectory()) {
        total += LocalSource.dirSize(p);
      } else {
        total += st.size;
      }
    }
    return total;
  }

  private static removeDirQuietly(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.rmdirSync(path);
      }
    } catch (e) {
      // 忽略清理失败
    }
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
