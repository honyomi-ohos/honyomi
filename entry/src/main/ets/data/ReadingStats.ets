import { relationalStore } from '@kit.ArkData';
import { AppDb } from './AppDb';
import { Util } from '../common/Util';

// 每日阅读时长（统计图数据点）
export class DayDuration {
  day: string = ''; // YYYY-MM-DD
  seconds: number = 0;
}

// 阅读时长统计：会话记录（readingSession 表）+ 按日聚合查询
// 会话跟踪对齐 Mihon ReaderViewModel：进入章节开始计时，切章/退出/应用退后台时结算落库；
// 无痕浏览不记录。翻页时超过 2 分钟的会话先落库再重启计时（防崩溃丢失过长会话）。
export class ReadingStatsRepo {
  private static activeMangaId: number = -1;
  private static activeChapterId: number = -1;
  private static activeStartAt: number = 0;

  // 开始/重启一段阅读会话计时
  static begin(mangaId: number, chapterId: number): void {
    ReadingStatsRepo.activeMangaId = mangaId;
    ReadingStatsRepo.activeChapterId = chapterId;
    ReadingStatsRepo.activeStartAt = Date.now();
  }

  // 翻页时调用：会话累计超过 2 分钟则先落库再重启计时
  static tick(): void {
    if (ReadingStatsRepo.activeStartAt === 0) {
      return;
    }
    if (Date.now() - ReadingStatsRepo.activeStartAt >= 120000) {
      const mangaId = ReadingStatsRepo.activeMangaId;
      const chapterId = ReadingStatsRepo.activeChapterId;
      ReadingStatsRepo.flush();
      ReadingStatsRepo.begin(mangaId, chapterId);
    }
  }

  // 结束当前会话并落库（无痕浏览不记录）
  static flush(): void {
    if (ReadingStatsRepo.activeStartAt === 0) {
      return;
    }
    const mangaId = ReadingStatsRepo.activeMangaId;
    const chapterId = ReadingStatsRepo.activeChapterId;
    const startAt = ReadingStatsRepo.activeStartAt;
    ReadingStatsRepo.activeStartAt = 0;
    const seconds = Math.floor((Date.now() - startAt) / 1000);
    if (seconds < 1) {
      return;
    }
    ReadingStatsRepo.insertSession(mangaId, chapterId, startAt, seconds);
  }

  private static async insertSession(mangaId: number, chapterId: number,
    startAt: number, seconds: number): Promise<void> {
    if (AppStorage.get<boolean>('incognito') ?? false) {
      return;
    }
    try {
      const store = await AppDb.get();
      const values: relationalStore.ValuesBucket = {
        'mangaId': mangaId,
        'chapterId': chapterId,
        'day': Util.formatDate(startAt),
        'startTime': startAt,
        'duration': seconds,
      };
      await store.insert('readingSession', values);
    } catch (_e) {
      // 落库失败不影响阅读
    }
  }

  // 总阅读时长（秒）
  static async totalDuration(): Promise<number> {
    const store = await AppDb.get();
    const rs = await store.querySql(
      `SELECT COALESCE(SUM(duration), 0) AS total FROM readingSession`);
    let total = 0;
    if (rs.goToNextRow()) {
      total = rs.getLong(rs.getColumnIndex('total'));
    }
    rs.close();
    return total;
  }

  // [fromDay, toDay] 区间内每日阅读时长（秒），key 为 YYYY-MM-DD
  static async dailyTotals(fromDay: string, toDay: string): Promise<Record<string, number>> {
    const store = await AppDb.get();
    const rs = await store.querySql(
      `SELECT day, COALESCE(SUM(duration), 0) AS total FROM readingSession
       WHERE day >= ? AND day <= ? GROUP BY day`, [fromDay, toDay]);
    const totals: Record<string, number> = {};
    while (rs.goToNextRow()) {
      totals[rs.getString(rs.getColumnIndex('day'))] = rs.getLong(rs.getColumnIndex('total'));
    }
    rs.close();
    return totals;
  }

  // 构建覆盖 [fromDay, toDay] 的每日数据点（缺失日补 0）
  static buildRange(fromDay: string, toDay: string, totals: Record<string, number>): DayDuration[] {
    const list: DayDuration[] = [];
    const from = ReadingStatsRepo.parseDay(fromDay);
    const to = ReadingStatsRepo.parseDay(toDay);
    if (from === undefined || to === undefined) {
      return list;
    }
    const cur = new Date(from.getTime());
    while (cur.getTime() <= to.getTime()) {
      const key = Util.formatDate(cur.getTime());
      const item = new DayDuration();
      item.day = key;
      item.seconds = totals[key] ?? 0;
      list.push(item);
      cur.setDate(cur.getDate() + 1);
    }
    return list;
  }

  // 本周区间（周一 ~ 周日）：[fromDay, toDay]
  static weekRange(now: Date): string[] {
    const offset = (now.getDay() + 6) % 7; // 周一为一周起点
    const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset);
    const sunday = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 6);
    return [Util.formatDate(monday.getTime()), Util.formatDate(sunday.getTime())];
  }

  // 本月区间（1 日 ~ 月末）：[fromDay, toDay]
  static monthRange(now: Date): string[] {
    const first = new Date(now.getFullYear(), now.getMonth(), 1);
    const last = new Date(now.getFullYear(), now.getMonth() + 1, 0);
    return [Util.formatDate(first.getTime()), Util.formatDate(last.getTime())];
  }

  // 某天（YYYY-MM-DD）的星期序号：0=周日 .. 6=周六；解析失败返回 -1
  static dayOfWeek(day: string): number {
    const d = ReadingStatsRepo.parseDay(day);
    return d === undefined ? -1 : d.getDay();
  }

  private static parseDay(day: string): Date | undefined {
    const parts = day.split('-');
    if (parts.length !== 3) {
      return undefined;
    }
    const y = Number(parts[0]);
    const m = Number(parts[1]);
    const d = Number(parts[2]);
    if (Number.isNaN(y) || Number.isNaN(m) || Number.isNaN(d)) {
      return undefined;
    }
    return new Date(y, m - 1, d);
  }
}
