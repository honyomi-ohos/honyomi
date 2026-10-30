// Bangumi 条目详情页（新番时间表卡片进入）：
// 封面 + 标题 + 评分（星级/人数/排名/直方图）+ 收藏统计 + 简介 + 标签 + 作品信息
// + 角色（横滑）+ 制作人员 + 相关条目（横滑）+“在应用内搜索”入口（跳全局搜索）
// lg+ 双列布局：左栏（封面/收藏统计/作品信息/标签）+ 右主栏（标题/评分/简介/角色/制作人员/相关条目）
// 统一边距：内容列 constraintSize 限宽 + 父容器居中，区块不再叠加 16 + contentInset
import { BangumiApi, BgmCharacter, BgmInfoboxEntry, BgmPerson, BgmRelatedSubject, BgmSubjectDetail, BgmTag } from '../data/BangumiApi';
import { AppDb } from '../data/AppDb';
import { GlobalSearchParams, SubjectDetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { NavGlassPage } from '../common/HdsNavHost';
import { AppIcon } from './components/AppIcon';
import { SmartImage } from './components/SmartImage';
import { ErrorState } from './components/ErrorState';
import { SubjectDetailSkeleton } from './components/SubjectDetailSkeleton';

// 标签折叠展示条数 / 简介折叠判定字数 / 作品信息折叠展示行数
const SUBJECT_TAGS_COLLAPSED: number = 12;
const SUBJECT_SUMMARY_COLLAPSED_CHARS: number = 140;
const SUBJECT_INFO_COLLAPSED: number = 6;
// 评分直方图星级展示顺序（10 星 → 1 星）
const SUBJECT_HIST_STARS: number[] = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1];

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
  // 角色（含声优，静默加载失败即隐藏区块）
  @State characters: BgmCharacter[] = [];
  // 制作人员（静默加载失败即隐藏区块）
  @State staff: BgmPerson[] = [];
  // 简介展开 / 标签展开 / 作品信息展开
  @State summaryExpanded: boolean = false;
  @State tagsExpanded: boolean = false;
  @State infoExpanded: boolean = false;
  // 预格式化文案（资源含 %d 占位，渲染前经 Util.resStr 一次性格式化）
  @State scoreText: string = '-';
  @State ratingSubText: string = '';
  @State statTexts: string[] = [];
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
        SubjectDetailSkeleton({ wide: this.isWideLayout() })
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
            if (this.isWideLayout()) {
              this.wideBody(this.detail)
            } else {
              this.compactBody(this.detail)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .scrollBar(BarState.Auto)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
  }

  // 紧凑单列（sm/md）：整页纵向串联，内容列限宽 720 居中
  @Builder
  compactBody(d: BgmSubjectDetail) {
    Column({ space: 16 }) {
      this.headerBlock(d)
      if (this.hasRatingData(d)) {
        this.ratingBlock(d)
      }
      this.summaryBlock(d)
      this.tagsBlock(d)
      this.infoBlock(d)
      this.charactersBlock()
      this.staffBlock()
      this.relatedBlock()
    }
    .width('100%')
    .constraintSize({ maxWidth: 720 })
    .padding({ left: 16, right: 16, top: 16, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }

  // 宽屏双列（lg+）：左栏封面/收藏统计/作品信息/标签，右主栏标题/评分/简介/角色/制作人员/相关条目
  @Builder
  wideBody(d: BgmSubjectDetail) {
    Row({ space: 24 }) {
      Column({ space: 16 }) {
        SmartImage({
          url: d.cover,
          bgmId: this.subjectId,
          fit: ImageFit.Cover,
          placeholderIconSize: 28
        })
        .width('100%')
        .aspectRatio(2 / 3)
        .borderRadius(8)
        .clip(true)
        .backgroundColor(this.pal.chip)

        if (this.statTexts.length > 0) {
          this.statsCard()
        }
        this.infoBlock(d)
        this.tagsBlock(d)
      }
      .width(240)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 16 }) {
        this.titleBlock(d)
        if (this.hasRatingData(d)) {
          this.ratingBlock(d)
        }
        this.summaryBlock(d)
        this.charactersBlock()
        this.staffBlock()
        this.relatedBlock()
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ maxWidth: 960 })
    .padding({ left: 24, right: 24, top: 16, bottom: 32 })
    .alignItems(VerticalAlign.Top)
  }

  // 封面 + 标题行（紧凑单列头部）
  @Builder
  headerBlock(d: BgmSubjectDetail) {
    Row({ space: 16 }) {
      SmartImage({
        url: d.cover,
        bgmId: this.subjectId,
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
        if (d.date !== '') {
          Text(d.date)
            .fontSize(13)
            .fontColor(this.pal.sub)
            .maxLines(1)
        }
        Blank()
        this.searchButton()
      }
      .layoutWeight(1)
      .height(165)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  // 标题块（宽屏右主栏顶部）
  @Builder
  titleBlock(d: BgmSubjectDetail) {
    Column({ space: 6 }) {
      Text(d.nameCn !== '' ? d.nameCn : d.name)
        .fontSize(22)
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
      if (d.date !== '') {
        Text(d.date)
          .fontSize(13)
          .fontColor(this.pal.sub)
          .maxLines(1)
      }
      this.searchButton()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // “在应用内搜索”胶囊按钮
  @Builder
  searchButton() {
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

  // 评分卡：星级 + 分数 + 评分人数/排名 + 收藏统计胶囊（紧凑单列）+ 评分直方图
  @Builder
  ratingBlock(d: BgmSubjectDetail) {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            if (d.score > 0) {
              Rating({ rating: d.score / 2, indicator: true })
                .stars(5)
                .stepSize(0.5)
                .width(86)
                .height(16)
            }
            Text(this.scoreText)
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal.text)
              .maxLines(1)
          }
          .alignItems(VerticalAlign.Center)

          if (this.ratingSubText !== '') {
            Text(this.ratingSubText)
              .fontSize(12)
              .fontColor(this.pal.sub)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        if (this.statTexts.length > 0 && !this.isWideLayout()) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
            ForEach(this.statTexts, (statText: string, index: number) => {
              Text(statText)
                .fontSize(12)
                .fontColor(this.pal.sub)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(12)
                .backgroundColor(this.pal.chip)
                .margin({ left: 4, top: 4 })
            }, (statText: string, index: number) => `stat-${index}`)
          }
          .constraintSize({ maxWidth: '52%' })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (d.ratingTotal > 0) {
        this.histogramBlock(d)
      }
    }
    .width('100%')
    .backgroundColor(this.pal.card)
    .borderRadius(12)
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }

  // 收藏统计卡（宽屏左栏）
  @Builder
  statsCard() {
    Column({ space: 4 }) {
      ForEach(this.statTexts, (statText: string, index: number) => {
        Text(statText)
          .fontSize(13)
          .fontColor(this.pal.sub)
          .maxLines(1)
      }, (statText: string, index: number) => `rail-stat-${index}`)
    }
    .width('100%')
    .backgroundColor(this.pal.card)
    .borderRadius(12)
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  // 评分直方图：10 → 1 星各档人数占比（横条）
  @Builder
  histogramBlock(d: BgmSubjectDetail) {
    Column({ space: 4 }) {
      ForEach(SUBJECT_HIST_STARS, (star: number) => {
        Row({ space: 8 }) {
          Text(`${star}`)
            .fontSize(11)
            .fontColor(this.pal.sub)
            .width(14)
          Progress({
            value: d.scoreHistogram[star - 1],
            total: this.histMax(d),
            type: ProgressType.Linear
          })
            .layoutWeight(1)
            .height(6)
            .color(this.pal.primary)
            .backgroundColor(this.pal.chip)
            .style({ strokeWidth: 6 })
          Text(`${d.scoreHistogram[star - 1]}`)
            .fontSize(11)
            .fontColor(this.pal.sub)
            .width(40)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }, (star: number) => `hist-${star}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 简介块（长文折叠，展开/收起）
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
        .maxLines(this.summaryExpanded ? 999 : 6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (d.summary.length > SUBJECT_SUMMARY_COLLAPSED_CHARS) {
        Row({ space: 4 }) {
          AppIcon({
            name: this.summaryExpanded ? 'expand_less' : 'expand_more',
            iconSize: 18,
            tint: this.pal.primary
          })
          Text(this.summaryExpanded ? $r('app.string.detail_collapse') : $r('app.string.detail_expand'))
            .fontSize(13)
            .fontColor(this.pal.primary)
        }
        .padding({ top: 4, bottom: 4 })
        .onClick(() => {
          this.summaryExpanded = !this.summaryExpanded;
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 标签块（胶囊流式排布，超过折叠阈值时可展开）
  @Builder
  tagsBlock(d: BgmSubjectDetail) {
    if (d.tags.length > 0) {
      Column({ space: 10 }) {
        Text($r('app.string.subject_label_tags'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.displayTags(d), (tag: BgmTag) => {
            Text(`${tag.name} ${tag.count}`)
              .fontSize(12)
              .fontColor(this.pal.sub)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(12)
              .backgroundColor(this.pal.chip)
              .margin({ right: 8, bottom: 8 })
          }, (tag: BgmTag) => `tag-${tag.name}-${tag.count}`)
        }
        .width('100%')
        if (d.tags.length > SUBJECT_TAGS_COLLAPSED) {
          Row({ space: 4 }) {
            AppIcon({
              name: this.tagsExpanded ? 'expand_less' : 'expand_more',
              iconSize: 18,
              tint: this.pal.primary
            })
            Text(this.tagsExpanded ? $r('app.string.detail_collapse') : $r('app.string.detail_expand'))
              .fontSize(13)
              .fontColor(this.pal.primary)
          }
          .padding({ top: 4, bottom: 4 })
          .onClick(() => {
            this.tagsExpanded = !this.tagsExpanded;
          })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  // 作品信息卡（bgm.tv infobox 键值行；常见键本地化，其余保留原文；
  // 行数超过阈值时折叠，展开/收起切换，避免长表占满整屏）
  @Builder
  infoBlock(d: BgmSubjectDetail) {
    if (d.infobox.length > 0) {
      Column({ space: 4 }) {
        Text($r('app.string.subject_label_info'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .padding({ top: 12, left: 16, right: 16 })
        ForEach(this.displayInfobox(d), (entry: BgmInfoboxEntry, index: number) => {
          Row({ space: 12 }) {
            Text(this.infoboxLabel(entry.key))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .constraintSize({ maxWidth: '38%' })
            Blank()
            Text(entry.text)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal.text)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.End)
              .constraintSize({ maxWidth: '58%' })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        }, (entry: BgmInfoboxEntry, index: number) => `infobox-${index}-${entry.key}`)
        if (d.infobox.length > SUBJECT_INFO_COLLAPSED) {
          Row({ space: 4 }) {
            AppIcon({
              name: this.infoExpanded ? 'expand_less' : 'expand_more',
              iconSize: 18,
              tint: this.pal.primary
            })
            Text(this.infoExpanded ? $r('app.string.detail_collapse') : $r('app.string.detail_expand'))
              .fontSize(13)
              .fontColor(this.pal.primary)
          }
          .padding({ top: 4, bottom: 4 })
          .onClick(() => {
            this.infoExpanded = !this.infoExpanded;
          })
        }
      }
      .width('100%')
      .backgroundColor(this.pal.card)
      .borderRadius(12)
      .padding({ bottom: 12 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  // 角色块（横滑卡片：头像 + 角色名 + 定位 + 声优）
  @Builder
  charactersBlock() {
    if (this.characters.length > 0) {
      Column({ space: 8 }) {
        Text($r('app.string.subject_label_characters'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
        List({ space: 12 }) {
          ForEach(this.characters, (item: BgmCharacter) => {
            ListItem() {
              Column({ space: 6 }) {
                SmartImage({
                  url: item.cover,
                  fit: ImageFit.Cover,
                  placeholderIconSize: 18
                })
                .width(84)
                .aspectRatio(2 / 3)
                .borderRadius(8)
                .clip(true)
                .backgroundColor(this.pal.chip)

                Text(item.name)
                  .fontSize(13)
                  .fontColor(this.pal.text)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(this.roleLabelRes(item.roleType))
                  .fontSize(11)
                  .fontColor(this.pal.sub)
                  .maxLines(1)

                if (item.actorName !== '') {
                  Text(item.actorName)
                    .fontSize(11)
                    .fontColor(this.pal.sub)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .width(84)
              .alignItems(HorizontalAlign.Start)
            }
          }, (item: BgmCharacter) => `char-${item.id}`)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  // 制作人员块（两列流式卡片：头像 + 姓名 + 职务）
  @Builder
  staffBlock() {
    if (this.staff.length > 0) {
      Column({ space: 8 }) {
        Text($r('app.string.subject_label_staff'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.staff, (person: BgmPerson) => {
            Row({ space: 10 }) {
              SmartImage({
                url: person.cover,
                fit: ImageFit.Cover,
                placeholderIconSize: 14
              })
              .width(32)
              .height(32)
              .borderRadius(16)
              .clip(true)
              .backgroundColor(this.pal.chip)

              Column({ space: 2 }) {
                Text(person.name)
                  .fontSize(13)
                  .fontColor(this.pal.text)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (person.career !== '') {
                  Text(person.career)
                    .fontSize(11)
                    .fontColor(this.pal.sub)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('48%')
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: 10 })
          }, (person: BgmPerson) => `staff-${person.id}`)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
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
                  bgmId: item.id,
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
    this.detail = undefined;
    this.related = [];
    this.characters = [];
    this.staff = [];
    this.statTexts = [];
    this.scoreText = '-';
    this.ratingSubText = '';
    this.summaryExpanded = false;
    this.tagsExpanded = false;
    this.infoExpanded = false;
    // 数据库就绪后 Bangumi 数据才可读写本地缓存（未就绪时 API 内部自动跳过缓存）
    try {
      await AppDb.ready(Util.hostAbilityContext(this.getUIContext()));
    } catch (e) {
      // 数据库初始化失败不阻塞详情加载
    }
    // 附属数据并行加载，失败静默隐藏对应区块
    this.loadRelated();
    this.loadCharacters();
    this.loadPersons();
    try {
      this.detail = await BangumiApi.getSubject(this.subjectId);
      this.applyTexts();
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

  // 角色：与详情并行加载，失败静默隐藏区块
  private async loadCharacters(): Promise<void> {
    this.characters = [];
    try {
      this.characters = await BangumiApi.getSubjectCharacters(this.subjectId);
    } catch (e) {
      this.characters = [];
    }
  }

  // 制作人员：与详情并行加载，失败静默隐藏区块
  private async loadPersons(): Promise<void> {
    this.staff = [];
    try {
      this.staff = await BangumiApi.getSubjectPersons(this.subjectId);
    } catch (e) {
      this.staff = [];
    }
  }

  // 资源含 %d 占位，渲染前经 Util.resStr 一次性格式化到状态
  private applyTexts(): void {
    const d = this.detail;
    if (d === undefined) {
      return;
    }
    const ui = this.getUIContext();
    this.scoreText = d.score > 0 ? d.score.toFixed(1) : '-';
    const subParts: string[] = [];
    if (d.ratingTotal > 0) {
      subParts.push(Util.resStr(ui, $r('app.string.subject_rating_total'), [d.ratingTotal]));
    }
    if (d.ratingRank > 0) {
      subParts.push(Util.resStr(ui, $r('app.string.subject_rating_rank'), [d.ratingRank]));
    }
    this.ratingSubText = subParts.join(' · ');
    const c = d.collection;
    if (c.wish + c.collect + c.doing + c.dropped > 0) {
      this.statTexts = [
        Util.resStr(ui, $r('app.string.subject_stat_wish'), [c.wish]),
        Util.resStr(ui, $r('app.string.subject_stat_collect'), [c.collect]),
        Util.resStr(ui, $r('app.string.subject_stat_doing'), [c.doing]),
        Util.resStr(ui, $r('app.string.subject_stat_dropped'), [c.dropped])
      ];
    }
  }

  // 是否展示评分卡（无任何评分/收藏数据时隐藏）
  private hasRatingData(d: BgmSubjectDetail): boolean {
    return d.score > 0 || d.ratingTotal > 0 || this.statTexts.length > 0;
  }

  // 标签折叠：展开全部，否则截取前 N 条
  private displayTags(d: BgmSubjectDetail): BgmTag[] {
    return this.tagsExpanded ? d.tags : d.tags.slice(0, SUBJECT_TAGS_COLLAPSED);
  }

  // 作品信息折叠：展开全部，否则截取前 N 行
  private displayInfobox(d: BgmSubjectDetail): BgmInfoboxEntry[] {
    return this.infoExpanded ? d.infobox : d.infobox.slice(0, SUBJECT_INFO_COLLAPSED);
  }

  // 直方图峰值（作各档占比分母；无数据时保底 1 避免除零）
  private histMax(d: BgmSubjectDetail): number {
    let max = 0;
    for (let i = 0; i < d.scoreHistogram.length; i++) {
      if (d.scoreHistogram[i] > max) {
        max = d.scoreHistogram[i];
      }
    }
    return max > 0 ? max : 1;
  }

  // infobox 常见键本地化，其余保留 bgm.tv 原文
  private infoboxLabel(key: string): ResourceStr {
    switch (key) {
      case '放送开始':
        return $r('app.string.subject_infobox_air_start');
      case '放送星期':
        return $r('app.string.subject_infobox_weekday');
      case '别名':
        return $r('app.string.subject_infobox_aliases');
      case '导演':
        return $r('app.string.subject_infobox_director');
      case '脚本':
        return $r('app.string.subject_infobox_script');
      case '系列构成':
        return $r('app.string.subject_infobox_series_composition');
      case '音乐':
        return $r('app.string.subject_infobox_music');
      case '动画制作':
        return $r('app.string.subject_infobox_studio');
      case '人物设定':
        return $r('app.string.subject_infobox_character_design');
      case '时长':
        return $r('app.string.subject_infobox_duration');
      default:
        return key;
    }
  }

  // 角色定位文案：1 主角 / 2 配角 / 3 客串
  private roleLabelRes(roleType: number): ResourceStr {
    if (roleType === 1) {
      return $r('app.string.subject_role_main');
    }
    if (roleType === 2) {
      return $r('app.string.subject_role_supporting');
    }
    if (roleType === 3) {
      return $r('app.string.subject_role_guest');
    }
    return '';
  }

  // 关系文案：已知关系本地化，未知（如“游戏”“角色出演”）原样展示
  private relationLabel(relation: string): ResourceStr {
    return BangumiApi.relationLabelRes(relation);
  }

  // lg+ 双列布局
  private isWideLayout(): boolean {
    return this.windowW >= Bp.LG_MIN;
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
