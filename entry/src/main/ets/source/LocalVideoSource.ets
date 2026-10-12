import { fileIo as fs } from '@kit.CoreFileKit';
import { SManga, SChapter, SPage, SVideo, MangasPage, ContentType } from '../model/Models';
import { Source } from './Source';
import { LocalFolderManager } from './LocalFolderManager';

const VIDEO_EXTS: string[] = ['.mp4', '.mkv', '.webm', '.mov', '.m4v'];

// 本地视频：扫描固定本地源文件夹的同步副本（filesDir/local_root，未设置时回退 filesDir/local_video）
// <片名>/**/*.{mp4,mkv,webm,mov,m4v}，一个文件一集；
// 支持子目录分层（季/集），章节名按相对路径显示为“季 / 集”
export class LocalVideoSource implements Source {
  readonly key = 'local_video';
  readonly name = '本地视频';
  readonly lang = 'zh';
  readonly supportsLatest = false;
  readonly contentType = ContentType.VIDEO;

  private readonly legacyDir: string;
  private readonly syncRoot: string;

  constructor(filesDir: string) {
    this.legacyDir = `${filesDir}/local_video`;
    this.syncRoot = LocalFolderManager.syncedRootPath(filesDir);
    if (!fs.accessSync(this.legacyDir)) {
      fs.mkdirSync(this.legacyDir, true);
    }
  }

  // 扫描根：设置了本地源文件夹且已同步过则用同步副本下的 anime 子文件夹，否则回退旧导入目录
  private rootDir(): string {
    if (fs.accessSync(this.syncRoot)) {
      return `${this.syncRoot}/${LocalFolderManager.ANIME_SUBDIR}`;
    }
    return this.legacyDir;
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
    // 递归收集视频文件相对路径（含季级子目录），按层级自然排序
    const relEntries: string[] = [];
    this.collectVideoEntries(`${this.rootDir()}/${mangaKey}`, '', relEntries);
    const chapters: SChapter[] = [];
    for (let i = 0; i < relEntries.length; i++) {
      chapters.push(this.buildChapter(mangaKey, relEntries[i], i));
    }
    return chapters;
  }

  async getPageList(_chapterKey: string): Promise<SPage[]> {
    return [];
  }

  async getChapterText(_chapterKey: string): Promise<string> {
    return '';
  }

  async getVideoList(chapterKey: string): Promise<SVideo[]> {
    const path = this.entryPath(chapterKey);
    if (path === '' || !fs.accessSync(path)) {
      throw new Error('视频文件不存在');
    }
    const video: SVideo = { url: `file://${path}`, quality: '本地', headers: {} };
    return [video];
  }

  imageRequestHeaders(): Record<string, string> | undefined {
    return undefined;
  }

  // 递归收集目录下全部视频文件的相对路径，每层按中文数字习惯排序
  private collectVideoEntries(dir: string, prefix: string, out: string[]): void {
    if (!fs.accessSync(dir)) {
      return;
    }
    const entries = fs.listFileSync(dir).sort((a: string, b: string): number => a.localeCompare(b, 'zh', { numeric: true }));
    for (const entry of entries) {
      const rel = prefix === '' ? entry : `${prefix}/${entry}`;
      const fullPath = `${dir}/${entry}`;
      if (fs.statSync(fullPath).isDirectory()) {
        this.collectVideoEntries(fullPath, rel, out);
      } else if (LocalVideoSource.isVideo(entry)) {
        out.push(rel);
      }
    }
  }

  private listDirs(): string[] {
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
      // 仅列出含视频文件的目录（本地源文件夹内漫画、小说等自动排除）
      if (fs.statSync(fullPath).isDirectory() &&
        LocalFolderManager.hasFileWithExts(fullPath, VIDEO_EXTS)) {
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
      description: '本地导入的视频',
      genre: '本地',
      status: 'local',
    };
    return manga;
  }

  // 相对路径条目（可含“季/集.mkv”层级）转章节，名称显示为“季 / 集”
  private buildChapter(mangaDir: string, entry: string, order: number): SChapter {
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

  private entryPath(chapterKey: string): string {
    const sepIdx = chapterKey.indexOf('::');
    if (sepIdx < 0) {
      return '';
    }
    const mangaDir = chapterKey.substring(0, sepIdx);
    const entry = chapterKey.substring(sepIdx + 2);
    return `${this.rootDir()}/${mangaDir}/${entry}`;
  }

  private static isVideo(name: string): boolean {
    const lower = name.toLowerCase();
    for (let i = 0; i < VIDEO_EXTS.length; i++) {
      if (lower.endsWith(VIDEO_EXTS[i])) {
        return true;
      }
    }
    return false;
  }
}
