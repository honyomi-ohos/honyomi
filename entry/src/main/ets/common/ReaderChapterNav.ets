import { ChapterRepo } from '../data/Repos';
import { ChapterRecord } from '../model/Models';

// 相邻章节信息：prevId/nextId 为 0 表示无；hasPrev/hasNext 同义；chapters 为全量章节表
export interface ChapterNeighbors {
  prevId: number;
  nextId: number;
  hasPrev: boolean;
  hasNext: boolean;
  index: number;
  total: number;
  chapters: ChapterRecord[];
}

// 三阅读器（漫画/小说/视频）共用的章节导航：定位当前章节并给出前后章节
export class ReaderChapterNav {
  static async neighbors(mangaId: number, chapterId: number): Promise<ChapterNeighbors> {
    const list: ChapterRecord[] = await ChapterRepo.listByManga(mangaId);
    let idx = -1;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === chapterId) {
        idx = i;
        break;
      }
    }
    const result: ChapterNeighbors = {
      prevId: idx > 0 ? list[idx - 1].id : 0,
      nextId: idx >= 0 && idx < list.length - 1 ? list[idx + 1].id : 0,
      hasPrev: idx > 0,
      hasNext: idx >= 0 && idx < list.length - 1,
      index: idx,
      total: list.length,
      chapters: list,
    };
    return result;
  }

  // 前后目标章节 id；无目标返回 0
  static async neighborChapterId(mangaId: number, chapterId: number, next: boolean): Promise<number> {
    const n: ChapterNeighbors = await ReaderChapterNav.neighbors(mangaId, chapterId);
    return next ? n.nextId : n.prevId;
  }
}
