import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDb } from '../data/AppDb';
import { HistoryRepo, UpdatesRepo, MangaRepo, ChapterRepo, UpcomingRepo } from '../data/Repos';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { HistoryItem, MangaRecord, UpcomingManga } from '../model/Models';
import { ImageCache } from '../common/ImageCache';
import { Util } from '../common/Util';

const DOMAIN = 0x0001;
const TAG = 'WidgetUpdater';
const PREFS_NAME = 'widget_forms';
const PREFS_KEY = 'forms';
const PREFS_KEY_PENDING = 'pending_manga';
const ROW_COUNT = 3;
// refreshAll 总超时（毫秒）：超时后不再阻塞调用方，余下卡片在后台继续推送
const REFRESH_ALL_TIMEOUT_MS: number = 8000;

// forms 注册表写操作串行化：UIAbility 与 FormExtensionAbility 可能并发
// 读-改-写同一 preferences，模块级 Promise 链保证写操作互斥，避免丢失更新
let formChain: Promise<void> = Promise.resolve();

function runSerialFormOp<T>(op: () => Promise<T>): Promise<T> {
  const run: Promise<T> = formChain.then((): Promise<T> => op());
  // 无论成功失败都续链，避免一次失败卡死后续写操作
  formChain = run.then((): void => {}, (_e: Error): void => {});
  return run;
}

// 桌面卡片实例信息（持久化到 preferences，供应用侧主动刷新）
export class CardFormInfo {
  formId: string = '';
  name: string = '';
  wide: boolean = false;
  mangaId: number = 0; // 仅 MangaCard 使用
}

// 漫画卡片构建结果：data 推给 formProvider；coverFile 的 fd 由调用方在 updateForm 完成后关闭
export class MangaCardData {
  data: formBindingData.FormBindingData = formBindingData.createFormBindingData();
  coverFile: fs.File | undefined = undefined;
}

// 桌面卡片数据构建与主动刷新：
// - EntryFormAbility 与 UIAbility 共用（同 bundle 同模块，preferences/rdb 路径一致）
// - onAddForm 同步返回默认数据后异步补数据；应用退后台/书架刷新后 refreshAll 推送最新内容
export class WidgetUpdater {
  static async saveForm(context: common.Context, info: CardFormInfo): Promise<void> {
    await runSerialFormOp(async (): Promise<void> => {
      const forms = await WidgetUpdater.loadForms(context);
      let found = false;
      for (let i = 0; i < forms.length; i++) {
        if (forms[i].formId === info.formId) {
          forms[i] = info;
          found = true;
          break;
        }
      }
      if (!found) {
        forms.push(info);
      }
      await WidgetUpdater.writeForms(context, forms);
    });
  }

  static async removeForm(context: common.Context, formId: string): Promise<void> {
    await runSerialFormOp(async (): Promise<void> => {
      const forms = await WidgetUpdater.loadForms(context);
      const filtered: CardFormInfo[] = [];
      for (let i = 0; i < forms.length; i++) {
        if (forms[i].formId !== formId) {
          filtered.push(forms[i]);
        }
      }
      await WidgetUpdater.writeForms(context, filtered);
    });
  }

  static async loadForms(context: common.Context): Promise<CardFormInfo[]> {
    let raw: preferences.ValueType = '';
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFS_NAME });
      const has = await prefs.has(PREFS_KEY);
      if (!has) {
        return [];
      }
      raw = await prefs.get(PREFS_KEY, '');
    } catch (e) {
      throw new Error(`load widget forms failed: ${e}`);
    }
    if (typeof raw !== 'string') {
      return [];
    }
    if (raw === '') {
      return [];
    }
    try {
      const list = JSON.parse(raw) as CardFormInfo[];
      const forms: CardFormInfo[] = [];
      for (let i = 0; i < list.length; i++) {
        const f = list[i];
        // 逐字段规范化：旧记录可能缺字段/类型漂移（mangaId 为 undefined 而非 0 等）
        if (typeof f.formId !== 'string' || f.formId === '') {
          continue;
        }
        const info = new CardFormInfo();
        info.formId = f.formId;
        info.name = typeof f.name === 'string' ? f.name : '';
        info.wide = f.wide === true;
        info.mangaId = Number(f.mangaId) || 0;
        forms.push(info);
      }
      return forms;
    } catch (_e) {
      return [];
    }
  }

  private static async writeForms(context: common.Context, forms: CardFormInfo[]): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFS_NAME });
      await prefs.put(PREFS_KEY, JSON.stringify(forms));
      await prefs.flush();
    } catch (e) {
      throw new Error(`write widget forms failed: ${e}`);
    }
  }

  // ---------------- 漫画卡片 pending 机制 ----------------
  // 详情页发起 requestPublishForm 前写入 mangaId；onAddForm 必读必清（系统可能不转发自定义 want 参数）

  static async setPendingManga(context: common.Context, mangaId: number): Promise<void> {
    await runSerialFormOp(async (): Promise<void> => {
      const prefs = await preferences.getPreferences(context, { name: PREFS_NAME });
      await prefs.put(PREFS_KEY_PENDING, `${mangaId}`);
      await prefs.flush();
    });
  }

  // 读取并清除 pending mangaId；无则返回 0
  static async takePendingManga(context: common.Context): Promise<number> {
    return await runSerialFormOp(async (): Promise<number> => {
      const prefs = await preferences.getPreferences(context, { name: PREFS_NAME });
      const has = await prefs.has(PREFS_KEY_PENDING);
      if (!has) {
        return 0;
      }
      const raw = await prefs.get(PREFS_KEY_PENDING, '');
      await prefs.delete(PREFS_KEY_PENDING);
      await prefs.flush();
      if (typeof raw !== 'string' || raw === '') {
        return 0;
      }
      const id = Number(raw);
      return id > 0 ? Math.floor(id) : 0;
    });
  }

  // 刷新单个卡片（按表单名分发；漫画卡片需在 updateForm 完成后关闭封面 fd）
  static async refreshOne(context: common.Context, info: CardFormInfo): Promise<void> {
    try {
      if (info.name === 'MangaCard') {
        const built = await WidgetUpdater.buildMangaData(context, info.mangaId);
        try {
          await formProvider.updateForm(info.formId, built.data);
        } finally {
          if (built.coverFile !== undefined) {
            fs.closeSync(built.coverFile);
          }
        }
      } else {
        const data = await WidgetUpdater.buildData(context, info.name, info.wide);
        await formProvider.updateForm(info.formId, data);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'refreshOne %{public}s failed: %{public}s', info.formId, `${e}`);
    }
  }

  // 刷新全部已注册卡片（应用退后台 / 书架刷新完成后调用）；
  // 8 秒总超时保护：超时后调用方继续执行，余下卡片在后台继续推送
  static async refreshAll(context: common.Context): Promise<void> {
    const forms = await WidgetUpdater.loadForms(context);
    if (forms.length === 0) {
      return;
    }
    const total: Promise<void> = (async (): Promise<void> => {
      for (let i = 0; i < forms.length; i++) {
        await WidgetUpdater.refreshOne(context, forms[i]);
      }
    })();
    const timeout: Promise<void> = new Promise<void>((resolve: () => void) => {
      setTimeout((): void => {
        resolve();
      }, REFRESH_ALL_TIMEOUT_MS);
    });
    const racers: Array<Promise<void>> = [total, timeout];
    await Promise.race(racers);
  }

  // ---------------- 漫画卡片 ----------------

  // 漫画卡片添加：mangaId 解析（want 参数 → pending → 书架内最近阅读回退）→ 保存注册 → 刷新
  static async addMangaCard(context: common.Context, info: CardFormInfo): Promise<void> {
    await AppDb.ready(context);
    const pendingId = await WidgetUpdater.takePendingManga(context);
    if (info.mangaId === 0) {
      info.mangaId = pendingId;
    }
    if (info.mangaId === 0) {
      const last = await HistoryRepo.lastInLibrary();
      if (last !== undefined) {
        info.mangaId = last.mangaId;
      }
    }
    try {
      await WidgetUpdater.saveForm(context, info);
    } catch (e) {
      // 注册表保存失败不阻断内容推送：卡片本次仍可显示，
      // 但注册表缺失该条目，后续主动刷新（refreshAll/onUpdateForm）将无法覆盖此卡片
      hilog.warn(DOMAIN, TAG,
        'saveForm failed: form registry missing but card content still pushed: %{public}s', `${e}`);
    }
    await WidgetUpdater.refreshOne(context, info);
  }

  // 构建漫画卡片数据：封面（formImages fd）+ 标题 + 续读章节（最近阅读 → 第一条未读）
  static async buildMangaData(context: common.Context, mangaId: number): Promise<MangaCardData> {
    const built = new MangaCardData();
    const record: Record<string, string | number | boolean> = {
      'empty': true, 'hasCover': false, 'hasChapter': false,
      'title': '', 'chapter': '', 'mangaId': '', 'chapterId': '', 'contentType': 'manga'
    };
    await AppDb.ready(context);
    const manga: MangaRecord | undefined = mangaId > 0 ? await MangaRepo.get(mangaId) : undefined;
    if (manga === undefined) {
      built.data = formBindingData.createFormBindingData(record);
      return built;
    }
    record['empty'] = false;
    record['title'] = manga.title;
    record['mangaId'] = `${manga.id}`;
    record['contentType'] = manga.contentType;
    let chapterId = 0;
    let chapterName = '';
    const last = await HistoryRepo.lastForManga(manga.id);
    if (last !== undefined) {
      chapterId = last.chapterId;
      chapterName = last.chapterName;
    } else {
      const firstUnread = await ChapterRepo.firstUnreadChapter(manga.id);
      if (firstUnread !== undefined) {
        chapterId = firstUnread.id;
        chapterName = firstUnread.name;
      }
    }
    if (chapterId > 0) {
      record['hasChapter'] = true;
      record['chapter'] = chapterName;
      record['chapterId'] = `${chapterId}`;
    }
    let coverPath = await ImageCache.ensureLocal(context, manga.thumbnailUrl, manga.sourceKey);
    if (coverPath.indexOf('file://') === 0) {
      coverPath = coverPath.substring('file://'.length);
    }
    let file: fs.File | undefined = undefined;
    try {
      if (coverPath !== '' && fs.accessSync(coverPath)) {
        file = fs.openSync(coverPath, fs.OpenMode.READ_ONLY);
      }
    } catch (e) {
      throw new Error(`open cover file failed: ${e}`);
    }
    if (file !== undefined) {
      record['hasCover'] = true;
      const formImages: Record<string, number> = { 'cover': file.fd };
      const payload: Record<string, Object> = {};
      const keys = Object.keys(record);
      for (let i = 0; i < keys.length; i++) {
        payload[keys[i]] = record[keys[i]];
      }
      payload['formImages'] = formImages;
      built.data = formBindingData.createFormBindingData(payload);
      built.coverFile = file;
    } else {
      built.data = formBindingData.createFormBindingData(record);
    }
    return built;
  }

  // 构建卡片数据：RecentCard / UpdatesCard / UpcomingCard，行内容平铺为 t{i}/c{i}/m{i}/ch{i}/time{i}/b{i}
  static async buildData(context: common.Context, name: string, wide: boolean):
    Promise<formBindingData.FormBindingData> {
    if (name === 'StatsWeekCard' || name === 'StatsMonthCard') {
      return await WidgetUpdater.buildStatsData(context, name, wide);
    }
    const record: Record<string, string | number | boolean> = { 'wide': wide };
    await AppDb.ready(context);
    if (name === 'RecentCard') {
      const items = await WidgetUpdater.dedupRecent(await HistoryRepo.recent(12));
      for (let i = 0; i < ROW_COUNT; i++) {
        const item = i < items.length ? items[i] : undefined;
        record[`t${i}`] = item !== undefined ? item.mangaTitle : '';
        record[`c${i}`] = item !== undefined ? item.chapterName : '';
        record[`m${i}`] = item !== undefined ? `${item.mangaId}` : '';
        record[`ch${i}`] = item !== undefined ? `${item.chapterId}` : '';
        record[`time${i}`] = item !== undefined ? WidgetUpdater.timeText(item.seenAt) : '';
        record[`b${i}`] = item !== undefined ? WidgetUpdater.badgeChar(item.mangaTitle) : '';
      }
    } else if (name === 'UpcomingCard') {
      const items = await UpcomingRepo.upcomingList();
      for (let i = 0; i < ROW_COUNT; i++) {
        const item: UpcomingManga | undefined = i < items.length ? items[i] : undefined;
        record[`t${i}`] = item !== undefined ? item.title : '';
        record[`d${i}`] = item !== undefined ? WidgetUpdater.upcomingDateText(context, item.expectedAt) : '';
        record[`m${i}`] = item !== undefined ? `${item.mangaId}` : '';
        record[`b${i}`] = item !== undefined ? WidgetUpdater.badgeChar(item.title) : '';
      }
    } else {
      const items = await UpdatesRepo.unreadChapters(ROW_COUNT);
      const total = await UpdatesRepo.unreadCount();
      let countText: string = '';
      if (total > 0) {
        try {
          countText = context.resourceManager.getStringSync($r('app.string.card_unread_count').id, total);
        } catch (e) {
          throw new Error(`load unread count text failed: ${e}`);
        }
      }
      record['countText'] = countText;
      for (let i = 0; i < ROW_COUNT; i++) {
        const item = i < items.length ? items[i] : undefined;
        record[`t${i}`] = item !== undefined ? item.mangaTitle : '';
        record[`c${i}`] = item !== undefined ? item.chapterName : '';
        record[`m${i}`] = item !== undefined ? `${item.mangaId}` : '';
        record[`ch${i}`] = item !== undefined ? `${item.chapterId}` : '';
        record[`time${i}`] = item !== undefined ? WidgetUpdater.timeText(item.dateUpload) : '';
        record[`b${i}`] = item !== undefined ? WidgetUpdater.badgeChar(item.mangaTitle) : '';
      }
    }
    return formBindingData.createFormBindingData(record);
  }

  // 构建统计卡片数据：周（周一~周日）/ 月（1 日~月末）每日阅读时长柱状图
  // 柱高预计算为 vp 数值，平铺为逗号串（卡片侧 ForEach 渲染）；周卡片附带星期标签
  private static async buildStatsData(context: common.Context, name: string, wide: boolean):
    Promise<formBindingData.FormBindingData> {
    await AppDb.ready(context);
    const week = name === 'StatsWeekCard';
    const now = new Date();
    const range = week ? ReadingStatsRepo.weekRange(now) : ReadingStatsRepo.monthRange(now);
    const totals = await ReadingStatsRepo.dailyTotals(range[0], range[1]);
    const days = ReadingStatsRepo.buildRange(range[0], range[1], totals);
    let totalSeconds = 0;
    let maxV = 0;
    for (let i = 0; i < days.length; i++) {
      totalSeconds += days[i].seconds;
      if (days[i].seconds > maxV) {
        maxV = days[i].seconds;
      }
    }
    const month = now.getMonth() + 1;
    let titleText: string = '';
    let totalText: string = '';
    try {
      titleText = context.resourceManager.getStringSync(
        week ? $r('app.string.card_stats_week_display').id : $r('app.string.card_stats_month_display').id);
      totalText = context.resourceManager.getStringSync(week
        ? $r('app.string.stats_week_total').id
        : $r('app.string.stats_month_total').id, Util.formatDuration(context, totalSeconds));
    } catch (e) {
      throw new Error(`load stats card text failed: ${e}`);
    }
    const record: Record<string, string | number | boolean> = {
      'wide': wide,
      'empty': totalSeconds <= 0,
      'titleText': titleText,
      'rangeText': week
        ? `${range[0].substring(5)} ~ ${range[1].substring(5)}`
        : `${now.getFullYear()}-${WidgetUpdater.pad2(month)}`,
      'totalText': totalText,
      'bars': '',
      'labels': '',
    };
    // 柱高（vp）：无数据 2vp 底线，其余按最大值等比缩放
    const chartH = wide ? 80 : 52;
    const heights: string[] = [];
    const labels: string[] = [];
    for (let i = 0; i < days.length; i++) {
      const v = days[i].seconds;
      if (v <= 0 || maxV <= 0) {
        heights.push('2');
      } else {
        heights.push(`${Math.max(4, Math.round(v / maxV * chartH))}`);
      }
      if (week) {
        labels.push(Util.weekdayShort(context, ReadingStatsRepo.dayOfWeek(days[i].day)));
      }
    }
    record['bars'] = heights.join(',');
    record['labels'] = labels.join(',');
    return formBindingData.createFormBindingData(record);
  }

  private static pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  // 同一部漫画只保留最近一条阅读记录
  private static dedupRecent(items: HistoryItem[]): HistoryItem[] {
    const seen = new Set<number>();
    const list: HistoryItem[] = [];
    for (let i = 0; i < items.length; i++) {
      if (seen.has(items[i].mangaId)) {
        continue;
      }
      seen.add(items[i].mangaId);
      list.push(items[i]);
      if (list.length >= ROW_COUNT) {
        break;
      }
    }
    return list;
  }

  // 按系统语言格式化的短日期（月-日）/ 全日期（年-月-日），替代硬编码 MM-dd / yyyy-MM-dd
  private static formatShortDate(d: Date): string {
    const fmt = new Intl.DateTimeFormat(undefined, { month: '2-digit', day: '2-digit' });
    return fmt.format(d);
  }

  private static formatFullDate(d: Date): string {
    const fmt = new Intl.DateTimeFormat(undefined, { year: 'numeric', month: '2-digit', day: '2-digit' });
    return fmt.format(d);
  }

  // 语言无关的紧凑时间：当天 HH:mm，同年/跨年按系统语言经 Intl 格式化日期
  private static timeText(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const d = new Date(ms);
    const now = new Date();
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    const sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() &&
      d.getDate() === now.getDate();
    if (sameDay) {
      return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    }
    if (d.getFullYear() === now.getFullYear()) {
      return WidgetUpdater.formatShortDate(d);
    }
    return WidgetUpdater.formatFullDate(d);
  }

  // 即将推出日期文本（与页面 relativeDate 一致）：今天 / N 天前 / N 天后 / 同年 MM-dd / 跨年 YYYY-MM-dd
  private static upcomingDateText(context: common.Context, ms: number): string {
    const startOf = (t: number): number => {
      const x: Date = new Date(t);
      return new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
    };
    const diff: number = Math.round((startOf(Date.now()) - startOf(ms)) / (24 * 60 * 60 * 1000));
    if (diff === 0) {
      try {
        return context.resourceManager.getStringSync($r('app.string.relative_time_today').id);
      } catch (e) {
        throw new Error(`load upcoming date text failed: ${e}`);
      }
    }
    if (diff > 0 && diff < 7) {
      try {
        return context.resourceManager.getStringSync($r('app.string.relative_time_days_ago').id, diff);
      } catch (e) {
        throw new Error(`load upcoming date text failed: ${e}`);
      }
    }
    if (diff < 0 && diff >= -7) {
      try {
        return context.resourceManager.getStringSync($r('app.string.upcoming_relative_time_days').id, -diff);
      } catch (e) {
        throw new Error(`load upcoming date text failed: ${e}`);
      }
    }
    const d: Date = new Date(ms);
    const now: Date = new Date();
    if (d.getFullYear() === now.getFullYear()) {
      return WidgetUpdater.formatShortDate(d);
    }
    return WidgetUpdater.formatFullDate(d);
  }

  // 行首徽标字符：标题首字符（拉丁转大写）
  private static badgeChar(title: string): string {
    if (title === '') {
      return '#';
    }
    return title.charAt(0).toUpperCase();
  }
}
