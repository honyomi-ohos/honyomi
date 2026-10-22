import { i18n } from '@kit.LocalizationKit';
import { AppDb } from '../data/AppDb';
import { SheetPreset } from './components/SheetPreset';
import { CategoryRepo, UpcomingRepo } from '../data/Repos';
import { CategoryRecord, UpcomingManga } from '../model/Models';
import { DetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Settings } from '../common/Settings';
import { Util } from '../common/Util';
import { PageHeader } from './components/PageHeader';
import { AppIcon } from './components/AppIcon';
import { CoverPlaceholder } from './components/CoverPlaceholder';
import { UpdatesFilterSheet } from './components/UpdatesFilterSheet';

// 即将推出页帮助：跳转应用内帮助文档（更新与「即将更新」小节）
const DAY_MS: number = 24 * 60 * 60 * 1000;

// 列表行模型：日期分组头 / 漫画条目
class UpcomingRow {
  isHeader: boolean = false;
  dateMs: number = 0;
  count: number = 0;
  manga: UpcomingManga | undefined = undefined;
}

function startOfDay(ms: number): number {
  const d: Date = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}

function dateKeyOf(ms: number): string {
  const d: Date = new Date(ms);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

// 即将推出页（对齐 Mihon UpcomingScreen）：
// 月历（今日描边、过去置灰、最多 3 个主色圆点指示）+ 按预计更新日分组的列表
// 数据：书架内连载中/完结连载漫画，按章节上传间隔推算预计更新时间（FetchInterval 移植）
@Component
export struct UpcomingPage {
  // 路由栈：NavDestination onReady 时从自身上下文获取（官方推荐方式）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @State allManga: UpcomingManga[] = [];
  @State rows: UpcomingRow[] = [];
  @State events: Record<string, number> = {};
  @State selYear: number = 0;
  @State selMonth: number = 0;
  @State showFilterSheet: boolean = false;
  // Index 根节点 Esc 广播：关闭筛选弹层（计数器递增触发）
  @StorageLink('sheetEsc') @Watch('onSheetEsc') sheetEsc: number = 0;
  @State categories: CategoryRecord[] = [];
  @State includedCats: number[] = [];
  @State excludedCats: number[] = [];
  private headerIndex: Record<string, number> = {};
  private scroller: Scroller = new Scroller();
  private firstDayOfWeek: number = 1;
  private weekdayLabels: string[] = [];
  private monthFmt: Intl.DateTimeFormat | undefined = undefined;

  aboutToAppear(): void {
    const now: Date = new Date();
    this.selYear = now.getFullYear();
    this.selMonth = now.getMonth() + 1;
    try {
      const cal: i18n.Calendar = i18n.getCalendar(this.localeTag(), 'gregory');
      this.firstDayOfWeek = cal.getFirstDayOfWeek();
    } catch (e) {
      this.firstDayOfWeek = 1;
    }
    try {
      this.monthFmt = new Intl.DateTimeFormat(this.localeTag(), { year: 'numeric', month: 'long' });
    } catch (e) {
      this.monthFmt = undefined;
    }
    this.buildWeekdayLabels();
    this.loadData();
  }

  // Esc 广播：关闭筛选半模态弹层
  onSheetEsc(): void {
    if (this.showFilterSheet) {
      this.showFilterSheet = false;
    }
  }

  async loadData(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    await AppDb.ready(context);
    this.categories = await CategoryRepo.list();
    this.includedCats = Settings.getUpcomingIncludedCategories();
    this.excludedCats = Settings.getUpcomingExcludedCategories();
    this.allManga = await UpcomingRepo.upcomingList();
    this.recompute();
  }

  @Builder
  filterSheetBuilder() {
    UpdatesFilterSheet({
      categories: this.categories,
      showFilterTab: false,
      initIncluded: this.includedCats,
      initExcluded: this.excludedCats,
      onCategoriesChanged: (included: number[], excluded: number[]): void => {
        this.includedCats = included;
        this.excludedCats = excluded;
        Settings.setUpcomingIncludedCategories(included);
        Settings.setUpcomingExcludedCategories(excluded);
        this.recompute();
      }
    })
  }

  // 页面主体：滚动容器全宽（滚动条贴窗口边），内容列经 contentInset 限宽居中（720 上限）
  private inset(): number {
    return Bp.contentInset(this.windowW);
  }

  @Builder
  dayCell(day: number) {
    Stack() {
      if (this.cellDateMs(day) === this.todayStart()) {
        Column()
          .width(40)
          .height(40)
          .borderRadius(20)
          .border({ width: 1, color: this.pal.text })
      }
      Text(`${day}`)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.cellDateMs(day) < this.todayStart() ? this.pal.sub : this.pal.text)
      Row({ space: 2 }) {
        ForEach(this.dayDots(day), (i: number) => {
          Column()
            .width(5)
            .height(5)
            .borderRadius(2.5)
            .backgroundColor(this.pal.primary)
            .opacity((i + 1) * 0.3)
        }, (i: number) => `dot-${i}`)
      }
      .translate({ y: 14 })
    }
    .layoutWeight(1)
    .height(48)
    .onClick(() => {
      this.onDayClick(day);
    })
  }

  @Builder
  dateHeader(row: UpcomingRow) {
    Row() {
      Text(this.relativeDate(row.dateMs))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal.sub)
        .maxLines(1)
      Text(`${row.count}`)
        .fontSize(11)
        .fontColor(this.pal.onPrimary)
        .backgroundColor(this.pal.primary)
        .borderRadius(10)
        .padding({
          left: 6,
          right: 6,
          top: 1,
          bottom: 1
        })
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({
      left: 16 + this.inset(),
      right: 16 + this.inset(),
      top: 8,
      bottom: 8
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  mangaItem(m: UpcomingManga) {
    Row({ space: 16 }) {
      if (m.coverUrl === '') {
        // 无封面：默认封面占位
        CoverPlaceholder({ iconSize: 24 })
          .width(56)
          .height(80)
          .borderRadius(4)
      } else {
        Image(m.coverUrl)
          .width(56)
          .height(80)
          .objectFit(ImageFit.Cover)
          .borderRadius(4)
          .backgroundColor(this.pal.chip)
      }
      Text(m.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal.text)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(96)
    .padding({
      left: 16 + this.inset(),
      right: 16 + this.inset(),
      top: 8,
      bottom: 8
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      const params: DetailParams = { mangaId: m.mangaId };
      this.pathStack.pushPathByName('MangaDetail', params);
    })
  }

  @Builder
  calendarBlock() {
    Column({ space: 4 }) {
      // 月份切换头
      Row() {
        Text(this.monthTitle())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
          .maxLines(1)
          .padding({ left: 16 + this.inset() })
        AppIcon({ name: 'keyboard_arrow_left', iconSize: 24, tint: this.pal.text })
          .padding({
            left: 8,
            right: 8,
            top: 8,
            bottom: 8
          })
          .onClick(() => {
            this.shiftMonth(-1);
          })
        AppIcon({ name: 'keyboard_arrow_right', iconSize: 24, tint: this.pal.text })
          .padding({
            left: 8,
            right: 8,
            top: 8,
            bottom: 8
          })
          .onClick(() => {
            this.shiftMonth(1);
          })
      }
      .width('100%')

      // 星期标题行
      Row() {
        ForEach(this.weekdayLabels, (label: string, col: number) => {
          Text(label)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal.text)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .maxLines(1)
        }, (label: string, col: number) => `wd-${col}`)
      }
      .width('100%')
      .padding({ left: 8 + this.inset(), right: 8 + this.inset() })

      // 日期网格
      ForEach(this.monthWeeks(), (week: number[], weekIdx: number) => {
        Row() {
          ForEach(week, (day: number, col: number) => {
            if (day === 0) {
              Column()
                .layoutWeight(1)
                .height(48)
            } else {
              this.dayCell(day)
            }
          }, (day: number, col: number) => `d-${weekIdx}-${col}`)
        }
        .width('100%')
        .padding({ left: 8 + this.inset(), right: 8 + this.inset() })
      }, (week: number[], weekIdx: number) => `w-${this.selYear}-${this.selMonth}-${weekIdx}`)
    }
    .width('100%')
    .padding({ top: 4, bottom: 8 })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.label_upcoming'), inset: this.inset() }) {
          AppIcon({ name: 'filter_list', iconSize: 22, tint: this.filterActive() ? this.pal.primary : this.pal.text })
            .padding({ left: 12 })
            .onClick(() => {
              this.showFilterSheet = true;
            })
            .bindSheet($$this.showFilterSheet, this.filterSheetBuilder(),
              SheetPreset.fit(this.windowW, {
                height: Bp.sheetHeight(this.windowW),
                detents: ['60%', SheetSize.LARGE],
                showClose: false,
                bg: this.pal.bg
              }))
          AppIcon({ name: 'help', iconSize: 22, tint: this.pal.text })
            .padding({ left: 12 })
            .onClick(() => {
              this.pathStack.pushPathByName('Help', null);
            })
        }

        Column() {
          List({ scroller: this.scroller }) {
            ListItem() {
              this.calendarBlock()
            }

            ForEach(this.rows, (row: UpcomingRow, idx: number) => {
              ListItem() {
                if (row.isHeader) {
                  this.dateHeader(row)
                } else if (row.manga !== undefined) {
                  this.mangaItem(row.manga)
                }
              }
            }, (row: UpcomingRow, idx: number) => row.isHeader ? `uh-${row.dateMs}` : `ui-${row.manga?.mangaId ?? idx}`)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .contentEndOffset(this.navBarH + 16)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
    .backgroundColor(this.pal.bg)
  }

  private localeTag(): string {
    const lang: string = Settings.getAppLanguage();
    if (lang === 'auto') {
      return i18n.System.getSystemLanguage();
    }
    return lang;
  }

  // 星期短标签按本地一周首日排序（0=周日..6=周六 → stats_wd_*）
  private buildWeekdayLabels(): void {
    const ctx = Util.hostAbilityContext(this.getUIContext());
    const firstJs: number = this.firstDayOfWeek % 7;
    this.weekdayLabels = [];
    for (let col = 0; col < 7; col++) {
      this.weekdayLabels.push(Util.weekdayShort(ctx, (firstJs + col) % 7));
    }
  }

  // 分类筛选：排除优先；包含非空时作白名单（对齐 UpcomingViewModel.cycleCategory 语义）
  private catAllowed(categoryId: number): boolean {
    if (this.excludedCats.indexOf(categoryId) >= 0) {
      return false;
    }
    if (this.includedCats.length > 0 && this.includedCats.indexOf(categoryId) < 0) {
      return false;
    }
    return true;
  }

  private filterActive(): boolean {
    return this.includedCats.length > 0 || this.excludedCats.length > 0;
  }

  // 过滤 + 按预计日分组，生成分组头/条目行与日历事件计数
  private recompute(): void {
    const shown: UpcomingManga[] = [];
    for (const m of this.allManga) {
      if (this.catAllowed(m.categoryId)) {
        shown.push(m);
      }
    }
    shown.sort((a: UpcomingManga, b: UpcomingManga): number => {
      if (a.expectedAt !== b.expectedAt) {
        return a.expectedAt - b.expectedAt;
      }
      return a.title < b.title ? -1 : (a.title > b.title ? 1 : 0);
    });
    const counts: Record<string, number> = {};
    for (const m of shown) {
      const key: string = dateKeyOf(m.expectedAt);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    const rows: UpcomingRow[] = [];
    const headerIndex: Record<string, number> = {};
    let lastKey: string = '';
    for (const m of shown) {
      const key: string = dateKeyOf(m.expectedAt);
      if (key !== lastKey) {
        headerIndex[key] = rows.length;
        const header: UpcomingRow = new UpcomingRow();
        header.isHeader = true;
        header.dateMs = m.expectedAt;
        header.count = counts[key] ?? 0;
        rows.push(header);
        lastKey = key;
      }
      const row: UpcomingRow = new UpcomingRow();
      row.manga = m;
      rows.push(row);
    }
    this.rows = rows;
    this.events = counts;
    this.headerIndex = headerIndex;
  }

  private shiftMonth(delta: number): void {
    let month: number = this.selMonth + delta;
    let year: number = this.selYear;
    if (month < 1) {
      month = 12;
      year -= 1;
    } else if (month > 12) {
      month = 1;
      year += 1;
    }
    this.selMonth = month;
    this.selYear = year;
  }

  private monthTitle(): string {
    const date: Date = new Date(this.selYear, this.selMonth - 1, 1);
    if (this.monthFmt !== undefined) {
      try {
        return this.monthFmt.format(date);
      } catch (e) {
        // 格式化失败回退数字形式
      }
    }
    return `${this.selYear}-${this.selMonth}`;
  }

  // 当月单元格：0 表示空位（前导/尾随补齐）
  private monthCells(): number[] {
    const cells: number[] = [];
    const firstDate: Date = new Date(this.selYear, this.selMonth - 1, 1);
    const daysInMonth: number = new Date(this.selYear, this.selMonth, 0).getDate();
    const firstJs: number = this.firstDayOfWeek % 7;
    const leading: number = (firstDate.getDay() - firstJs + 7) % 7;
    for (let i = 0; i < leading; i++) {
      cells.push(0);
    }
    for (let d = 1; d <= daysInMonth; d++) {
      cells.push(d);
    }
    while (cells.length % 7 !== 0) {
      cells.push(0);
    }
    return cells;
  }

  private monthWeeks(): number[][] {
    const cells: number[] = this.monthCells();
    const weeks: number[][] = [];
    for (let i = 0; i < cells.length; i += 7) {
      weeks.push(cells.slice(i, i + 7));
    }
    return weeks;
  }

  private cellDateMs(day: number): number {
    return new Date(this.selYear, this.selMonth - 1, day).getTime();
  }

  private todayStart(): number {
    return startOfDay(Date.now());
  }

  private dayDots(day: number): number[] {
    const n: number = this.events[dateKeyOf(this.cellDateMs(day))] ?? 0;
    const count: number = Math.min(n, 3);
    const dots: number[] = [];
    for (let i = 0; i < count; i++) {
      dots.push(i);
    }
    return dots;
  }

  // 点击日期滚动到对应分组头（日历为列表首项，行索引需 +1）
  private onDayClick(day: number): void {
    const key: string = dateKeyOf(this.cellDateMs(day));
    const idx: number | undefined = this.headerIndex[key];
    if (idx !== undefined) {
      this.scroller.scrollToIndex(1 + idx);
    }
  }

  // 相对日期文本（对齐 LocalDate.toRelativeString）：今天 / N 天前 / N 天后 / 具体日期
  private relativeDate(ms: number): string {
    const ui: UIContext = this.getUIContext();
    const diff: number = Math.round((this.todayStart() - startOfDay(ms)) / DAY_MS);
    if (diff === 0) {
      return Util.resStr(ui, $r('app.string.relative_time_today'));
    }
    if (diff > 0 && diff < 7) {
      return Util.resStr(ui, $r('app.string.relative_time_days_ago'), [diff]);
    }
    if (diff < 0 && diff >= -7) {
      return Util.resStr(ui, $r('app.string.upcoming_relative_time_days'), [-diff]);
    }
    return Util.formatDate(ms);
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function UpcomingBuilder() {
  UpcomingPage()
}
