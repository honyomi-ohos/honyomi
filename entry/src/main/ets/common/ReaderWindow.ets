import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

// 阅读类页面共用的窗口方向/亮度控制（ReaderPage / NovelReaderPage 原各自复制一份）
// free=传感器自由旋转；portrait/landscape=跟随传感器(含倒置)；
// lock_portrait/lock_landscape=固定方向(不受传感器影响)
export class ReaderWindow {
  static orientationTarget(name: string): window.Orientation {
    if (name === 'portrait') {
      return window.Orientation.AUTO_ROTATION_PORTRAIT;
    }
    if (name === 'landscape') {
      return window.Orientation.AUTO_ROTATION_LANDSCAPE;
    }
    if (name === 'lock_portrait') {
      return window.Orientation.PORTRAIT;
    }
    if (name === 'lock_landscape') {
      return window.Orientation.LANDSCAPE;
    }
    return window.Orientation.AUTO_ROTATION;
  }

  static applyOrientation(ctx: common.UIAbilityContext, name: string): void {
    window.getLastWindow(ctx).then((win: window.Window) => {
      if (canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
        win.setPreferredOrientation(ReaderWindow.orientationTarget(name)).catch(() => {
        });
      }
    }).catch(() => {
    });
  }

  static applyBrightness(ctx: common.UIAbilityContext, level: number): void {
    window.getLastWindow(ctx).then((win: window.Window) => {
      win.setWindowBrightness(level).catch(() => {
      });
    }).catch(() => {
    });
  }

  // 阅读中屏幕常亮（true=保持常亮，false=恢复系统默认熄屏策略）
  static setKeepScreenOn(ctx: common.UIAbilityContext, on: boolean): void {
    window.getLastWindow(ctx).then((win: window.Window) => {
      win.setWindowKeepScreenOn(on).catch(() => {
      });
    }).catch(() => {
    });
  }

  // 退出阅读页：还原窗口方向、亮度与熄屏策略
  static restore(ctx: common.UIAbilityContext): void {
    window.getLastWindow(ctx).then((win: window.Window) => {
      if (canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
        win.setPreferredOrientation(window.Orientation.UNSPECIFIED).catch(() => {
        });
      }
      win.setWindowBrightness(0).catch(() => {
      });
      win.setWindowKeepScreenOn(false).catch(() => {
      });
    }).catch(() => {
    });
  }
}
