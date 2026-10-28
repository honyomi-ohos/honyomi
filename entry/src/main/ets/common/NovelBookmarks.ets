import { Settings } from './Settings';

// 小说章内阅读位置书签：章节 + 千分比进度 + 落点时间（按漫画持久化为 JSON）
export class NovelBookmark {
  chapterId: number = 0;
  // 阅读进度（千分比 0-1000；滚动=滚动比例，翻页/双页=页码比例）
  permille: number = 0;
  chapterName: string = '';
  time: number = 0;
}

// JSON 反序列化原始模型（字段可缺省，逐字段校验后拷入严格模型）
interface NovelBookmarkRaw {
  chapterId?: number;
  permille?: number;
  chapterName?: string;
  time?: number;
}

// 单本小说的书签集合：读/写/增/删/查询（去重、上限 50 条）
export class NovelBookmarks {
  private static readonly MAX_COUNT: number = 50;
  // 同章书签的进度去重容差（千分比）
  private static readonly DUP_TOLERANCE: number = 15;

  static list(mangaId: number): NovelBookmark[] {
    const out: NovelBookmark[] = [];
    try {
      const parsed = JSON.parse(Settings.getNovelBookmarkJson(mangaId)) as NovelBookmarkRaw[];
      if (!Array.isArray(parsed)) {
        return out;
      }
      for (const raw of parsed) {
        if (raw === null || typeof raw !== 'object') {
          continue;
        }
        const bm = new NovelBookmark();
        bm.chapterId = typeof raw.chapterId === 'number' ? raw.chapterId : 0;
        bm.permille = typeof raw.permille === 'number' ? raw.permille : 0;
        bm.chapterName = typeof raw.chapterName === 'string' ? raw.chapterName : '';
        bm.time = typeof raw.time === 'number' ? raw.time : 0;
        if (bm.chapterId > 0) {
          out.push(bm);
        }
      }
    } catch (_e) {
    }
    return out;
  }

  static save(mangaId: number, list: NovelBookmark[]): void {
    Settings.setNovelBookmarkJson(mangaId, JSON.stringify(list));
  }

  // 添加书签：同章近似进度（容差内）视为同一书签并覆盖，新书签置于列表头；返回更新后的列表
  static add(mangaId: number, bm: NovelBookmark): NovelBookmark[] {
    const list = NovelBookmarks.list(mangaId);
    for (let i = 0; i < list.length; i++) {
      if (list[i].chapterId === bm.chapterId &&
        Math.abs(list[i].permille - bm.permille) < NovelBookmarks.DUP_TOLERANCE) {
        list.splice(i, 1);
        break;
      }
    }
    list.unshift(bm);
    if (list.length > NovelBookmarks.MAX_COUNT) {
      list.splice(NovelBookmarks.MAX_COUNT);
    }
    NovelBookmarks.save(mangaId, list);
    return list;
  }

  // 按落点时间删除书签；返回更新后的列表
  static remove(mangaId: number, time: number): NovelBookmark[] {
    const list = NovelBookmarks.list(mangaId);
    for (let i = 0; i < list.length; i++) {
      if (list[i].time === time) {
        list.splice(i, 1);
        break;
      }
    }
    NovelBookmarks.save(mangaId, list);
    return list;
  }

  // 列表中是否存在当前章节的近似进度书签（图标实心态判定）
  static hasAt(list: NovelBookmark[], chapterId: number, permille: number): boolean {
    for (let i = 0; i < list.length; i++) {
      if (list[i].chapterId === chapterId &&
        Math.abs(list[i].permille - permille) < NovelBookmarks.DUP_TOLERANCE) {
        return true;
      }
    }
    return false;
  }
}
