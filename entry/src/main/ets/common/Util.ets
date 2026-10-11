// 通用工具
import { common, Want } from '@kit.AbilityKit';

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
}
