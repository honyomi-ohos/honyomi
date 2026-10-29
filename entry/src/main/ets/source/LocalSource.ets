import { fileIo as fs } from '@kit.CoreFileKit';
import { ContentType, SChapter, SManga, SPage, WorksPage } from '../model/Models';
import { LocalFolderManager } from './LocalFolderManager';
import { LocalFsSource } from './LocalFsSource';
import { NaturalCompare } from '../common/NaturalCompare';
import { ArchiveFormat, ArchiveReader } from '../common/ArchiveReader';

// local_extract 解压缓存条目（容量管理用）
interface ExtractCacheDir {
  path: string;
  mtime: number;
  size: number;
}

// 本地漫画源：扫描固定本地源文件夹的同步副本（filesDir/local_root）
// 目录结构：<系列名>/<章节名>.归档 或 <章节名>/图片；
// 归档对齐 Mihon 支持集：zip/cbz/tar/cbt 可解包阅读，rar/cbr 与 7z/cb7 识别后给友好错误；
// 支持子目录分层（卷/章），章节名按相对路径显示为“卷 / 章”；
// 另提供文件夹模式浏览 browseFolder（目录下钻 + 相对路径 workKey）
export class LocalSource extends LocalFsSource {
  // 解压缓存总量上限：超限时按目录 mtime 淘汰最旧的解压目录
  private static readonly EXTRACT_CACHE_LIMIT: number = 256 * 1024 * 1024;
  // 文件夹模式/嵌套作品扫描的目录递归深度上限
  private static readonly MAX_FOLDER_DEPTH: number = 8;
  readonly key = 'local';
  readonly name = '本地漫画';
  readonly contentType = ContentType.MANGA;
  private readonly cacheDir: string;
  private readonly imageExts: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'];

  constructor(filesDir: string, cacheDir: string) {
    super(filesDir);
    this.cacheDir = cacheDir;
  }

  private static dirSize(dir: string): number {
    let total = 0;
    let entries: string[] = [];
    try {
      entries = fs.listFileSync(dir);
    } catch (e) {
      return total;
    }
    for (const entry of entries) {
      const p = `${dir}/${entry}`;
      let isDir = false;
      let size = 0;
      try {
        const st = fs.statSync(p);
        isDir = st.isDirectory();
        size = st.size;
      } catch (e) {
        continue;
      }
      if (isDir) {
        total += LocalSource.dirSize(p);
      } else {
        total += size;
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

  // 搜索：顶层作品（现有行为）+ 任意深度嵌套作品（文件夹模式可发现的目录随搜索可达）
  async getSearchWorks(_page: number, query: string): Promise<WorksPage> {
    const q = query.toLowerCase();
    const names = this.listDirs().filter((n: string): boolean => n.toLowerCase().includes(q));
    const nested: string[] = [];
    this.collectNestedWorks('', q, nested, 0);
    const seen = new Set<string>();
    const merged: string[] = [];
    for (const n of names) {
      if (!seen.has(n)) {
        seen.add(n);
        merged.push(n);
      }
    }
    for (const n of nested) {
      if (!seen.has(n)) {
        seen.add(n);
        merged.push(n);
      }
    }
    merged.sort((a: string, b: string): number => NaturalCompare.compare(a, b));
    return this.namesToWorks(merged);
  }

  async getChapterList(workKey: string): Promise<SChapter[]> {
    // 递归收集章节条目相对路径（含卷级子目录），按层级自然排序
    const relEntries: string[] = [];
    this.collectChapterEntries(`${this.rootDir()}/${workKey}`, '', relEntries);
    return this.entriesToChapters(workKey, relEntries);
  }

  async getPageList(chapterKey: string): Promise<SPage[]> {
    const entryPath = this.entryPath(chapterKey);
    if (entryPath === '' || !this.fileExists(entryPath)) {
      throw new Error('chapter_missing');
    }
    const sepIdx = chapterKey.indexOf('::');
    const mangaDir = chapterKey.substring(0, sepIdx);
    const entry = chapterKey.substring(sepIdx + 2);
    if (this.isArchive(entry)) {
      const files = await this.extractArchive(mangaDir, entry);
      return this.urlsToPages(files);
    }
    let isDir = false;
    try {
      isDir = fs.statSync(entryPath).isDirectory();
    } catch (e) {
      throw new Error(`stat chapter failed: ${e}`);
    }
    if (isDir) {
      return this.urlsToPages(this.listImages(entryPath));
    }
    throw new Error('unsupported_format');
  }

  // ---------------- #12 文件夹模式分层浏览 ----------------
  // 契约：返回 SManga 列表，status === 'local_folder' 为目录条目（key=相对路径，
  // 点击应再次调用 browseFolder(key) 下钻；relDir 传 '' 为根目录）；
  // 其余为作品条目（key 即 workKey，可含 '/' 的相对路径，
  // 走 getWorkDetail/getChapterList/getPageList 全链路，进详情打开阅读）。
  // 顶层 getPopularWorks/getSearchWorks 行为保持向后兼容（搜索额外并入嵌套作品）。
  async browseFolder(relDir: string): Promise<SManga[]> {
    const clean = LocalSource.sanitizeRelPath(relDir);
    const listDir = clean === '' ? this.rootDir() : `${this.rootDir()}/${clean}`;
    let entries: string[] = [];
    try {
      if (!fs.accessSync(listDir)) {
        return [];
      }
      entries = fs.listFileSync(listDir).sort((a: string, b: string): number => NaturalCompare.compare(a, b));
    } catch (e) {
      return [];
    }
    const result: SManga[] = [];
    for (const entry of entries) {
      if (entry.startsWith('.')) {
        continue;
      }
      const full = `${listDir}/${entry}`;
      let isDir = false;
      try {
        isDir = fs.statSync(full).isDirectory();
      } catch (e) {
        continue;
      }
      if (!isDir) {
        continue;
      }
      const rel = clean === '' ? entry : `${clean}/${entry}`;
      if (this.hasDirectChapters(full)) {
        // 作品：第一层直接含章节条目（归档文件 / 图片文件夹）
        result.push(this.buildManga(rel));
      } else if (this.containsChapterDeep(full, 0)) {
        // 文件夹：更深一层才含漫画内容，可继续下钻
        result.push(LocalSource.buildFolderEntry(rel, entry));
      }
    }
    return result;
  }

  // 目录条目（status=local_folder，点击下钻而非进详情）
  private static buildFolderEntry(relPath: string, name: string): SManga {
    const folder: SManga = {
      key: relPath,
      title: name,
      coverUrl: '',
      author: '',
      description: '',
      genre: '本地',
      status: 'local_folder',
    };
    return folder;
  }

  // 相对路径净化：剔除空段与 '.'，'..' 段整条拒绝（路径穿越防护）
  private static sanitizeRelPath(relDir: string): string {
    const segs = relDir.split('/');
    const kept: string[] = [];
    for (const seg of segs) {
      if (seg === '' || seg === '.') {
        continue;
      }
      if (seg === '..') {
        return '';
      }
      kept.push(seg);
    }
    return kept.join('/');
  }

  // 目录第一层是否直接含章节条目（归档文件 / 含图片的子目录）
  private hasDirectChapters(dir: string): boolean {
    let entries: string[] = [];
    try {
      entries = fs.listFileSync(dir);
    } catch (e) {
      return false;
    }
    for (const entry of entries) {
      if (entry.startsWith('.')) {
        continue;
      }
      if (this.isArchive(entry)) {
        return true;
      }
      const full = `${dir}/${entry}`;
      let isDir = false;
      try {
        isDir = fs.statSync(full).isDirectory();
      } catch (e) {
        continue;
      }
      if (isDir && this.listImages(full).length > 0) {
        return true;
      }
    }
    return false;
  }

  // 目录内任意深度是否含章节条目（有界递归，文件夹条目判定用）
  private containsChapterDeep(dir: string, depth: number): boolean {
    if (depth > LocalSource.MAX_FOLDER_DEPTH) {
      return false;
    }
    let entries: string[] = [];
    try {
      entries = fs.listFileSync(dir);
    } catch (e) {
      return false;
    }
    for (const entry of entries) {
      if (entry.startsWith('.')) {
        continue;
      }
      if (this.isArchive(entry)) {
        return true;
      }
      const full = `${dir}/${entry}`;
      let isDir = false;
      try {
        isDir = fs.statSync(full).isDirectory();
      } catch (e) {
        continue;
      }
      if (!isDir) {
        continue;
      }
      if (this.listImages(full).length > 0 || this.containsChapterDeep(full, depth + 1)) {
        return true;
      }
    }
    return false;
  }

  // 收集嵌套作品相对路径（第一层直接含章节条目的目录；匹配 query，不进入作品内部）
  private collectNestedWorks(prefix: string, query: string, out: string[], depth: number): void {
    if (depth > LocalSource.MAX_FOLDER_DEPTH) {
      return;
    }
    const listDir = prefix === '' ? this.rootDir() : `${this.rootDir()}/${prefix}`;
    let entries: string[] = [];
    try {
      if (!fs.accessSync(listDir)) {
        return;
      }
      entries = fs.listFileSync(listDir).sort((a: string, b: string): number => NaturalCompare.compare(a, b));
    } catch (e) {
      return;
    }
    for (const entry of entries) {
      if (entry.startsWith('.')) {
        continue;
      }
      const full = `${listDir}/${entry}`;
      const rel = prefix === '' ? entry : `${prefix}/${entry}`;
      let isDir = false;
      try {
        isDir = fs.statSync(full).isDirectory();
      } catch (e) {
        continue;
      }
      if (!isDir) {
        continue;
      }
      if (this.hasDirectChapters(full)) {
        if (rel.toLowerCase().includes(query)) {
          out.push(rel);
        }
      } else {
        this.collectNestedWorks(rel, query, out, depth + 1);
      }
    }
  }

  protected syncSubDir(): string {
    return LocalFolderManager.COMIC_SUBDIR;
  }

  protected contentExts(): string[] {
    return this.imageExts.concat(ArchiveFormat.supportedExts());
  }

  protected mangaDescription(): string {
    return 'local_desc_manga';
  }

  // 无图片的目录视为卷（继续向下收集其归档/图片目录）
  private collectChapterEntries(dir: string, prefix: string, out: string[]): void {
    let entries: string[] = [];
    try {
      if (!fs.accessSync(dir)) {
        return;
      }
      entries = fs.listFileSync(dir).sort((a: string, b: string): number => NaturalCompare.compare(a, b));
    } catch (e) {
      return;
    }
    for (const entry of entries) {
      const rel = prefix === '' ? entry : `${prefix}/${entry}`;
      const fullPath = `${dir}/${entry}`;
      if (this.isArchive(entry)) {
        out.push(rel);
      } else {
        let isDir = false;
        try {
          isDir = fs.statSync(fullPath).isDirectory();
        } catch (e) {
          continue;
        }
        if (isDir && entry !== '.extracted') {
          if (this.listImages(fullPath).length > 0) {
            out.push(rel);
          } else {
            this.collectChapterEntries(fullPath, rel, out);
          }
        }
      }
    }
  }

  private isArchive(name: string): boolean {
    return ArchiveFormat.isSupported(name);
  }

  // 列出目录下的图片（自然排序）
  private listImages(dir: string): string[] {
    const files: string[] = [];
    let entries: string[] = [];
    try {
      entries = fs.listFileSync(dir);
    } catch (e) {
      return files;
    }
    for (const entry of entries) {
      const lower = entry.toLowerCase();
      if (this.imageExts.some((ext: string): boolean => lower.endsWith(ext))) {
        files.push(`${dir}/${entry}`);
      }
    }
    return files.sort((a: string, b: string): number => NaturalCompare.compare(a, b));
  }

  private async extractArchive(mangaDir: string, entry: string): Promise<string[]> {
    const archivePath = `${this.rootDir()}/${mangaDir}/${entry}`;
    const safeEntry = ArchiveFormat.stripArchiveExt(entry);
    const outDir = `${this.cacheDir}/local_extract/${mangaDir}/${safeEntry}`;
    // 已解压过则直接复用（通过标记文件判断）
    const doneFlag = `${outDir}/.extracted`;
    let done = false;
    try {
      done = fs.accessSync(doneFlag);
    } catch (e) {
      done = false;
    }
    if (!done) {
      // 先清理可能存在的半成品目录（doneFlag 未写成功即视为未完成）
      LocalSource.removeDirQuietly(outDir);
      // 写入前容量管理：解压缓存总量超限时按目录 mtime 淘汰最旧
      this.ensureExtractBudget();
      try {
        fs.mkdirSync(outDir, true);
        // 统一分派：zip/cbz 走 zlib，tar/cbt 走 TarExtractor，
        // rar/cbr、7z/cb7 抛出带中文文案的业务错误
        await ArchiveReader.openArchive(archivePath, outDir);
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
    let mangaDirs: string[] = [];
    try {
      if (!fs.accessSync(root)) {
        return;
      }
      mangaDirs = fs.listFileSync(root);
    } catch (e) {
      return;
    }
    const dirs: ExtractCacheDir[] = [];
    for (const mangaDir of mangaDirs) {
      const mangaPath = `${root}/${mangaDir}`;
      let mangaIsDir = false;
      try {
        mangaIsDir = fs.statSync(mangaPath).isDirectory();
      } catch (e) {
        continue;
      }
      if (!mangaIsDir) {
        continue;
      }
      let entries: string[] = [];
      try {
        entries = fs.listFileSync(mangaPath);
      } catch (e) {
        continue;
      }
      for (const name of entries) {
        const p = `${mangaPath}/${name}`;
        let isDir = false;
        let mtime = 0;
        try {
          isDir = fs.statSync(p).isDirectory();
          mtime = fs.statSync(p).mtime;
        } catch (e) {
          continue;
        }
        if (!isDir) {
          continue;
        }
        const info: ExtractCacheDir = { path: p, mtime: mtime, size: LocalSource.dirSize(p) };
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

  private collectImages(dir: string, out: string[]): void {
    let entries: string[] = [];
    try {
      entries = fs.listFileSync(dir);
    } catch (e) {
      return;
    }
    for (const entry of entries) {
      const fullPath = `${dir}/${entry}`;
      const lower = entry.toLowerCase();
      if (this.imageExts.some((ext: string): boolean => lower.endsWith(ext))) {
        out.push(fullPath);
      } else {
        try {
          if (fs.statSync(fullPath).isDirectory() && entry !== '.extracted') {
            this.collectImages(fullPath, out);
          }
        } catch (e) {
          continue;
        }
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
