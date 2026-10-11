let recentStorage = new LocalStorage();

// 最近阅读卡片：展示最近阅读的漫画与章节，点击行可继续阅读
@Entry(recentStorage)
@Component
struct RecentCard {
  @LocalStorageProp('wide') wide: boolean = false;
  @LocalStorageProp('t0') t0: string = '';
  @LocalStorageProp('t1') t1: string = '';
  @LocalStorageProp('t2') t2: string = '';
  @LocalStorageProp('c0') c0: string = '';
  @LocalStorageProp('c1') c1: string = '';
  @LocalStorageProp('c2') c2: string = '';
  @LocalStorageProp('m0') m0: string = '';
  @LocalStorageProp('m1') m1: string = '';
  @LocalStorageProp('m2') m2: string = '';
  @LocalStorageProp('ch0') ch0: string = '';
  @LocalStorageProp('ch1') ch1: string = '';
  @LocalStorageProp('ch2') ch2: string = '';
  @LocalStorageProp('time0') time0: string = '';
  @LocalStorageProp('time1') time1: string = '';
  @LocalStorageProp('time2') time2: string = '';
  @LocalStorageProp('b0') b0: string = '';
  @LocalStorageProp('b1') b1: string = '';
  @LocalStorageProp('b2') b2: string = '';

  private hasData(): boolean {
    return this.t0 !== '' || this.t1 !== '' || this.t2 !== '';
  }

  build() {
    Column() {
      // 标题栏：继续阅读 + 跳转历史页签
      Row() {
        Text($r('app.string.card_recent_header'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.mihon_text'))
        Text('›')
          .fontSize(16)
          .fontColor($r('app.color.mihon_sub'))
          .margin({ left: 4 })
      }
      .justifyContent(FlexAlign.Start)
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })
      .onClick(() => {
        postCardAction(this, {
          'action': 'router',
          'abilityName': 'EntryAbility',
          'params': { 'cardTarget': 'history' }
        });
      })

      if (this.hasData()) {
        // 行 0
        if (this.t0 !== '') {
          this.rowItem(0)
        }
        // 行 1
        if (this.t1 !== '') {
          this.rowItem(1)
        }
        // 行 2
        if (this.t2 !== '') {
          this.rowItem(2)
        }
      } else {
        // 空状态
        Column() {
          Text($r('app.string.card_empty_recent'))
            .fontSize(13)
            .fontColor($r('app.color.mihon_sub'))
          Text($r('app.string.card_open_hint'))
            .fontSize(12)
            .fontColor($r('app.color.mihon_primary_blue'))
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
    .backgroundColor($r('app.color.mihon_card'))
    .borderRadius(16)
  }

  @Builder
  rowItem(index: number) {
    Row() {
      // 行首徽标
      Stack() {
        Text(this.badgeOf(index))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.mihon_primary_blue'))
      }
      .width(22)
      .height(22)
      .borderRadius(11)
      .backgroundColor($r('app.color.mihon_primary_soft_blue'))
      .alignContent(Alignment.Center)

      // 标题 + 章节
      Column() {
        Text(this.titleOf(index))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.mihon_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.chapterOf(index))
          .fontSize(11)
          .fontColor($r('app.color.mihon_sub'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })

      // 时间（仅宽卡片显示）
      if (this.wide) {
        Text(this.timeOf(index))
          .fontSize(11)
          .fontColor($r('app.color.mihon_sub'))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': {
          'cardTarget': 'reader',
          'mangaId': this.mangaIdOf(index),
          'chapterId': this.chapterIdOf(index)
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

  private chapterOf(index: number): string {
    if (index === 0) { return this.c0; }
    if (index === 1) { return this.c1; }
    return this.c2;
  }

  private timeOf(index: number): string {
    if (index === 0) { return this.time0; }
    if (index === 1) { return this.time1; }
    return this.time2;
  }

  private mangaIdOf(index: number): string {
    if (index === 0) { return this.m0; }
    if (index === 1) { return this.m1; }
    return this.m2;
  }

  private chapterIdOf(index: number): string {
    if (index === 0) { return this.ch0; }
    if (index === 1) { return this.ch1; }
    return this.ch2;
  }
}
