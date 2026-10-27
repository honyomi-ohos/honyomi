// 华为阅读风格宽滑道 Slider：InSet 宽胶囊滑道 + 圆形滑块，
// 步长档位适中（≤30 档）时在滑道上绘制小圆点表示 step；
// 档位过密的连续调节（如百分比滤镜）不绘制圆点，避免挤成虚线；
// 阅读进度等特殊背景可通过 tint 参数覆盖默认主题配色。
// 注意：动态入参必须用 @Prop（普通成员仅在创建时赋值一次，
// 父组件翻页/进度更新时不会触发内部 Slider 重新应用值，滑块会停在旧位置）
import { ThemePalette } from '../../common/Theme';

@Component
export struct WideSlider {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop sliderValue: number = 0;
  @Prop min: number = 0;
  @Prop max: number = 100;
  @Prop step: number = 1;
  @Prop trackTint: ResourceColor = '';
  @Prop fillTint: ResourceColor = '';
  @Prop knobTint: ResourceColor = '';
  @Prop knobBorderTint: ResourceColor = '';
  // 圆点刻度开关（进度类滑条建议关闭）
  dotsEnabled: boolean = true;
  onChange: (value: number, mode: SliderChangeMode) => void =
    (value: number, mode: SliderChangeMode) => {
    };

  build() {
    Slider({
      value: this.sliderValue,
      min: this.min,
      max: this.max,
      step: this.step,
      style: SliderStyle.InSet
    })
      .trackThickness(28)
      .trackBorderRadius(14)
      .selectedColor(this.fillTint === '' ? this.pal.primary : this.fillTint)
      .trackColor(this.trackTint === '' ? this.pal.chip : this.trackTint)
      .blockColor(this.knobTint === '' ? this.pal.card : this.knobTint)
      .blockSize({ width: 20, height: 20 })
      .blockBorderColor(this.knobBorderTint === '' ? this.pal.divider : this.knobBorderTint)
      .blockBorderWidth(1)
      .showSteps(this.hasStepDots())
      .stepSize(4)
      .stepColor('#80808080')
      .onChange((v: number, mode: SliderChangeMode) => {
        this.onChange(v, mode);
      })
  }

  // 圆点刻度仅在 1~30 档时绘制（每档仍有可见间距）
  private hasStepDots(): boolean {
    if (!this.dotsEnabled || this.step <= 0 || this.max <= this.min) {
      return false;
    }
    const intervals: number = (this.max - this.min) / this.step;
    return intervals >= 1 && intervals <= 30;
  }
}
