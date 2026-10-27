import { uiMaterial } from '@kit.ArkUI';
import { Bp } from '../../common/Breakpoint';

// 半模态（bindSheet）可选差异项：全部可选，未提供的字段使用 SheetPreset 默认值。
// 解决 17 个文件中 preferType/width/detents/dragBar/showClose/blurStyle 选项样板的重复
export interface SheetExtras {
  /** 标题（不提供则不设标题栏） */
  title?: ResourceStr;

  /** 高度（默认 SheetSize.FIT_CONTENT） */
  height?: SheetSize | Dimension;

  /** 档位（默认 [SheetSize.FIT_CONTENT]，最多 3 档） */
  detents?: [SheetSize | Dimension, (SheetSize | Dimension)?, (SheetSize | Dimension)?];

  /** 是否显示关闭按钮（默认 true） */
  showClose?: boolean;

  /** true = 沉浸光感（液态玻璃）系统材质，低版本自动回退模糊样式 */
  glass?: boolean;

  /** true = 弹层外可交互 */
  interactive?: boolean;

  /** 背景色（覆盖默认模糊底） */
  bg?: ResourceColor;

  /** 遮罩颜色 */
  maskColor?: ResourceColor;

  /** 宽屏定宽（默认 560vp，与 HDS 弹窗规范一致） */
  wideWidth?: number;

  /** 弹层关闭回调 */
  onDisappear?: () => void;
}

// 断点自适应半模态选项工厂：窄屏 BOTTOM 全宽、宽屏（≥lg）CENTER 定宽居中，
// 统一 dragBar/COMPONENT_ULTRA_THICK 模糊底等默认值，各站点只声明差异项
export class SheetPreset {
  static fit(windowW: number, extras?: SheetExtras): SheetOptions {
    const opts: SheetOptions = {
      preferType: Bp.sheetType(windowW),
      width: Bp.sheetWidth(windowW, extras !== undefined && extras.wideWidth !== undefined
        ? extras.wideWidth : 560),
      height: SheetSize.FIT_CONTENT,
      detents: [SheetSize.FIT_CONTENT],
      dragBar: true,
      showClose: true,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK
    };
    if (extras !== undefined) {
      if (extras.height !== undefined) {
        opts.height = extras.height;
      }
      if (extras.detents !== undefined) {
        opts.detents = extras.detents;
      }
      if (extras.showClose !== undefined) {
        opts.showClose = extras.showClose;
      }
      if (extras.title !== undefined) {
        opts.title = { title: extras.title };
      }
      if (extras.glass === true) {
        opts.systemMaterial = new uiMaterial.ImmersiveMaterial();
      }
      if (extras.interactive === true) {
        opts.enableOutsideInteractive = true;
      }
      if (extras.bg !== undefined) {
        opts.backgroundColor = extras.bg;
      }
      if (extras.maskColor !== undefined) {
        opts.maskColor = extras.maskColor;
      }
      if (extras.onDisappear !== undefined) {
        opts.onDisappear = extras.onDisappear;
      }
    }
    return opts;
  }
}
