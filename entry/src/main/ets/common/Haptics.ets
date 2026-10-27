import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 触感反馈：参考华为系应用，在翻页、章节跳转、档位切换等关键操作给短振反馈。
// usage 'touch' 跟随系统「触感反馈」开关；效果不支持时静默降级为时长振动。
export class Haptics {
  private static softReady: boolean | null = null;

  // 轻触反馈：翻页、点按确认等高频操作
  static soft(): void {
    Haptics.checkSoftEffect();
    if (Haptics.softReady === false) {
      Haptics.vibrate({ type: 'time', duration: 8 });
      return;
    }
    Haptics.vibrate({ type: 'preset', effectId: 'haptic.effect.soft', count: 1 });
  }

  // 明显反馈：章节切换、模式切换、进度滑杆释放等
  static medium(): void {
    Haptics.checkSoftEffect();
    if (Haptics.softReady === false) {
      Haptics.vibrate({ type: 'time', duration: 16 });
      return;
    }
    Haptics.vibrate({ type: 'preset', effectId: 'haptic.effect.hard', count: 1 });
  }

  // 检查设备是否支持系统预置轻触效果（结果缓存）
  private static checkSoftEffect(): void {
    if (Haptics.softReady !== null) {
      return;
    }
    vibrator.isSupportEffect('haptic.effect.soft').then((state: boolean) => {
      Haptics.softReady = state;
    }).catch(() => {
      Haptics.softReady = false;
    });
  }

  private static vibrate(effect: vibrator.VibrateEffect): void {
    try {
      vibrator.startVibration(effect, { usage: 'touch' }).catch(() => {
      });
    } catch (error) {
      const err = error as BusinessError;
      void err;
    }
  }
}
