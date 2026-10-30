import { fileIo, picker } from '@kit.CoreFileKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';

// 故障日志导出（对齐 Mihon crashLogUtil.dumpLogs）：
// faultLogger 自 API 18 起弃用，改用 hiAppEvent 订阅系统崩溃/卡死事件
// （EntryAbility 启动时注册，内存缓冲，每类最多 10 条），附设备与版本信息头，
// 经系统文档保存器导出为文本文件

// 缓冲的单条故障记录
interface FaultRecord {
  label: string; // 展示标签（事件名/故障类型）
  time: number; // 事件时间戳（毫秒）
  detail: string; // 事件参数 JSON 与故障日志全文
}

// 事件参数 raw 模型（params 声明为 object，须经命名模型归一后访问）
interface FaultParamsRaw {
  time?: number;
  crash_type?: string;
  external_log?: Array<string>;
}

// 每类系统事件最多缓冲条数（对齐原 FaultLogger.query 每类 10 条）
const MAX_RECORDS_PER_EVENT = 10;
// 单条故障日志读取截断上限（256KB），防超大日志撑爆内存
const MAX_LOG_TEXT_LEN = 262144;

export class CrashLogs {
  private static records: FaultRecord[] = [];
  private static watched: boolean = false;

  // 订阅系统崩溃/卡死事件：必须在应用启动后、业务逻辑前注册，
  // 故障发生（进程存活期间或重启后补投）时经 onReceive 缓冲到内存
  static startWatch(): void {
    if (CrashLogs.watched) {
      return;
    }
    const watcher: hiAppEvent.Watcher = {
      name: 'honyomiFaultWatcher',
      appEventFilters: [
        {
          domain: hiAppEvent.domain.OS,
          names: [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE],
        },
      ],
      onReceive: (domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>): void => {
        for (const group of appEventGroups) {
          for (const info of group.appEventInfos) {
            CrashLogs.bufferRecord(group.name, info);
          }
        }
      },
    };
    try {
      hiAppEvent.addWatcher(watcher);
      CrashLogs.watched = true;
    } catch (e) {
      // 订阅失败不阻断启动，仅失去本次会话的故障缓冲
    }
  }

  // 缓冲单条事件：记录事件名/类型/时间与故障日志全文，超限时淘汰同类最旧一条
  private static bufferRecord(eventName: string, info: hiAppEvent.AppEventInfo): void {
    const paramsRaw: string = JSON.stringify(info.params);
    const parsed: FaultParamsRaw = JSON.parse(paramsRaw) as FaultParamsRaw;
    let time = Date.now();
    if (typeof parsed.time === 'number') {
      time = parsed.time;
    }
    let label = eventName;
    if (typeof parsed.crash_type === 'string' && parsed.crash_type !== '') {
      label = `${eventName}/${parsed.crash_type}`;
    }
    const rec: FaultRecord = {
      label: label,
      time: time,
      detail: `params: ${paramsRaw}\n${CrashLogs.readExternalLogs(parsed)}`,
    };
    const records = CrashLogs.records;
    records.push(rec);
    // 容量裁剪：同类事件超过上限时移除最旧一条
    let count = 0;
    let oldestIdx = -1;
    for (let i = 0; i < records.length; i++) {
      if (records[i].label.split('/')[0] === eventName) {
        count++;
        if (oldestIdx < 0) {
          oldestIdx = i;
        }
      }
    }
    if (count > MAX_RECORDS_PER_EVENT && oldestIdx >= 0) {
      records.splice(oldestIdx, 1);
    }
  }

  // 读取事件 external_log 指向的故障日志文件（崩溃堆栈全文），总量截断保护
  private static readExternalLogs(parsed: FaultParamsRaw): string {
    const paths = parsed.external_log;
    if (paths === undefined) {
      return '';
    }
    let text = '';
    for (const path of paths) {
      if (path === '') {
        continue;
      }
      text += CrashLogs.readFileText(path);
      if (text.length >= MAX_LOG_TEXT_LEN) {
        break;
      }
    }
    if (text.length > MAX_LOG_TEXT_LEN) {
      text = text.substring(0, MAX_LOG_TEXT_LEN);
    }
    return text;
  }

  private static readFileText(path: string): string {
    try {
      return fileIo.readTextSync(path);
    } catch (e) {
      return '';
    }
  }

  // 返回导出的故障日志条数；0 = 无可导出故障；-1 = 用户取消保存位置
  static async export(context: common.UIAbilityContext): Promise<number> {
    const records = CrashLogs.records;
    if (records.length === 0) {
      return 0;
    }
    const sections: string[] = [];
    for (const rec of records) {
      const time = new Date(rec.time).toISOString();
      sections.push(`===== [${rec.label}] ${time} =====\n${rec.detail}\n`);
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
    } catch (e) {
      throw new Error(`write log file failed: ${e}`);
    } finally {
      try {
        fileIo.closeSync(file);
      } catch (e) {
      }
    }
    return records.length;
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
