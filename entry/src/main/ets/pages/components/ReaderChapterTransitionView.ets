import { AppIcon } from './AppIcon';

// 章节过渡视图（对齐 Mihon ChapterTransition）：
// kind='next'：上方“已读完”当前章 + 下方“下一章”信息（无下一章时为提示卡片）
// kind='prev'：上方“上一章”信息（无上一章时为提示卡片）+ 下方“当前”章
// 章节块含汉化组与已下载标记；两章章节号不连续时居中显示缺章警告卡片
// 组件自身不处理点击（点击由宿主容器/触摸热区接管），宿主负责全屏居中
@Component
export struct ReaderChapterTransitionView {
  @Prop kind: string = 'next';
  @Prop currentName: string = '';
  @Prop currentScanlator: string = '';
  @Prop currentDownloaded: boolean = false;
  // 相邻章节名；空串表示没有相邻章节（显示“没有下一章/上一章”卡片）
  @Prop targetName: string = '';
  @Prop targetScanlator: string = '';
  @Prop targetDownloaded: boolean = false;
  // 两章之间被跳过/缺失的章节数（<=0 不显示警告）
  @Prop gapCount: number = 0;
  @Prop textCol: string = '#ECEEF2';
  @Prop subCol: string = '#99ECEEF2';
  @Prop warnCol: string = '#FFFF6E6E';

  // 章节信息块：次要色标签 + 章节名（含已下载标记，多行省略）+ 汉化组
  @Builder
  chapterText(header: ResourceStr, name: string, scanlator: string, downloaded: boolean) {
    Column({ space: 4 }) {
      Text(header)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.subCol)
        .maxLines(1)
        .width('100%')
      Row({ space: 6 }) {
        if (downloaded) {
          AppIcon({ name: 'check_circle', iconSize: 18, tint: this.textCol })
            .margin({ top: 4 })
        }
        Text(name)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .lineHeight(28)
          .fontColor(this.textCol)
          .maxLines(5)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      if (scanlator !== '') {
        Text(scanlator)
          .fontSize(12)
          .fontColor(this.subCol)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  // 描边提示卡片（info=无相邻章节 / warning=缺章警告）
  @Builder
  outlinedCard(iconName: string, iconTint: ResourceColor, text: ResourceStr) {
    Row({ space: 16 }) {
      AppIcon({ name: iconName, iconSize: 20, tint: iconTint })
      Text(text)
        .fontSize(14)
        .lineHeight(20)
        .fontColor(this.textCol)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: 12
    })
    .borderRadius(12)
    .border({ width: 1, color: this.subCol })
  }

  // 缺章警告卡片（自带与上方的 24vp 间距，供两处直接调用）
  @Builder
  gapWarningCard() {
    Column() {
      this.outlinedCard('warning', this.warnCol, $r('app.string.missing_chapters_warning', this.gapCount))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 24 })
  }

  build() {
    Column() {
      if (this.kind === 'next') {
        // 已读完：当前章节
        this.chapterText($r('app.string.transition_finished'), this.currentName, this.currentScanlator,
          this.currentDownloaded)
        // 缺章警告（有下一章且章节号不连续时）
        if (this.targetName !== '' && this.gapCount > 0) {
          this.gapWarningCard()
        }
        // 下一章信息 / 无下一章提示卡片
        if (this.targetName !== '') {
          Column() {
            this.chapterText($r('app.string.transition_next'), this.targetName, this.targetScanlator,
              this.targetDownloaded)
          }
          .width('100%')
          .margin({ top: 24 })
        } else {
          Column() {
            this.outlinedCard('info', this.textCol, $r('app.string.transition_no_next'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 24 })
        }
      } else {
        // 上一章信息 / 无上一章提示卡片
        if (this.targetName !== '') {
          Column() {
            this.chapterText($r('app.string.transition_previous'), this.targetName, this.targetScanlator,
              this.targetDownloaded)
          }
          .width('100%')
        } else {
          Column() {
            this.outlinedCard('info', this.textCol, $r('app.string.transition_no_previous'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        // 缺章警告（有上一章且章节号不连续时）
        if (this.targetName !== '' && this.gapCount > 0) {
          this.gapWarningCard()
        }
        // 当前章节
        Column() {
          this.chapterText($r('app.string.transition_current'), this.currentName, this.currentScanlator,
            this.currentDownloaded)
        }
        .width('100%')
        .margin({ top: 24 })
      }
    }
    .constraintSize({ maxWidth: 460 })
    .width('100%')
    .padding({
      left: 32,
      right: 32,
      top: 16,
      bottom: 16
    })
    .alignItems(HorizontalAlign.Center)
  }
}
