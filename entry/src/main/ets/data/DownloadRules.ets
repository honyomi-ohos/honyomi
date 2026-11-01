import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from '../common/Settings';
import { DownloadService } from './DownloadService';
import { ChapterRepo, MangaRepo } from './Repos';
import { ChapterRecord, ContentType, DownloadTask, MangaRecord } from '../model/Models';
import { ReaderChapterNav } from '../common/ReaderChapterNav';

const TAG = 'DownloadRules';

// 下载规则中心（对齐 Mihon 的删除策略 / 自动下载 / 阅读预下载）：
// - 标记已读后删除下载（手动多选/全部标记）
// - 阅读完当前章后删除倒数第 N 章的下载
// - 库更新发现新章节时自动入队下载
// - 阅读时当前章+下一章均已下载则预下载后续未读章节
export class DownloadRules {
  // 手动标记已读后按设置删除对应下载（多选"标记已读"路径）
  static onDeleteMarkedRead(mangaId: number, chapterIds: number[]): void {
    if (!Settings.getRemoveAfterMarkedAsRead() || chapterIds.length === 0) {
      return;
    }
    DownloadRules.deleteDownloadedChapters(mangaId, chapterIds).catch((e: Error): void => {
      hilog.warn(0x0001, TAG, 'delete after marked read failed: %{public}s', e.message);
    });
  }

  // 整部漫画全部标记已读路径：删除全部已读章节的下载
  static onDeleteAllRead(mangaId: number): void {
    if (!Settings.getRemoveAfterMarkedAsRead()) {
      return;
    }
    ChapterRepo.listByManga(mangaId).then((list: ChapterRecord[]): Promise<void> => {
      const ids: number[] = [];
      for (const c of list) {
        if (c.read) {
          ids.push(c.id);
        }
      }
      return DownloadRules.deleteDownloadedChapters(mangaId, ids);
    }).catch((e: Error): void => {
      hilog.warn(0x0001, TAG, 'delete after all read failed: %{public}s', e.message);
    });
  }

  // 阅读完一章后：按 slots 删除倒数第 N 章的下载（阅读器读完上报路径）
  static onChapterFinished(mangaId: number, chapterId: number): void {
    const slots = Settings.getRemoveAfterReadSlots();
    if (slots < 1) {
      return;
    }
    Promise.all([
      ChapterRepo.listByManga(mangaId),
      MangaRepo.get(mangaId),
    ]).then((pair: [ChapterRecord[], MangaRecord | undefined]): Promise<void> => {
      // 阅读正序定位：倒数第 N 章 = 阅读方向上更早的章节
      const list = ReaderChapterNav.readingOrder(pair[0],
        pair[1] !== undefined ? pair[1].chapterFlags : 0,
        pair[1] !== undefined ? pair[1].sourceKey : '');
      let idx = -1;
      for (let i = 0; i < list.length; i++) {
        if (list[i].id === chapterId) {
          idx = i;
          break;
        }
      }
      const targetIdx = idx - slots;
      if (idx < 0 || targetIdx < 0) {
        return Promise.resolve();
      }
      const target = list[targetIdx];
      return DownloadRules.deleteDownloadedChapters(mangaId, [target.id]);
    }).catch((e: Error): void => {
      hilog.warn(0x0001, TAG, 'delete after read failed: %{public}s', e.message);
    });
  }

  // 库更新发现新章节：按设置自动入队下载（视频源跳过，避免流媒体章节入队后必然失败）
  static autoDownloadNewChapters(manga: MangaRecord, newChapters: ChapterRecord[]): void {
    if (!Settings.getDownloadNewChapters() || newChapters.length === 0) {
      return;
    }
    if (ContentType.isLocal(manga.sourceKey) || manga.contentType === ContentType.VIDEO) {
      return;
    }
    ChapterRepo.listByManga(manga.id).then((all: ChapterRecord[]): void => {
      for (const ch of newChapters) {
        if (DownloadService.isQueued(ch.id) || DownloadService.isDownloaded(ch.id)) {
          continue;
        }
        if (Settings.getDownloadNewUnreadOnly() &&
          DownloadRules.isDuplicateOfRead(ch, all)) {
          continue;
        }
        DownloadService.enqueue(DownloadRules.taskOf(manga, ch));
      }
    }).catch((e: Error): void => {
      hilog.warn(0x0001, TAG, 'auto download new chapters failed: %{public}s', e.message);
    });
  }

  // 阅读预下载（对齐 Mihon downloadNextChapters）：当前章与下一章均已下载时，
  // 预下载后续 amount 个未读且未入队的章节
  static downloadAheadIfNeeded(manga: MangaRecord, chapterId: number): void {
    const amount = Settings.getAutoDownloadWhileReading();
    if (amount <= 0) {
      return;
    }
    if (ContentType.isLocal(manga.sourceKey) || manga.contentType === ContentType.VIDEO) {
      return;
    }
    ChapterRepo.listByManga(manga.id).then((raw: ChapterRecord[]): void => {
      // 阅读正序：下一章 = 阅读方向上更靠后的章节（不受详情页展示方向影响）
      const list = ReaderChapterNav.readingOrder(raw, manga.chapterFlags, manga.sourceKey);
      let idx = -1;
      for (let i = 0; i < list.length; i++) {
        if (list[i].id === chapterId) {
          idx = i;
          break;
        }
      }
      if (idx < 0 || idx + 1 >= list.length) {
        return;
      }
      // 触发条件：当前章节和下一章节均已下载
      if (!DownloadService.isDownloaded(list[idx].id) ||
        !DownloadService.isDownloaded(list[idx + 1].id)) {
        return;
      }
      let enqueued = 0;
      for (let i = idx + 1; i < list.length && enqueued < amount; i++) {
        const c = list[i];
        if (c.read || DownloadService.isQueued(c.id) || DownloadService.isDownloaded(c.id)) {
          continue;
        }
        DownloadService.enqueue(DownloadRules.taskOf(manga, c));
        enqueued += 1;
      }
    }).catch((e: Error): void => {
      hilog.warn(0x0001, TAG, 'download ahead failed: %{public}s', e.message);
    });
  }

  // 新章节与已读章节号重复（源站重传/合并章节场景）：跳过自动下载
  private static isDuplicateOfRead(chapter: ChapterRecord, all: ChapterRecord[]): boolean {
    if (chapter.chapterNumber <= 0) {
      return false;
    }
    for (const c of all) {
      if (c.id !== chapter.id && c.read && c.chapterNumber === chapter.chapterNumber) {
        return true;
      }
    }
    return false;
  }

  private static async deleteDownloadedChapters(mangaId: number, chapterIds: number[]): Promise<void> {
    const allowBookmarked = Settings.getRemoveBookmarked();
    for (const id of chapterIds) {
      const chapter = await ChapterRepo.getById(id);
      if (chapter === undefined) {
        continue;
      }
      if (chapter.bookmark && !allowBookmarked) {
        continue;
      }
      if (DownloadService.isDownloaded(id)) {
        await DownloadService.deleteChapter(mangaId, id);
      }
    }
  }

  private static taskOf(manga: MangaRecord, chapter: ChapterRecord): DownloadTask {
    const task = new DownloadTask();
    task.mangaId = manga.id;
    task.mangaTitle = manga.title;
    task.chapterId = chapter.id;
    task.chapterName = chapter.name;
    task.chapterNumber = chapter.chapterNumber;
    task.dateUpload = chapter.dateUpload;
    task.sourceKey = manga.sourceKey;
    task.mangaUrl = manga.url;
    task.chapterUrl = chapter.url;
    return task;
  }
}
