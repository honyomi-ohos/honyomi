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

  static timeAgo(ms: number): string {
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
      return `${m}分钟前`;
    }
    if (diff < day) {
      return `${Math.floor(diff / hour)}小时前`;
    }
    if (diff < 30 * day) {
      return `${Math.floor(diff / day)}天前`;
    }
    return Util.formatDate(ms);
  }

  static statusLabel(status: string): string {
    switch (status) {
      case 'ongoing':
        return '连载中';
      case 'completed':
        return '已完结';
      case 'hiatus':
        return '休刊中';
      case 'cancelled':
        return '已弃坑';
      case 'publication_complete':
        return '出版完毕';
      default:
        return '未知';
    }
  }

  static toast(ui: UIContext, message: string): void {
    ui.getPromptAction().showToast({ message: message });
  }
}
