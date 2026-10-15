import { ContentType, SChapter, SManga } from '../model/Models';
import { LocalFolderManager } from './LocalFolderManager';
import { LocalFsSource } from './LocalFsSource';
import { Util } from '../common/Util';
import { NaturalCompare } from '../common/NaturalCompare';
import { BookParser } from '../common/bookparser/BookParser';
import { BookFileIo } from '../common/bookparser/ByteUtils';

// 本地小说：扫描固定本地源文件夹的同步副本（filesDir/local_root，未设置时回退 filesDir/local_novel）
// <书名>/**/*.txt，一个文件一章；支持子目录分层（卷/章），章节名按相对路径显示为“卷 / 章”
// 另支持书籍文件（epub/mobi/azw/azw3/prc）：taskpool 解析为章节 HTML + 图片缓存（book_cache/<hash>/），
// 书籍 mangaKey 为相对路径（可含 '/'），章节 key 以 '#' 前缀区分 txt 文件章节
export class LocalNovelSource extends LocalFsSource {
  readonly key = 'local_novel';
  readonly name = '本地小说';
  readonly contentType = ContentType.NOVEL;

  constructor(filesDir: string) {
    super(filesDir, 'local_novel');
    BookParser.init(filesDir);
  }

  // 列表 = txt 目录 + 任意深度书籍文件（嵌套书籍也升格）
  protected listDirs(): string[] {
    const names = super.listDirs();
    const bookFiles: string[] = [];
    this.collectEntriesByExts(this.rootDir(), '', bookFiles, BookParser.bookExts());
    const all = names.concat(bookFiles);
    return all.sort((a: string, b: string): number => NaturalCompare.compare(a, b));
  }

  async getChapterList(mangaKey: string): Promise<SChapter[]> {
    if (BookParser.isBookFile(mangaKey) && LocalNovelSource.noDotDot(mangaKey)) {
      const path = `${this.rootDir()}/${mangaKey}`;
      const info = await BookParser.parse(path);
      const chapters: SChapter[] = [];
      const dateUpload = BookFileIo.mtime(path) * 1000;
      for (let i = 0; i < info.chapterNames.length; i++) {
        const name = info.chapterNames[i] !== '' ? info.chapterNames[i] : `${i + 1}`;
        const chapter: SChapter = {
          key: `${mangaKey}::#${i}`,
          name: name,
          chapterNumber: -1,
          dateUpload: dateUpload,
          pages: 0,
          sortOrder: i,
        };
        chapters.push(chapter);
      }
      return chapters;
    }
    // 递归收集 txt 相对路径（含卷级子目录），按层级自然排序
    const relEntries: string[] = [];
    this.collectEntriesByExts(`${this.rootDir()}/${mangaKey}`, '', relEntries, ['.txt']);
    return this.entriesToChapters(mangaKey, relEntries);
  }

  async getChapterText(chapterKey: string): Promise<string> {
    const sepIdx = chapterKey.indexOf('::');
    if (sepIdx < 0) {
      throw new Error('chapter_missing');
    }
    const mangaKey = chapterKey.substring(0, sepIdx);
    const entry = chapterKey.substring(sepIdx + 2);
    // 书籍章节：'#' + 序号
    if (entry.length > 0 && entry[0] === '#') {
      if (BookParser.isBookFile(mangaKey) && LocalNovelSource.noDotDot(mangaKey)) {
        const index = Number.parseInt(entry.substring(1), 10);
        if (Number.isNaN(index) || index < 0) {
          throw new Error('chapter_missing');
        }
        return BookParser.loadChapterText(`${this.rootDir()}/${mangaKey}`, index);
      }
      throw new Error('chapter_missing');
    }
    // txt 文件章节
    const path = this.entryPath(chapterKey);
    if (path === '' || !this.fileExists(path)) {
      throw new Error('chapter_missing');
    }
    // 本地 txt 可能为 UTF-8/GBK 等编码，智能识别解码避免乱码
    return Util.readTextAuto(path);
  }

  async getMangaDetail(mangaKey: string): Promise<SManga> {
    if (BookParser.isBookFile(mangaKey) && LocalNovelSource.noDotDot(mangaKey)) {
      const path = `${this.rootDir()}/${mangaKey}`;
      const info = await BookParser.parse(path);
      const manga: SManga = {
        key: mangaKey,
        title: info.title !== '' ? info.title : LocalNovelSource.baseNameNoExt(mangaKey),
        coverUrl: info.coverPath !== '' ? `file://${info.coverPath}` : '',
        author: info.author,
        description: this.mangaDescription(),
        genre: '本地',
        status: 'local',
      };
      return manga;
    }
    return this.buildManga(mangaKey);
  }

  // 列表页书籍条目：标题取文件名去扩展名（不解析，保证列表性能）
  protected buildManga(dirName: string): SManga {
    if (BookParser.isBookFile(dirName)) {
      const manga: SManga = {
        key: dirName,
        title: LocalNovelSource.baseNameNoExt(dirName),
        coverUrl: '',
        author: '',
        description: this.mangaDescription(),
        genre: '本地',
        status: 'local',
      };
      return manga;
    }
    return super.buildManga(dirName);
  }

  protected syncSubDir(): string {
    return LocalFolderManager.NOVEL_SUBDIR;
  }

  protected contentExts(): string[] {
    return ['.txt'];
  }

  protected mangaDescription(): string {
    return 'local_desc_novel';
  }

  private static noDotDot(path: string): boolean {
    const segs = path.split('/');
    for (const seg of segs) {
      if (seg === '..') {
        return false;
      }
    }
    return true;
  }

  // 相对路径条目名 → 文件名去扩展名（含 '/' 的嵌套 key 取末段）
  private static baseNameNoExt(entry: string): string {
    const slashIdx = entry.lastIndexOf('/');
    const base = slashIdx >= 0 ? entry.substring(slashIdx + 1) : entry;
    const dotIdx = base.lastIndexOf('.');
    return dotIdx > 0 ? base.substring(0, dotIdx) : base;
  }
}
