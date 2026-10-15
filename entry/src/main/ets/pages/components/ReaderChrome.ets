// 阅读器共享 Chrome 组件（Wave 3I 从 ReaderPage / NovelReaderPage 抽出）：
// 菜单骨架（顶栏+占位+底栏）、章节导航行、页码胶囊、指示徽标、方向 Sheet、滤镜容器。
// 样式与两页原实现逐行一致，行为不变。
import { ThemePalette } from '../../common/Theme';
import { AppIconRes, AppIcon } from './AppIcon';
import { PickerSheet } from './PickerSheet';

// 屏幕方向的可选值（与方向选择 sheet 选项一一对应，两阅读器共用）
export const READER_ORIENTATIONS: string[] =
  ['free', 'portrait', 'landscape', 'lock_portrait', 'lock_landscape'];
export const READER_ORIENTATION_ICONS: string[] =
  ['screen_rotation', 'stay_current_portrait', 'stay_current_landscape', 'screen_lock_portrait', 'screen_lock_landscape'];

// 阅读器菜单骨架：顶栏（返回 + 标题/章节名）+ 点击关闭占位 + 底栏
// 顶栏从上方滑入、底栏经 bottomBar 注入（内部自带下方滑入转场）
@Component
export struct ReaderMenu {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop statusBarH: number = 0;
  onBack: () => void = (): void => {};
  onBackdrop: () => void = (): void => {};
  @BuilderParam bottomBar: () => void = this.emptyBuilder;

  build() {
    Column() {
      // 顶栏
      Row() {
        AppIcon({ name: 'arrow_back', iconSize: 24, tint: '#FFFFFF' })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.onBack();
          })
        Column() {
          Text(this.title)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.subtitle)
            .fontSize(11)
            .fontColor('#CCCCCC')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 4, right: 16, top: this.statusBarH + 10, bottom: 10 })
      // 液态玻璃顶栏（对齐沉浸光感材质规范）：内容相关的材质模糊 + 半透明深色叠层 + 底缘高光描边
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
      .backgroundColor('#66000000')
      .border({ width: { bottom: 0.5 }, color: { bottom: '#1FFFFFFF' } })
      // 对齐 Mihon ReaderAppBars：顶栏从屏幕上方滑入/滑出 + 渐隐（滑移 200ms、渐隐 150ms）
      .transition(
        TransitionEffect.translate({ y: -120 })
          .animation({ duration: 200, curve: Curve.Linear })
          .combine(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.Linear }))
      )

      // 占位（空 Column 宽度默认自适应内容为 0，必须显式撑满才能接收点击关闭菜单）
      Column()
        .layoutWeight(1)
        .width('100%')
        .onClick(() => {
          this.onBackdrop();
        })

      this.bottomBar()
    }
    .width('100%')
    .height('100%')
    // 整棵子树删除时根组件需有消失转场时间，保证子组件的退出动画完整播放
    .transition(
      TransitionEffect.asymmetric(
        TransitionEffect.IDENTITY,
        TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Linear })
      )
    )
  }

  @Builder
  emptyBuilder() {
  }
}

// 阅读器底栏（液态玻璃设计，参考华为阅读底栏布局）：
// 进度（章节导航行）与设置行拆为两个独立的悬浮玻璃胶囊
// （材质模糊 + 半透明叠层 + 高光描边 + 柔和投影），从屏幕下方滑入/滑出
@Component
export struct ReaderBottomBar {
  @Prop navBarH: number = 0;
  @BuilderParam navRow: () => void = this.emptyBuilder;
  @BuilderParam settingsRow: () => void = this.emptyBuilder;

  // 进度组：章节导航行（上一章 / 进度胶囊 / 下一章）独占一个液态玻璃胶囊
  @Builder
  progressGroup() {
    Column() {
      this.navRow()
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 8, right: 8 })
    .borderRadius(28)
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .backgroundColor('#59000000')
    .border({ width: 1, color: '#1FFFFFFF' })
    .shadow({ radius: 32, color: '#66000000', offsetY: 12 })
  }

  // 设置组：功能图标行独占一个液态玻璃胶囊
  @Builder
  settingsGroup() {
    Column() {
      this.settingsRow()
    }
    .width('100%')
    .padding({ top: 4, bottom: 4, left: 6, right: 6 })
    .borderRadius(28)
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
    .backgroundColor('#59000000')
    .border({ width: 1, color: '#1FFFFFFF' })
    .shadow({ radius: 32, color: '#66000000', offsetY: 12 })
  }

  build() {
    Column({ space: 10 }) {
      this.progressGroup()
      this.settingsGroup()
    }
    .width('100%')
    .margin({ left: 16, right: 16, bottom: this.navBarH + 12 })
    // 对齐 Mihon ReaderAppBars：底栏从屏幕下方滑入/滑出 + 渐隐
    .transition(
      TransitionEffect.translate({ y: 240 })
        .animation({ duration: 200, curve: Curve.Linear })
        .combine(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.Linear }))
    )
  }

  @Builder
  emptyBuilder() {
  }
}

// 阅读器章节导航行：上一章圆钮 + 中间胶囊（BuilderParam 注入）+ 下一章圆钮
@Component
export struct ReaderNavRow {
  @Prop prevActive: boolean = true;
  @Prop nextActive: boolean = true;
  @BuilderParam pill: () => void = this.emptyBuilder;
  onPrev: () => void = (): void => {};
  onNext: () => void = (): void => {};

  build() {
    Row({ space: 12 }) {
      ReaderChapterButton({
        icon: 'skip_previous',
        isActive: this.prevActive,
        onTap: (): void => {
          this.onPrev();
        }
      })

      this.pill()

      ReaderChapterButton({
        icon: 'skip_next',
        isActive: this.nextActive,
        onTap: (): void => {
          this.onNext();
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  emptyBuilder() {
  }
}

// 章节跳转圆钮（44×44，禁用态 opacity 0.4；是否可点的 guard 由调用方回调内保留）
@Component
export struct ReaderChapterButton {
  @Prop icon: string = 'skip_previous';
  @Prop isActive: boolean = true;
  onTap: () => void = (): void => {};

  build() {
    Column() {
      Image(AppIconRes.get(this.icon))
        .width(24)
        .height(24)
        .fillColor('#FFFFFF')
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .justifyContent(FlexAlign.Center)
    // 玻璃内嵌控件：半透明填充 + 发丝高光描边
    .backgroundColor('#26FFFFFF')
    .border({ width: 1, color: '#1AFFFFFF' })
    .opacity(this.isActive ? 1 : 0.4)
    .onClick(() => {
      this.onTap();
    })
  }
}

// 设置行图标按钮（48×44，白图标）
@Component
export struct ReaderMenuIconButton {
  @Prop icon: string = 'settings';
  onTap: () => void = (): void => {};

  build() {
    Column() {
      Image(AppIconRes.get(this.icon))
        .width(24)
        .height(24)
        .fillColor('#FFFFFF')
    }
    .width(48)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onTap();
    })
  }
}

// 页码胶囊：当前页 + Slider + 总页数（Slider 松手才翻页）
@Component
export struct ReaderPagePill {
  @Prop pos: number = 1;
  @Prop total: number = 1;
  onSeek: (value: number) => void = (value: number): void => {};

  build() {
    Row() {
      Text(`${this.pos}`)
        .fontSize(13)
        .fontColor('#FFFFFF')
        .width(24)
        .textAlign(TextAlign.End)
      Slider({
        value: this.pos,
        min: 1,
        max: this.total > 1 ? this.total : 2,
        step: 1,
        style: SliderStyle.OutSet
      })
        .layoutWeight(1)
        .blockColor('#FFFFFF')
        .selectedColor('#88FFFFFF')
        .trackColor('#33FFFFFF')
        .margin({ left: 8, right: 8 })
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.onSeek(Math.round(value));
          }
        })
      Text(`${this.total}`)
        .fontSize(13)
        .fontColor('#FFFFFF')
        .width(24)
    }
    .layoutWeight(1)
    .height(44)
    .borderRadius(22)
    // 玻璃内嵌胶囊：半透明填充 + 发丝高光描边
    .backgroundColor('#1AFFFFFF')
    .border({ width: 1, color: '#14FFFFFF' })
    .padding({ left: 14, right: 14 })
  }
}

// 进度/页码指示徽标（菜单收起时右下角悬浮）
@Component
export struct ReaderIndicatorBadge {
  @Prop text: string = '';
  @Prop navBarH: number = 0;

  build() {
    Text(this.text)
      .fontSize(11)
      .fontColor('#FFFFFF')
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(10)
      // 液态玻璃悬浮徽标：材质模糊 + 半透明叠层 + 高光描边
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
      .backgroundColor('#4D000000')
      .border({ width: 0.5, color: '#1AFFFFFF' })
      .margin({ left: 16, top: 16, right: 16, bottom: this.navBarH + 16 })
  }
}

// 屏幕方向选择 Sheet（两阅读器共用）
@Component
export struct ReaderOrientationSheet {
  @Prop selected: string = 'free';
  onPick: (value: string) => void = (value: string): void => {};

  build() {
    PickerSheet({
      options: [$r('app.string.reader_orientation_free'), $r('app.string.reader_orientation_portrait'),
        $r('app.string.reader_orientation_landscape'), $r('app.string.reader_orientation_lock_portrait'),
        $r('app.string.reader_orientation_lock_landscape')],
      icons: READER_ORIENTATION_ICONS,
      selectedIndex: READER_ORIENTATIONS.indexOf(this.selected),
      onPick: (index: number): void => {
        const v: string | undefined = READER_ORIENTATIONS[index];
        if (v !== undefined) {
          this.onPick(v);
        }
      }
    })
  }
}

// 滤镜容器：灰度/反色/亮度/对比度/饱和度滤镜链唯一出现处（对齐 Mihon 滤镜面板）
// 内容经 BuilderParam 注入；onAreaChange 等区域同步留在内容组件上，语义不变
@Component
export struct ReaderFilterArea {
  @Prop grayOn: boolean = false;
  @Prop invOn: boolean = false;
  @Prop brightOn: boolean = false;
  @Prop brightPct: number = 1;
  @Prop contrOn: boolean = false;
  @Prop contrPct: number = 1;
  @Prop satOn: boolean = false;
  @Prop satPct: number = 1;
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Stack() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .grayscale(this.grayOn ? 1 : 0)
    .invert(this.invOn ? 1 : 0)
    .brightness(this.brightOn ? this.brightPct : 1)
    .contrast(this.contrOn ? this.contrPct : 1)
    .saturate(this.satOn ? this.satPct : 1)
  }

  @Builder
  emptyBuilder() {
  }
}

// 章节过渡视图（对齐 Mihon ChapterTransition）：
// kind='next'：上方“已读完”当前章 + 下方“下一章”信息（无下一章时为提示卡片）
// kind='prev'：上方“上一章”信息（无上一章时为提示卡片）+ 下方“当前”章
// 组件自身不处理点击（点击由宿主容器/触摸热区接管），宿主负责全屏居中
@Component
export struct ReaderTransition {
  @Prop kind: string = 'next';
  @Prop currentName: string = '';
  // 相邻章节名；空串表示没有相邻章节（显示“没有下一章/上一章”卡片）
  @Prop targetName: string = '';
  @Prop textCol: string = '#ECEEF2';
  @Prop subCol: string = '#99ECEEF2';

  // 章节信息块：小号次要色标签 + 中号章节名（多行省略）
  @Builder
  chapterBlock(label: ResourceStr, name: string) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(13)
        .fontColor(this.subCol)
        .maxLines(1)
        .width('100%')
      Text(name)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .lineHeight(26)
        .fontColor(this.textCol)
        .maxLines(5)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  // 无相邻章节提示卡片（描边卡片 + info 图标）
  @Builder
  noChapterCard(label: ResourceStr) {
    Row({ space: 12 }) {
      AppIcon({ name: 'info', iconSize: 20, tint: this.textCol })
      Text(label)
        .fontSize(14)
        .lineHeight(20)
        .fontColor(this.textCol)
    }
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .borderRadius(12)
    .border({ width: 1, color: this.subCol })
  }

  build() {
    Column() {
      if (this.kind === 'next') {
        // 已读完：当前章节
        this.chapterBlock($r('app.string.transition_finished'), this.currentName)
        // 下一章信息 / 无下一章提示卡片
        if (this.targetName !== '') {
          Column() {
            this.chapterBlock($r('app.string.transition_next'), this.targetName)
          }
          .width('100%')
          .margin({ top: 32 })
        } else {
          Column() {
            this.noChapterCard($r('app.string.transition_no_next'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 32 })
        }
      } else {
        // 上一章信息 / 无上一章提示卡片
        if (this.targetName !== '') {
          Column() {
            this.chapterBlock($r('app.string.transition_previous'), this.targetName)
          }
          .width('100%')
        } else {
          Column() {
            this.noChapterCard($r('app.string.transition_no_previous'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        // 当前章节
        Column() {
          this.chapterBlock($r('app.string.transition_current'), this.currentName)
        }
        .width('100%')
        .margin({ top: 32 })
      }
    }
    .constraintSize({ maxWidth: 520 })
    .width('100%')
    .padding({ left: 32, right: 32, top: 16, bottom: 16 })
    .alignItems(HorizontalAlign.Center)
  }
}
