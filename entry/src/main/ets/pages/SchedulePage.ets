import { BangumiApi, BgmCalendarItem } from '../data/BangumiApi';
import { SubjectDetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Settings } from '../common/Settings';
import { Util, LibGrid } from '../common/Util';
import { NavGlassAction, NavGlassPage } from '../common/HdsNavHost';
import { EmptyScreen } from './components/EmptyScreen';
import { MangaSkeletonGrid } from './components/MangaSkeletonGrid';
import { SmartImage } from './components/SmartImage';

// 时间表星期 chips 顺序：周一起排（周日殿后）
const SCHEDULE_DAY_ORDER: number[] = [1, 2, 3, 4, 5, 6, 0];

// 新番时间表页（Bangumi 每日放送）：
// 星期 chips（周一起排、今日主色描边）+ 按选中星期过滤的封面网格
// 网格与书架同构：Grid + columnsTemplate，列数同规则（书架手动列数/自动档），宽屏不限宽
@Component
export struct SchedulePage {
  // 路由栈：NavDestination onReady 时从自身上下文获取（官方推荐方式）
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @State scheduleLoading: boolean = false;
  @State scheduleError: string = '';
  @State scheduleAll: BgmCalendarItem[] = [];
  // 选中星期（JS 约定 0=周日..6=周六），初始为今天
  @State scheduleDay: number = new Date().getDay();
  // 星期短标签（索引 = JS 星期）
  @State weekdayLabels: string[] = [];
  // 网格内容区宽度镜像：列数与书架同规则（LibGrid 推导），档位跨越时经 animateTo 平滑重排
  @State schedW: number = 0;
  private todayJs: number = new Date().getDay();

  aboutToAppear(): void {
    this.buildWeekdayLabels();
    this.loadSchedule(false);
  }

  build() {
    NavGlassPage({
      title: $r('app.string.updates_tab_schedule'),
      actions: this.headerActions(),
      onReady: (ctx: NavDestinationContext): void => {
        this.pathStack = ctx.pathStack;
      }
    }) {
      this.scheduleContent()
    }
  }

  // 新番时间表内容：星期 chips + 按选中星期过滤的封面网格
  @Builder
  scheduleContent() {
    Column() {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(SCHEDULE_DAY_ORDER, (day: number) => {
            this.dayChip(day)
          }, (day: number) => `wd-${day}`)
        }
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 8
        })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      if (this.scheduleLoading) {
        // 首次加载骨架屏（与时间表网格同布局的占位卡片）
        MangaSkeletonGrid({
          columns: this.schedColsCount(),
          coverRatio: 2 / 3,
          gapX: 8,
          gapY: 12,
          padH: 8,
          padTop: 0
        })
      } else if (this.scheduleError !== '') {
        Column() {
          EmptyScreen({ message: $r('app.string.schedule_load_failed') })
          Text($r('app.string.common_retry'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal.primary)
            .padding({ top: 4, bottom: 12 })
            .onClick(() => {
              this.loadSchedule(true);
            })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.dayItems().length === 0) {
        Column() {
          EmptyScreen({ message: $r('app.string.schedule_empty') })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.dayItems(), (item: BgmCalendarItem) => {
            GridItem() {
              this.scheduleCard(item)
            }
          }, (item: BgmCalendarItem) => `bgm-${item.id}`)
        }
        .columnsTemplate(this.schedColumnsTemplate())
        .columnsGap(8)
        .rowsGap(12)
        .padding({ left: 8, right: 8 })
        .contentEndOffset(this.navBarH + 16)
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_old: Area, newArea: Area) => {
      const w = newArea.width;
      if (typeof w === 'number') {
        this.applySchedW(w);
      }
    })
  }

  // 星期 chip：选中实心、今日描边
  @Builder
  dayChip(day: number) {
    Text(this.weekdayLabel(day))
      .fontSize(13)
      .fontWeight(this.scheduleDay === day ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.scheduleDay === day ? this.pal.onPrimary :
        (this.todayJs === day ? this.pal.primary : this.pal.sub))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.scheduleDay === day ? this.pal.primary : Color.Transparent)
      .border({
        width: this.scheduleDay !== day && this.todayJs === day ? 1 : 0,
        color: this.pal.primary
      })
      .onClick(() => {
        this.scheduleDay = day;
      })
  }

  // 时间表卡片：封面（2:3）+ 评分角标 + 标题 + 放送日期，点击进条目详情
  @Builder
  scheduleCard(item: BgmCalendarItem) {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        SmartImage({
          url: item.cover,
          bgmId: item.id,
          fit: ImageFit.Cover,
          placeholderIconSize: 24
        })
          .width('100%')
          .aspectRatio(2 / 3)
          .borderRadius(8)
          .clip(true)
          .backgroundColor(this.pal.chip)

        if (item.score > 0) {
          Text(`★ ${item.score.toFixed(1)}`)
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFD180')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor('#CC000000')
            .margin(5)
        }
      }
      .width('100%')

      // 标题固定 2 行、放送日期固定 1 行：文字长短/缺失不改变卡片高度，同行卡片底部对齐
      Text(item.nameCn !== '' ? item.nameCn : item.name)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal.text)
        .minLines(2)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })

      Text(item.airDate)
        .fontSize(11)
        .fontColor(this.pal.sub)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      const params: SubjectDetailParams = { subjectId: item.id };
      this.pathStack.pushPathByName('SubjectDetail', params);
    })
  }

  // 标题栏右侧动作：刷新 Bangumi 日历
  private headerActions(): NavGlassAction[] {
    return [
      {
        icon: $r('app.media.ic_refresh'),
        action: (): void => {
          this.loadSchedule(true);
        }
      }
    ];
  }

  private async loadSchedule(force: boolean): Promise<void> {
    this.scheduleLoading = true;
    this.scheduleError = '';
    try {
      this.scheduleAll = await BangumiApi.getCalendar(force);
      this.scheduleLoading = false;
    } catch (e) {
      this.scheduleLoading = false;
      this.scheduleError = e instanceof Error ? e.message : 'load_failed';
    }
  }

  // 星期短标签（索引 = JS 星期 0=周日..6=周六）
  private buildWeekdayLabels(): void {
    const ctx = Util.hostAbilityContext(this.getUIContext());
    const labels: string[] = [];
    for (let day = 0; day < 7; day++) {
      labels.push(Util.weekdayShort(ctx, day));
    }
    this.weekdayLabels = labels;
  }

  private weekdayLabel(day: number): string {
    return this.weekdayLabels.length === 7 ? (this.weekdayLabels[day] ?? '') : `${day}`;
  }

  // 选中星期的条目
  private dayItems(): BgmCalendarItem[] {
    return this.scheduleAll.filter((it: BgmCalendarItem): boolean => it.jsDay === this.scheduleDay);
  }

  // 当前生效列数：与书架同规则——书架手动列数按可行区间收敛（0=自动），自动档约 128vp 一格
  private effectiveSchedCols(w: number): number {
    const manual: number = Settings.getLibraryGridCols();
    if (manual > 0) {
      return LibGrid.clampCols(manual, w);
    }
    return LibGrid.autoCols(w);
  }

  // 首帧宽度估计：窗口宽扣除宽屏侧边导航栏（真实宽度待 onAreaChange 首次测量回填），
  // 避免大屏首帧按 360vp 兜底算出 2 列、骨架/网格先渲染出超大封面
  private estSchedW(): number {
    if (this.windowW <= 0) {
      return 360;
    }
    return Math.max(0, this.windowW - (Bp.isWide(this.windowW) ? Bp.WIDE_RAIL_W : 0));
  }

  private schedColsCount(): number {
    return this.effectiveSchedCols(this.schedW > 0 ? this.schedW : this.estSchedW());
  }

  // 网格宽变化：生效列数档位变化时包 animateTo，让网格重排带过渡动画；
  // 首次测量回填不包动画——首帧已按窗口宽估计列数，档位校正即时生效，不播收缩动画
  private applySchedW(w: number): void {
    if (w === this.schedW) {
      return;
    }
    const firstMeasure: boolean = this.schedW <= 0;
    const reflow: boolean = this.effectiveSchedCols(w) !== this.schedColsCount();
    if (!firstMeasure && reflow) {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, (): void => {
        this.schedW = w;
      });
    } else {
      this.schedW = w;
    }
  }

  private schedColumnsTemplate(): string {
    let tpl = '';
    for (let i = 0; i < this.schedColsCount(); i++) {
      tpl += '1fr ';
    }
    return tpl.trim();
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function ScheduleBuilder() {
  SchedulePage()
}
