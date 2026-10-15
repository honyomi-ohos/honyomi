let statsMonthStorage = new LocalStorage();

// 月统计卡片：本月每日阅读时长柱状图 + 总时长，点击跳转统计页
// 柱高由 WidgetUpdater 预计算为 vp 数值，经 bars 逗号串传入（卡片数据经序列化为字符串）
@Entry(statsMonthStorage)
@Component
struct StatsMonthCard {
  @LocalStorageProp('wide') wide: boolean = false;
  @LocalStorageProp('titleText') titleText: string = '';
  @LocalStorageProp('rangeText') rangeText: string = '';
  @LocalStorageProp('totalText') totalText: string = '';
  @LocalStorageProp('bars') bars: string = '';
  @LocalStorageProp('empty') empty: boolean = false;

  build() {
    Column() {
      // 标题栏：月统计 + 年月
      Row() {
        Text(this.titleText)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.honyomi_text'))
        Text(this.rangeText)
          .fontSize(11)
          .fontColor($r('app.color.honyomi_sub'))
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .maxLines(1)
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 4
      })

      if (this.empty) {
        // 空状态
        Column() {
          Text($r('app.string.card_stats_empty'))
            .fontSize(13)
            .fontColor($r('app.color.honyomi_sub'))
          Text($r('app.string.card_open_hint'))
            .fontSize(12)
            .fontColor($r('app.color.honyomi_primary_blue'))
            .margin({ top: 6 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        // 每日时长柱状图（28~31 根细柱）
        Row({ space: 2 }) {
          ForEach(this.barList(), (h: string) => {
            Column() {
              Column()
                .width('64%')
                .height(this.barHeight(h))
                .backgroundColor(this.barColor(h))
                .borderRadius(1)
            }
            .layoutWeight(1)
            .height(this.wide ? 84 : 56)
            .justifyContent(FlexAlign.End)
            .alignItems(HorizontalAlign.Center)
          }, (h: string, idx: number) => `${idx}_${h}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })

        // 本月总时长
        Text(this.totalText)
          .fontSize(12)
          .fontColor($r('app.color.honyomi_primary_blue'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 6, bottom: 12 })
          .maxLines(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.honyomi_card'))
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': { 'cardTarget': 'stats' }
      });
    })
  }

  private barList(): string[] {
    if (this.bars === '') {
      return [];
    }
    return this.bars.split(',');
  }

  private barHeight(h: string): number {
    return Number(h);
  }

  private barColor(h: string): ResourceColor {
    return Number(h) > 2 ? $r('app.color.honyomi_primary_blue') : $r('app.color.honyomi_chip');
  }
}
