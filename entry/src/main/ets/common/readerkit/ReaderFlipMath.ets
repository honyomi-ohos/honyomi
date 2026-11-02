// 翻页动画纯数学（与渲染解耦，公式与原 NovelReaderPage 实现逐行一致）
export class ReaderFlipMath {
  // 翻转中的页面投影（增强仿真立体感）
  static flipShadow(active: boolean): ShadowOptions {
    if (active) {
      return { radius: 16, color: '#4D000000' };
    }
    return { radius: 0, color: Color.Transparent };
  }

  // 仿真翻转的透视相机距离（px）：约 2 倍页宽，近大远小；非 curl 或无宽时返回 0
  static flipPerspective(curlActive: boolean, widthVp: number, density: number): number {
    if (!curlActive || widthVp <= 0) {
      return 0;
    }
    const px: number = widthVp * density * 2;
    return Math.min(Math.max(px, 400), 2800);
  }

  // 仿真卷曲阴影不透明度：翻起（0→90°）随弯曲渐深，翻过竖直（90→180°）渐消，静止时为 0
  static curlShade(curlActive: boolean, angle: number): number {
    if (!curlActive) {
      return 0;
    }
    const a: number = Math.abs(angle);
    if (a < 0.5) {
      return 0;
    }
    if (a <= 90) {
      return a / 90 * 0.32;
    }
    return Math.max(0, 1 - (a - 90) / 90) * 0.18;
  }
}
