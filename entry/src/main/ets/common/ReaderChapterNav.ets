import { ChapterRepo, MangaRepo } from '../data/Repos';
import { ChapterRecord } from '../model/Models';
import { ChapterFlags } from './ChapterFlags';
import { NaturalCompare } from './NaturalCompare';

// 相邻章节信息：prevId/nextId 为 0 表示无；hasPrev/hasNext 同义；chapters 为阅读正序章节表
export interface ChapterNeighbors {
  prevId: number;
  nextId: number;
  hasPrev: boolean;
  hasNext: boolean;
  index: number;
  total: number;
  chapters: ChapterRecord[];
}

// 三阅读器（漫画/小说/视频）共用的章节导航：定位当前章节并给出前后章节。
// prev/next 恒按"阅读正序"（旧→新）计算，不受详情页列表展示方向影响
export class ReaderChapterNav {
  // 阅读正序排序：
  // - 源顺序模式：sortOrder 即源声明顺序（本应用插件按"旧→新"自然顺序返回章节列表，
  //   详情页"源顺序原样"展示同此顺序），正序 = sortOrder 升序
  // - 章节号/上传日期/字母模式：对应键升序
  // 同值回退 sortOrder 升序保持稳定序，再回退 id
  static readingOrder(list: ChapterRecord[], flags: number, _sourceKey: string): ChapterRecord[] {
    const mode: number = ChapterFlags.sortingMode(flags);
    const sorted: ChapterRecord[] = list.slice().sort((a: ChapterRecord, b: ChapterRecord): number => {
      let cmp: number = 0;
      if (mode === ChapterFlags.SORTING_NUMBER) {
        cmp = a.chapterNumber - b.chapterNumber;
      } else if (mode === ChapterFlags.SORTING_UPLOAD_DATE) {
        cmp = a.dateUpload - b.dateUpload;
      } else if (mode === ChapterFlags.SORTING_ALPHABET) {
        cmp = NaturalCompare.compare(a.name, b.name);
      } else {
        cmp = a.sortOrder - b.sortOrder;
      }
      if (cmp !== 0) {
        return cmp;
      }
      const orderCmp: number = a.sortOrder - b.sortOrder;
      if (orderCmp !== 0) {
        return orderCmp;
      }
      return a.id - b.id;
    });
    return sorted;
  }

  static async neighbors(mangaId: number, chapterId: number): Promise<ChapterNeighbors> {
    const manga = await MangaRepo.get(mangaId);
    const raw: ChapterRecord[] = await ChapterRepo.listByManga(mangaId);
    const list: ChapterRecord[] = ReaderChapterNav.readingOrder(raw,
      manga !== undefined ? manga.chapterFlags : 0,
      manga !== undefined ? manga.sourceKey : '');
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
