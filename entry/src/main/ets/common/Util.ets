// 通用工具
import { common, Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Settings } from './Settings';

export class Util {
  // 长度为 n 的零数组（阅读器翻页变换数组初始化）
  static zeros(n: number): number[] {
    return new Array<number>(n).fill(0);
  }

  // PC 鼠标点击时是否按住 Ctrl（经事件对象的 getModifierKeyState 查询；触屏或不支持时返回 false）
  // 用于 PC 端 Ctrl+点击进入/切换多选，移动端不受影响
  static isCtrlHeld(event: BaseEvent): boolean {
    if (event.getModifierKeyState === undefined) {
      return false;
    }
    try {
      return event.getModifierKeyState(['Ctrl']);
    } catch (_e) {
      return false;
    }
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

  // 字符串原样返回；避免模板插值把整个对象格式化成 [object Object]
  static errSummary(e: Object | string): string {
    if (typeof e === 'string') {
      return e;
    }
    const be = e as BusinessError;
    const message: string = typeof be.message === 'string' && be.message !== '' ? be.message : 'unknown error';
    if (typeof be.code === 'number') {
      return `${be.code}: ${message}`;
    }
    return message;
  }

  // 捕获的异常 → 可读摘要：BusinessError 取 "code: message"，普通 Error 取 message，

  // 常见网络原因归组为独立码（errText 本地化展示），未识别的保留原始 code + message
  static netErrOf(e: Object | string): string {
    const be = e as BusinessError;
    const code: number = typeof be.code === 'number' ? be.code : -1;
    if (code === 2300006) {
      return 'net_host_resolve_failed';
    }
    if (code === 2300007) {
      return 'net_connect_failed';
    }
    if (code === 2300028) {
      return 'net_timeout';
    }
    if (code === 2300056) {
      return 'net_interrupted';
    }
    const curl: number = code - 2300000;
    if (curl === 35 || curl === 51 || curl === 53 || curl === 54 || curl === 58 || curl === 59 ||
      curl === 60 || curl === 64 || curl === 66 || curl === 77 || curl === 80 || curl === 82 ||
      curl === 83 || curl === 90 || curl === 91) {
      return 'net_ssl_failed';
    }
    return `net_request_failed|${Util.errSummary(e)}`;
  }

  // 网络层 BusinessError（@ohos.net.http 返回 curl 系错误码，基数 2300000）→ 稳定错误码：

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
      case 'bt_download_first':
        res = $r('app.string.video_bt_download_first');
        break;
      case 'bt_component_required':
        res = $r('app.string.download_bt_component_required');
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
      case 'hls_live_unsupported':
        res = $r('app.string.download_error_hls_live');
        break;
      case 'hls_unsupported_encryption':
        res = $r('app.string.download_error_hls_encrypted');
        break;
      case 'hls_parse_failed':
      case 'hls_no_segments':
      case 'hls_decrypt_failed':
      case 'hls_write_failed':
        res = $r('app.string.download_error_failed');
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
      case 'net_host_resolve_failed':
        res = $r('app.string.net_host_resolve_failed');
        break;
      case 'net_connect_failed':
        res = $r('app.string.net_connect_failed');
        break;
      case 'net_timeout':
        res = $r('app.string.net_timeout');
        break;
      case 'net_ssl_failed':
        res = $r('app.string.net_ssl_failed');
        break;
      case 'net_interrupted':
        res = $r('app.string.net_interrupted');
        break;
      case 'net_request_failed':
        res = $r('app.string.net_request_failed');
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
      case 'plugin_write_failed':
        res = $r('app.string.plugin_error_write_failed');
        break;
      case 'plugin_uninstall_failed':
        res = $r('app.string.plugin_error_uninstall_failed');
        break;
      case 'plugin_start_read_failed':
        res = $r('app.string.plugin_error_start_read_failed');
        break;
      case 'plugin_checksum_failed':
        res = $r('app.string.plugin_error_checksum_failed');
        break;
      case 'plugin_extract_failed':
        res = $r('app.string.plugin_error_extract_failed');
        break;
      case 'plugin_manifest_read_failed':
        res = $r('app.string.plugin_error_manifest_read_failed');
        break;
      case 'plugin_stage_failed':
        res = $r('app.string.plugin_error_stage_failed');
        break;
      default:
        break;
    }
    if (res === undefined) {
      return raw;
    }
    return arg === '' ? Util.resStr(ui, res) : Util.resStr(ui, res, [arg]);
  }

  // 错误码 → 本地化文案：服务层业务错误统一为 "code" 或 "code|arg" 格式，

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

  // 统一换行符为 \n，并去除解码残留的 BOM 字符
  static cleanText(text: string): string {
    return text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
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

  private static decodeWith(encoding: string, data: Uint8Array): string {
    const options: util.TextDecoderOptions = { fatal: true, ignoreBOM: false };
    return util.TextDecoder.create(encoding, options).decodeToString(data);
  }
}
