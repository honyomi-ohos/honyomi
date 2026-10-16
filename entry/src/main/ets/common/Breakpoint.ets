// 一多断点工具：对齐系统 WidthBreakpoint 参考范围与华为设计规范（HarmonyOS Design）
// sm：<600vp（手机竖屏） md：600~840vp（折叠屏展开/平板竖屏）
// lg：840~1200vp（平板横屏） xl：≥1200vp（PC/大屏窗口）
// 窗口宽度 vp 由 Index 写入 AppStorage('windowW')，页面经 @StorageProp 读取后调用本工具适配
export class Bp {
  static readonly MD_MIN: number = 600;
  static readonly LG_MIN: number = 840;
  static readonly XL_MIN: number = 1200;

  // 宽屏左侧常驻导航栏宽度（Index wideRail），页面计算内容限宽缩进时需扣除
  static readonly WIDE_RAIL_W: number = 200;

  // lg 及以上视为宽屏（侧边导航/双栏/居中弹窗阈值）
  static isWide(widthVp: number): boolean {
    return widthVp >= Bp.LG_MIN;
  }

  // 半模态/弹窗类型：宽屏 CENTER 居中弹窗，窄屏 BOTTOM 底部半模态
  static sheetType(widthVp: number): SheetType {
    return widthVp >= Bp.LG_MIN ? SheetType.CENTER : SheetType.BOTTOM;
  }

  // 半模态/弹窗宽度：宽屏定宽居中，窄屏全宽（wideWidth 默认 560vp，与 HDS 弹窗规范一致）
  // 返回 Dimension（而非 Length）：SheetOptions.width 不接受任意字符串
  static sheetWidth(widthVp: number, wideWidth: number = 560): Dimension {
    return widthVp >= Bp.LG_MIN ? wideWidth : '100%';
  }

  // 半模态高度：宽屏定高（默认 560vp），窄屏随内容自适应
  static sheetHeight(widthVp: number, wideHeight: number = 560): SheetSize | Dimension {
    return widthVp >= Bp.LG_MIN ? wideHeight : SheetSize.FIT_CONTENT;
  }

  // 限宽内容列的左右缩进：滚动容器保持全宽（滚动条贴窗口边），
  // 内容行/卡片以该缩进居中限宽；maxWidth 为内容列宽度（720/960），
  // railW 为宽屏左侧导航占宽（默认常驻导航栏；设置页场景由调用方传实际值）
  static contentInset(widthVp: number, maxWidth: number = 720,
    railW: number = Bp.WIDE_RAIL_W): number {
    const pageW = widthVp - (widthVp >= Bp.LG_MIN ? railW : 0);
    const inset = Math.floor((pageW - maxWidth) / 2);
    return inset > 0 ? inset : 0;
  }
}

// 断点取值映射（参考官方 ResponsiveLayout 示例 WidthBreakpointType<T>）：
// 按 sm/md/lg/xl 四档返回各自配置值，替代散落各页的三元表达式
// 用法：private pad: BpValue<number> = new BpValue<number>(16, 24, 32, 32); this.pad.getValue(this.windowW)
export class BpValue<T> {
  private readonly smVal: T;
  private readonly mdVal: T;
  private readonly lgVal: T;
  private readonly xlVal: T;

  constructor(sm: T, md: T, lg: T, xl: T) {
    this.smVal = sm;
    this.mdVal = md;
    this.lgVal = lg;
    this.xlVal = xl;
  }

  getValue(widthVp: number): T {
    if (widthVp >= Bp.XL_MIN) {
      return this.xlVal;
    }
    if (widthVp >= Bp.LG_MIN) {
      return this.lgVal;
    }
    return widthVp >= Bp.MD_MIN ? this.mdVal : this.smVal;
  }
}
