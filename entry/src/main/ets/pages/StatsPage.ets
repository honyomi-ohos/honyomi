import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo, TrackRepo } from '../data/Repos';
import { ContentType } from '../model/Models';
import { ReadingStatsRepo, DayDuration } from '../data/ReadingStats';
import { DownloadService } from '../data/DownloadService';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { PageHeader } from './components/PageHeader';
import { PrefGroup } from './components/Prefs';

// 统计页汇总数据
class StatsSummary {
  libraryCount: number = 0;
  completedCount: number = 0;
  startedCount: number = 0;
  localCount: number = 0;
  totalChapters: number = 0;
  readChapters: number = 0;
  downloadedChapters: number = 0;
  trackedCount: number = 0;
  meanScore: number = -1;
  trackerCount: number = 0;
  totalReadSeconds: number = 0;
  mangaSeconds: number = 0;
  novelSeconds: number = 0;
  videoSeconds: number = 0;
}

// 单个统计项：数值 + 标签（对齐 Mihon StatsOverviewItem）
@Component
struct StatsItem {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  title: Resource | string = '';
  value: Resource | string = '';

  build() {
    Column() {
      Text(this.value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.title)
        .fontSize(12)
        .fontColor(this.pal.sub)
        .margin({ top: 2 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 14, bottom: 14 })
  }
}

// 统计页：概览/作品/章节/追踪 四段卡片（对齐 Mihon StatsScreen）
// + 本周/本月每日阅读时长柱状图（数据来自 readingSession 会话表）
@Component
export struct StatsPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State loading: boolean = true;
  @State summary: StatsSummary = new StatsSummary();
  // 图表周期：0=周 1=月
  @State chartMode: number = 0;
  @State weekDays: DayDuration[] = [];
  @State monthDays: DayDuration[] = [];

  aboutToAppear(): void {
    this.loadData();
  }

  private ctx(): common.UIAbilityContext {
    return Util.hostAbilityContext(this.getUIContext());
  }

  async loadData(): Promise<void> {
    try {
      await AppDb.ready(this.ctx());
      const summary = new StatsSummary();
      // 作品/章节统计（书架内）
      const library = await MangaRepo.getLibrary();
      const statsMap = await MangaRepo.stats();
      summary.libraryCount = library.length;
      for (let i = 0; i < library.length; i++) {
        const m = library[i];
        const st = statsMap[`${m.id}`];
        const total = st !== undefined ? st.total : 0;
        const readCnt = st !== undefined ? st.readCount : 0;
        if (m.status === 'completed' && total - readCnt <= 0) {
          summary.completedCount += 1;
        }
        if (readCnt > 0) {
          summary.startedCount += 1;
        }
        if (ContentType.isLocal(m.sourceKey)) {
          summary.localCount += 1;
        }
        summary.totalChapters += total;
        summary.readChapters += readCnt;
      }
      // 已下载章节数
      const dlCounts = DownloadService.downloadedChapterCounts();
      const dlKeys = Object.keys(dlCounts);
      for (let i = 0; i < dlKeys.length; i++) {
        const v: number | undefined = dlCounts[dlKeys[i]];
        if (v !== undefined) {
          summary.downloadedChapters += v;
        }
      }
      // 追踪统计
      const trackedIds = await TrackRepo.trackedMangaIds();
      summary.trackedCount = trackedIds.size;
      summary.trackerCount = trackedIds.size > 0 ? 1 : 0;
      const scores = await TrackRepo.allScores();
      if (scores.length > 0) {
        let sum = 0;
        for (let i = 0; i < scores.length; i++) {
          sum += scores[i];
        }
        summary.meanScore = sum / scores.length;
      }
      // 阅读时长
      summary.totalReadSeconds = await ReadingStatsRepo.totalDuration();
      const byType = await ReadingStatsRepo.durationByType();
      summary.mangaSeconds = byType['manga'] !== undefined ? byType['manga'] : 0;
      summary.novelSeconds = byType['novel'] !== undefined ? byType['novel'] : 0;
      summary.videoSeconds = byType['video'] !== undefined ? byType['video'] : 0;
      this.summary = summary;
      // 周/月每日时长
      const now = new Date();
      const wr = ReadingStatsRepo.weekRange(now);
      this.weekDays = ReadingStatsRepo.buildRange(
        wr[0], wr[1], await ReadingStatsRepo.dailyTotals(wr[0], wr[1]));
      const mr = ReadingStatsRepo.monthRange(now);
      this.monthDays = ReadingStatsRepo.buildRange(
        mr[0], mr[1], await ReadingStatsRepo.dailyTotals(mr[0], mr[1]));
    } catch (_e) {
      // 统计失败不阻塞页面
    }
    this.loading = false;
  }

  private chartDays(): DayDuration[] {
    return this.chartMode === 0 ? this.weekDays : this.monthDays;
  }

  private chartTotal(): number {
    const days = this.chartDays();
    let total = 0;
    for (let i = 0; i < days.length; i++) {
      total += days[i].seconds;
    }
    return total;
  }

  private chartMax(): number {
    const days = this.chartDays();
    let maxV = 0;
    for (let i = 0; i < days.length; i++) {
      if (days[i].seconds > maxV) {
        maxV = days[i].seconds;
      }
    }
    return maxV;
  }

  private barHeight(d: DayDuration): number {
    const maxV = this.chartMax();
    if (d.seconds <= 0 || maxV <= 0) {
      return 2;
    }
    return Math.max(6, Math.round(d.seconds / maxV * 96));
  }

  private barColor(d: DayDuration): ResourceColor {
    return d.seconds > 0 ? this.pal.primary : this.pal.chip;
  }

  // 周模式横轴的星期短标签
  private dayLabel(d: DayDuration): string {
    return Util.weekdayShort(this.ctx(), ReadingStatsRepo.dayOfWeek(d.day));
  }

  private totalDurationText(): string {
    return Util.formatDuration(this.ctx(), this.summary.totalReadSeconds);
  }

  private meanScoreText(): Resource | string {
    if (this.summary.meanScore > 0) {
      return `${this.summary.meanScore.toFixed(2)} ★`;
    }
    return $r('app.string.stats_not_applicable');
  }

  private chartTotalText(): string {
    const total = this.chartTotal();
    const res = this.chartMode === 0
      ? $r('app.string.stats_week_total', Util.formatDuration(this.ctx(), total))
      : $r('app.string.stats_month_total', Util.formatDuration(this.ctx(), total));
    try {
      return this.ctx().resourceManager.getStringSync(res.id);
    } catch (e) {
      throw new Error(`chart total text failed: ${e}`);
    }
  }

  @Builder
  chartToggle() {
    Row() {
      Text($r('app.string.stats_week'))
        .fontSize(12)
        .fontColor(this.chartMode === 0 ? this.pal.primary : this.pal.sub)
        .backgroundColor(this.chartMode === 0 ? this.pal.card : Color.Transparent)
        .borderRadius(10)
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .onClick(() => {
          this.chartMode = 0;
        })
      Text($r('app.string.stats_month'))
        .fontSize(12)
        .fontColor(this.chartMode === 1 ? this.pal.primary : this.pal.sub)
        .backgroundColor(this.chartMode === 1 ? this.pal.card : Color.Transparent)
        .borderRadius(10)
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .margin({ left: 2 })
        .onClick(() => {
          this.chartMode = 1;
        })
    }
    .borderRadius(12)
    .backgroundColor(this.pal.chip)
    .padding(2)
  }

  // 阅读时长卡片：周/月切换 + 每日时长柱状图
  @Builder
  durationCard() {
    PrefGroup() {
      Column() {
        Row() {
          Text($r('app.string.stats_read_duration'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .layoutWeight(1)
          this.chartToggle()
        }
        .width('100%')
        .padding({ left: 16, right: 12, top: 14, bottom: 4 })

        if (this.chartTotal() <= 0) {
          Text($r('app.string.stats_no_reading'))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 28, bottom: 28 })
        } else {
          Row({ space: this.chartMode === 0 ? 6 : 2 }) {
            ForEach(this.chartDays(), (d: DayDuration) => {
              Column() {
                if (this.chartMode === 0) {
                  Text(Util.formatDuration(this.ctx(), d.seconds))
                    .fontSize(9)
                    .fontColor(this.pal.sub)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ bottom: 4 })
                }
                Column()
                  .width(this.chartMode === 0 ? '62%' : '64%')
                  .height(this.barHeight(d))
                  .backgroundColor(this.barColor(d))
                  .borderRadius(2)
                if (this.chartMode === 0) {
                  Text(this.dayLabel(d))
                    .fontSize(10)
                    .fontColor(this.pal.sub)
                    .margin({ top: 4 })
                    .maxLines(1)
                }
              }
              .layoutWeight(1)
              .height(this.chartMode === 0 ? 150 : 112)
              .justifyContent(FlexAlign.End)
              .alignItems(HorizontalAlign.Center)
            }, (d: DayDuration) => d.day)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 })

          Text(this.chartTotalText())
            .fontSize(12)
            .fontColor(this.pal.sub)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 8, bottom: 14 })
        }
      }
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.stats_title') })
        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(this.pal.primary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              // 概览
              PrefGroup({ groupTitle: $r('app.string.stats_overview_section') }) {
                Column() {
                  Row() {
                    StatsItem({
                      title: $r('app.string.stats_in_library'),
                      value: `${this.summary.libraryCount}`
                    })
                    StatsItem({
                      title: $r('app.string.stats_read_duration'),
                      value: this.totalDurationText()
                    })
                    StatsItem({
                      title: $r('app.string.stats_completed_titles'),
                      value: `${this.summary.completedCount}`
                    })
                  }
                  Row() {
                    StatsItem({
                      title: $r('app.string.stats_duration_manga'),
                      value: Util.formatDuration(this.ctx(), this.summary.mangaSeconds)
                    })
                    StatsItem({
                      title: $r('app.string.stats_duration_novel'),
                      value: Util.formatDuration(this.ctx(), this.summary.novelSeconds)
                    })
                    StatsItem({
                      title: $r('app.string.stats_duration_video'),
                      value: Util.formatDuration(this.ctx(), this.summary.videoSeconds)
                    })
                  }
                }
              }

              // 阅读时长（周/月柱状图）
              this.durationCard()

              // 作品
              PrefGroup({ groupTitle: $r('app.string.stats_titles_section') }) {
                Row() {
                  StatsItem({
                    title: $r('app.string.stats_started_titles'),
                    value: `${this.summary.startedCount}`
                  })
                  StatsItem({
                    title: $r('app.string.stats_local_titles'),
                    value: `${this.summary.localCount}`
                  })
                }
              }

              // 章节
              PrefGroup({ groupTitle: $r('app.string.stats_chapters_section') }) {
                Row() {
                  StatsItem({
                    title: $r('app.string.stats_total_chapters'),
                    value: `${this.summary.totalChapters}`
                  })
                  StatsItem({
                    title: $r('app.string.stats_read_chapters'),
                    value: `${this.summary.readChapters}`
                  })
                  StatsItem({
                    title: $r('app.string.stats_downloaded_chapters'),
                    value: `${this.summary.downloadedChapters}`
                  })
                }
              }

              // 追踪
              PrefGroup({ groupTitle: $r('app.string.stats_tracker_section') }) {
                Row() {
                  StatsItem({
                    title: $r('app.string.stats_tracked_titles'),
                    value: `${this.summary.trackedCount}`
                  })
                  StatsItem({
                    title: $r('app.string.stats_mean_score'),
                    value: this.meanScoreText()
                  })
                  StatsItem({
                    title: $r('app.string.stats_used'),
                    value: `${this.summary.trackerCount}`
                  })
                }
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 24 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.TopStart)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function StatsBuilder() {
  StatsPage()
}
