// 通用工具
import { common, Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Settings } from './Settings';

export class Util {
  // 长度为 n 的零数组（阅读器翻页变换数组初始化）
  static zeros(n: number): number[] {
    return new Array<number>(n).fill(0);
  }

  // the global getContext() helper is deprecated since API 18: use UIContext.getHostContext() instead
  static hostAbilityContext(ui: UIContext): common.UIAbilityContext {
    return ui.getHostContext() as common.UIAbilityContext;
  }

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
    try {
      if (seconds < 1) {
        return context.resourceManager.getStringSync($r('app.string.stats_second_short').id, 0);
      }
      const days: number = Math.floor(seconds / 86400);
      const hours: number = Math.floor((seconds % 86400) / 3600);
      const minutes: number = Math.floor((seconds % 3600) / 60);
      const secs: number = seconds % 60;
      const parts: string[] = [];
      if (days > 0) {
        parts.push(context.resourceManager.getStringSync($r('app.string.stats_day_short').id, days));
      }
      if (hours > 0) {
        parts.push(context.resourceManager.getStringSync($r('app.string.stats_hour_short').id, hours));
      }
      if (minutes > 0 && (days === 0 || hours === 0)) {
        parts.push(context.resourceManager.getStringSync($r('app.string.stats_minute_short').id, minutes));
      }
      if (secs > 0 && days === 0 && hours === 0) {
        parts.push(context.resourceManager.getStringSync($r('app.string.stats_second_short').id, secs));
      }
      return parts.join(' ');
    } catch (e) {
      throw new Error(`format duration failed: ${e}`);
    }
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
    try {
      return context.resourceManager.getStringSync(res.id);
    } catch (e) {
      throw new Error(`weekday label failed: ${e}`);
    }
  }


  // 相对时间（"N 分钟前"等）：统一返回 string，拼接处不再出现 [object Object]
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
      return Util.resText($r('app.string.util_time_minutes_ago'), m, Util.formatDate(ms));
    }
    if (diff < day) {
      return Util.resText($r('app.string.util_time_hours_ago'), Math.floor(diff / hour), Util.formatDate(ms));
    }
    if (diff < 30 * day) {
      return Util.resText($r('app.string.util_time_days_ago'), Math.floor(diff / day), Util.formatDate(ms));
    }
    return Util.formatDate(ms);
  }

  // 资源字符串解析：context 取 Settings.init 登记的应用上下文；不可得时回退 fallback
  private static resText(res: Resource, arg: number, fallback: string): string {
    const ctx = Settings.appContext();
    if (ctx === undefined) {
      return fallback;
    }
    try {
      return ctx.resourceManager.getStringSync(res.id, arg);
    } catch (e) {
      throw new Error(`resolve text failed: ${e}`);
    }
  }

  static statusLabel(status: string): Resource {
    switch (status) {
      case 'ongoing':
        return $r('app.string.util_status_ongoing');
      case 'completed':
        return $r('app.string.util_status_completed');
      case 'licensed':
        return $r('app.string.util_status_licensed');
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

  // 分类名 → 本地化标签：内置分类（内容类型 code）走资源，用户自建/改名分类原样显示
  static categoryLabel(name: string): ResourceStr {
    if (name === 'manga') {
      return $r('app.string.category_manga');
    }
    if (name === 'novel') {
      return $r('app.string.category_novel');
    }
    if (name === 'video') {
      return $r('app.string.category_video');
    }
    return name;
  }

  // 同 categoryLabel，返回 string（用于插值拼接场景）
  static categoryLabelStr(ui: UIContext, name: string): string {
    if (name === 'manga') {
      return Util.resStr(ui, $r('app.string.category_manga'));
    }
    if (name === 'novel') {
      return Util.resStr(ui, $r('app.string.category_novel'));
    }
    if (name === 'video') {
      return Util.resStr(ui, $r('app.string.category_video'));
    }
    return name;
  }

  // 本地源名称显示：内置三源走资源，其余源原样
  static localSourceName(ui: UIContext, key: string, name: string): string {
    if (key === 'local') {
      return Util.resStr(ui, $r('app.string.browse_local_source_name'));
    }
    if (key === 'local_novel') {
      return Util.resStr(ui, $r('app.string.browse_local_novel_name'));
    }
    if (key === 'local_video') {
      return Util.resStr(ui, $r('app.string.browse_local_video_name'));
    }
    return name;
  }

  // 本地源作品简介：描述字段为内置 code（或历史中文值）时转本地化文案，真实简介原样
  static localDescriptionLabel(ui: UIContext, description: string): string {
    if (description === 'local_desc_manga' || description === '本地导入的漫画') {
      return Util.resStr(ui, $r('app.string.local_desc_manga'));
    }
    if (description === 'local_desc_novel' || description === '本地导入的小说') {
      return Util.resStr(ui, $r('app.string.local_desc_novel'));
    }
    if (description === 'local_desc_video' || description === '本地导入的视频') {
      return Util.resStr(ui, $r('app.string.local_desc_video'));
    }
    return description;
  }

  // 从资源取字符串（用于 toast / 非组件上下文）；args 对应资源中的 %d/%s 占位
  static resStr(ui: UIContext, res: Resource, args: Array<string | number> = []): string {
    const ctx = ui.getHostContext();
    if (ctx === undefined) {
      return '';
    }
    try {
      return ctx.resourceManager.getStringSync(res.id, ...args);
    } catch (e) {
      throw new Error(`resolve string failed: ${e}`);
    }
  }

  static toast(ui: UIContext, message: string): void {
    try {
      ui.getPromptAction().showToast({ message: message });
    } catch (e) {
      throw new Error(`show toast failed: ${e}`);
    }
  }

  static toastRes(ui: UIContext, res: Resource, args: Array<string | number> = []): void {
    Util.toast(ui, Util.resStr(ui, res, args));
  }

  // 错误码 → 本地化文案：服务层业务错误统一为 "code" 或 "code|arg" 格式，
  // 未识别内容（插件自抛消息/引擎透传/系统错误）原样返回
  static errText(ui: UIContext, raw: string): string {
    let code: string = raw;
    let arg: string = '';
    const sep: number = raw.indexOf('|');
    if (sep >= 0) {
      code = raw.substring(0, sep);
      arg = raw.substring(sep + 1);
    }
    let res: Resource | undefined = undefined;
    switch (code) {
      case 'cf_required':
        res = $r('app.string.cf_retry_hint');
        break;
      case 'source_unavailable':
        res = $r('app.string.reader_source_unavailable');
        break;
      case 'no_content':
        res = $r('app.string.reader_no_content');
        break;
      case 'play_failed':
        res = $r('app.string.video_play_failed');
        break;
      case 'video_no_streams':
        res = $r('app.string.video_no_streams');
        break;
      case 'download_cancelled':
        res = $r('app.string.download_error_cancelled');
        break;
      case 'download_failed':
        res = $r('app.string.download_error_failed');
        break;
      case 'download_timeout':
        res = $r('app.string.download_error_timeout');
        break;
      case 'download_fail':
        res = $r('app.string.download_error_fail');
        break;
      case 'stream_only':
        res = $r('app.string.download_error_stream_only');
        break;
      case 'download_not_ready':
        res = $r('app.string.download_error_not_ready');
        break;
      case 'source_not_found':
        res = $r('app.string.download_error_source_missing');
        break;
      case 'chapter_missing':
        res = $r('app.string.local_error_chapter_missing');
        break;
      case 'unsupported_format':
        res = $r('app.string.local_error_unsupported_format');
        break;
      case 'video_missing':
        res = $r('app.string.local_error_video_missing');
        break;
      case 'redirect_blocked':
        res = $r('app.string.net_redirect_blocked');
        break;
      case 'too_many_redirects':
        res = $r('app.string.net_too_many_redirects');
        break;
      case 'tts_busy':
        res = $r('app.string.tts_error_busy');
        break;
      case 'tts_stalled':
        res = $r('app.string.tts_error_stalled');
        break;
      case 'tts_unavailable':
        res = $r('app.string.tts_error_unavailable');
        break;
      case 'engine_create_failed':
        res = $r('app.string.jsvm_error_engine_create');
        break;
      case 'script_failed':
        res = $r('app.string.jsvm_error_script_failed');
        break;
      case 'ext_not_loaded':
        res = $r('app.string.ext_error_not_loaded');
        break;
      case 'ext_broken':
        res = $r('app.string.ext_error_broken');
        break;
      case 'ext_init_failed':
        res = $r('app.string.ext_error_init_failed');
        break;
      case 'ext_init_timeout':
        res = $r('app.string.ext_error_init_timeout');
        break;
      case 'ext_call_timeout':
        res = $r('app.string.ext_error_call_timeout');
        break;
      case 'ext_call_failed':
        res = $r('app.string.ext_error_call_failed');
        break;
      case 'ext_invalid_json':
        res = $r('app.string.ext_error_invalid_json');
        break;
      case 'ext_unknown':
        res = $r('app.string.ext_error_unknown');
        break;
      case 'plugin_bad_key':
        res = $r('app.string.plugin_error_bad_key');
        break;
      case 'plugin_missing_name':
        res = $r('app.string.plugin_error_missing_name');
        break;
      case 'plugin_bad_version_code':
        res = $r('app.string.plugin_error_bad_version_code');
        break;
      case 'plugin_bad_engine':
        res = $r('app.string.plugin_error_bad_engine');
        break;
      case 'plugin_dsl_too_new':
        res = $r('app.string.plugin_error_dsl_too_new');
        break;
      case 'plugin_app_too_old':
        res = $r('app.string.plugin_error_app_too_old');
        break;
      case 'plugin_read_failed':
        res = $r('app.string.plugin_error_read_failed');
        break;
      case 'plugin_repo_not_https':
        res = $r('app.string.plugin_error_repo_not_https');
        break;
      case 'plugin_checksum_mismatch':
        res = $r('app.string.plugin_error_checksum_mismatch');
        break;
      case 'plugin_missing_main':
        res = $r('app.string.plugin_error_missing_main');
        break;
      case 'plugin_replace_failed':
        res = $r('app.string.plugin_error_replace_failed');
        break;
      case 'plugin_no_manifest':
        res = $r('app.string.plugin_error_no_manifest');
        break;
      case 'plugin_repo_entry_not_https':
        res = $r('app.string.plugin_error_repo_entry_not_https');
        break;
      case 'plugin_runtime_invalid':
        res = $r('app.string.plugin_error_runtime_invalid');
        break;
      case 'plugin_runtime_missing':
        res = $r('app.string.plugin_error_runtime_missing');
        break;
      case 'plugin_invalid_detail':
        res = $r('app.string.plugin_error_invalid_detail');
        break;
      case 'plugin_no_chapter_text':
        res = $r('app.string.plugin_error_no_chapter_text');
        break;
      case 'plugin_no_video_list':
        res = $r('app.string.plugin_error_no_video_list');
        break;
      default:
        break;
    }
    if (res === undefined) {
      return raw;
    }
    return arg === '' ? Util.resStr(ui, res) : Util.resStr(ui, res, [arg]);
  }

  // 用系统浏览器打开链接
  static openUrl(context: common.UIAbilityContext, url: string): void {
    const want: Want = { action: 'ohos.want.action.viewData', uri: url, entities: ['entity.system.browsable'] };
    context.startAbility(want).catch((_e: Error) => {
    });
  }

  // 智能读取文本文件：自动识别 UTF-8/UTF-16(BOM)/GB18030/GBK/Big5，避免中文乱码
  static readTextAuto(path: string): string {
    try {
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
        try {
          fs.closeSync(file);
        } catch (_e) {
        }
      }
    } catch (e) {
      throw new Error(`read text file failed: ${e}`);
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
