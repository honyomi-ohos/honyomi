// 展开/收起小组件（精确复刻 Mihon anim_caret_down 折叠翻转箭头）：
// 箭头由左右两臂（24 视口下 2×8 竖条）组成，展开时两臂绕铰点反向各旋 90°
// ——v 先折平成横线再翻成 ^，铰点整体上浮 6/24（对应 caret01 的 translate 动画）；
// 300ms + Curve.FastOutSlowIn 对应 Android fast_out_slow_in 插值器，与 Mihon 动画规格一致。
// label 传空串时仅渲染箭头（分组头指示器场景），传文案时渲染「箭头 + 展开/收起文本」。
import { ThemePalette } from '../../common/Theme';

// Mihon anim_caret_down 动画规格：300ms fast_out_slow_in
const EXPAND_TOGGLE_DURATION_MS: number = 300;
// 24 视口下的臂条尺寸（与 anim_caret_down pathData 一致：宽 2、高 8）
const CARET_STROKE: number = 2;
const CARET_ARM_LEN: number = 8;

@Component
export struct ExpandToggle {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop @Watch('onExpandedChanged') expanded: boolean = false;
  @Prop iconSize: number = 18;
  @Prop tint: ResourceColor = '';
  @Prop label: ResourceStr = '';
  @Prop labelSize: number = 13;
  // 左臂角（v 态 135° → ^ 态 45°）、右臂角（v 态 45° → ^ 态 135°，与左臂反向）、
  // 铰点竖向偏移（v 态 +3 → ^ 态 −3，24 视口单位）
  @State leftAngle: number = 135;
  @State rightAngle: number = 45;
  @State caretShift: number = 3;
  onToggle: () => void = () => {};

  aboutToAppear(): void {
    // 初始态直接就位，不做首次翻转动画
    this.applyExpanded(this.expanded);
  }

  // 父组件切换 expanded 后驱动翻转：两臂反向旋转 + 铰点位移，
  // 对应 anim_caret_down 的三段 objectAnimator（同为 300ms fast_out_slow_in）
  onExpandedChanged(): void {
    this.getUIContext().animateTo({ duration: EXPAND_TOGGLE_DURATION_MS, curve: Curve.FastOutSlowIn }, (): void => {
      this.applyExpanded(this.expanded);
    });
  }

  private applyExpanded(expanded: boolean): void {
    this.leftAngle = expanded ? 45 : 135;
    this.rightAngle = expanded ? 135 : 45;
    this.caretShift = expanded ? -3 : 3;
  }

  // 24 视口单位 → vp 缩放
  private unit(): number {
    return this.iconSize / 24;
  }

  build() {
    Row({ space: 4 }) {
      Stack() {
        // 左臂：竖条置于铰点下方 3 单位（条内铰点 (1,1)），展开时绕铰点旋至 45°
        Rect({ width: this.unit() * CARET_STROKE, height: this.unit() * CARET_ARM_LEN })
          .fill(this.tint !== '' ? this.tint : this.pal.text)
          .position({ x: this.unit() * 11, y: this.unit() * 11 })
          .rotate({ angle: this.leftAngle, centerX: this.unit(), centerY: this.unit() })
        // 右臂：竖条置于铰点上方 3 单位（条内铰点 (1,7)），与左臂反向旋转
        Rect({ width: this.unit() * CARET_STROKE, height: this.unit() * CARET_ARM_LEN })
          .fill(this.tint !== '' ? this.tint : this.pal.text)
          .position({ x: this.unit() * 11, y: this.unit() * 5 })
          .rotate({ angle: this.rightAngle, centerX: this.unit(), centerY: this.unit() * 7 })
      }
      .width(this.iconSize)
      .height(this.iconSize)
      .translate({ y: this.caretShift * this.unit() })
      if (this.label !== '') {
        Text(this.label)
          .fontSize(this.labelSize)
          .fontColor(this.tint !== '' ? this.tint : this.pal.primary)
      }
    }
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onToggle();
    })
  }
}
