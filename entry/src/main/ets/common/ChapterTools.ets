import { ChapterRecord } from '../model/Models';

// 章节名汉化组解析（对齐 Mihon SChapter.scanlator 约定）：
// 源未显式提供 scanlator 时，从章节名前缀 [组名] / 【组名】 提取
export class ScanlatorParser {
  private static readonly BRACKET_RE: RegExp = new RegExp('^[\\s]*[\\[【（(]([^\\]】）)]+)[\\]】）)]');

  static parse(chapterName: string): string {
    const m = ScanlatorParser.BRACKET_RE.exec(chapterName);
    return m !== null ? m[1].trim() : '';
  }
}

// 缺失章节检测（对齐 Mihon viewer/MissingChapters.calculateMissingChapters）：
// 章节号取整后在 [min, max] 序列中的缺口计数；仅统计 >= 1 的章节号
export class MissingChapters {
  // 缺失章节数（数据不足/无缺口返回 0）
  static count(chapters: ChapterRecord[]): number {
    if (chapters.length === 0) {
      return 0;
    }
    const present = new Set<number>();
    for (const c of chapters) {
      const rounded = Math.round(c.chapterNumber);
      if (rounded >= 1) {
        present.add(rounded);
      }
    }
    if (present.size === 0) {
      return 0;
    }
    let min = Number.MAX_VALUE;
    let max = 0;
    present.forEach((n: number): void => {
      if (n < min) {
        min = n;
      }
      if (n > max) {
        max = n;
      }
    });
    const missing = (max - min + 1) - present.size;
    return missing > 0 ? missing : 0;
  }
}
