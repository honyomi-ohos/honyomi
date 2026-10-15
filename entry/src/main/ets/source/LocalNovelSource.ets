import { ContentType, SChapter, SManga } from '../model/Models';
import { LocalFolderManager } from './LocalFolderManager';
import { LocalFsSource } from './LocalFsSource';
import { Util } from '../common/Util';

// 本地小说：扫描固定本地源文件夹的同步副本（filesDir/local_root，未设置时回退 filesDir/local_novel）
// <书名>/**/*.txt，一个文件一章；
// 支持子目录分层（卷/章），章节名按相对路径显示为“卷 / 章”
export class LocalNovelSource extends LocalFsSource {
  readonly key = 'local_novel';
  readonly name = '本地小说';
  readonly contentType = ContentType.NOVEL;

  constructor(filesDir: string) {
    super(filesDir, 'local_novel');
  }

  async getChapterList(mangaKey: string): Promise<SChapter[]> {
    // 递归收集 txt 相对路径（含卷级子目录），按层级自然排序
    const relEntries: string[] = [];
    this.collectEntriesByExts(`${this.rootDir()}/${mangaKey}`, '', relEntries, ['.txt']);
    return this.entriesToChapters(mangaKey, relEntries);
  }

  async getChapterText(chapterKey: string): Promise<string> {
    const path = this.entryPath(chapterKey);
    if (path === '' || !this.fileExists(path)) {
      throw new Error('chapter_missing');
    }
    // 本地 txt 可能为 UTF-8/GBK 等编码，智能识别解码避免乱码
    return Util.readTextAuto(path);
  }

  async getMangaDetail(mangaKey: string): Promise<SManga> {
    return this.buildManga(mangaKey);
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
}
