import { ContentType, SChapter, SVideo } from '../model/Models';
import { LocalFolderManager } from './LocalFolderManager';
import { LocalFsSource } from './LocalFsSource';

const VIDEO_EXTS: string[] = ['.mp4', '.mkv', '.webm', '.mov', '.m4v'];

// 本地视频：扫描固定本地源文件夹的同步副本（filesDir/local_root，未设置时回退 filesDir/local_video）
// <片名>/**/*.{mp4,mkv,webm,mov,m4v}，一个文件一集；
// 支持子目录分层（季/集），章节名按相对路径显示为“季 / 集”
export class LocalVideoSource extends LocalFsSource {
  readonly key = 'local_video';
  readonly name = '本地视频';
  readonly contentType = ContentType.VIDEO;

  constructor(filesDir: string) {
    super(filesDir, 'local_video');
  }

  async getChapterList(mangaKey: string): Promise<SChapter[]> {
    // 递归收集视频文件相对路径（含季级子目录），按层级自然排序
    const relEntries: string[] = [];
    this.collectEntriesByExts(`${this.rootDir()}/${mangaKey}`, '', relEntries, VIDEO_EXTS);
    return this.entriesToChapters(mangaKey, relEntries);
  }

  async getVideoList(chapterKey: string): Promise<SVideo[]> {
    const path = this.entryPath(chapterKey);
    if (path === '' || !this.fileExists(path)) {
      throw new Error('video_missing');
    }
    const video: SVideo = { url: `file://${path}`, quality: 'local', headers: {} };
    return [video];
  }

  protected syncSubDir(): string {
    return LocalFolderManager.ANIME_SUBDIR;
  }

  protected contentExts(): string[] {
    return VIDEO_EXTS;
  }

  protected mangaDescription(): string {
    return 'local_desc_video';
  }
}
