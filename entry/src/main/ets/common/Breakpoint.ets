// 一多断点工具：对齐华为设计规范（HarmonyOS Design）
// sm：<600vp（手机竖屏） md：600~840vp（折叠屏展开/平板竖屏） lg：≥840vp（平板横屏/PC）
// 大屏下内容需限宽居中，避免列表/表单被拉伸过宽
export class Bp {
  static readonly MD_MIN: number = 600;
  static readonly LG_MIN: number = 840;

  static sizeOf(widthVp: number): string {
    if (widthVp >= Bp.LG_MIN) {
      return 'lg';
    }
    return widthVp >= Bp.MD_MIN ? 'md' : 'sm';
  }

  static isWide(widthVp: number): boolean {
    return widthVp >= Bp.LG_MIN;
  }

  // 响应式页面水平边距：sm 16 / md 24 / lg 32
  static hPadding(widthVp: number): number {
    if (widthVp >= Bp.LG_MIN) {
      return 32;
    }
    return widthVp >= Bp.MD_MIN ? 24 : 16;
  }
}
