// 主题选择器（参考 Mihon ThemePrefWidget）：
// 窄屏：横向滚动的主题预览卡片列表（触屏滑动；鼠标左键拖拽经 PanGesture 驱动——
//   嵌套在外层纵向 Scroll 内时滚轮会被外层拦截、隐藏滚动条下鼠标拖拽不生效，见 faqs-arkui-860）；
// 宽屏（lg ≥840vp，PC/平板横屏）：Flex 换行网格平铺全部主题，无需滚动。
// 选中卡片描边高亮并带对勾标记；点击回调主题 id。
import { Theme, ThemePalette, ThemeScheme, AppThemeDef } from '../../common/Theme';
import { Bp } from '../../common/Breakpoint';
import { AppIcon } from './AppIcon';

// 单个主题预览卡片
@Component
export struct ThemePreviewCard {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop themeId: string = '';
  @Prop isDark: boolean = false;
  @Prop amoled: boolean = false;
  @Prop selected: boolean = false;
  onPick: (id: string) => void = (id: string) => {};

  // 当前模式下的预览色板（随 isDark/amoled 变化重新求值）
  private scheme(): ThemeScheme {
    return Theme.colorsFor(this.themeId, this.isDark, this.amoled);
  }

  build() {
    Column({ space: 6 }) {
      // 迷你界面模型：顶栏（chip 底 + primary 圆标 + 标题条）+ 内容条 + 主色按钮
      Column() {
        Row({ space: 5 }) {
          Column()
            .width(13)
            .height(13)
            .borderRadius(7)
            .backgroundColor(this.scheme().primary)
          Column()
            .width(36)
            .height(5)
            .borderRadius(2.5)
            .backgroundColor(this.scheme().text)
        }
        .width('100%')
        .height(26)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 8, right: 8 })
        .backgroundColor(this.scheme().chip)

        Column({ space: 5 }) {
          Column()
            .width('72%')
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.scheme().text)
          Column()
            .width('48%')
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.scheme().sub)
          Row() {
            Column()
              .width(34)
              .height(13)
              .borderRadius(7)
              .backgroundColor(this.scheme().primary)
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 8, right: 8, top: 9, bottom: 9 })
        .layoutWeight(1)
      }
      .width(104)
      .height(86)
      .borderRadius(12)
      .clip(true)
      .backgroundColor(this.scheme().bg)
      .border({
        width: this.selected ? 2 : 1,
        color: this.selected ? this.pal.primary : this.pal.divider
      })

      // 标签：主题名 + 选中对勾
      Row({ space: 3 }) {
        if (this.selected) {
          AppIcon({ name: 'check_circle', iconSize: 13, tint: this.pal.primary })
        }
        Text(Theme.findTheme(this.themeId).labelRes)
          .fontSize(11)
          .fontColor(this.selected ? this.pal.primary : this.pal.sub)
          .maxLines(1)
      }
      .height(16)
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onPick(this.themeId);
    })
  }
}

// 主题选择器：窄屏横向滚动 / 宽屏换行网格（预览随当前深浅/AMOLED 模式渲染）
@Component
export struct ThemePicker {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('amoled') amoled: boolean = false;
  @StorageProp('windowW') windowW: number = 0;
  @Prop selectedTheme: string = 'default';
  onPick: (id: string) => void = (id: string) => {};
  private scroller: Scroller = new Scroller();
  // PanGesture 偏移为累计值，记录上次值换算单次增量
  private lastPanX: number = 0;

  // 鼠标左键拖拽滚动（触屏/触摸板走内置滚动手势，仅鼠标拖拽在内置滚动下不生效）
  private onMousePan(event: GestureEvent): void {
    if (event.sourceTool !== SourceTool.MOUSE) {
      return;
    }
    const delta: number = event.offsetX - this.lastPanX;
    this.lastPanX = event.offsetX;
    if (delta !== 0) {
      this.scroller.scrollBy(-delta, 0);
    }
  }

  build() {
    if (Bp.isWide(this.windowW)) {
      // 宽屏：全部主题换行平铺，无需滚动
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(Theme.themes(), (t: AppThemeDef) => {
          ThemePreviewCard({
            themeId: t.id,
            isDark: this.isDark,
            amoled: this.amoled,
            selected: this.selectedTheme === t.id,
            onPick: (id: string): void => {
              this.onPick(id);
            }
          })
            .margin(5)
        }, (t: AppThemeDef) => `${t.id}-${this.selectedTheme === t.id ? 1 : 0}`)
      }
      .width('100%')
      .padding({ left: 11, right: 11, top: 7, bottom: 1 })
    } else {
      // 窄屏：横向滚动列表
      Scroll(this.scroller) {
        Row({ space: 10 }) {
          ForEach(Theme.themes(), (t: AppThemeDef) => {
            ThemePreviewCard({
              themeId: t.id,
              isDark: this.isDark,
              amoled: this.amoled,
              selected: this.selectedTheme === t.id,
              onPick: (id: string): void => {
                this.onPick(id);
              }
            })
          }, (t: AppThemeDef) => `${t.id}-${this.selectedTheme === t.id ? 1 : 0}`)
        }
        .padding({ left: 16, right: 16, top: 12, bottom: 6 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .width('100%')
      .gesture(
        PanGesture(new PanGestureOptions({ fingers: 1, direction: PanDirection.Horizontal }))
          .onActionStart((event: GestureEvent) => {
            this.lastPanX = 0;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.onMousePan(event);
          })
      )
    }
  }
}
