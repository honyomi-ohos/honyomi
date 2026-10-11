// 智感握姿能力探测：canIUse 预检 + motion.on 实际订阅验证
// 设备设置中无“智感握姿”开关时 motion.on 抛 801，据此在不支持的设备上隐藏该模式选项
import { motion } from '@kit.MultimodalAwarenessKit';

export class GripSupport {
  private static probed: boolean = false;
  private static supported: boolean = false;

  static isSupported(): boolean {
    if (!GripSupport.probed) {
      GripSupport.probed = true;
      GripSupport.supported = GripSupport.probe();
    }
    return GripSupport.supported;
  }

  private static probe(): boolean {
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      return false;
    }
    const noop: (status: motion.HoldingHandStatus) => void =
      (_status: motion.HoldingHandStatus): void => {
      };
    try {
      motion.on('holdingHandChanged', noop);
    } catch (error) {
      return false;
    }
    try {
      motion.off('holdingHandChanged', noop);
    } catch (error) {
    }
    return true;
  }
}
