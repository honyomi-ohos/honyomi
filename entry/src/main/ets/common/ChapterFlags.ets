// 章节列表排序/筛选标志位（对齐 Mihon Manga.chapterFlags 位常量与
// SetMangaChapterFlags 的"同模式点击翻转方向、切模式重置方向"语义）
// 持久化于 manga.chapterFlags，详情页加载后解码、变更后回写。
export class ChapterFlags {
  // 排序方向：0 = 倒序（源顺序原样展示），1 = 正序（反向）
  static readonly SORT_DESC: number = 0x00000000;
  static readonly SORT_ASC: number = 0x00000001;
  static readonly SORT_DIR_MASK: number = 0x00000001;
  // 排序模式
  static readonly SORTING_SOURCE: number = 0x00000000;
  static readonly SORTING_NUMBER: number = 0x00000100;
  static readonly SORTING_UPLOAD_DATE: number = 0x00000200;
  static readonly SORTING_ALPHABET: number = 0x00000300;
  static readonly SORTING_MASK: number = 0x00000300;
  // 三态筛选：置 is 位 = 只看，置 not 位 = 排除，两 位皆空 = 忽略
  static readonly SHOW_UNREAD: number = 0x00000002;
  static readonly SHOW_READ: number = 0x00000004;
  static readonly UNREAD_MASK: number = 0x00000006;
  static readonly SHOW_DOWNLOADED: number = 0x00000008;
  static readonly SHOW_NOT_DOWNLOADED: number = 0x00000010;
  static readonly DOWNLOADED_MASK: number = 0x00000018;
  static readonly SHOW_BOOKMARKED: number = 0x00000020;
  static readonly SHOW_NOT_BOOKMARKED: number = 0x00000040;
  static readonly BOOKMARKED_MASK: number = 0x00000060;

  // 位运算助手：mask 内替换为 flag
  static setFlag(flags: number, flag: number, mask: number): number {
    return (flags & ~mask) | (flag & mask);
  }

  static sortingMode(flags: number): number {
    return flags & ChapterFlags.SORTING_MASK;
  }

  static isAscending(flags: number): boolean {
    return (flags & ChapterFlags.SORT_DIR_MASK) !== 0;
  }

  static unreadFilter(flags: number): string {
    const masked = flags & ChapterFlags.UNREAD_MASK;
    if (masked === ChapterFlags.SHOW_UNREAD) {
      return 'include';
    }
    if (masked === ChapterFlags.SHOW_READ) {
      return 'exclude';
    }
    return 'ignore';
  }

  static downloadedFilter(flags: number): string {
    const masked = flags & ChapterFlags.DOWNLOADED_MASK;
    if (masked === ChapterFlags.SHOW_DOWNLOADED) {
      return 'include';
    }
    if (masked === ChapterFlags.SHOW_NOT_DOWNLOADED) {
      return 'exclude';
    }
    return 'ignore';
  }

  static bookmarkedFilter(flags: number): string {
    const masked = flags & ChapterFlags.BOOKMARKED_MASK;
    if (masked === ChapterFlags.SHOW_BOOKMARKED) {
      return 'include';
    }
    if (masked === ChapterFlags.SHOW_NOT_BOOKMARKED) {
      return 'exclude';
    }
    return 'ignore';
  }

  // 当前状态编码回 flags
  static encode(mode: number, ascending: boolean, unread: string, downloaded: string, bookmarked: string): number {
    let flags = 0;
    flags = ChapterFlags.setFlag(flags, mode, ChapterFlags.SORTING_MASK);
    flags = ChapterFlags.setFlag(flags, ascending ? ChapterFlags.SORT_ASC : ChapterFlags.SORT_DESC,
      ChapterFlags.SORT_DIR_MASK);
    flags = ChapterFlags.setFlag(flags, ChapterFlags.triFlag(unread, ChapterFlags.SHOW_UNREAD, ChapterFlags.SHOW_READ),
      ChapterFlags.UNREAD_MASK);
    flags = ChapterFlags.setFlag(flags,
      ChapterFlags.triFlag(downloaded, ChapterFlags.SHOW_DOWNLOADED, ChapterFlags.SHOW_NOT_DOWNLOADED),
      ChapterFlags.DOWNLOADED_MASK);
    flags = ChapterFlags.setFlag(flags,
      ChapterFlags.triFlag(bookmarked, ChapterFlags.SHOW_BOOKMARKED, ChapterFlags.SHOW_NOT_BOOKMARKED),
      ChapterFlags.BOOKMARKED_MASK);
    return flags;
  }

  private static triFlag(value: string, isFlag: number, notFlag: number): number {
    if (value === 'include') {
      return isFlag;
    }
    if (value === 'exclude') {
      return notFlag;
    }
    return 0;
  }
}
