import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { UIContext, window } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme, ThemePalette } from './Theme';
import { AppKeys } from './AppKeys';
import { BackupPolicyRegistry, NoBackup, NoBackupPrefix, Sensitive } from './BackupPolicy';

const DOMAIN = 0x0000;
const TAG = 'Settings';

// 插件仓库记录（多仓库管理，对齐 Mihon ExtensionStore：地址 + 展示名 + 官网）
export interface PluginStoreRecord {
  url: string;
  name: string;

  // 仓库官网（索引声明 website 字段）；未声明为空字符串
  website: string;
}

// 轻量设置存储（阅读/主题/书架/阅读器/浏览/全局开关等）
export class Settings {
  private static store: preferences.Preferences | undefined = undefined;
  private static appCtx: common.UIAbilityContext | undefined = undefined;
  // flush 防抖定时器（500ms 批量落盘）
  private static flushTimer: number = -1;
  // 避让区高度（vp）写入 AppStorage，供页面上下 padding 避让状态栏/导航栏
  private static avoidSubscribed: boolean = false;

  static init(context: common.UIAbilityContext): void {
    Settings.appCtx = context;
    if (Settings.store === undefined) {
      const options: preferences.Options = { name: 'honyomi_settings' };
      try {
        Settings.store = preferences.getPreferencesSync(context, options);
      } catch (_e) {
      }
    }
  }

  // 供无 context 入参的工具层解析资源字符串（Util.timeAgo 等）
  static appContext(): common.UIAbilityContext | undefined {
    return Settings.appCtx;
  }

  // 立即 flush 并取消防抖定时器（应用退后台/销毁时调用）
  static flushNow(): void {
    if (Settings.flushTimer !== -1) {
      clearTimeout(Settings.flushTimer);
      Settings.flushTimer = -1;
    }
    if (Settings.store !== undefined) {
      try {
        // 同步 try/catch 只能捕获 flush() 同步抛错；Promise 化的落盘失败需 catch 兜底
        Settings.store.flush().catch((e: Object): void => {
          hilog.warn(DOMAIN, TAG, 'settings flushNow failed: %{public}s', `${e}`);
        });
      } catch (_e) {
      }
    }
  }

  // ---- 既有键 ----
  static getReaderMode(): string {
    return Settings.getStr('readerMode', 'ltr');
  }

  static setReaderMode(mode: string): void {
    Settings.setStr('readerMode', mode);
  }

  static getNovelFontSize(): number {
    const n = Settings.getNum('novelFontSize', 18);
    return n >= 14 && n <= 32 ? n : 18;
  }

  static setNovelFontSize(v: number): void {
    Settings.setNum('novelFontSize', v);
  }

  static getNovelLineHeight(): number {
    const n = Settings.getNum('novelLineHeight', 32);
    return n >= 20 && n <= 56 ? n : 32;
  }

  static setNovelLineHeight(v: number): void {
    Settings.setNum('novelLineHeight', v);
  }

  // 小说阅读模式：scroll（滚动）| paged（单页式从左到右）| paged_rtl（单页式从右到左）| double（双页）
  static getNovelReaderMode(): string {
    const raw = Settings.getStr('novelReaderMode', 'scroll');
    if (raw === 'paged' || raw === 'paged_rtl' || raw === 'double') {
      return raw;
    }
    return 'scroll';
  }

  static setNovelReaderMode(v: string): void {
    Settings.setStr('novelReaderMode', v);
  }

  // 小说翻页动画（翻页/双页模式）：curl（仿真）| slide（滑动）| cover（覆盖）
  static getNovelPageAnim(): string {
    const raw = Settings.getStr('novelPageAnim', 'slide');
    if (raw === 'curl' || raw === 'cover') {
      return raw;
    }
    return 'slide';
  }

  static setNovelPageAnim(v: string): void {
    Settings.setStr('novelPageAnim', v);
  }

  // 小说阅读器屏幕方向：free | portrait | landscape | lock_portrait | lock_landscape
  static getNovelOrientation(): string {
    return Settings.getStr('novelOrientation', 'free');
  }

  static setNovelOrientation(v: string): void {
    Settings.setStr('novelOrientation', v);
  }

  // 小说文字配色：auto（跟随背景）| light（浅色文字）| dark（深色文字）
  static getNovelColorScheme(): string {
    const raw = Settings.getStr('novelColorScheme', 'auto');
    if (raw === 'light' || raw === 'dark') {
      return raw;
    }
    return 'auto';
  }

  static setNovelColorScheme(v: string): void {
    Settings.setStr('novelColorScheme', v);
  }

  // 小说正文左右边距（vp）
  static getNovelMargin(): number {
    const n = Settings.getNum('novelMargin', 20);
    return n >= 8 && n <= 48 ? n : 20;
  }

  static setNovelMargin(v: number): void {
    Settings.setNum('novelMargin', v);
  }

  // 小说正文字体：default | serif（宋体）| sans（黑体）| mono（等宽）
  static getNovelFontFamily(): string {
    const raw = Settings.getStr('novelFontFamily', 'default');
    if (raw === 'serif' || raw === 'sans' || raw === 'mono') {
      return raw;
    }
    return 'default';
  }

  static setNovelFontFamily(v: string): void {
    Settings.setStr('novelFontFamily', v);
  }

  // 小说段间距（vp）
  static getNovelParagraphSpacing(): number {
    const n = Settings.getNum('novelParagraphSpacing', 0);
    return n >= 0 && n <= 28 ? n : 0;
  }

  static setNovelParagraphSpacing(v: number): void {
    Settings.setNum('novelParagraphSpacing', v);
  }

  // 小说正文合并空行：段落间连续空行（含仅空白字符行）合并为单个换行
  static getNovelMergeBlankLines(): boolean {
    return Settings.getBool('novelMergeBlankLines', false);
  }

  static setNovelMergeBlankLines(v: boolean): void {
    Settings.setBool('novelMergeBlankLines', v);
  }

  // 小说段落首行缩进（全角空格数，0 = 不缩进）：无缩进正文自动补缩进
  static getNovelParagraphIndent(): number {
    const n = Settings.getNum('novelParagraphIndent', 0);
    return n >= 0 && n <= 4 ? n : 0;
  }

  static setNovelParagraphIndent(v: number): void {
    Settings.setNum('novelParagraphIndent', v);
  }

  // 小说阅读时屏幕常亮（默认开）
  static getNovelKeepScreenOn(): boolean {
    return Settings.getBool('novelKeepScreenOn', true);
  }

  static setNovelKeepScreenOn(v: boolean): void {
    Settings.setBool('novelKeepScreenOn', v);
  }

  // 音量键翻页（默认关；开=音量上/下代替翻页）
  static getNovelVolumeTurn(): boolean {
    return Settings.getBool('novelVolumeTurn', false);
  }

  static setNovelVolumeTurn(v: boolean): void {
    Settings.setBool('novelVolumeTurn', v);
  }

  // 正文两端对齐（默认开）
  static getNovelJustify(): boolean {
    return Settings.getBool('novelJustify', true);
  }

  static setNovelJustify(v: boolean): void {
    Settings.setBool('novelJustify', v);
  }

  // 自动阅读速度档位（1-10，默认 4：滚动=档位*8 vp/s，翻页=13-档位 秒/页）
  static getNovelAutoSpeed(): number {
    const n = Settings.getNum('novelAutoSpeed', 4);
    return n >= 1 && n <= 10 ? n : 4;
  }

  static setNovelAutoSpeed(v: number): void {
    Settings.setNum('novelAutoSpeed', v);
  }

  // 小说章内阅读位置书签（按漫画持久化为 JSON，模型见 common/NovelBookmarks）
  @NoBackupPrefix('novelBm_')
  static getNovelBookmarkJson(mangaId: number): string {
    return Settings.getStr(`novelBm_${mangaId}`, '[]');
  }

  static setNovelBookmarkJson(mangaId: number, v: string): void {
    Settings.setStr(`novelBm_${mangaId}`, v);
  }

  // 听书语速（0.5 - 2.0，默认 1.0）
  static getNovelTtsSpeed(): number {
    const n = Settings.getNum('novelTtsSpeed', 1);
    return n >= 0.5 && n <= 2 ? n : 1;
  }

  static setNovelTtsSpeed(v: number): void {
    Settings.setNum('novelTtsSpeed', v);
  }

  // 听书音色：default 女声（默认）| male 男声（需系统已下载，未下载回退女声）
  static getNovelTtsVoice(): string {
    const raw = Settings.getStr('novelTtsVoice', 'default');
    return raw === 'male' ? raw : 'default';
  }

  static setNovelTtsVoice(v: string): void {
    Settings.setStr('novelTtsVoice', v);
  }

  static getThemeMode(): string {
    return Settings.getStr('themeMode', 'auto');
  }

  static setThemeMode(mode: string): void {
    Settings.setStr('themeMode', mode);
  }

  // 密码与 OAuth token 一律走 SecureStore（Asset Store）加密存储，不落明文偏好
  static getTrackUsername(syncId: number): string {
    return Settings.getStr(`trackUsername_${syncId}`, '');
  }

  static setTrackUsername(syncId: number, v: string): void {
    Settings.setStr(`trackUsername_${syncId}`, v);
  }

  static getTrackDisplay(syncId: number): string {
    return Settings.getStr(`trackDisplay_${syncId}`, '');
  }

  static setTrackDisplay(syncId: number, v: string): void {
    Settings.setStr(`trackDisplay_${syncId}`, v);
  }

  // AniList 评分制：POINT_100 / POINT_10 / POINT_10_DECIMAL / POINT_5 / POINT_3
  static getAnilistScoreType(): string {
    return Settings.getStr('anilistScoreType', 'POINT_100');
  }

  static setAnilistScoreType(v: string): void {
    Settings.setStr('anilistScoreType', v);
  }

  // ---- 追踪（对齐 Mihon TrackPreferences）----
  // 仅存非敏感信息：trackUsername_{syncId} / trackDisplay_{syncId}

  // Kitsu 评分制：simple（表情）/ regular（星）/ advanced（10 分制小数）
  static getKitsuScoreType(): string {
    const raw: string = Settings.getStr('kitsuScoreType', 'simple');
    if (raw === 'regular' || raw === 'advanced') {
      return raw;
    }
    return 'simple';
  }

  static setKitsuScoreType(v: string): void {
    Settings.setStr('kitsuScoreType', v);
  }

  // 阅读完成后自动同步追踪进度
  static getTrackAutoUpdate(): boolean {
    return Settings.getBool('trackAutoUpdate', true);
  }

  static setTrackAutoUpdate(v: boolean): void {
    Settings.setBool('trackAutoUpdate', v);
  }

  @NoBackup('lastRefreshAt')
  static getLastRefreshAt(): number {
    return Settings.getNum('lastRefreshAt', 0);
  }

  static setLastRefreshAt(time: number): void {
    Settings.setNum('lastRefreshAt', time);
  }

  // ---- 插件仓库（多仓库管理）----

  // 多仓库列表（JSON 数组 [{url, name, website}]）；
  // 备份排除：与顶层 extensionRepos 区段双写冗余，恢复统一走 extensionRepos 路径
  @NoBackup('pluginStores')
  static getPluginStores(): PluginStoreRecord[] {
    const raw = Settings.getStr('pluginStores', '');
    if (raw !== '') {
      try {
        const parsed = JSON.parse(raw) as PluginStoreRecord[];
        if (Array.isArray(parsed)) {
          const out: PluginStoreRecord[] = [];
          for (const item of parsed) {
            if (item !== undefined && item !== null && typeof item.url === 'string' && item.url !== '') {
              out.push({
                url: item.url,
                name: typeof item.name === 'string' && item.name !== '' ? item.name : Settings.urlHostOf(item.url),
                website: typeof item.website === 'string' ? item.website : '',
              });
            }
          }
          return out;
        }
      } catch (_e) {
      }
    }
    return [];
  }

  static setPluginStores(list: PluginStoreRecord[]): void {
    Settings.setStr('pluginStores', JSON.stringify(list));
  }

  static hasPluginStore(url: string): boolean {
    for (const s of Settings.getPluginStores()) {
      if (s.url === url) {
        return true;
      }
    }
    return false;
  }

  static addPluginStore(record: PluginStoreRecord): void {
    const list = Settings.getPluginStores();
    for (const s of list) {
      if (s.url === record.url) {
        return;
      }
    }
    list.push(record);
    Settings.setPluginStores(list);
  }

  static removePluginStore(url: string): void {
    const list = Settings.getPluginStores();
    const next: PluginStoreRecord[] = [];
    for (const s of list) {
      if (s.url !== url) {
        next.push(s);
      }
    }
    Settings.setPluginStores(next);
  }

  // 仓库地址主机名（仓库展示名兜底；非 http(s) 返回原串）
  static urlHostOf(url: string): string {
    const m = new RegExp('^https?://([^/?#]+)').exec(url);
    return m !== null ? m[1] : url;
  }

  // ---- 受信任插件（对齐 Mihon trustedExtensions）----

  // 受信任插件记录（JSON string[]，元素 "key:versionCode:contentHash"）：
  // 插件激活（拉引擎执行插件代码）前必须命中记录；版本升级或内容变化后需重新确认信任。
  // 备份排除：导出信任状态等于在备份中静默授权执行任意插件代码，必须由用户在新设备重新确认
  @NoBackup('trustedPlugins')
  static getTrustedPlugins(): string[] {
    const raw = Settings.getStr('trustedPlugins', '[]');
    try {
      const parsed = JSON.parse(raw) as string[];
      if (Array.isArray(parsed)) {
        const out: string[] = [];
        for (const item of parsed) {
          if (typeof item === 'string' && item !== '') {
            out.push(item);
          }
        }
        return out;
      }
    } catch (_e) {
    }
    return [];
  }

  static setTrustedPlugins(list: string[]): void {
    Settings.setStr('trustedPlugins', JSON.stringify(list));
  }

  static isPluginTrusted(key: string, versionCode: number, contentHash: string): boolean {
    return Settings.getTrustedPlugins().indexOf(`${key}:${versionCode}:${contentHash}`) >= 0;
  }

  // 登记信任：移除同 key 旧版本记录后写入新记录（对齐 Mihon TrustExtension.trust）
  static trustPlugin(key: string, versionCode: number, contentHash: string): void {
    const prefix = `${key}:`;
    const kept: string[] = [];
    for (const item of Settings.getTrustedPlugins()) {
      if (!item.startsWith(prefix)) {
        kept.push(item);
      }
    }
    kept.push(`${key}:${versionCode}:${contentHash}`);
    Settings.setTrustedPlugins(kept);
  }

  // 移除单个插件的信任记录（卸载时调用；重装同版本也需重新确认信任）
  static revokePluginTrust(key: string): void {
    const prefix = `${key}:`;
    const kept: string[] = [];
    for (const item of Settings.getTrustedPlugins()) {
      if (!item.startsWith(prefix)) {
        kept.push(item);
      }
    }
    Settings.setTrustedPlugins(kept);
  }

  // 撤销全部插件信任记录（对齐 Mihon ext_revoke_trust）
  static revokeAllPluginTrust(): void {
    Settings.setTrustedPlugins([]);
  }

  // 自动备份频率（小时，0=关闭）
  static getBackupInterval(): number {
    return Settings.getNum('backupInterval', 0);
  }

  static setBackupInterval(v: number): void {
    Settings.setNum('backupInterval', v);
  }

  // 上次自动备份时间戳（毫秒）。备份排除：设备本地易变时间戳
  @NoBackup('lastAutoBackupTimestamp')
  static getLastAutoBackupTimestamp(): number {
    return Settings.getNum('lastAutoBackupTimestamp', 0);
  }

  static setLastAutoBackupTimestamp(v: number): void {
    Settings.setNum('lastAutoBackupTimestamp', v);
  }

  // 启动时清除章节缓存
  static getAutoClearChapterCache(): boolean {
    return Settings.getBool('autoClearChapterCache', false);
  }

  static setAutoClearChapterCache(v: boolean): void {
    Settings.setBool('autoClearChapterCache', v);
  }

  // ---- 数据与存储（对齐 Mihon BackupPreferences / LibraryPreferences）----

  // ---- 主题 ----
  static getAppThemeId(): string {
    const raw: string = Settings.getStr('appTheme', 'default');
    return Theme.isValidTheme(raw) ? raw : 'default';
  }

  static setAppThemeId(v: string): void {
    Settings.setStr('appTheme', v);
  }

  static getAmoledMode(): boolean {
    return Settings.getBool('amoledMode', false);
  }

  static setAmoledMode(v: boolean): void {
    Settings.setBool('amoledMode', v);
  }

  // ---- 全局标志 ----
  // 备份排除：仅下载为易变阅读状态（非持久偏好），新设备应回默认关闭
  @NoBackup('downloadedOnly')
  static getDownloadedOnly(): boolean {
    return Settings.getBool('downloadedOnly', false);
  }

  static setDownloadedOnly(v: boolean): void {
    Settings.setBool('downloadedOnly', v);
    AppStorage.setOrCreate(AppKeys.DOWNLOADED_ONLY, v);
  }

  static getIncognito(): boolean {
    return Settings.getBool('incognito', false);
  }

  static setIncognito(v: boolean): void {
    Settings.setBool('incognito', v);
    AppStorage.setOrCreate(AppKeys.INCOGNITO, v);
    // 隐私界面=「无痕模式时」档位需随无痕开关即时切换防截屏
    if (Settings.appCtx !== undefined) {
      Settings.applySecureScreen(Settings.appCtx);
    }
  }

  static getShowNsfw(): boolean {
    return Settings.getBool('showNsfw', false);
  }

  static setShowNsfw(v: boolean): void {
    Settings.setBool('showNsfw', v);
    AppStorage.setOrCreate(AppKeys.SHOW_NSFW, v);
  }

  static getDownloadWifiOnly(): boolean {
    return Settings.getBool('downloadWifiOnly', true);
  }

  static setDownloadWifiOnly(v: boolean): void {
    Settings.setBool('downloadWifiOnly', v);
  }

  // ---- BT / BitTorrent ----

  // BT 服务总开关：默认关闭，用户在 BT 设置页主动开启；关闭后立即停引擎
  // （TorrentManager.shutdown，worker 保留可再启），BT 下载请求被拒
  // （bt_service_disabled）；重新开启后按需启动
  static getBtServiceEnabled(): boolean {
    return Settings.getBool('btServiceEnabled', false);
  }

  static setBtServiceEnabled(v: boolean): void {
    Settings.setBool('btServiceEnabled', v);
  }

  // BT 下载引擎选择：'ask'（未决，每次询问）| 'module'（内置引擎）| 'system'（交给系统应用）
  static getBtEngineChoice(): string {
    const raw = Settings.getStr('btEngineChoice', 'ask');
    if (raw === 'module' || raw === 'system') {
      return raw;
    }
    return 'ask';
  }

  static setBtEngineChoice(v: string): void {
    Settings.setStr('btEngineChoice', v);
  }

  // BT 边下边播：视频任务按顺序下载，未完成即可开始播放
  static getBtProgressive(): boolean {
    return Settings.getBool('btProgressive', true);
  }

  static setBtProgressive(v: boolean): void {
    Settings.setBool('btProgressive', v);
  }

  // BT 会话级下载限速（KB/s，0 = 不限）
  static getBtDownloadLimitKb(): number {
    const n = Settings.getNum('btDownloadLimitKb', 0);
    return n >= 0 ? Math.floor(n) : 0;
  }

  static setBtDownloadLimitKb(v: number): void {
    Settings.setNum('btDownloadLimitKb', v);
  }

  // BT 会话级上传限速（KB/s，0 = 不限）
  static getBtUploadLimitKb(): number {
    const n = Settings.getNum('btUploadLimitKb', 0);
    return n >= 0 ? Math.floor(n) : 0;
  }

  static setBtUploadLimitKb(v: number): void {
    Settings.setNum('btUploadLimitKb', v);
  }

  // 额外 tracker 列表（多行文本，每行一个 URL，附加到每个新 BT 任务）
  static getBtExtraTrackers(): string {
    return Settings.getStr('btExtraTrackers', '');
  }

  static setBtExtraTrackers(v: string): void {
    Settings.setStr('btExtraTrackers', v);
  }

  // BT 分享率限制（上传/下载比值，达标后停止优先做种；1000 = 不限）
  static getBtShareRatioLimit(): number {
    const n = Settings.getNum('btShareRatioLimit', 2.0);
    return n >= 1.0 ? n : 2.0;
  }

  static setBtShareRatioLimit(v: number): void {
    Settings.setNum('btShareRatioLimit', v);
  }

  // 计费网络（蜂窝）限制上传为 10KB/s
  static getBtLimitUploadOnMetered(): boolean {
    return Settings.getBool('btLimitUploadOnMetered', true);
  }

  static setBtLimitUploadOnMetered(v: boolean): void {
    Settings.setBool('btLimitUploadOnMetered', v);
  }

  // BT Peer 过滤规则（多行文本，每行 "from-to" 区间或单个 IP，屏蔽连接）
  static getBtPeerFilter(): string {
    return Settings.getStr('btPeerFilter', '');
  }

  static setBtPeerFilter(v: string): void {
    Settings.setStr('btPeerFilter', v);
  }

  // ---- 下载设置（对齐 Mihon DownloadPreferences） ----

  // 章节保存为 CBZ 压缩包（阅读时解压到缓存目录；与原版默认 true 不同，
  // 鸿蒙端 zip 内页需解压读取，保守默认 false 由用户开启）
  static getSaveChaptersAsCbz(): boolean {
    return Settings.getBool('saveChaptersAsCbz', false);
  }

  static setSaveChaptersAsCbz(v: boolean): void {
    Settings.setBool('saveChaptersAsCbz', v);
  }

  // 下载时拆分超长条漫图片（提升阅读器渲染性能）
  static getSplitTallImages(): boolean {
    return Settings.getBool('splitTallImages', false);
  }

  static setSplitTallImages(v: boolean): void {
    Settings.setBool('splitTallImages', v);
  }

  // 同时下载的源数量上限（1-10）
  static getDownloadParallelSourceLimit(): number {
    const n = Settings.getNum('downloadParallelSourceLimit', 5);
    return n >= 1 && n <= 10 ? n : 5;
  }

  static setDownloadParallelSourceLimit(v: number): void {
    Settings.setNum('downloadParallelSourceLimit', v);
  }

  // 单章节内页面并发下载数（1-15）
  static getDownloadParallelPageLimit(): number {
    const n = Settings.getNum('downloadParallelPageLimit', 5);
    return n >= 1 && n <= 15 ? n : 5;
  }

  static setDownloadParallelPageLimit(v: number): void {
    Settings.setNum('downloadParallelPageLimit', v);
  }

  // 手动标记已读后删除下载
  static getRemoveAfterMarkedAsRead(): boolean {
    return Settings.getBool('removeAfterMarkedAsRead', false);
  }

  static setRemoveAfterMarkedAsRead(v: boolean): void {
    Settings.setBool('removeAfterMarkedAsRead', v);
  }

  // 阅读后自动删除第 N 个之前已读章节的下载（-1 禁用，1-5）
  static getRemoveAfterReadSlots(): number {
    const n = Settings.getNum('removeAfterReadSlots', -1);
    return n === -1 || (n >= 1 && n <= 5) ? n : -1;
  }

  static setRemoveAfterReadSlots(v: number): void {
    Settings.setNum('removeAfterReadSlots', v);
  }

  // 允许删除已书签章节的下载
  static getRemoveBookmarked(): boolean {
    return Settings.getBool('removeBookmarked', false);
  }

  static setRemoveBookmarked(v: boolean): void {
    Settings.setBool('removeBookmarked', v);
  }

  // 库更新发现新章节时自动下载
  static getDownloadNewChapters(): boolean {
    return Settings.getBool('downloadNewChapters', false);
  }

  static setDownloadNewChapters(v: boolean): void {
    Settings.setBool('downloadNewChapters', v);
  }

  // 自动下载时跳过与已读章节重复的新章节
  static getDownloadNewUnreadOnly(): boolean {
    return Settings.getBool('downloadNewUnreadOnly', false);
  }

  static setDownloadNewUnreadOnly(v: boolean): void {
    Settings.setBool('downloadNewUnreadOnly', v);
  }

  // 阅读时预下载后续未读章节数（0 禁用，1/2/3/5/10）
  static getAutoDownloadWhileReading(): number {
    const n = Settings.getNum('autoDownloadWhileReading', 0);
    return n === 1 || n === 2 || n === 3 || n === 5 || n === 10 ? n : 0;
  }

  static setAutoDownloadWhileReading(v: number): void {
    Settings.setNum('autoDownloadWhileReading', v);
  }

  static pushGlobalFlags(): void {
    AppStorage.setOrCreate(AppKeys.DOWNLOADED_ONLY, Settings.getDownloadedOnly());
    AppStorage.setOrCreate(AppKeys.INCOGNITO, Settings.getIncognito());
    AppStorage.setOrCreate(AppKeys.SHOW_NSFW, Settings.getShowNsfw());
  }

  // ---- 隐私（对齐 Mihon SecurityPreferences / PrivacyPreferences，遥测开关不适用）----

  // 应用锁：打开应用时要求系统解锁凭据（指纹/人脸/锁屏口令）认证
  static getAppLock(): boolean {
    return Settings.getBool('appLock', false);
  }

  static setAppLock(v: boolean): void {
    Settings.setBool('appLock', v);
  }

  // 空闲锁定（切后台时锁定）：0=切后台立即锁定；>0=超过 N 分钟锁定；-1=从不自动锁定
  static getLockAfterMinutes(): number {
    return Settings.getNum('lockAfterMinutes', 0);
  }

  static setLockAfterMinutes(v: number): void {
    Settings.setNum('lockAfterMinutes', v);
  }

  // 隐私界面（防截屏）：'always'（始终）| 'incognito'（无痕模式时）| 'never'（关闭）
  static getSecureScreen(): string {
    const raw = Settings.getStr('secureScreen', 'incognito');
    if (raw === 'always' || raw === 'never') {
      return raw;
    }
    return 'incognito';
  }

  static setSecureScreen(v: string): void {
    Settings.setStr('secureScreen', v);
  }

  // 隐藏通知内容：下载实况通知不显示作品/章节名
  static getHideNotificationContent(): boolean {
    return Settings.getBool('hideNotificationContent', false);
  }

  static setHideNotificationContent(v: boolean): void {
    Settings.setBool('hideNotificationContent', v);
  }

  // 上次切后台时间戳：进程存活期间内存判断 + 持久化兜底（进程被杀后重启判定空闲锁定）。
  // 备份排除：设备本地易变时间戳
  @NoBackup('lastAppClosedAt')
  static getLastAppClosedAt(): number {
    return Settings.getNum('lastAppClosedAt', 0);
  }

  static setLastAppClosedAt(v: number): void {
    Settings.setNum('lastAppClosedAt', v);
  }

  // 隐私界面生效态：按 secureScreen 设置与无痕模式计算
  static isSecureScreenActive(): boolean {
    const mode: string = Settings.getSecureScreen();
    if (mode === 'always') {
      return true;
    }
    if (mode === 'incognito') {
      return Settings.getIncognito();
    }
    return false;
  }

  // 将防截屏（窗口隐私模式）应用到当前主窗口；需 module.json5 声明 ohos.permission.PRIVACY_WINDOW
  static applySecureScreen(context: common.Context): void {
    if (!canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
      return;
    }
    const enable: boolean = Settings.isSecureScreenActive();
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowPrivacyMode(enable).catch((e: Object): void => {
        hilog.warn(DOMAIN, TAG, 'set privacy mode(%{public}s) failed: %{public}s', `${enable}`, `${e}`);
      });
    }).catch((_e: Object): void => {
    });
  }

  // ---- 高级（对齐 Mihon SettingsAdvancedScreen）----

  // 详细日志：Log.debug 门禁开关（关闭时 debug 级零输出）
  static getVerboseLogging(): boolean {
    return Settings.getBool('verboseLogging', false);
  }

  static setVerboseLogging(v: boolean): void {
    Settings.setBool('verboseLogging', v);
  }

  // 自定义 User-Agent（空串 = 默认 UA；Http/CF WebView 同步读取）
  static getUserAgent(): string {
    return Settings.getStr('userAgent', '');
  }

  static setUserAgent(v: string): void {
    Settings.setStr('userAgent', v);
  }

  // Bangumi API 镜像（高级设置）：存储原始输入，空串 = 未设置（默认 api.bgm.tv）
  static getBangumiApiBaseInput(): string {
    return Settings.getStr('bangumiApiBase', '').trim();
  }

  static setBangumiApiBase(v: string): void {
    Settings.setStr('bangumiApiBase', v.trim());
  }

  // 生效的 Bangumi API 基地址：自定义镜像强制 https:// 前缀（去尾部斜杠），
  // 未设置/非法回退默认 https://api.bgm.tv（国内网络可指向自建反代）
  static bangumiApiBase(): string {
    const raw: string = Settings.getBangumiApiBaseInput().replace(/\/+$/, '');
    if (/^https:\/\//.test(raw)) {
      return raw;
    }
    return 'https://api.bgm.tv';
  }

  // Bangumi 图片镜像（高级设置）：与 API 镜像成对（bgm 反代一般同时代理
  // api.bgm.tv 与 lain.bgm.tv）；存储原始输入，空串 = 未设置
  static getBangumiImgBaseInput(): string {
    return Settings.getStr('bangumiImgBase', '').trim();
  }

  static setBangumiImgBase(v: string): void {
    Settings.setStr('bangumiImgBase', v.trim());
  }

  // 生效的 Bangumi 图片基地址：强制 https:// 前缀，未设置/非法回退默认 https://lain.bgm.tv
  static bangumiImgBase(): string {
    const raw: string = Settings.getBangumiImgBaseInput().replace(/\/+$/, '');
    if (/^https:\/\//.test(raw)) {
      return raw;
    }
    return 'https://lain.bgm.tv';
  }

  // Bangumi next 镜像（高级设置）：吐槽箱/单集评论等新版接口源（next.bgm.tv），
  // 独立于 v0 API 镜像；存储原始输入，空串 = 未设置
  static getBangumiNextBaseInput(): string {
    return Settings.getStr('bangumiNextBase', '').trim();
  }

  static setBangumiNextBase(v: string): void {
    Settings.setStr('bangumiNextBase', v.trim());
  }

  // 生效的 next 基地址：强制 https:// 前缀，未设置/非法回退默认 https://next.bgm.tv
  static bangumiNextBase(): string {
    const raw: string = Settings.getBangumiNextBaseInput().replace(/\/+$/, '');
    if (/^https:\/\//.test(raw)) {
      return raw;
    }
    return 'https://next.bgm.tv';
  }

  // Bangumi 图片 URL 统一出口：协议相对（//lain.bgm.tv/...）补 https；
  // host 为 lain.bgm.tv 时替换为图片镜像基地址（路径原样保留），其余 URL 原样返回
  static rewriteBangumiImageUrl(url: string): string {
    if (url === '') {
      return '';
    }
    const normalized: string = url.indexOf('//') === 0 ? `https:${url}` : url;
    const schemeIdx: number = normalized.indexOf('://');
    if (schemeIdx < 0) {
      return normalized;
    }
    const rest: string = normalized.substring(schemeIdx + 3);
    const slashIdx: number = rest.indexOf('/');
    const host: string = slashIdx < 0 ? rest : rest.substring(0, slashIdx);
    if (host !== 'lain.bgm.tv') {
      return normalized;
    }
    const path: string = slashIdx < 0 ? '' : rest.substring(slashIdx);
    return Settings.bangumiImgBase() + path;
  }

  // DoH 供应商 id（空串 = 关闭；供应商清单见 net/Doh.ets）
  static getDohProvider(): string {
    return Settings.getStr('dohProvider', '');
  }

  static setDohProvider(v: string): void {
    Settings.setStr('dohProvider', v);
  }

  // 阅读器高质量渲染（图片插值）
  static getReaderHighQuality(): boolean {
    return Settings.getBool('readerHighQuality', false);
  }

  static setReaderHighQuality(v: boolean): void {
    Settings.setBool('readerHighQuality', v);
  }

  // 重置各作品阅读器标志（viewer_mode:* 偏好清空，恢复全局默认阅读模式）
  static resetViewerFlags(): number {
    if (Settings.store === undefined) {
      return 0;
    }
    let removed = 0;
    try {
      const all = Settings.store.getAllSync();
      const keys = Object.keys(all as Record<string, Object>);
      for (const key of keys) {
        if (key.indexOf('viewer_mode:') === 0) {
          Settings.store.deleteSync(key);
          removed++;
        }
      }
    } catch (_e) {
      return removed;
    }
    Settings.scheduleFlush();
    return removed;
  }

  // ---- 通用 ----
  static getStartTab(): number {
    return Settings.getNum('startTab', 0);
  }

  static setStartTab(v: number): void {
    Settings.setNum('startTab', v);
  }

  // ---- 新手引导（对齐 Mihon shownOnboarding）----
  // 备份排除：引导标记为设备本地一次性状态，新设备应重新展示引导
  @NoBackup('shownOnboarding')
  static getShownOnboarding(): boolean {
    return Settings.getBool('shownOnboarding', false);
  }

  static setShownOnboarding(v: boolean): void {
    Settings.setBool('shownOnboarding', v);
  }

  // 'auto' 跟随系统，否则为 BCP-47 语言标签（如 'zh-Hans' / 'en-US'）
  static getAppLanguage(): string {
    return Settings.getStr('appLanguage', 'auto');
  }

  static setAppLanguage(v: string): void {
    Settings.setStr('appLanguage', v);
  }

  // 应用语言偏好到系统（立即生效并持久化；'default' 跟随系统需冷启动生效）
  static applyAppLanguage(): void {
    const lang: string = Settings.getAppLanguage();
    AppStorage.setOrCreate(AppKeys.APP_LANGUAGE, lang);
    const tag: string = lang === 'auto' ? 'default' : lang;
    try {
      i18n.System.setAppPreferredLanguage(tag);
    } catch (_e) {
    }
  }

  // 排序键：'alpha','total','lastRead','lastUpdate','unread','latestChapter','fetchDate','dateAdded','rating','random'
  static getLibrarySort(): string {
    return Settings.getStr('librarySort', 'alpha');
  }

  static setLibrarySort(v: string): void {
    Settings.setStr('librarySort', v);
  }

  static getLibrarySortAsc(): boolean {
    return Settings.getBool('librarySortAsc', true);
  }

  // ---- 应用语言 ----

  static setLibrarySortAsc(v: boolean): void {
    Settings.setBool('librarySortAsc', v);
  }

  // 值为 'ignore'（忽略）| 'include'（包含）| 'exclude'（排除）。
  // 备份排除：书架筛选器当前状态为易变 UI 状态非偏好
  @NoBackupPrefix('libFilter:')
  static getLibraryTriState(key: string): string {
    return Settings.getStr('libFilter:' + key, 'ignore');
  }

  static setLibraryTriState(key: string, v: string): void {
    Settings.setStr('libFilter:' + key, v);
  }

  // ---- 书架 ----

  // 默认归入分类（对齐 Mihon LibraryPreferences.defaultCategory）：
  // 0 自动（默认：按内容类型落漫画/小说/动画）| -1 每次都询问 | >0 指定分类 id
  static getDefaultCategory(): number {
    return Settings.getNum('defaultCategory', 0);
  }

  static setDefaultCategory(v: number): void {
    Settings.setNum('defaultCategory', v);
  }

  // 三态：key 为 'downloaded','unread','started','bookmarked'
  static getUpdatesTriState(key: string): string {
    return Settings.getStr('updFilter:' + key, 'ignore');
  }

  static setUpdatesTriState(key: string, v: string): void {
    Settings.setStr('updFilter:' + key, v);
  }

  // 分类筛选（JSON 数组）：排除优先于包含
  static getUpdatesIncludedCategories(): number[] {
    return Settings.getNumList('updFilterCats:included');
  }

  static setUpdatesIncludedCategories(v: number[]): void {
    Settings.setStr('updFilterCats:included', JSON.stringify(v));
  }

  // 三态筛选：key 为 'downloaded','unread','started','bookmarked','completed','tracked'

  static getUpdatesExcludedCategories(): number[] {
    return Settings.getNumList('updFilterCats:excluded');
  }

  static setUpdatesExcludedCategories(v: number[]): void {
    Settings.setStr('updFilterCats:excluded', JSON.stringify(v));
  }

  // ---- 更新页筛选（对齐 Mihon UpdatesPreferences）----

  // ---- 即将推出页分类筛选（对齐 Mihon UpcomingPreferences）----
  static getUpcomingIncludedCategories(): number[] {
    return Settings.getNumList('upcomingCats:included');
  }

  static setUpcomingIncludedCategories(v: number[]): void {
    Settings.setStr('upcomingCats:included', JSON.stringify(v));
  }

  static getUpcomingExcludedCategories(): number[] {
    return Settings.getNumList('upcomingCats:excluded');
  }

  static setUpcomingExcludedCategories(v: number[]): void {
    Settings.setStr('upcomingCats:excluded', JSON.stringify(v));
  }

  // 显示模式：'compact','comfortable','cover','list'
  static getLibraryView(): string {
    return Settings.getStr('libraryView', 'compact');
  }

  static setLibraryView(v: string): void {
    Settings.setStr('libraryView', v);
  }

  // 源浏览页显示模式：'comfortable','compact','list'（对齐 Mihon pref_display_mode_catalogue）
  static getBrowseView(): string {
    return Settings.getStr('browseView', 'comfortable');
  }

  static setBrowseView(v: string): void {
    Settings.setStr('browseView', v);
  }

  // 每行数目：0 = 自动
  static getLibraryGridCols(): number {
    const v: number = Settings.getNum('libraryGridCols', 0);
    if (v < 0 || v > 10) {
      return 0;
    }
    return Math.floor(v);
  }

  static setLibraryGridCols(v: number): void {
    Settings.setNum('libraryGridCols', v);
  }

  static getShowUnreadBadge(): boolean {
    return Settings.getBool('showUnreadBadge', true);
  }

  static setShowUnreadBadge(v: boolean): void {
    Settings.setBool('showUnreadBadge', v);
  }

  static getShowDownloadBadge(): boolean {
    return Settings.getBool('showDownloadBadge', true);
  }

  static setShowDownloadBadge(v: boolean): void {
    Settings.setBool('showDownloadBadge', v);
  }

  static getShowLocalBadge(): boolean {
    return Settings.getBool('showLocalBadge', false);
  }

  static setShowLocalBadge(v: boolean): void {
    Settings.setBool('showLocalBadge', v);
  }

  static getShowLanguageBadge(): boolean {
    return Settings.getBool('showLanguageBadge', false);
  }

  static setShowLanguageBadge(v: boolean): void {
    Settings.setBool('showLanguageBadge', v);
  }

  static getShowCategoryTabs(): boolean {
    return Settings.getBool('showCategoryTabs', true);
  }

  static setShowCategoryTabs(v: boolean): void {
    Settings.setBool('showCategoryTabs', v);
  }

  static getShowMangaCount(): boolean {
    return Settings.getBool('showMangaCount', false);
  }

  static setShowMangaCount(v: boolean): void {
    Settings.setBool('showMangaCount', v);
  }

  // ---- 阅读器 ----
  static getReaderShowPageNumber(): boolean {
    return Settings.getBool('readerShowPageNumber', true);
  }

  static setReaderShowPageNumber(v: boolean): void {
    Settings.setBool('readerShowPageNumber', v);
  }

  static getReaderTheme(): number {
    return Settings.getNum('readerTheme', 3);
  }

  static setReaderTheme(v: number): void {
    Settings.setNum('readerTheme', v);
  }

  static getReaderBrightness(): number {
    const n: number = Settings.getNum('readerBrightness', 0);
    // 钳制到 [0,1]：越界值传给 setWindowBrightness 会静默失败，导致亮度调节永久失效
    return n >= 0 && n <= 1 ? n : 0;
  }

  static setReaderBrightness(v: number): void {
    Settings.setNum('readerBrightness', v);
  }

  static getReaderCrop(): boolean {
    return Settings.getBool('readerCrop', false);
  }

  static setReaderCrop(v: boolean): void {
    Settings.setBool('readerCrop', v);
  }

  static getReaderOrientation(): string {
    return Settings.getStr('readerOrientation', 'free');
  }

  static setReaderOrientation(v: string): void {
    Settings.setStr('readerOrientation', v);
  }

  // ---- 阅读器滤镜（灰度/反色为开关；亮度/对比度/饱和度有开关+百分比，100=原始） ----
  static getReaderGrayscale(): boolean {
    return Settings.getBool('readerGrayscale', false);
  }

  static setReaderGrayscale(v: boolean): void {
    Settings.setBool('readerGrayscale', v);
  }

  static getReaderInvert(): boolean {
    return Settings.getBool('readerInvert', false);
  }

  static setReaderInvert(v: boolean): void {
    Settings.setBool('readerInvert', v);
  }

  static getReaderBrightnessEnabled(): boolean {
    return Settings.getBool('readerBrightnessEnabled', false);
  }

  static setReaderBrightnessEnabled(v: boolean): void {
    Settings.setBool('readerBrightnessEnabled', v);
  }

  static getReaderFilterBrightness(): number {
    return Settings.getNum('readerFilterBrightness', 100);
  }

  static setReaderFilterBrightness(v: number): void {
    Settings.setNum('readerFilterBrightness', v);
  }

  static getReaderContrastEnabled(): boolean {
    return Settings.getBool('readerContrastEnabled', false);
  }

  static setReaderContrastEnabled(v: boolean): void {
    Settings.setBool('readerContrastEnabled', v);
  }

  static getReaderContrast(): number {
    return Settings.getNum('readerContrast', 100);
  }

  static setReaderContrast(v: number): void {
    Settings.setNum('readerContrast', v);
  }

  static getReaderSaturationEnabled(): boolean {
    return Settings.getBool('readerSaturationEnabled', false);
  }

  static setReaderSaturationEnabled(v: boolean): void {
    Settings.setBool('readerSaturationEnabled', v);
  }

  static getReaderSaturation(): number {
    return Settings.getNum('readerSaturation', 100);
  }

  static setReaderSaturation(v: number): void {
    Settings.setNum('readerSaturation', v);
  }

  // 漫画翻页动画（横向分页）：curl（仿真）| slide（滑动）| cover（覆盖）
  // | cube（3D 立方体）| stack（堆叠）| fade（淡入淡出）| flip（3D 翻转）| sphere（球面）
  // 垂直滚动与条漫不使用。3D 模式经组件 rotate/scale 过渡实现。
  static getReaderPageAnim(): string {
    const raw = Settings.getStr('readerPageAnim', 'slide');
    if (raw === 'curl' || raw === 'cover' || raw === 'cube' || raw === 'stack' ||
      raw === 'fade' || raw === 'flip' || raw === 'sphere') {
      return raw;
    }
    return 'slide';
  }

  static setReaderPageAnim(v: string): void {
    Settings.setStr('readerPageAnim', v);
  }

  // 点击翻页区域：'default','ltr','rtl','vertical','edge','none','lshape'（L 型）,'kindle'（Kindle 式）
  static getReaderNavMode(): string {
    const raw = Settings.getStr('readerNavMode', 'default');
    if (raw === 'ltr' || raw === 'rtl' || raw === 'vertical' || raw === 'edge' ||
      raw === 'none' || raw === 'lshape' || raw === 'kindle') {
      return raw;
    }
    return 'default';
  }

  static setReaderNavMode(v: string): void {
    Settings.setStr('readerNavMode', v);
  }

  // 条漫侧边距（百分比 0-25）
  static getReaderWebtoonPadding(): number {
    return Settings.getNum('readerWebtoonPadding', 0);
  }

  static setReaderWebtoonPadding(v: number): void {
    Settings.setNum('readerWebtoonPadding', v);
  }

  // 自动翻页间隔（秒，0=关闭；华为阅读对齐）
  static getReaderAutoPageSec(): number {
    return Settings.getNum('readerAutoPageSec', 0);
  }

  static setReaderAutoPageSec(v: number): void {
    Settings.setNum('readerAutoPageSec', v);
  }

  // 备份排除：按设备本地 manga id 拼键，跨设备 id 不一致无法映射
  @NoBackupPrefix('viewer_mode:')
  static getViewerMode(mangaId: string): string {
    return Settings.getStr('viewer_mode:' + mangaId, '');
  }

  static setViewerMode(mangaId: string, mode: string): void {
    Settings.setStr('viewer_mode:' + mangaId, mode);
  }

  static removeViewerMode(mangaId: string): void {
    if (Settings.store === undefined) {
      return;
    }
    try {
      Settings.store.deleteSync('viewer_mode:' + mangaId);
    } catch (_e) {
    }
    Settings.scheduleFlush();
  }

  // ---- 阅读体验 ----

  // 音量键翻页（漫画阅读器，默认关；开=音量上/下代替翻页）
  static getReaderVolumeTurn(): boolean {
    return Settings.getBool('readerVolumeTurn', false);
  }

  static setReaderVolumeTurn(v: boolean): void {
    Settings.setBool('readerVolumeTurn', v);
  }

  // 阅读时屏幕常亮（漫画阅读器，默认开）
  static getReaderKeepScreenOn(): boolean {
    return Settings.getBool('readerKeepScreenOn', true);
  }

  static setReaderKeepScreenOn(v: boolean): void {
    Settings.setBool('readerKeepScreenOn', v);
  }

  // 预加载后续页数（0-10，默认 4；分页模式 Swiper cachedCount）
  static getReaderPreloadPages(): number {
    const n = Settings.getNum('readerPreloadPages', 4);
    return n >= 0 && n <= 10 ? Math.floor(n) : 4;
  }

  static setReaderPreloadPages(v: number): void {
    Settings.setNum('readerPreloadPages', v);
  }

  // 双页模式：'auto'（横屏自动，默认）| 'force'（始终双页）| 'off'（始终单页）
  static getReaderDualPageMode(): string {
    const raw = Settings.getStr('readerDualPageMode', 'auto');
    if (raw === 'force' || raw === 'off') {
      return raw;
    }
    return 'auto';
  }

  static setReaderDualPageMode(v: string): void {
    Settings.setStr('readerDualPageMode', v);
  }

  // 双页时封面独立成页（默认开，对齐 Mihon dualPageSkip TbC）
  static getReaderDualPageCover(): boolean {
    return Settings.getBool('readerDualPageCover', true);
  }

  static setReaderDualPageCover(v: boolean): void {
    Settings.setBool('readerDualPageCover', v);
  }

  // 条漫/连续模式页间距（vp，0-40）
  static getReaderWebtoonGap(): number {
    const n = Settings.getNum('readerWebtoonGap', 0);
    return n >= 0 && n <= 40 ? n : 0;
  }

  static setReaderWebtoonGap(v: number): void {
    Settings.setNum('readerWebtoonGap', v);
  }

  // 显示页眉页脚（章节名/页码常驻边角，默认关）
  static getReaderShowHeaderFooter(): boolean {
    return Settings.getBool('readerShowHeaderFooter', false);
  }

  static setReaderShowHeaderFooter(v: boolean): void {
    Settings.setBool('readerShowHeaderFooter', v);
  }

  // ---- 页面处理 ----

  // 跳过重复页（相邻页文件大小+首尾采样哈希一致即跳过，仅本地页）
  static getReaderSkipDuplicatePages(): boolean {
    return Settings.getBool('readerSkipDuplicatePages', false);
  }

  static setReaderSkipDuplicatePages(v: boolean): void {
    Settings.setBool('readerSkipDuplicatePages', v);
  }

  // 清理空白页（解码缩略图判定纯色页并跳过，仅本地页）
  static getReaderCleanBlankPages(): boolean {
    return Settings.getBool('readerCleanBlankPages', false);
  }

  static setReaderCleanBlankPages(v: boolean): void {
    Settings.setBool('readerCleanBlankPages', v);
  }

  // ---- 阅读器导航/条漫 ----

  // 默认播放倍速（0.5 - 3.0）
  static getVideoSpeed(): number {
    const n = Settings.getNum('videoSpeed', 1.0);
    return n >= 0.5 && n <= 3.0 ? n : 1.0;
  }

  static setVideoSpeed(v: number): void {
    Settings.setNum('videoSpeed', v);
  }

  // 播完自动连播下一集
  static getVideoAutoNext(): boolean {
    return Settings.getBool('videoAutoNext', true);
  }

  static setVideoAutoNext(v: boolean): void {
    Settings.setBool('videoAutoNext', v);
  }

  // 画面显示模式（0=适应 1=填充 2=拉伸）
  static getVideoScaleMode(): number {
    const n = Settings.getNum('videoScaleMode', 0);
    return n >= 0 && n <= 2 ? Math.floor(n) : 0;
  }

  static setVideoScaleMode(v: number): void {
    Settings.setNum('videoScaleMode', v);
  }

  // 播放器软件音量（0.0-1.0，键盘 ↑↓ 步进调节，M 静音）。备份排除：播放器运行时状态
  @NoBackup('videoVolume')
  static getVideoVolume(): number {
    const n = Settings.getNum('videoVolume', 1.0);
    return n >= 0 && n <= 1 ? n : 1.0;
  }

  static setVideoVolume(v: number): void {
    Settings.setNum('videoVolume', v);
  }

  // 播放器亮度（0=跟随系统，(0,1]=固定亮度；左半屏上下滑手势调节）。备份排除：播放器运行时状态
  @NoBackup('videoBrightness')
  static getVideoBrightness(): number {
    const n = Settings.getNum('videoBrightness', 0);
    return n >= 0 && n <= 1 ? n : 0;
  }

  static setVideoBrightness(v: number): void {
    Settings.setNum('videoBrightness', v);
  }

  // ---- 弹幕 ----
  static getDanmakuEnabled(): boolean {
    return Settings.getBool('danmakuEnabled', true);
  }

  // ---- 视频播放器 ----

  static setDanmakuEnabled(v: boolean): void {
    Settings.setBool('danmakuEnabled', v);
  }

  // 弹幕字号（vp）
  static getDanmakuFont(): number {
    const n = Settings.getNum('danmakuFont', 16);
    return n >= 12 && n <= 28 ? n : 16;
  }

  static setDanmakuFont(v: number): void {
    Settings.setNum('danmakuFont', v);
  }

  // 弹幕不透明度（百分比 10 - 100）
  static getDanmakuOpacityPct(): number {
    const n = Settings.getNum('danmakuOpacity', 80);
    return n >= 10 && n <= 100 ? n : 80;
  }

  static setDanmakuOpacityPct(v: number): void {
    Settings.setNum('danmakuOpacity', v);
  }

  // 弹幕显示区域（占屏幕高度百分比：25/50/75/100）
  static getDanmakuAreaPct(): number {
    const n = Settings.getNum('danmakuArea', 50);
    return n === 25 || n === 75 || n === 100 ? n : 50;
  }

  static setDanmakuAreaPct(v: number): void {
    Settings.setNum('danmakuArea', v);
  }

  // 弹幕滚动时长（秒，越短越快：6/8/10/12）
  static getDanmakuDurationSec(): number {
    const n = Settings.getNum('danmakuDuration', 10);
    return n === 6 || n === 8 || n === 12 ? n : 10;
  }

  static setDanmakuDurationSec(v: number): void {
    Settings.setNum('danmakuDuration', v);
  }

  // 弹幕屏蔽过滤规则（正则字符串数组，命中任一即隐藏该条弹幕）
  static getDanmakuFilters(): string[] {
    const raw: string = Settings.getStr('danmakuFilters', '[]');
    try {
      const parsed: Object[] = JSON.parse(raw) as Object[];
      const out: string[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const item: Object | undefined = parsed[i];
        if (typeof item === 'string' && item !== '') {
          out.push(item);
        }
      }
      return out;
    } catch (_e) {
      return [];
    }
  }

  static setDanmakuFilters(v: string[]): void {
    Settings.setStr('danmakuFilters', JSON.stringify(v));
  }

  // ---- 视频跳过片头/片尾 ----

  // 自动跳过 OP/ED 全局开关
  static getVideoSkipOpEd(): boolean {
    return Settings.getBool('videoSkipOpEd', false);
  }

  static setVideoSkipOpEd(v: boolean): void {
    Settings.setBool('videoSkipOpEd', v);
  }

  // 按漫画存储跳过区间（秒，-1 未设置）：返回 [opS, opE, edS, edE]。
  // 备份排除：按设备本地 manga id 拼键，跨设备 id 不一致无法映射
  @NoBackupPrefix('videoSkipRange.')
  static getVideoSkipRanges(mangaId: number): number[] {
    const raw: string = Settings.getStr(`videoSkipRange.${mangaId}`, '');
    if (raw === '') {
      return [-1, -1, -1, -1];
    }
    const segs: string[] = raw.split(',');
    if (segs.length < 4) {
      return [-1, -1, -1, -1];
    }
    const out: number[] = [];
    for (let i = 0; i < 4; i++) {
      const n: number = parseInt(segs[i], 10);
      out.push(isFinite(n) ? n : -1);
    }
    return out;
  }

  static setVideoSkipRanges(mangaId: number, opS: number, opE: number, edS: number, edE: number): void {
    Settings.setStr(`videoSkipRange.${mangaId}`, `${opS},${opE},${edS},${edE}`);
  }

  static clearVideoSkipRanges(mangaId: number): void {
    Settings.setStr(`videoSkipRange.${mangaId}`, '');
  }

  // ---- 外挂字幕 ----

  // 字幕启用开关
  static getSubtitleEnabled(): boolean {
    return Settings.getBool('subtitleEnabled', true);
  }

  static setSubtitleEnabled(v: boolean): void {
    Settings.setBool('subtitleEnabled', v);
  }

  // 字幕字号（vp）
  static getSubtitleFont(): number {
    const n = Settings.getNum('subtitleFont', 18);
    return n >= 12 && n <= 28 ? n : 18;
  }

  static setSubtitleFont(v: number): void {
    Settings.setNum('subtitleFont', v);
  }

  // ---- 本地源文件夹（Mihon local source：固定一个用户文件夹，同步进沙箱扫描）----
  // 备份排除：设备级 URI 授权跨设备无效，需在新设备重新选取授权
  @NoBackup('localFolderUri')
  static getLocalFolderUri(): string {
    return Settings.getStr('localFolderUri', '');
  }

  static setLocalFolderUri(v: string): void {
    Settings.setStr('localFolderUri', v);
  }

  // 备份排除：与 localFolderUri 配套的设备本地显示名
  @NoBackup('localFolderName')
  static getLocalFolderName(): string {
    return Settings.getStr('localFolderName', '');
  }

  static setLocalFolderName(v: string): void {
    Settings.setStr('localFolderName', v);
  }

  // 备份排除：设备本地易变时间戳
  @NoBackup('lastLocalSyncAt')
  static getLastLocalSyncAt(): number {
    return Settings.getNum('lastLocalSyncAt', 0);
  }

  static setLastLocalSyncAt(v: number): void {
    Settings.setNum('lastLocalSyncAt', v);
  }

  // ---- 源 ----
  static getPinnedSources(): string {
    return Settings.getStr('pinnedSources', '[]');
  }

  static setPinnedSources(v: string): void {
    Settings.setStr('pinnedSources', v);
  }

  // 全局搜索“只显示有结果的源”开关（对齐 Mihon globalSearchFilterState 偏好）
  static getGlobalSearchFilterResults(): boolean {
    return Settings.getBool('globalSearchFilterResults', false);
  }

  static setGlobalSearchFilterResults(v: boolean): void {
    Settings.setBool('globalSearchFilterResults', v);
  }

  // ---- 浏览：最近使用的源（图源 Tab 顶部“最近使用”分组）----
  // 备份排除：最近源浏览痕迹为易变状态，跨设备无意义
  @NoBackup('recentSources')
  static getRecentSources(): string {
    return Settings.getStr('recentSources', '[]');
  }

  static setRecentSources(v: string): void {
    Settings.setStr('recentSources', v);
  }

  // 记录一次源使用：key 前移去重，最多保留 5 个；
  // 递增 AppStorage 版本号，图源 Tab 在栈底未卸载时经 @Watch 重载分组
  static touchRecentSource(key: string): void {
    if (key === '') {
      return;
    }
    let keys: string[] = [];
    try {
      const parsed = JSON.parse(Settings.getRecentSources()) as string[];
      if (Array.isArray(parsed)) {
        keys = parsed;
      }
    } catch (_e) {
      keys = [];
    }
    const next: string[] = [key];
    for (const k of keys) {
      if (k !== key && next.length < 5) {
        next.push(k);
      }
    }
    Settings.setRecentSources(JSON.stringify(next));
    AppStorage.setOrCreate(AppKeys.RECENT_SOURCES_VER,
      (AppStorage.get<number>(AppKeys.RECENT_SOURCES_VER) ?? 0) + 1);
  }

  // 根据设置与系统颜色模式计算是否深色，并写入 AppStorage 与 palette
  static applyTheme(systemDark: boolean): void {
    const mode: string = Settings.getThemeMode();
    const dark: boolean = mode === 'dark' || (mode === 'auto' && systemDark);
    AppStorage.setOrCreate(AppKeys.IS_DARK, dark);
    AppStorage.setOrCreate(AppKeys.APP_THEME, Settings.getAppThemeId());
    AppStorage.setOrCreate(AppKeys.AMOLED, Settings.getAmoledMode());
    Settings.pushPalette();
  }

  // 主题/AMOLED 变更：更新 AppStorage、重建色板并同步系统栏
  static applyAppTheme(context: common.Context): void {
    AppStorage.setOrCreate(AppKeys.APP_THEME, Settings.getAppThemeId());
    AppStorage.setOrCreate(AppKeys.AMOLED, Settings.getAmoledMode());
    Settings.pushPalette();
    Settings.applySystemBar(context);
  }

  // 重建色板并写入 AppStorage 'palette'（组件经 @StorageProp 绑定）
  static pushPalette(): void {
    const dark: boolean = AppStorage.get<boolean>(AppKeys.IS_DARK) ?? false;
    AppStorage.setOrCreate(AppKeys.PALETTE,
      Theme.buildPalette(Settings.getAppThemeId(), dark, Settings.getAmoledMode()));
  }

  // 应用颜色模式到系统（资源/系统组件随此切换；auto = 跟随系统）
  static applyColorMode(context: common.Context): void {
    const mode: string = Settings.getThemeMode();
    if (mode === 'dark') {
      try {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } catch (e) {
        throw new Error(`set color mode failed: ${e}`);
      }
    } else if (mode === 'light') {
      try {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } catch (e) {
        throw new Error(`set color mode failed: ${e}`);
      }
    } else {
      try {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      } catch (e) {
        throw new Error(`set color mode failed: ${e}`);
      }
    }
    Settings.applySystemBar(context);
  }

  // 系统栏：透明背景（沉浸式，光感效果由系统渲染），内容色取自当前 palette 的文本色
  static applySystemBar(context: common.Context): void {
    window.getLastWindow(context).then((win: window.Window) => {
      const dark: boolean = AppStorage.get<boolean>(AppKeys.IS_DARK) ?? false;
      const pal: ThemePalette = AppStorage.get<ThemePalette>(AppKeys.PALETTE) ?? new ThemePalette();
      const content: string = pal.text;
      if (canIUse('SystemCapability.WindowManager.WindowManager.Core')) {
        win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          statusBarContentColor: content,
          isStatusBarLightIcon: dark,
          navigationBarColor: '#00000000',
          navigationBarContentColor: content,
          isNavigationBarLightIcon: dark
        }).catch((_e: Error) => {
        });
      }
    }).catch((_e: Error) => {
    });
  }

  static initAvoidAreas(context: common.Context): void {
    window.getLastWindow(context).then((win: window.Window) => {
      const ui: UIContext = win.getUIContext();
      const sync = (): void => {
        const sb: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const nb: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        AppStorage.setOrCreate(AppKeys.STATUS_BAR_H, ui.px2vp(sb.topRect.height));
        AppStorage.setOrCreate(AppKeys.NAV_BAR_H, ui.px2vp(nb.bottomRect.height));
      };
      sync();
      // 动态订阅避让区变化：折叠/旋转后高度随之更新，避免只取一次快照导致避让区过期
      if (!Settings.avoidSubscribed) {
        try {
          win.on('avoidAreaChange', (_data: window.AvoidAreaOptions): void => {
            sync();
          });
          Settings.avoidSubscribed = true;
        } catch (_e) {
        }
      }
    }).catch((_e: Error) => {
    });
  }

  // ---- 翻译 ----

  // 翻译功能总开关（阅读器内文本翻译）
  static getTransEnabled(): boolean {
    return Settings.getBool('transEnabled', false);
  }

  static setTransEnabled(v: boolean): void {
    Settings.setBool('transEnabled', v);
  }

  // 翻译引擎优先级顺序（CSV，id 见 TranslationService.ENGINE_IDS）
  static getTransEngineOrder(): string {
    return Settings.getStr('transEngineOrder',
      'baidu,caiyun,youdao,tencent,volcano,niutrans,deepl,microsoft,google');
  }

  static setTransEngineOrder(v: string): void {
    Settings.setStr('transEngineOrder', v);
  }

  // 翻译目标语言（应用内语言码，候选见 TransLangs.TARGETS）
  static getTransTargetLang(): string {
    return Settings.getStr('transTargetLang', 'zh');
  }

  static setTransTargetLang(v: string): void {
    Settings.setStr('transTargetLang', v);
  }

  // ---- Mihon 对齐增补 ----

  // 章末行为：自动进入下一章时跳过已读章节
  static getReaderSkipRead(): boolean {
    return Settings.getBool('readerSkipRead', false);
  }

  static setReaderSkipRead(v: boolean): void {
    Settings.setBool('readerSkipRead', v);
  }

  // 章末行为：跳过被详情页筛选隐藏的章节
  static getReaderSkipFiltered(): boolean {
    return Settings.getBool('readerSkipFiltered', false);
  }

  static setReaderSkipFiltered(v: boolean): void {
    Settings.setBool('readerSkipFiltered', v);
  }

  // 章末行为：跳过重复章节（同章节号已读过其它版本）
  static getReaderSkipDuplicate(): boolean {
    return Settings.getBool('readerSkipDuplicate', false);
  }

  static setReaderSkipDuplicate(v: boolean): void {
    Settings.setBool('readerSkipDuplicate', v);
  }

  // 章节转换页：章与章之间显示转换信息页（关闭则直接进入下一章）
  static getReaderShowChapterTransition(): boolean {
    return Settings.getBool('readerShowChapterTransition', true);
  }

  static setReaderShowChapterTransition(v: boolean): void {
    Settings.setBool('readerShowChapterTransition', v);
  }

  // 书库条目滑动操作：开始侧动作
  // 值：'none'（禁用）| 'read'（切换已读）| 'bookmark'（切换书签）| 'download'（下载未读章节）
  static getLibrarySwipeStartAction(): string {
    const raw = Settings.getStr('librarySwipeStartAction', 'read');
    if (raw === 'none' || raw === 'bookmark' || raw === 'download') {
      return raw;
    }
    return 'read';
  }

  static setLibrarySwipeStartAction(v: string): void {
    Settings.setStr('librarySwipeStartAction', v);
  }

  // 书库条目滑动操作：结束侧动作（默认禁用）
  static getLibrarySwipeEndAction(): string {
    const raw = Settings.getStr('librarySwipeEndAction', 'none');
    if (raw === 'read' || raw === 'bookmark' || raw === 'download') {
      return raw;
    }
    return 'none';
  }

  static setLibrarySwipeEndAction(v: string): void {
    Settings.setStr('librarySwipeEndAction', v);
  }

  // NSFW 插件门禁：开启 NSFW 显示 / 进入 NSFW 插件详情时需生物识别确认
  static getNsfwBiometricConfirm(): boolean {
    return Settings.getBool('nsfwBiometricConfirm', true);
  }

  static setNsfwBiometricConfirm(v: boolean): void {
    Settings.setBool('nsfwBiometricConfirm', v);
  }

  // 按插件隐身：指定插件浏览时默认隐身模式（对齐 Mihon incognitoExtensions）
  static getIncognitoPlugins(): string[] {
    const raw = Settings.getStr('incognitoPlugins', '[]');
    try {
      const parsed = JSON.parse(raw) as string[];
      if (Array.isArray(parsed)) {
        const out: string[] = [];
        for (const item of parsed) {
          if (typeof item === 'string' && item !== '') {
            out.push(item);
          }
        }
        return out;
      }
    } catch (_e) {
    }
    return [];
  }

  static setIncognitoPlugins(list: string[]): void {
    Settings.setStr('incognitoPlugins', JSON.stringify(list));
  }

  static isPluginIncognito(key: string): boolean {
    return Settings.getIncognitoPlugins().indexOf(key) >= 0;
  }

  // 快速判断：是否存在任何「按插件隐身」配置（无痕闸门短路用，避免每次 JSON 解析）
  static hasIncognitoPlugins(): boolean {
    return Settings.getStr('incognitoPlugins', '[]') !== '[]';
  }

  // 扩展更新检查：刷新仓库索引时比对已装插件版本并提醒更新
  static getExtensionUpdateCheck(): boolean {
    return Settings.getBool('extensionUpdateCheck', true);
  }

  static setExtensionUpdateCheck(v: boolean): void {
    Settings.setBool('extensionUpdateCheck', v);
  }

  // 上次扩展更新提醒时间戳（同批更新只提醒一次）。备份排除：设备本地易变时间戳
  @NoBackup('lastExtUpdateNotifiedAt')
  static getLastExtUpdateNotifiedAt(): number {
    return Settings.getNum('lastExtUpdateNotifiedAt', 0);
  }

  static setLastExtUpdateNotifiedAt(v: number): void {
    Settings.setNum('lastExtUpdateNotifiedAt', v);
  }

  // 库全局更新限制（对齐 Mihon updateRestrictions）：仅 Wi-Fi / 仅充电
  static getLibraryUpdateWifiOnly(): boolean {
    return Settings.getBool('libraryUpdateWifiOnly', false);
  }

  static setLibraryUpdateWifiOnly(v: boolean): void {
    Settings.setBool('libraryUpdateWifiOnly', v);
  }

  static getLibraryUpdateChargingOnly(): boolean {
    return Settings.getBool('libraryUpdateChargingOnly', false);
  }

  static setLibraryUpdateChargingOnly(v: boolean): void {
    Settings.setBool('libraryUpdateChargingOnly', v);
  }

  // 阅读器裁切边框（分页模式 / 条漫模式分别设置）
  static getReaderCropBordersPaged(): boolean {
    return Settings.getBool('readerCropBordersPaged', false);
  }

  static setReaderCropBordersPaged(v: boolean): void {
    Settings.setBool('readerCropBordersPaged', v);
  }

  static getReaderCropBordersWebtoon(): boolean {
    return Settings.getBool('readerCropBordersWebtoon', false);
  }

  static setReaderCropBordersWebtoon(v: boolean): void {
    Settings.setBool('readerCropBordersWebtoon', v);
  }

  // 色彩滤镜混合模式：'none' | 'multiply' | 'screen' | 'overlay' | 'darken' | 'lighten'
  static getReaderColorFilterBlend(): string {
    const raw = Settings.getStr('readerColorFilterBlend', 'none');
    if (raw === 'multiply' || raw === 'screen' || raw === 'overlay' || raw === 'darken' || raw === 'lighten') {
      return raw;
    }
    return 'none';
  }

  static setReaderColorFilterBlend(v: string): void {
    Settings.setStr('readerColorFilterBlend', v);
  }

  // 条漫禁止缩小（保持页面宽度不低于适配宽度）
  static getReaderWebtoonDisableZoomOut(): boolean {
    return Settings.getBool('readerWebtoonDisableZoomOut', false);
  }

  static setReaderWebtoonDisableZoomOut(v: boolean): void {
    Settings.setBool('readerWebtoonDisableZoomOut', v);
  }

  // 缩放起始位置：'automatic' | 'left' | 'right' | 'center'
  static getReaderZoomStart(): string {
    const raw = Settings.getStr('readerZoomStart', 'automatic');
    if (raw === 'left' || raw === 'right' || raw === 'center') {
      return raw;
    }
    return 'automatic';
  }

  static setReaderZoomStart(v: string): void {
    Settings.setStr('readerZoomStart', v);
  }

  // 防残影闪屏：翻页时黑/白闪屏冲刷残影（对齐 Mihon flashPagePrefetch）
  static getReaderFlashEnabled(): boolean {
    return Settings.getBool('readerFlashEnabled', false);
  }

  static setReaderFlashEnabled(v: boolean): void {
    Settings.setBool('readerFlashEnabled', v);
  }

  // 闪屏颜色：'white' | 'black' | 'both'（黑白交替）
  static getReaderFlashColor(): string {
    const raw = Settings.getStr('readerFlashColor', 'white');
    if (raw === 'black' || raw === 'both') {
      return raw;
    }
    return 'white';
  }

  static setReaderFlashColor(v: string): void {
    Settings.setStr('readerFlashColor', v);
  }

  // 闪屏时长（毫秒，40-500）
  static getReaderFlashDurationMs(): number {
    const n = Settings.getNum('readerFlashDurationMs', 100);
    return n >= 40 && n <= 500 ? n : 100;
  }

  static setReaderFlashDurationMs(v: number): void {
    Settings.setNum('readerFlashDurationMs', v);
  }

  // 闪屏间隔（每翻 N 页闪一次，1-10）
  static getReaderFlashEveryPages(): number {
    const n = Settings.getNum('readerFlashEveryPages', 1);
    return n >= 1 && n <= 10 ? Math.floor(n) : 1;
  }

  static setReaderFlashEveryPages(v: number): void {
    Settings.setNum('readerFlashEveryPages', v);
  }

  // 百度翻译开放平台凭据（appid + 密钥）。敏感凭据：仅进备份加密 secure 段
  @Sensitive('transBaiduAppid')
  static getTransBaiduAppid(): string {
    return Settings.getStr('transBaiduAppid', '');
  }

  static setTransBaiduAppid(v: string): void {
    Settings.setStr('transBaiduAppid', v);
  }

  @Sensitive('transBaiduKey')
  static getTransBaiduKey(): string {
    return Settings.getStr('transBaiduKey', '');
  }

  static setTransBaiduKey(v: string): void {
    Settings.setStr('transBaiduKey', v);
  }

  // 有道智云凭据（应用ID + 应用密钥）
  @Sensitive('transYoudaoKey')
  static getTransYoudaoKey(): string {
    return Settings.getStr('transYoudaoKey', '');
  }

  static setTransYoudaoKey(v: string): void {
    Settings.setStr('transYoudaoKey', v);
  }

  @Sensitive('transYoudaoSecret')
  static getTransYoudaoSecret(): string {
    return Settings.getStr('transYoudaoSecret', '');
  }

  static setTransYoudaoSecret(v: string): void {
    Settings.setStr('transYoudaoSecret', v);
  }

  // 彩云小译令牌
  @Sensitive('transCaiyunToken')
  static getTransCaiyunToken(): string {
    return Settings.getStr('transCaiyunToken', '');
  }

  static setTransCaiyunToken(v: string): void {
    Settings.setStr('transCaiyunToken', v);
  }

  // 腾讯云机器翻译凭据（SecretId + SecretKey）
  @Sensitive('transTencentSecretId')
  static getTransTencentSecretId(): string {
    return Settings.getStr('transTencentSecretId', '');
  }

  static setTransTencentSecretId(v: string): void {
    Settings.setStr('transTencentSecretId', v);
  }

  @Sensitive('transTencentSecretKey')
  static getTransTencentSecretKey(): string {
    return Settings.getStr('transTencentSecretKey', '');
  }

  static setTransTencentSecretKey(v: string): void {
    Settings.setStr('transTencentSecretKey', v);
  }

  // 火山引擎机器翻译凭据（AccessKeyID + SecretAccessKey）
  @Sensitive('transVolcanoAccessKey')
  static getTransVolcanoAccessKey(): string {
    return Settings.getStr('transVolcanoAccessKey', '');
  }

  static setTransVolcanoAccessKey(v: string): void {
    Settings.setStr('transVolcanoAccessKey', v);
  }

  @Sensitive('transVolcanoSecretKey')
  static getTransVolcanoSecretKey(): string {
    return Settings.getStr('transVolcanoSecretKey', '');
  }

  static setTransVolcanoSecretKey(v: string): void {
    Settings.setStr('transVolcanoSecretKey', v);
  }

  // 小牛翻译 API 密钥
  @Sensitive('transNiutransApikey')
  static getTransNiutransApikey(): string {
    return Settings.getStr('transNiutransApikey', '');
  }

  static setTransNiutransApikey(v: string): void {
    Settings.setStr('transNiutransApikey', v);
  }

  // ---- 备份导出/导入（设置批量迁移，配合 BackupService v3 完整备份）----

  // 明文设置导出：过滤敏感/易变/设备本地键，仅保留可 JSON 序列化的原始类型值。
  // 备份策略（敏感/排除）由各设置访问器上的 @Sensitive/@NoBackup/@NoBackupPrefix 装饰器
  // 声明并登记进 BackupPolicyRegistry；装饰器未生效时 fail-closed 拒绝导出，
  // 宁可备份缺设置段，也不导出插件信任状态或敏感键明文。
  static exportAll(): Record<string, Object> {
    const out: Record<string, Object> = {};
    if (Settings.store === undefined) {
      return out;
    }
    if (!BackupPolicyRegistry.decoratorsApplied()) {
      hilog.error(0x0000, TAG, 'backup policy decorators missing, refuse settings export');
      return out;
    }
    try {
      const all: Record<string, Object> = Settings.store.getAllSync() as Record<string, Object>;
      const keys = Object.keys(all);
      for (const key of keys) {
        if (BackupPolicyRegistry.isSensitive(key) || BackupPolicyRegistry.isExcluded(key)) {
          continue;
        }
        const v: Object | undefined = all[key];
        if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') {
          out[key] = v;
        }
      }
    } catch (_e) {
    }
    return out;
  }

  // 明文设置导入：合并覆盖（不删除本地多余键）；敏感/排除键拒绝（敏感键仅经 secure 段恢复）。
  // 装饰器未生效时 fail-closed 拒绝导入，防止伪造备份经 settings 段注入 trustedPlugins 等排除键
  static importAll(map: Record<string, Object>): void {
    if (Settings.store === undefined) {
      return;
    }
    if (!BackupPolicyRegistry.decoratorsApplied()) {
      hilog.error(0x0000, TAG, 'backup policy decorators missing, refuse settings import');
      return;
    }
    const keys = Object.keys(map);
    for (const key of keys) {
      if (BackupPolicyRegistry.isSensitive(key) || BackupPolicyRegistry.isExcluded(key)) {
        continue;
      }
      const v: Object | undefined = map[key];
      if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') {
        try {
          Settings.store.putSync(key, v);
        } catch (_e) {
        }
      }
    }
    Settings.scheduleFlush();
  }

  // 敏感设置导出（进 secure 加密段）：仅收录装饰器登记的非空值
  static exportSensitive(): Record<string, string> {
    const out: Record<string, string> = {};
    for (const key of BackupPolicyRegistry.sensitiveKeyList()) {
      const v: string = Settings.getStr(key, '');
      if (v !== '') {
        out[key] = v;
      }
    }
    return out;
  }

  // 敏感设置导入（secure 段解密后调用）：仅接受装饰器登记的键
  static importSensitive(map: Record<string, string>): void {
    const keys = Object.keys(map);
    for (const key of keys) {
      if (!BackupPolicyRegistry.isSensitive(key)) {
        continue;
      }
      const v: Object | undefined = map[key];
      if (typeof v === 'string') {
        Settings.setStr(key, v);
      }
    }
  }

  // 取值后 typeof 校验：跨版本类型变更时回退默认值，避免静默返回错误类型
  private static getStr(key: string, def: string): string {
    if (Settings.store === undefined) {
      return def;
    }
    try {
      const v = Settings.store.getSync(key, def);
      return typeof v === 'string' ? v as string : def;
    } catch (e) {
      return def;
    }
  }

  // ---- 主题应用 ----

  // 写入保持 putSync（读己之写）+ 500ms 防抖批量 flush（高频写场景消除 I/O 放大）
  private static setStr(key: string, value: string): void {
    if (Settings.store === undefined) {
      return;
    }
    try {
      Settings.store.putSync(key, value);
    } catch (_e) {
    }
    Settings.scheduleFlush();
  }

  private static getBool(key: string, def: boolean): boolean {
    if (Settings.store === undefined) {
      return def;
    }
    try {
      const v = Settings.store.getSync(key, def);
      return typeof v === 'boolean' ? v as boolean : def;
    } catch (e) {
      return def;
    }
  }

  private static setBool(key: string, value: boolean): void {
    if (Settings.store === undefined) {
      return;
    }
    try {
      Settings.store.putSync(key, value);
    } catch (_e) {
    }
    Settings.scheduleFlush();
  }

  private static getNum(key: string, def: number): number {
    if (Settings.store === undefined) {
      return def;
    }
    try {
      const v = Settings.store.getSync(key, def);
      return typeof v === 'number' ? v as number : def;
    } catch (e) {
      return def;
    }
  }

  private static setNum(key: string, value: number): void {
    if (Settings.store === undefined) {
      return;
    }
    try {
      Settings.store.putSync(key, value);
    } catch (_e) {
    }
    Settings.scheduleFlush();
  }

  // 防抖批量落盘：500ms 内的连续写只触发一次 flush
  private static scheduleFlush(): void {
    if (Settings.flushTimer !== -1) {
      clearTimeout(Settings.flushTimer);
    }
    Settings.flushTimer = setTimeout((): void => {
      Settings.flushTimer = -1;
      if (Settings.store !== undefined) {
        // flush() 返回 Promise：必须挂 catch，否则异步落盘失败成为未处理 rejection
        Settings.store.flush().catch((e: Object): void => {
          hilog.warn(DOMAIN, TAG, 'debounced settings flush failed: %{public}s', `${e}`);
        });
      }
    }, 500);
  }

  // JSON 数字数组读取（异常/类型不符时回退空数组）
  private static getNumList(key: string): number[] {
    const raw: string = Settings.getStr(key, '[]');
    const result: number[] = [];
    try {
      const parsed = JSON.parse(raw) as number[];
      for (const n of parsed) {
        if (typeof n === 'number') {
          result.push(n);
        }
      }
    } catch (e) {
      // 解析失败按空处理
    }
    return result;
  }
}
