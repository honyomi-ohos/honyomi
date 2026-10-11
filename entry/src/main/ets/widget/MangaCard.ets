let mangaStorage = new LocalStorage();

// 漫画卡片：单部书架漫画的封面 + 标题 + 续读章节，点击直接继续阅读
@Entry(mangaStorage)
@Component
struct MangaCard {
  @LocalStorageProp('wide') wide: boolean = false;
  @LocalStorageProp('empty') empty: boolean = true;
  @LocalStorageProp('title') title: string = '';
  @LocalStorageProp('chapter') chapter: string = '';
  @LocalStorageProp('mangaId') mangaId: string = '';
  @LocalStorageProp('chapterId') chapterId: string = '';
  @LocalStorageProp('hasChapter') hasChapter: boolean = false;
  @LocalStorageProp('hasCover') hasCover: boolean = false;

  private badgeChar(): string {
    if (this.title === '') {
      return '#';
    }
    return this.title.charAt(0).toUpperCase();
  }

  // 点击分发：有续读章节 → 阅读器；有漫画 → 详情页；否则打开应用
  private openTarget(): void {
    if (this.hasChapter && this.mangaId !== '' && this.chapterId !== '') {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': {
          'cardTarget': 'reader',
          'mangaId': this.mangaId,
          'chapterId': this.chapterId
        }
      });
      return;
    }
    if (this.mangaId !== '') {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': {
          'cardTarget': 'detail',
          'mangaId': this.mangaId
        }
      });
      return;
    }
    postCardAction(this, {
      'action': 'router',
      'abilityName': 'EntryAbility',
      'params': {}
    });
  }

  build() {
    Column() {
      if (this.empty) {
        this.emptyState()
      } else if (this.wide) {
        this.wideLayout()
      } else {
        this.posterLayout()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.mihon_card'))
    .borderRadius(16)
    .clip(true)
    .onClick(() => {
      this.openTarget();
    })
  }

  // 空状态：无绑定漫画
  @Builder
  emptyState() {
    Column() {
      Text($r('app.string.card_manga_empty'))
        .fontSize(13)
        .fontColor($r('app.color.mihon_sub'))
      Text($r('app.string.card_open_hint'))
        .fontSize(12)
        .fontColor($r('app.color.mihon_primary_blue'))
        .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 2×2 海报式：封面全卡铺满 + 底部渐变遮罩 + 标题/章节叠字
  @Builder
  posterLayout() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.hasCover) {
        Image('memory://cover')
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Text(this.badgeChar())
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.mihon_primary_blue'))
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.mihon_chip'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      // 底部渐变遮罩，保证白色文字可读
      Column()
        .width('100%')
        .height(72)
        .linearGradient({
          angle: 180,
          colors: [['#00000000', 0.0], ['#B3000000', 1.0]]
        })
      // 标题 + 续读章节
      Column() {
        Text(this.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.hasChapter) {
          Text(this.chapter)
            .fontSize(11)
            .fontColor('#E6FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12, bottom: 10 })
    }
    .width('100%')
    .height('100%')
  }

  // 2×4 分栏式：左封面 + 右标题/章节/继续阅读提示
  @Builder
  wideLayout() {
    Row() {
      Stack() {
        if (this.hasCover) {
          Image('memory://cover')
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text(this.badgeChar())
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.mihon_primary_blue'))
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.mihon_chip'))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .height('100%')
      .aspectRatio(0.7)
      .backgroundColor($r('app.color.mihon_chip'))

      Column() {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.mihon_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.hasChapter) {
          Text(this.chapter)
            .fontSize(12)
            .fontColor($r('app.color.mihon_sub'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
        }
        Text($r('app.string.card_manga_read_hint'))
          .fontSize(12)
          .fontColor($r('app.color.mihon_primary_blue'))
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 14, right: 14 })
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
  }
}
