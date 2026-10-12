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
  }

  static async removeForm(context: common.Context, formId: string): Promise<void> {
    const forms = await WidgetUpdater.loadForms(context);
    const filtered: CardFormInfo[] = [];
    for (let i = 0; i < forms.length; i++) {
      if (forms[i].formId !== formId) {
        filtered.push(forms[i]);
      }
    }
    await WidgetUpdater.writeForms(context, filtered);
  }

  static async loadForms(context: common.Context): Promise<CardFormInfo[]> {
    const prefs = await preferences.getPreferences(context, { name: PREFS_NAME });
    const has = await prefs.has(PREFS_KEY);
    if (!has) {
      return [];
    }
    const raw = await prefs.get(PREFS_KEY, '');
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
        if (list[i].formId !== undefined && list[i].name !== undefined) {
          forms.push(list[i]);
        }
      }
      return forms;
    } catch (_e) {
      return [];
    }
  }

  private static async writeForms(context: common.Context, forms: CardFormInfo[]): Promise<void> {
    const prefs = await preferences.getPreferences(context, { name: PREFS_NAME });
    await prefs.put(PREFS_KEY, JSON.stringify(forms));
    await prefs.flush();
  }

  // ---------------- 漫画卡片 pending 机制 ----------------
  // 详情页发起 requestPublishForm 前写入 mangaId；onAddForm 必读必清（系统可能不转发自定义 want 参数）

  static async setPendingManga(context: common.Context, mangaId: number): Promise<void> {
    const prefs = await preferences.getPreferences(context, { name: PREFS_NAME });
    await prefs.put(PREFS_KEY_PENDING, `${mangaId}`);
    await prefs.flush();
  }

  // 读取并清除 pending mangaId；无则返回 0
  static async takePendingManga(context: common.Context): Promise<number> {
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

  // 刷新全部已注册卡片（应用退后台 / 书架刷新完成后调用）
  static async refreshAll(context: common.Context): Promise<void> {
    const forms = await WidgetUpdater.loadForms(context);
    for (let i = 0; i < forms.length; i++) {
      await WidgetUpdater.refreshOne(context, forms[i]);
    }
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
    await WidgetUpdater.saveForm(context, info);
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
    if (coverPath !== '' && fs.accessSync(coverPath)) {
      const file = fs.openSync(coverPath, fs.OpenMode.READ_ONLY);
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
      record['countText'] = total > 0
        ? context.resourceManager.getStringSync($r('app.string.card_unread_count'), total)
        : '';
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
    const record: Record<string, string | number | boolean> = {
      'wide': wide,
      'empty': totalSeconds <= 0,
      'titleText': context.resourceManager.getStringSync(
        week ? $r('app.string.card_stats_week_display') : $r('app.string.card_stats_month_display')),
      'rangeText': week
        ? `${range[0].substring(5)} ~ ${range[1].substring(5)}`
        : `${now.getFullYear()}-${WidgetUpdater.pad2(month)}`,
      'totalText': context.resourceManager.getStringSync(week
        ? $r('app.string.stats_week_total')
        : $r('app.string.stats_month_total'), Util.formatDuration(context, totalSeconds)),
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

  // 语言无关的紧凑时间：当天 HH:mm，同年 MM-dd，跨年 YYYY-MM-dd
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
      return `${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    }
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }

  // 即将推出日期文本（与页面 relativeDate 一致）：今天 / N 天前 / N 天后 / 同年 MM-dd / 跨年 YYYY-MM-dd
  private static upcomingDateText(context: common.Context, ms: number): string {
    const startOf = (t: number): number => {
      const x: Date = new Date(t);
      return new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
    };
    const diff: number = Math.round((startOf(Date.now()) - startOf(ms)) / (24 * 60 * 60 * 1000));
    if (diff === 0) {
      return context.resourceManager.getStringSync($r('app.string.relative_time_today'));
    }
    if (diff > 0 && diff < 7) {
      return context.resourceManager.getStringSync($r('app.string.relative_time_days_ago'), diff);
    }
    if (diff < 0 && diff >= -7) {
      return context.resourceManager.getStringSync($r('app.string.upcoming_relative_time_days'), -diff);
    }
    const d: Date = new Date(ms);
    const now: Date = new Date();
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    if (d.getFullYear() === now.getFullYear()) {
      return `${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    }
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }

  // 行首徽标字符：标题首字符（拉丁转大写）
  private static badgeChar(title: string): string {
    if (title === '') {
      return '#';
    }
    return title.charAt(0).toUpperCase();
  }
}
