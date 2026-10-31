import { i18n } from '@kit.LocalizationKit';
import { AppDb } from '../data/AppDb';
import { SheetPreset } from './components/SheetPreset';
import { CategoryRepo, MangaRepo, UpcomingRepo } from '../data/Repos';
import { CategoryRecord, UpcomingManga } from '../model/Models';
import { DetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Settings } from '../common/Settings';
import { Util } from '../common/Util';
import { NavGlassAction, NavGlassPage } from '../common/HdsNavHost';
import { AppIcon } from './components/AppIcon';
import { CoverPlaceholder } from './components/CoverPlaceholder';
import { SmartImage } from './components/SmartImage';
import { UpdatesFilterSheet } from './components/UpdatesFilterSheet';
import { EmptyScreen } from './components/EmptyScreen';

// 即将推出页帮助：跳转应用内帮助文档（更新与「即将更新」小节）
const DAY_MS: number = 24 * 60 * 60 * 1000;

// 宽屏双列内容总宽上限：超出部分居中留白（对齐 xl 档限宽策略）
const WIDE_PANE_MAX_W: number = 960;

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
  // 日历选中日期（当天 0 点毫秒值，0 = 未选中）
  @State selDateMs: number = 0;
  // Index 根节点 Esc 广播：关闭筛选弹层（计数器递增触发）
  @StorageLink('sheetEsc') @Watch('onSheetEsc') sheetEsc: number = 0;
  @State categories: CategoryRecord[] = [];
  @State includedCats: number[] = [];
  @State excludedCats: number[] = [];
  // manga_category membership 真源（mangaId → 分类 id 列表，仅 inLibrary）
  private categoryIdsMap: Map<number, number[]> = new Map<number, number[]>();
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
    // membership 真源（mangaId → 分类 id 列表，仅 inLibrary）：分类筛选含任一 membership 即算
    this.categoryIdsMap = await MangaRepo.libraryCategoryIds();
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

  @Builder
  dayCell(day: number) {
    Stack() {
      // 选中日：主色实心圆；今日未选中时：描边圆
      if (this.isDaySelected(day)) {
        Column()
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.pal.primary)
      } else if (this.cellDateMs(day) === this.todayStart()) {
        Column()
          .width(40)
          .height(40)
          .borderRadius(20)
          .border({ width: 1, color: this.pal.text })
      }
      Text(`${day}`)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.dayTextColor(day))
      Row({ space: 2 }) {
        ForEach(this.dayDots(day), (i: number) => {
          Column()
            .width(5)
            .height(5)
            .borderRadius(2.5)
            .backgroundColor(this.isDaySelected(day) ? this.pal.onPrimary : this.pal.primary)
            .opacity((i + 1) * 0.3)
        }, (i: number) => `dot-${i}`)
      }
      .translate({ y: 14 })
    }
    .layoutWeight(1)
    .height(48)
    .hoverEffect(HoverEffect.Highlight)
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
        // 封面经 SmartImage 公共图片缓存管线（LRU）加载，不再 Image 直连
        SmartImage({
          url: m.coverUrl,
          sourceKey: m.sourceKey,
          fit: ImageFit.Cover,
          fill: true,
          placeholderIconSize: 20
        })
          .width(56)
          .height(80)
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
      // 大屏边距：月份标题左侧已按 contentInset 限宽，右侧箭头同步避让，
      // 避免 SM/LG 宽屏上切换箭头贴窗口边而其余内容居中
      .padding({ right: 16 + this.inset() })

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

  // 更新列表行（单列/宽屏右列共用）：日期分组头 + 条目
  @Builder
  updatingRows() {
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

  // 列表区空状态：书架内无连载中/完结连载作品（或全被分类筛选排除）
  @Builder
  upcomingEmpty() {
    EmptyScreen({ message: $r('app.string.card_empty_upcoming') })
  }

  // 窄屏单列：日历为列表首项，与更新列表同容器滚动
  @Builder
  compactBody() {
    List({ scroller: this.scroller }) {
      ListItem() {
        this.calendarBlock()
      }

      if (this.rows.length === 0) {
        ListItem() {
          Column() {
            this.upcomingEmpty()
          }
          .width('100%')
          .constraintSize({ minHeight: 200 })
          .justifyContent(FlexAlign.Center)
          .padding({ bottom: this.navBarH + 16 })
        }
      } else {
        this.updatingRows()
      }
    }
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .contentEndOffset(this.navBarH + 16)
    .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.FastOutSlowIn }))
  }

  // 宽屏双列（lg 及以上，对齐 Mihon 平板 UpcomingScreen 双栏）：
  // 左列 = 月历（独立滚动），右列 = 更新列表（独立滚动），中间竖分隔线
  @Builder
  wideBody() {
    Row() {
      Scroll() {
        Column() {
          this.calendarBlock()
        }
        .width('100%')
      }
      .width(this.calendarPaneW())
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)

      Column()
        .width(0.5)
        .height('100%')
        .backgroundColor(this.pal.divider)

      if (this.rows.length === 0) {
        Column() {
          this.upcomingEmpty()
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ bottom: this.navBarH + 16 })
      } else {
        List({ scroller: this.scroller }) {
          this.updatingRows()
        }
        .layoutWeight(1)
        .height('100%')
        .scrollBar(BarState.Auto)
        .contentEndOffset(this.navBarH + 16)
      }
    }
    .width(this.widePaneW())
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.FastOutSlowIn }))
  }

  build() {
    NavGlassPage({
      title: $r('app.string.label_upcoming'),
      scroller: this.scroller,
      actions: this.headerActions(),
      onReady: (ctx: NavDestinationContext): void => {
        this.pathStack = ctx.pathStack;
      }
    }) {
      Column() {
        if (this.isWideLayout()) {
          this.wideBody()
        } else {
          this.compactBody()
        }
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.showFilterSheet, this.filterSheetBuilder(),
        SheetPreset.fit(this.windowW, {
          showClose: false,
          bg: this.pal.bg
        }))
    }
  }

  // 页面主体：滚动容器全宽（滚动条贴窗口边），内容列经 contentInset 限宽居中（720 上限）
  // 宽屏双列布局下列宽自身已约束，内容不再整体限宽缩进
  private inset(): number {
    return this.isWideLayout() ? 0 : Bp.contentInset(this.windowW);
  }

  // 宽屏（lg 及以上）：左右双列布局（左日历右列表）
  private isWideLayout(): boolean {
    return Bp.isWide(this.windowW);
  }

  // 宽屏双列内容总宽：可用宽度（扣除左侧常驻导航栏），上限 960 居中
  private widePaneW(): number {
    const avail: number = Math.max(0, this.windowW - Bp.WIDE_RAIL_W);
    return Math.min(avail, WIDE_PANE_MAX_W);
  }

  // 宽屏左列（日历）宽度：双列总宽一半，上限 450
  private calendarPaneW(): number {
    return Math.min(Math.floor(this.widePaneW() / 2), 450);
  }

  // 标题栏右侧动作：分类筛选（半模态）+ 帮助入口
  private headerActions(): NavGlassAction[] {
    return [
      {
        icon: $r('app.media.ic_filter_list'),
        action: (): void => {
          this.showFilterSheet = true;
        }
      },
      {
        icon: $r('app.media.ic_help'),
        action: (): void => {
          this.pathStack.pushPathByName('Help', null);
        }
      }
    ];
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

  // 作品分类 id 列表：membership 优先（含任一 membership 即算），空则回退主分类
  private categoriesOf(m: UpcomingManga): number[] {
    const ids: number[] | undefined = this.categoryIdsMap.get(m.mangaId);
    if (ids !== undefined && ids.length > 0) {
      return ids;
    }
    return [m.categoryId];
  }

  // 过滤 + 按预计日分组，生成分组头/条目行与日历事件计数
  private recompute(): void {
    const shown: UpcomingManga[] = [];
    for (const m of this.allManga) {
      // 任一所属分类通过筛选即展示
      let allowed = false;
      for (const cid of this.categoriesOf(m)) {
        if (this.catAllowed(cid)) {
          allowed = true;
          break;
        }
      }
      if (allowed) {
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

  // 点击日期：记录选中态并滚动到对应分组头（单列布局日历为列表首项，行索引需 +1；宽屏双列无需偏移）
  private onDayClick(day: number): void {
    this.selDateMs = this.cellDateMs(day);
    const key: string = dateKeyOf(this.selDateMs);
    const idx: number | undefined = this.headerIndex[key];
    if (idx !== undefined) {
      this.scroller.scrollToIndex(this.isWideLayout() ? idx : 1 + idx);
    }
  }

  // 日历选中判断
  private isDaySelected(day: number): boolean {
    return this.selDateMs > 0 && this.selDateMs === this.cellDateMs(day);
  }

  // 日期数字颜色：选中 → 主色反色；过去 → 弱化；其余 → 常规
  private dayTextColor(day: number): ResourceColor {
    if (this.isDaySelected(day)) {
      return this.pal.onPrimary;
    }
    return this.cellDateMs(day) < this.todayStart() ? this.pal.sub : this.pal.text;
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
