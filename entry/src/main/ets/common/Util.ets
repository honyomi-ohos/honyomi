// 通用工具
import { common, Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export class Util {
  static formatDate(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const d: Date = new Date(ms);
    const month: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const mm: string = month < 10 ? `0${month}` : `${month}`;
    const dd: string = day < 10 ? `0${day}` : `${day}`;
    return `${d.getFullYear()}-${mm}-${dd}`;
  }

  // 字节数可读化（对齐 Android Formatter.formatFileSize 的近似展示）
  static formatBytes(bytes: number): string {
    if (bytes >= 1024 * 1024 * 1024) {
      return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GB`;
    }
    if (bytes >= 1024 * 1024) {
      return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
    }
    if (bytes >= 1024) {
      return `${Math.round(bytes / 1024)} KB`;
    }
    return `${bytes} B`;
  }

  // 紧凑时长（对齐 Mihon Duration.toDurationString）：
  // "3天2小时" / "5小时30分" / "45分" / "30秒"
  static formatDuration(context: common.Context, seconds: number): string {
    if (seconds < 1) {
      return context.resourceManager.getStringSync($r('app.string.stats_second_short'), 0);
    }
    const days: number = Math.floor(seconds / 86400);
    const hours: number = Math.floor((seconds % 86400) / 3600);
    const minutes: number = Math.floor((seconds % 3600) / 60);
    const secs: number = seconds % 60;
    const parts: string[] = [];
    if (days > 0) {
      parts.push(context.resourceManager.getStringSync($r('app.string.stats_day_short'), days));
    }
    if (hours > 0) {
      parts.push(context.resourceManager.getStringSync($r('app.string.stats_hour_short'), hours));
    }
    if (minutes > 0 && (days === 0 || hours === 0)) {
      parts.push(context.resourceManager.getStringSync($r('app.string.stats_minute_short'), minutes));
    }
    if (secs > 0 && days === 0 && hours === 0) {
      parts.push(context.resourceManager.getStringSync($r('app.string.stats_second_short'), secs));
    }
    return parts.join(' ');
  }

  // 星期短标签（周统计横轴）：day 0=周日 .. 6=周六
  static weekdayShort(context: common.Context, day: number): string {
    let res: Resource = $r('app.string.stats_wd_sun');
    if (day === 1) {
      res = $r('app.string.stats_wd_mon');
    } else if (day === 2) {
      res = $r('app.string.stats_wd_tue');
    } else if (day === 3) {
      res = $r('app.string.stats_wd_wed');
    } else if (day === 4) {
      res = $r('app.string.stats_wd_thu');
    } else if (day === 5) {
      res = $r('app.string.stats_wd_fri');
    } else if (day === 6) {
      res = $r('app.string.stats_wd_sat');
    }
    return context.resourceManager.getStringSync(res);
  }


  static timeAgo(ms: number): Resource | string {
    if (ms <= 0) {
      return '';
    }
    const diff: number = Date.now() - ms;
    const minute: number = 60 * 1000;
    const hour: number = 60 * minute;
    const day: number = 24 * hour;
    if (diff < 0) {
      return Util.formatDate(ms);
    }
    if (diff < hour) {
      const m: number = Math.max(1, Math.floor(diff / minute));
      return $r('app.string.util_time_minutes_ago', m);
    }
    if (diff < day) {
      return $r('app.string.util_time_hours_ago', Math.floor(diff / hour));
    }
    if (diff < 30 * day) {
      return $r('app.string.util_time_days_ago', Math.floor(diff / day));
    }
    return Util.formatDate(ms);
  }

  static statusLabel(status: string): Resource {
    switch (status) {
      case 'ongoing':
        return $r('app.string.util_status_ongoing');
      case 'completed':
        return $r('app.string.util_status_completed');
      case 'hiatus':
        return $r('app.string.util_status_hiatus');
      case 'cancelled':
        return $r('app.string.util_status_cancelled');
      case 'publication_complete':
        return $r('app.string.util_status_publication_complete');
      default:
        return $r('app.string.util_status_unknown');
    }
  }

  // 从资源取字符串（用于 toast / 非组件上下文）；args 对应资源中的 %d/%s 占位
  static resStr(ui: UIContext, res: Resource, args: Array<string | number> = []): string {
    const ctx = ui.getHostContext();
    if (ctx === undefined) {
      return '';
    }
    return ctx.resourceManager.getStringSync(res, ...args);
  }

  static toast(ui: UIContext, message: string): void {
    ui.getPromptAction().showToast({ message: message });
  }

  static toastRes(ui: UIContext, res: Resource, args: Array<string | number> = []): void {
    Util.toast(ui, Util.resStr(ui, res, args));
  }

  // 用系统浏览器打开链接
  static openUrl(context: common.UIAbilityContext, url: string): void {
    const want: Want = { action: 'ohos.want.action.viewData', uri: url, entities: ['entity.system.browsable'] };
    context.startAbility(want).catch((_e: Error) => {
    });
  }

  // 智能读取文本文件：自动识别 UTF-8/UTF-16(BOM)/GB18030/GBK/Big5，避免中文乱码
  static readTextAuto(path: string): string {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const size: number = fs.statSync(file.fd).size;
      if (size <= 0) {
        return '';
      }
      const buf: ArrayBuffer = new ArrayBuffer(size);
      const read: number = fs.readSync(file.fd, buf);
      return Util.decodeBytes(new Uint8Array(buf, 0, read));
    } finally {
      fs.closeSync(file);
    }
  }

  // 字节流解码：BOM 优先，随后依次以严格模式尝试 UTF-8/GB18030/GBK/Big5，全部失败回退宽松 UTF-8
  static decodeBytes(bytes: Uint8Array): string {
    if (bytes.length === 0) {
      return '';
    }
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      return Util.cleanText(Util.decodeWith('utf-16le', bytes.subarray(2)));
    }
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      return Util.cleanText(Util.decodeWith('utf-16be', bytes.subarray(2)));
    }
    try {
      return Util.cleanText(Util.decodeWith('utf-8', bytes));
    } catch (e) {
      // 非 UTF-8，继续尝试中文编码
    }
    try {
      return Util.cleanText(Util.decodeWith('gb18030', bytes));
    } catch (e) {
      // 非 GB18030
    }
    try {
      return Util.cleanText(Util.decodeWith('gbk', bytes));
    } catch (e) {
      // 非 GBK
    }
    try {
      return Util.cleanText(Util.decodeWith('big5', bytes));
    } catch (e) {
      // 非 Big5
    }
    return Util.cleanText(Util.decodeWith('utf-8', bytes));
  }

  private static decodeWith(encoding: string, data: Uint8Array): string {
    const options: util.TextDecoderOptions = { fatal: true, ignoreBOM: false };
    return util.TextDecoder.create(encoding, options).decodeToString(data);
  }

  // 统一换行符为 \n，并去除解码残留的 BOM 字符
  static cleanText(text: string): string {
    return text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  }
}
