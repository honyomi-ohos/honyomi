import { ThemePalette } from '../../common/Theme';

// 漫画卡片骨架屏（数据加载占位）：封面 + 标题占位，呼吸闪烁
// 布局参数默认为图源浏览网格样式；其他网格（如更新-时间表）按各自网格布局覆写
@Component
export struct MangaSkeletonGrid {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop columns: number = 2;
  // 封面占位宽高比（宽/高）
  @Prop coverRatio: number = 0.7;
  // 列间 / 行间间距
  @Prop gapX: number = 12;
  @Prop gapY: number = 16;
  // 横向留白 / 顶部留白
  @Prop padH: number = 16;
  @Prop padTop: number = 4;
  @State shimmerAlpha: number = 1;
  private shimmerStarted: boolean = false;
  private placeholders: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

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
    Grid() {
      ForEach(this.placeholders, (item: number) => {
        GridItem() {
          Column() {
            Column()
              .width('100%')
              .aspectRatio(this.coverRatio)
              .borderRadius(8)
              .backgroundColor(this.pal.chip)

            Column()
              .width('70%')
              .height(12)
              .borderRadius(6)
              .backgroundColor(this.pal.chip)
              .margin({ top: 8 })

            Column()
              .width('45%')
              .height(12)
              .borderRadius(6)
              .backgroundColor(this.pal.chip)
              .margin({ top: 6 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .opacity(this.shimmerAlpha)
        }
      }, (item: number) => `skeleton-${item}`)
    }
    .columnsTemplate(this.columnsTpl())
    .columnsGap(this.gapX)
    .rowsGap(this.gapY)
    .padding({ left: this.padH, right: this.padH, top: this.padTop })
    .layoutWeight(1)
    .onAppear(() => {
      this.startShimmer();
    })
  }

  private columnsTpl(): string {
    const cols = this.columns > 0 ? this.columns : 2;
    let tpl = '';
    for (let i = 0; i < cols; i++) {
      tpl += '1fr ';
    }
    return tpl.trim();
  }
}
