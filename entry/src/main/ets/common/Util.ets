// 通用工具

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
}
