import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from './Settings';

const DOMAIN = 0x0000;
const TAG = 'Log';

// 统一日志封装：debug 级受「高级 → 详细日志」开关门禁（关闭时零开销直返），
// info/warn/error 恒定输出；各模块沿用自身 domain/tag 以便 hilog 过滤
export class Log {
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
