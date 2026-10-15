// 章节读完后的追踪进度更新（对齐 Mihon TrackChapter）
// 调用点：ReaderPage/NovelReaderPage 标记章节已读后；由“自动更新追踪进度”开关控制
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from '../../common/Settings';
import { ChapterRepo, TrackRepo } from '../Repos';
import { TrackerManager } from './TrackerManager';

export class TrackService {
  static async updateChapterRead(mangaId: number, chapterId: number): Promise<void> {
    try {
      if (!Settings.getTrackAutoUpdate()) {
        return;
      }
      const tracks = await TrackRepo.listByManga(mangaId);
      if (tracks.length === 0) {
        return;
      }
      const chapter = await ChapterRepo.getById(chapterId);
      if (chapter === undefined) {
        return;
      }
      const chapterNumber = chapter.chapterNumber;
      if (!(chapterNumber > 0)) {
        return;
      }
      for (const track of tracks) {
        if (chapterNumber <= track.lastChapterRead) {
          continue;
        }
        const tracker = TrackerManager.get(track.syncId);
        if (tracker === undefined || !tracker.isLoggedIn()) {
          continue;
        }
        try {
          // 先刷新远端状态（合并其他端修改），再推进进度并落库
          await tracker.refresh(track);
          await tracker.setRemoteLastChapterRead(track, chapterNumber);
        } catch (e) {
          hilog.warn(0x0001, 'TrackService', 'update track %{public}d failed: %{public}s',
            track.syncId, e instanceof Error ? e.message : String(e));
        }
      }
    } catch (e) {
      hilog.warn(0x0001, 'TrackService', 'updateChapterRead failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }
}
