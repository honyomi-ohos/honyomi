import { ThemePalette } from '../../common/Theme';

// 番剧详情页骨架屏：数据加载占位，呼吸闪烁（同 MangaSkeletonGrid 模式）
// 两套几何对齐最终布局：紧凑单列（sm/md）与宽屏双列（lg+，左栏封面/信息卡 + 右主栏）
@Component
export struct SubjectDetailSkeleton {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop wide: boolean = false;
  @State shimmerAlpha: number = 1;
  private shimmerStarted: boolean = false;

  startShimmer(): void {
    if (this.shimmerStarted) {
      return;
    }
    this.shimmerStarted = true;
    this.getUIContext().animateTo({
      duration: 700,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate,
    }, (): void => {
      this.shimmerAlpha = 0.35;
    });
  }

  build() {
    Column() {
      if (this.wide) {
        this.wideBody()
      } else {
        this.compactBody()
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: this.wide ? 960 : 720 })
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
    .opacity(this.shimmerAlpha)
    .onAppear(() => {
      this.startShimmer();
    })
  }

  // 紧凑单列：头部封面行 + 评分卡 + 简介行 + 信息卡 + 封面横滑行
  @Builder
  compactBody() {
    Column({ space: 16 }) {
      Row({ space: 16 }) {
        Column()
          .width(110)
          .aspectRatio(2 / 3)
          .borderRadius(8)
          .backgroundColor(this.pal.chip)

        Column({ space: 8 }) {
          this.bar('80%', 20, 6)
          this.bar('50%', 14, 6)
          Blank()
          this.bar(130, 32, 16)
        }
        .layoutWeight(1)
        .height(165)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.ratingCard()

      Column({ space: 10 }) {
        this.bar(90, 16, 6)
        this.bar('100%', 12, 6)
        this.bar('100%', 12, 6)
        this.bar('62%', 12, 6)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.infoCard()

      this.coverRowBlock()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 宽屏双列：左栏（封面/统计卡/信息卡）+ 右主栏（标题/评分卡/简介/封面行）
  @Builder
  wideBody() {
    Row({ space: 24 }) {
      Column({ space: 16 }) {
        Column()
          .width('100%')
          .aspectRatio(2 / 3)
          .borderRadius(8)
          .backgroundColor(this.pal.chip)

        this.infoCard()

        this.infoCard()
      }
      .width(240)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 16 }) {
        this.bar('60%', 24, 6)
        this.bar('35%', 14, 6)
        this.ratingCard()
        Column({ space: 10 }) {
          this.bar(90, 16, 6)
          this.bar('100%', 12, 6)
          this.bar('100%', 12, 6)
          this.bar('62%', 12, 6)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        this.coverRowBlock()
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  // 评分占位卡：星级条 + 分数块 + 收藏统计占位
  @Builder
  ratingCard() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            this.bar(86, 16, 8)
            this.bar(46, 24, 6)
          }
          .alignItems(VerticalAlign.Center)

          this.bar(70, 10, 5)
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Row({ space: 16 }) {
          this.statCell()
          this.statCell()
          this.statCell()
          this.statCell()
        }
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
    }
    .width('100%')
    .backgroundColor(this.pal.card)
    .borderRadius(12)
    .padding(16)
  }

  // 收藏统计占位（胶囊标签条）
  @Builder
  statCell() {
    Column()
      .width(84)
      .height(24)
      .borderRadius(12)
      .backgroundColor(this.pal.chip)
  }

  // 信息占位卡：标签/数值成对行
  @Builder
  infoCard() {
    Column({ space: 12 }) {
      Row() {
        this.bar(64, 12, 6)
        Blank()
        this.bar(110, 12, 6)
      }
      .width('100%')

      Row() {
        this.bar(52, 12, 6)
        Blank()
        this.bar(88, 12, 6)
      }
      .width('100%')

      Row() {
        this.bar(70, 12, 6)
        Blank()
        this.bar(96, 12, 6)
      }
      .width('100%')
    }
    .width('100%')
    .backgroundColor(this.pal.card)
    .borderRadius(12)
    .padding(16)
  }

  // 封面横滑占位块：区块标题条 + 3 张封面卡
  @Builder
  coverRowBlock() {
    Column({ space: 10 }) {
      this.bar(110, 16, 6)
      Row({ space: 12 }) {
        ForEach([0, 1, 2], (item: number) => {
          Column({ space: 6 }) {
            Column()
              .width(96)
              .aspectRatio(2 / 3)
              .borderRadius(8)
              .backgroundColor(this.pal.chip)
            this.bar(70, 12, 6)
          }
          .alignItems(HorizontalAlign.Start)
        }, (item: number) => `skeleton-cover-${item}`)
      }
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 圆角占位条
  @Builder
  bar(w: Length, h: number, r: number) {
    Column()
      .width(w)
      .height(h)
      .borderRadius(r)
      .backgroundColor(this.pal.chip)
  }
}
