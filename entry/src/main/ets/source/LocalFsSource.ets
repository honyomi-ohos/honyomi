import { fileIo as fs } from '@kit.CoreFileKit';
import { SManga, SChapter, SPage, SVideo, MangasPage } from '../model/Models';
import { Source } from './Source';
import { LocalFolderManager } from './LocalFolderManager';
import { NaturalCompare } from '../common/NaturalCompare';

// 本地文件源基类：三个本地图源（漫画/小说/视频）共用
// 扫描根 = 本地源文件夹同步副本下的子目录，未同步时回退旧导入目录
// 目录条目约定：<作品名>/<章节条目>，chapterKey 格式 <作品目录>::<章节条目相对路径>
export abstract class LocalFsSource implements Source {
  abstract readonly key: string;
  abstract readonly name: string;
  readonly lang = 'zh';
  readonly supportsLatest = false;
  readonly iconPath = '';
  abstract readonly contentType: string;

  private readonly syncRoot: string;
  protected readonly legacyDir: string;

  protected constructor(filesDir: string, legacyName: string) {
    this.legacyDir = `${filesDir}/${legacyName}`;
    this.syncRoot = LocalFolderManager.syncedRootPath(filesDir);
    if (!fs.accessSync(this.legacyDir)) {
      fs.mkdirSync(this.legacyDir, true);
    }
  }

  // 同步副本下的子目录名（comic / novel / anime）
  protected abstract syncSubDir(): string;

  // 列作品目录时的内容文件扩展名过滤
  protected abstract contentExts(): string[];

  protected abstract mangaDescription(): string;

  protected rootDir(): string {
    if (fs.accessSync(this.syncRoot)) {
      return `${this.syncRoot}/${this.syncSubDir()}`;
    }
    return this.legacyDir;
  }

  async getPopularManga(page: number): Promise<MangasPage> {
    const names = page === 1 ? this.listDirs() : [];
    return this.namesToMangas(names);
  }

  // 本地源不支持最新更新，回退为全部列表（接口要求实现，UI 不会触发）
  async getLatestManga(page: number): Promise<MangasPage> {
    return this.getPopularManga(page);
  }

  async getSearchManga(_page: number, query: string): Promise<MangasPage> {
    const names = this.listDirs().filter((n: string): boolean => n.includes(query));
    return this.namesToMangas(names);
  }

  async getMangaDetail(mangaKey: string): Promise<SManga> {
    return this.buildManga(mangaKey);
  }

  abstract getChapterList(mangaKey: string): Promise<SChapter[]>;

  async getPageList(_chapterKey: string): Promise<SPage[]> {
    return [];
  }

  async getChapterText(_chapterKey: string): Promise<string> {
    return '';
  }

  async getVideoList(_chapterKey: string): Promise<SVideo[]> {
    return [];
  }

  imageRequestHeaders(): Record<string, string> | undefined {
    return undefined;
  }

  protected namesToMangas(names: string[]): MangasPage {
    const mangas: SManga[] = [];
    for (const name of names) {
      mangas.push(this.buildManga(name));
    }
    const result: MangasPage = { mangas: mangas, hasNextPage: false };
    return result;
  }

  protected entriesToChapters(mangaKey: string, relEntries: string[]): SChapter[] {
    const chapters: SChapter[] = [];
    for (let i = 0; i < relEntries.length; i++) {
      chapters.push(this.buildChapter(mangaKey, relEntries[i], i));
    }
    return chapters;
  }

  // 仅列出含指定类型内容文件的目录（本地源文件夹内其他类型自动排除）
  protected listDirs(): string[] {
    if (!fs.accessSync(this.rootDir())) {
      return [];
    }
    const names: string[] = [];
    const entries = fs.listFileSync(this.rootDir());
    for (const entry of entries) {
      if (entry.startsWith('.')) {
        continue;
      }
      const fullPath = `${this.rootDir()}/${entry}`;
      if (fs.statSync(fullPath).isDirectory() &&
        LocalFolderManager.hasFileWithExts(fullPath, this.contentExts())) {
        names.push(entry);
      }
    }
    return names.sort((a: string, b: string): number => NaturalCompare.compare(a, b));
  }

  protected buildManga(dirName: string): SManga {
    const manga: SManga = {
      key: dirName,
      title: dirName,
      coverUrl: '',
      author: '',
      description: this.mangaDescription(),
      genre: '本地',
      status: 'local',
    };
    return manga;
  }

  // 相对路径条目（可含"卷/章"层级）转章节，名称显示为"卷 / 章"
  protected buildChapter(mangaDir: string, entry: string, order: number): SChapter {
    let dateUpload = 0;
    try {
      dateUpload = fs.statSync(`${this.rootDir()}/${mangaDir}/${entry}`).mtime * 1000;
    } catch (e) {
      dateUpload = 0;
    }
    const dotIdx = entry.lastIndexOf('.');
    const noExt = dotIdx > 0 ? entry.substring(0, dotIdx) : entry;
    const chapter: SChapter = {
      key: `${mangaDir}::${entry}`,
      name: noExt.split('/').join(' / '),
      chapterNumber: -1,
      dateUpload: dateUpload,
      pages: 0,
      sortOrder: order,
    };
    return chapter;
  }

  // chapterKey（<作品目录>::<章节条目>）转绝对路径；无效返回空串
  protected entryPath(chapterKey: string): string {
    const sepIdx = chapterKey.indexOf('::');
    if (sepIdx < 0) {
      return '';
    }
    const mangaDir = chapterKey.substring(0, sepIdx);
    const entry = chapterKey.substring(sepIdx + 2);
    return `${this.rootDir()}/${mangaDir}/${entry}`;
  }

  // 递归收集扩展名匹配的文件相对路径（含卷级子目录），每层按自然顺序排序
  // （阿拉伯数字与中文数字均按数值比较，"第十章"排在"第二章"之后）
  protected collectEntriesByExts(dir: string, prefix: string, out: string[], exts: string[]): void {
    if (!fs.accessSync(dir)) {
      return;
    }
    const entries = fs.listFileSync(dir).sort((a: string, b: string): number => NaturalCompare.compare(a, b));
    for (const entry of entries) {
      const rel = prefix === '' ? entry : `${prefix}/${entry}`;
      const fullPath = `${dir}/${entry}`;
      if (fs.statSync(fullPath).isDirectory()) {
        this.collectEntriesByExts(fullPath, rel, out, exts);
      } else if (this.hasExt(entry, exts)) {
        out.push(rel);
      }
    }
  }

  protected hasExt(name: string, exts: string[]): boolean {
    const lower = name.toLowerCase();
    for (let i = 0; i < exts.length; i++) {
      if (lower.endsWith(exts[i])) {
        return true;
      }
    }
    return false;
  }

  protected fileExists(path: string): boolean {
    return fs.accessSync(path);
  }
}
