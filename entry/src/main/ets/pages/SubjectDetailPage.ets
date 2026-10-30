// Bangumi 条目详情页（新番时间表卡片进入）：
// 封面 + 标题/中文名 + 放送信息 + 简介 + 相关条目（横滑卡片，bgm.tv 关联条目）
// + “在应用内搜索”入口（跳全局搜索）
import { BangumiApi, BgmRelatedSubject, BgmSubjectDetail } from '../data/BangumiApi';
import { AppDb } from '../data/AppDb';
import { GlobalSearchParams, SubjectDetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { NavGlassPage } from '../common/HdsNavHost';
import { AppIcon } from './components/AppIcon';
import { SmartImage } from './components/SmartImage';
import { LoadingState } from './components/LoadingState';
import { ErrorState } from './components/ErrorState';

@Component
export struct SubjectDetailPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State detail: BgmSubjectDetail | undefined = undefined;
  // 相关条目（bgm.tv 关联条目，加载失败或无关联时保持空数组即隐藏区块）
  @State related: BgmRelatedSubject[] = [];
  private subjectId: number = 0;
  private scroller: Scroller = new Scroller();

  build() {
    NavGlassPage({
      title: $r('app.string.subject_detail_title'),
      scroller: this.scroller,
      onReady: (ctx: NavDestinationContext): void => {
        this.pathStack = ctx.pathStack;
        const params = ctx.pathInfo.param as SubjectDetailParams;
        if (params !== undefined && params !== null && typeof params.subjectId === 'number') {
          this.subjectId = params.subjectId;
          this.loadDetail();
        } else {
          this.loading = false;
          this.loadError = 'invalid_params';
        }
      }
    }) {
      if (this.loading) {
        LoadingState({ fill: true })
      } else if (this.loadError !== '') {
        Column() {
          ErrorState({
            message: $r('app.string.subject_load_failed')
          })
          Text($r('app.string.common_retry'))
            .fontSize(14)
            .fontColor(this.pal.primary)
            .padding(12)
            .onClick(() => {
              this.loadDetail();
            })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
      } else if (this.detail !== undefined) {
        Scroll(this.scroller) {
          Column() {
            this.headerBlock(this.detail)
            this.infoRows(this.detail)
            this.summaryBlock(this.detail)
            this.relatedBlock()
          }
          .width('100%')
          .constraintSize({ maxWidth: 720 })
          .alignItems(HorizontalAlign.Start)
        }
        .scrollBar(BarState.Auto)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      }
    }
  }

  // 封面 + 标题行（跳全局搜索按钮）
  @Builder
  headerBlock(d: BgmSubjectDetail) {
    Row({ space: 16 }) {
      SmartImage({
        url: d.cover,
        fit: ImageFit.Cover,
        placeholderIconSize: 28
      })
      .width(110)
      .aspectRatio(2 / 3)
      .borderRadius(8)
      .clip(true)
      .backgroundColor(this.pal.chip)

      Column({ space: 6 }) {
        Text(d.nameCn !== '' ? d.nameCn : d.name)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (d.name !== '' && d.nameCn !== '' && d.name !== d.nameCn) {
          Text(d.name)
            .fontSize(13)
            .fontColor(this.pal.sub)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Blank()
        Row({ space: 6 }) {
          AppIcon({ name: 'search', iconSize: 16, tint: this.pal.onPrimary })
          Text($r('app.string.subject_search_in_app'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal.onPrimary)
            .maxLines(1)
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(18)
        .backgroundColor(this.pal.primary)
        .onClick(() => {
          this.searchInApp();
        })
      }
      .layoutWeight(1)
      .height(165)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({
      left: 16 + Bp.contentInset(this.windowW),
      right: 16 + Bp.contentInset(this.windowW),
      top: 12,
      bottom: 12
    })
    .alignSelf(ItemAlign.Center)
  }

  // 放送日期 / 集数 / 评分 信息行
  @Builder
  infoRows(d: BgmSubjectDetail) {
    Column() {
      this.infoRow($r('app.string.subject_label_air_date'), d.date)
      this.infoRow($r('app.string.subject_label_eps'), d.eps > 0 ? `${d.eps}` : '-')
      this.infoRow($r('app.string.subject_label_score'), d.score > 0 ? d.score.toFixed(1) : '-')
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor(this.pal.card)
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    .margin({
      left: 16 + Bp.contentInset(this.windowW),
      right: 16 + Bp.contentInset(this.windowW),
      top: 4,
      bottom: 4
    })
    .alignSelf(ItemAlign.Center)
  }

  @Builder
  infoRow(label: Resource, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.pal.sub)
      Blank()
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '60%' })
    }
    .width('100%')
    .height(44)
  }

  // 简介块
  @Builder
  summaryBlock(d: BgmSubjectDetail) {
    Column({ space: 8 }) {
      Text($r('app.string.subject_label_summary'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
      Text(d.summary !== '' ? d.summary : $r('app.string.subject_summary_empty'))
        .fontSize(14)
        .fontColor(this.pal.sub)
        .lineHeight(22)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: 16 + Bp.contentInset(this.windowW),
      right: 16 + Bp.contentInset(this.windowW),
      top: 12,
      bottom: 24
    })
  }

  // 相关条目块（横滑卡片；参考 animeko RelatedSubjectsRow）
  @Builder
  relatedBlock() {
    if (this.related.length > 0) {
      Column({ space: 8 }) {
        Text($r('app.string.subject_label_related'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
        List({ space: 12 }) {
          ForEach(this.related, (item: BgmRelatedSubject) => {
            ListItem() {
              Column({ space: 6 }) {
                SmartImage({
                  url: item.cover,
                  fit: ImageFit.Cover,
                  placeholderIconSize: 24
                })
                .width(96)
                .aspectRatio(2 / 3)
                .borderRadius(8)
                .clip(true)
                .backgroundColor(this.pal.chip)

                Text(item.nameCn !== '' ? item.nameCn : item.name)
                  .fontSize(13)
                  .fontColor(this.pal.text)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(this.relationLabel(item.relation))
                  .fontSize(11)
                  .fontColor(this.pal.sub)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width(96)
              .alignItems(HorizontalAlign.Start)
              .onClick(() => {
                this.openRelated(item);
              })
            }
          }, (item: BgmRelatedSubject): string => `rel-${item.id}`)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: 16 + Bp.contentInset(this.windowW),
        right: 16 + Bp.contentInset(this.windowW),
        top: 12,
        bottom: 24
      })
    }
  }

  // ---- 数据 ----

  private async loadDetail(): Promise<void> {
    if (this.subjectId <= 0) {
      this.loading = false;
      this.loadError = 'invalid_params';
      return;
    }
    this.loading = true;
    this.loadError = '';
    // 数据库就绪后 Bangumi 数据才可读写本地缓存（未就绪时 API 内部自动跳过缓存）
    try {
      await AppDb.ready(Util.hostAbilityContext(this.getUIContext()));
    } catch (e) {
      // 数据库初始化失败不阻塞详情加载
    }
    this.loadRelated();
    try {
      this.detail = await BangumiApi.getSubject(this.subjectId);
      this.loading = false;
    } catch (e) {
      this.loading = false;
      this.loadError = e instanceof Error ? e.message : 'load_failed';
    }
  }

  // 相关条目：与详情并行加载，失败静默隐藏区块
  private async loadRelated(): Promise<void> {
    this.related = [];
    try {
      this.related = await BangumiApi.getSubjectRelations(this.subjectId);
    } catch (e) {
      this.related = [];
    }
  }

  // 关系文案：已知关系本地化，未知（如“游戏”“角色出演”）原样展示
  private relationLabel(relation: string): ResourceStr {
    return BangumiApi.relationLabelRes(relation);
  }

  // 点击关联卡片：进入该条目自己的详情页
  private openRelated(item: BgmRelatedSubject): void {
    const params: SubjectDetailParams = { subjectId: item.id };
    this.pathStack.pushPathByName('SubjectDetail', params);
  }

  // “在应用内搜索”：用中文名（回退原名）发起全局搜索
  private searchInApp(): void {
    const d: BgmSubjectDetail | undefined = this.detail;
    if (d === undefined) {
      return;
    }
    const query: string = d.nameCn !== '' ? d.nameCn : d.name;
    if (query.trim() === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.subject_search_in_app'));
      return;
    }
    const params: GlobalSearchParams = { query: query.trim() };
    this.pathStack.pushPathByName('GlobalSearch', params);
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function SubjectDetailBuilder() {
  SubjectDetailPage()
}
