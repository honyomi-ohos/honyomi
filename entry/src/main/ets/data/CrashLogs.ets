import { fileIo, picker } from '@kit.CoreFileKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { FaultLogger } from '@kit.PerformanceAnalysisKit';

// 故障日志导出（对齐 Mihon crashLogUtil.dumpLogs）：
// 汇总本应用最近的 JS 崩溃 / C++ 崩溃 / 卡死故障日志（FaultLogger，
// 每类最多 10 条），附设备与版本信息头，经系统文档保存器导出为文本文件
export class CrashLogs {
  // 返回导出的故障日志条数；0 = 无可导出故障；-1 = 用户取消保存位置
  static async export(context: common.UIAbilityContext): Promise<number> {
    const sections: string[] = [];
    const types: FaultLogger.FaultType[] = [
      FaultLogger.FaultType.JS_CRASH,
      FaultLogger.FaultType.CPP_CRASH,
      FaultLogger.FaultType.APP_FREEZE,
    ];
    for (const type of types) {
      try {
        const logs = await FaultLogger.query(type);
        for (const info of logs) {
          const time = new Date(info.timestamp).toISOString();
          sections.push(`===== [${CrashLogs.typeLabel(type)}] ${time} reason=${info.reason} module=${info.module} =====\n` +
            `${info.fullLog}\n`);
        }
      } catch (_e) {
        // 单类查询失败不阻断整体导出
      }
    }
    if (sections.length === 0) {
      return 0;
    }
    const text = `${CrashLogs.header()}\n\n${sections.join('\n')}`;
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`honyomi_logs_${Date.now()}.txt`];
    const docPicker = new picker.DocumentViewPicker(context);
    const uris: Array<string> = await docPicker.save(options);
    if (uris.length === 0) {
      return -1;
    }
    let file: fileIo.File;
    try {
      file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    } catch (e) {
      throw new Error(`open log file failed: ${e}`);
    }
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      try {
        fileIo.closeSync(file);
      } catch (e) {
      }
    }
    return sections.length;
  }

  private static typeLabel(type: FaultLogger.FaultType): string {
    if (type === FaultLogger.FaultType.JS_CRASH) {
      return 'JS_CRASH';
    }
    if (type === FaultLogger.FaultType.CPP_CRASH) {
      return 'CPP_CRASH';
    }
    if (type === FaultLogger.FaultType.APP_FREEZE) {
      return 'APP_FREEZE';
    }
    return 'FAULT';
  }

  private static header(): string {
    let version = '';
    let versionCode = 0;
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      version = info.versionName;
      versionCode = info.versionCode;
    } catch (_e) {
    }
    return `honyomi crash logs\n` +
      `app: ${version} (${versionCode})\n` +
      `device: ${deviceInfo.productModel} (${deviceInfo.deviceType})\n` +
      `os: ${deviceInfo.osFullName} ${deviceInfo.displayVersion} api ${deviceInfo.sdkApiVersion}\n` +
      `exported: ${new Date().toISOString()}`;
  }
}
