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

  // 清除探测缓存：用户在系统设置中后开"智感握姿"开关后，本进程内可重新探测生效
  static invalidate(): void {
    GripSupport.probed = false;
    GripSupport.supported = false;
  }

  private static probe(): boolean {
    const noop: (status: motion.HoldingHandStatus) => void =
      (_status: motion.HoldingHandStatus): void => {
      };
    if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
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
    return false;
  }
}
