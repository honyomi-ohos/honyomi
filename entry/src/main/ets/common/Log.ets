import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from './Settings';

const DOMAIN = 0x0000;
const TAG = 'Log';

// 统一日志门禁：「高级 → 详细日志」开关经 hilog.setMinLogLevel 全局生效，
// 关闭时进程内全部 hilog.debug（含各模块裸调用）零输出，开启时恢复 DEBUG 级；
// info/warn/error 恒定输出。开关在 EntryAbility 启动与 AdvancedPage 切换时应用。
export class Log {
  // 按当前「详细日志」开关设置进程级最低日志级别（debug 应用下系统不生效，属预期）
  static applyVerboseLogging(): void {
    hilog.setMinLogLevel(Settings.getVerboseLogging() ? hilog.LogLevel.DEBUG : hilog.LogLevel.INFO);
  }

  static debug(tag: string, msg: string): void {
    if (!Settings.getVerboseLogging()) {
      return;
    }
    hilog.debug(DOMAIN, tag, '%{public}s', msg);
  }

  static info(tag: string, msg: string): void {
    hilog.info(DOMAIN, tag, '%{public}s', msg);
  }

  static warn(tag: string, msg: string): void {
    hilog.warn(DOMAIN, tag, '%{public}s', msg);
  }

  static error(tag: string, msg: string): void {
    hilog.error(DOMAIN, tag, '%{public}s', msg);
  }
}
