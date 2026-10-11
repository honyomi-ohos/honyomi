let upcomingStorage = new LocalStorage();

// 即将推出卡片：展示书架漫画的预计更新日期，点击行进入详情，标题进入日历页
@Entry(upcomingStorage)
@Component
struct UpcomingCard {
  @LocalStorageProp('wide') wide: boolean = false;
  @LocalStorageProp('t0') t0: string = '';
  @LocalStorageProp('t1') t1: string = '';
  @LocalStorageProp('t2') t2: string = '';
  @LocalStorageProp('d0') d0: string = '';
  @LocalStorageProp('d1') d1: string = '';
  @LocalStorageProp('d2') d2: string = '';
  @LocalStorageProp('m0') m0: string = '';
  @LocalStorageProp('m1') m1: string = '';
  @LocalStorageProp('m2') m2: string = '';
  @LocalStorageProp('b0') b0: string = '';
  @LocalStorageProp('b1') b1: string = '';
  @LocalStorageProp('b2') b2: string = '';

  private hasData(): boolean {
    return this.t0 !== '' || this.t1 !== '' || this.t2 !== '';
  }

  build() {
    Column() {
      // 标题栏：即将推出 + 跳转日历页
      Row() {
        Text($r('app.string.card_upcoming_header'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.honyomi_text'))
        Text('›')
          .fontSize(16)
          .fontColor($r('app.color.honyomi_sub'))
          .margin({ left: 4 })
      }
      .justifyContent(FlexAlign.Start)
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })
      .onClick(() => {
        postCardAction(this, {
          'action': 'router',
          'abilityName': 'EntryAbility',
          'params': { 'cardTarget': 'upcoming' }
        });
      })

      if (this.hasData()) {
        if (this.t0 !== '') {
          this.rowItem(0)
        }
        if (this.t1 !== '') {
          this.rowItem(1)
        }
        if (this.t2 !== '') {
          this.rowItem(2)
        }
      } else {
        Column() {
          Text($r('app.string.card_empty_upcoming'))
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
        .onClick(() => {
          postCardAction(this, {
            'action': 'router',
            'abilityName': 'EntryAbility',
            'params': {}
          });
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.honyomi_card'))
    .borderRadius(16)
  }

  @Builder
  rowItem(index: number) {
    Row() {
      Stack() {
        Text(this.badgeOf(index))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.honyomi_primary_blue'))
      }
      .width(22)
      .height(22)
      .borderRadius(11)
      .backgroundColor($r('app.color.honyomi_primary_soft_blue'))
      .alignContent(Alignment.Center)

      Text(this.titleOf(index))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.honyomi_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 8 })

      Text(this.dateOf(index))
        .fontSize(11)
        .fontColor($r('app.color.honyomi_primary_blue'))
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': {
          'cardTarget': 'detail',
          'mangaId': this.mangaIdOf(index)
        }
      });
    })
  }

  private badgeOf(index: number): string {
    if (index === 0) { return this.b0; }
    if (index === 1) { return this.b1; }
    return this.b2;
  }

  private titleOf(index: number): string {
    if (index === 0) { return this.t0; }
    if (index === 1) { return this.t1; }
    return this.t2;
  }

  private dateOf(index: number): string {
    if (index === 0) { return this.d0; }
    if (index === 1) { return this.d1; }
    return this.d2;
  }

  private mangaIdOf(index: number): string {
    if (index === 0) { return this.m0; }
    if (index === 1) { return this.m1; }
    return this.m2;
  }
}
